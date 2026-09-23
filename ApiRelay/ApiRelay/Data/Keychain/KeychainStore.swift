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

    /// macOS 同时存在 legacy file-based Keychain 与 Data Protection Keychain。
    /// 其他平台（含 Mac Catalyst）只有应用应使用的现代 Keychain 语义。
    private enum Backend {
        case primary
        case legacyMac
    }

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
    /// 隔离只能靠换 Service 名。进程后缀进一步隔开同机并行的 native macOS 与
    /// Catalyst runner，避免一边的 reset / erase-all 删除另一边正在验证的材料。
    static let testServicePrefix =
        "com.apirelay.keychain.tests.\(ProcessInfo.processInfo.processIdentifier)"

    private let accessGroup: String?
    /// 单元测试宿主常缺 iCloud Keychain entitlement；为 true 时全部 Service 不写 synchronizable。
    private let disableSynchronizableForTesting: Bool
    private let servicePrefix: String

    init(
        accessGroup: String? = nil,
        disableSynchronizableForTesting: Bool = false,
        servicePrefix: String = KeychainStore.productionServicePrefix,
        allowProductionNamespaceInTests: Bool = false
    ) {
        if AppRuntime.isRunningTests,
           servicePrefix == KeychainStore.productionServicePrefix,
           !allowProductionNamespaceInTests {
            preconditionFailure(
                "KeychainStore: 测试禁止使用生产 servicePrefix。请用 KeychainStore.makeForTests()；仅只读回归用例可传 allowProductionNamespaceInTests: true。"
            )
        }
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

    /// native macOS 必须显式选择 Data Protection Keychain；否则非同步条目会落入
    /// legacy file-based Keychain，`kSecAttrAccessible` / access group 的预期保护不成立。
    private func applyBackend(_ backend: Backend, to query: inout [String: Any]) {
        #if os(macOS) && !targetEnvironment(macCatalyst)
        // 显式 false 同样重要：带 `kSecAttrSynchronizableAny` 的宽查询若省略此键，
        // 某些 macOS 版本会跨到 DP 域，导致 legacy 清理误删刚迁移的新条目。
        query[kSecUseDataProtectionKeychain as String] = backend == .primary
        #endif
    }

    /// 只有历史上实际为本机非同步保存的两类口令才需要查询 legacy Keychain。
    /// keys/admin 在生产配置中是同步条目，不扩大 fallback，避免误读同名旧条目。
    private func supportsLegacyMacMigration(_ service: KeychainService) -> Bool {
        #if os(macOS) && !targetEnvironment(macCatalyst)
        switch service {
        case .masterpw, .backuppw:
            return true
        case .keys, .admin:
            return false
        }
        #else
        return false
        #endif
    }

    private func matchQuery(
        service: KeychainService,
        account: UUID,
        backend: Backend,
        synchronizable: Any
    ) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName(for: service),
            kSecAttrAccount as String: account.uuidString,
            kSecAttrSynchronizable as String: synchronizable,
        ]
        applyAccessGroup(to: &query)
        applyBackend(backend, to: &query)
        return query
    }

    private func upsert(
        _ data: Data,
        service: KeychainService,
        account: UUID,
        backend: Backend
    ) throws {
        let synchronizable = isSynchronizable(for: service)
        let match = matchQuery(
            service: service,
            account: account,
            backend: backend,
            synchronizable: synchronizable
        )
        let updates: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: accessibleAttribute(for: service),
        ]
        let updateStatus = SecItemUpdate(match as CFDictionary, updates as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw ApiRelayError.keychainFailure(updateStatus)
        }

        // 仅在确认不存在时新增；禁止“先删后加”，否则新增失败会把旧值及其云端副本一起删掉。
        var add = match
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = accessibleAttribute(for: service)
        let addStatus = SecItemAdd(add as CFDictionary, nil)
        if addStatus == errSecDuplicateItem {
            // 查询与新增之间若刚好收到另一设备的同名条目，重新走原子更新。
            let retryStatus = SecItemUpdate(match as CFDictionary, updates as CFDictionary)
            guard retryStatus == errSecSuccess else {
                throw ApiRelayError.keychainFailure(retryStatus)
            }
            return
        }
        guard addStatus == errSecSuccess else {
            throw ApiRelayError.keychainFailure(addStatus)
        }
    }

    private func addIfAbsent(
        _ data: Data,
        service: KeychainService,
        account: UUID,
        backend: Backend,
        transactionTag: UUID? = nil
    ) -> OSStatus {
        var add = matchQuery(
            service: service,
            account: account,
            backend: backend,
            synchronizable: isSynchronizable(for: service)
        )
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = accessibleAttribute(for: service)
        if let transactionTag {
            add[kSecAttrGeneric as String] = Self.transactionTagData(transactionTag)
        }
        return SecItemAdd(add as CFDictionary, nil)
    }

    private nonisolated static func transactionTagData(_ tag: UUID) -> Data {
        Data("ARX1:\(tag.uuidString.lowercased())".utf8)
    }

    private func copyData(
        service: KeychainService,
        account: UUID,
        backend: Backend
    ) throws -> Data {
        var query = matchQuery(
            service: service,
            account: account,
            backend: backend,
            synchronizable: kSecAttrSynchronizableAny
        )
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else {
            throw ApiRelayError.keychainFailure(status)
        }
        guard let data = result as? Data else {
            throw ApiRelayError.keychainFailure(errSecDecode)
        }
        return data
    }

    @discardableResult
    private func deleteItem(
        service: KeychainService,
        account: UUID,
        backend: Backend
    ) -> OSStatus {
        let query = matchQuery(
            service: service,
            account: account,
            backend: backend,
            synchronizable: kSecAttrSynchronizableAny
        )
        return SecItemDelete(query as CFDictionary)
    }

    private func listAccountUUIDs(
        service: KeychainService,
        backend: Backend
    ) throws -> [UUID] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName(for: service),
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
        ]
        applyAccessGroup(to: &query)
        applyBackend(backend, to: &query)

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

    /// legacy -> DP 迁移必须“只新增、不覆盖”：如果并发流程已写入 DP，DP 永远胜出，
    /// 绝不能用旧 legacy 值覆盖新口令。只有读回值与 legacy 完全一致时才删除 legacy。
    /// 迁移失败时返回 legacy 数据，保证老用户不会因升级被锁死。
    private func preferredDataAfterLegacyMigration(
        _ legacyData: Data,
        service: KeychainService,
        account: UUID
    ) -> Data {
        do {
            let addStatus = addIfAbsent(
                legacyData,
                service: service,
                account: account,
                backend: .primary
            )
            guard addStatus == errSecSuccess || addStatus == errSecDuplicateItem else {
                return legacyData
            }

            let primaryData = try copyData(service: service, account: account, backend: .primary)
            if primaryData == legacyData {
                let deleteStatus = deleteItem(service: service, account: account, backend: .legacyMac)
                guard deleteStatus == errSecSuccess || deleteStatus == errSecItemNotFound else {
                    return primaryData
                }
            }
            return primaryData
        } catch {
            return legacyData
        }
    }

    /// 显式保存新值后清理同名 legacy 副本。读回完全一致是删除旧值的硬前提；
    /// 清理失败不把一次已经成功的安全保存伪装成失败，后续读取仍以 DP 为准。
    private func removeLegacyAfterVerifiedPrimarySave(
        expectedData: Data,
        service: KeychainService,
        account: UUID
    ) {
        guard supportsLegacyMacMigration(service) else { return }
        do {
            let primaryData = try copyData(service: service, account: account, backend: .primary)
            guard primaryData == expectedData else { return }
            _ = deleteItem(service: service, account: account, backend: .legacyMac)
        } catch {
            // DP 保存已经成功；保留 legacy 比误删或让调用方误以为新值未生效更安全。
        }
    }

    // MARK: - KeychainStoring

    func save(_ secret: String, service: KeychainService, account: UUID) throws {
        guard let data = secret.data(using: .utf8) else {
            throw ApiRelayError.keychainFailure(errSecParam)
        }

        try upsert(data, service: service, account: account, backend: .primary)
        removeLegacyAfterVerifiedPrimarySave(
            expectedData: data,
            service: service,
            account: account
        )
    }

    func insertIfAbsent(
        _ secret: String,
        service: KeychainService,
        account: UUID
    ) throws -> Bool {
        guard let data = secret.data(using: .utf8) else {
            throw ApiRelayError.keychainFailure(errSecParam)
        }
        let status = addIfAbsent(
            data,
            service: service,
            account: account,
            backend: .primary
        )
        if status == errSecDuplicateItem { return false }
        guard status == errSecSuccess else {
            throw ApiRelayError.keychainFailure(status)
        }
        removeLegacyAfterVerifiedPrimarySave(
            expectedData: data,
            service: service,
            account: account
        )
        return true
    }

    func insertIfAbsent(
        _ secret: String,
        service: KeychainService,
        account: UUID,
        transactionTag: UUID
    ) throws -> Bool {
        guard let data = secret.data(using: .utf8) else {
            throw ApiRelayError.keychainFailure(errSecParam)
        }
        let status = addIfAbsent(
            data,
            service: service,
            account: account,
            backend: .primary,
            transactionTag: transactionTag
        )
        if status == errSecDuplicateItem { return false }
        guard status == errSecSuccess else {
            throw ApiRelayError.keychainFailure(status)
        }
        removeLegacyAfterVerifiedPrimarySave(
            expectedData: data,
            service: service,
            account: account
        )
        return true
    }

    func deleteIfTransactionTagMatches(
        service: KeychainService,
        account: UUID,
        transactionTag: UUID
    ) throws -> Bool {
        var query = matchQuery(
            service: service,
            account: account,
            backend: .primary,
            synchronizable: kSecAttrSynchronizableAny
        )
        query[kSecAttrGeneric as String] = Self.transactionTagData(transactionTag)
        let status = SecItemDelete(query as CFDictionary)
        if status == errSecItemNotFound { return false }
        guard status == errSecSuccess else {
            throw ApiRelayError.keychainFailure(status)
        }
        return true
    }

    func finalizeTransactionTagIfMatches(
        service: KeychainService,
        account: UUID,
        transactionTag: UUID
    ) throws {
        var query = matchQuery(
            service: service,
            account: account,
            backend: .primary,
            synchronizable: kSecAttrSynchronizableAny
        )
        query[kSecAttrGeneric as String] = Self.transactionTagData(transactionTag)
        let updates: [String: Any] = [kSecAttrGeneric as String: Data()]
        let status = SecItemUpdate(query as CFDictionary, updates as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw ApiRelayError.keychainFailure(status)
        }
    }

    func read(service: KeychainService, account: UUID) throws -> String {
        let data: Data
        do {
            data = try copyData(service: service, account: account, backend: .primary)
        } catch let ApiRelayError.keychainFailure(status)
            where status == errSecItemNotFound && supportsLegacyMacMigration(service) {
            let legacyData = try copyData(service: service, account: account, backend: .legacyMac)
            data = preferredDataAfterLegacyMigration(
                legacyData,
                service: service,
                account: account
            )
        }
        guard let secret = String(data: data, encoding: .utf8) else {
            throw ApiRelayError.keychainFailure(errSecDecode)
        }
        return secret
    }

    func delete(service: KeychainService, account: UUID) throws {
        let primaryStatus = deleteItem(service: service, account: account, backend: .primary)
        var firstFailure: OSStatus?
        if primaryStatus != errSecSuccess && primaryStatus != errSecItemNotFound {
            firstFailure = primaryStatus
        }

        // 即使 DP 删除异常，也继续尝试 legacy，确保“删除全部数据”不会只清一半。
        if supportsLegacyMacMigration(service) {
            let legacyStatus = deleteItem(service: service, account: account, backend: .legacyMac)
            if legacyStatus != errSecSuccess,
               legacyStatus != errSecItemNotFound,
               firstFailure == nil {
                firstFailure = legacyStatus
            }
        }

        if let firstFailure {
            throw ApiRelayError.keychainFailure(firstFailure)
        }
    }

    func listAccounts(service: KeychainService) throws -> [UUID] {
        let primaryAccounts = try listAccountUUIDs(service: service, backend: .primary)
        guard supportsLegacyMacMigration(service) else {
            return primaryAccounts
        }

        let legacyAccounts = try listAccountUUIDs(service: service, backend: .legacyMac)
        var seen = Set(primaryAccounts)
        var merged = primaryAccounts
        for account in legacyAccounts {
            do {
                let legacyData = try copyData(service: service, account: account, backend: .legacyMac)
                _ = preferredDataAfterLegacyMigration(
                    legacyData,
                    service: service,
                    account: account
                )
                if seen.insert(account).inserted {
                    merged.append(account)
                }
            } catch let ApiRelayError.keychainFailure(status) where status == errSecItemNotFound {
                // 并发删除：列表快照中的条目已经不存在，无需失败。
            }
        }
        return merged
    }
}
