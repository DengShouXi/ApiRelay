#if DEBUG
import Foundation
import Security

nonisolated private final class FakeKeychainCallControl: @unchecked Sendable {
    private let lock = NSLock()
    private var armedBlocks: [String: Int] = [:]
    private var activeBlocks: [String: [DispatchSemaphore]] = [:]
    private var blockWaiters: [String: [CheckedContinuation<Void, Never>]] = [:]
    private var nextFailures: [String: [ApiRelayError]] = [:]

    func blockNext(_ method: String) {
        lock.lock()
        armedBlocks[method, default: 0] += 1
        lock.unlock()
    }

    func failNext(_ method: String, with error: ApiRelayError) {
        lock.lock()
        nextFailures[method, default: []].append(error)
        lock.unlock()
    }

    func intercept(_ method: String) throws {
        lock.lock()
        if var failures = nextFailures[method], !failures.isEmpty {
            let error = failures.removeFirst()
            nextFailures[method] = failures.isEmpty ? nil : failures
            lock.unlock()
            throw error
        }
        guard let armed = armedBlocks[method], armed > 0 else {
            lock.unlock()
            return
        }
        armedBlocks[method] = armed == 1 ? nil : armed - 1
        let semaphore = DispatchSemaphore(value: 0)
        activeBlocks[method, default: []].append(semaphore)
        let waiters = blockWaiters.removeValue(forKey: method) ?? []
        lock.unlock()
        waiters.forEach { $0.resume() }
        semaphore.wait()
    }

    func waitUntilBlocked(_ method: String) async {
        await withCheckedContinuation { continuation in
            lock.lock()
            if activeBlocks[method]?.isEmpty == false {
                lock.unlock()
                continuation.resume()
            } else {
                blockWaiters[method, default: []].append(continuation)
                lock.unlock()
            }
        }
    }

    func releaseBlocked(_ method: String) {
        lock.lock()
        guard var blocks = activeBlocks[method], !blocks.isEmpty else {
            lock.unlock()
            return
        }
        let semaphore = blocks.removeFirst()
        activeBlocks[method] = blocks.isEmpty ? nil : blocks
        lock.unlock()
        semaphore.signal()
    }
}

/// 内存版钥匙串：按 service + account 存明文。不碰系统 Keychain。
actor FakeKeychain: KeychainStoring {
    var journal = FakeJournal()
    private var storage: [KeychainService: [UUID: String]] = [:]
    private var transactionTags: [KeychainService: [UUID: UUID]] = [:]
    nonisolated private let callControl = FakeKeychainCallControl()

    nonisolated func blockNextCall(_ method: String) {
        callControl.blockNext(method)
    }

    nonisolated func failNextCall(_ method: String, with error: ApiRelayError) {
        callControl.failNext(method, with: error)
    }

    nonisolated func waitUntilCallIsBlocked(_ method: String) async {
        await callControl.waitUntilBlocked(method)
    }

    nonisolated func releaseBlockedCall(_ method: String) {
        callControl.releaseBlocked(method)
    }

    func fail(_ method: String, with error: ApiRelayError) {
        journal.fail(method, with: error)
    }

    func clearFailure(_ method: String) {
        journal.clearFailure(method)
    }

    func save(_ secret: String, service: KeychainService, account: UUID) throws {
        try journal.record("save")
        try callControl.intercept("save")
        var bucket = storage[service] ?? [:]
        bucket[account] = secret
        storage[service] = bucket
    }

    func read(service: KeychainService, account: UUID) throws -> String {
        try journal.record("read")
        try callControl.intercept("read")
        guard let value = storage[service]?[account] else {
            throw ApiRelayError.keychainFailure(errSecItemNotFound)
        }
        return value
    }

    func insertIfAbsent(
        _ secret: String,
        service: KeychainService,
        account: UUID,
        transactionTag: UUID
    ) throws -> Bool {
        try journal.record("save")
        try callControl.intercept("save")
        guard storage[service]?[account] == nil else { return false }
        storage[service, default: [:]][account] = secret
        transactionTags[service, default: [:]][account] = transactionTag
        return true
    }

    func deleteIfTransactionTagMatches(
        service: KeychainService,
        account: UUID,
        transactionTag: UUID
    ) throws -> Bool {
        try journal.record("delete")
        try callControl.intercept("delete")
        guard transactionTags[service]?[account] == transactionTag else { return false }
        storage[service]?[account] = nil
        transactionTags[service]?[account] = nil
        return true
    }

    func finalizeTransactionTagIfMatches(
        service: KeychainService,
        account: UUID,
        transactionTag: UUID
    ) throws {
        try journal.record("finalizeTransactionTag")
        try callControl.intercept("finalizeTransactionTag")
        guard transactionTags[service]?[account] == transactionTag else { return }
        transactionTags[service]?[account] = nil
    }

    func delete(service: KeychainService, account: UUID) throws {
        try journal.record("delete")
        try callControl.intercept("delete")
        storage[service]?[account] = nil
        transactionTags[service]?[account] = nil
    }

    func listAccounts(service: KeychainService) throws -> [UUID] {
        try journal.record("listAccounts")
        try callControl.intercept("listAccounts")
        return Array((storage[service] ?? [:]).keys)
    }
}
#endif
