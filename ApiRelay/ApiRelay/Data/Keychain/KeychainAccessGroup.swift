import Foundation
import Security

/// 解析 entitlements 中的 `$(AppIdentifierPrefix)group.com.apirelay.shared`。
enum KeychainAccessGroup {
    static let groupSuffix = "group.com.apirelay.shared"

    /// 生产环境 access group；解析失败时返回 nil（系统回退到 App 默认组）。
    static var resolved: String? {
        if let prefix = bundleSeedID(), !prefix.isEmpty {
            return prefix.hasSuffix(".") ? "\(prefix)\(groupSuffix)" : "\(prefix).\(groupSuffix)"
        }
        return nil
    }

    /// 通过向 Keychain 写入探测项读取 App Identifier Prefix（Team ID.）。
    private static func bundleSeedID() -> String? {
        let service = "com.apirelay.keychain.seed-probe"
        let account = "seed"
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnAttributes as String: true,
        ]
        var result: AnyObject?
        var status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            let add: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecValueData as String: Data([0]),
            ]
            status = SecItemAdd(add as CFDictionary, nil)
            guard status == errSecSuccess || status == errSecDuplicateItem else { return nil }
            status = SecItemCopyMatching(query as CFDictionary, &result)
        }
        guard status == errSecSuccess,
              let attrs = result as? [String: Any],
              let accessGroup = attrs[kSecAttrAccessGroup as String] as? String else {
            return nil
        }
        // accessGroup 形如 "TEAMID.com.apirelay.ApiRelay" 或 "TEAMID.group..."
        // 取第一个点号前的 TeamID 作为 prefix。
        if let dot = accessGroup.firstIndex(of: ".") {
            return String(accessGroup[..<dot])
        }
        return nil
    }
}
