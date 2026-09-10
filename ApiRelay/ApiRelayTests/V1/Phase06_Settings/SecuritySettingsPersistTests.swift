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
