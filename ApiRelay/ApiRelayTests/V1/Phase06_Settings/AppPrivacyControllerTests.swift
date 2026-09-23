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

    func testCachedUnlockedWaitsForAuthoritativePreferencesBeforeShowingContent() async throws {
        let sut = try await makeController(appLock: false, hide: true, seconds: 60)
        XCTAssertFalse(sut.session.isPreferencesReady)
        XCTAssertFalse(sut.session.isSessionLocked)
        XCTAssertTrue(sut.session.blocksContent)
        await sut.start()
        XCTAssertTrue(sut.session.isPreferencesReady)
        XCTAssertFalse(sut.session.blocksContent)
    }

    func testBecomeActiveBeforeStartCannotBypassArmedColdStart() async throws {
        let sessionLock = SessionLockBox()
        let sut = try await makeHarness(
            appLock: true,
            hide: true,
            seconds: 0,
            launchAppLockEnabled: false,
            scenePresence: { .userFacing },
            sessionLockBox: sessionLock
        ).controller

        sut.handleDidBecomeActive()
        await Task.yield()
        XCTAssertFalse(sut.session.isPreferencesReady)
        XCTAssertTrue(sut.session.blocksContent, "启动准备期间收到 active 仍须保持中性隐私屏障")
        XCTAssertTrue(sessionLock.isAuthorizationSuspended())

        await sut.start()
        XCTAssertTrue(sut.session.isPreferencesReady)
        XCTAssertTrue(sut.session.isSessionLocked, "持久层已武装时冷启动最终必须上锁")
        XCTAssertFalse(sessionLock.isAuthorizationSuspended())
    }

    func testExternalPolicyRefreshBeforeStartStaysFencedUntilColdStart() async throws {
        let sessionLock = SessionLockBox()
        let sut = try await makeHarness(
            appLock: true,
            hide: true,
            seconds: 0,
            launchAppLockEnabled: false,
            scenePresence: { .userFacing },
            sessionLockBox: sessionLock
        ).controller
        let token = sessionLock.beginExternalSecurityPolicyRefresh()

        let appliedBeforeStart = await sut.reloadSecurityPreferencesAfterExternalImport(token)
        XCTAssertFalse(appliedBeforeStart)
        XCTAssertFalse(sut.session.isPreferencesReady)
        XCTAssertTrue(sessionLock.hasPendingSecurityPolicyRefresh())
        XCTAssertTrue(sessionLock.isAuthorizationSuspended())

        await sut.start()
        XCTAssertTrue(sut.session.isPreferencesReady)
        XCTAssertTrue(sut.session.isSessionLocked)
        XCTAssertFalse(sessionLock.hasPendingSecurityPolicyRefresh())
        XCTAssertFalse(sessionLock.isAuthorizationSuspended())
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

    func testUncachedLaunchUsesNeutralBarrierUntilPreferencesLoad() async throws {
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
            enablesUnlockPrompt: false,
            scenePresence: { .offScreen }
        )
        XCTAssertFalse(sut.session.isPreferencesReady)
        XCTAssertFalse(sut.session.isSessionLocked)
        XCTAssertTrue(sut.session.blocksContent)
        await sut.start()
        XCTAssertTrue(sut.session.isPreferencesReady)
        XCTAssertFalse(sut.session.isSessionLocked)
        XCTAssertFalse(sut.session.blocksContent)
    }

    func testStartWithDefaultsDoesNotLockButHidesInSwitcher() async throws {
        let presence = PresenceBox(initial: .userFacing)
        let sut = try await makeHarness(
            appLock: false,
            hide: true,
            seconds: 60,
            scenePresence: { presence.value }
        ).controller
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
        presence.value = .offScreen
        sut.handleWillResignActive(now: t0.addingTimeInterval(2))
        XCTAssertTrue(sut.session.showsSnapshotCover)
        XCTAssertTrue(sut.session.blocksContent)
        XCTAssertFalse(sut.session.showsAppLockUI)
        presence.value = .userFacing
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

    func testMasterPasswordCancellationIsNotReportedAsWrongPassword() async throws {
        let harness = try await makeHarness(
            appLock: true,
            hide: false,
            seconds: 60,
            revealPolicy: .masterPassword,
            masterPassword: "vault-pass-word",
            biometry: .faceID
        )
        let fake = try XCTUnwrap(harness.fakeGate)
        await fake.fail("confirmWithMasterPassword", with: .authenticationCancelled)
        await harness.controller.start()

        await harness.controller.unlockWithMasterPassword("vault-pass-word")

        XCTAssertTrue(harness.controller.session.isSessionLocked)
        XCTAssertEqual(harness.controller.unlockError, String(localized: "appLock.unlockInterrupted"))
        XCTAssertNotEqual(harness.controller.unlockError, String(localized: "appLock.masterPassword.incorrect"))
    }

    func testMasterPasswordOperationalFailuresKeepTheirRealMessage() async throws {
        for error: ApiRelayError in [
            .masterPasswordRetryDelayed(secondsRemaining: 8),
            .keychainFailure(-50),
        ] {
            let harness = try await makeHarness(
                appLock: true,
                hide: false,
                seconds: 60,
                revealPolicy: .masterPassword,
                masterPassword: "vault-pass-word",
                biometry: .faceID
            )
            let fake = try XCTUnwrap(harness.fakeGate)
            await fake.fail("confirmWithMasterPassword", with: error)
            await harness.controller.start()

            await harness.controller.unlockWithMasterPassword("vault-pass-word")

            XCTAssertTrue(harness.controller.session.isSessionLocked)
            XCTAssertEqual(harness.controller.unlockError, error.localizedDescription)
            XCTAssertNotEqual(harness.controller.unlockError, String(localized: "appLock.masterPassword.incorrect"))
        }
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
        XCTAssertTrue(sut.session.isSessionLocked)
        XCTAssertNotEqual(sut.session.preferences.revealPolicy, .noVerification)
    }

    /// 忘记主密码必须有出口，否则用户的数据被自己锁死，只能删 App。
    /// 恢复成功后仍保持锁态，由用户用新的设备验证再解锁。
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

        XCTAssertTrue(sut.session.isSessionLocked)
        XCTAssertNil(sut.unlockError)
        XCTAssertFalse(sut.usesMasterPasswordUnlock)
        let stillSet = try await harness.master.isSet()
        XCTAssertFalse(stillSet)

        // 落到设备密码档而不是「不验证」——取出明文的门闩不得被顺手废掉。
        await harness.preferences.drainPendingWrites()
        let saved = try await harness.preferences.load()
        XCTAssertEqual(saved.revealPolicy, .biometricOrPasscode)
    }

    func testDeviceUnlockSuccessDoesNotRelockOnSystemSheetActivationNotifications() async throws {
        let harness = try await makeHarness(appLock: true, hide: true, seconds: 0,
            deviceOwnerAuth: { _, _ in }, scenePresence: { .userFacing })
        let sut = harness.controller
        await sut.start()
        sut.handleDidBecomeActive()
        XCTAssertTrue(sut.session.isSessionLocked)
        sut.handleWillResignActive()
        await sut.promptUnlock(force: true)
        XCTAssertFalse(sut.session.isSessionLocked)
        for _ in 0..<3 { sut.handleDidBecomeActive() }
        XCTAssertFalse(sut.session.isSessionLocked)
        XCTAssertFalse(sut.session.needsUnlockPrompt)
    }

    func testDeviceUnlockInterruptionKeepsLockAndExplainsWhy() async throws {
        let harness = try await makeHarness(appLock: true, hide: false, seconds: 0,
            deviceOwnerAuth: { _, _ in throw ApiRelayError.authenticationCancelled },
            scenePresence: { .userFacing })
        let sut = harness.controller
        await sut.start()
        sut.handleDidBecomeActive()
        await sut.promptUnlock(force: true)
        XCTAssertTrue(sut.session.isSessionLocked)
        XCTAssertEqual(sut.unlockError, String(localized: "appLock.unlockInterrupted"))
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

    func testForgotMasterPasswordBackgroundDuringDeviceOwnerDoesNotPersistOrDelete() async throws {
        AppLockLaunchCache.write(true)
        let prefs = FakePreferences()
        try await prefs.update(PreferencesPatch(
            appLockEnabled: true,
            revealPolicy: .masterPassword
        ))
        let master = FakeMasterPassword()
        try await master.setPassword("vault-pass-word")
        let gate = FakeRevealGate()
        let sut = AppPrivacyController(
            gate: gate,
            preferences: prefs,
            masterPassword: master,
            installsSnapshotCover: false,
            enablesUnlockPrompt: false,
            launchAppLockEnabled: true,
            scenePresence: { .offScreen }
        )
        await sut.start()
        await gate.setConfirmMandatoryHook {
            await MainActor.run {
                sut.handleDidEnterBackground()
            }
        }
        await sut.recoverFromLostMasterPassword()
        XCTAssertTrue(sut.session.isSessionLocked)
        XCTAssertTrue(sut.usesMasterPasswordUnlock)
        let stillSet = try await master.isSet()
        XCTAssertTrue(stillSet)
        XCTAssertEqual(prefs.persistWriteCount(), 0)
        let stored = try await prefs.load()
        XCTAssertEqual(stored.revealPolicy, .masterPassword)
        XCTAssertNotEqual(stored.revealPolicy, .noVerification)
    }

    func testForgotMasterPasswordMacAppSwitchDuringDeviceOwnerDoesNotPersistOrDelete() async throws {
        AppLockLaunchCache.write(true)
        let prefs = FakePreferences()
        try await prefs.update(PreferencesPatch(
            appLockEnabled: true,
            revealPolicy: .masterPassword
        ))
        let master = FakeMasterPassword()
        try await master.setPassword("vault-pass-word")
        let gate = FakeRevealGate()
        let presence = PresenceBox(initial: .userFacing)
        let sut = AppPrivacyController(
            gate: gate,
            preferences: prefs,
            masterPassword: master,
            installsSnapshotCover: false,
            enablesUnlockPrompt: false,
            launchAppLockEnabled: true,
            treatsApplicationResignAsBackground: true,
            scenePresence: { presence.value }
        )
        await sut.start()
        await gate.setConfirmMandatoryHook {
            await MainActor.run {
                presence.value = .offScreen
                sut.handleWillResignActive()
            }
        }

        await sut.recoverFromLostMasterPassword()

        XCTAssertTrue(sut.session.isSessionLocked)
        XCTAssertTrue(sut.usesMasterPasswordUnlock)
        let stillSet = try await master.isSet()
        XCTAssertTrue(stillSet)
        XCTAssertEqual(prefs.persistWriteCount(), 0)
        let stored = try await prefs.load()
        XCTAssertEqual(stored.revealPolicy, .masterPassword)
    }

    func testForgotMasterPasswordMacResignAfterAuthorizationBeforeCommitDoesNotPersistOrDelete() async throws {
        AppLockLaunchCache.write(true)
        let prefs = FakePreferences()
        try await prefs.update(PreferencesPatch(
            appLockEnabled: true,
            revealPolicy: .masterPassword
        ))
        let master = FakeMasterPassword()
        try await master.setPassword("vault-pass-word")
        let gate = FakeRevealGate()
        let presence = PresenceBox(initial: .userFacing)
        let sut = AppPrivacyController(
            gate: gate,
            preferences: prefs,
            masterPassword: master,
            installsSnapshotCover: false,
            enablesUnlockPrompt: false,
            launchAppLockEnabled: true,
            treatsApplicationResignAsBackground: true,
            scenePresence: { presence.value }
        )
        await sut.start()

        let persistEntered = AsyncStream<Void>.makeStream()
        let allowPersist = AsyncStream<Void>.makeStream()
        // This seam is reached only after the final async `authorizing` call.
        // Releasing it attempts the repository-equivalent synchronous commit.
        await prefs.setPersistFinalCommitDelay {
            persistEntered.continuation.yield(())
            for await _ in allowPersist.stream { break }
        }
        var enteredIterator = persistEntered.stream.makeAsyncIterator()
        let recovery = Task { await sut.recoverFromLostMasterPassword() }
        _ = await enteredIterator.next()

        presence.value = .offScreen
        sut.handleWillResignActive()
        allowPersist.continuation.yield(())
        allowPersist.continuation.finish()
        await recovery.value
        persistEntered.continuation.finish()

        XCTAssertTrue(sut.session.isSessionLocked)
        XCTAssertTrue(sut.usesMasterPasswordUnlock)
        let materialWasKept = try await master.isSet()
        XCTAssertTrue(materialWasKept, "离前台后不得删除应用密码材料")
        XCTAssertEqual(prefs.persistWriteCount(), 0)
        let stored = try await prefs.load()
        XCTAssertEqual(stored.revealPolicy, .masterPassword)
    }

    func testUnavailableBiometryMacResignAfterAuthorizationBeforeCommitDoesNotPersistOrUnlock() async throws {
        AppLockLaunchCache.write(true)
        let prefs = FakePreferences()
        try await prefs.update(PreferencesPatch(
            appLockEnabled: true,
            revealPolicy: .biometryOrAppPassword
        ))
        let gate = FakeRevealGate()
        let master = FakeMasterPassword()
        let presence = PresenceBox(initial: .userFacing)
        let sut = AppPrivacyController(
            gate: gate,
            preferences: prefs,
            masterPassword: master,
            installsSnapshotCover: false,
            enablesUnlockPrompt: false,
            launchAppLockEnabled: true,
            treatsApplicationResignAsBackground: true,
            scenePresence: { presence.value }
        )
        await sut.start()

        let persistEntered = AsyncStream<Void>.makeStream()
        let allowPersist = AsyncStream<Void>.makeStream()
        // Authentication and both service-level authorization checks have passed.
        await prefs.setPersistFinalCommitDelay {
            persistEntered.continuation.yield(())
            for await _ in allowPersist.stream { break }
        }
        var enteredIterator = persistEntered.stream.makeAsyncIterator()
        let recovery = Task { await sut.recoverFromUnavailableBiometry() }
        _ = await enteredIterator.next()

        presence.value = .offScreen
        sut.handleWillResignActive()
        allowPersist.continuation.yield(())
        allowPersist.continuation.finish()
        await recovery.value
        persistEntered.continuation.finish()

        XCTAssertTrue(sut.session.isSessionLocked, "离前台后不得 finishUnlockSucceeded")
        XCTAssertTrue(sut.usesCombinationUnlock)
        XCTAssertEqual(prefs.persistWriteCount(), 0)
        let stored = try await prefs.load()
        XCTAssertEqual(stored.revealPolicy, .biometryOrAppPassword)
    }

    func testIPadOnScreenIdleAfterAuthorizationBeforeCommitRevokesRecoveryAndSessionLeases() async throws {
        AppLockLaunchCache.write(true)
        let prefs = FakePreferences()
        try await prefs.update(PreferencesPatch(
            appLockEnabled: true,
            revealPolicy: .masterPassword
        ))
        let master = FakeMasterPassword()
        try await master.setPassword("vault-pass-word")
        let gate = FakeRevealGate()
        let presence = PresenceBox(initial: .userFacing)
        let sessionLock = SessionLockBox()
        let sut = AppPrivacyController(
            gate: gate,
            preferences: prefs,
            masterPassword: master,
            installsSnapshotCover: false,
            enablesUnlockPrompt: false,
            launchAppLockEnabled: true,
            treatsApplicationResignAsBackground: false,
            scenePresence: { presence.value },
            sessionLockBox: sessionLock
        )
        await sut.start()

        // The controller is intentionally on its lock screen. Open only the test
        // box long enough to prove the focus transition advances its generation.
        sessionLock.setLocked(false)
        let oldSessionLease = try sessionLock.captureAuthorizationLease()

        let persistEntered = AsyncStream<Void>.makeStream()
        let allowPersist = AsyncStream<Void>.makeStream()
        await prefs.setPersistFinalCommitDelay {
            persistEntered.continuation.yield(())
            for await _ in allowPersist.stream { break }
        }
        var enteredIterator = persistEntered.stream.makeAsyncIterator()
        let recovery = Task { await sut.recoverFromLostMasterPassword() }
        _ = await enteredIterator.next()

        // Authentication is over, but Stage Manager focus is now on another
        // app in the same on-screen group. The queued repository commit must lose.
        presence.value = .onScreenIdle
        sut.handleHostFocusDidChange()
        XCTAssertThrowsError(try sessionLock.validateAuthorizationLease(oldSessionLease))
        XCTAssertThrowsError(
            try sessionLock.captureAuthorizationLease(),
            "an idle Stage Manager window must not mint a fresh lease during the lock grace period"
        )

        allowPersist.continuation.yield(())
        allowPersist.continuation.finish()
        await recovery.value
        persistEntered.continuation.finish()

        XCTAssertEqual(prefs.persistWriteCount(), 0)
        let stored = try await prefs.load()
        XCTAssertEqual(stored.revealPolicy, .masterPassword)
        let materialKept = try await master.verify("vault-pass-word")
        XCTAssertTrue(materialKept, "闲置后不得删应用密码材料")
        let journal = await master.journal
        XCTAssertFalse(journal.didCall("reset"))
    }

    func testReturningUserFacingResumesNewLeasesWithoutRevivingOldLease() throws {
        let sessionLock = SessionLockBox()
        let oldLease = try sessionLock.captureAuthorizationLease()

        sessionLock.setAuthorizationSuspended(true)
        XCTAssertTrue(sessionLock.isAuthorizationSuspended())
        XCTAssertThrowsError(try sessionLock.validateAuthorizationLease(oldLease))
        XCTAssertThrowsError(try sessionLock.captureAuthorizationLease())

        sessionLock.setAuthorizationSuspended(false)
        XCTAssertFalse(sessionLock.isAuthorizationSuspended())
        XCTAssertThrowsError(try sessionLock.validateAuthorizationLease(oldLease))
        XCTAssertNoThrow(try sessionLock.captureAuthorizationLease())
    }

    func testIPadTransientAuthenticationFocusLossWaitsThenRevokesIfStillIdle() async throws {
        let prefs = FakePreferences()
        let gate = FakeRevealGate()
        let master = FakeMasterPassword()
        let presence = PresenceBox(initial: .userFacing)
        let sessionLock = SessionLockBox()
        let sut = AppPrivacyController(
            gate: gate,
            preferences: prefs,
            masterPassword: master,
            installsSnapshotCover: false,
            enablesUnlockPrompt: false,
            launchAppLockEnabled: false,
            treatsApplicationResignAsBackground: false,
            scenePresence: { presence.value },
            sessionLockBox: sessionLock
        )
        await sut.start()
        let lease = try sessionLock.captureAuthorizationLease()

        await gate.setAuthenticationInProgress(true, owner: .content)
        presence.value = .onScreenIdle
        sut.handleHostFocusDidChange()
        XCTAssertNoThrow(try sessionLock.validateAuthorizationLease(lease), "系统认证瞬时失焦不能提前撤销")

        await gate.setAuthenticationInProgress(false, owner: .content)
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertThrowsError(try sessionLock.validateAuthorizationLease(lease), "认证收口后仍闲置必须撤销")
    }

    /// 设备验证缺生物识别不是死局：可回落本机密码。
    func testDeviceAuthDoesNotTreatMissingBiometryAsDeadEnd() async throws {
        let harness = try await makeHarness(
            appLock: true,
            hide: false,
            seconds: 60,
            revealPolicy: .biometricOrPasscode,
            biometry: BiometryKind.none,
            deviceOwnerAuth: { _, _ in }
        )
        let sut = harness.controller
        await sut.start()
        XCTAssertFalse(sut.biometryUnavailableForUnlock)
        XCTAssertTrue(sut.session.isSessionLocked)
    }

    func testLoadFailureKeepsCachedLockAndDoesNotDisableCache() async throws {
        AppLockLaunchCache.write(true)
        let prefs = FakePreferences()
        await prefs.setLoadError(ApiRelayError.networkUnavailable)
        let keychain = KeychainStore.makeForTests()
        let master = MasterPasswordService(keychain: keychain, calibratedIterations: 10_000)
        try? await master.reset()
        let sut = AppPrivacyController(
            gate: RevealGate(masterPassword: master, authenticateDeviceOwner: { _, _ in }),
            preferences: prefs,
            masterPassword: master,
            installsSnapshotCover: false,
            enablesUnlockPrompt: false
        )
        XCTAssertTrue(sut.session.isSessionLocked)
        await sut.start()
        XCTAssertTrue(sut.securityPreferencesUnavailable)
        XCTAssertTrue(sut.session.isSessionLocked, "读失败不得按默认关锁放行")
        XCTAssertEqual(AppLockLaunchCache.read(), true)
    }

    func testPhoneResignDoesNotImmediateLockUntilBackground() async throws {
        let presence = PresenceBox(initial: .userFacing)
        let sut = try await makeHarness(
            appLock: false,
            hide: false,
            seconds: 0,
            scenePresence: { presence.value }
        ).controller
        await sut.start()
        sut.applyLivePreferences(AppLockPreferences(
            appLockEnabled: true,
            autoLockSeconds: 0,
            hideInAppSwitcher: false,
            revealPolicy: .biometricOrPasscode
        ))
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        sut.handleDidBecomeActive(now: t0)
        XCTAssertFalse(sut.session.isSessionLocked)
        sut.handleWillResignActive(now: t0.addingTimeInterval(2))
        XCTAssertFalse(sut.session.isSessionLocked, "iPhone：resign 不是离开，控制中心不得立即锁")
        XCTAssertFalse(sut.session.isInactive)
        presence.value = .offScreen
        sut.handleDidEnterBackground(now: t0.addingTimeInterval(2.1))
        XCTAssertTrue(sut.session.isSessionLocked)
    }

    func testOffScreenResignLocksImmediatelyWhenRapidReturnCancelsBackgroundNotifications() async throws {
        let presence = PresenceBox(initial: .userFacing)
        let harness = try await makeHarness(
            appLock: false,
            hide: true,
            seconds: 0,
            scenePresence: { presence.value },
            hasForegroundActiveScene: { false },
            hasForegroundInactiveSceneWithoutActiveAppearance: { true }
        )
        let sut = harness.controller
        await sut.start()
        try await persistAndApply(AppLockPreferences(
            appLockEnabled: true,
            autoLockSeconds: 0,
            hideInAppSwitcher: true,
            revealPolicy: .biometricOrPasscode
        ), to: harness)
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        sut.handleDidBecomeActive(now: t0)

        // Strong-signal variant: every scene is already known to be off-screen,
        // so the controller must not wait for a redundant background callback.
        presence.value = .offScreen
        sut.handleWillResignActive(now: t0.addingTimeInterval(0.1))
        XCTAssertTrue(sut.session.isSessionLocked)
        XCTAssertTrue(sut.session.blocksContent)
        XCTAssertNotNil(sut.session.lastLeftMonotonic)

        presence.value = .userFacing
        sut.handleDidBecomeActive(now: t0.addingTimeInterval(0.2))
        XCTAssertTrue(sut.session.isSessionLocked)
        XCTAssertTrue(sut.session.needsUnlockPrompt)
    }

    func testImmediateNonUserFacingResignLocksBeforeRapidDidBecomeActive() async throws {
        let presence = PresenceBox(initial: .userFacing)
        let inactiveAppearance = BoolBox(initial: false)
        let harness = try await makeHarness(
            appLock: false,
            hide: true,
            seconds: 0,
            scenePresence: { presence.value },
            hasForegroundActiveScene: { false },
            hasForegroundInactiveSceneWithoutActiveAppearance: { inactiveAppearance.value }
        )
        let sut = harness.controller
        await sut.start()
        try await persistAndApply(AppLockPreferences(
            appLockEnabled: true,
            autoLockSeconds: 0,
            hideInAppSwitcher: true,
            revealPolicy: .biometricOrPasscode
        ), to: harness)
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        sut.handleDidBecomeActive(now: t0)

        // The real iPad reports the first Home frame exactly like Control Center:
        // user-facing with active appearance. A later raw trait is the first
        // trustworthy distinction.
        sut.handleWillResignActive(now: t0.addingTimeInterval(0.1))
        XCTAssertFalse(sut.session.isSessionLocked, "the first resign frame is still ambiguous")
        XCTAssertEqual(
            sut.windowPrivacy.coveredIDs,
            [WindowPrivacyInput.syntheticProcessID],
            "hide-in-switcher must cover the real user-facing first frame synchronously"
        )

        inactiveAppearance.value = true
        sut.handleHostFocusDidChange()
        XCTAssertTrue(sut.session.isSessionLocked, "a later inactive appearance confirms the Home transition")
        XCTAssertEqual(sut.windowPrivacy.coveredIDs, [WindowPrivacyInput.syntheticProcessID])

        presence.value = .userFacing
        sut.handleDidBecomeActive(now: t0.addingTimeInterval(0.2))
        XCTAssertTrue(sut.session.isSessionLocked)
        XCTAssertTrue(sut.session.needsUnlockPrompt)
        XCTAssertNotNil(sut.session.lastLeftMonotonic)
    }

    func testQualifiedRapidHomeResignLocksWhenForegroundNotificationIsAlsoOmitted() async throws {
        let presence = PresenceBox(initial: .userFacing)
        let inactiveAppearance = BoolBox(initial: false)
        let harness = try await makeHarness(
            appLock: false,
            hide: true,
            seconds: 0,
            scenePresence: { presence.value },
            hasForegroundActiveScene: { false },
            hasForegroundInactiveSceneWithoutActiveAppearance: { inactiveAppearance.value }
        )
        let sut = harness.controller
        await sut.start()
        try await persistAndApply(AppLockPreferences(
            appLockEnabled: true,
            autoLockSeconds: 0,
            hideInAppSwitcher: true,
            revealPolicy: .biometricOrPasscode
        ), to: harness)
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        sut.handleDidBecomeActive(now: t0)

        sut.handleWillResignActive(now: t0.addingTimeInterval(0.1))
        XCTAssertFalse(sut.session.isSessionLocked)

        // Some iPad transitions do not deliver a trait callback. The bounded
        // probe must observe the later raw scene appearance by itself.
        inactiveAppearance.value = true
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertTrue(sut.session.isSessionLocked)

        presence.value = .userFacing
        sut.handleDidBecomeActive(now: t0.addingTimeInterval(0.2))

        XCTAssertTrue(sut.session.isSessionLocked)
        XCTAssertTrue(sut.session.needsUnlockPrompt)
    }

    func testSameStageResignDoesNotLockOrCover() async throws {
        let presence = PresenceBox(initial: .onScreenIdle)
        let harness = try await makeHarness(
            appLock: false,
            hide: true,
            seconds: 0,
            scenePresence: { presence.value },
            hasForegroundActiveScene: { true }
        )
        let sut = harness.controller
        await sut.start()
        try await persistAndApply(AppLockPreferences(
            appLockEnabled: true,
            autoLockSeconds: 0,
            hideInAppSwitcher: true,
            revealPolicy: .biometricOrPasscode
        ), to: harness)
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        sut.handleDidBecomeActive(now: t0)
        sut.handleWillResignActive(now: t0.addingTimeInterval(2))
        XCTAssertFalse(sut.session.isSessionLocked, "iPad 台前同一组里点别的软件：窗还在，不得锁")
        XCTAssertFalse(sut.session.isInactive, "也不得盖成只有锁图标的白屏")
        XCTAssertFalse(sut.session.showsSnapshotCover)
        XCTAssertFalse(sut.session.needsUnlockPrompt)
        XCTAssertNil(sut.session.lastLeftMonotonic, "同组闲置不得开始自动锁计时")

        presence.value = .userFacing
        sut.handleDidBecomeActive(now: t0.addingTimeInterval(2.1))
        XCTAssertFalse(sut.session.isSessionLocked, "同组往返不得被快速 Home 补偿误锁")
        XCTAssertNil(sut.session.lastLeftMonotonic)
    }

    func testControlCenterLikeInactiveSceneDoesNotArmRapidHomeLock() async throws {
        let presence = PresenceBox(initial: .userFacing)
        let inactiveAppearance = BoolBox(initial: false)
        let harness = try await makeHarness(
            appLock: false,
            hide: true,
            seconds: 0,
            scenePresence: { presence.value },
            hasForegroundActiveScene: { false },
            hasForegroundInactiveSceneWithoutActiveAppearance: { inactiveAppearance.value }
        )
        let sut = harness.controller
        await sut.start()
        try await persistAndApply(AppLockPreferences(
            appLockEnabled: true,
            autoLockSeconds: 0,
            hideInAppSwitcher: true,
            revealPolicy: .biometricOrPasscode
        ), to: harness)
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        sut.handleDidBecomeActive(now: t0)

        // A system overlay may make the scene foreground-inactive, but the host
        // window keeps active appearance. That is not a Home departure.
        sut.handleWillResignActive(now: t0.addingTimeInterval(0.1))
        XCTAssertEqual(sut.windowPrivacy.coveredIDs, [WindowPrivacyInput.syntheticProcessID])
        presence.value = .userFacing
        sut.handleDidBecomeActive(now: t0.addingTimeInterval(0.2))

        // Even if a stale trait callback arrives after the active edge, the old
        // probe generation is already invalid and must never lock this cycle.
        inactiveAppearance.value = true
        sut.handleHostFocusDidChange()
        try await Task.sleep(for: .milliseconds(80))

        XCTAssertFalse(sut.session.isSessionLocked)
        XCTAssertNil(sut.session.lastLeftMonotonic)
        XCTAssertTrue(sut.windowPrivacy.coveredIDs.isEmpty)
    }

    func testAmbiguousResignFenceIsReversibleForControlCenter() async throws {
        let presence = PresenceBox(initial: .userFacing)
        let sessionLock = SessionLockBox()
        let harness = try await makeHarness(
            appLock: false,
            hide: true,
            seconds: 0,
            scenePresence: { presence.value },
            hasForegroundActiveScene: { false },
            hasForegroundInactiveSceneWithoutActiveAppearance: { false },
            sessionLockBox: sessionLock
        )
        let sut = harness.controller
        await sut.start()
        try await persistAndApply(AppLockPreferences(
            appLockEnabled: true,
            autoLockSeconds: 0,
            hideInAppSwitcher: true,
            revealPolicy: .biometricOrPasscode
        ), to: harness)
        let lease = try sessionLock.captureAuthorizationLease()

        sut.handleWillResignActive(now: Date(timeIntervalSince1970: 1_700_000_000))

        XCTAssertTrue(sessionLock.isAuthorizationProvisionallyFenced())
        XCTAssertThrowsError(try sessionLock.validateAuthorizationLease(lease))
        XCTAssertEqual(sut.windowPrivacy.coveredIDs, [WindowPrivacyInput.syntheticProcessID])

        sut.handleDidBecomeActive(now: Date(timeIntervalSince1970: 1_700_000_000.2))

        XCTAssertFalse(sessionLock.isAuthorizationProvisionallyFenced())
        XCTAssertNoThrow(try sessionLock.validateAuthorizationLease(lease))
        XCTAssertFalse(sut.session.isSessionLocked)
        XCTAssertTrue(sut.windowPrivacy.coveredIDs.isEmpty)
    }

    func testImmediateResignProbeRejectsRawEvidenceAfterAbsoluteDeadline() async throws {
        let presence = PresenceBox(initial: .userFacing)
        let inactiveAppearance = BoolBox(initial: false)
        let uptime = TimeBox(initial: 100)
        let harness = try await makeHarness(
            appLock: false,
            hide: true,
            seconds: 0,
            scenePresence: { presence.value },
            hasForegroundActiveScene: { false },
            hasForegroundInactiveSceneWithoutActiveAppearance: { inactiveAppearance.value },
            monotonicUptime: { uptime.value }
        )
        let sut = harness.controller
        await sut.start()
        try await persistAndApply(AppLockPreferences(
            appLockEnabled: true,
            autoLockSeconds: 0,
            hideInAppSwitcher: true,
            revealPolicy: .biometricOrPasscode
        ), to: harness)
        sut.handleWillResignActive(now: Date(timeIntervalSince1970: 1_700_000_000))

        uptime.value = 102.001
        inactiveAppearance.value = true
        sut.handleHostFocusDidChange()

        XCTAssertFalse(sut.session.isSessionLocked, "late trait evidence must not extend the probe window")
        XCTAssertNil(sut.session.lastLeftMonotonic)
        sut.handleDidBecomeActive(now: Date(timeIntervalSince1970: 1_700_000_003))
        XCTAssertFalse(sut.session.isSessionLocked)
    }

    func testImmediateResignProbeStopsWhenAuthenticationStarts() async throws {
        let presence = PresenceBox(initial: .userFacing)
        let inactiveAppearance = BoolBox(initial: false)
        let harness = try await makeHarness(
            appLock: false,
            hide: true,
            seconds: 0,
            biometry: .faceID,
            scenePresence: { presence.value },
            hasForegroundActiveScene: { false },
            hasForegroundInactiveSceneWithoutActiveAppearance: { inactiveAppearance.value }
        )
        let sut = harness.controller
        let gate = try XCTUnwrap(harness.fakeGate)
        await sut.start()
        try await persistAndApply(AppLockPreferences(
            appLockEnabled: true,
            autoLockSeconds: 0,
            hideInAppSwitcher: true,
            revealPolicy: .biometricOrPasscode
        ), to: harness)
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        sut.handleDidBecomeActive(now: t0)
        presence.value = .onScreenIdle
        sut.handleWillResignActive(now: t0.addingTimeInterval(0.1))

        await gate.setAuthenticationInProgress(true)
        inactiveAppearance.value = true
        try await Task.sleep(for: .milliseconds(80))

        XCTAssertFalse(sut.session.isSessionLocked, "Face ID must cancel the ambiguous Home probe")
        XCTAssertNil(sut.session.lastLeftMonotonic)
    }

    func testImmediateResignProbeStopsWhenPolicyChangesAwayFromImmediate() async throws {
        let presence = PresenceBox(initial: .userFacing)
        let inactiveAppearance = BoolBox(initial: false)
        let harness = try await makeHarness(
            appLock: false,
            hide: true,
            seconds: 0,
            scenePresence: { presence.value },
            hasForegroundActiveScene: { false },
            hasForegroundInactiveSceneWithoutActiveAppearance: { inactiveAppearance.value }
        )
        let sut = harness.controller
        await sut.start()
        try await persistAndApply(AppLockPreferences(
            appLockEnabled: true,
            autoLockSeconds: 0,
            hideInAppSwitcher: true,
            revealPolicy: .biometricOrPasscode
        ), to: harness)
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        sut.handleDidBecomeActive(now: t0)
        presence.value = .onScreenIdle
        sut.handleWillResignActive(now: t0.addingTimeInterval(0.1))

        try await persistAndApply(AppLockPreferences(
            appLockEnabled: true,
            autoLockSeconds: 60,
            hideInAppSwitcher: true,
            revealPolicy: .biometricOrPasscode
        ), to: harness)
        inactiveAppearance.value = true
        try await Task.sleep(for: .milliseconds(80))

        XCTAssertFalse(sut.session.isSessionLocked)
        XCTAssertNil(sut.session.lastLeftMonotonic)
    }

    func testUserFacingResignDoesNotCoverOrLock() async throws {
        let sut = try await makeHarness(
            appLock: false,
            hide: true,
            seconds: 0,
            scenePresence: { .userFacing }
        ).controller
        await sut.start()
        sut.applyLivePreferences(AppLockPreferences(
            appLockEnabled: true,
            autoLockSeconds: 0,
            hideInAppSwitcher: true,
            revealPolicy: .biometricOrPasscode
        ))
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        sut.handleDidBecomeActive(now: t0)
        sut.handleWillResignActive(now: t0.addingTimeInterval(2))
        XCTAssertFalse(sut.session.isSessionLocked, "控制中心 / 验证框抢前台不得锁")
        XCTAssertFalse(sut.session.isInactive)
        XCTAssertFalse(sut.session.showsSnapshotCover)
        XCTAssertNil(sut.session.lastLeftMonotonic)
        sut.handleDidBecomeActive(now: t0.addingTimeInterval(2.1))
        XCTAssertFalse(sut.session.isSessionLocked)
        XCTAssertFalse(sut.session.showsSnapshotCover)
    }

    func testAuthenticationInProgressDoesNotCancelOnIdleFocusChange() async throws {
        let container = try AppSchema.makeInMemoryContainer()
        var patch = PreferencesPatch()
        patch.appLockEnabled = true
        patch.autoLockSeconds = 0
        patch.hideInAppSwitcher = false
        let preferences = PreferencesService(modelContainer: container)
        try await preferences.update(patch)
        let keychain = KeychainStore.makeForTests()
        let master = MasterPasswordService(keychain: keychain, calibratedIterations: 10_000)
        try? await master.reset()
        let gate = FakeRevealGate()
        let presence = PresenceBox(initial: .userFacing)
        let sut = AppPrivacyController(
            gate: gate,
            preferences: preferences,
            masterPassword: master,
            installsSnapshotCover: false,
            enablesUnlockPrompt: false,
            scenePresence: { presence.value }
        )
        await sut.start()
        sut.handleDidBecomeActive()
        await gate.setAuthenticationInProgress(true)
        presence.value = .onScreenIdle
        sut.handleHostFocusDidChange()
        let cancelledWhileAuthenticating = await gate.cancelCallCount()
        XCTAssertEqual(cancelledWhileAuthenticating, 0, "验证进行中不得当闲置去 cancel")
        await gate.setAuthenticationInProgress(false)
        sut.handleHostFocusDidChange()
        let cancelledWhenIdle = await gate.cancelCallCount()
        XCTAssertEqual(cancelledWhenIdle, 1, "已确认闲置且未在验证则必须 cancel")
    }

    func testSameGroupUnfocusFromSignalsDoesNotLock() async throws {
        let safari = AppLockScenePresence.resolve(
            ScenePresenceSignals.known(
                sceneIsForegroundActive: true,
                sceneIsForegroundInactive: false,
                applicationIsActive: true,
                isKeyWindow: false,
                activeAppearanceIsActive: false
            )
        )
        XCTAssertEqual(safari, .onScreenIdle)
        let sut = try await makeHarness(
            appLock: false,
            hide: true,
            seconds: 0,
            scenePresence: { safari }
        ).controller
        await sut.start()
        sut.applyLivePreferences(AppLockPreferences(
            appLockEnabled: true,
            autoLockSeconds: 0,
            hideInAppSwitcher: true,
            revealPolicy: .biometricOrPasscode
        ))
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        sut.handleDidBecomeActive(now: t0)
        sut.handleWillResignActive(now: t0.addingTimeInterval(2))
        XCTAssertFalse(sut.session.isSessionLocked, "T-W3：同组失焦无验证框不得锁")
        XCTAssertNil(sut.session.lastLeftMonotonic)
    }

    func testAuthInProgressFromSignalsDoesNotCancelWhenKeyStolen() async throws {
        let container = try AppSchema.makeInMemoryContainer()
        var patch = PreferencesPatch()
        patch.appLockEnabled = true
        let preferences = PreferencesService(modelContainer: container)
        try await preferences.update(patch)
        let keychain = KeychainStore.makeForTests()
        let master = MasterPasswordService(keychain: keychain, calibratedIterations: 10_000)
        try? await master.reset()
        let gate = FakeRevealGate()
        let auth = AuthBox()
        let sut = AppPrivacyController(
            gate: gate,
            preferences: preferences,
            masterPassword: master,
            installsSnapshotCover: false,
            enablesUnlockPrompt: false,
            scenePresence: {
                AppLockScenePresence.resolve(
                    ScenePresenceSignals.known(
                        sceneIsForegroundActive: true,
                        sceneIsForegroundInactive: false,
                        applicationIsActive: true,
                        isKeyWindow: false,
                        activeAppearanceIsActive: nil,
                        authenticationInProgress: auth.value
                    )
                )
            }
        )
        await sut.start()
        sut.handleDidBecomeActive()
        await gate.setAuthenticationInProgress(true)
        auth.value = true
        sut.handleHostFocusDidChange()
        let cancelled = await gate.cancelCallCount()
        XCTAssertEqual(cancelled, 0, "T-W3：状态 C 抢走 Key 不得 cancel")
    }

    func testSameStageBackgroundDoesNotLockOrCover() async throws {
        let sut = try await makeHarness(
            appLock: false,
            hide: true,
            seconds: 0,
            scenePresence: { .onScreenIdle }
        ).controller
        await sut.start()
        sut.applyLivePreferences(AppLockPreferences(
            appLockEnabled: true,
            autoLockSeconds: 0,
            hideInAppSwitcher: true,
            revealPolicy: .biometricOrPasscode
        ))
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        sut.handleDidBecomeActive(now: t0)
        sut.handleWillResignActive(now: t0.addingTimeInterval(2))
        sut.handleDidEnterBackground(now: t0.addingTimeInterval(2.1))
        XCTAssertFalse(sut.session.isSessionLocked, "iPad 同组误发 background 时窗还在，不得锁")
        XCTAssertFalse(sut.session.isInactive)
        XCTAssertFalse(sut.session.showsSnapshotCover)
        XCTAssertFalse(sut.shouldAutomaticallyPromptUnlock())

        // A transient/spurious background notification without the paired
        // will-enter-foreground event is not a completed leave/return cycle.
        sut.handleDidBecomeActive(now: t0.addingTimeInterval(2.2))
        XCTAssertFalse(sut.session.isSessionLocked)
        XCTAssertNil(sut.session.lastLeftMonotonic)
    }

    func testRapidReturnFinalizesPendingApplicationBackgroundBeforeReveal() async throws {
        let presence = PresenceBox(initial: .userFacing)
        let sut = try await makeHarness(
            appLock: false,
            hide: true,
            seconds: 0,
            scenePresence: { presence.value },
            hasForegroundActiveScene: { false }
        ).controller
        await sut.start()
        sut.applyLivePreferences(AppLockPreferences(
            appLockEnabled: true,
            autoLockSeconds: 0,
            hideInAppSwitcher: true,
            revealPolicy: .biometricOrPasscode
        ))
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        sut.handleDidBecomeActive(now: t0)

        // iPad can deliver didEnterBackground while its live scene snapshot is
        // still foreground-inactive, then reverse immediately toward foreground.
        presence.value = .onScreenIdle
        sut.handleWillResignActive(now: t0.addingTimeInterval(0.1))
        sut.handleDidEnterBackground(now: t0.addingTimeInterval(0.2))
        XCTAssertFalse(sut.session.isSessionLocked, "stale idle snapshot waits for a definitive return edge")
        XCTAssertNil(sut.session.lastLeftMonotonic)

        presence.value = .userFacing
        sut.handleWillEnterForeground(now: t0.addingTimeInterval(0.7))
        XCTAssertTrue(sut.session.isSessionLocked, "willEnterForeground proves the pending background cycle")
        XCTAssertTrue(sut.session.blocksContent, "the vault must be blocked before becoming active")
        XCTAssertEqual(sut.session.lastLeftActiveAt, t0.addingTimeInterval(0.2))
        XCTAssertNotNil(sut.session.lastLeftMonotonic)

        sut.handleDidBecomeActive(now: t0.addingTimeInterval(0.8))
        XCTAssertTrue(sut.session.isSessionLocked)
        XCTAssertTrue(sut.session.needsUnlockPrompt)
    }

    func testSceneBackgroundNotificationUsesItsSceneIdentityInsteadOfReversedSnapshot() async throws {
        let windows = WindowsBox(initial: [
            WindowPrivacyInput(id: "iPad-main", presence: .userFacing)
        ])
        let sut = try await makeHarness(
            appLock: false,
            hide: true,
            seconds: 0,
            windowsSnapshot: { windows.value }
        ).controller
        await sut.start()
        sut.applyLivePreferences(AppLockPreferences(
            appLockEnabled: true,
            autoLockSeconds: 0,
            hideInAppSwitcher: true,
            revealPolicy: .biometricOrPasscode
        ))
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        sut.handleDidBecomeActive(now: t0)

        // The notification itself says this scene is no longer onscreen. Its
        // live activationState may already have reversed by the time we sample.
        windows.value = [WindowPrivacyInput(id: "iPad-main", presence: .onScreenIdle)]
        sut.handleSceneDidEnterBackground(
            now: t0.addingTimeInterval(0.2),
            confirmedSceneID: "iPad-main"
        )

        XCTAssertTrue(sut.session.isSessionLocked)
        XCTAssertNotNil(sut.session.lastLeftMonotonic)
    }

    func testBackgroundedSceneIdentityDoesNotLockAnotherUserFacingWindow() async throws {
        let windows = WindowsBox(initial: [
            WindowPrivacyInput(id: "iPad-A", presence: .onScreenIdle),
            WindowPrivacyInput(id: "iPad-B", presence: .userFacing)
        ])
        let sessionLock = SessionLockBox()
        let sut = try await makeHarness(
            appLock: false,
            hide: true,
            seconds: 0,
            windowsSnapshot: { windows.value },
            sessionLockBox: sessionLock
        ).controller
        await sut.start()
        sut.applyLivePreferences(AppLockPreferences(
            appLockEnabled: true,
            autoLockSeconds: 0,
            hideInAppSwitcher: true,
            revealPolicy: .biometricOrPasscode
        ))
        sut.handleDidBecomeActive(now: Date(timeIntervalSince1970: 1_700_000_000))

        sut.handleSceneDidEnterBackground(
            now: Date(timeIntervalSince1970: 1_700_000_001),
            confirmedSceneID: "iPad-A"
        )

        XCTAssertFalse(sut.session.isSessionLocked, "another user-facing scene keeps the process unlocked")
        XCTAssertNil(sut.session.lastLeftMonotonic)
        XCTAssertFalse(sessionLock.isAuthorizationSuspended())
    }

    func testTransientDidBecomeActiveDoesNotReuseExpiredPreviousBackgroundDeadline() async throws {
        let presence = PresenceBox(initial: .userFacing)
        let harness = try await makeHarness(
            appLock: false,
            hide: false,
            seconds: 1,
            scenePresence: { presence.value }
        )
        let sut = harness.controller
        await sut.start()
        let armed = AppLockPreferences(
            appLockEnabled: true,
            autoLockSeconds: 1,
            hideInAppSwitcher: false,
            revealPolicy: .biometricOrPasscode
        )
        var patch = PreferencesPatch()
        patch.appLockEnabled = armed.appLockEnabled
        patch.autoLockSeconds = armed.autoLockSeconds
        patch.hideInAppSwitcher = armed.hideInAppSwitcher
        patch.revealPolicy = armed.revealPolicy
        try await harness.preferences.update(patch)
        sut.applyLivePreferences(armed)

        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        sut.handleDidBecomeActive(now: t0)
        presence.value = .offScreen
        sut.handleDidEnterBackground(now: t0.addingTimeInterval(0.1))
        presence.value = .userFacing
        sut.handleWillEnterForeground(now: t0.addingTimeInterval(0.2))
        sut.handleDidBecomeActive(now: t0.addingTimeInterval(0.3))
        XCTAssertFalse(sut.session.isSessionLocked)

        // Let the old one-second deadline expire while the app remains active.
        // Control Center / Face ID then produces resign -> didBecomeActive but
        // no willEnterForeground, so it must not reevaluate that old deadline.
        try await Task.sleep(for: .milliseconds(1_100))
        sut.handleWillResignActive(now: t0.addingTimeInterval(2))
        sut.handleDidBecomeActive(now: t0.addingTimeInterval(2.1))

        XCTAssertFalse(sut.session.isSessionLocked)
    }

    func testSceneBackgroundReconcilesStaleIPadApplicationSnapshotAndLocks() async throws {
        let presence = PresenceBox(initial: .onScreenIdle)
        let sut = try await makeHarness(
            appLock: false,
            hide: true,
            seconds: 0,
            scenePresence: { presence.value }
        ).controller
        await sut.start()
        sut.applyLivePreferences(AppLockPreferences(
            appLockEnabled: true,
            autoLockSeconds: 0,
            hideInAppSwitcher: true,
            revealPolicy: .biometricOrPasscode
        ))
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        sut.handleDidBecomeActive(now: t0)

        sut.handleDidEnterBackground(now: t0.addingTimeInterval(2))
        XCTAssertFalse(
            sut.session.isSessionLocked,
            "UIApplication 早通知看到过渡态时须等待 scene 最终确认"
        )

        presence.value = .offScreen
        sut.handleSceneDidEnterBackground(now: t0.addingTimeInterval(2.1))
        XCTAssertTrue(sut.session.isSessionLocked, "最后一扇 scene 离屏后立即档必须锁")
        XCTAssertTrue(sut.session.isInactive)
        XCTAssertNotNil(sut.session.lastLeftMonotonic)
    }

    func testMultipleBackgroundNotificationsDoNotMoveAutoLockStartTime() async throws {
        let presence = PresenceBox(initial: .userFacing)
        let sut = try await makeHarness(
            appLock: false,
            hide: true,
            seconds: 60,
            scenePresence: { presence.value }
        ).controller
        await sut.start()
        sut.applyLivePreferences(AppLockPreferences(
            appLockEnabled: true,
            autoLockSeconds: 60,
            hideInAppSwitcher: true,
            revealPolicy: .biometricOrPasscode
        ))
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        sut.handleDidBecomeActive(now: t0)
        presence.value = .offScreen
        sut.handleDidEnterBackground(now: t0.addingTimeInterval(2))
        let firstMark = try XCTUnwrap(sut.session.lastLeftMonotonic)

        sut.handleSceneDidEnterBackground(now: t0.addingTimeInterval(20))
        XCTAssertEqual(sut.session.lastLeftMonotonic, firstMark)
        XCTAssertEqual(sut.session.lastLeftActiveAt, t0.addingTimeInterval(2))
    }

    func testOneBackgroundSceneDoesNotLockUntilEveryWindowIsOffScreen() async throws {
        let windows = WindowsBox(initial: [
            WindowPrivacyInput(id: "A", presence: .offScreen),
            WindowPrivacyInput(id: "B", presence: .userFacing)
        ])
        let sessionLock = SessionLockBox()
        let sut = try await makeHarness(
            appLock: false,
            hide: true,
            seconds: 0,
            windowsSnapshot: { windows.value },
            sessionLockBox: sessionLock
        ).controller
        await sut.start()
        sut.applyLivePreferences(AppLockPreferences(
            appLockEnabled: true,
            autoLockSeconds: 0,
            hideInAppSwitcher: true,
            revealPolicy: .biometricOrPasscode
        ))
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        sut.handleDidBecomeActive(now: t0)
        sut.handleSceneDidEnterBackground(now: t0.addingTimeInterval(2))
        XCTAssertFalse(sut.session.isSessionLocked, "仍有前台窗口时不得锁全局会话")
        XCTAssertFalse(
            sessionLock.isAuthorizationSuspended(),
            "仍有前台窗口时不得永久暂停全局安全操作"
        )

        windows.value = [
            WindowPrivacyInput(id: "A", presence: .offScreen),
            WindowPrivacyInput(id: "B", presence: .offScreen)
        ]
        sut.handleSceneDidEnterBackground(now: t0.addingTimeInterval(2.1))
        XCTAssertTrue(sut.session.isSessionLocked)
        XCTAssertTrue(sessionLock.isAuthorizationSuspended())
    }

    func testMacResignImmediatelyLocksAndCoversAllWindows() async throws {
        let windows = WindowsBox(initial: [
            WindowPrivacyInput(id: "main", presence: .userFacing),
            WindowPrivacyInput(id: "secondary", presence: .onScreenIdle)
        ])
        let sut = try await makeHarness(
            appLock: false,
            hide: true,
            seconds: 0,
            treatsApplicationResignAsBackground: true,
            windowsSnapshot: { windows.value }
        ).controller
        await sut.start()
        sut.applyLivePreferences(AppLockPreferences(
            appLockEnabled: true,
            autoLockSeconds: 0,
            hideInAppSwitcher: true,
            revealPolicy: .biometricOrPasscode
        ))

        sut.handleWillResignActive(now: Date(timeIntervalSince1970: 1_700_000_000))

        XCTAssertTrue(sut.session.isSessionLocked, "Mac 选立即锁定后，切到其它 App 必须当场锁")
        XCTAssertTrue(sut.session.isInactive)
        XCTAssertNotNil(sut.session.lastLeftMonotonic)
        XCTAssertEqual(sut.windowPrivacy.coveredIDs, ["main", "secondary"])
    }

    func testMacResignStartsGraceTimerEvenWhileWindowRemainsVisible() async throws {
        let sut = try await makeHarness(
            appLock: false,
            hide: false,
            seconds: 60,
            treatsApplicationResignAsBackground: true,
            scenePresence: { .userFacing }
        ).controller
        await sut.start()
        sut.applyLivePreferences(AppLockPreferences(
            appLockEnabled: true,
            autoLockSeconds: 60,
            hideInAppSwitcher: false,
            revealPolicy: .biometricOrPasscode
        ))

        sut.handleWillResignActive(now: Date(timeIntervalSince1970: 1_700_000_000))

        XCTAssertFalse(sut.session.isSessionLocked)
        XCTAssertTrue(sut.session.isInactive)
        XCTAssertNotNil(sut.session.lastLeftMonotonic, "Mac 失焦必须从此刻开始自动锁计时")
    }

    func testMacSystemAuthenticationResignDoesNotSelfLock() async throws {
        let harness = try await makeHarness(
            appLock: false,
            hide: true,
            seconds: 0,
            biometry: .touchID,
            treatsApplicationResignAsBackground: true,
            scenePresence: { .userFacing }
        )
        await harness.controller.start()
        harness.controller.applyLivePreferences(AppLockPreferences(
            appLockEnabled: true,
            autoLockSeconds: 0,
            hideInAppSwitcher: true,
            revealPolicy: .biometricOrPasscode
        ))
        let gate = try XCTUnwrap(harness.fakeGate)
        await gate.setAuthenticationInProgress(true)

        harness.controller.handleWillResignActive()

        XCTAssertFalse(harness.controller.session.isSessionLocked)
        XCTAssertNil(harness.controller.session.lastLeftMonotonic)
        let cancelCount = await gate.cancelCallCount()
        XCTAssertEqual(cancelCount, 0)
    }

    func testMacAuthenticationResignReconcilesRealAppSwitchAfterAuthenticationEnds() async throws {
        let presence = PresenceBox(initial: .userFacing)
        let harness = try await makeHarness(
            appLock: false,
            hide: true,
            seconds: 0,
            biometry: .touchID,
            treatsApplicationResignAsBackground: true,
            scenePresence: { presence.value }
        )
        await harness.controller.start()
        let armedPreferences = AppLockPreferences(
            appLockEnabled: true,
            autoLockSeconds: 0,
            hideInAppSwitcher: true,
            revealPolicy: .biometricOrPasscode
        )
        // `handleDidBecomeActive` 会按生产逻辑重新读取持久层；先模拟设置页已成功落盘，
        // 避免测试用“不一致的内存/磁盘状态”制造与生命周期无关的竞态。
        var armedPatch = PreferencesPatch()
        armedPatch.appLockEnabled = armedPreferences.appLockEnabled
        armedPatch.autoLockSeconds = armedPreferences.autoLockSeconds
        armedPatch.hideInAppSwitcher = armedPreferences.hideInAppSwitcher
        armedPatch.revealPolicy = armedPreferences.revealPolicy
        try await harness.preferences.update(armedPatch)
        harness.controller.applyLivePreferences(armedPreferences)
        harness.controller.handleDidBecomeActive(now: Date(timeIntervalSince1970: 1_700_000_000))
        let gate = try XCTUnwrap(harness.fakeGate)
        await gate.setAuthenticationInProgress(true)

        harness.controller.handleWillResignActive(now: Date(timeIntervalSince1970: 1_700_000_010))
        presence.value = .offScreen
        await gate.setAuthenticationInProgress(false)
        try await Task.sleep(for: .milliseconds(150))

        XCTAssertTrue(harness.controller.session.isSessionLocked)
        XCTAssertTrue(harness.controller.session.isInactive)
        XCTAssertNotNil(harness.controller.session.lastLeftMonotonic)
    }

    func testMacAuthenticationResignIsDiscardedWhenOriginalAppBecomesActiveAgain() async throws {
        let presence = PresenceBox(initial: .userFacing)
        let harness = try await makeHarness(
            appLock: false,
            hide: true,
            seconds: 0,
            biometry: .touchID,
            treatsApplicationResignAsBackground: true,
            scenePresence: { presence.value }
        )
        await harness.controller.start()
        let armedPreferences = AppLockPreferences(
            appLockEnabled: true,
            autoLockSeconds: 0,
            hideInAppSwitcher: true,
            revealPolicy: .biometricOrPasscode
        )
        // 与真实设置变更一致：前台刷新看到的持久值必须和当前会话相同。
        var armedPatch = PreferencesPatch()
        armedPatch.appLockEnabled = armedPreferences.appLockEnabled
        armedPatch.autoLockSeconds = armedPreferences.autoLockSeconds
        armedPatch.hideInAppSwitcher = armedPreferences.hideInAppSwitcher
        armedPatch.revealPolicy = armedPreferences.revealPolicy
        try await harness.preferences.update(armedPatch)
        harness.controller.applyLivePreferences(armedPreferences)
        harness.controller.handleDidBecomeActive(now: Date(timeIntervalSince1970: 1_700_000_000))
        let gate = try XCTUnwrap(harness.fakeGate)
        await gate.setAuthenticationInProgress(true)

        harness.controller.handleWillResignActive(now: Date(timeIntervalSince1970: 1_700_000_010))
        await gate.setAuthenticationInProgress(false)
        harness.controller.handleDidBecomeActive(now: Date(timeIntervalSince1970: 1_700_000_011))
        try await Task.sleep(for: .milliseconds(100))

        XCTAssertFalse(harness.controller.session.isSessionLocked)
        XCTAssertFalse(harness.controller.session.isInactive)
        XCTAssertNil(harness.controller.session.lastLeftMonotonic)
    }

    func testMacDefaultDoesNotAutoPromptEvenWhenUserFacing() async throws {
        let sut = try await makeHarness(
            appLock: true,
            hide: false,
            seconds: 0,
            enablesUnlockPrompt: true,
            autoPromptsSystemAuth: false,
            scenePresence: { .userFacing }
        ).controller
        await sut.start()
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        sut.handleWillEnterForeground(now: t0)
        sut.handleDidBecomeActive(now: t0.addingTimeInterval(0.1))
        XCTAssertTrue(sut.session.needsUnlockPrompt, "已锁且人在用本窗：必须有解锁按钮")
        XCTAssertFalse(sut.shouldAutomaticallyPromptUnlock(), "Mac 不得自己弹触控 ID")
    }

    func testBecomeActiveReloadsPersistedSecurityPreferencesInsteadOfKeepingStaleSession() async throws {
        let harness = try await makeHarness(
            appLock: true,
            hide: true,
            seconds: 60,
            revealPolicy: .biometricOrPasscode,
            scenePresence: { .userFacing }
        )
        await harness.controller.start()
        XCTAssertEqual(harness.controller.session.preferences.revealPolicy, .biometricOrPasscode)

        var remoteLikePatch = PreferencesPatch()
        remoteLikePatch.revealPolicy = .noVerification
        remoteLikePatch.appLockEnabled = false
        remoteLikePatch.hideInAppSwitcher = false
        try await harness.preferences.update(remoteLikePatch)
        XCTAssertEqual(
            harness.controller.session.preferences.revealPolicy,
            .biometricOrPasscode,
            "test setup must prove the in-memory session is stale before foreground refresh"
        )

        harness.controller.handleDidBecomeActive()
        try await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(harness.controller.session.preferences.revealPolicy, .noVerification)
        XCTAssertFalse(harness.controller.session.preferences.appLockEnabled)
        XCTAssertFalse(harness.controller.session.preferences.hideInAppSwitcher)
        XCTAssertFalse(harness.controller.session.isSessionLocked)
    }

    func testPhoneAutoPromptRequiresUserFacingWindow() async throws {
        let idle = try await makeHarness(
            appLock: true,
            hide: false,
            seconds: 0,
            enablesUnlockPrompt: true,
            autoPromptsSystemAuth: true,
            scenePresence: { .onScreenIdle }
        ).controller
        await idle.start()
        idle.handleDidBecomeActive()
        XCTAssertFalse(idle.shouldAutomaticallyPromptUnlock(), "焦点在组里别的软件：不得弹系统框")

        let facing = try await makeHarness(
            appLock: true,
            hide: false,
            seconds: 0,
            enablesUnlockPrompt: true,
            autoPromptsSystemAuth: true,
            scenePresence: { .userFacing }
        ).controller
        await facing.start()
        facing.handleDidBecomeActive()
        XCTAssertTrue(facing.shouldAutomaticallyPromptUnlock())
    }

    func testBecomeActiveWithoutForegroundDoesNotClearLockNeedlessly() async throws {
        let sut = try await makeController(appLock: true, hide: true, seconds: 60)
        await sut.start()
        XCTAssertTrue(sut.session.isSessionLocked)
        XCTAssertTrue(sut.session.needsUnlockPrompt, "冷启动已在前台，应有解锁入口")
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        sut.handleDidBecomeActive(now: t0)
        sut.handleWillResignActive(now: t0.addingTimeInterval(2))
        XCTAssertTrue(sut.session.isSessionLocked)
        XCTAssertFalse(sut.session.needsUnlockPrompt, "仍 inactive 时不得只出锁图标却无入口——等真正回来")
        sut.handleDidBecomeActive(now: t0.addingTimeInterval(2.1))
        XCTAssertTrue(sut.session.needsUnlockPrompt, "回来后必须能点解锁；自动弹验证另走 willEnterForeground")
    }

    func testTwoScenesUserFacingDoesNotStartTimerAndCoversOnlyOffScreen() async throws {
        let windows = WindowsBox(initial: [
            WindowPrivacyInput(id: "A", presence: .userFacing),
            WindowPrivacyInput(id: "B", presence: .offScreen)
        ])
        let sut = try await makeHarness(
            appLock: false,
            hide: true,
            seconds: 0,
            windowsSnapshot: { windows.value }
        ).controller
        await sut.start()
        sut.applyLivePreferences(AppLockPreferences(
            appLockEnabled: true,
            autoLockSeconds: 0,
            hideInAppSwitcher: true,
            revealPolicy: .biometricOrPasscode
        ))
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        sut.handleDidBecomeActive(now: t0)
        sut.handleDidEnterBackground(now: t0.addingTimeInterval(2))
        XCTAssertNil(sut.session.lastLeftMonotonic, "T-W2-01：一扇仍在操作则不得开始计时")
        XCTAssertFalse(sut.session.isSessionLocked)
        XCTAssertEqual(sut.windowPrivacy.coveredIDs, ["B"])
        XCTAssertFalse(sut.windowPrivacy.surface(for: "A").showsSnapshotCover)
    }

    func testAllScenesOffScreenStartsImmediateLock() async throws {
        let windows = WindowsBox(initial: [
            WindowPrivacyInput(id: "A", presence: .offScreen),
            WindowPrivacyInput(id: "B", presence: .offScreen)
        ])
        let sut = try await makeHarness(
            appLock: false,
            hide: true,
            seconds: 0,
            windowsSnapshot: { windows.value }
        ).controller
        await sut.start()
        sut.applyLivePreferences(AppLockPreferences(
            appLockEnabled: true,
            autoLockSeconds: 0,
            hideInAppSwitcher: true,
            revealPolicy: .biometricOrPasscode
        ))
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        sut.handleDidBecomeActive(now: t0)
        sut.handleDidEnterBackground(now: t0.addingTimeInterval(2))
        XCTAssertTrue(sut.session.isSessionLocked, "T-W2-02：全部离屏且「立即」则锁")
        XCTAssertNotNil(sut.session.lastLeftMonotonic)
        XCTAssertEqual(sut.windowPrivacy.coveredIDs, ["A", "B"])
    }

    func testLockedBecomeActiveUncoversOnlyCurrentScene() async throws {
        let windows = WindowsBox(initial: [
            WindowPrivacyInput(id: "A", presence: .userFacing),
            WindowPrivacyInput(id: "B", presence: .offScreen)
        ])
        let sut = try await makeHarness(
            appLock: true,
            hide: true,
            seconds: 60,
            windowsSnapshot: { windows.value }
        ).controller
        await sut.start()
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        sut.handleDidBecomeActive(now: t0)
        XCTAssertTrue(sut.session.isSessionLocked)
        XCTAssertEqual(sut.windowPrivacy.unlockChromeIDs, ["A"], "T-W2-03：只在回到前台的那一扇出解锁")
        XCTAssertEqual(sut.windowPrivacy.coveredIDs, ["B"])
        XCTAssertFalse(sut.windowPrivacy.surface(for: "A").showsSnapshotCover)
    }

    func testApplicationLifecycleObserversInstallOnce() async throws {
        let sut = try await makeController(appLock: false, hide: true, seconds: 60)
        let center = NotificationCenter()
        #if canImport(UIKit)
        let expectedObserverCount = 5
        #else
        let expectedObserverCount = 4
        #endif
        sut.installApplicationLifecycleObservers(on: center)
        XCTAssertEqual(
            sut.applicationLifecycleObserverCount,
            expectedObserverCount,
            "T-W2-04：应用级通知只订一份"
        )
        sut.installApplicationLifecycleObservers(on: center)
        XCTAssertEqual(sut.applicationLifecycleObserverCount, expectedObserverCount)
        await sut.start()
        sut.installApplicationLifecycleObservers(on: center)
        XCTAssertEqual(
            sut.applicationLifecycleObserverCount,
            expectedObserverCount,
            "第二扇窗再 start 也不得加订"
        )
    }

    func testNoVerificationWithAppLockDoesNotLockOnStartOrBackground() async throws {
        let sut = try await makeController(
            appLock: true,
            hide: false,
            seconds: 0,
            revealPolicy: .noVerification
        )
        await sut.start()
        XCTAssertFalse(sut.session.isSessionLocked)
        XCTAssertFalse(sut.session.needsUnlockPrompt)
        XCTAssertFalse(sut.session.showsAppLockUI)
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        sut.handleDidBecomeActive(now: t0)
        sut.handleDidEnterBackground(now: t0.addingTimeInterval(2))
        sut.handleWillEnterForeground(now: t0.addingTimeInterval(3))
        XCTAssertFalse(sut.session.isSessionLocked)
        XCTAssertFalse(sut.shouldAutomaticallyPromptUnlock())
    }

    func testForgotMasterPasswordKeepsLockWhenPersistFails() async throws {
        AppLockLaunchCache.write(true)
        let prefs = FakePreferences()
        try await prefs.update(PreferencesPatch(
            appLockEnabled: true,
            revealPolicy: .masterPassword
        ))
        let keychain = KeychainStore.makeForTests()
        let master = MasterPasswordService(keychain: keychain, calibratedIterations: 10_000)
        try? await master.reset()
        try await master.setPassword("vault-pass-word")
        let sut = AppPrivacyController(
            gate: FakeRevealGate(),
            preferences: prefs,
            masterPassword: master,
            installsSnapshotCover: false,
            enablesUnlockPrompt: false,
            launchAppLockEnabled: true,
            scenePresence: { .offScreen }
        )
        await sut.start()
        XCTAssertTrue(sut.session.isSessionLocked)
        await prefs.setUpdateError(ApiRelayError.networkUnavailable)

        await sut.recoverFromLostMasterPassword()

        XCTAssertTrue(sut.session.isSessionLocked)
        XCTAssertTrue(sut.usesMasterPasswordUnlock)
        XCTAssertEqual(sut.session.preferences.revealPolicy, .masterPassword)
        let stillSet = try await master.isSet()
        XCTAssertTrue(stillSet)
        let stored = try await prefs.load()
        XCTAssertEqual(stored.revealPolicy, .masterPassword)
    }

    func testForgotMasterPasswordDoesNotFallToNoVerification() async throws {
        let harness = try await makeHarness(
            appLock: true,
            hide: false,
            seconds: 60,
            revealPolicy: .masterPassword,
            masterPassword: "vault-pass-word",
            deviceOwnerAuth: { _, _ in }
        )
        await harness.controller.recoverFromLostMasterPassword()
        await harness.preferences.drainPendingWrites()
        let saved = try await harness.preferences.load()
        XCTAssertEqual(saved.revealPolicy, .biometricOrPasscode)
        XCTAssertNotEqual(saved.revealPolicy, .noVerification)
    }

    func testCombinationAppPasswordUnlockUsesExplicitCombinationEntry() async throws {
        let harness = try await makeHarness(
            appLock: true,
            hide: false,
            seconds: 60,
            revealPolicy: .biometryOrAppPassword,
            biometry: .faceID
        )
        let fake = try XCTUnwrap(harness.fakeGate)
        await fake.setAppPasswordMaterialSet(true)
        let sut = harness.controller
        await sut.start()
        XCTAssertTrue(sut.usesCombinationUnlock)
        XCTAssertTrue(sut.session.isSessionLocked)
        var journal = await fake.journal
        XCTAssertFalse(journal.didCall("confirmCombinationWithAppPassword"))
        XCTAssertFalse(journal.didCall("confirmMandatory"))

        await sut.beginCombinationAppPasswordEntry()
        await sut.unlockWithCombinationAppPassword("combination-password")
        XCTAssertFalse(sut.session.isSessionLocked)
        journal = await fake.journal
        XCTAssertEqual(journal.callCount("confirmCombinationWithAppPassword"), 1)
        XCTAssertEqual(journal.callCount("confirmMandatory"), 0)
        XCTAssertEqual(journal.callCount("confirmWithMasterPassword"), 0)
    }

    func testCombinationWrongPasswordStaysLockedWithoutDeviceOwner() async throws {
        let harness = try await makeHarness(
            appLock: true,
            hide: false,
            seconds: 60,
            revealPolicy: .biometryOrAppPassword,
            biometry: .faceID
        )
        let fake = try XCTUnwrap(harness.fakeGate)
        await fake.setAppPasswordMaterialSet(true)
        await fake.fail("confirmCombinationWithAppPassword", with: .authenticationFailed)
        let sut = harness.controller
        await sut.start()
        await sut.unlockWithCombinationAppPassword("wrong-password")
        XCTAssertTrue(sut.session.isSessionLocked)
        XCTAssertEqual(sut.unlockError, String(localized: "appLock.masterPassword.incorrect"))
        let journal = await fake.journal
        XCTAssertEqual(journal.callCount("confirmMandatory"), 0)
    }

    func testCombinationMissingMaterialDoesNotUnlockOrCallMandatory() async throws {
        let harness = try await makeHarness(
            appLock: true,
            hide: false,
            seconds: 60,
            revealPolicy: .biometryOrAppPassword,
            biometry: .faceID
        )
        let fake = try XCTUnwrap(harness.fakeGate)
        await fake.setAppPasswordMaterialSet(false)
        let sut = harness.controller
        await sut.start()
        XCTAssertTrue(sut.combinationAppPasswordMissing)
        await sut.unlockWithCombinationAppPassword("1234")
        XCTAssertTrue(sut.session.isSessionLocked)
        XCTAssertEqual(sut.unlockError, String(localized: "appLock.combination.notSet"))
        let journal = await fake.journal
        XCTAssertEqual(journal.callCount("confirmMandatory"), 0)
        XCTAssertEqual(journal.callCount("confirmCombinationWithAppPassword"), 0)
    }

    func testCombinationUnreadableMaterialIsNotReportedAsUnsetOrWrongPassword() async throws {
        let harness = try await makeHarness(
            appLock: true,
            hide: false,
            seconds: 60,
            revealPolicy: .biometryOrAppPassword,
            biometry: .faceID
        )
        let fake = try XCTUnwrap(harness.fakeGate)
        await fake.setAppPasswordMaterialStatus(.unreadable)
        let sut = harness.controller
        await sut.start()

        await sut.unlockWithCombinationAppPassword("1234")

        XCTAssertTrue(sut.session.isSessionLocked)
        XCTAssertFalse(sut.combinationAppPasswordMissing)
        XCTAssertEqual(sut.unlockError, String(localized: "settings.appPassword.status.unreadable"))
        XCTAssertNotEqual(sut.unlockError, String(localized: "appLock.combination.notSet"))
        XCTAssertNotEqual(sut.unlockError, String(localized: "appLock.masterPassword.incorrect"))
    }

    func testCombinationLockSetupDoesNotWritePassword() async throws {
        let harness = try await makeHarness(
            appLock: true,
            hide: false,
            seconds: 60,
            revealPolicy: .biometryOrAppPassword,
            biometry: .faceID
        )
        let fake = try XCTUnwrap(harness.fakeGate)
        await fake.setAppPasswordMaterialSet(false)
        let sut = harness.controller
        await sut.start()
        await sut.setupCombinationAppPasswordFromLock("vault-pass-word")
        XCTAssertTrue(sut.session.isSessionLocked)
        XCTAssertTrue(sut.combinationAppPasswordMissing)
        XCTAssertEqual(sut.unlockError, String(localized: "appLock.combination.notSet"))
        let journal = await fake.journal
        XCTAssertEqual(journal.callCount("confirmMandatory"), 0)
        let passwordIsSet = try await harness.master.isSet()
        XCTAssertFalse(passwordIsSet)
    }

    func testCombinationSetupCancelStaysLockedWithoutWritingPassword() async throws {
        let harness = try await makeHarness(
            appLock: true,
            hide: false,
            seconds: 60,
            revealPolicy: .biometryOrAppPassword,
            biometry: .faceID
        )
        let fake = try XCTUnwrap(harness.fakeGate)
        await fake.setAppPasswordMaterialSet(false)
        await fake.fail("confirmMandatory", with: .authenticationCancelled)
        let sut = harness.controller
        await sut.start()
        await sut.setupCombinationAppPasswordFromLock("vault-pass-word")
        XCTAssertTrue(sut.session.isSessionLocked)
        let passwordIsSet = try await harness.master.isSet()
        XCTAssertFalse(passwordIsSet)
    }

    func testCombinationEmptyPasswordDoesNotCallGate() async throws {
        let harness = try await makeHarness(
            appLock: true,
            hide: false,
            seconds: 60,
            revealPolicy: .biometryOrAppPassword,
            biometry: .faceID
        )
        let fake = try XCTUnwrap(harness.fakeGate)
        await fake.setAppPasswordMaterialSet(true)
        let sut = harness.controller
        await sut.start()
        await sut.unlockWithCombinationAppPassword("   ")
        XCTAssertTrue(sut.session.isSessionLocked)
        XCTAssertEqual(sut.unlockError, String(localized: "appLock.masterPassword.empty"))
        let journal = await fake.journal
        XCTAssertFalse(journal.didCall("confirmCombinationWithAppPassword"))
    }

    func testLockRecoveryDoesNotDeleteNewerMaterial() async throws {
        AppLockLaunchCache.write(true)
        let prefs = FakePreferences()
        try await prefs.update(PreferencesPatch(
            appLockEnabled: true,
            revealPolicy: .masterPassword
        ))
        let master = FakeMasterPassword()
        try await master.setPassword("original-pass-word")
        await master.setBeforeExclusiveResetHook {
            try await master.changePassword(
                current: "original-pass-word",
                new: "other-window-pass"
            )
        }
        let sut = AppPrivacyController(
            gate: FakeRevealGate(),
            preferences: prefs,
            masterPassword: master,
            installsSnapshotCover: false,
            enablesUnlockPrompt: false,
            launchAppLockEnabled: true,
            // This test isolates the material-revision race; recovery itself is a
            // foreground-only action on desktop.
            scenePresence: { .userFacing }
        )
        await sut.start()
        await sut.recoverFromLostMasterPassword()
        let otherKept = try await master.verify("other-window-pass")
        let originalKept = try await master.verify("original-pass-word")
        XCTAssertTrue(otherKept)
        XCTAssertFalse(originalKept)
        let stored = try await prefs.load()
        XCTAssertEqual(stored.revealPolicy, .biometricOrPasscode)
        XCTAssertNotEqual(stored.revealPolicy, .noVerification)
        XCTAssertTrue(sut.session.isSessionLocked)
        XCTAssertNotNil(sut.unlockError)
    }

    private struct Harness {
        let controller: AppPrivacyController
        let master: MasterPasswordService
        let preferences: PreferencesService
        let fakeGate: FakeRevealGate?
    }

    private func persistAndApply(
        _ preferences: AppLockPreferences,
        to harness: Harness
    ) async throws {
        var patch = PreferencesPatch()
        patch.appLockEnabled = preferences.appLockEnabled
        patch.autoLockSeconds = preferences.autoLockSeconds
        patch.hideInAppSwitcher = preferences.hideInAppSwitcher
        patch.revealPolicy = preferences.revealPolicy
        try await harness.preferences.update(patch)
        harness.controller.applyLivePreferences(preferences)
    }

    private final class AuthBox: @unchecked Sendable {
        var value = false
    }

    private final class BoolBox: @unchecked Sendable {
        var value: Bool
        init(initial: Bool) { value = initial }
    }

    private final class TimeBox: @unchecked Sendable {
        var value: TimeInterval
        init(initial: TimeInterval) { value = initial }
    }

    private final class PresenceBox: @unchecked Sendable {
        var value: AppLockScenePresence
        init(initial: AppLockScenePresence) { value = initial }
    }

    private final class WindowsBox: @unchecked Sendable {
        var value: [WindowPrivacyInput]
        init(initial: [WindowPrivacyInput]) { value = initial }
    }

    private func makeController(
        appLock: Bool,
        hide: Bool,
        seconds: Int,
        revealPolicy: RevealPolicy = .biometricOrPasscode,
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
        revealPolicy: RevealPolicy = .biometricOrPasscode,
        masterPassword: String? = nil,
        biometry: BiometryKind? = nil,
        deviceOwnerAuth: (@Sendable (String, LAPolicy) async throws -> Void)? = nil,
        enablesUnlockPrompt: Bool = false,
        autoPromptsSystemAuth: Bool = false,
        treatsApplicationResignAsBackground: Bool = false,
        launchAppLockEnabled: Bool? = nil,
        scenePresence: @escaping @MainActor () -> AppLockScenePresence = { .offScreen },
        hasForegroundActiveScene: @escaping @MainActor () -> Bool = { true },
        hasForegroundInactiveSceneWithoutActiveAppearance: @escaping @MainActor () -> Bool = { false },
        monotonicUptime: @escaping @MainActor () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
        windowsSnapshot: (@MainActor () -> [WindowPrivacyInput])? = nil,
        sessionLockBox: SessionLockBox? = nil
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
        var fakeGate: FakeRevealGate?
        if let biometry {
            let fake = FakeRevealGate()
            await fake.setAvailableBiometry(biometry)
            gate = fake
            fakeGate = fake
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
            enablesUnlockPrompt: enablesUnlockPrompt,
            launchAppLockEnabled: launchAppLockEnabled,
            autoPromptsSystemAuth: autoPromptsSystemAuth,
            treatsApplicationResignAsBackground: treatsApplicationResignAsBackground,
            scenePresence: scenePresence,
            hasForegroundActiveScene: hasForegroundActiveScene,
            hasForegroundInactiveSceneWithoutActiveAppearance: hasForegroundInactiveSceneWithoutActiveAppearance,
            monotonicUptime: monotonicUptime,
            windowsSnapshot: windowsSnapshot,
            sessionLockBox: sessionLockBox
        )
        return Harness(controller: controller, master: master, preferences: preferences, fakeGate: fakeGate)
    }
}
