@preconcurrency import XCTest
@testable import ApiRelay

@MainActor
final class SecuritySettingsPersistTests: XCTestCase {
    override func setUp() {
        super.setUp()
        AppLockLaunchCache.resetForTests()
    }

    override func tearDown() {
        AppLockLaunchCache.resetForTests()
        super.tearDown()
    }

    func testAppliesMemoryBeforePersistOnlyWhenNotWeakening() {
        let locked = PreferencesDTO.fakeDefault().applying(PreferencesPatch(appLockEnabled: true))
        XCTAssertFalse(
            SecurityPreferenceCommit.appliesMemoryBeforePersist(
                PreferencesPatch(appLockEnabled: false),
                relativeTo: locked
            )
        )
        XCTAssertTrue(
            SecurityPreferenceCommit.appliesMemoryBeforePersist(
                PreferencesPatch(appLockEnabled: true),
                relativeTo: locked
            )
        )
        let biometric = PreferencesDTO.fakeDefault().applying(
            PreferencesPatch(revealPolicy: .biometricOrPasscode)
        )
        XCTAssertFalse(
            SecurityPreferenceCommit.appliesMemoryBeforePersist(
                PreferencesPatch(revealPolicy: .noVerification),
                relativeTo: biometric
            )
        )
    }

    func testWeakeningAppLockDoesNotUnlockWhenPersistFails() async throws {
        let prefs = FakePreferences()
        try await prefs.update(PreferencesPatch(appLockEnabled: true))
        XCTAssertEqual(AppLockLaunchCache.read(), true)
        let privacy = try await makePrivacy(preferences: prefs)
        await privacy.start()
        XCTAssertTrue(privacy.session.isSessionLocked)

        await prefs.setUpdateError(ApiRelayError.networkUnavailable)
        let current = try await prefs.load()
        let failed = expectation(forNotification: .securityPreferencesPersistFailed, object: nil)
        var appliedMemory = false
        SecurityPreferenceCommit.persist(
            PreferencesPatch(appLockEnabled: false),
            relativeTo: current,
            using: prefs
        ) { next in
            appliedMemory = true
            privacy.applyLivePreferences(AppLockPreferences(next))
        }
        await fulfillment(of: [failed], timeout: 2)
        XCTAssertFalse(appliedMemory, "降低等级失败不得改内存锁态")
        XCTAssertTrue(privacy.session.isSessionLocked)
        XCTAssertEqual(AppLockLaunchCache.read(), true)
        let stored = try await prefs.load()
        XCTAssertTrue(stored.appLockEnabled)
    }

    func testWeakeningAppLockUnlocksOnlyAfterPersistSucceeds() async throws {
        let prefs = FakePreferences()
        try await prefs.update(PreferencesPatch(appLockEnabled: true))
        let privacy = try await makePrivacy(preferences: prefs)
        await privacy.start()
        XCTAssertTrue(privacy.session.isSessionLocked)

        let current = try await prefs.load()
        let persisted = expectation(forNotification: .securityPreferencesDidPersist, object: nil)
        SecurityPreferenceCommit.persist(
            PreferencesPatch(appLockEnabled: false),
            relativeTo: current,
            using: prefs
        ) { _ in
            XCTFail("降低等级不得在 persist 成功前改内存")
        }
        await fulfillment(of: [persisted], timeout: 2)
        XCTAssertTrue(privacy.session.isSessionLocked, "落盘成功后仍须等界面套用")
        let loaded = try await prefs.load()
        privacy.applyLivePreferences(AppLockPreferences(loaded))
        XCTAssertFalse(privacy.session.isSessionLocked)
        XCTAssertEqual(AppLockLaunchCache.read(), false)
        XCTAssertFalse(loaded.appLockEnabled)
    }

    func testWeakeningRevealPolicyKeepsOldRankWhenPersistFails() async throws {
        let prefs = FakePreferences()
        try await prefs.update(PreferencesPatch(
            appLockEnabled: true,
            revealPolicy: .biometricOrPasscode
        ))
        let privacy = try await makePrivacy(preferences: prefs)
        await privacy.start()
        XCTAssertEqual(privacy.session.preferences.revealPolicy, .biometricOrPasscode)

        await prefs.setUpdateError(ApiRelayError.networkUnavailable)
        let current = try await prefs.load()
        let failed = expectation(forNotification: .securityPreferencesPersistFailed, object: nil)
        SecurityPreferenceCommit.persist(
            PreferencesPatch(revealPolicy: .noVerification),
            relativeTo: current,
            using: prefs
        ) { next in
            privacy.applyLivePreferences(AppLockPreferences(next))
        }
        await fulfillment(of: [failed], timeout: 2)
        XCTAssertEqual(privacy.session.preferences.revealPolicy, .biometricOrPasscode)
        XCTAssertTrue(privacy.session.isSessionLocked)
        let stored = try await prefs.load()
        XCTAssertEqual(stored.revealPolicy, .biometricOrPasscode)
    }

    func testWeakeningRevealAuthKeepsEnabledWhenPersistFails() async throws {
        let prefs = FakePreferences()
        try await prefs.update(PreferencesPatch(
            appLockEnabled: true,
            revealPolicy: .biometricOrPasscode,
            revealAuthEnabled: true
        ))
        let privacy = try await makePrivacy(preferences: prefs)
        await privacy.start()

        await prefs.setUpdateError(ApiRelayError.networkUnavailable)
        let current = try await prefs.load()
        let failed = expectation(forNotification: .securityPreferencesPersistFailed, object: nil)
        var appliedMemory = false
        SecurityPreferenceCommit.persist(
            PreferencesPatch(revealAuthEnabled: false),
            relativeTo: current,
            using: prefs
        ) { _ in
            appliedMemory = true
        }
        await fulfillment(of: [failed], timeout: 2)
        XCTAssertFalse(appliedMemory)
        let stored = try await prefs.load()
        XCTAssertTrue(stored.revealAuthEnabled)
        XCTAssertTrue(privacy.session.isSessionLocked)
    }

    func testLaunchCacheUsesArmedStateNotBareAppLockSwitch() async throws {
        let prefs = FakePreferences()
        try await prefs.update(PreferencesPatch(
            appLockEnabled: true,
            revealPolicy: .noVerification
        ))
        XCTAssertEqual(AppLockLaunchCache.read(), false, "不验证即使开着自动锁也不得预锁首帧")
        try await prefs.update(PreferencesPatch(revealPolicy: .biometricOrPasscode))
        XCTAssertEqual(AppLockLaunchCache.read(), true)
    }

    func testEveryOrdinarySecurityDowngradeInvalidatedAtFinalCommitWritesNothing() async throws {
        let cases: [(String, PreferencesPatch)] = [
            ("no-verification", PreferencesPatch(revealPolicy: .noVerification)),
            ("app-lock-off", PreferencesPatch(appLockEnabled: false)),
            ("switcher-cover-off", PreferencesPatch(hideInAppSwitcher: false)),
            ("clipboard-clear-off", PreferencesPatch(clipboardClearEnabled: false)),
            ("clipboard-local-only-off", PreferencesPatch(clipboardLocalOnly: false)),
            ("auto-lock-longer", PreferencesPatch(autoLockSeconds: 300)),
            ("clipboard-clear-longer", PreferencesPatch(clipboardClearSeconds: 300)),
            ("reveal-auth-off", PreferencesPatch(revealAuthEnabled: false))
        ]

        for (name, patch) in cases {
            let prefs = FakePreferences()
            try await prefs.update(PreferencesPatch(
                appLockEnabled: true,
                autoLockSeconds: 30,
                revealPolicy: .biometricOrPasscode,
                revealAuthEnabled: true,
                clipboardClearEnabled: true,
                clipboardClearSeconds: 30,
                clipboardLocalOnly: true,
                hideInAppSwitcher: true
            ))
            let current = try await prefs.load()
            XCTAssertTrue(SecurityPolicyChange.weakens(patch, relativeTo: current), name)
            let sessionLock = SessionLockBox()
            let authorization = try SecurityPreferenceAuthorization(
                currentPolicy: current.revealPolicy,
                targetPolicy: patch.revealPolicy,
                sessionLock: sessionLock
            )
            let persistEntered = AsyncStream<Void>.makeStream()
            let allowPersist = AsyncStream<Void>.makeStream()
            await prefs.setPersistFinalCommitDelay {
                persistEntered.continuation.yield(())
                for await _ in allowPersist.stream { break }
            }
            var enteredIterator = persistEntered.stream.makeAsyncIterator()
            let failed = expectation(description: "revoked-\(name)")
            SecurityPreferenceCommit.persist(
                patch,
                relativeTo: current,
                using: prefs,
                authorization: authorization
            ) { _ in
                XCTFail("downgrade must not update memory after revocation: \(name)")
            }

            _ = await enteredIterator.next()
            authorization.invalidate()
            sessionLock.invalidateAuthorizationLeases()
            let notification = expectation(forNotification: .securityPreferencesPersistFailed, object: nil) { _ in
                failed.fulfill()
                return true
            }
            allowPersist.continuation.yield(())
            allowPersist.continuation.finish()
            await fulfillment(of: [notification, failed], timeout: 2)
            persistEntered.continuation.finish()

            XCTAssertEqual(prefs.persistWriteCount(), 0, name)
            let stored = try await prefs.load()
            XCTAssertEqual(stored.appLockEnabled, current.appLockEnabled, name)
            XCTAssertEqual(stored.autoLockSeconds, current.autoLockSeconds, name)
            XCTAssertEqual(stored.revealPolicy, current.revealPolicy, name)
            XCTAssertEqual(stored.revealAuthEnabled, current.revealAuthEnabled, name)
            XCTAssertEqual(stored.clipboardClearEnabled, current.clipboardClearEnabled, name)
            XCTAssertEqual(stored.clipboardClearSeconds, current.clipboardClearSeconds, name)
            XCTAssertEqual(stored.clipboardLocalOnly, current.clipboardLocalOnly, name)
            XCTAssertEqual(stored.hideInAppSwitcher, current.hideInAppSwitcher, name)
        }
    }

    func testKeepExistingMasterToComboRequiresCurrentPasswordAndDoesNotPersist() async throws {
        let env = AppEnvironment.makePreview()
        let master = env.masterPassword as! FakeMasterPassword
        let prefs = env.preferences as! FakePreferences
        try await master.setPassword("keep-me-pass")
        try await prefs.update(PreferencesPatch(revealPolicy: .masterPassword))
        do {
            try await env.persistPasswordDependentPolicyKeepingMaterial(
                target: .biometryOrAppPassword,
                confirmCurrentIfNeeded: {
                    try await AppPasswordSettingsFlow.confirmCurrent(
                        gate: env.gate,
                        master: env.masterPassword,
                        currentPolicy: .masterPassword,
                        currentPassword: "",
                        combinationAppPassword: nil,
                        prefersCombinationAppPassword: false
                    )
                }
            )
            XCTFail("keep existing without current password must fail")
        } catch ApiRelayError.validationFailed(_, let reason)
            where reason == "master_password_prompt_required"
        {
        } catch {
            XCTFail("unexpected \(error)")
        }
        let stored = try await prefs.load()
        XCTAssertEqual(stored.revealPolicy, .masterPassword)
        let journal = await master.journal
        XCTAssertEqual(journal.calls.filter { $0 == "setPassword" }.count, 1)
    }

    func testKeepExistingMasterToComboPersistsTargetWithoutSetPassword() async throws {
        let env = AppEnvironment.makePreview()
        let master = env.masterPassword as! FakeMasterPassword
        let prefs = env.preferences as! FakePreferences
        try await master.setPassword("keep-me-pass")
        try await prefs.update(PreferencesPatch(revealPolicy: .masterPassword))
        try await env.persistPasswordDependentPolicyKeepingMaterial(
            target: .biometryOrAppPassword,
            confirmCurrentIfNeeded: {
                try await AppPasswordSettingsFlow.confirmCurrent(
                    gate: env.gate,
                    master: env.masterPassword,
                    currentPolicy: .masterPassword,
                    currentPassword: "keep-me-pass",
                    combinationAppPassword: nil,
                    prefersCombinationAppPassword: false
                )
            }
        )
        let stored = try await prefs.load()
        XCTAssertEqual(stored.revealPolicy, .biometryOrAppPassword)
        let journal = await master.journal
        XCTAssertEqual(journal.calls.filter { $0 == "setPassword" }.count, 1)
        let kept = try await master.verify("keep-me-pass")
        XCTAssertTrue(kept)
    }

    func testKeepExistingComboToMasterUsesBiometryOrExplicitAppPassword() async throws {
        let env = AppEnvironment.makePreview()
        let master = env.masterPassword as! FakeMasterPassword
        let prefs = env.preferences as! FakePreferences
        let biometryGate = env.gate as! FakeRevealGate
        try await master.setPassword("keep-me-pass")
        try await prefs.update(PreferencesPatch(revealPolicy: .biometryOrAppPassword))
        try await env.persistPasswordDependentPolicyKeepingMaterial(
            target: .masterPassword,
            confirmCurrentIfNeeded: {
                try await AppPasswordSettingsFlow.confirmCurrent(
                    gate: env.gate,
                    master: env.masterPassword,
                    currentPolicy: .biometryOrAppPassword,
                    currentPassword: "",
                    combinationAppPassword: nil,
                    prefersCombinationAppPassword: false
                )
            }
        )
        var stored = try await prefs.load()
        XCTAssertEqual(stored.revealPolicy, .masterPassword)
        let biometryCalls = await biometryGate.journal.calls
        XCTAssertTrue(biometryCalls.contains("confirm"))
        XCTAssertFalse(biometryCalls.contains("confirmCombinationWithAppPassword"))

        try await prefs.update(PreferencesPatch(revealPolicy: .biometryOrAppPassword))
        try await env.persistPasswordDependentPolicyKeepingMaterial(
            target: .masterPassword,
            confirmCurrentIfNeeded: {
                try await AppPasswordSettingsFlow.confirmCurrent(
                    gate: env.gate,
                    master: env.masterPassword,
                    currentPolicy: .biometryOrAppPassword,
                    currentPassword: "",
                    combinationAppPassword: "keep-me-pass",
                    prefersCombinationAppPassword: true
                )
            }
        )
        stored = try await prefs.load()
        XCTAssertEqual(stored.revealPolicy, .masterPassword)
        let laterCalls = await biometryGate.journal.calls
        XCTAssertTrue(laterCalls.contains("confirmCombinationWithAppPassword"))
        XCTAssertFalse(laterCalls.contains("confirmMandatory"))
    }

    func testKeepExistingInvalidatedDuringConfirmDoesNotPersist() async throws {
        let env = AppEnvironment.makePreview()
        let master = env.masterPassword as! FakeMasterPassword
        let prefs = env.preferences as! FakePreferences
        let gate = env.gate as! FakeRevealGate
        try await master.setPassword("keep-me-pass")
        try await prefs.update(PreferencesPatch(revealPolicy: .masterPassword))
        let lease = AppPasswordPageLease(
            target: .biometryOrAppPassword,
            currentPolicy: .masterPassword
        )
        let token = try XCTUnwrap(lease.begin())
        await gate.setAfterConfirmHook {
            lease.invalidate()
        }
        do {
            try await env.persistPasswordDependentPolicyKeepingMaterial(
                target: .biometryOrAppPassword,
                request: AppPasswordSubmitContext(lease: lease, token: token),
                confirmCurrentIfNeeded: {
                    try lease.authorize(
                        token,
                        step: .proceed,
                        currentPolicy: .masterPassword
                    )
                    try await AppPasswordSettingsFlow.confirmCurrent(
                        gate: env.gate,
                        master: env.masterPassword,
                        currentPolicy: .masterPassword,
                        currentPassword: "keep-me-pass",
                        combinationAppPassword: nil,
                        prefersCombinationAppPassword: false
                    )
                    try lease.authorize(
                        token,
                        step: .proceed,
                        currentPolicy: .masterPassword
                    )
                }
            )
            XCTFail("stale page request must not persist")
        } catch ApiRelayError.validationFailed(_, let reason) where reason == "stale_page_request" {
        } catch {
            XCTFail("unexpected \(error)")
        }
        let stored = try await prefs.load()
        XCTAssertEqual(stored.revealPolicy, .masterPassword)
    }

    func testCommittedKeepExistingRemainsAfterLaterInvalidation() async throws {
        let env = AppEnvironment.makePreview()
        let master = env.masterPassword as! FakeMasterPassword
        let prefs = env.preferences as! FakePreferences
        try await master.setPassword("keep-me-pass")
        try await prefs.update(PreferencesPatch(revealPolicy: .masterPassword))
        let lease = AppPasswordPageLease(
            target: .biometryOrAppPassword,
            currentPolicy: .masterPassword
        )
        let token = try XCTUnwrap(lease.begin())
        try await env.persistPasswordDependentPolicyKeepingMaterial(
            target: .biometryOrAppPassword,
            confirmCurrentIfNeeded: {
                try await AppPasswordSettingsFlow.confirmCurrent(
                    gate: env.gate,
                    master: env.masterPassword,
                    currentPolicy: .masterPassword,
                    currentPassword: "keep-me-pass",
                    combinationAppPassword: nil,
                    prefersCombinationAppPassword: false
                )
            }
        )
        lease.invalidate()
        XCTAssertFalse(lease.isFresh(token, sceneActive: true))
        let stored = try await prefs.load()
        XCTAssertEqual(stored.revealPolicy, .biometryOrAppPassword)
    }

    func testSettingsRecoveryFromUnsetMasterFallsToDeviceAuth() async throws {
        let env = AppEnvironment.makePreview()
        let master = env.masterPassword as! FakeMasterPassword
        let prefs = env.preferences as! FakePreferences
        try await prefs.update(PreferencesPatch(revealPolicy: .masterPassword))
        let before = await master.materialStatus()
        XCTAssertEqual(before, .unset)
        try await env.resetAppPasswordAndFallToDeviceAuth()
        let stored = try await prefs.load()
        XCTAssertEqual(stored.revealPolicy, .biometricOrPasscode)
        XCTAssertNotEqual(stored.revealPolicy, .noVerification)
        let after = await master.materialStatus()
        XCTAssertEqual(after, .unset)
        let journal = await master.journal
        XCTAssertFalse(journal.didCall("setPassword"))
    }

    private func makePrivacy(preferences: FakePreferences) async throws -> AppPrivacyController {
        let keychain = KeychainStore.makeForTests()
        let master = MasterPasswordService(keychain: keychain, calibratedIterations: 10_000)
        try? await master.reset()
        return AppPrivacyController(
            gate: FakeRevealGate(),
            preferences: preferences,
            masterPassword: master,
            installsSnapshotCover: false,
            enablesUnlockPrompt: false,
            launchAppLockEnabled: true,
            scenePresence: { .offScreen }
        )
    }
}
