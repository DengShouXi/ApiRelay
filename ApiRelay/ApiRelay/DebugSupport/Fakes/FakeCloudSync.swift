#if DEBUG
import Foundation

/// 假 CloudKit 同步状态：可配置快照。不碰 CloudKit。
actor FakeCloudSync: CloudSyncServing {
    var journal = FakeJournal()
    var status: CloudSyncStatusDTO
    var syncOutcome: CloudSyncNowOutcome = .localOnly

    init(
        status: CloudSyncStatusDTO = CloudSyncStatusDTO(
            account: .unknown,
            cloudKitUserRecordName: nil,
            mirroringEnabled: false,
            activity: .idle,
            lastSuccessAt: nil,
            lastFailureMessage: nil,
            lastFailureAt: nil
        ),
        syncOutcome: CloudSyncNowOutcome = .localOnly
    ) {
        self.status = status
        self.syncOutcome = syncOutcome
    }
    func snapshot() async -> CloudSyncStatusDTO {
        journal.recordNonThrowing("snapshot")
        return status
    }

    func requestMetadataSync() async -> CloudSyncNowOutcome {
        journal.recordNonThrowing("requestMetadataSync")
        return syncOutcome
    }
}
#endif
