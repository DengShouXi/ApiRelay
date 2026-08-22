import Foundation

/// Keychain 存储协议。实现 MUST 为 actor，不得依赖 SwiftUI。
/// - MUST NOT 设置 `kSecAttrAccessControl`——它与 `kSecAttrSynchronizable` 互斥（errSecParam）。
/// - `masterpw` 与 `backuppw` MUST 使用 `WhenUnlockedThisDeviceOnly` 且不同步。
///
/// 继承 `Actor`（而非仅 `Sendable`），以便在
/// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` 下与具体 actor 实现的隔离域一致。
protocol KeychainStoring: Actor {
    /// 保存密钥明文到 Keychain。
    func save(_ secret: String, service: KeychainService, account: UUID) throws

    /// 从 Keychain 读取密钥明文。
    func read(service: KeychainService, account: UUID) throws -> String

    /// 从 Keychain 删除密钥明文。
    func delete(service: KeychainService, account: UUID) throws

    /// 列出指定 Service 下的全部 account UUID（供孤儿巡检）。
    func listAccounts(service: KeychainService) throws -> [UUID]
}
