@preconcurrency import XCTest
@testable import ApiRelay

@MainActor
final class SecurityPolicyChangeTests: XCTestCase {
    func testImportedPolicyNotificationClosesAuthorizationBeforePostReturns() async throws {
        let center = NotificationCenter()
        let notificationName = Notification.Name("tests.security-policy-import")
        let sessionLock = SessionLockBox()
        let oldLease = try sessionLock.captureAuthorizationLease()
        let reloadEntered = AsyncStream<Void>.makeStream()
        let allowReload = AsyncStream<Void>.makeStream()
        let reloadFinished = expectation(description: "authoritative policy reload finished")

        let fence = SecurityPolicyRefreshNotificationFence(
            center: center,
            notificationName: notificationName,
            sessionLock: sessionLock,
            decode: { notification in
                switch notification.object as? String {
                case "begin": return .began
                case "end": return .ended
                default: return nil
                }
            },
            reload: { _ in
                reloadEntered.continuation.yield(())
                for await _ in allowReload.stream { break }
                reloadFinished.fulfill()
                return true
            }
        )
        _ = fence

        center.post(name: notificationName, object: "begin")

        XCTAssertTrue(sessionLock.hasPendingSecurityPolicyRefresh())
        XCTAssertThrowsError(try sessionLock.validateAuthorizationLease(oldLease))
        XCTAssertThrowsError(
            try sessionLock.captureAuthorizationLease(),
            "the callback must fail closed synchronously, before its async reload starts"
        )

        var enteredIterator = reloadEntered.stream.makeAsyncIterator()
        center.post(name: notificationName, object: "end")
        _ = await enteredIterator.next()
        XCTAssertThrowsError(try sessionLock.captureAuthorizationLease())

        allowReload.continuation.yield(())
        allowReload.continuation.finish()
        await fulfillment(of: [reloadFinished], timeout: 1.0)
        for _ in 0..<100 where sessionLock.hasPendingSecurityPolicyRefresh() {
            await Task.yield()
        }
        XCTAssertFalse(sessionLock.hasPendingSecurityPolicyRefresh())
        XCTAssertNoThrow(try sessionLock.captureAuthorizationLease())
        reloadEntered.continuation.finish()
    }

    func testOverlappingImportedPolicyReloadCannotBeReopenedByOlderCompletion() throws {
        let sessionLock = SessionLockBox()
        let oldLease = try sessionLock.captureAuthorizationLease()
        let first = sessionLock.beginExternalSecurityPolicyRefresh()
        let second = sessionLock.beginExternalSecurityPolicyRefresh()

        XCTAssertThrowsError(try sessionLock.validateAuthorizationLease(oldLease))
        XCTAssertFalse(sessionLock.completeExternalSecurityPolicyRefresh(first))
        XCTAssertTrue(sessionLock.hasPendingSecurityPolicyRefresh())
        XCTAssertThrowsError(try sessionLock.captureAuthorizationLease())

        XCTAssertTrue(sessionLock.completeExternalSecurityPolicyRefresh(second))
        XCTAssertFalse(sessionLock.hasPendingSecurityPolicyRefresh())
        XCTAssertNoThrow(try sessionLock.captureAuthorizationLease())
    }

    func testPreContainerImportAlreadyInFlightStartsFenceDuringInitialization() {
        let center = NotificationCenter()
        let sessionLock = SessionLockBox()
        let fence = SecurityPolicyRefreshNotificationFence(
            center: center,
            notificationName: Notification.Name("tests.never-posted"),
            sessionLock: sessionLock,
            decode: { _ in nil },
            bootstrapImportInFlight: { true },
            reload: { _ in true }
        )
        _ = fence

        XCTAssertTrue(sessionLock.hasPendingSecurityPolicyRefresh())
        XCTAssertThrowsError(try sessionLock.captureAuthorizationLease())
    }

    func testImportedPolicyRevisionWinsFinalSideEffectCommitRace() throws {
        let sessionLock = SessionLockBox()
        let oldLease = try sessionLock.captureAuthorizationLease()
        let refresh = sessionLock.beginExternalSecurityPolicyRefresh()
        var sideEffects = 0

        XCTAssertThrowsError(
            try sessionLock.commitAuthorizationLease(oldLease) {
                sideEffects += 1
            }
        )
        XCTAssertEqual(sideEffects, 0)
        XCTAssertTrue(sessionLock.completeExternalSecurityPolicyRefresh(refresh))
    }

    func testFailedAuthoritativePolicyReloadRemainsFailClosed() async throws {
        let center = NotificationCenter()
        let notificationName = Notification.Name("tests.security-policy-import-failure")
        let sessionLock = SessionLockBox()
        let reloadAttempted = expectation(description: "authoritative reload attempted")
        let fence = SecurityPolicyRefreshNotificationFence(
            center: center,
            notificationName: notificationName,
            sessionLock: sessionLock,
            decode: { notification in
                (notification.object as? Bool) == true ? .ended : .began
            },
            reload: { _ in
                reloadAttempted.fulfill()
                return false
            }
        )
        _ = fence

        center.post(name: notificationName, object: false)
        center.post(name: notificationName, object: true)
        await fulfillment(of: [reloadAttempted], timeout: 1.0)
        for _ in 0..<20 { await Task.yield() }

        XCTAssertTrue(sessionLock.hasPendingSecurityPolicyRefresh())
        XCTAssertThrowsError(try sessionLock.captureAuthorizationLease())
    }

    func testTurningOffAppLockIsWeakening() {
        let current = PreferencesDTO.fakeDefault().applying(PreferencesPatch(appLockEnabled: true))
        XCTAssertTrue(SecurityPolicyChange.weakens(PreferencesPatch(appLockEnabled: false), relativeTo: current))
        XCTAssertFalse(SecurityPolicyChange.weakens(PreferencesPatch(appLockEnabled: true), relativeTo: current))
    }

    func testLongerAutoLockIsWeakening() {
        let current = PreferencesDTO.fakeDefault().applying(
            PreferencesPatch(appLockEnabled: true, autoLockSeconds: 30)
        )
        XCTAssertTrue(SecurityPolicyChange.weakens(PreferencesPatch(autoLockSeconds: 120), relativeTo: current))
        XCTAssertFalse(SecurityPolicyChange.weakens(PreferencesPatch(autoLockSeconds: 0), relativeTo: current))
    }

    func testNoVerificationIsWeakerThanBiometric() {
        let current = PreferencesDTO.fakeDefault().applying(
            PreferencesPatch(revealPolicy: .biometricOrPasscode)
        )
        XCTAssertTrue(SecurityPolicyChange.weakens(PreferencesPatch(revealPolicy: .noVerification), relativeTo: current))
        XCTAssertTrue(
            SecurityPolicyChange.weakens(PreferencesPatch(revealPolicy: .masterPassword), relativeTo: current)
        )
        XCTAssertFalse(SecurityPolicyChange.weakens(PreferencesPatch(revealPolicy: .biometricOrPasscode), relativeTo: current))
    }

    func testStrengthenFromNoVerificationIsNotWeakening() {
        let current = PreferencesDTO.fakeDefault().applying(
            PreferencesPatch(revealPolicy: .noVerification)
        )
        XCTAssertFalse(
            SecurityPolicyChange.weakens(PreferencesPatch(revealPolicy: .biometricOrPasscode), relativeTo: current)
        )
        XCTAssertFalse(
            SecurityPolicyChange.weakens(PreferencesPatch(revealPolicy: .masterPassword), relativeTo: current)
        )
        XCTAssertFalse(
            SecurityPolicyChange.weakens(PreferencesPatch(revealPolicy: .biometryOrAppPassword), relativeTo: current)
        )
    }

    func testAuthenticatedPolicySwapsAreSensitive() {
        let device = PreferencesDTO.fakeDefault().applying(
            PreferencesPatch(revealPolicy: .biometricOrPasscode)
        )
        XCTAssertTrue(
            SecurityPolicyChange.weakens(PreferencesPatch(revealPolicy: .biometryOrAppPassword), relativeTo: device)
        )
        let password = device.applying(PreferencesPatch(revealPolicy: .masterPassword))
        XCTAssertTrue(
            SecurityPolicyChange.weakens(PreferencesPatch(revealPolicy: .biometricOrPasscode), relativeTo: password)
        )
        XCTAssertTrue(
            SecurityPolicyChange.weakens(PreferencesPatch(revealPolicy: .biometryOrAppPassword), relativeTo: password)
        )
    }

    func testTurningOffRevealAuthIsWeakening() {
        let current = PreferencesDTO.fakeDefault()
        let revealAuthEnabled = current.revealAuthEnabled
        XCTAssertTrue(revealAuthEnabled)
        XCTAssertTrue(SecurityPolicyChange.weakens(PreferencesPatch(revealAuthEnabled: false), relativeTo: current))
        XCTAssertFalse(SecurityPolicyChange.weakens(PreferencesPatch(revealAuthEnabled: true), relativeTo: current))
        let off = current.applying(PreferencesPatch(revealAuthEnabled: false))
        XCTAssertFalse(SecurityPolicyChange.weakens(PreferencesPatch(revealAuthEnabled: true), relativeTo: off))
    }

    func testHideAndClipboardClearOffAreWeakening() {
        let current = PreferencesDTO.fakeDefault().applying(
            PreferencesPatch(
                clipboardClearEnabled: true,
                clipboardClearSeconds: 30,
                clipboardLocalOnly: true,
                hideInAppSwitcher: true
            )
        )
        XCTAssertTrue(SecurityPolicyChange.weakens(PreferencesPatch(hideInAppSwitcher: false), relativeTo: current))
        XCTAssertTrue(SecurityPolicyChange.weakens(PreferencesPatch(clipboardClearEnabled: false), relativeTo: current))
        XCTAssertTrue(SecurityPolicyChange.weakens(PreferencesPatch(clipboardClearSeconds: 120), relativeTo: current))
        XCTAssertFalse(SecurityPolicyChange.weakens(PreferencesPatch(clipboardClearSeconds: 0), relativeTo: current))
        XCTAssertTrue(SecurityPolicyChange.weakens(PreferencesPatch(clipboardLocalOnly: false), relativeTo: current))
        XCTAssertFalse(SecurityPolicyChange.weakens(PreferencesPatch(clipboardLocalOnly: true), relativeTo: current))
    }

    func testCurrentMethodConfirmDoesNotCallMandatory() async throws {
        let gate = FakeRevealGate()
        try await CurrentRevealPolicyAuth.confirm(
            .biometricOrPasscode,
            gate: gate,
            reason: "settings",
            purpose: .settings
        )
        let calls = await gate.journal.calls
        XCTAssertEqual(calls.filter { $0 == "confirm" }.count, 1)
        XCTAssertFalse(calls.contains("confirmMandatory"))
    }

    func testCurrentMethodConfirmSkipsAuthWhenNoVerification() async throws {
        let gate = FakeRevealGate()
        try await CurrentRevealPolicyAuth.confirm(
            .noVerification,
            gate: gate,
            reason: "settings",
            purpose: .settings
        )
        let calls = await gate.journal.calls
        XCTAssertTrue(calls.isEmpty)
    }

    func testCurrentMethodConfirmUsesAppPasswordNotDeviceOwner() async throws {
        let gate = FakeRevealGate()
        try await CurrentRevealPolicyAuth.confirm(
            .masterPassword,
            gate: gate,
            reason: "settings",
            purpose: .settings,
            appPassword: "vault-pass-word"
        )
        let calls = await gate.journal.calls
        XCTAssertTrue(calls.contains("confirmWithMasterPassword"))
        XCTAssertFalse(calls.contains("confirmMandatory"))
    }

    func testUnconfiguredAppPasswordCannotPersistAsPolicy() {
        XCTAssertFalse(
            AppPasswordPolicyGate.requiresMaterialLookup(
                for: PreferencesPatch(autoLockSeconds: 0)
            ),
            "immediate auto-lock must not wait on an unrelated Keychain material read"
        )
        XCTAssertFalse(
            AppPasswordPolicyGate.requiresMaterialLookup(
                for: PreferencesPatch(revealPolicy: .biometricOrPasscode)
            )
        )
        XCTAssertTrue(
            AppPasswordPolicyGate.requiresMaterialLookup(
                for: PreferencesPatch(revealPolicy: .masterPassword)
            )
        )
        XCTAssertTrue(
            AppPasswordPolicyGate.requiresMaterialLookup(
                for: PreferencesPatch(revealPolicy: .biometryOrAppPassword)
            )
        )
        XCTAssertFalse(
            AppPasswordPolicyGate.canPersistAsCurrentPolicy(.masterPassword, materialIsSet: false)
        )
        XCTAssertNotNil(
            AppPasswordPolicyGate.persistRejection(
                PreferencesPatch(revealPolicy: .masterPassword),
                materialIsSet: false
            )
        )
        XCTAssertTrue(
            AppPasswordPolicyGate.canPersistAsCurrentPolicy(.masterPassword, materialIsSet: true)
        )
        XCTAssertFalse(
            AppPasswordPolicyGate.canPersistAsCurrentPolicy(.biometryOrAppPassword, materialIsSet: false)
        )
        XCTAssertNotNil(
            AppPasswordPolicyGate.persistRejection(
                PreferencesPatch(revealPolicy: .biometryOrAppPassword),
                materialIsSet: false
            )
        )
        XCTAssertFalse(AppPasswordPolicyGate.canUseAppPasswordEntry(materialIsSet: false))
        XCTAssertTrue(AppPasswordPolicyGate.canUseAppPasswordEntry(materialIsSet: true))
        XCTAssertEqual(
            AppPasswordPolicyGate.ordinaryEntryUnavailableMessage(material: .unset),
            AppPasswordPolicyGate.ordinaryEntryMissingMaterialMessage()
        )
        XCTAssertEqual(
            AppPasswordPolicyGate.ordinaryEntryUnavailableMessage(material: .unreadable),
            String(localized: "settings.appPassword.status.unreadable")
        )
        XCTAssertFalse(
            AppPasswordPolicyGate.canPersistAsCurrentPolicy(
                .biometryOrAppPassword,
                material: .unreadable
            )
        )
        XCTAssertEqual(
            AppPasswordSettingsRouting.destination(selected: .masterPassword),
            .appPasswordPage(target: .masterPassword)
        )
        XCTAssertEqual(
            AppPasswordSettingsRouting.destination(selected: .biometryOrAppPassword),
            .appPasswordPage(target: .biometryOrAppPassword)
        )
        XCTAssertEqual(
            AppPasswordSettingsRouting.destination(selected: .biometricOrPasscode),
            .persistPolicy(.biometricOrPasscode)
        )
        XCTAssertTrue(AppPasswordSettingsRouting.showsHomeManagementRow(currentPolicy: .masterPassword))
        XCTAssertTrue(
            AppPasswordSettingsRouting.showsHomeManagementRow(currentPolicy: .biometryOrAppPassword)
        )
        XCTAssertFalse(
            AppPasswordSettingsRouting.showsHomeManagementRow(currentPolicy: .biometricOrPasscode)
        )
        XCTAssertFalse(AppPasswordSettingsRouting.showsHomeManagementRow(currentPolicy: .noVerification))
        XCTAssertTrue(
            AppPasswordSettingsRouting.isManagingCurrent(
                target: .biometryOrAppPassword,
                current: .biometryOrAppPassword
            )
        )
        XCTAssertFalse(
            AppPasswordSettingsRouting.isManagingCurrent(
                target: .biometryOrAppPassword,
                current: .masterPassword
            )
        )
    }

    func testAppPasswordPageSurfaceMatrixForBothTargets() {
        let targets: [RevealPolicy] = [.masterPassword, .biometryOrAppPassword]
        let currents: [RevealPolicy] = [
            .noVerification,
            .biometricOrPasscode,
            .masterPassword,
            .biometryOrAppPassword
        ]
        let materials: [AppPasswordMaterialStatus] = [.unset, .set, .unreadable]
        var cells = 0
        for target in targets {
            for current in currents {
                for material in materials {
                    let surface = AppPasswordPageSurface(
                        target: target,
                        currentPolicy: current,
                        material: material
                    )
                    XCTAssertTrue(surface.isLoaded)
                    XCTAssertTrue(surface.showsRecover, "\(target) \(current) \(material)")
                    XCTAssertEqual(surface.showsCreateForm, material == .unset)
                    XCTAssertEqual(surface.showsChangePassword, material == .set)
                    XCTAssertEqual(surface.showsRetry, material == .unreadable)
                    XCTAssertEqual(surface.showsUnreadableBanner, material == .unreadable)
                    XCTAssertEqual(
                        surface.showsKeepExisting,
                        material == .set && !surface.isManagingCurrent
                    )
                    XCTAssertEqual(
                        surface.showsCurrentMasterPasswordField,
                        material == .set
                            && current == .masterPassword
                            && surface.showsKeepExisting
                    )
                    XCTAssertEqual(
                        surface.showsComboExplicitPasswordField,
                        material == .set
                            && current == .biometryOrAppPassword
                            && surface.showsKeepExisting
                    )
                    XCTAssertEqual(
                        surface.isManagingCurrent,
                        AppPasswordSettingsRouting.isManagingCurrent(
                            target: target,
                            current: current
                        )
                    )
                    cells += 1
                }
            }
        }
        XCTAssertEqual(cells, 24)
        let loading = AppPasswordPageSurface(
            target: .masterPassword,
            currentPolicy: .masterPassword,
            material: nil
        )
        XCTAssertTrue(loading.showsLoading)
        XCTAssertFalse(loading.showsCreateForm)
        XCTAssertFalse(loading.showsRecover)
    }

    func testSettingsConfirmRequiresCurrentMasterPasswordWhenSet() async throws {
        let gate = FakeRevealGate()
        let master = FakeMasterPassword()
        try await master.setPassword("keep-me-pass")
        do {
            try await AppPasswordSettingsFlow.confirmCurrent(
                gate: gate,
                master: master,
                currentPolicy: .masterPassword,
                currentPassword: "",
                combinationAppPassword: nil,
                prefersCombinationAppPassword: false
            )
            XCTFail("empty current password must not skip master confirm")
        } catch ApiRelayError.validationFailed(_, let reason)
            where reason == "master_password_prompt_required"
        {
        } catch {
            XCTFail("unexpected \(error)")
        }
        let calls = await gate.journal.calls
        XCTAssertFalse(calls.contains("confirmWithMasterPassword"))
        XCTAssertFalse(calls.contains("confirmMandatory"))
    }

    func testSettingsConfirmMasterPasswordWhenSetUsesCurrentPassword() async throws {
        let gate = FakeRevealGate()
        let master = FakeMasterPassword()
        try await master.setPassword("keep-me-pass")
        try await AppPasswordSettingsFlow.confirmCurrent(
            gate: gate,
            master: master,
            currentPolicy: .masterPassword,
            currentPassword: "keep-me-pass",
            combinationAppPassword: nil,
            prefersCombinationAppPassword: false
        )
        let calls = await gate.journal.calls
        XCTAssertTrue(calls.contains("confirmWithMasterPassword"))
        XCTAssertFalse(calls.contains("confirmMandatory"))
    }

    func testSettingsConfirmSkipsMissingMasterPasswordSoRecoveryCanRun() async throws {
        let gate = FakeRevealGate()
        let master = FakeMasterPassword()
        try await AppPasswordSettingsFlow.confirmCurrent(
            gate: gate,
            master: master,
            currentPolicy: .masterPassword,
            currentPassword: "",
            combinationAppPassword: nil,
            prefersCombinationAppPassword: false
        )
        let calls = await gate.journal.calls
        XCTAssertTrue(calls.isEmpty)
    }

    func testSettingsConfirmComboCanUseBiometryOrExplicitAppPassword() async throws {
        let master = FakeMasterPassword()
        try await master.setPassword("keep-me-pass")
        let biometryGate = FakeRevealGate()
        try await AppPasswordSettingsFlow.confirmCurrent(
            gate: biometryGate,
            master: master,
            currentPolicy: .biometryOrAppPassword,
            currentPassword: "",
            combinationAppPassword: nil,
            prefersCombinationAppPassword: false
        )
        let biometryCalls = await biometryGate.journal.calls
        XCTAssertTrue(biometryCalls.contains("confirm"))
        XCTAssertFalse(biometryCalls.contains("confirmCombinationWithAppPassword"))
        XCTAssertFalse(biometryCalls.contains("confirmMandatory"))

        let passwordGate = FakeRevealGate()
        try await AppPasswordSettingsFlow.confirmCurrent(
            gate: passwordGate,
            master: master,
            currentPolicy: .biometryOrAppPassword,
            currentPassword: "",
            combinationAppPassword: "keep-me-pass",
            prefersCombinationAppPassword: true
        )
        let passwordCalls = await passwordGate.journal.calls
        XCTAssertTrue(passwordCalls.contains("confirmCombinationWithAppPassword"))
        XCTAssertFalse(passwordCalls.contains("confirmMandatory"))
        XCTAssertFalse(passwordCalls.contains("confirm"))
    }

    func testSettingsConfirmComboExplicitEmptyPasswordDoesNotFallToDeviceOwner() async throws {
        let gate = FakeRevealGate()
        let master = FakeMasterPassword()
        try await master.setPassword("keep-me-pass")
        do {
            try await AppPasswordSettingsFlow.confirmCurrent(
                gate: gate,
                master: master,
                currentPolicy: .biometryOrAppPassword,
                currentPassword: "",
                combinationAppPassword: "",
                prefersCombinationAppPassword: true
            )
            XCTFail("empty explicit combo password must not proceed")
        } catch ApiRelayError.validationFailed(_, let reason)
            where reason == "combination_password_empty"
        {
        } catch {
            XCTFail("unexpected \(error)")
        }
        let calls = await gate.journal.calls
        XCTAssertFalse(calls.contains("confirmMandatory"))
        XCTAssertFalse(calls.contains("confirmCombinationWithAppPassword"))
    }

    func testAppPasswordPageLeaseRejectsReentryAndStaleConfirm() throws {
        let lease = AppPasswordPageLease(
            target: .biometryOrAppPassword,
            currentPolicy: .masterPassword
        )
        let token = try XCTUnwrap(lease.begin())
        XCTAssertNil(lease.begin())
        lease.end(token)
        let next = try XCTUnwrap(lease.begin())
        lease.invalidate()
        XCTAssertFalse(lease.isFresh(next, sceneActive: true))
        XCTAssertFalse(lease.isFresh(next, sceneActive: false))
        do {
            try lease.requireFreshForConfirm(
                next,
                currentPolicy: .masterPassword,
                sceneActive: true
            )
            XCTFail("invalidated request must not confirm")
        } catch ApiRelayError.validationFailed(_, let reason) where reason == "stale_page_request" {
        } catch {
            XCTFail("unexpected \(error)")
        }
    }
}
