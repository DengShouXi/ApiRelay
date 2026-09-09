import Foundation

/// 监听 CloudKit **成功导入**通知，合并延迟后再跑身份清扫。
/// 不在 MainActor 上 `await` SwiftData save：调度在本 actor，写入仍在仓库 ModelActor。
actor CloudImportIdentityHygiene {
    private let scheduler: IdentityHygieneScheduler
    private let prune: @Sendable () async -> Void

    init(
        delay: Duration = .milliseconds(1500),
        prune: @escaping @Sendable () async -> Void
    ) {
        self.scheduler = IdentityHygieneScheduler(delay: delay)
        self.prune = prune
    }

    /// 测试可直接打这一下，不必发系统通知。
    func handleImportSucceeded() async {
        await scheduler.request(prune)
    }

    func startObserving() async {
        let notifications = NotificationCenter.default.notifications(
            named: .apiRelayCloudMetadataDidImport
        )
        for await _ in notifications {
            // 不得 await handle 到结束再读下一条，否则连发无法合并。
            Task { await self.handleImportSucceeded() }
        }
    }
}
