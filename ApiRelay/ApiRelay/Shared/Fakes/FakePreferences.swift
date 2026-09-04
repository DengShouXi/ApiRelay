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

    func load() async throws -> PreferencesDTO {
        try journal.record("load")
        return store.load()
    }

    func update(_ patch: PreferencesPatch) async throws {
        try journal.record("update")
        store.apply(patch)
    }

    nonisolated func persist(_ patch: PreferencesPatch) {
        store.apply(patch)
        Task { await self.notePersist() }
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
