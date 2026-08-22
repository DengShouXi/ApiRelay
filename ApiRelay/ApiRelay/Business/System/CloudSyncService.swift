import Foundation

protocol CloudSyncServing: Actor {
    func snapshot() async -> CloudSyncStatusDTO
    /// 催元数据：等到本次 CloudKit 导入/导出结束，或确认本机无待传。明文无法催。
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
            lastFailureMessage: await monitor.lastFailureMessage()
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
        case .succeeded(let date):
            return .uploaded(date)
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
