@preconcurrency import XCTest
@testable import ApiRelay
import LocalAuthentication

@MainActor
final class RevealGateTests: XCTestCase {
    #if canImport(UIKit)
    func testSuccessfulAuthenticationSurvivesSystemDismissalLongerThanTwoSeconds() async throws {
        var phone = ScenePresenceSignals.known(sceneIsForegroundActive: false,
            sceneIsForegroundInactive: true, applicationIsActive: false,
            isKeyWindow: true, activeAppearanceIsActive: true)
        phone.requiresWindowFocus = false
        var reads = 0
        let witness = AuthenticationSceneWitness(readSignals: {
            reads += 1
            if reads == 45 {
                phone.sceneIsForegroundActive = .known(true)
                phone.sceneIsForegroundInactive = .known(false)
                phone.applicationIsActive = .known(true)
            }
            return phone
        })
        try await witness.waitUntilActive(checkCancellation: {})
        XCTAssertEqual(reads, 45)
    }

    func testPhoneAuthenticationReturnWaitsForSceneButNotWindowAppearance() async throws {
        var phone = ScenePresenceSignals.known(sceneIsForegroundActive: false,
            sceneIsForegroundInactive: true, applicationIsActive: false,
            isKeyWindow: false, activeAppearanceIsActive: false)
        phone.requiresWindowFocus = false
        var reads = 0
        let witness = AuthenticationSceneWitness(readSignals: {
            reads += 1
            if reads == 2 {
                phone.sceneIsForegroundActive = .known(true)
                phone.sceneIsForegroundInactive = .known(false)
                phone.applicationIsActive = .known(true)
            }
            return phone
        })
        try await witness.waitUntilActive(checkCancellation: {})
        XCTAssertEqual(reads, 2, "Must wait for active scene; stale appearance/key must not reject phone")
    }

    func testPhoneAuthenticationReturnStillRejectsBackgroundAndCancellation() async {
        var phone = ScenePresenceSignals.known(sceneIsForegroundActive: false,
            sceneIsForegroundInactive: false, applicationIsActive: false,
            isKeyWindow: true, activeAppearanceIsActive: true)
        phone.requiresWindowFocus = false
        XCTAssertFalse(AppLockScenePresence.hostIsUserFacing(phone))
        XCTAssertEqual(AppLockScenePresence.resolve(phone), .offScreen)
        let witness = AuthenticationSceneWitness(readSignals: { phone })
        do {
            try await witness.waitUntilActive {
                throw ApiRelayError.authenticationCancelled
            }
            XCTFail("Cancelled authentication must never resume")
        } catch ApiRelayError.authenticationCancelled {
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testWindowedAuthenticationReturnWaitsForOriginFocus() async throws {
        var origin = ScenePresenceSignals.known(sceneIsForegroundActive: true,
            sceneIsForegroundInactive: false, applicationIsActive: true,
            isKeyWindow: true, activeAppearanceIsActive: false)
        var reads = 0
        let witness = AuthenticationSceneWitness(readSignals: {
            reads += 1
            if reads == 3 { origin.activeAppearanceIsActive = .known(true) }
            return origin
        })
        try await witness.waitUntilActive(checkCancellation: {})
        XCTAssertEqual(reads, 3, "iPad/Mac must still wait for the original window to regain focus")
    }

    func testUnlockReturnBindsSingleInactivePhoneSceneWithoutKeyWindow() {
        let signal = ScenePresenceSignals.known(sceneIsForegroundActive: false,
            sceneIsForegroundInactive: true, applicationIsActive: false,
            isKeyWindow: false, activeAppearanceIsActive: nil)
        XCTAssertEqual(AuthenticationSceneWitness.originIndex([signal]), 0)
    }

    func testUnlockReturnDoesNotGuessBetweenTwoUnfocusedScenesOrBindBackground() {
        let foreground = ScenePresenceSignals.known(sceneIsForegroundActive: true,
            sceneIsForegroundInactive: false, applicationIsActive: true,
            isKeyWindow: false, activeAppearanceIsActive: false)
        let background = ScenePresenceSignals.known(sceneIsForegroundActive: false,
            sceneIsForegroundInactive: false, applicationIsActive: true,
            isKeyWindow: true, activeAppearanceIsActive: true)
        XCTAssertNil(AuthenticationSceneWitness.originIndex([foreground, foreground]))
        XCTAssertNil(AuthenticationSceneWitness.originIndex([background]))
    }

    func testUnlockReturnBindsFocusedOriginRatherThanAnotherIdleWindow() {
        let idle = ScenePresenceSignals.known(sceneIsForegroundActive: true,
            sceneIsForegroundInactive: false, applicationIsActive: true,
            isKeyWindow: false, activeAppearanceIsActive: false)
        let focused = ScenePresenceSignals.known(sceneIsForegroundActive: true,
            sceneIsForegroundInactive: false, applicationIsActive: true,
            isKeyWindow: true, activeAppearanceIsActive: true)
        XCTAssertEqual(AuthenticationSceneWitness.originIndex([idle, focused]), 1)
        var returned = focused
        returned.isKeyWindow = .known(false)
        XCTAssertTrue(AppLockScenePresence.hostIsUserFacing(returned), "Active origin does not require the identical key window")
        XCTAssertFalse(AppLockScenePresence.hostIsUserFacing(idle))
    }
    #endif

    func testU3TransientSystemSheetPausesWritesAndRestoresSameRequest() throws {
        let lease = AppPasswordPageLease(target: .masterPassword, currentPolicy: .biometricOrPasscode)
        let token = try XCTUnwrap(lease.begin())
        lease.noteSceneActive(false)
        XCTAssertThrowsError(try lease.authorize(token, step: .proceed))
        lease.noteSceneActive(true)
        XCTAssertNoThrow(try lease.authorize(token, step: .proceed))
    }

    func testU3BackgroundRevocationCannotBeRestoredByReturningActive() throws {
        let lease = AppPasswordPageLease(target: .masterPassword, currentPolicy: .biometricOrPasscode)
        let token = try XCTUnwrap(lease.begin())
        lease.noteSceneActive(false)
        lease.invalidate()
        lease.noteSceneActive(true)
        XCTAssertThrowsError(try lease.authorize(token, step: .proceed))
    }

    func testU3ExplicitAppPasswordUsesExistingVerifierOnly() async throws {
        let master = FakeMasterPassword()
        try await master.setPassword("1234")
        let gate = RevealGate(
            masterPassword: master,
            authenticateDeviceOwner: { _, _ in XCTFail("Must not use device auth") }
        )
        try await gate.confirmCombinationWithAppPassword(reason: "test", password: "1234")
        let journal = await master.journal
        XCTAssertTrue(journal.didCall("verify"))
    }

    func testU3UnavailableBiometryUsesDeviceOwnerPolicyForPasscode() async throws {
        let probe = AuthProbe()
        let gate = RevealGate(
            masterPassword: FakeMasterPassword(),
            authenticateDeviceOwner: { try await probe.authenticate($0, $1) },
            availableBiometry: { .none }
        )
        try await gate.confirm(reason: "test", policy: .biometryOrAppPassword)
        XCTAssertEqual(probe.snapshot(), [.deviceOwnerAuthentication])
    }

    func testU3CombinationUsesOneSystemFlowForBiometryAndDevicePassword() async throws {
        let probe = AuthProbe()
        let gate = RevealGate(
            masterPassword: FakeMasterPassword(),
            authenticateDeviceOwner: { try await probe.authenticate($0, $1) },
            availableBiometry: { .faceID }
        )
        try await gate.confirm(reason: "test", policy: .biometryOrAppPassword)
        XCTAssertEqual(
            probe.snapshot(),
            [.deviceOwnerAuthentication],
            "A second context would restart Face ID instead of entering the system passcode fallback"
        )
    }

    func testU3SystemCancelDoesNotCreateOrVerifyAppPassword() async throws {
        let master = FakeMasterPassword()
        let probe = AuthProbe()
        probe.error = LAError(.userCancel)
        let gate = RevealGate(
            masterPassword: master,
            authenticateDeviceOwner: { try await probe.authenticate($0, $1) }
        )
        do {
            try await gate.confirm(reason: "test", policy: .biometryOrAppPassword)
            XCTFail("Cancellation must not authorize")
        } catch ApiRelayError.authenticationCancelled {}
        XCTAssertEqual(probe.snapshot(), [.deviceOwnerAuthentication])
        let journal = await master.journal
        XCTAssertFalse(journal.didCall("setPassword"))
        XCTAssertFalse(journal.didCall("verify"))
    }

    func testU3ExplicitAppPasswordCannotCreateMissingMaterial() async throws {
        let master = FakeMasterPassword()
        let gate = RevealGate(
            masterPassword: master,
            authenticateDeviceOwner: { _, _ in XCTFail("Must not use device auth") }
        )
        do {
            try await gate.confirmCombinationWithAppPassword(reason: "test", password: "1234")
            XCTFail("Missing material must not authorize")
        } catch ApiRelayError.validationFailed {}
        let journal = await master.journal
        XCTAssertFalse(journal.didCall("setPassword"))
    }

    func testPolicyNoneDoesNotCallLAOrAppPassword() async throws {
        let master = FakeMasterPassword()
        let probe = AuthProbe()
        let gate = makeGate(master: master, probe: probe)
        try await gate.confirm(reason: "test", policy: .noVerification)
        XCTAssertEqual(probe.callCount, 0)
        let journal = await master.journal
        XCTAssertFalse(journal.didCall("isSet"))
        XCTAssertFalse(journal.didCall("verify"))
    }

    func testDeviceAuthUsesDeviceOwnerAuthenticationOnSuccess() async throws {
        let master = FakeMasterPassword()
        let probe = AuthProbe()
        let gate = makeGate(master: master, probe: probe)
        try await gate.confirm(reason: "test", policy: .biometricOrPasscode)
        XCTAssertEqual(probe.snapshot(), [.deviceOwnerAuthentication])
        let journal = await master.journal
        XCTAssertFalse(journal.didCall("verify"))
    }

    func testDeviceAuthCancelDoesNotRetry() async throws {
        let probe = AuthProbe()
        probe.error = LAError(.userCancel)
        let gate = makeGate(master: FakeMasterPassword(), probe: probe)
        do {
            try await gate.confirm(reason: "test", policy: .biometricOrPasscode)
            XCTFail("expected cancel")
        } catch ApiRelayError.authenticationCancelled {
        }
        XCTAssertEqual(probe.snapshot(), [.deviceOwnerAuthentication])
    }

    func testDeviceAuthSystemError() async throws {
        let probe = AuthProbe()
        probe.error = LAError(.authenticationFailed)
        let gate = makeGate(master: FakeMasterPassword(), probe: probe)
        do {
            try await gate.confirm(reason: "test", policy: .biometricOrPasscode)
            XCTFail("expected system error")
        } catch ApiRelayError.systemAuthenticationFailed {
        }
        XCTAssertEqual(probe.snapshot(), [.deviceOwnerAuthentication])
    }

    func testMasterPasswordNotSetFailsWithoutLA() async throws {
        let keychain = KeychainStore.makeForTests()
        let master = MasterPasswordService(keychain: keychain, calibratedIterations: 10_000)
        try? await master.reset()
        let probe = AuthProbe()
        let gate = makeGate(master: master, probe: probe)
        do {
            try await gate.confirm(reason: "test", policy: .masterPassword)
            XCTFail("expected validationFailed")
        } catch let ApiRelayError.validationFailed(_, reason) {
            XCTAssertTrue(reason.contains("master_password"))
        }
        XCTAssertEqual(probe.callCount, 0)
    }

    func testMasterPasswordPromptRequiredDoesNotCallLA() async throws {
        let keychain = KeychainStore.makeForTests()
        let master = MasterPasswordService(keychain: keychain, calibratedIterations: 10_000)
        try? await master.reset()
        try await master.setPassword("test-pass-word")
        addTeardownBlock { try? await master.reset() }
        let probe = AuthProbe()
        let gate = makeGate(master: master, probe: probe)
        do {
            try await gate.confirm(reason: "test", policy: .masterPassword)
            XCTFail("expected prompt_required")
        } catch let ApiRelayError.validationFailed(_, reason) {
            XCTAssertEqual(reason, "master_password_prompt_required")
        }
        XCTAssertEqual(probe.callCount, 0)
    }

    func testMasterPasswordSuccessViaConfirmWithPassword() async throws {
        let keychain = KeychainStore.makeForTests()
        let master = MasterPasswordService(keychain: keychain, calibratedIterations: 10_000)
        try? await master.reset()
        try await master.setPassword("test-pass-word")
        addTeardownBlock { try? await master.reset() }
        let probe = AuthProbe()
        let gate = makeGate(master: master, probe: probe)
        try await gate.confirmWithMasterPassword(reason: "test", password: "test-pass-word")
        XCTAssertEqual(probe.callCount, 0)
    }

    func testAppPasswordConfirmationCancelledInFlightCannotSucceedLater() async throws {
        let master = FakeMasterPassword()
        try await master.setPassword("test-pass-word")
        let enteredVerify = ConfirmRendezvous()
        let releaseVerify = ConfirmRendezvous()
        await master.setBeforeVerifyHook {
            await enteredVerify.meet()
            await releaseVerify.meet()
        }
        let gate = RevealGate(masterPassword: master)

        let confirmation = Task {
            try await gate.confirmWithMasterPassword(reason: "test", password: "test-pass-word")
        }
        await enteredVerify.meet()
        XCTAssertTrue(gate.isAuthenticationInProgress())
        gate.cancelAllAuthentication()
        await releaseVerify.meet()

        do {
            try await confirmation.value
            XCTFail("expected authenticationCancelled")
        } catch ApiRelayError.authenticationCancelled {
        }
        XCTAssertFalse(gate.isAuthenticationInProgress())
    }

    func testMasterPasswordWrongPassword() async throws {
        let keychain = KeychainStore.makeForTests()
        let master = MasterPasswordService(keychain: keychain, calibratedIterations: 10_000)
        try? await master.reset()
        try await master.setPassword("test-pass-word")
        addTeardownBlock { try? await master.reset() }
        let gate = makeGate(master: master, probe: AuthProbe())
        do {
            try await gate.confirmWithMasterPassword(reason: "test", password: "wrong-pass-word")
            XCTFail("expected authenticationFailed")
        } catch ApiRelayError.authenticationFailed {
        }
    }

    func testMasterPasswordRetryDelayPropagates() async throws {
        let keychain = KeychainStore.makeForTests()
        let master = MasterPasswordService(keychain: keychain, calibratedIterations: 10_000)
        try? await master.reset()
        try await master.setPassword("test-pass-word")
        addTeardownBlock { try? await master.reset() }
        let gate = makeGate(master: master, probe: AuthProbe())
        _ = try await master.verify("xxxx")
        _ = try await master.verify("xxxx")
        _ = try await master.verify("xxxx")
        do {
            try await gate.confirmWithMasterPassword(reason: "test", password: "xxxx")
            XCTFail("expected retry delay")
        } catch ApiRelayError.masterPasswordRetryDelayed {
        }
    }

    func testCombinationUsesDeviceOwnerPolicyOnSuccess() async throws {
        let master = FakeMasterPassword()
        let probe = AuthProbe()
        let gate = makeGate(master: master, biometry: .faceID, probe: probe)
        try await gate.confirm(reason: "test", policy: .biometryOrAppPassword)
        XCTAssertEqual(probe.snapshot(), [.deviceOwnerAuthentication])
        let journal = await master.journal
        XCTAssertFalse(journal.didCall("verify"))
    }

    func testCombinationCancelDoesNotAutoInvokeAppPassword() async throws {
        let master = FakeMasterPassword()
        let probe = AuthProbe()
        probe.error = LAError(.userCancel)
        let gate = makeGate(master: master, biometry: .touchID, probe: probe)
        do {
            try await gate.confirm(reason: "test", policy: .biometryOrAppPassword)
            XCTFail("expected cancel")
        } catch ApiRelayError.authenticationCancelled {
        }
        XCTAssertEqual(probe.snapshot(), [.deviceOwnerAuthentication])
        let journal = await master.journal
        XCTAssertFalse(journal.didCall("verify"))
        XCTAssertFalse(journal.didCall("isSet"))
    }

    func testCombinationBiometryUnavailableStillAllowsSystemPasscode() async throws {
        let probe = AuthProbe()
        let gate = makeGate(master: FakeMasterPassword(), biometry: .none, probe: probe)
        try await gate.confirm(reason: "test", policy: .biometryOrAppPassword)
        XCTAssertEqual(probe.snapshot(), [.deviceOwnerAuthentication])
    }

    func testCombinationUnexpectedLockoutFromDeviceOwnerPolicyIsSystemFailure() async throws {
        let probe = AuthProbe()
        probe.error = LAError(.biometryLockout)
        let gate = makeGate(master: FakeMasterPassword(), biometry: .faceID, probe: probe)
        do {
            try await gate.confirm(reason: "test", policy: .biometryOrAppPassword)
            XCTFail("expected lockout")
        } catch ApiRelayError.systemAuthenticationFailed {
        }
        XCTAssertEqual(probe.snapshot(), [.deviceOwnerAuthentication])
    }

    func testCombinationSystemError() async throws {
        let probe = AuthProbe()
        probe.error = LAError(.invalidContext)
        let gate = makeGate(master: FakeMasterPassword(), biometry: .faceID, probe: probe)
        do {
            try await gate.confirm(reason: "test", policy: .biometryOrAppPassword)
            XCTFail("expected system error")
        } catch ApiRelayError.authenticationContextInvalid {
        }
        XCTAssertEqual(probe.snapshot(), [.deviceOwnerAuthentication])
    }

    func testDeviceAuthenticationPreservesActionableSystemErrorCategories() async throws {
        let cases: [(LAError.Code, (ApiRelayError) -> Bool)] = [
            (.passcodeNotSet, { if case .devicePasscodeNotSet = $0 { return true }; return false }),
            (.notInteractive, { if case .authenticationNotInteractive = $0 { return true }; return false }),
            (.systemCancel, { if case .authenticationInterrupted = $0 { return true }; return false }),
        ]
        for (code, matches) in cases {
            let probe = AuthProbe()
            probe.error = LAError(code)
            let gate = makeGate(master: FakeMasterPassword(), probe: probe)
            do {
                try await gate.confirm(reason: "test", policy: .biometricOrPasscode)
                XCTFail("expected mapped error for \(code.rawValue)")
            } catch let error as ApiRelayError {
                XCTAssertTrue(matches(error), "wrong mapping for \(code.rawValue): \(error)")
            }
        }
    }

    func testCombinationExplicitAppPasswordSuccessDoesNotCallLA() async throws {
        let keychain = KeychainStore.makeForTests()
        let master = MasterPasswordService(keychain: keychain, calibratedIterations: 10_000)
        try? await master.reset()
        try await master.setPassword("test-pass-word")
        addTeardownBlock { try? await master.reset() }
        let probe = AuthProbe()
        let gate = makeGate(master: master, probe: probe)
        try await gate.confirmCombinationWithAppPassword(reason: "test", password: "test-pass-word")
        XCTAssertEqual(probe.callCount, 0)
    }

    func testCombinationExplicitAppPasswordNotSet() async throws {
        let keychain = KeychainStore.makeForTests()
        let master = MasterPasswordService(keychain: keychain, calibratedIterations: 10_000)
        try? await master.reset()
        let probe = AuthProbe()
        let gate = makeGate(master: master, probe: probe)
        do {
            try await gate.confirmCombinationWithAppPassword(reason: "test", password: "test-pass-word")
            XCTFail("expected not set")
        } catch let ApiRelayError.validationFailed(_, reason) {
            XCTAssertEqual(reason, "master_password_not_set")
        }
        XCTAssertEqual(probe.callCount, 0)
        let materialUnset = try await gate.isAppPasswordMaterialSet()
        XCTAssertFalse(materialUnset)
    }

    func testCombinationExplicitAppPasswordWrong() async throws {
        let keychain = KeychainStore.makeForTests()
        let master = MasterPasswordService(keychain: keychain, calibratedIterations: 10_000)
        try? await master.reset()
        try await master.setPassword("test-pass-word")
        addTeardownBlock { try? await master.reset() }
        let gate = makeGate(master: master, probe: AuthProbe())
        do {
            try await gate.confirmCombinationWithAppPassword(reason: "test", password: "wrong-pass-word")
            XCTFail("expected authenticationFailed")
        } catch ApiRelayError.authenticationFailed {
        }
    }

    func testConfirmMandatoryAlwaysDeviceOwnerAuthentication() async throws {
        let probe = AuthProbe()
        let gate = makeGate(master: FakeMasterPassword(), biometry: .none, probe: probe)
        try await gate.confirmMandatory(reason: "test", purpose: .recovery)
        XCTAssertEqual(probe.snapshot(), [.deviceOwnerAuthentication])
    }

    func testIsAppPasswordMaterialSetReflectsKeychain() async throws {
        let keychain = KeychainStore.makeForTests()
        let master = MasterPasswordService(keychain: keychain, calibratedIterations: 10_000)
        try? await master.reset()
        let gate = RevealGate(masterPassword: master)
        let before = try await gate.isAppPasswordMaterialSet()
        XCTAssertFalse(before)
        try await master.setPassword("test-pass-word")
        addTeardownBlock { try? await master.reset() }
        let after = try await gate.isAppPasswordMaterialSet()
        XCTAssertTrue(after)
    }

    func testResetAppPasswordRequiresDeviceOwnerAndLeavesOtherKeychainItems() async throws {
        let keychain = KeychainStore.makeForTests()
        let master = MasterPasswordService(keychain: keychain, calibratedIterations: 10_000)
        try? await master.reset()
        try await master.setPassword("test-pass-word")
        let keyId = UUID()
        let adminId = UUID()
        try await keychain.save("sk-keep-local", service: .keys, account: keyId)
        try await keychain.save("admin-keep-local", service: .admin, account: adminId)
        try await keychain.save("backup-keep-local", service: .backuppw, account: KeychainStore.backupPassphraseAccount)
        addTeardownBlock {
            try? await master.reset()
            try? await keychain.delete(service: .keys, account: keyId)
            try? await keychain.delete(service: .admin, account: adminId)
            try? await keychain.delete(service: .backuppw, account: KeychainStore.backupPassphraseAccount)
        }
        let probe = AuthProbe()
        let gate = makeGate(master: master, probe: probe)
        let beforeReset = try await gate.isAppPasswordMaterialSet()
        XCTAssertTrue(beforeReset)
        try await AppPasswordRecovery.recoverToDeviceAuth(
            confirmMandatory: { try await gate.confirmMandatory(reason: "reset") },
            persistDeviceAuth: { },
            resetMaterial: { try await master.reset() }
        )
        XCTAssertEqual(probe.snapshot(), [.deviceOwnerAuthentication])
        let afterReset = try await gate.isAppPasswordMaterialSet()
        XCTAssertFalse(afterReset)
        let keptKey = try await keychain.read(service: .keys, account: keyId)
        let keptAdmin = try await keychain.read(service: .admin, account: adminId)
        let keptBackup = try await keychain.read(
            service: .backuppw,
            account: KeychainStore.backupPassphraseAccount
        )
        XCTAssertEqual(keptKey, "sk-keep-local")
        XCTAssertEqual(keptAdmin, "admin-keep-local")
        XCTAssertEqual(keptBackup, "backup-keep-local")
        XCTAssertEqual(AppPasswordRecovery.deviceAuthPatch.revealPolicy, .biometricOrPasscode)
        XCTAssertNotEqual(AppPasswordRecovery.deviceAuthPatch.revealPolicy, .noVerification)
    }

    func testResetCancelledLeavesMaterial() async throws {
        let keychain = KeychainStore.makeForTests()
        let master = MasterPasswordService(keychain: keychain, calibratedIterations: 10_000)
        try? await master.reset()
        try await master.setPassword("test-pass-word")
        addTeardownBlock { try? await master.reset() }
        let probe = AuthProbe()
        probe.error = LAError(.userCancel)
        let gate = makeGate(master: master, probe: probe)
        let log = StepLog()
        do {
            try await AppPasswordRecovery.recoverToDeviceAuth(
                confirmMandatory: { try await gate.confirmMandatory(reason: "reset") },
                persistDeviceAuth: { log.add("persist") },
                resetMaterial: { log.add("reset") }
            )
            XCTFail("expected cancel")
        } catch ApiRelayError.authenticationCancelled {
        }
        let stillSet = try await gate.isAppPasswordMaterialSet()
        XCTAssertTrue(stillSet)
        XCTAssertEqual(probe.snapshot(), [.deviceOwnerAuthentication])
        XCTAssertEqual(log.snapshot(), [])
    }

    func testWrongPasswordErrorDoesNotEmbedSecret() async throws {
        let keychain = KeychainStore.makeForTests()
        let master = MasterPasswordService(keychain: keychain, calibratedIterations: 10_000)
        try? await master.reset()
        let secret = "unique-test-secret-xyz"
        try await master.setPassword(secret)
        addTeardownBlock { try? await master.reset() }
        let gate = RevealGate(masterPassword: master) { _, _ in }
        do {
            try await gate.confirmWithMasterPassword(reason: "test", password: "wrong-\(secret)")
            XCTFail("expected authenticationFailed")
        } catch let error as ApiRelayError {
            let text = "\(error) \(error.localizedDescription)"
            XCTAssertFalse(text.contains(secret))
            XCTAssertFalse(text.contains("wrong-\(secret)"))
        }
    }

    func testRecoveryCoordinatorOrderIsConfirmPersistReset() async throws {
        let log = StepLog()
        try await AppPasswordRecovery.recoverToDeviceAuth(
            confirmMandatory: { log.add("confirm") },
            persistDeviceAuth: { log.add("persist") },
            resetMaterial: { log.add("reset") }
        )
        XCTAssertEqual(log.snapshot(), ["confirm", "persist", "reset"])
    }

    func testRecoveryCoordinatorPersistFailureSkipsReset() async throws {
        let log = StepLog()
        do {
            try await AppPasswordRecovery.recoverToDeviceAuth(
                confirmMandatory: { log.add("confirm") },
                persistDeviceAuth: {
                    log.add("persist")
                    throw ApiRelayError.networkUnavailable
                },
                resetMaterial: { log.add("reset") }
            )
            XCTFail("expected persist failure")
        } catch ApiRelayError.networkUnavailable {
        }
        XCTAssertEqual(log.snapshot(), ["confirm", "persist"])
    }

    func testRecoveryPersistFailureKeepsMaterialAndSurfacesError() async throws {
        let env = AppEnvironment.makePreview()
        let master = try XCTUnwrap(env.masterPassword as? FakeMasterPassword)
        let prefs = try XCTUnwrap(env.preferences as? FakePreferences)
        try await master.setPassword("test-pass-word")
        await prefs.setUpdateError(ApiRelayError.networkUnavailable)
        do {
            try await env.resetAppPasswordAndFallToDeviceAuth()
            XCTFail("expected persist failure")
        } catch ApiRelayError.networkUnavailable {
        }
        let stillSet = try await master.isSet()
        XCTAssertTrue(stillSet)
        let loaded = try await prefs.load()
        XCTAssertNotEqual(loaded.revealPolicy, .noVerification)
    }

    func testRecoveryDeleteFailureSurfacesAfterPersist() async throws {
        let env = AppEnvironment.makePreview()
        let master = try XCTUnwrap(env.masterPassword as? FakeMasterPassword)
        let prefs = try XCTUnwrap(env.preferences as? FakePreferences)
        try await master.setPassword("test-pass-word")
        await master.fail("reset", with: ApiRelayError.keychainFailure(-50))
        do {
            try await env.resetAppPasswordAndFallToDeviceAuth()
            XCTFail("expected delete failure")
        } catch let ApiRelayError.keychainFailure(status) {
            XCTAssertEqual(status, -50)
        }
        let loaded = try await prefs.load()
        XCTAssertEqual(loaded.revealPolicy, .biometricOrPasscode)
        XCTAssertNotEqual(loaded.revealPolicy, .noVerification)
    }

    func testRecoverySuccessOrderConfirmPersistThenReset() async throws {
        let env = AppEnvironment.makePreview()
        let master = try XCTUnwrap(env.masterPassword as? FakeMasterPassword)
        let prefs = try XCTUnwrap(env.preferences as? FakePreferences)
        let gate = try XCTUnwrap(env.gate as? FakeRevealGate)
        try await master.setPassword("test-pass-word")
        try await env.resetAppPasswordAndFallToDeviceAuth()
        let stillSet = try await master.isSet()
        XCTAssertFalse(stillSet)
        let loaded = try await prefs.load()
        XCTAssertEqual(loaded.revealPolicy, .biometricOrPasscode)
        let gateJournal = await gate.journal
        let prefsJournal = await prefs.journal
        let masterJournal = await master.journal
        XCTAssertTrue(gateJournal.didCall("confirmMandatory"))
        XCTAssertTrue(prefsJournal.didCall("update"))
        XCTAssertTrue(masterJournal.didCall("reset"))
    }

    func testPasswordDependentPersistGateUsesMaterialThreeStates() {
        let passwordTargets: [RevealPolicy] = [.masterPassword, .biometryOrAppPassword]
        let otherPolicies: [RevealPolicy] = [.noVerification, .biometricOrPasscode]
        let statuses: [AppPasswordMaterialStatus] = [.unset, .set, .unreadable]
        for target in passwordTargets {
            for status in statuses {
                let allowed = AppPasswordPolicyGate.canPersistAsCurrentPolicy(target, material: status)
                XCTAssertEqual(allowed, status == .set, "\(target) \(status)")
                let rejection = AppPasswordPolicyGate.persistRejection(
                    PreferencesPatch(revealPolicy: target),
                    material: status
                )
                if status == .set {
                    XCTAssertNil(rejection, "\(target)")
                } else {
                    XCTAssertNotNil(rejection, "\(target) \(status)")
                }
            }
        }
        for policy in otherPolicies {
            for status in statuses {
                XCTAssertTrue(
                    AppPasswordPolicyGate.canPersistAsCurrentPolicy(policy, material: status),
                    "\(policy) \(status)"
                )
            }
        }
        XCTAssertFalse(
            AppPasswordPolicyGate.canUseAppPasswordEntry(material: .unreadable)
        )
        XCTAssertFalse(
            AppPasswordPolicyGate.canUseAppPasswordEntry(material: .unset)
        )
    }

    func testCreateCoordinatorBindsOriginalTargetAndOrder() async throws {
        let passwordTargets: [RevealPolicy] = [.masterPassword, .biometryOrAppPassword]
        for target in passwordTargets {
            let master = FakeMasterPassword()
            let log = StepLog()
            try await AppPasswordSetup.createMaterialThenPersistTarget(
                target: target,
                materialStatus: { await master.materialStatus() },
                confirmCurrentIfNeeded: { log.add("current") },
                confirmDeviceOwner: { log.add("owner") },
                setAndVerifyMaterial: {
                    log.add("set")
                    try await master.setPassword("test-pass-word")
                },
                persistTarget: { policy in
                    log.add("persist:\(policy.rawValue)")
                }
            )
            XCTAssertEqual(
                log.snapshot(),
                ["current", "owner", "set", "persist:\(target.rawValue)"]
            )
            let status = await master.materialStatus()
            XCTAssertEqual(status, .set)
        }
    }

    func testCreateCoordinatorRejectsSetAndUnreadableWithoutWriting() async throws {
        for status in [AppPasswordMaterialStatus.set, .unreadable] {
            let log = StepLog()
            do {
                try await AppPasswordSetup.createMaterialThenPersistTarget(
                    target: .biometryOrAppPassword,
                    materialStatus: { status },
                    confirmCurrentIfNeeded: { log.add("current") },
                    confirmDeviceOwner: { log.add("owner") },
                    setAndVerifyMaterial: { log.add("set") },
                    persistTarget: { _ in log.add("persist") }
                )
                XCTFail("expected reject \(status)")
            } catch let ApiRelayError.validationFailed(_, reason) {
                XCTAssertTrue(reason == "already_set" || reason == "material_unreadable")
            }
            XCTAssertEqual(log.snapshot(), [])
        }
    }

    func testCreateCoordinatorCancelBeforeWriteLeavesNoPersist() async throws {
        let log = StepLog()
        do {
            try await AppPasswordSetup.createMaterialThenPersistTarget(
                target: .masterPassword,
                materialStatus: { .unset },
                confirmCurrentIfNeeded: { log.add("current") },
                confirmDeviceOwner: {
                    log.add("owner")
                    throw ApiRelayError.authenticationCancelled
                },
                setAndVerifyMaterial: { log.add("set") },
                persistTarget: { _ in log.add("persist") }
            )
            XCTFail("expected cancel")
        } catch ApiRelayError.authenticationCancelled {
        }
        XCTAssertEqual(log.snapshot(), ["current", "owner"])
    }

    func testPersistExistingDoesNotSetPasswordAndKeepsTarget() async throws {
        let log = StepLog()
        try await AppPasswordSetup.persistExistingMaterialTarget(
            target: .biometryOrAppPassword,
            materialStatus: { .set },
            confirmCurrentIfNeeded: { log.add("current") },
            persistTarget: { policy in
                log.add("persist:\(policy.rawValue)")
            }
        )
        XCTAssertEqual(log.snapshot(), ["current", "persist:biometryOrAppPassword"])
    }

    func testEnvironmentCreateComboDoesNotRewriteToMaster() async throws {
        let env = AppEnvironment.makePreview()
        let master = try XCTUnwrap(env.masterPassword as? FakeMasterPassword)
        let prefs = try XCTUnwrap(env.preferences as? FakePreferences)
        let gate = try XCTUnwrap(env.gate as? FakeRevealGate)
        try await env.createAppPasswordMaterialThenPersist(
            password: "test-pass-word",
            target: .biometryOrAppPassword,
            confirmCurrentIfNeeded: { }
        )
        let loaded = try await prefs.load()
        XCTAssertEqual(loaded.revealPolicy, .biometryOrAppPassword)
        XCTAssertNotEqual(loaded.revealPolicy, .masterPassword)
        let gateJournal = await gate.journal
        let masterJournal = await master.journal
        XCTAssertTrue(gateJournal.didCall("confirmMandatory"))
        XCTAssertEqual(masterJournal.callCount("setPassword"), 1)
        let materialSet = try await master.isSet()
        XCTAssertTrue(materialSet)
    }

    func testEnvironmentCreatePersistFailureKeepsMaterialAndOldPolicy() async throws {
        let env = AppEnvironment.makePreview()
        let master = try XCTUnwrap(env.masterPassword as? FakeMasterPassword)
        let prefs = try XCTUnwrap(env.preferences as? FakePreferences)
        await prefs.setUpdateError(ApiRelayError.networkUnavailable)
        do {
            try await env.createAppPasswordMaterialThenPersist(
                password: "test-pass-word",
                target: .masterPassword,
                confirmCurrentIfNeeded: { }
            )
            XCTFail("expected persist failure")
        } catch ApiRelayError.networkUnavailable {
        }
        let kept = try await master.isSet()
        XCTAssertTrue(kept)
        let loaded = try await prefs.load()
        XCTAssertEqual(loaded.revealPolicy, .biometricOrPasscode)
        XCTAssertNotEqual(loaded.revealPolicy, .masterPassword)
    }

    func testEnvironmentPersistExistingDoesNotCallSetPassword() async throws {
        let env = AppEnvironment.makePreview()
        let master = try XCTUnwrap(env.masterPassword as? FakeMasterPassword)
        let prefs = try XCTUnwrap(env.preferences as? FakePreferences)
        try await master.setPassword("test-pass-word")
        let before = await master.journal
        XCTAssertEqual(before.callCount("setPassword"), 1)
        try await env.persistPasswordDependentPolicyKeepingMaterial(
            target: .masterPassword,
            confirmCurrentIfNeeded: { }
        )
        let after = await master.journal
        XCTAssertEqual(after.callCount("setPassword"), 1)
        let loaded = try await prefs.load()
        XCTAssertEqual(loaded.revealPolicy, .masterPassword)
    }

    func testOrdinaryConfirmDoesNotSetPassword() async throws {
        let master = FakeMasterPassword()
        let probe = AuthProbe()
        let gate = makeGate(master: master, probe: probe)
        try await gate.confirm(reason: "test", policy: .biometricOrPasscode)
        let journal = await master.journal
        XCTAssertFalse(journal.didCall("setPassword"))
    }

    func testAppPasswordMaterialStatusUnreadableIsNotUnset() async throws {
        let master = FakeMasterPassword()
        await master.fail("materialStatus", with: ApiRelayError.keychainFailure(-50))
        let gate = RevealGate(masterPassword: master)
        let status = await gate.appPasswordMaterialStatus()
        XCTAssertEqual(status, .unreadable)
        XCTAssertNotEqual(status, .unset)
        XCTAssertFalse(AppPasswordPolicyGate.canPersistAsCurrentPolicy(.masterPassword, material: status))
        XCTAssertFalse(
            AppPasswordPolicyGate.canPersistAsCurrentPolicy(.biometryOrAppPassword, material: status)
        )
    }

    func testCreateRejectsWhenOtherWindowSetsDuringCurrentConfirm() async throws {
        let passwordTargets: [RevealPolicy] = [.masterPassword, .biometryOrAppPassword]
        for target in passwordTargets {
            let env = AppEnvironment.makePreview()
            let master = try XCTUnwrap(env.masterPassword as? FakeMasterPassword)
            let prefs = try XCTUnwrap(env.preferences as? FakePreferences)
            do {
                try await env.createAppPasswordMaterialThenPersist(
                    password: "stale-create-pass",
                    target: target,
                    confirmCurrentIfNeeded: {
                        try await master.setPassword("other-window-pass")
                    }
                )
                XCTFail("expected already_set \(target)")
            } catch let ApiRelayError.validationFailed(_, reason) {
                XCTAssertEqual(reason, "already_set", "\(target)")
            }
            let otherKept = try await master.verify("other-window-pass")
            let staleKept = try await master.verify("stale-create-pass")
            XCTAssertTrue(otherKept, "\(target)")
            XCTAssertFalse(staleKept, "\(target)")
            let loaded = try await prefs.load()
            XCTAssertEqual(loaded.revealPolicy, .biometricOrPasscode, "\(target)")
            XCTAssertNotEqual(loaded.revealPolicy, target)
            let journal = await master.journal
            XCTAssertEqual(journal.callCount("setPassword"), 1, "\(target)")
        }
    }

    func testCreateRejectsWhenMaterialBecomesUnreadableDuringConfirm() async throws {
        let passwordTargets: [RevealPolicy] = [.masterPassword, .biometryOrAppPassword]
        for target in passwordTargets {
            let env = AppEnvironment.makePreview()
            let master = try XCTUnwrap(env.masterPassword as? FakeMasterPassword)
            let prefs = try XCTUnwrap(env.preferences as? FakePreferences)
            do {
                try await env.createAppPasswordMaterialThenPersist(
                    password: "stale-create-pass",
                    target: target,
                    confirmCurrentIfNeeded: {
                        await master.overrideMaterialStatus(.unreadable)
                    }
                )
                XCTFail("expected unreadable \(target)")
            } catch let ApiRelayError.validationFailed(_, reason) {
                XCTAssertEqual(reason, "material_unreadable", "\(target)")
            }
            let journal = await master.journal
            XCTAssertFalse(journal.didCall("setPassword"), "\(target)")
            let status = await master.materialStatus()
            XCTAssertEqual(status, .unreadable)
            let loaded = try await prefs.load()
            XCTAssertEqual(loaded.revealPolicy, .biometricOrPasscode)
        }
    }

    func testCreateRejectsWhenOtherWindowSetsDuringDeviceOwner() async throws {
        let env = AppEnvironment.makePreview()
        let master = try XCTUnwrap(env.masterPassword as? FakeMasterPassword)
        let prefs = try XCTUnwrap(env.preferences as? FakePreferences)
        let gate = try XCTUnwrap(env.gate as? FakeRevealGate)
        await gate.setConfirmMandatoryHook {
            try await master.setPassword("other-window-pass")
        }
        do {
            try await env.createAppPasswordMaterialThenPersist(
                password: "stale-create-pass",
                target: .biometryOrAppPassword,
                confirmCurrentIfNeeded: { }
            )
            XCTFail("expected already_set")
        } catch let ApiRelayError.validationFailed(_, reason) {
            XCTAssertEqual(reason, "already_set")
        }
        let otherKept = try await master.verify("other-window-pass")
        let staleKept = try await master.verify("stale-create-pass")
        XCTAssertTrue(otherKept)
        XCTAssertFalse(staleKept)
        let loaded = try await prefs.load()
        XCTAssertEqual(loaded.revealPolicy, .biometricOrPasscode)
    }

    func testCreateCancelLeavesMaterialAndPolicyUnchanged() async throws {
        let env = AppEnvironment.makePreview()
        let master = try XCTUnwrap(env.masterPassword as? FakeMasterPassword)
        let prefs = try XCTUnwrap(env.preferences as? FakePreferences)
        do {
            try await env.createAppPasswordMaterialThenPersist(
                password: "stale-create-pass",
                target: .masterPassword,
                confirmCurrentIfNeeded: { throw ApiRelayError.authenticationCancelled }
            )
            XCTFail("expected cancel")
        } catch ApiRelayError.authenticationCancelled {
        }
        let created = try await master.isSet()
        XCTAssertFalse(created)
        let loaded = try await prefs.load()
        XCTAssertEqual(loaded.revealPolicy, .biometricOrPasscode)
        let journal = await master.journal
        XCTAssertFalse(journal.didCall("setPassword"))
    }

    func testCreateWriteFailureDoesNotPersist() async throws {
        let env = AppEnvironment.makePreview()
        let master = try XCTUnwrap(env.masterPassword as? FakeMasterPassword)
        let prefs = try XCTUnwrap(env.preferences as? FakePreferences)
        await master.fail("setPassword", with: ApiRelayError.keychainFailure(-34018))
        do {
            try await env.createAppPasswordMaterialThenPersist(
                password: "stale-create-pass",
                target: .masterPassword,
                confirmCurrentIfNeeded: { }
            )
            XCTFail("expected keychainFailure")
        } catch let ApiRelayError.keychainFailure(status) {
            XCTAssertEqual(status, -34018)
        }
        let created = try await master.isSet()
        XCTAssertFalse(created)
        let loaded = try await prefs.load()
        XCTAssertEqual(loaded.revealPolicy, .biometricOrPasscode)
    }

    func testPersistExistingAbortsWhenMaterialRemovedDuringConfirm() async throws {
        let passwordTargets: [RevealPolicy] = [.masterPassword, .biometryOrAppPassword]
        for target in passwordTargets {
            let env = AppEnvironment.makePreview()
            let master = try XCTUnwrap(env.masterPassword as? FakeMasterPassword)
            let prefs = try XCTUnwrap(env.preferences as? FakePreferences)
            try await master.setPassword("keep-me-pass")
            do {
                try await env.persistPasswordDependentPolicyKeepingMaterial(
                    target: target,
                    confirmCurrentIfNeeded: {
                        try await env.resetAppPasswordAndFallToDeviceAuth()
                    }
                )
                XCTFail("expected reject \(target)")
            } catch let ApiRelayError.validationFailed(_, reason) {
                XCTAssertTrue(
                    reason == "master_password_not_configured" || reason == "stale_concurrent",
                    "\(target) \(reason)"
                )
            }
            let stillSet = try await master.isSet()
            XCTAssertFalse(stillSet, "\(target)")
            let loaded = try await prefs.load()
            XCTAssertEqual(loaded.revealPolicy, .biometricOrPasscode, "\(target)")
            XCTAssertNotEqual(loaded.revealPolicy, target)
        }
    }

    func testPersistExistingAbortsWhenMaterialBecomesUnreadable() async throws {
        let env = AppEnvironment.makePreview()
        let master = try XCTUnwrap(env.masterPassword as? FakeMasterPassword)
        let prefs = try XCTUnwrap(env.preferences as? FakePreferences)
        try await master.setPassword("keep-me-pass")
        do {
            try await env.persistPasswordDependentPolicyKeepingMaterial(
                target: .masterPassword,
                confirmCurrentIfNeeded: {
                    await master.overrideMaterialStatus(.unreadable)
                }
            )
            XCTFail("expected unreadable")
        } catch let ApiRelayError.validationFailed(_, reason) {
            XCTAssertEqual(reason, "material_unreadable")
        }
        let kept = try await master.verify("keep-me-pass")
        XCTAssertTrue(kept)
        let loaded = try await prefs.load()
        XCTAssertEqual(loaded.revealPolicy, .biometricOrPasscode)
    }

    func testConcurrentCreatesDoNotOverwriteOrDoublePersist() async throws {
        let env = AppEnvironment.makePreview()
        let master = try XCTUnwrap(env.masterPassword as? FakeMasterPassword)
        let prefs = try XCTUnwrap(env.preferences as? FakePreferences)
        let meet = ConfirmRendezvous()
        let firstTask = Task { @MainActor in
            do {
                try await env.createAppPasswordMaterialThenPersist(
                    password: "first-window-pass",
                    target: .masterPassword,
                    confirmCurrentIfNeeded: { await meet.meet() }
                )
                return PasswordSetOutcome.success
            } catch let ApiRelayError.validationFailed(_, reason) {
                return PasswordSetOutcome.failureReason(reason)
            } catch {
                return PasswordSetOutcome.failureReason("other")
            }
        }
        let secondTask = Task { @MainActor in
            do {
                try await env.createAppPasswordMaterialThenPersist(
                    password: "second-window-pass",
                    target: .biometryOrAppPassword,
                    confirmCurrentIfNeeded: { await meet.meet() }
                )
                return PasswordSetOutcome.success
            } catch let ApiRelayError.validationFailed(_, reason) {
                return PasswordSetOutcome.failureReason(reason)
            } catch {
                return PasswordSetOutcome.failureReason("other")
            }
        }
        let results = [await firstTask.value, await secondTask.value]
        let successes = results.filter { if case .success = $0 { return true } else { return false } }
        let failures = results.filter { if case .failureReason = $0 { return true } else { return false } }
        XCTAssertEqual(successes.count, 1)
        XCTAssertEqual(failures.count, 1)
        if case let .failureReason(reason) = failures[0] {
            XCTAssertEqual(reason, "already_set")
        }
        let firstKept = try await master.verify("first-window-pass")
        let secondKept = try await master.verify("second-window-pass")
        XCTAssertEqual([firstKept, secondKept].filter(\.self).count, 1)
        let loaded = try await prefs.load()
        if firstKept {
            XCTAssertEqual(loaded.revealPolicy, .masterPassword)
        } else {
            XCTAssertEqual(loaded.revealPolicy, .biometryOrAppPassword)
        }
    }

    func testRecoverDoesNotDeleteNewerMaterialFromOtherWindow() async throws {
        let env = AppEnvironment.makePreview()
        let master = try XCTUnwrap(env.masterPassword as? FakeMasterPassword)
        let prefs = try XCTUnwrap(env.preferences as? FakePreferences)
        let gate = try XCTUnwrap(env.gate as? FakeRevealGate)
        try await master.setPassword("original-pass-word")
        await gate.setConfirmMandatoryHook {
            try await master.reset()
            try await master.setPassword("other-window-pass")
        }
        do {
            try await env.resetAppPasswordAndFallToDeviceAuth()
            XCTFail("expected stale_concurrent")
        } catch let ApiRelayError.validationFailed(_, reason) {
            XCTAssertEqual(reason, "stale_concurrent")
        }
        let otherKept = try await master.verify("other-window-pass")
        let originalKept = try await master.verify("original-pass-word")
        XCTAssertTrue(otherKept)
        XCTAssertFalse(originalKept)
        let loaded = try await prefs.load()
        XCTAssertEqual(loaded.revealPolicy, .biometricOrPasscode)
        let journal = await master.journal
        XCTAssertEqual(journal.callCount("reset"), 1)
    }

    func testRecoverSkipsResetWhenRevisionChangesDuringPersist() async throws {
        let master = FakeMasterPassword()
        try await master.setPassword("original-pass-word")
        let log = StepLog()
        do {
            try await AppPasswordRecovery.recoverToDeviceAuth(
                confirmMandatory: { log.add("confirm") },
                persistDeviceAuth: {
                    log.add("persist")
                    try await master.reset()
                    try await master.setPassword("other-window-pass")
                },
                resetIfRevision: { expected in
                    log.add("reset")
                    try await master.reset(expectedRevision: expected)
                },
                snapshotRevision: { await master.materialRevision() }
            )
            XCTFail("expected stale_concurrent")
        } catch let ApiRelayError.validationFailed(_, reason) {
            XCTAssertEqual(reason, "stale_concurrent")
        }
        XCTAssertEqual(log.snapshot(), ["confirm", "persist", "reset"])
        let otherKept = try await master.verify("other-window-pass")
        XCTAssertTrue(otherKept)
    }

    func testRecoverDoesNotDeleteWhenMaterialChangesBeforeExclusiveReset() async throws {
        let passwordTargets: [RevealPolicy] = [.masterPassword, .biometryOrAppPassword]
        for _ in passwordTargets {
            let env = AppEnvironment.makePreview()
            let master = try XCTUnwrap(env.masterPassword as? FakeMasterPassword)
            let prefs = try XCTUnwrap(env.preferences as? FakePreferences)
            try await master.setPassword("original-pass-word")
            await master.setBeforeExclusiveResetHook {
                try await master.changePassword(
                    current: "original-pass-word",
                    new: "other-window-pass"
                )
            }
            do {
                try await env.resetAppPasswordAndFallToDeviceAuth()
                XCTFail("expected stale_concurrent")
            } catch let ApiRelayError.validationFailed(_, reason) {
                XCTAssertEqual(reason, "stale_concurrent")
            }
            let otherKept = try await master.verify("other-window-pass")
            let originalKept = try await master.verify("original-pass-word")
            XCTAssertTrue(otherKept)
            XCTAssertFalse(originalKept)
            let loaded = try await prefs.load()
            XCTAssertEqual(loaded.revealPolicy, .biometricOrPasscode)
            XCTAssertNotEqual(loaded.revealPolicy, .noVerification)
        }
    }

    func testPersistExistingLeaseBlocksResetDuringCommit() async throws {
        let passwordTargets: [RevealPolicy] = [.masterPassword, .biometryOrAppPassword]
        for target in passwordTargets {
            let env = AppEnvironment.makePreview()
            let master = try XCTUnwrap(env.masterPassword as? FakeMasterPassword)
            let prefs = try XCTUnwrap(env.preferences as? FakePreferences)
            try await master.setPassword("keep-me-pass")
            let snapshot = await master.materialRevision()
            await master.setDuringLeaseHook {
                do {
                    try await master.reset(expectedRevision: snapshot)
                    XCTFail("lease should reject reset \(target)")
                } catch let ApiRelayError.validationFailed(_, reason) {
                    XCTAssertEqual(reason, "stale_concurrent", "\(target)")
                }
            }
            try await env.persistPasswordDependentPolicyKeepingMaterial(
                target: target,
                confirmCurrentIfNeeded: { }
            )
            let kept = try await master.verify("keep-me-pass")
            XCTAssertTrue(kept, "\(target)")
            let loaded = try await prefs.load()
            XCTAssertEqual(loaded.revealPolicy, target)
        }
    }

    func testCreateLeaseBlocksResetDuringCommit() async throws {
        let passwordTargets: [RevealPolicy] = [.masterPassword, .biometryOrAppPassword]
        for target in passwordTargets {
            let env = AppEnvironment.makePreview()
            let master = try XCTUnwrap(env.masterPassword as? FakeMasterPassword)
            let prefs = try XCTUnwrap(env.preferences as? FakePreferences)
            await master.setDuringLeaseHook {
                let snapshot = await master.materialRevision()
                do {
                    try await master.reset(expectedRevision: snapshot)
                    XCTFail("lease should reject reset \(target)")
                } catch let ApiRelayError.validationFailed(_, reason) {
                    XCTAssertEqual(reason, "stale_concurrent", "\(target)")
                }
            }
            try await env.createAppPasswordMaterialThenPersist(
                password: "keep-me-pass",
                target: target,
                confirmCurrentIfNeeded: { }
            )
            let kept = try await master.verify("keep-me-pass")
            XCTAssertTrue(kept, "\(target)")
            let loaded = try await prefs.load()
            XCTAssertEqual(loaded.revealPolicy, target)
        }
    }

    func testCreateStopsWhenRequestInvalidatedDuringCurrentConfirm() async throws {
        for target in [RevealPolicy.masterPassword, .biometryOrAppPassword] {
            let master = FakeMasterPassword()
            let lease = AppPasswordPageLease(target: target, currentPolicy: .biometricOrPasscode)
            let token = try XCTUnwrap(lease.begin())
            let log = StepLog()
            do {
                try await AppPasswordSetup.createMaterialThenPersistTarget(
                    target: target,
                    materialStatus: { await master.materialStatus() },
                    confirmCurrentIfNeeded: { lease.invalidate() },
                    confirmDeviceOwner: { XCTFail("device owner must not start \(target)") },
                    setAndVerifyMaterial: {
                        log.add("set")
                        try await master.setPassword("test-pass-word")
                    },
                    persistTarget: { _ in log.add("persist") },
                    authorize: { try lease.authorize(token, step: .proceed) }
                )
                XCTFail("stale current confirm \(target)")
            } catch ApiRelayError.validationFailed(_, let reason) where reason == "stale_page_request" {
            } catch {
                XCTFail("unexpected \(error) \(target)")
            }
            XCTAssertEqual(log.snapshot(), [], "\(target)")
            let status = await master.materialStatus()
            XCTAssertEqual(status, .unset, "\(target)")
        }
    }

    func testCreateStopsAfterDeviceOwnerBeforeMaterialWrite() async throws {
        for target in [RevealPolicy.masterPassword, .biometryOrAppPassword] {
            let master = FakeMasterPassword()
            let lease = AppPasswordPageLease(target: target, currentPolicy: .biometricOrPasscode)
            let token = try XCTUnwrap(lease.begin())
            let log = StepLog()
            do {
                try await AppPasswordSetup.createMaterialThenPersistTarget(
                    target: target,
                    materialStatus: { await master.materialStatus() },
                    confirmCurrentIfNeeded: { },
                    confirmDeviceOwner: { lease.invalidate() },
                    setAndVerifyMaterial: {
                        log.add("set")
                        try await master.setPassword("test-pass-word")
                    },
                    persistTarget: { _ in log.add("persist") },
                    authorize: { try lease.authorize(token, step: .proceed) }
                )
                XCTFail("W3/06 counterexample must now fail \(target)")
            } catch ApiRelayError.validationFailed(_, let reason) where reason == "stale_page_request" {
            } catch {
                XCTFail("unexpected \(error) \(target)")
            }
            XCTAssertEqual(log.snapshot(), [], "\(target)")
            let status = await master.materialStatus()
            XCTAssertEqual(status, .unset, "\(target)")
            let journal = await master.journal
            XCTAssertEqual(journal.callCount("setPassword"), 0, "\(target)")
        }
    }

    func testEnvironmentCreateStopsAfterDeviceOwnerIfRequestInvalidated() async throws {
        for target in [RevealPolicy.masterPassword, .biometryOrAppPassword] {
            let env = AppEnvironment.makePreview()
            let master = try XCTUnwrap(env.masterPassword as? FakeMasterPassword)
            let prefs = try XCTUnwrap(env.preferences as? FakePreferences)
            let gate = try XCTUnwrap(env.gate as? FakeRevealGate)
            let request = try liveAppPasswordSubmit(target: target, current: .biometricOrPasscode)
            let lease = request.lease
            await gate.setConfirmMandatoryHook {
                lease.invalidate()
            }
            do {
                try await env.createAppPasswordMaterialThenPersist(
                    password: "test-pass-word",
                    target: target,
                    request: request,
                    confirmCurrentIfNeeded: { }
                )
                XCTFail("stale device owner \(target)")
            } catch ApiRelayError.validationFailed(_, let reason) where reason == "stale_page_request" {
            } catch {
                XCTFail("unexpected \(error) \(target)")
            }
            let status = await master.materialStatus()
            XCTAssertEqual(status, .unset, "\(target)")
            let journal = await master.journal
            XCTAssertEqual(journal.callCount("setPassword"), 0, "\(target)")
            XCTAssertEqual(prefs.persistWriteCount(), 0, "\(target)")
            let loaded = try await prefs.load()
            XCTAssertEqual(loaded.revealPolicy, .biometricOrPasscode, "\(target)")
        }
    }

    func testMaterialWriteRefusesWhenInvalidatedDuringBusyWait() async throws {
        for target in [RevealPolicy.masterPassword, .biometryOrAppPassword] {
            let env = AppEnvironment.makePreview()
            let master = try XCTUnwrap(env.masterPassword as? FakeMasterPassword)
            let prefs = try XCTUnwrap(env.preferences as? FakePreferences)
            let request = try liveAppPasswordSubmit(target: target, current: .biometricOrPasscode)
            let lease = request.lease
            await master.setBeforeSetPasswordHook {
                lease.invalidate()
            }
            do {
                try await env.createAppPasswordMaterialThenPersist(
                    password: "test-pass-word",
                    target: target,
                    request: request,
                    confirmCurrentIfNeeded: { }
                )
                XCTFail("busy wait stale \(target)")
            } catch ApiRelayError.validationFailed(_, let reason) where reason == "stale_page_request" {
            } catch {
                XCTFail("unexpected \(error) \(target)")
            }
            let status = await master.materialStatus()
            XCTAssertEqual(status, .unset, "\(target)")
            XCTAssertEqual(prefs.persistWriteCount(), 0, "\(target)")
        }
    }

    func testMaterialKeptWhenPolicyPersistInvalidated() async throws {
        for target in [RevealPolicy.masterPassword, .biometryOrAppPassword] {
            let env = AppEnvironment.makePreview()
            let master = try XCTUnwrap(env.masterPassword as? FakeMasterPassword)
            let prefs = try XCTUnwrap(env.preferences as? FakePreferences)
            let request = try liveAppPasswordSubmit(target: target, current: .biometricOrPasscode)
            let lease = request.lease
            await prefs.setPersistDelay {
                lease.invalidate()
            }
            do {
                try await env.createAppPasswordMaterialThenPersist(
                    password: "test-pass-word",
                    target: target,
                    request: request,
                    confirmCurrentIfNeeded: { }
                )
                XCTFail("policy persist stale \(target)")
            } catch ApiRelayError.validationFailed(_, let reason) where reason == "stale_page_request" {
            } catch {
                XCTFail("unexpected \(error) \(target)")
            }
            let status = await master.materialStatus()
            XCTAssertEqual(status, .set, "\(target)")
            let kept = try await master.isSet()
            XCTAssertTrue(kept, "\(target)")
            XCTAssertEqual(prefs.persistWriteCount(), 0, "\(target)")
            let loaded = try await prefs.load()
            XCTAssertEqual(loaded.revealPolicy, .biometricOrPasscode, "\(target)")
            XCTAssertNotEqual(loaded.revealPolicy, target)
        }
    }

    func testCommittedPolicyNotRevertedByLaterInvalidation() async throws {
        for target in [RevealPolicy.masterPassword, .biometryOrAppPassword] {
            let env = AppEnvironment.makePreview()
            let master = try XCTUnwrap(env.masterPassword as? FakeMasterPassword)
            let prefs = try XCTUnwrap(env.preferences as? FakePreferences)
            let request = try liveAppPasswordSubmit(target: target, current: .biometricOrPasscode)
            try await env.createAppPasswordMaterialThenPersist(
                password: "test-pass-word",
                target: target,
                request: request,
                confirmCurrentIfNeeded: { }
            )
            request.lease.invalidate()
            let loaded = try await prefs.load()
            XCTAssertEqual(loaded.revealPolicy, target)
            let status = await master.materialStatus()
            XCTAssertEqual(status, .set, "\(target)")
        }
    }

    func testRecoveryStopsBeforeDevicePolicyPersist() async throws {
        for current in [RevealPolicy.masterPassword, .biometryOrAppPassword] {
            let env = AppEnvironment.makePreview()
            let master = try XCTUnwrap(env.masterPassword as? FakeMasterPassword)
            let prefs = try XCTUnwrap(env.preferences as? FakePreferences)
            let gate = try XCTUnwrap(env.gate as? FakeRevealGate)
            try await master.setPassword("keep-me-pass")
            try await prefs.update(PreferencesPatch(revealPolicy: current))
            let request = try liveAppPasswordSubmit(target: .biometricOrPasscode, current: current)
            let lease = request.lease
            await gate.setConfirmMandatoryHook {
                lease.invalidate()
            }
            do {
                try await env.resetAppPasswordAndFallToDeviceAuth(request: request)
                XCTFail("recovery persist stale \(current)")
            } catch ApiRelayError.validationFailed(_, let reason) where reason == "stale_page_request" {
            } catch {
                XCTFail("unexpected \(error) \(current)")
            }
            let status = await master.materialStatus()
            XCTAssertEqual(status, .set, "\(current)")
            XCTAssertEqual(prefs.persistWriteCount(), 0, "\(current)")
            let loaded = try await prefs.load()
            XCTAssertEqual(loaded.revealPolicy, current)
            XCTAssertNotEqual(loaded.revealPolicy, .noVerification)
        }
    }

    func testRecoveryStopsBeforeDeleteAfterDevicePolicySaved() async throws {
        for current in [RevealPolicy.masterPassword, .biometryOrAppPassword] {
            let env = AppEnvironment.makePreview()
            let master = try XCTUnwrap(env.masterPassword as? FakeMasterPassword)
            let prefs = try XCTUnwrap(env.preferences as? FakePreferences)
            try await master.setPassword("keep-me-pass")
            try await prefs.update(PreferencesPatch(revealPolicy: current))
            let request = try liveAppPasswordSubmit(target: .biometricOrPasscode, current: current)
            let lease = request.lease
            await master.setBeforeExclusiveResetHook {
                lease.invalidate()
            }
            do {
                try await env.resetAppPasswordAndFallToDeviceAuth(request: request)
                XCTFail("recovery delete stale \(current)")
            } catch ApiRelayError.validationFailed(_, let reason) where reason == "stale_page_request" {
            } catch {
                XCTFail("unexpected \(error) \(current)")
            }
            let status = await master.materialStatus()
            XCTAssertEqual(status, .set, "\(current)")
            let loaded = try await prefs.load()
            XCTAssertEqual(loaded.revealPolicy, .biometricOrPasscode, "\(current)")
            XCTAssertNotEqual(loaded.revealPolicy, .noVerification)
        }
    }

    func testOldEndDoesNotClearNewerRequest() throws {
        let lease = AppPasswordPageLease(
            target: .masterPassword,
            currentPolicy: .biometricOrPasscode
        )
        let first = try XCTUnwrap(lease.begin())
        lease.end(first)
        let second = try XCTUnwrap(lease.begin())
        XCTAssertNotEqual(first, second)
        lease.end(first)
        XCTAssertTrue(lease.isBusy())
        XCTAssertTrue(lease.isFresh(second, sceneActive: true))
        try lease.authorize(second, step: .proceed)
        do {
            try lease.authorize(first, step: .proceed)
            XCTFail("old token must stay stale")
        } catch ApiRelayError.validationFailed(_, let reason) where reason == "stale_page_request" {
        } catch {
            XCTFail("unexpected \(error)")
        }
        lease.invalidate()
        XCTAssertFalse(lease.isFresh(second, sceneActive: true))
    }

    func testAuthorizeInvalidateLinearizationHasSingleWinner() async throws {
        let lease = AppPasswordPageLease(
            target: .masterPassword,
            currentPolicy: .biometricOrPasscode
        )
        let token = try XCTUnwrap(lease.begin())
        let box = LinearizationBox()
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                do {
                    try lease.authorize(token, step: .materialWrite)
                    box.noteAuthorized()
                } catch {
                    box.noteRejected()
                }
            }
            group.addTask {
                lease.invalidate()
            }
            await group.waitForAll()
        }
        XCTAssertEqual(box.authorizedCount() + box.rejectedCount(), 1)
        do {
            try lease.authorize(token, step: .policyPersist)
            XCTFail("token must be stale after the race")
        } catch ApiRelayError.validationFailed(_, let reason) where reason == "stale_page_request" {
        } catch {
            XCTFail("unexpected \(error)")
        }
        if box.authorizedCount() == 1 {
            XCTAssertEqual(box.rejectedCount(), 0)
        } else {
            XCTAssertEqual(box.authorizedCount(), 0)
            XCTAssertEqual(box.rejectedCount(), 1)
        }
    }
}

@MainActor
private func makeGate(
    master: MasterPasswordServing,
    biometry: BiometryKind = .faceID,
    probe: AuthProbe
) -> RevealGate {
    return RevealGate(
        masterPassword: master,
        authenticateDeviceOwner: { reason, policy in
            try await probe.authenticate(reason, policy)
        },
        availableBiometry: { biometry }
    )
}

private final class AuthProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var policies: [LAPolicy] = []
    var error: Error?

    var callCount: Int {
        lock.lock(); defer { lock.unlock() }
        return policies.count
    }

    func snapshot() -> [LAPolicy] {
        lock.lock(); defer { lock.unlock() }
        return policies
    }

    func authenticate(_ reason: String, _ policy: LAPolicy) async throws {
        _ = reason
        try record(policy)
    }

    private func record(_ policy: LAPolicy) throws {
        lock.lock()
        policies.append(policy)
        let error = self.error
        lock.unlock()
        if let error { throw error }
    }
}

private final class StepLog: @unchecked Sendable {
    private let lock = NSLock()
    private var steps: [String] = []

    func add(_ step: String) {
        lock.lock()
        steps.append(step)
        lock.unlock()
    }

    func snapshot() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return steps
    }
}

private enum PasswordSetOutcome: Sendable {
    case success
    case failureReason(String)
}

private actor ConfirmRendezvous {
    private var waiting: CheckedContinuation<Void, Never>?

    func meet() async {
        if let waiting {
            waiting.resume()
            self.waiting = nil
        } else {
            await withCheckedContinuation { continuation in
                self.waiting = continuation
            }
        }
    }
}

private func liveAppPasswordSubmit(
    target: RevealPolicy,
    current: RevealPolicy
) throws -> AppPasswordSubmitContext {
    let lease = AppPasswordPageLease(target: target, currentPolicy: current)
    let token = try XCTUnwrap(lease.begin())
    return AppPasswordSubmitContext(lease: lease, token: token)
}

private final class LinearizationBox: @unchecked Sendable {
    private let lock = NSLock()
    private var authorized = 0
    private var rejected = 0

    func noteAuthorized() {
        lock.lock()
        authorized += 1
        lock.unlock()
    }

    func noteRejected() {
        lock.lock()
        rejected += 1
        lock.unlock()
    }

    func authorizedCount() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return authorized
    }

    func rejectedCount() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return rejected
    }
}
