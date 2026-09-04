#if DEBUG
import Foundation
import Security

/// 内存版钥匙串：按 service + account 存明文。不碰系统 Keychain。
actor FakeKeychain: KeychainStoring {
    var journal = FakeJournal()
    private var storage: [KeychainService: [UUID: String]] = [:]

    func save(_ secret: String, service: KeychainService, account: UUID) throws {
        try journal.record("save")
        var bucket = storage[service] ?? [:]
        bucket[account] = secret
        storage[service] = bucket
    }

    func read(service: KeychainService, account: UUID) throws -> String {
        try journal.record("read")
        guard let value = storage[service]?[account] else {
            throw ApiRelayError.keychainFailure(errSecItemNotFound)
        }
        return value
    }

    func delete(service: KeychainService, account: UUID) throws {
        try journal.record("delete")
        storage[service]?[account] = nil
    }

    func listAccounts(service: KeychainService) throws -> [UUID] {
        try journal.record("listAccounts")
        return Array((storage[service] ?? [:]).keys)
    }
}
#endif
