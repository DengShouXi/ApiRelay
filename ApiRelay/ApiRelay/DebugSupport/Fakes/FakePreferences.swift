#if DEBUG
import Foundation

/// 假偏好：内存 DTO。`persist` 走非隔离箱，不碰 SwiftData / CloudKit。
actor FakePreferences: PreferencesServing {
    var journal = FakeJournal()
    private let store: Store

    init(initial: PreferencesDTO = .fakeDefault()) {
        store = Store(initial: initial)
    }

    private final class Store: @unchecked Sendable {
        private let lock = NSLock()
        private var value: PreferencesDTO

        init(initial: PreferencesDTO) {
            value = initial
        }

        func load() -> PreferencesDTO {
            lock.lock()
            defer { lock.unlock() }
            return value
        }

        func apply(_ patch: PreferencesPatch) {
            lock.lock()
            defer { lock.unlock() }
            value = value.applying(patch)
        }

        func reset() {
            lock.lock()
            defer { lock.unlock() }
            value = PreferencesDTO.fakeDefault()
        }
    }

    private var loadError: Error?
    private var updateError: Error?
    private nonisolated let persistBox = PersistBox()

    private final class PersistBox: @unchecked Sendable {
        private let lock = NSLock()
        var delay: (@Sendable () async -> Void)?
        var finalCommitDelay: (@Sendable () async -> Void)?
        var writeCount = 0

        func snapshotDelay() -> (@Sendable () async -> Void)? {
            lock.lock()
            defer { lock.unlock() }
            return delay
        }

        func setDelay(_ delay: (@Sendable () async -> Void)?) {
            lock.lock()
            self.delay = delay
            lock.unlock()
        }

        func snapshotFinalCommitDelay() -> (@Sendable () async -> Void)? {
            lock.lock()
            defer { lock.unlock() }
            return finalCommitDelay
        }

        func setFinalCommitDelay(_ delay: (@Sendable () async -> Void)?) {
            lock.lock()
            finalCommitDelay = delay
            lock.unlock()
        }

        func noteWrite() {
            lock.lock()
            writeCount += 1
            lock.unlock()
        }

        func writes() -> Int {
            lock.lock()
            defer { lock.unlock() }
            return writeCount
        }
    }

    func setLoadError(_ error: Error?) {
        loadError = error
    }

    func setUpdateError(_ error: Error?) {
        updateError = error
    }

    func setPersistDelay(_ delay: (@Sendable () async -> Void)?) {
        persistBox.setDelay(delay)
    }

    /// Test seam after the last async authorization and immediately before the
    /// synchronous repository-equivalent commit authorization.
    func setPersistFinalCommitDelay(_ delay: (@Sendable () async -> Void)?) {
        persistBox.setFinalCommitDelay(delay)
    }

    nonisolated func persistWriteCount() -> Int {
        persistBox.writes()
    }

    func load() async throws -> PreferencesDTO {
        try journal.record("load")
        if let loadError { throw loadError }
        return store.load()
    }

    func update(_ patch: PreferencesPatch) async throws {
        try prepareUpdate()
        applyUpdate(patch)
    }

    private func prepareUpdate() throws {
        try journal.record("update")
        if let updateError { throw updateError }
    }

    nonisolated private func applyUpdate(_ patch: PreferencesPatch) {
        store.apply(patch)
        let next = store.load()
        let armed = next.appLockEnabled && next.revealPolicy != .noVerification
        AppLockLaunchCache.write(armed)
    }

    nonisolated func persist(
        _ patch: PreferencesPatch,
        authorizing: @escaping @Sendable () async throws -> Void,
        committing: @escaping PreferencesCommit,
        expectedCurrentPolicy: RevealPolicy?,
        onFailure: (@Sendable (Error) -> Void)?,
        onSuccess: (@Sendable () -> Void)?
    ) {
        Task {
            do {
                if let delay = persistBox.snapshotDelay() {
                    await delay()
                }
                try await authorizing()
                if let expected = expectedCurrentPolicy {
                    let loaded = try await self.load()
                    let actual = RevealPolicyPersistence.canonical(loaded.revealPolicy)
                    let wanted = RevealPolicyPersistence.canonical(expected)
                    guard actual == wanted else {
                        throw ApiRelayError.validationFailed(
                            field: "revealPolicy",
                            reason: "stale_page_request"
                        )
                    }
                    try await authorizing()
                }
                if let delay = persistBox.snapshotFinalCommitDelay() {
                    await delay()
                }
                try await self.prepareUpdate()
                try committing {
                    self.applyUpdate(patch)
                }
                persistBox.noteWrite()
                await self.notePersist()
                onSuccess?()
            } catch {
                onFailure?(error)
            }
        }
    }

    func purgeAllRecordsForErase() async throws {
        try journal.record("purgeAllRecordsForErase")
        store.reset()
    }

    func purgeAllRecordsForCommittedErase(
        authorization: CommittedEraseToken
    ) async throws {
        try authorization.validate(operation: "fake_preferences_committed_erase")
        try journal.record("purgeAllRecordsForErase")
        store.reset()
    }

    private func notePersist() {
        journal.recordNonThrowing("persist")
    }
}
#endif
