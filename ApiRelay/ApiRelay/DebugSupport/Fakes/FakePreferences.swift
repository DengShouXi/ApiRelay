#if DEBUG
import Foundation

/// 假偏好：内存 DTO。`persist` 走非隔离箱，不碰 SwiftData / CloudKit。
actor FakePreferences: PreferencesServing {
    var journal = FakeJournal()
    private let store = Store()

    private final class Store: @unchecked Sendable {
        private let lock = NSLock()
        private var value = PreferencesDTO.fakeDefault()

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

    func setLoadError(_ error: Error?) {
        loadError = error
    }

    func setUpdateError(_ error: Error?) {
        updateError = error
    }

    func load() async throws -> PreferencesDTO {
        try journal.record("load")
        if let loadError { throw loadError }
        return store.load()
    }

    func update(_ patch: PreferencesPatch) async throws {
        try journal.record("update")
        if let updateError { throw updateError }
        store.apply(patch)
    }

    nonisolated func persist(_ patch: PreferencesPatch, onFailure: (@Sendable (Error) -> Void)?) {
        Task {
            do {
                try await self.update(patch)
                await self.notePersist()
            } catch {
                onFailure?(error)
            }
        }
    }

    func purgeAllRecordsForErase() async throws {
        try journal.record("purgeAllRecordsForErase")
        store.reset()
    }

    private func notePersist() {
        journal.recordNonThrowing("persist")
    }
}
#endif
