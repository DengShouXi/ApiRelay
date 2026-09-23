@preconcurrency import CoreData
@preconcurrency import XCTest
@testable import ApiRelay

private actor ScriptedCloudEraseMonitor: CloudKitSyncMonitoring {
    nonisolated let mirroringEnabled: Bool
    private var results: [CloudKitExportWaitResult]
    private var waitCallCount = 0

    init(
        mirroringEnabled: Bool = true,
        results: [CloudKitExportWaitResult]
    ) {
        self.mirroringEnabled = mirroringEnabled
        self.results = results
    }

    func accountState() async -> CloudAccountState { .signedIn }
    func userRecordName() async -> String? { nil }
    func activity() async -> CloudSyncActivity { .idle }
    func lastSuccessAt() async -> Date? { nil }
    func lastFailureMessage() async -> String? { nil }
    func lastFailureAt() async -> Date? { nil }
    func hasInFlightActivity() async -> Bool { false }

    func waitForCloudActivity(
        grace: Duration,
        activeTimeout: Duration
    ) async -> CloudKitExportWaitResult {
        _ = grace
        _ = activeTimeout
        waitCallCount += 1
        guard !results.isEmpty else { return .nothingPending }
        return results.removeFirst()
    }

    func waits() -> Int { waitCallCount }
}

private actor RepurgeProbe {
    private var callCount = 0

    func record() {
        callCount += 1
    }

    func count() -> Int { callCount }
}

@MainActor
final class CloudEraseConvergenceTests: XCTestCase {
    func testImportAndExportEachRequireRepurgeBeforeQuietCompletion() async throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let monitor = ScriptedCloudEraseMonitor(results: [
            .succeeded(now, .import),
            .succeeded(now.addingTimeInterval(1), .export),
            .nothingPending,
        ])
        let probe = RepurgeProbe()
        let sut = CloudEraseConvergence(
            monitor: monitor,
            quietGrace: .milliseconds(1),
            activeTimeout: .milliseconds(1)
        )

        try await sut.finishAfterInitialPurge {
            await probe.record()
        }

        let repurges = await probe.count()
        let waits = await monitor.waits()
        // Baseline final sweep + one sweep after each observed wave.
        XCTAssertEqual(repurges, 3)
        XCTAssertEqual(waits, 3)
    }

    func testDisabledMirroringCompletesWithoutWaitingOrRepurging() async throws {
        let monitor = ScriptedCloudEraseMonitor(
            mirroringEnabled: false,
            results: [.timedOut]
        )
        let probe = RepurgeProbe()
        let sut = CloudEraseConvergence(monitor: monitor)

        try await sut.finishAfterInitialPurge {
            await probe.record()
        }

        let repurges = await probe.count()
        let waits = await monitor.waits()
        XCTAssertEqual(repurges, 0)
        XCTAssertEqual(waits, 0)
    }

    func testMonitorNotMirroringCompletesAfterBaselineRepurge() async throws {
        let monitor = ScriptedCloudEraseMonitor(results: [.notMirroring])
        let probe = RepurgeProbe()
        let sut = CloudEraseConvergence(monitor: monitor)

        try await sut.finishAfterInitialPurge {
            await probe.record()
        }

        let repurges = await probe.count()
        let waits = await monitor.waits()
        XCTAssertEqual(repurges, 1)
        XCTAssertEqual(waits, 1)
    }

    func testPipelineFailureFailsClosedAfterBaselineRepurge() async {
        let monitor = ScriptedCloudEraseMonitor(results: [.failed("quota")])
        let probe = RepurgeProbe()
        let sut = CloudEraseConvergence(monitor: monitor)

        await assertRecoveryFailure(
            detail: "cloud_pipeline_failed",
            operation: {
                try await sut.finishAfterInitialPurge {
                    await probe.record()
                }
            }
        )

        let repurges = await probe.count()
        XCTAssertEqual(repurges, 1)
    }

    func testPipelineTimeoutFailsClosedAfterBaselineRepurge() async {
        let monitor = ScriptedCloudEraseMonitor(results: [.timedOut])
        let probe = RepurgeProbe()
        let sut = CloudEraseConvergence(monitor: monitor)

        await assertRecoveryFailure(
            detail: "cloud_pipeline_timed_out",
            operation: {
                try await sut.finishAfterInitialPurge {
                    await probe.record()
                }
            }
        )

        let repurges = await probe.count()
        XCTAssertEqual(repurges, 1)
    }

    func testSustainedActivityPerformsContainmentSweepThenFailsClosedAtCap() async {
        let now = Date(timeIntervalSince1970: 1_700_000_100)
        let monitor = ScriptedCloudEraseMonitor(results: [
            .succeeded(now, .import),
            .succeeded(now.addingTimeInterval(1), .export),
            .succeeded(now.addingTimeInterval(2), .import),
        ])
        let probe = RepurgeProbe()
        let sut = CloudEraseConvergence(
            monitor: monitor,
            quietGrace: .milliseconds(1),
            activeTimeout: .milliseconds(1),
            maxObservedActivityWaves: 2
        )

        await assertRecoveryFailure(
            detail: "cloud_activity_did_not_quiesce",
            operation: {
                try await sut.finishAfterInitialPurge {
                    await probe.record()
                }
            }
        )

        // Even the over-cap import receives one last containment sweep. The
        // outer journal still remains sealed because convergence throws.
        let repurges = await probe.count()
        let waits = await monitor.waits()
        XCTAssertEqual(repurges, 4)
        XCTAssertEqual(waits, 3)
    }

    func testCheckpointConsumesTerminalEventThatFinishedBeforeWaiterRegistration() async throws {
        let suite = "ApiRelay.CloudEraseCheckpointTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let monitor = CloudKitSyncMonitor(
            mirroringEnabled: true,
            defaults: defaults
        )
        let checkpoint = await monitor.pipelineRevision()
        let at = Date(timeIntervalSince1970: 1_700_000_200)

        // Both notifications finish before waitForCloudActivity(after:) is
        // called. The checkpoint-aware path must replay the terminal result
        // instead of incorrectly reporting a quiet window.
        await monitor.applyPipelineEvent(
            phase: .import,
            succeeded: true,
            ended: false,
            errorText: nil,
            date: at
        )
        await monitor.applyPipelineEvent(
            phase: .import,
            succeeded: true,
            ended: true,
            errorText: nil,
            date: at
        )

        let result = await monitor.waitForCloudActivity(
            after: checkpoint,
            grace: .seconds(5),
            activeTimeout: .seconds(5)
        )
        XCTAssertEqual(result, .succeeded(at, .import))
    }

    func testCheckpointFailureIsNotHiddenByLaterOtherPhaseSuccess() async {
        let suite = "ApiRelay.CloudEraseFailureCheckpointTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let monitor = CloudKitSyncMonitor(
            mirroringEnabled: true,
            defaults: defaults
        )
        let checkpoint = await monitor.pipelineRevision()
        let at = Date(timeIntervalSince1970: 1_700_000_300)

        await monitor.applyPipelineEvent(
            phase: .export,
            succeeded: false,
            ended: true,
            errorText: "export failed",
            date: at
        )
        await monitor.applyPipelineEvent(
            phase: .import,
            succeeded: true,
            ended: true,
            errorText: nil,
            date: at.addingTimeInterval(1)
        )

        let result = await monitor.waitForCloudActivity(
            after: checkpoint,
            grace: .seconds(5),
            activeTimeout: .seconds(5)
        )
        XCTAssertEqual(result, .failed("export failed"))
    }

    func testRealMonitorQuietPathReturnsNothingPendingWithinBound() async {
        let suite = "ApiRelay.CloudEraseQuietWaitTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let monitor = CloudKitSyncMonitor(
            mirroringEnabled: true,
            defaults: defaults
        )

        let result = await boundedWait {
            await monitor.waitForCloudActivity(
                grace: .milliseconds(20),
                activeTimeout: .milliseconds(40)
            )
        }
        XCTAssertEqual(result, .nothingPending)
    }

    func testMonitorInitSynchronouslyObservesImmediatePipelineStart() async {
        let suite = "ApiRelay.CloudEraseObserverInitTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let notificationCenter = NotificationCenter()
        let startedAt = Date(timeIntervalSince1970: 1_700_000_350)
        let monitor = CloudKitSyncMonitor(
            mirroringEnabled: true,
            defaults: defaults,
            notificationCenter: notificationCenter,
            pipelineEventDecoder: { notification in
                guard notification.userInfo?["syntheticPipelineStart"] as? Bool == true else {
                    return nil
                }
                return CloudKitPipelineEventSnapshot(
                    phase: .import,
                    succeeded: true,
                    ended: false,
                    errorText: nil,
                    date: startedAt
                )
            }
        )

        // Posting immediately after init must be observed. If registration is
        // deferred to a Task, this start can be lost and the wait reports
        // `nothingPending` instead of timing out on active import work.
        notificationCenter.post(
            name: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil,
            userInfo: ["syntheticPipelineStart": true]
        )

        let result = await boundedWait {
            await monitor.waitForCloudActivity(
                grace: .milliseconds(100),
                activeTimeout: .milliseconds(20)
            )
        }
        XCTAssertEqual(result, .timedOut)
        let revision = await monitor.pipelineRevision()
        XCTAssertEqual(revision, 1)
    }

    func testRealMonitorInFlightWithoutEndReturnsTimedOutWithinBound() async {
        let suite = "ApiRelay.CloudEraseActiveWaitTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let monitor = CloudKitSyncMonitor(
            mirroringEnabled: true,
            defaults: defaults
        )
        await monitor.applyPipelineEvent(
            phase: .import,
            succeeded: true,
            ended: false,
            errorText: nil,
            date: Date(timeIntervalSince1970: 1_700_000_400)
        )

        let result = await boundedWait {
            await monitor.waitForCloudActivity(
                grace: .milliseconds(10),
                activeTimeout: .milliseconds(30)
            )
        }
        XCTAssertEqual(result, .timedOut)
    }

    private func assertRecoveryFailure(
        detail expectedDetail: String,
        operation: () async throws -> Void
    ) async {
        do {
            try await operation()
            XCTFail("Expected fail-closed Cloud erase convergence")
        } catch let ApiRelayError.storageRecoveryFailed(operation, detail) {
            XCTAssertEqual(operation, "erase_cloud_convergence")
            XCTAssertEqual(detail, expectedDetail)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    /// XCTest's own timeout remains outside the monitor task. A regression in
    /// task-group teardown therefore fails in one second instead of hanging the
    /// entire suite forever.
    private func boundedWait(
        operation: @escaping @MainActor () async -> CloudKitExportWaitResult
    ) async -> CloudKitExportWaitResult? {
        let finished = expectation(description: "CloudKit monitor wait returned")
        var result: CloudKitExportWaitResult?
        let work = Task { @MainActor in
            result = await operation()
            finished.fulfill()
        }
        await fulfillment(of: [finished], timeout: 1.0)
        work.cancel()
        return result
    }
}
