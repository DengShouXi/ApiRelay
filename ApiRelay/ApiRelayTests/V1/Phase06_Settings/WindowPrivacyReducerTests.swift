@preconcurrency import XCTest
@testable import ApiRelay

@MainActor
final class WindowPrivacyReducerTests: XCTestCase {
    func testUserFacingAndOffScreenDoesNotStartTimerAndCoversOnlyOffScreen() {
        let reduction = WindowPrivacyReducer.reduce(
            windows: [
                WindowPrivacyInput(id: "A", presence: .userFacing),
                WindowPrivacyInput(id: "B", presence: .offScreen)
            ],
            hideInAppSwitcher: true,
            isSessionLocked: false,
            hasBecomeActiveOnce: true
        )
        XCTAssertEqual(reduction.processPresence, .userFacing)
        XCTAssertFalse(reduction.startIdleTimer, "T-W2-01：有一扇仍在操作则不得开始自动锁计时")
        XCTAssertEqual(reduction.coveredIDs, ["B"])
        XCTAssertFalse(reduction.surface(for: "A").showsSnapshotCover)
        XCTAssertFalse(reduction.surface(for: "A").showsUnlockChrome)
        XCTAssertTrue(reduction.surface(for: "B").showsSnapshotCover)
        XCTAssertFalse(reduction.surface(for: "B").showsUnlockChrome)
    }

    func testAllOffScreenStartsTimerAndCoversBoth() {
        let reduction = WindowPrivacyReducer.reduce(
            windows: [
                WindowPrivacyInput(id: "A", presence: .offScreen),
                WindowPrivacyInput(id: "B", presence: .offScreen)
            ],
            hideInAppSwitcher: true,
            isSessionLocked: false,
            hasBecomeActiveOnce: true
        )
        XCTAssertEqual(reduction.processPresence, .offScreen)
        XCTAssertTrue(reduction.startIdleTimer, "T-W2-02：全部离屏才开始计时")
        XCTAssertEqual(reduction.coveredIDs, ["A", "B"])
    }

    func testLockedReturnUncoversOnlyActiveWindow() {
        let reduction = WindowPrivacyReducer.reduce(
            windows: [
                WindowPrivacyInput(id: "A", presence: .userFacing),
                WindowPrivacyInput(id: "B", presence: .offScreen)
            ],
            hideInAppSwitcher: false,
            isSessionLocked: true,
            hasBecomeActiveOnce: true
        )
        XCTAssertEqual(reduction.processPresence, .userFacing)
        XCTAssertFalse(reduction.startIdleTimer)
        XCTAssertEqual(reduction.coveredIDs, ["B"], "T-W2-03：只揭正在操作的那一扇")
        XCTAssertEqual(reduction.unlockChromeIDs, ["A"])
        XCTAssertFalse(reduction.surface(for: "A").showsSnapshotCover)
        XCTAssertTrue(reduction.surface(for: "A").showsUnlockChrome)
        XCTAssertTrue(reduction.surface(for: "B").showsSnapshotCover)
        XCTAssertFalse(reduction.surface(for: "B").showsUnlockChrome)
    }

    func testIdleWindowsStayUncoveredAndDoNotUnlock() {
        let reduction = WindowPrivacyReducer.reduce(
            windows: [
                WindowPrivacyInput(id: "idle", presence: .onScreenIdle),
                WindowPrivacyInput(id: "away", presence: .offScreen)
            ],
            hideInAppSwitcher: true,
            isSessionLocked: true,
            hasBecomeActiveOnce: true
        )
        XCTAssertEqual(reduction.processPresence, .onScreenIdle)
        XCTAssertFalse(reduction.startIdleTimer)
        XCTAssertEqual(reduction.coveredIDs, ["away"])
        XCTAssertTrue(reduction.unlockChromeIDs.isEmpty)
    }
}
