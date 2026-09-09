import Foundation

protocol CloudSyncServing: Actor {
    func snapshot() async -> CloudSyncStatusDTO
    /// 刷新并等待可观测的 CloudKit 活动；系统不提供强制同步 API。
    func requestMetadataSync() async -> CloudSyncNowOutcome
}

actor CloudSyncService: CloudSyncServing {
    private let monitor: any CloudKitSyncMonitoring

    init(monitor: any CloudKitSyncMonitoring) {
        self.monitor = monitor
    }

    func snapshot() async -> CloudSyncStatusDTO {
        CloudSyncStatusDTO(
            account: await monitor.accountState(),
            cloudKitUserRecordName: await monitor.userRecordName(),
            mirroringEnabled: monitor.mirroringEnabled,
            activity: await monitor.activity(),
            lastSuccessAt: await monitor.lastSuccessAt(),
            lastFailureMessage: await monitor.lastFailureMessage(),
            lastFailureAt: await monitor.lastFailureAt()
        )
    }

    func requestMetadataSync() async -> CloudSyncNowOutcome {
        switch await monitor.accountState() {
        case .signedIn:
            break
        default:
            return .unavailable
        }
        guard monitor.mirroringEnabled else {
            return .localOnly
        }
        let wait = await monitor.waitForCloudActivity(
            grace: .seconds(2.5),
            activeTimeout: .seconds(20)
        )
        switch wait {
        case .succeeded(let date, let phase):
            return phase == .export ? .uploaded(date) : .refreshed(date)
        case .nothingPending:
            return .nothingToUpload(lastSuccess: await monitor.lastSuccessAt())
        case .timedOut:
            return .timedOut
        case .failed(let message):
            return .failed(message)
        case .notMirroring:
            return .localOnly
        }
    }
}
