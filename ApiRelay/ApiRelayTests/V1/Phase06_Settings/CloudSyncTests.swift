@preconcurrency import XCTest
@testable import ApiRelay

actor FakeCloudKitSyncMonitor: CloudKitSyncMonitoring {
    nonisolated let mirroringEnabled: Bool
    var account: CloudAccountState
    var userRecord: String?
    var pipelineActivity: CloudSyncActivity
    var lastSuccess: Date?
    var lastFailure: String?
    var inFlight: Bool
    var waitResult: CloudKitExportWaitResult

    init(
        mirroringEnabled: Bool,
        account: CloudAccountState,
        userRecord: String? = nil,
        activity: CloudSyncActivity = .idle,
        lastSuccess: Date? = nil,
        lastFailure: String? = nil,
        inFlight: Bool = false,
        waitResult: CloudKitExportWaitResult = .nothingPending
    ) {
        self.mirroringEnabled = mirroringEnabled
        self.account = account
        self.userRecord = userRecord
        self.pipelineActivity = activity
        self.lastSuccess = lastSuccess
        self.lastFailure = lastFailure
        self.inFlight = inFlight
        self.waitResult = waitResult
    }

    func accountState() async -> CloudAccountState { account }
    func userRecordName() async -> String? { userRecord }
    func activity() async -> CloudSyncActivity { pipelineActivity }
    func lastSuccessAt() async -> Date? { lastSuccess }
    func lastFailureMessage() async -> String? { lastFailure }
    func hasInFlightActivity() async -> Bool { inFlight }
    func waitForCloudActivity(grace: Duration, activeTimeout: Duration) async -> CloudKitExportWaitResult {
        _ = grace
        _ = activeTimeout
        return waitResult
    }
}

@MainActor
final class CloudSyncTests: XCTestCase {
    func testInMemoryContainerDisablesMirroring() throws {
        _ = try AppSchema.makeInMemoryContainer()
        XCTAssertFalse(AppSchema.isCloudKitMirroringEnabled)
    }

    func testShortCloudIdentityUsesPrefixWithoutHyphens() {
        var dto = CloudSyncStatusDTO.placeholder
        dto.cloudKitUserRecordName = "abcdef12-3456-7890-abcd-ef1234567890"
        XCTAssertEqual(dto.shortCloudIdentity, "ABCDEF12")
        dto.cloudKitUserRecordName = nil
        XCTAssertNil(dto.shortCloudIdentity)
    }

    func testSnapshotCopiesMonitorFields() async {
        let at = Date(timeIntervalSince1970: 1_700_000_000)
        let monitor = FakeCloudKitSyncMonitor(
            mirroringEnabled: true,
            account: .signedIn,
            userRecord: "user-record",
            activity: .exporting,
            lastSuccess: at,
            lastFailure: nil
        )
        let sut = CloudSyncService(monitor: monitor)
        let snap = await sut.snapshot()
        XCTAssertEqual(snap.account, .signedIn)
        XCTAssertEqual(snap.cloudKitUserRecordName, "user-record")
        XCTAssertTrue(snap.mirroringEnabled)
        XCTAssertEqual(snap.activity, .exporting)
        XCTAssertEqual(snap.lastSuccessAt, at)
    }

    func testRequestMetadataSyncUnavailableWhenSignedOut() async {
        let monitor = FakeCloudKitSyncMonitor(
            mirroringEnabled: true,
            account: .signedOut,
            waitResult: .succeeded(Date())
        )
        let sut = CloudSyncService(monitor: monitor)
        let outcome = await sut.requestMetadataSync()
        XCTAssertEqual(outcome, .unavailable)
    }

    func testRequestMetadataSyncLocalOnlyWhenMirroringOff() async {
        let monitor = FakeCloudKitSyncMonitor(
            mirroringEnabled: false,
            account: .signedIn,
            waitResult: .succeeded(Date())
        )
        let sut = CloudSyncService(monitor: monitor)
        let outcome = await sut.requestMetadataSync()
        XCTAssertEqual(outcome, .localOnly)
    }

    func testRequestMetadataSyncUploadedOnExportSuccess() async {
        let at = Date(timeIntervalSince1970: 1_700_000_100)
        let monitor = FakeCloudKitSyncMonitor(
            mirroringEnabled: true,
            account: .signedIn,
            waitResult: .succeeded(at)
        )
        let sut = CloudSyncService(monitor: monitor)
        let outcome = await sut.requestMetadataSync()
        XCTAssertEqual(outcome, .uploaded(at))
    }

    func testRequestMetadataSyncNothingPendingKeepsLastSuccess() async {
        let at = Date(timeIntervalSince1970: 1_700_000_200)
        let monitor = FakeCloudKitSyncMonitor(
            mirroringEnabled: true,
            account: .signedIn,
            lastSuccess: at,
            waitResult: .nothingPending
        )
        let sut = CloudSyncService(monitor: monitor)
        let outcome = await sut.requestMetadataSync()
        XCTAssertEqual(outcome, .nothingToUpload(lastSuccess: at))
    }

    func testRequestMetadataSyncDoesNotSucceedOnTimeout() async {
        let monitor = FakeCloudKitSyncMonitor(
            mirroringEnabled: true,
            account: .signedIn,
            waitResult: .timedOut
        )
        let sut = CloudSyncService(monitor: monitor)
        let outcome = await sut.requestMetadataSync()
        XCTAssertEqual(outcome, .timedOut)
    }

    func testRequestMetadataSyncFailedPassesMessage() async {
        let monitor = FakeCloudKitSyncMonitor(
            mirroringEnabled: true,
            account: .signedIn,
            waitResult: .failed("quota")
        )
        let sut = CloudSyncService(monitor: monitor)
        let outcome = await sut.requestMetadataSync()
        XCTAssertEqual(outcome, .failed("quota"))
    }

    func testHelpCopySplitsOnChinesePeriod() {
        let status = String(localized: "vault.sync.status.help")
        XCTAssertGreaterThanOrEqual(InlineHelpButton.sentences(in: status).count, 2)

        let settings = String(localized: "vault.sync.openSystemSettings.footnote")
        XCTAssertGreaterThanOrEqual(InlineHelpButton.blocks(in: settings).count, 2)
    }

    func testMonitorPersistsSuccessAndWakesWaiter() async throws {
        let suite = "ApiRelay.CloudSyncTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let monitor = CloudKitSyncMonitor(
            mirroringEnabled: true,
            defaults: defaults
        )
        let date = Date(timeIntervalSince1970: 1_700_000_300)
        let waitTask = Task {
            await monitor.waitForCloudActivity(grace: .seconds(8), activeTimeout: .seconds(8))
        }
        try await Task.sleep(for: .milliseconds(80))
        await monitor.applyPipelineEvent(
            phase: .export,
            succeeded: true,
            ended: false,
            errorText: nil,
            date: date
        )
        await monitor.applyPipelineEvent(
            phase: .export,
            succeeded: true,
            ended: true,
            errorText: nil,
            date: date
        )
        let result = await waitTask.value
        XCTAssertEqual(result, .succeeded(date))
        let last = await monitor.lastSuccessAt()
        XCTAssertEqual(last, date)
    }
}
