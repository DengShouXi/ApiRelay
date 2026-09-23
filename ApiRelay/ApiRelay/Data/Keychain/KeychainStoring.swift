import Foundation
import Security

/// Final synchronous authorization seam around one concrete Keychain mutation.
/// The closure must not suspend while `operation` is running.
typealias KeychainCommit = @Sendable (_ operation: () throws -> Void) throws -> Void

/// Keychain 存储协议。实现 MUST 为 actor，不得依赖 SwiftUI。
/// - MUST NOT 设置 `kSecAttrAccessControl`——它与 `kSecAttrSynchronizable` 互斥（errSecParam）。
/// - `masterpw` 与 `backuppw` MUST 使用 `WhenUnlockedThisDeviceOnly` 且不同步。
///
/// 继承 `Actor`（而非仅 `Sendable`），以便在
/// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` 下与具体 actor 实现的隔离域一致。
protocol KeychainStoring: Actor {
    /// 保存密钥明文到 Keychain。
    func save(_ secret: String, service: KeychainService, account: UUID) throws

    /// Atomically inserts without replacing a same-service/account item.
    /// Returns false when another local/remote writer already owns the item.
    func insertIfAbsent(
        _ secret: String,
        service: KeychainService,
        account: UUID
    ) throws -> Bool

    /// Atomically inserts the value and a non-secret transaction ownership tag
    /// in the same Keychain item. The tag closes the crash window between
    /// `SecItemAdd` and a second journal write.
    func insertIfAbsent(
        _ secret: String,
        service: KeychainService,
        account: UUID,
        transactionTag: UUID
    ) throws -> Bool

    /// Atomically deletes only an item whose ownership tag matches. A
    /// pre-existing or concurrently replaced item is never removed.
    func deleteIfTransactionTagMatches(
        service: KeychainService,
        account: UUID,
        transactionTag: UUID
    ) throws -> Bool

    /// Roll-forward finalization after the durable commit decision. Removes the
    /// provisional tag without changing the secret. Missing/already-finalized
    /// items are idempotent no-ops.
    func finalizeTransactionTagIfMatches(
        service: KeychainService,
        account: UUID,
        transactionTag: UUID
    ) throws

    /// 从 Keychain 读取密钥明文。
    func read(service: KeychainService, account: UUID) throws -> String

    /// 从 Keychain 删除密钥明文。
    func delete(service: KeychainService, account: UUID) throws

    /// 列出指定 Service 下的全部 account UUID（供孤儿巡检）。
    func listAccounts(service: KeychainService) throws -> [UUID]
}

nonisolated private final class KeychainInsertResultBox: @unchecked Sendable {
    var value = false
}

extension KeychainStoring {
    /// Actor-serialized fallback for test doubles. The production KeychainStore
    /// overrides this with one SecItemAdd so iCloud arrival races stay atomic.
    func insertIfAbsent(
        _ secret: String,
        service: KeychainService,
        account: UUID
    ) throws -> Bool {
        do {
            _ = try read(service: service, account: account)
            return false
        } catch let ApiRelayError.keychainFailure(status) where status == errSecItemNotFound {
            try save(secret, service: service, account: account)
            return true
        }
    }

    /// Safe compatibility fallback for isolated test doubles. Production and
    /// `FakeKeychain` override this with real tag storage.
    func insertIfAbsent(
        _ secret: String,
        service: KeychainService,
        account: UUID,
        transactionTag: UUID
    ) throws -> Bool {
        try insertIfAbsent(secret, service: service, account: account)
    }

    func deleteIfTransactionTagMatches(
        service: KeychainService,
        account: UUID,
        transactionTag: UUID
    ) throws -> Bool {
        // Without tag support it is safer to preserve an orphan than to delete
        // a value whose ownership cannot be proven.
        false
    }

    func finalizeTransactionTagIfMatches(
        service: KeychainService,
        account: UUID,
        transactionTag: UUID
    ) throws {}

    /// Runs authorization and the concrete actor-isolated write without an
    /// intervening actor hop. A page lease can therefore linearize invalidation
    /// against the actual Keychain mutation rather than merely its preparation.
    func save(
        _ secret: String,
        service: KeychainService,
        account: UUID,
        committing: KeychainCommit
    ) throws {
        try committing {
            try save(secret, service: service, account: account)
        }
    }

    func delete(
        service: KeychainService,
        account: UUID,
        committing: KeychainCommit
    ) throws {
        try committing {
            try delete(service: service, account: account)
        }
    }

    func insertIfAbsent(
        _ secret: String,
        service: KeychainService,
        account: UUID,
        committing: KeychainCommit
    ) throws -> Bool {
        let result = KeychainInsertResultBox()
        try committing {
            result.value = try insertIfAbsent(
                secret,
                service: service,
                account: account
            )
        }
        return result.value
    }

    func insertIfAbsent(
        _ secret: String,
        service: KeychainService,
        account: UUID,
        transactionTag: UUID,
        committing: KeychainCommit
    ) throws -> Bool {
        let result = KeychainInsertResultBox()
        try committing {
            result.value = try insertIfAbsent(
                secret,
                service: service,
                account: account,
                transactionTag: transactionTag
            )
        }
        return result.value
    }
}
