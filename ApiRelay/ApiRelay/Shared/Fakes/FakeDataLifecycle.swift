#if DEBUG
import Foundation

/// 假数据生命周期：只记调用。不碰门闩 / Keychain / SwiftData。
actor FakeDataLifecycle: DataLifecycleServing {
    var journal = FakeJournal()

    func eraseAllUserData() async throws {
        try journal.record("eraseAllUserData")
    }
}
#endif
