@preconcurrency import XCTest
@testable import ApiRelay

@MainActor
final class AppLockSessionTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    func testUnreadyBlocksContentSoListCannotFlash() {
        let session = AppLockSession.unready()
        XCTAssertFalse(session.isPreferencesReady)
        XCTAssertTrue(session.blocksContent)
        XCTAssertFalse(session.needsUnlockPrompt)
        XCTAssertFalse(session.showsSnapshotCover)
    }

    func testColdStartWithAppLockOffShowsContent() {
        var session = AppLockSession.unready()
        session.completeColdStart(with: .defaults)
        XCTAssertFalse(session.preferences.appLockEnabled)
        XCTAssertTrue(session.preferences.hideInAppSwitcher)
        XCTAssertEqual(session.preferences.autoLockSeconds, 60)
        XCTAssertFalse(session.isSessionLocked)
        XCTAssertFalse(session.blocksContent)
    }

    func testColdStartWithAppLockOnLocksBeforeContent() {
        var session = AppLockSession.unready()
        session.completeColdStart(with: AppLockPreferences(
            appLockEnabled: true,
            autoLockSeconds: 60,
            hideInAppSwitcher: false
        ))
        XCTAssertTrue(session.isSessionLocked)
        XCTAssertTrue(session.blocksContent)
        XCTAssertTrue(session.needsUnlockPrompt)
    }

    func testHideInSwitcherCoversOnlyWhileInactive() {
        var session = ready(hide: true, lock: false)
        XCTAssertFalse(session.showsSnapshotCover)
        session.noteWillResignActive(now: t0)
        XCTAssertTrue(session.showsSnapshotCover)
        XCTAssertTrue(session.blocksContent)
        session.noteWillEnterForeground(now: t0.addingTimeInterval(1))
        session.noteDidBecomeActive(now: t0.addingTimeInterval(1))
        XCTAssertFalse(session.showsSnapshotCover)
        XCTAssertFalse(session.blocksContent)
        XCTAssertFalse(session.isSessionLocked)
    }

    func testHideInSwitcherOffLeavesContentVisibleInSwitcher() {
        var session = ready(hide: false, lock: false)
        session.noteWillResignActive(now: t0)
        XCTAssertFalse(session.showsSnapshotCover)
        XCTAssertFalse(session.blocksContent)
    }

    func testTurningOffHideWhileInactiveRemovesCover() {
        var session = ready(hide: true, lock: false)
        session.noteWillResignActive(now: t0)
        XCTAssertTrue(session.showsSnapshotCover)
        session.applyLivePreferences(AppLockPreferences(
            appLockEnabled: false,
            autoLockSeconds: 60,
            hideInAppSwitcher: false
        ))
        XCTAssertFalse(session.showsSnapshotCover)
    }

    func testAppLockOffIgnoresAutoLockTimeout() {
        var session = ready(hide: false, lock: false, seconds: 0)
        session.noteWillResignActive(now: t0)
        session.noteWillEnterForeground(now: t0.addingTimeInterval(600))
        session.noteDidBecomeActive(now: t0.addingTimeInterval(600))
        XCTAssertFalse(session.isSessionLocked)
        XCTAssertFalse(session.blocksContent)
    }

    func testAutoLockZeroLocksAsSoonAsLeaving() {
        var session = ready(hide: false, lock: true, seconds: 0)
        session.unlockSucceeded()
        XCTAssertFalse(session.isSessionLocked)
        session.noteWillResignActive(now: t0)
        XCTAssertTrue(session.isSessionLocked)
        XCTAssertTrue(session.showsSnapshotCover, "锁态离开前台不得在切换器露出列表")
        session.noteWillEnterForeground(now: t0.addingTimeInterval(1))
        session.noteDidBecomeActive(now: t0.addingTimeInterval(1))
        XCTAssertTrue(session.isSessionLocked)
        XCTAssertTrue(session.needsUnlockPrompt)
        XCTAssertTrue(session.blocksContent)
    }

    func testAutoLockGraceDoesNotLockIfReturnedEarly() {
        var session = ready(hide: false, lock: true, seconds: 60)
        session.unlockSucceeded()
        session.noteWillResignActive(now: t0)
        XCTAssertFalse(session.isSessionLocked)
        XCTAssertFalse(session.showsSnapshotCover)
        session.noteWillEnterForeground(now: t0.addingTimeInterval(59))
        session.noteDidBecomeActive(now: t0.addingTimeInterval(59))
        XCTAssertFalse(session.isSessionLocked)
        XCTAssertFalse(session.blocksContent)
        XCTAssertFalse(session.needsUnlockPrompt)
    }

    func testAutoLockGraceLocksAtTimeout() {
        var session = ready(hide: false, lock: true, seconds: 60)
        session.unlockSucceeded()
        session.noteWillResignActive(now: t0)
        session.noteWillEnterForeground(now: t0.addingTimeInterval(60))
        XCTAssertTrue(session.isSessionLocked, "进入前台之前就必须已上锁")
        session.noteDidBecomeActive(now: t0.addingTimeInterval(60))
        XCTAssertTrue(session.needsUnlockPrompt)
        XCTAssertTrue(session.blocksContent)
        XCTAssertFalse(session.showsSnapshotCover)
    }

    func testLockDecisionHappensBeforeBecomingActive() {
        var session = ready(hide: true, lock: true, seconds: 30)
        session.unlockSucceeded()
        session.noteWillResignActive(now: t0)
        XCTAssertTrue(session.showsSnapshotCover)
        session.noteWillEnterForeground(now: t0.addingTimeInterval(30))
        XCTAssertTrue(session.isSessionLocked)
        XCTAssertTrue(session.blocksContent)
        XCTAssertTrue(session.isInactive, "仍视为 inactive 时不得先揭开")
        session.noteDidBecomeActive(now: t0.addingTimeInterval(30))
        XCTAssertTrue(session.blocksContent)
    }

    /// 系统在离开期间短暂拉起 active 再 inactive，不得把「离开时刻」改成闪断那一下。
    func testBriefActiveFlickerDoesNotResetAutoLockClock() {
        var session = ready(hide: false, lock: true, seconds: 30)
        session.unlockSucceeded()
        session.noteWillResignActive(now: t0)
        // 离开 10 秒后系统闪断：active 0.2 秒又 inactive
        session.noteWillEnterForeground(now: t0.addingTimeInterval(10))
        session.noteDidBecomeActive(now: t0.addingTimeInterval(10))
        XCTAssertFalse(session.isSessionLocked)
        session.noteWillResignActive(now: t0.addingTimeInterval(10.2))
        // 从最初离开算满 30 秒应上锁（若被重置成 10.2 起算则此处不锁）
        session.noteWillEnterForeground(now: t0.addingTimeInterval(30))
        XCTAssertTrue(session.isSessionLocked)
    }

    func testSustainedActiveThenLeaveRestartsAutoLockClock() {
        var session = ready(hide: false, lock: true, seconds: 30)
        session.unlockSucceeded()
        session.noteWillResignActive(now: t0)
        session.noteWillEnterForeground(now: t0.addingTimeInterval(10))
        session.noteDidBecomeActive(now: t0.addingTimeInterval(10))
        // 真正使用超过 brief 阈值后再离开，应重新起算
        session.noteWillResignActive(now: t0.addingTimeInterval(10 + AppLockSession.briefActiveThreshold + 0.5))
        session.noteWillEnterForeground(now: t0.addingTimeInterval(10 + AppLockSession.briefActiveThreshold + 20))
        XCTAssertFalse(session.isSessionLocked, "新离开周期未满 30 秒")
        session.noteWillEnterForeground(now: t0.addingTimeInterval(10 + AppLockSession.briefActiveThreshold + 30.5))
        XCTAssertTrue(session.isSessionLocked)
    }

    func testTurningOffAppLockUnlocksImmediately() {
        var session = AppLockSession.unready()
        session.completeColdStart(with: AppLockPreferences(
            appLockEnabled: true,
            autoLockSeconds: 60,
            hideInAppSwitcher: true
        ))
        XCTAssertTrue(session.isSessionLocked)
        session.applyLivePreferences(AppLockPreferences(
            appLockEnabled: false,
            autoLockSeconds: 60,
            hideInAppSwitcher: true
        ))
        XCTAssertFalse(session.isSessionLocked)
        XCTAssertFalse(session.blocksContent)
    }

    func testTurningOnAppLockDoesNotLockUntilNextLeave() {
        var session = ready(hide: false, lock: false)
        session.applyLivePreferences(AppLockPreferences(
            appLockEnabled: true,
            autoLockSeconds: 0,
            hideInAppSwitcher: false
        ))
        XCTAssertFalse(session.isSessionLocked)
        XCTAssertFalse(session.blocksContent)
        session.noteWillResignActive(now: t0)
        XCTAssertTrue(session.isSessionLocked)
    }

    func testUnlockClearsLockAndDoesNotPrompt() {
        var session = AppLockSession.unready()
        session.completeColdStart(with: AppLockPreferences(
            appLockEnabled: true,
            autoLockSeconds: 60,
            hideInAppSwitcher: false
        ))
        session.unlockSucceeded()
        XCTAssertFalse(session.isSessionLocked)
        XCTAssertFalse(session.needsUnlockPrompt)
        XCTAssertFalse(session.blocksContent)
    }

    /// 长时间在外回来：可能在仍标 inactive 时就完成 Face ID。解锁后必须能进内容，
    /// 不能停在「有遮罩、无解锁按钮」的死态。
    func testUnlockWhileInactiveEntersContentEvenIfHideOn() {
        var session = ready(hide: true, lock: true, seconds: 30)
        session.noteWillResignActive(now: t0)
        session.noteWillEnterForeground(now: t0.addingTimeInterval(60))
        XCTAssertTrue(session.isSessionLocked)
        XCTAssertTrue(session.isInactive)
        XCTAssertTrue(session.blocksContent)
        XCTAssertFalse(session.needsUnlockPrompt, "inactive 时不应只出锁图标却无解锁入口")
        session.unlockSucceeded()
        XCTAssertFalse(session.isSessionLocked)
        XCTAssertFalse(session.isInactive)
        XCTAssertFalse(session.blocksContent)
        XCTAssertFalse(session.needsUnlockPrompt)
    }

    func testRepeatedResignDoesNotResetGraceClock() {
        var session = ready(hide: false, lock: true, seconds: 60)
        session.unlockSucceeded()
        session.noteWillResignActive(now: t0)
        session.noteWillResignActive(now: t0.addingTimeInterval(50))
        session.noteWillEnterForeground(now: t0.addingTimeInterval(59))
        session.noteDidBecomeActive(now: t0.addingTimeInterval(59))
        XCTAssertFalse(session.isSessionLocked)
    }

    private func ready(hide: Bool, lock: Bool, seconds: Int = 60) -> AppLockSession {
        var session = AppLockSession.unready()
        session.completeColdStart(with: AppLockPreferences(
            appLockEnabled: lock,
            autoLockSeconds: seconds,
            hideInAppSwitcher: hide
        ))
        if lock {
            session.unlockSucceeded()
        }
        return session
    }
}
