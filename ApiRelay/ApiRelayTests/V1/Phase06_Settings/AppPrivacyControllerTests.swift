@preconcurrency import XCTest
@testable import ApiRelay

@MainActor
final class AppPrivacyControllerTests: XCTestCase {
    func testStartUsesStoredAppLockAndDefaultHide() async throws {
        let sut = try await makeController(appLock: true, hide: true, seconds: 60)
        await sut.start()
        XCTAssertTrue(sut.session.isPreferencesReady)
        XCTAssertTrue(sut.session.isSessionLocked)
        XCTAssertTrue(sut.session.blocksContent)
        XCTAssertTrue(sut.session.needsUnlockPrompt)
    }

    func testStartWithDefaultsDoesNotLockButHidesInSwitcher() async throws {
        let sut = try await makeController(appLock: false, hide: true, seconds: 60)
        await sut.start()
        XCTAssertFalse(sut.session.isSessionLocked)
        XCTAssertFalse(sut.session.blocksContent)
        sut.handleWillResignActive()
        XCTAssertTrue(sut.session.showsSnapshotCover)
        XCTAssertTrue(sut.session.blocksContent)
        sut.handleDidBecomeActive()
        XCTAssertFalse(sut.session.blocksContent)
        XCTAssertFalse(sut.session.isSessionLocked)
    }

    func testTurningOffHideRemovesSwitcherCover() async throws {
        let sut = try await makeController(appLock: false, hide: true, seconds: 60)
        await sut.start()
        sut.handleWillResignActive()
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

    private func makeController(
        appLock: Bool,
        hide: Bool,
        seconds: Int,
        revealPolicy: RevealPolicy = .none,
        masterPassword: String? = nil
    ) async throws -> AppPrivacyController {
        let container = try AppSchema.makeInMemoryContainer()
        let preferences = PreferencesService(modelContainer: container)
        var patch = PreferencesPatch()
        patch.appLockEnabled = appLock
        patch.autoLockSeconds = seconds
        patch.hideInAppSwitcher = hide
        patch.revealPolicy = revealPolicy
        try await preferences.update(patch)
        let keychain = KeychainStore(accessGroup: nil, disableSynchronizableForTesting: true)
        let master = MasterPasswordService(keychain: keychain, calibratedIterations: 10_000)
        if let masterPassword {
            try await master.setPassword(masterPassword)
        }
        let gate = RevealGate(masterPassword: master) { _, _ in
            XCTFail("App lock with master-password policy must not present the device passcode prompt")
        }
        return AppPrivacyController(
            gate: gate,
            preferences: preferences,
            installsSnapshotCover: false,
            enablesUnlockPrompt: false
        )
    }
}
