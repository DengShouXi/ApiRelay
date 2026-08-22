import Foundation
import Security

/// KeychainStoring 的 actor 实现。
/// 四类 Service（keys / admin / masterpw / backuppw），各配不同的 accessible 与 synchronizable 策略。
///
/// **MUST NOT 设置 `kSecAttrAccessControl`**——它与 `kSecAttrSynchronizable` 互斥（errSecParam）。
/// 门闩统一在应用层实现（research §1）。
///
/// - Parameters:
///   - accessGroup: 生产环境传入 `$(AppIdentifierPrefix)group.com.apirelay.shared` 展开后的值。
///     传 `nil` 时省略 `kSecAttrAccessGroup`，系统落到 entitlement 里的第一个组——
///     本工程只有一个组，所以 `nil` 与显式传值指向同一份条目，**不构成测试隔离**。
///   - servicePrefix: 测试隔离靠它，见 `testServicePrefix`。
actor KeychainStore: KeychainStoring {

    /// 主密码条目的固定 account（singleton）。
    static let masterPasswordAccount = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!
    /// 备份口令条目的固定 account（singleton）。明文仅用于加密备份文件。
    static let backupPassphraseAccount = UUID(uuidString: "00000000-0000-4000-8000-000000000002")!

    /// 生产 Service 名前缀。
    static let productionServicePrefix = "com.apirelay.keychain"
    /// 单元测试专用 Service 名前缀，MUST 与 `productionServicePrefix` 不同。
    ///
    /// 测试 bundle 由 `ApiRelay.app` 宿主加载，进程带的是 App 的 entitlements，而
    /// `keychain-access-groups` 里只有一个组——省略 `kSecAttrAccessGroup` 时系统就落到该组。
    /// 因此 `accessGroup: nil` 并不构成隔离：测试 setUp 里的 `MasterPasswordService.reset()`
    /// 与 `eraseAllUserData()` 的枚举删除，会直接命中用户在本机真实存下的主密码与密钥明文。
    /// 隔离只能靠换 Service 名。
    static let testServicePrefix = "com.apirelay.keychain.tests"

    private let accessGroup: String?
    /// 单元测试宿主常缺 iCloud Keychain entitlement；为 true 时全部 Service 不写 synchronizable。
    private let disableSynchronizableForTesting: Bool
    private let servicePrefix: String

    init(
        accessGroup: String? = nil,
        disableSynchronizableForTesting: Bool = false,
        servicePrefix: String = KeychainStore.productionServicePrefix
    ) {
        self.accessGroup = accessGroup
        self.disableSynchronizableForTesting = disableSynchronizableForTesting
        self.servicePrefix = servicePrefix
    }

    // MARK: - Service 配置

    private func serviceName(for service: KeychainService) -> String {
        switch service {
        case .keys:     return "\(servicePrefix).keys"
        case .admin:    return "\(servicePrefix).admin"
        case .masterpw: return "\(servicePrefix).masterpw"
        case .backuppw: return "\(servicePrefix).backuppw"
        }
    }

    private func accessibleAttribute(for service: KeychainService) -> CFString {
        switch service {
        case .keys:     return kSecAttrAccessibleWhenUnlocked
        case .admin:    return kSecAttrAccessibleAfterFirstUnlock
        case .masterpw, .backuppw: return kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        }
    }

    private func isSynchronizable(for service: KeychainService) -> Bool {
        if disableSynchronizableForTesting { return false }
        switch service {
        case .keys, .admin: return true
        case .masterpw, .backuppw: return false
        }
    }

    private func applyAccessGroup(to query: inout [String: Any]) {
        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
    }

    // MARK: - KeychainStoring

    func save(_ secret: String, service: KeychainService, account: UUID) throws {
        try? delete(service: service, account: account)

        guard let data = secret.data(using: .utf8) else {
            throw ApiRelayError.keychainFailure(errSecParam)
        }

        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName(for: service),
            kSecAttrAccount as String: account.uuidString,
            kSecValueData as String: data,
            kSecAttrAccessible as String: accessibleAttribute(for: service),
            kSecAttrSynchronizable as String: isSynchronizable(for: service),
        ]
        applyAccessGroup(to: &query)

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw ApiRelayError.keychainFailure(status)
        }
    }

    func read(service: KeychainService, account: UUID) throws -> String {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName(for: service),
            kSecAttrAccount as String: account.uuidString,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
        ]
        applyAccessGroup(to: &query)

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else {
            throw ApiRelayError.keychainFailure(status)
        }
        guard let data = result as? Data,
              let secret = String(data: data, encoding: .utf8) else {
            throw ApiRelayError.keychainFailure(errSecDecode)
        }
        return secret
    }

    func delete(service: KeychainService, account: UUID) throws {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName(for: service),
            kSecAttrAccount as String: account.uuidString,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
        ]
        applyAccessGroup(to: &query)

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw ApiRelayError.keychainFailure(status)
        }
    }

    func listAccounts(service: KeychainService) throws -> [UUID] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName(for: service),
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
        ]
        applyAccessGroup(to: &query)

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return []
        }
        guard status == errSecSuccess else {
            throw ApiRelayError.keychainFailure(status)
        }
        guard let items = result as? [[String: Any]] else {
            return []
        }

        return items.compactMap { item in
            guard let account = item[kSecAttrAccount as String] as? String else { return nil }
            return UUID(uuidString: account)
        }
    }
}
