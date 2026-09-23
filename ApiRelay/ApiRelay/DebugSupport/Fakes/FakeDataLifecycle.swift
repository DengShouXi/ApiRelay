#if DEBUG
import Foundation

/// 假数据生命周期：只记调用。不碰门闩 / Keychain / SwiftData。
actor FakeDataLifecycle: DataLifecycleServing {
    var journal = FakeJournal()

    nonisolated func hasPendingErase() -> Bool { false }

    func eraseAllUserData(appPassword: String?) async throws {
        lastAppPassword = appPassword
        try journal.record("eraseAllUserData")
    }

    func eraseAllUserDataForStorageRecovery() async throws {
        try journal.record("eraseAllUserDataForStorageRecovery")
    }

    private(set) var lastAppPassword: String?
}
#endif
