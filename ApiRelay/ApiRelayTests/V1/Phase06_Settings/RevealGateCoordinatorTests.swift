@preconcurrency import XCTest
@testable import ApiRelay
import LocalAuthentication
import Combine

@MainActor
final class RevealGateCoordinatorTests: XCTestCase {
    func testAuthPurposeHasOneExplicitRequestOwner() {
        XCTAssertEqual(AuthPurpose.unlockApp.requestOwner, .appUnlock)
        XCTAssertEqual(AuthPurpose.recovery.requestOwner, .recovery)
        XCTAssertEqual(AuthPurpose.revealSecret.requestOwner, .content)
        XCTAssertEqual(AuthPurpose.destructive.requestOwner, .content)
        XCTAssertEqual(AuthPurpose.settings.requestOwner, .content)
    }

    func testStaleSameOwnerCleanupCannotCancelReplacementRequest() throws {
        let coordinator = AuthenticationRequestCoordinator()
        let requestA = try coordinator.begin(owner: .content)
        let requestB = try coordinator.begin(owner: .content)

        // A -> B -> delayed cleanup from A. Owner-level cancellation here would
        // incorrectly revoke B because both screens belong to `.content`.
        coordinator.cancel(request: requestA)

        XCTAssertTrue(coordinator.isActive(owner: .content))
        XCTAssertNoThrow(try coordinator.throwIfCancelled(requestB))
        XCTAssertThrowsError(try coordinator.throwIfCancelled(requestA))

        coordinator.cancel(request: requestB)
        XCTAssertFalse(coordinator.isActive())
    }

    func testOldPageScopeCleanupCannotCancelNewPageRequest() async throws {
        let firstStarted = XCTestExpectation(description: "page-a-started")
        let secondStarted = XCTestExpectation(description: "page-b-started")
        let firstRelease = AsyncStream<Void>.makeStream()
        let secondRelease = AsyncStream<Void>.makeStream()
        let gate = RevealGate(masterPassword: FakeMasterPassword()) { reason, _ in
            if reason == "page-a" {
                firstStarted.fulfill()
                for await _ in firstRelease.stream { break }
            } else {
                secondStarted.fulfill()
                for await _ in secondRelease.stream { break }
            }
        }
        let pageA = AuthenticationRequestScope()
        let pageB = AuthenticationRequestScope()

        let requestA = Task {
            try await pageA.perform {
                try await gate.confirmMandatory(reason: "page-a", purpose: .settings)
            }
        }
        await fulfillment(of: [firstStarted], timeout: 2)

        let requestB = Task {
            try await pageB.perform {
                try await gate.confirmMandatory(reason: "page-b", purpose: .settings)
            }
        }
        await fulfillment(of: [secondStarted], timeout: 2)

        // Delayed onDisappear from A must use A's exact scope. It is a no-op
        // against B even though both requests share the `.content` owner.
        pageA.cancel()
        XCTAssertTrue(gate.isAuthenticationInProgress(owner: .content))

        secondRelease.continuation.yield(())
        secondRelease.continuation.finish()
        try await requestB.value

        firstRelease.continuation.yield(())
        firstRelease.continuation.finish()
        do {
            try await requestA.value
            XCTFail("the replaced page-A request must remain cancelled")
        } catch ApiRelayError.authenticationCancelled {
            // expected
        }
    }

    func testContentCancellationCannotRevokeAppUnlockOwner() async throws {
        let started = XCTestExpectation(description: "unlock-started")
        let release = AsyncStream<Void>.makeStream()
        let gate = RevealGate(masterPassword: FakeMasterPassword()) { _, _ in
            started.fulfill()
            for await _ in release.stream { break }
        }

        let unlock = Task {
            try await gate.confirmMandatory(reason: "unlock", purpose: .unlockApp)
        }
        await fulfillment(of: [started], timeout: 2)
        XCTAssertTrue(gate.isAuthenticationInProgress(owner: .appUnlock))

        gate.cancelAuthentication(owner: .content)

        XCTAssertTrue(
            gate.isAuthenticationInProgress(owner: .appUnlock),
            "A hidden content screen must not revoke the lock-screen request"
        )
        release.continuation.yield(())
        release.continuation.finish()
        try await unlock.value
        XCTAssertFalse(gate.isAuthenticationInProgress())
    }

    func testContentCancellationCannotRevokeAppPasswordUnlockOwner() async throws {
        let started = XCTestExpectation(description: "password-verify-started")
        let release = AsyncStream<Void>.makeStream()
        let master = FakeMasterPassword()
        try await master.setPassword("test-pass-word")
        await master.setBeforeVerifyHook {
            started.fulfill()
            for await _ in release.stream { break }
        }
        let gate = RevealGate(masterPassword: master)
        let unlock = Task {
            try await gate.confirmWithMasterPassword(
                reason: "unlock",
                password: "test-pass-word",
                purpose: .unlockApp
            )
        }
        await fulfillment(of: [started], timeout: 2)

        gate.cancelAuthentication(owner: .content)

        XCTAssertTrue(gate.isAuthenticationInProgress(owner: .appUnlock))
        release.continuation.yield(())
        release.continuation.finish()
        try await unlock.value
    }

    func testContentCancellationCannotRevokeRecoveryOwner() async throws {
        let started = XCTestExpectation(description: "recovery-started")
        let release = AsyncStream<Void>.makeStream()
        let gate = RevealGate(masterPassword: FakeMasterPassword()) { _, _ in
            started.fulfill()
            for await _ in release.stream { break }
        }
        let recovery = Task {
            try await gate.confirmMandatory(reason: "recovery", purpose: .recovery)
        }
        await fulfillment(of: [started], timeout: 2)

        gate.cancelAuthentication(owner: .content)

        XCTAssertTrue(gate.isAuthenticationInProgress(owner: .recovery))
        release.continuation.yield(())
        release.continuation.finish()
        try await recovery.value
    }

    func testContentRequestCannotPreemptAppUnlockOwner() async throws {
        let started = XCTestExpectation(description: "unlock-started")
        let release = AsyncStream<Void>.makeStream()
        let gate = RevealGate(masterPassword: FakeMasterPassword()) { reason, _ in
            if reason == "unlock" {
                started.fulfill()
                for await _ in release.stream { break }
            } else {
                XCTFail("The blocked content request must not reach the system evaluator")
            }
        }
        let unlock = Task {
            try await gate.confirmMandatory(reason: "unlock", purpose: .unlockApp)
        }
        await fulfillment(of: [started], timeout: 2)

        do {
            try await gate.confirmMandatory(reason: "content", purpose: .settings)
            XCTFail("Content must not replace an active app unlock")
        } catch ApiRelayError.authenticationCancelled {
        }
        XCTAssertTrue(gate.isAuthenticationInProgress(owner: .appUnlock))
        release.continuation.yield(())
        release.continuation.finish()
        try await unlock.value
    }

    func testCancelAllRevokesProtectedUnlock() async throws {
        let started = XCTestExpectation(description: "unlock-started")
        let release = AsyncStream<Void>.makeStream()
        let gate = RevealGate(masterPassword: FakeMasterPassword()) { _, _ in
            started.fulfill()
            for await _ in release.stream { break }
        }
        let unlock = Task {
            try await gate.confirmMandatory(reason: "unlock", purpose: .unlockApp)
        }
        await fulfillment(of: [started], timeout: 2)

        gate.cancelAllAuthentication()
        release.continuation.yield(())
        release.continuation.finish()

        do {
            try await unlock.value
            XCTFail("True background/global cancellation must revoke app unlock")
        } catch ApiRelayError.authenticationCancelled {
        }
        XCTAssertFalse(gate.isAuthenticationInProgress())
    }

    func testCancellationOfReplacedTaskCannotCancelNewRequest() async throws {
        let firstStarted = XCTestExpectation(description: "first-started")
        let secondStarted = XCTestExpectation(description: "second-started")
        let firstRelease = AsyncStream<Void>.makeStream()
        let secondRelease = AsyncStream<Void>.makeStream()
        let gate = RevealGate(masterPassword: FakeMasterPassword()) { reason, _ in
            if reason == "first" {
                firstStarted.fulfill()
                for await _ in firstRelease.stream { break }
            } else {
                secondStarted.fulfill()
                for await _ in secondRelease.stream { break }
            }
        }
        let first = Task {
            try await gate.confirmMandatory(reason: "first", purpose: .settings)
        }
        await fulfillment(of: [firstStarted], timeout: 2)
        let second = Task {
            try await gate.confirmMandatory(reason: "second", purpose: .settings)
        }
        await fulfillment(of: [secondStarted], timeout: 2)

        first.cancel()
        XCTAssertTrue(gate.isAuthenticationInProgress(owner: .content))
        secondRelease.continuation.yield(())
        secondRelease.continuation.finish()
        try await second.value
        firstRelease.continuation.yield(())
        firstRelease.continuation.finish()
        do {
            try await first.value
            XCTFail("The replaced request must remain cancelled")
        } catch ApiRelayError.authenticationCancelled {
        }
    }

    func testInjectedSystemAuthStillExecutesProductionReturnBoundary() async throws {
        let returnStarted = XCTestExpectation(description: "return-boundary-started")
        let releaseReturn = AsyncStream<Void>.makeStream()
        let gate = RevealGate(
            masterPassword: FakeMasterPassword(),
            authenticateDeviceOwner: { _, _ in },
            awaitAuthenticationReturn: {
                returnStarted.fulfill()
                for await _ in releaseReturn.stream { break }
            }
        )
        let unlock = Task {
            try await gate.confirmMandatory(reason: "unlock", purpose: .unlockApp)
        }

        await fulfillment(of: [returnStarted], timeout: 2)
        XCTAssertTrue(gate.isAuthenticationInProgress(owner: .appUnlock))
        gate.cancelAuthentication(owner: .content)
        releaseReturn.continuation.yield(())
        releaseReturn.continuation.finish()
        try await unlock.value
    }

    func testLockedVaultSessionSubscriberDoesNotCancelSuccessfulUnlock() async throws {
        let started = XCTestExpectation(description: "authentication started")
        let release = AsyncStream<Void>.makeStream()
        let gate = RevealGate(masterPassword: FakeMasterPassword()) { _, _ in
            started.fulfill()
            for await _ in release.stream { break }
        }
        let vm = try await makeVaultHomeViewModel(gateOverride: gate)
        let privacy = vm.environment.appPrivacy
        var patch = PreferencesPatch()
        patch.appLockEnabled = true
        patch.revealPolicy = .biometricOrPasscode
        try await vm.environment.preferences.update(patch)
        await privacy.start()
        XCTAssertTrue(privacy.session.isSessionLocked)
        // This is the actual subscription in the still-mounted, hidden VaultHomeView.
        let subscription = privacy.$session.sink { session in
            if session.isSessionLocked { vm.handleSessionLocked() }
        }
        defer { subscription.cancel() }
        let unlock = Task { await privacy.promptUnlock(force: true) }
        await fulfillment(of: [started], timeout: 2)
        // The system sheet closes before the gate completes its return checks.
        privacy.handleDidBecomeActive()
        XCTAssertTrue(gate.isAuthenticationInProgress(), "Hidden vault cleanup must not cancel app unlock")
        release.continuation.yield(())
        release.continuation.finish()
        await unlock.value
        XCTAssertFalse(privacy.session.isSessionLocked)
        XCTAssertNil(privacy.unlockError)
    }

    func testNewRequestCancelsThePreviousOne() async throws {
        let keychain = KeychainStore.makeForTests()
        let master = MasterPasswordService(keychain: keychain, calibratedIterations: 10_000)
        try? await master.reset()
        let firstStarted = XCTestExpectation(description: "first-started")
        let gate = RevealGate(masterPassword: master) { reason, _ in
            if reason == "first" {
                firstStarted.fulfill()
                try await Task.sleep(for: .milliseconds(400))
            }
        }
        async let first: Void = {
            do {
                try await gate.confirmMandatory(reason: "first", purpose: .settings)
                XCTFail("first request should be cancelled")
            } catch ApiRelayError.authenticationCancelled {
            }
        }()
        await fulfillment(of: [firstStarted], timeout: 1)
        try await gate.confirmMandatory(reason: "second", purpose: .settings)
        _ = try await first
    }

    func testReuseGrantOnlyAfterSuccessfulAuthenticatedDisplay() {
        let instance = UUID()
        let key = UUID()
        let otherInstance = UUID()
        let otherKey = UUID()
        let token = SecretRevealReuseToken.unissuedForTesting()

        XCTAssertNil(
            DetailRevealReuse.established(
                instanceID: instance,
                keyId: key,
                token: token,
                displayedSuccessfully: false,
                authentication: .verified
            ),
            "取消、失败或只显示掩码不得建授权"
        )
        XCTAssertNil(
            DetailRevealReuse.established(
                instanceID: instance,
                keyId: key,
                token: nil,
                displayedSuccessfully: true,
                authentication: .verified
            ),
            "没有服务端 token 不得建授权"
        )
        XCTAssertNil(
            DetailRevealReuse.established(
                instanceID: instance,
                keyId: key,
                token: token,
                displayedSuccessfully: true,
                authentication: .notRequired
            ),
            "不验证或取用关闭不得制造伪授权"
        )

        let grant = DetailRevealReuse.established(
            instanceID: instance,
            keyId: key,
            token: token,
            displayedSuccessfully: true,
            authentication: .verified
        )
        XCTAssertNotNil(grant)
        XCTAssertTrue(grant!.allowsImmediateCopy(instanceID: instance, keyId: key))
        XCTAssertFalse(grant!.allowsImmediateCopy(instanceID: otherInstance, keyId: key), "另一详情实例不得复用")
        XCTAssertFalse(grant!.allowsImmediateCopy(instanceID: instance, keyId: otherKey), "另一 key 不得复用")
    }

    func testReuseGrantClearReasonsInvalidateCopyViaProductionSeam() async throws {
        let vm = try await makeVaultHomeViewModel()
        let instance = UUID()
        let key = UUID()
        let events: [(String, () -> Void)] = [
            ("closeDetail", { vm.invalidateRevealReuseCloseDetail() }),
            ("switchKey", { vm.invalidateRevealReuseSwitchKey() }),
            ("leaveForeground", { vm.invalidateRevealReuseLeaveForeground() }),
            ("autoLock", { vm.invalidateRevealReuseAutoLock() }),
            ("sessionLock", { vm.invalidateRevealReuseSessionLock() }),
            ("windowDestroyed", { vm.invalidateRevealReuseWindowDestroyed() }),
            ("beginEdit", { vm.invalidateRevealReuseBeginEdit() }),
        ]
        for (name, invalidate) in events {
            let token = SecretRevealReuseToken.unissuedForTesting()
            vm.applyDetailRevealReuse(
                .authenticatedViewSucceeded(instanceID: instance, keyId: key, token: token)
            )
            XCTAssertTrue(vm.hasRevealReuseToken(instanceID: instance, keyId: key), name)
            invalidate()
            XCTAssertFalse(vm.hasRevealReuseToken(instanceID: instance, keyId: key), name)
        }
    }

    func testReuseInvalidationProductionWiringWouldFailIfEventSitesRemoved() throws {
        let keyDetail = try Self.productionSource("UI/Vault/KeyDetailView.swift")
        let vaultHome = try Self.productionSource("UI/Vault/VaultHomeView.swift")
        XCTAssertTrue(
            keyDetail.contains("viewModel.invalidateRevealReuseLeaveForeground()"),
            "离前台必须调用生产失效方法"
        )
        XCTAssertTrue(
            keyDetail.contains("viewModel.invalidateRevealReuseWindowDestroyed()"),
            "窗口销毁必须调用生产失效方法"
        )
        XCTAssertTrue(
            keyDetail.contains("viewModel.invalidateRevealReuseBeginEdit()"),
            "开始编辑必须调用生产失效方法"
        )
        XCTAssertTrue(
            keyDetail.contains("viewModel.invalidateRevealReuseSwitchKey()"),
            "详情换 key 必须调用生产失效方法"
        )
        XCTAssertTrue(
            keyDetail.contains("viewModel.handleSessionLocked()"),
            "详情会话锁必须接到 handleSessionLocked"
        )
        XCTAssertTrue(
            keyDetail.contains(
                "if !isTransientSystemAuthentication {\n                    leaveEditing(clearUnlock: true)"
            ),
            "真实离前台必须退出编辑并清掉 draftSecret；系统认证产生的短暂 inactive 除外"
        )
        XCTAssertTrue(
            keyDetail.contains(
                "viewModel.handleSessionLocked()\n                leaveEditing(clearUnlock: true)"
            ),
            "会话锁定必须同步退出编辑并清掉 originalSecret/draftSecret"
        )
        XCTAssertTrue(
            vaultHome.contains("viewModel.invalidateRevealReuseCloseDetail()"),
            "关详情必须调用生产失效方法"
        )
        XCTAssertTrue(
            vaultHome.contains("viewModel.invalidateRevealReuseSwitchKey()"),
            "列表换 key 必须调用生产失效方法"
        )
        XCTAssertTrue(
            vaultHome.contains("viewModel.handleSessionLocked()"),
            "自动锁/会话锁必须接到 handleSessionLocked"
        )
        XCTAssertTrue(
            vaultHome.contains("viewModel.abandonCombinationPending()"),
            "切页必须清组合档待办"
        )
        XCTAssertTrue(
            vaultHome.contains("viewModel.invalidateRevealReuseForSecuritySettingsChange()"),
            "安全设置变化必须清旧授权"
        )
    }

    func testCopyWithoutDisplayDoesNotEstablishGrant() {
        let copyFirst = DetailRevealReuse.established(
            instanceID: UUID(),
            keyId: UUID(),
            token: SecretRevealReuseToken.unissuedForTesting(),
            displayedSuccessfully: false,
            authentication: .verified
        )
        XCTAssertNil(copyFirst, "复制后查看不得把复制当成查看授权")
    }

    func testUnauthenticatedDisplayEventDoesNotCreateGrant() async throws {
        let vm = try await makeVaultHomeViewModel()
        let instance = UUID()
        let key = UUID()
        vm.noteRevealDisplay(
            instanceID: instance,
            keyId: key,
            result: SecretRevealResult(secret: "sk-plain", authentication: .notRequired)
        )
        XCTAssertFalse(vm.hasRevealReuseToken(instanceID: instance, keyId: key))
        vm.noteRevealDisplay(
            instanceID: instance,
            keyId: key,
            result: SecretRevealResult(secret: "sk-plain", authentication: .notRequired)
        )
        XCTAssertFalse(vm.hasRevealReuseToken(instanceID: instance, keyId: key))
        let token = SecretRevealReuseToken.unissuedForTesting()
        vm.noteRevealDisplay(
            instanceID: instance,
            keyId: key,
            result: SecretRevealResult(
                secret: "sk-plain",
                authentication: .verified,
                reuseToken: token
            )
        )
        XCTAssertTrue(vm.hasRevealReuseToken(instanceID: instance, keyId: key))
        XCTAssertEqual(vm.takeRevealReuseTokenIfAllowed(instanceID: instance, keyId: key), token)
        XCTAssertFalse(vm.hasRevealReuseToken(instanceID: instance, keyId: key))
    }

    func testUnauthenticatedDisplayAndCancelClearExistingGrant() async throws {
        let vm = try await makeVaultHomeViewModel()
        let instance = UUID()
        let key = UUID()
        vm.applyDetailRevealReuse(
            .authenticatedViewSucceeded(
                instanceID: instance,
                keyId: key,
                token: .unissuedForTesting()
            )
        )
        XCTAssertTrue(vm.hasRevealReuseToken(instanceID: instance, keyId: key))
        vm.applyDetailRevealReuse(.unauthenticatedDisplay)
        XCTAssertFalse(vm.hasRevealReuseToken(instanceID: instance, keyId: key))

        vm.applyDetailRevealReuse(
            .authenticatedViewSucceeded(
                instanceID: instance,
                keyId: key,
                token: .unissuedForTesting()
            )
        )
        vm.applyDetailRevealReuse(.viewCancelledOrFailed)
        XCTAssertFalse(vm.hasRevealReuseToken(instanceID: instance, keyId: key))

        vm.applyDetailRevealReuse(
            .authenticatedViewSucceeded(
                instanceID: instance,
                keyId: key,
                token: .unissuedForTesting()
            )
        )
        vm.invalidateRevealReuseForSecuritySettingsChange()
        XCTAssertFalse(vm.hasRevealReuseToken(instanceID: instance, keyId: key))
    }

    func testCombinationConfirmWithoutPasswordUsesSystemDeviceOwnerPathOnce() async throws {
        let gate = FakeRevealGate()
        try await CurrentRevealPolicyAuth.confirm(
            .biometryOrAppPassword,
            gate: gate,
            reason: "combo",
            purpose: .settings
        )
        let journal = await gate.journal
        XCTAssertEqual(journal.callCount("confirm"), 1)
        XCTAssertEqual(journal.callCount("confirmCombinationWithAppPassword"), 0)
        XCTAssertEqual(journal.callCount("confirmWithMasterPassword"), 0)
        XCTAssertEqual(journal.callCount("confirmMandatory"), 0)
    }

    func testCombinationPendingDoesNotArmNextOperationAndClearsOnLeave() async throws {
        XCTAssertFalse(
            CombinationExplicitAuth.shouldShowExplicitEntry(
                hasBoundOperation: false,
                policy: .biometryOrAppPassword
            )
        )
        XCTAssertTrue(
            CombinationExplicitAuth.shouldShowExplicitEntry(
                hasBoundOperation: true,
                policy: .biometryOrAppPassword
            )
        )
        XCTAssertFalse(
            CombinationExplicitAuth.shouldShowExplicitEntry(
                hasBoundOperation: true,
                policy: .biometricOrPasscode
            )
        )

        let vm = try await makeVaultHomeViewModel()
        XCTAssertFalse(vm.hasPendingSensitiveRetry)
        await vm.beginCombinationAppPasswordEntry()
        XCTAssertFalse(vm.presentMasterPasswordPrompt)
        XCTAssertFalse(vm.offerCombinationAppPassword)

        let container = try AppSchema.makeInMemoryContainer()
        let keychain = KeychainStore.makeForTests()
        let fake = FakeRevealGate()
        await fake.setAppPasswordMaterialSet(true)
        await fake.fail("confirm", with: .authenticationCancelled)
        var patch = PreferencesPatch()
        patch.revealPolicy = .biometryOrAppPassword
        patch.revealAuthEnabled = true
        try await UserPreferencesRepository(modelContainer: container).update(patch)
        let prefs = FakePreferences()
        try await prefs.update(patch)
        let master = FakeMasterPassword()
        let privacy = AppPrivacyController(
            gate: fake,
            preferences: prefs,
            masterPassword: master,
            installsSnapshotCover: false,
            enablesUnlockPrompt: false,
            launchAppLockEnabled: false
        )
        await privacy.start()
        privacy.applyLivePreferences(
            AppLockPreferences(
                appLockEnabled: false,
                autoLockSeconds: 60,
                hideInAppSwitcher: true,
                revealPolicy: .biometryOrAppPassword
            )
        )
        let vault = KeyVaultService(
            keychain: keychain,
            gate: fake,
            clipboard: SecureClipboard(),
            modelContainer: container,
            entitlements: StubEntitlements(tier: .unlimitedKeys)
        )
        let env = AppEnvironment(
            modelContainer: container,
            keychain: FakeKeychain(),
            masterPassword: master,
            gate: fake,
            clipboard: FakeClipboard(),
            vault: vault,
            consumerTools: FakeConsumerTools(),
            trashBatch: FakeRecentlyDeletedBatch(),
            entitlements: FakeEntitlements(tier: .unlimitedKeys),
            preferences: prefs,
            backups: FakeSecureBackup(),
            backupPassphrase: FakeBackupPassphrase(),
            dataLifecycle: FakeDataLifecycle(),
            cloudSync: FakeCloudSync(),
            appPrivacy: privacy
        )
        let pendingVM = VaultHomeViewModel(environment: env)
        let accountId = try await vault.createAccount(
            UpstreamAccountDraft(platform: "openai", displayName: "A")
        )
        let keyId = try await vault.createKey(
            KeyDraft(accountId: accountId, displayName: "k"),
            secret: "sk-combo-abandon-aaaa"
        )
        await pendingVM.deleteKey(keyId)
        XCTAssertTrue(pendingVM.hasPendingSensitiveRetry)
        pendingVM.invalidateRevealReuseCloseDetail()
        XCTAssertFalse(pendingVM.hasPendingSensitiveRetry)
        XCTAssertFalse(pendingVM.offerCombinationAppPassword)
        XCTAssertFalse(pendingVM.presentMasterPasswordPrompt)
        var remaining = try await vault.keys(in: accountId).map(\.id)
        XCTAssertEqual(remaining, [keyId])

        await pendingVM.deleteKey(keyId)
        XCTAssertTrue(pendingVM.hasPendingSensitiveRetry)
        pendingVM.handleSessionLocked()
        XCTAssertFalse(pendingVM.hasPendingSensitiveRetry)
        remaining = try await vault.keys(in: accountId).map(\.id)
        XCTAssertEqual(remaining, [keyId])

        await pendingVM.deleteKey(keyId)
        XCTAssertTrue(pendingVM.hasPendingSensitiveRetry)
        pendingVM.abandonCombinationPending()
        await pendingVM.beginCombinationAppPasswordEntry()
        XCTAssertFalse(pendingVM.presentMasterPasswordPrompt)
        remaining = try await vault.keys(in: accountId).map(\.id)
        XCTAssertEqual(remaining, [keyId])
    }

    func testCombinationConfirmWithPasswordUsesExplicitEntryOnce() async throws {
        let gate = FakeRevealGate()
        try await CurrentRevealPolicyAuth.confirm(
            .biometryOrAppPassword,
            gate: gate,
            reason: "combo",
            purpose: .settings,
            appPassword: "combo-pass-word"
        )
        let journal = await gate.journal
        XCTAssertEqual(journal.callCount("confirmCombinationWithAppPassword"), 1)
        XCTAssertEqual(journal.callCount("confirm"), 0)
        XCTAssertEqual(journal.callCount("confirmWithMasterPassword"), 0)
        XCTAssertEqual(journal.callCount("confirmMandatory"), 0)
    }

    func testCombinationEmptyPasswordRejectedBeforeGate() async throws {
        let gate = FakeRevealGate()
        do {
            try await CurrentRevealPolicyAuth.confirm(
                .biometryOrAppPassword,
                gate: gate,
                reason: "combo",
                purpose: .settings,
                appPassword: "   "
            )
            XCTFail("empty combination password must be rejected before the gate")
        } catch ApiRelayError.validationFailed(_, let reason) {
            XCTAssertEqual(reason, "combination_password_empty")
        }
        let journal = await gate.journal
        XCTAssertTrue(journal.calls.isEmpty)
    }

    func testCombinationSystemCancellationMayOfferExplicitAppPassword() {
        XCTAssertTrue(
            CombinationExplicitAuth.shouldOfferAppPassword(after: ApiRelayError.authenticationCancelled)
        )
        XCTAssertTrue(
            CombinationExplicitAuth.shouldOfferAppPassword(after: ApiRelayError.biometryUnavailable)
        )
        XCTAssertTrue(
            CombinationExplicitAuth.shouldOfferAppPassword(after: ApiRelayError.biometryLockout)
        )
        XCTAssertFalse(
            CombinationExplicitAuth.shouldOfferAppPassword(after: ApiRelayError.authenticationFailed)
        )
        XCTAssertFalse(
            CombinationExplicitAuth.shouldOfferAppPassword(
                after: ApiRelayError.validationFailed(field: "x", reason: "y")
            )
        )
    }

    func testCombinationRetryBindsOriginalVaultDelete() async throws {
        let container = try AppSchema.makeInMemoryContainer()
        let keychain = KeychainStore.makeForTests()
        let fake = FakeRevealGate()
        await fake.setAppPasswordMaterialSet(true)
        await fake.fail("confirm", with: .authenticationCancelled)
        var patch = PreferencesPatch()
        patch.revealPolicy = .biometryOrAppPassword
        patch.revealAuthEnabled = true
        try await UserPreferencesRepository(modelContainer: container).update(patch)
        let prefs = FakePreferences()
        try await prefs.update(patch)
        let master = FakeMasterPassword()
        let privacy = AppPrivacyController(
            gate: fake,
            preferences: prefs,
            masterPassword: master,
            installsSnapshotCover: false,
            enablesUnlockPrompt: false,
            launchAppLockEnabled: false
        )
        await privacy.start()
        privacy.applyLivePreferences(
            AppLockPreferences(
                appLockEnabled: false,
                autoLockSeconds: 60,
                hideInAppSwitcher: true,
                revealPolicy: .biometryOrAppPassword
            )
        )
        let vault = KeyVaultService(
            keychain: keychain,
            gate: fake,
            clipboard: SecureClipboard(),
            modelContainer: container,
            entitlements: StubEntitlements(tier: .unlimitedKeys)
        )
        let env = AppEnvironment(
            modelContainer: container,
            keychain: FakeKeychain(),
            masterPassword: master,
            gate: fake,
            clipboard: FakeClipboard(),
            vault: vault,
            consumerTools: FakeConsumerTools(),
            trashBatch: FakeRecentlyDeletedBatch(),
            entitlements: FakeEntitlements(tier: .unlimitedKeys),
            preferences: prefs,
            backups: FakeSecureBackup(),
            backupPassphrase: FakeBackupPassphrase(),
            dataLifecycle: FakeDataLifecycle(),
            cloudSync: FakeCloudSync(),
            appPrivacy: privacy
        )
        let vm = VaultHomeViewModel(environment: env)
        let accountId = try await vault.createAccount(
            UpstreamAccountDraft(platform: "openai", displayName: "A")
        )
        let keyId = try await vault.createKey(
            KeyDraft(accountId: accountId, displayName: "k"),
            secret: "sk-combo-retry-aaaa"
        )
        await vm.deleteKey(keyId)
        XCTAssertTrue(vm.hasPendingSensitiveRetry)
        XCTAssertTrue(vm.offerCombinationAppPassword)
        let remainingAfterCancel = try await vault.keys(in: accountId).map(\.id)
        XCTAssertEqual(remainingAfterCancel, [keyId])
        await vm.beginCombinationAppPasswordEntry()
        XCTAssertTrue(vm.presentMasterPasswordPrompt)
        await vm.submitMasterPassword("combo-pass-word")
        let remainingAfterRetry = try await vault.keys(in: accountId)
        XCTAssertTrue(remainingAfterRetry.isEmpty)
        let journal = await fake.journal
        XCTAssertEqual(journal.callCount("confirm"), 1)
        XCTAssertEqual(journal.callCount("confirmCombinationWithAppPassword"), 1)
        XCTAssertEqual(journal.callCount("confirmMandatory"), 0)
        XCTAssertEqual(journal.callCount("confirmWithMasterPassword"), 0)
    }

    func testOrdinaryCombinationMissingMaterialDoesNotSetPasswordOrRetryDelete() async throws {
        let container = try AppSchema.makeInMemoryContainer()
        let keychain = KeychainStore.makeForTests()
        let fake = FakeRevealGate()
        await fake.setAppPasswordMaterialSet(false)
        await fake.fail("confirm", with: .authenticationCancelled)
        var patch = PreferencesPatch()
        patch.revealPolicy = .biometryOrAppPassword
        patch.revealAuthEnabled = true
        try await UserPreferencesRepository(modelContainer: container).update(patch)
        let prefs = FakePreferences()
        try await prefs.update(patch)
        let master = FakeMasterPassword()
        let privacy = AppPrivacyController(
            gate: fake,
            preferences: prefs,
            masterPassword: master,
            installsSnapshotCover: false,
            enablesUnlockPrompt: false,
            launchAppLockEnabled: false
        )
        await privacy.start()
        privacy.applyLivePreferences(
            AppLockPreferences(
                appLockEnabled: false,
                autoLockSeconds: 60,
                hideInAppSwitcher: true,
                revealPolicy: .biometryOrAppPassword
            )
        )
        let vault = KeyVaultService(
            keychain: keychain,
            gate: fake,
            clipboard: SecureClipboard(),
            modelContainer: container,
            entitlements: StubEntitlements(tier: .unlimitedKeys)
        )
        let env = AppEnvironment(
            modelContainer: container,
            keychain: FakeKeychain(),
            masterPassword: master,
            gate: fake,
            clipboard: FakeClipboard(),
            vault: vault,
            consumerTools: FakeConsumerTools(),
            trashBatch: FakeRecentlyDeletedBatch(),
            entitlements: FakeEntitlements(tier: .unlimitedKeys),
            preferences: prefs,
            backups: FakeSecureBackup(),
            backupPassphrase: FakeBackupPassphrase(),
            dataLifecycle: FakeDataLifecycle(),
            cloudSync: FakeCloudSync(),
            appPrivacy: privacy
        )
        let vm = VaultHomeViewModel(environment: env)
        let accountId = try await vault.createAccount(
            UpstreamAccountDraft(platform: "openai", displayName: "A")
        )
        let keyId = try await vault.createKey(
            KeyDraft(accountId: accountId, displayName: "k"),
            secret: "sk-combo-missing-aaaa"
        )
        await vm.deleteKey(keyId)
        XCTAssertTrue(vm.hasPendingSensitiveRetry)
        await vm.beginCombinationAppPasswordEntry()
        XCTAssertFalse(vm.hasPendingSensitiveRetry)
        XCTAssertFalse(vm.presentMasterPasswordPrompt)
        XCTAssertTrue(vm.ordinaryAppPasswordNeedsIndependentRecovery)
        XCTAssertEqual(vm.errorMessage, AppPasswordPolicyGate.ordinaryEntryMissingMaterialMessage())
        await vm.submitMasterPassword("should-not-write")
        let remaining = try await vault.keys(in: accountId).map(\.id)
        XCTAssertEqual(remaining, [keyId])
        let masterJournal = await master.journal
        XCTAssertEqual(masterJournal.callCount("setPassword"), 0)
        let gateJournal = await fake.journal
        XCTAssertEqual(gateJournal.callCount("confirmMandatory"), 0)
        XCTAssertEqual(gateJournal.callCount("confirmCombinationWithAppPassword"), 0)
    }

    func testOrdinaryMissingMaterialIndependentRecoveryDoesNotRetryDelete() async throws {
        let container = try AppSchema.makeInMemoryContainer()
        let keychain = KeychainStore.makeForTests()
        let fake = FakeRevealGate()
        await fake.setAppPasswordMaterialSet(false)
        await fake.fail("confirm", with: .authenticationCancelled)
        var patch = PreferencesPatch()
        patch.revealPolicy = .biometryOrAppPassword
        patch.revealAuthEnabled = true
        try await UserPreferencesRepository(modelContainer: container).update(patch)
        let prefs = FakePreferences()
        try await prefs.update(patch)
        let master = FakeMasterPassword()
        let privacy = AppPrivacyController(
            gate: fake,
            preferences: prefs,
            masterPassword: master,
            installsSnapshotCover: false,
            enablesUnlockPrompt: false,
            launchAppLockEnabled: false,
            // This scenario models the still-mounted Vault page after the user
            // taps the independent recovery action. Headless desktop XCTest has
            // no frontmost app window, so inject the page's real presence just
            // as the shared Vault fixture does. Production keeps the strict
            // off-screen cancellation path.
            scenePresence: { .userFacing }
        )
        await privacy.start()
        privacy.applyLivePreferences(
            AppLockPreferences(
                appLockEnabled: false,
                autoLockSeconds: 60,
                hideInAppSwitcher: true,
                revealPolicy: .biometryOrAppPassword
            )
        )
        let vault = KeyVaultService(
            keychain: keychain,
            gate: fake,
            clipboard: SecureClipboard(),
            modelContainer: container,
            entitlements: StubEntitlements(tier: .unlimitedKeys)
        )
        let env = AppEnvironment(
            modelContainer: container,
            keychain: FakeKeychain(),
            masterPassword: master,
            gate: fake,
            clipboard: FakeClipboard(),
            vault: vault,
            consumerTools: FakeConsumerTools(),
            trashBatch: FakeRecentlyDeletedBatch(),
            entitlements: FakeEntitlements(tier: .unlimitedKeys),
            preferences: prefs,
            backups: FakeSecureBackup(),
            backupPassphrase: FakeBackupPassphrase(),
            dataLifecycle: FakeDataLifecycle(),
            cloudSync: FakeCloudSync(),
            appPrivacy: privacy
        )
        let vm = VaultHomeViewModel(environment: env)
        let accountId = try await vault.createAccount(
            UpstreamAccountDraft(platform: "openai", displayName: "A")
        )
        let keyId = try await vault.createKey(
            KeyDraft(accountId: accountId, displayName: "k"),
            secret: "sk-combo-recover-aaaa"
        )
        await vm.deleteKey(keyId)
        await vm.beginCombinationAppPasswordEntry()
        await vm.recoverIndependentAppPasswordFromOrdinaryEntry()
        let remaining = try await vault.keys(in: accountId).map(\.id)
        XCTAssertEqual(remaining, [keyId])
        XCTAssertFalse(vm.hasPendingSensitiveRetry)
        XCTAssertFalse(vm.ordinaryAppPasswordNeedsIndependentRecovery)
        let saved = try await prefs.load()
        XCTAssertEqual(saved.revealPolicy, .biometricOrPasscode)
        let masterJournal = await master.journal
        XCTAssertEqual(masterJournal.callCount("setPassword"), 0)
        XCTAssertFalse(privacy.session.isSessionLocked)
    }

    func testMasterOnlyMissingMaterialOffersRecoveryWithoutBusinessRetry() async throws {
        let env = AppEnvironment.makePreview()
        let gate = try XCTUnwrap(env.gate as? FakeRevealGate)
        await gate.setAppPasswordMaterialSet(false)
        try await env.preferences.update(PreferencesPatch(revealPolicy: .masterPassword))
        await env.appPrivacy.start()
        env.appPrivacy.applyLivePreferences(AppLockPreferences(
            appLockEnabled: false, autoLockSeconds: 60,
            hideInAppSwitcher: true, revealPolicy: .masterPassword
        ))
        let vm = VaultHomeViewModel(environment: env)
        await vm.deleteKey(UUID())
        XCTAssertTrue(vm.ordinaryAppPasswordNeedsIndependentRecovery)
        XCTAssertFalse(vm.hasPendingSensitiveRetry)
        XCTAssertFalse(vm.presentMasterPasswordPrompt)
        let journal = await gate.journal
        XCTAssertEqual(journal.callCount("confirm"), 0)
    }

    func testBackupMasterOnlyMissingMaterialIsNotPasswordPrompt() async throws {
        let env = AppEnvironment.makePreview()
        let gate = try XCTUnwrap(env.gate as? FakeRevealGate)
        await gate.setAppPasswordMaterialSet(false)
        try await env.preferences.update(PreferencesPatch(revealPolicy: .masterPassword))
        do {
            try await BackupCurrentPolicyAuth.confirm(environment: env, reason: "test", appPassword: nil)
            XCTFail("missing material must refuse the ordinary operation")
        } catch let error as ApiRelayError {
            XCTAssertTrue(BackupCurrentPolicyAuth.isMissingMaterial(error))
            XCTAssertFalse(BackupCurrentPolicyAuth.isPasswordPrompt(error))
        }
    }

    func testOrdinarySurfacesDoNotCallSetPasswordOnMissingMaterialPath() throws {
        let vaultVM = try Self.productionSource("UI/Vault/VaultHomeViewModel.swift")
        let vaultHome = try Self.productionSource("UI/Vault/VaultHomeView.swift")
        let backup = try Self.productionSource("UI/Settings/BackupSettingsViews.swift")
        let settings = try Self.productionSource("UI/Settings/SettingsView.swift")
        XCTAssertFalse(vaultVM.contains("completeCombinationSetupThenRetry"))
        XCTAssertFalse(vaultVM.contains("masterPassword.setPassword"))
        XCTAssertTrue(vaultVM.contains("refuseOrdinaryAppPasswordPath"))
        XCTAssertTrue(vaultHome.contains("recoverIndependentAppPasswordFromOrdinaryEntry"))
        XCTAssertFalse(vaultHome.contains("appLock.combination.setupTitle"))
        XCTAssertFalse(backup.contains("masterPassword.setPassword"))
        XCTAssertTrue(backup.contains("OrdinaryMissingAppPasswordRecoveryButton"))
        XCTAssertFalse(
            vaultVM.contains("try? await environment.gate.isAppPasswordMaterialSet"),
            "普通取用入口不得把 Keychain 读取错误压成未设"
        )
        XCTAssertFalse(
            backup.contains("try? await environment.gate.isAppPasswordMaterialSet"),
            "备份入口不得把 Keychain 读取错误压成未设"
        )
        XCTAssertFalse(
            settings.contains("masterPassword.setPassword"),
            "设置页普通降低/清空不得直接 setPassword"
        )
        XCTAssertTrue(settings.contains("ordinaryEntryMissingMaterialMessage"))
        XCTAssertFalse(
            settings.contains("try? await environment.gate.isAppPasswordMaterialSet"),
            "设置入口不得把 Keychain 读取错误压成未设"
        )
    }
}

extension RevealGateCoordinatorTests {
    fileprivate static func productionSource(_ relativePath: String) throws -> String {
        let testsFile = URL(fileURLWithPath: #filePath)
        let projectRoot = testsFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = projectRoot.appendingPathComponent("ApiRelay/\(relativePath)")
        return try String(contentsOf: url, encoding: .utf8)
    }

    fileprivate func makeVaultHomeViewModel(gateOverride: (any RevealGateServing)? = nil) async throws -> VaultHomeViewModel {
        let container = try AppSchema.makeInMemoryContainer()
        let gate: any RevealGateServing = gateOverride ?? FakeRevealGate()
        let prefs = FakePreferences()
        let master = FakeMasterPassword()
        let privacy = AppPrivacyController(
            gate: gate,
            preferences: prefs,
            masterPassword: master,
            installsSnapshotCover: false,
            enablesUnlockPrompt: false,
            launchAppLockEnabled: false,
            // This helper represents the still-mounted active Vault window.
            // A headless test process has no discoverable platform window and
            // therefore reports `.offScreen` unless the intended scene state is
            // injected explicitly.
            scenePresence: { .userFacing }
        )
        let env = AppEnvironment(
            modelContainer: container,
            keychain: FakeKeychain(),
            masterPassword: master,
            gate: gate,
            clipboard: FakeClipboard(),
            vault: FakeKeyVault(),
            consumerTools: FakeConsumerTools(),
            trashBatch: FakeRecentlyDeletedBatch(),
            entitlements: FakeEntitlements(tier: .unlimitedKeys),
            preferences: prefs,
            backups: FakeSecureBackup(),
            backupPassphrase: FakeBackupPassphrase(),
            dataLifecycle: FakeDataLifecycle(),
            cloudSync: FakeCloudSync(),
            appPrivacy: privacy
        )
        return VaultHomeViewModel(environment: env)
    }
}
