@preconcurrency import XCTest
@testable import ApiRelay
import LocalAuthentication

@MainActor
final class AppPrivacyControllerTests: XCTestCase {
    override func setUp() {
        super.setUp()
        AppLockLaunchCache.resetForTests()
    }

    override func tearDown() {
        AppLockLaunchCache.resetForTests()
        super.tearDown()
    }

    func testStartUsesStoredAppLockAndDefaultHide() async throws {
        let sut = try await makeController(appLock: true, hide: true, seconds: 60)
        await sut.start()
        XCTAssertTrue(sut.session.isPreferencesReady)
        XCTAssertTrue(sut.session.isSessionLocked)
        XCTAssertTrue(sut.session.blocksContent)
        XCTAssertTrue(sut.session.needsUnlockPrompt)
    }

    func testCachedAppLockLocksBeforeStart() async throws {
        let sut = try await makeController(appLock: true, hide: true, seconds: 60)
        XCTAssertTrue(sut.session.isSessionLocked)
        XCTAssertTrue(sut.session.blocksContent)
        XCTAssertFalse(sut.session.needsUnlockPrompt, "验证方式还没读到，不得先按默认「不验证」去弹系统解锁")
        await sut.start()
        XCTAssertTrue(sut.session.needsUnlockPrompt)
    }

    func testCachedUnlockedShowsContentBeforeStart() async throws {
        let sut = try await makeController(appLock: false, hide: true, seconds: 60)
        XCTAssertTrue(sut.session.isPreferencesReady)
        XCTAssertFalse(sut.session.isSessionLocked)
        XCTAssertFalse(sut.session.blocksContent)
    }

    func testCachedLockWaitsForRealRevealPolicy() async throws {
        let sut = try await makeController(
            appLock: true,
            hide: false,
            seconds: 60,
            revealPolicy: .masterPassword,
            masterPassword: "vault-pass-word"
        )
        XCTAssertTrue(sut.session.isSessionLocked)
        XCTAssertFalse(sut.session.isPreferencesReady)
        XCTAssertFalse(sut.usesMasterPasswordUnlock)
        XCTAssertFalse(sut.session.needsUnlockPrompt)
        await sut.start()
        XCTAssertTrue(sut.usesMasterPasswordUnlock)
        XCTAssertTrue(sut.session.needsUnlockPrompt)
    }

    func testUncachedLaunchShowsContentWithoutWaiting() async throws {
        AppLockLaunchCache.resetForTests()
        let container = try AppSchema.makeInMemoryContainer()
        let preferences = PreferencesService(modelContainer: container)
        let keychain = KeychainStore.makeForTests()
        let master = MasterPasswordService(keychain: keychain, calibratedIterations: 10_000)
        try? await master.reset()
        let sut = AppPrivacyController(
            gate: RevealGate(masterPassword: master, authenticateDeviceOwner: { _, _ in }),
            preferences: preferences,
            masterPassword: master,
            installsSnapshotCover: false,
            enablesUnlockPrompt: false
        )
        XCTAssertTrue(sut.session.isPreferencesReady)
        XCTAssertFalse(sut.session.isSessionLocked)
        XCTAssertFalse(sut.session.blocksContent)
        await sut.start()
        XCTAssertFalse(sut.session.isSessionLocked)
        XCTAssertFalse(sut.session.blocksContent)
    }

    func testStartWithDefaultsDoesNotLockButHidesInSwitcher() async throws {
        let sut = try await makeController(appLock: false, hide: true, seconds: 60)
        await sut.start()
        XCTAssertFalse(sut.session.isSessionLocked)
        XCTAssertFalse(sut.session.blocksContent)
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        sut.handleWillResignActive(now: t0)
        XCTAssertFalse(sut.session.showsSnapshotCover, "冷启动 inactive 不得当成切换器")
        sut.handleDidBecomeActive(now: t0.addingTimeInterval(0.1))
        sut.handleWillResignActive(now: t0.addingTimeInterval(0.2))
        XCTAssertFalse(sut.session.showsSnapshotCover, "进前台后立刻 inactive 仍是启动闪断")
        sut.handleDidBecomeActive(now: t0.addingTimeInterval(0.3))
        sut.handleWillResignActive(now: t0.addingTimeInterval(2))
        XCTAssertTrue(sut.session.showsSnapshotCover)
        XCTAssertTrue(sut.session.blocksContent)
        XCTAssertFalse(sut.session.showsAppLockUI)
        sut.handleDidBecomeActive(now: t0.addingTimeInterval(2.1))
        XCTAssertFalse(sut.session.blocksContent)
        XCTAssertFalse(sut.session.isSessionLocked)
    }

    func testTurningOffHideRemovesSwitcherCover() async throws {
        let sut = try await makeController(appLock: false, hide: true, seconds: 60)
        await sut.start()
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        sut.handleDidBecomeActive(now: t0)
        sut.handleWillResignActive(now: t0.addingTimeInterval(2))
        XCTAssertTrue(sut.session.showsSnapshotCover)
        sut.applyLivePreferences(
            AppLockPreferences(appLockEnabled: false, autoLockSeconds: 60, hideInAppSwitcher: false)
        )
        XCTAssertFalse(sut.session.showsSnapshotCover)
        XCTAssertFalse(sut.session.blocksContent)
    }

    func testTurningOffAppLockClearsColdStartLock() async throws {
        let sut = try await makeController(appLock: true, hide: false, seconds: 0)
        await sut.start()
        XCTAssertTrue(sut.session.isSessionLocked)
        sut.applyLivePreferences(
            AppLockPreferences(appLockEnabled: false, autoLockSeconds: 0, hideInAppSwitcher: false)
        )
        XCTAssertFalse(sut.session.isSessionLocked)
        XCTAssertFalse(sut.session.blocksContent)
    }

    func testMasterPasswordPolicyWaitsForAppPasswordNotDevicePasscode() async throws {
        let sut = try await makeController(
            appLock: true,
            hide: false,
            seconds: 60,
            revealPolicy: .masterPassword,
            masterPassword: "vault-pass-word"
        )
        await sut.start()
        XCTAssertTrue(sut.usesMasterPasswordUnlock)
        XCTAssertTrue(sut.session.isSessionLocked)
        await sut.unlockWithMasterPassword("wrong-guess")
        XCTAssertTrue(sut.session.isSessionLocked)
        XCTAssertEqual(sut.unlockError, String(localized: "appLock.masterPassword.incorrect"))
        await sut.unlockWithMasterPassword("vault-pass-word")
        XCTAssertFalse(sut.session.isSessionLocked)
        XCTAssertNil(sut.unlockError)
    }

    func testEmptyMasterPasswordExplainsInsteadOfUnlocking() async throws {
        let sut = try await makeController(
            appLock: true,
            hide: false,
            seconds: 60,
            revealPolicy: .masterPassword,
            masterPassword: "vault-pass-word"
        )
        await sut.start()
        await sut.unlockWithMasterPassword("   ")
        XCTAssertTrue(sut.session.isSessionLocked)
        XCTAssertEqual(sut.unlockError, String(localized: "appLock.masterPassword.empty"))
    }

    /// 策略要主密码、本机却没有时，提示 MUST NOT 说成「密码不正确」——
    /// 那会让用户以为是自己记错，反复重试一个根本不存在的密码。
    func testMissingMasterPasswordSaysNotSetInsteadOfIncorrect() async throws {
        let sut = try await makeController(
            appLock: true,
            hide: false,
            seconds: 60,
            revealPolicy: .masterPassword,
            masterPassword: nil
        )
        await sut.start()
        await sut.unlockWithMasterPassword("123456")
        XCTAssertTrue(sut.session.isSessionLocked)
        XCTAssertEqual(sut.unlockError, String(localized: "appLock.masterPassword.notSet"))
        XCTAssertNotEqual(sut.unlockError, String(localized: "appLock.masterPassword.incorrect"))
    }

    /// 死局必须在锁屏露面之前就被发现，而不是等用户输错几十次才反应过来。
    func testStartDetectsMissingMasterPasswordBeforeAnyAttempt() async throws {
        let sut = try await makeController(
            appLock: true,
            hide: false,
            seconds: 60,
            revealPolicy: .masterPassword,
            masterPassword: nil
        )
        await sut.start()
        XCTAssertTrue(sut.masterPasswordMissing)
        XCTAssertTrue(sut.session.isSessionLocked)
    }

    func testStartDoesNotFlagMissingWhenMasterPasswordExists() async throws {
        let sut = try await makeController(
            appLock: true,
            hide: false,
            seconds: 60,
            revealPolicy: .masterPassword,
            masterPassword: "vault-pass-word"
        )
        await sut.start()
        XCTAssertFalse(sut.masterPasswordMissing)
    }

    func testRecoveryClearsMissingFlag() async throws {
        let harness = try await makeHarness(
            appLock: true,
            hide: false,
            seconds: 60,
            revealPolicy: .masterPassword,
            masterPassword: nil,
            deviceOwnerAuth: { _, _ in }
        )
        let sut = harness.controller
        await sut.start()
        XCTAssertTrue(sut.masterPasswordMissing)

        await sut.recoverFromLostMasterPassword()

        XCTAssertFalse(sut.masterPasswordMissing)
        XCTAssertFalse(sut.session.isSessionLocked)
    }

    /// 忘记主密码必须有出口，否则用户的数据被自己锁死，只能删 App。
    func testForgotMasterPasswordUnlocksAfterDeviceOwnerAuth() async throws {
        let harness = try await makeHarness(
            appLock: true,
            hide: false,
            seconds: 60,
            revealPolicy: .masterPassword,
            masterPassword: "vault-pass-word",
            deviceOwnerAuth: { _, _ in }
        )
        let sut = harness.controller
        await sut.start()
        XCTAssertTrue(sut.session.isSessionLocked)

        await sut.recoverFromLostMasterPassword()

        XCTAssertFalse(sut.session.isSessionLocked)
        XCTAssertNil(sut.unlockError)
        XCTAssertFalse(sut.usesMasterPasswordUnlock)
        let stillSet = try await harness.master.isSet()
        XCTAssertFalse(stillSet)

        // 落到设备密码档而不是「不验证」——取出明文的门闩不得被顺手废掉。
        await harness.preferences.drainPendingWrites()
        let saved = try await harness.preferences.load()
        XCTAssertEqual(saved.revealPolicy, .biometricOrPasscode)
    }

    func testForgotMasterPasswordKeepsLockWhenDeviceOwnerAuthFails() async throws {
        let harness = try await makeHarness(
            appLock: true,
            hide: false,
            seconds: 60,
            revealPolicy: .masterPassword,
            masterPassword: "vault-pass-word",
            deviceOwnerAuth: { _, _ in throw ApiRelayError.authenticationCancelled }
        )
        let sut = harness.controller
        await sut.start()

        await sut.recoverFromLostMasterPassword()

        XCTAssertTrue(sut.session.isSessionLocked)
        XCTAssertTrue(sut.usesMasterPasswordUnlock)
        let stillSet = try await harness.master.isSet()
        XCTAssertTrue(stillSet)
        await harness.preferences.drainPendingWrites()
        let saved = try await harness.preferences.load()
        XCTAssertEqual(saved.revealPolicy, .masterPassword)
    }

    /// 「仅生物识别」但本机没有生物识别 = 死局，必须在锁屏露面之前摆出恢复出口。
    func testStartDetectsUnavailableBiometryForBiometricOnlyPolicy() async throws {
        let harness = try await makeHarness(
            appLock: true,
            hide: false,
            seconds: 60,
            revealPolicy: .biometricOnly,
            biometry: BiometryKind.none,
            deviceOwnerAuth: { _, _ in }
        )
        let sut = harness.controller
        await sut.start()
        XCTAssertTrue(sut.biometryUnavailableForUnlock)
        XCTAssertTrue(sut.session.isSessionLocked)
    }

    func testRecoverFromUnavailableBiometryDowngradesPolicy() async throws {
        let harness = try await makeHarness(
            appLock: true,
            hide: false,
            seconds: 60,
            revealPolicy: .biometricOnly,
            biometry: BiometryKind.none,
            deviceOwnerAuth: { _, _ in }
        )
        let sut = harness.controller
        await sut.start()
        XCTAssertTrue(sut.biometryUnavailableForUnlock)

        await sut.recoverFromUnavailableBiometry()

        XCTAssertFalse(sut.biometryUnavailableForUnlock)
        XCTAssertFalse(sut.session.isSessionLocked)
        await harness.preferences.drainPendingWrites()
        let saved = try await harness.preferences.load()
        XCTAssertEqual(saved.revealPolicy, .biometricOrPasscode)
    }

    private struct Harness {
        let controller: AppPrivacyController
        let master: MasterPasswordService
        let preferences: PreferencesService
    }

    private func makeController(
        appLock: Bool,
        hide: Bool,
        seconds: Int,
        revealPolicy: RevealPolicy = .noVerification,
        masterPassword: String? = nil
    ) async throws -> AppPrivacyController {
        try await makeHarness(
            appLock: appLock,
            hide: hide,
            seconds: seconds,
            revealPolicy: revealPolicy,
            masterPassword: masterPassword
        ).controller
    }

    /// - Parameter deviceOwnerAuth: 为 nil 时任何设备主人验证都判为测试失败——
    ///   主密码档解锁 MUST NOT 弹系统「iPhone 密码」。只有恢复出口的用例才注入它。
    /// - Parameter biometry: 非 nil 时改用 `FakeRevealGate`，以便稳定模拟「无生物识别」死局
    ///   （真机/模拟器的 `LAContext` 结果不稳定）。
    private func makeHarness(
        appLock: Bool,
        hide: Bool,
        seconds: Int,
        revealPolicy: RevealPolicy = .noVerification,
        masterPassword: String? = nil,
        biometry: BiometryKind? = nil,
        deviceOwnerAuth: (@Sendable (String, LAPolicy) async throws -> Void)? = nil
    ) async throws -> Harness {
        let container = try AppSchema.makeInMemoryContainer()
        let preferences = PreferencesService(modelContainer: container)
        var patch = PreferencesPatch()
        patch.appLockEnabled = appLock
        patch.autoLockSeconds = seconds
        patch.hideInAppSwitcher = hide
        patch.revealPolicy = revealPolicy
        try await preferences.update(patch)
        let keychain = KeychainStore.makeForTests()
        let master = MasterPasswordService(keychain: keychain, calibratedIterations: 10_000)
        // 「本机没有主密码」是被测状态之一，不能让上一个用例留下的条目污染。
        try? await master.reset()
        if let masterPassword {
            try await master.setPassword(masterPassword)
        }
        let gate: any RevealGateServing
        if let biometry {
            let fake = FakeRevealGate()
            await fake.setAvailableBiometry(biometry)
            gate = fake
        } else {
            let authenticate = deviceOwnerAuth ?? { _, _ in
                XCTFail("App lock with master-password policy must not present the device passcode prompt")
            }
            gate = RevealGate(masterPassword: master, authenticateDeviceOwner: authenticate)
        }
        let controller = AppPrivacyController(
            gate: gate,
            preferences: preferences,
            masterPassword: master,
            installsSnapshotCover: false,
            enablesUnlockPrompt: false
        )
        return Harness(controller: controller, master: master, preferences: preferences)
    }
}
