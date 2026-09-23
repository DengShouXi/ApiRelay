@testable import ApiRelay
import Foundation

/// Pauses immediately before `SessionLockBox` performs the final lease check.
/// Tests can invalidate the lease while no session-lock mutex is held, release
/// the pause, and prove that the concrete repository/Keychain mutation is zero.
nonisolated final class CommitBarrierSessionLock: SessionLockQuerying, @unchecked Sendable {
    private let box = SessionLockBox()
    private let lock = NSLock()
    private var armed = false
    private var active: DispatchSemaphore?
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func blockNextCommit() {
        lock.lock()
        armed = true
        lock.unlock()
    }

    func waitUntilCommitIsBlocked() async {
        await withCheckedContinuation { continuation in
            lock.lock()
            if active != nil {
                lock.unlock()
                continuation.resume()
            } else {
                waiters.append(continuation)
                lock.unlock()
            }
        }
    }

    func releaseCommit() {
        lock.lock()
        let semaphore = active
        active = nil
        lock.unlock()
        semaphore?.signal()
    }

    func invalidateAuthorizationLeases() {
        box.invalidateAuthorizationLeases()
    }

    func setLocked(_ value: Bool) {
        box.setLocked(value)
    }

    nonisolated func isSessionLocked() -> Bool {
        box.isSessionLocked()
    }

    nonisolated func captureAuthorizationLease() throws -> SessionAuthorizationLease {
        try box.captureAuthorizationLease()
    }

    nonisolated func validateAuthorizationLease(_ lease: SessionAuthorizationLease) throws {
        try box.validateAuthorizationLease(lease)
    }

    nonisolated func commitAuthorizationLease(
        _ lease: SessionAuthorizationLease,
        operation: () throws -> Void
    ) throws {
        lock.lock()
        guard armed else {
            lock.unlock()
            return try box.commitAuthorizationLease(lease, operation: operation)
        }
        armed = false
        let semaphore = DispatchSemaphore(value: 0)
        active = semaphore
        let ready = waiters
        waiters.removeAll(keepingCapacity: false)
        lock.unlock()
        ready.forEach { $0.resume() }
        semaphore.wait()
        try box.commitAuthorizationLease(lease, operation: operation)
    }
}

nonisolated final class InMemoryDataEraseJournal: DataEraseJournalStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var stage: DataEraseStage?
    private var corruptPending = false
    private var markFailure: ApiRelayError?
    private var persistsBeforeMarkFailure = false

    func failMarks(with error: ApiRelayError, afterPersisting: Bool = false) {
        lock.lock()
        markFailure = error
        persistsBeforeMarkFailure = afterPersisting
        lock.unlock()
    }

    func allowMarks() {
        lock.lock()
        markFailure = nil
        persistsBeforeMarkFailure = false
        lock.unlock()
    }

    func seedPending(_ stage: DataEraseStage? = .keychain) {
        lock.lock()
        self.stage = stage
        corruptPending = stage == nil
        lock.unlock()
    }

    nonisolated func mark(_ stage: DataEraseStage) throws {
        lock.lock()
        defer { lock.unlock() }
        if let markFailure, !persistsBeforeMarkFailure { throw markFailure }
        self.stage = stage
        corruptPending = false
        if let markFailure { throw markFailure }
    }

    nonisolated func clear() throws {
        lock.lock()
        stage = nil
        corruptPending = false
        lock.unlock()
    }

    nonisolated func hasPendingErase() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return stage != nil || corruptPending
    }

    nonisolated func currentStage() -> DataEraseStage? {
        lock.lock()
        defer { lock.unlock() }
        return stage
    }
}
