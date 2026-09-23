import Foundation

/// Narrows the race between a committed full erase and SwiftData's background
/// CloudKit importer.
///
/// The caller performs its initial idempotent purge before entering here. This
/// coordinator then performs a baseline final sweep with a pipeline checkpoint.
/// If the mirroring pipeline reports an import/export/setup wave, it sweeps
/// every synced repository context again. Completion requires a later quiet
/// observation window. Pipeline failure, timeout, or sustained activity is
/// deliberately fail-closed so the outer erase journal remains durable.
///
/// This is a process-local convergence fence, not a distributed transaction:
/// CloudKit schedules mirroring itself, and an offline peer can still make a
/// future write after this method returns. A system-wide reset guarantee would
/// require a synced erase generation/tombstone or ownership of a supported
/// record-zone reset; neither is represented by the current production schema.
protocol CloudEraseConverging: Actor {
    func finishAfterInitialPurge(
        repurge: @Sendable () async throws -> Void
    ) async throws
}

actor CloudEraseConvergence: CloudEraseConverging {
    private let monitor: any CloudKitSyncMonitoring
    private let quietGrace: Duration
    private let activeTimeout: Duration
    private let maxObservedActivityWaves: Int

    init(
        monitor: any CloudKitSyncMonitoring,
        quietGrace: Duration = .seconds(2.5),
        activeTimeout: Duration = .seconds(20),
        maxObservedActivityWaves: Int = 8
    ) {
        precondition(maxObservedActivityWaves > 0)
        self.monitor = monitor
        self.quietGrace = quietGrace
        self.activeTimeout = activeTimeout
        self.maxObservedActivityWaves = maxObservedActivityWaves
    }

    func finishAfterInitialPurge(
        repurge: @Sendable () async throws -> Void
    ) async throws {
        guard monitor.mirroringEnabled else { return }

        var observedActivityWaves = 0
        while true {
            // Take the checkpoint before each sweep. The monitor's checkpoint-
            // aware wait consumes a terminal event even if it starts and ends
            // during the sweep, before the waiter itself is registered.
            let checkpoint = await monitor.pipelineRevision()
            try await repurge()
            let result = await monitor.waitForCloudActivity(
                after: checkpoint,
                grace: quietGrace,
                activeTimeout: activeTimeout
            )
            switch result {
            case .nothingPending, .notMirroring:
                return

            case .succeeded:
                // An import can restore a row after the sweep. An export can be
                // the tombstones from that sweep. Repeat until a quiet window.
                observedActivityWaves += 1
                guard observedActivityWaves <= maxObservedActivityWaves else {
                    // Contain rows from the over-cap wave before preserving the
                    // outer journal for a later authenticated retry.
                    try await repurge()
                    throw Self.recoveryFailure("cloud_activity_did_not_quiesce")
                }

            case .failed:
                throw Self.recoveryFailure("cloud_pipeline_failed")

            case .timedOut:
                throw Self.recoveryFailure("cloud_pipeline_timed_out")
            }
        }
    }

    private nonisolated static func recoveryFailure(_ detail: String) -> ApiRelayError {
        .storageRecoveryFailed(
            operation: "erase_cloud_convergence",
            detail: detail
        )
    }
}
