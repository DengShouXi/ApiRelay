import Foundation

/// CloudKit 导入成功通知可能连发。合并窗口内只跑一次清扫。
/// 方法本身是 async，用 `Task.sleep` 赛跑代数，禁止在同步 actor 方法里再起超时 `Task`。
actor IdentityHygieneScheduler {
    private var generation = 0
    private let delay: Duration

    init(delay: Duration = .milliseconds(1500)) {
        self.delay = delay
    }

    func request(_ work: @escaping @Sendable () async -> Void) async {
        generation += 1
        let token = generation
        let sleepFor = delay
        try? await Task.sleep(for: sleepFor)
        guard token == generation else { return }
        await work()
    }
}
