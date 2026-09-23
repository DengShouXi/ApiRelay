@preconcurrency import XCTest
@testable import ApiRelay
import SwiftData

@MainActor
final class PreferencesServiceTests: XCTestCase {
    override func setUp() {
        super.setUp()
        AppLockLaunchCache.resetForTests()
    }

    override func tearDown() {
        AppLockLaunchCache.resetForTests()
        super.tearDown()
    }

    func testDefaultsAndAppearanceIsolation() async throws {
        let container = try AppSchema.makeInMemoryContainer()
        let sut = PreferencesService(modelContainer: container)
        let loaded = try await sut.load()
        XCTAssertEqual(loaded.clipboardClearSeconds, 120)
        XCTAssertTrue(loaded.clipboardClearEnabled)
        XCTAssertEqual(loaded.clipboardClearDurationOptions, [30, 120])
        XCTAssertEqual(loaded.revealPolicy, .biometricOrPasscode)
        XCTAssertTrue(loaded.revealAuthEnabled)
        XCTAssertFalse(loaded.appLockEnabled)
        XCTAssertEqual(loaded.autoLockSeconds, 60)
        XCTAssertEqual(loaded.autoLockDurationOptions, [0, 60])
        XCTAssertTrue(loaded.hideInAppSwitcher)

        var patch = PreferencesPatch()
        patch.appearance = .dark
        try await sut.update(patch)

        let user = try await UserPreferencesRepository(modelContainer: container).loadOrCreate()
        // UserPreferences repository returns placeholder appearance; device holds truth.
        XCTAssertEqual(user.appearance, .system)

        let device = try await DevicePreferencesRepository(modelContainer: container).loadOrCreate()
        XCTAssertEqual(device.appearance, .dark)
    }

    func testAppLockFieldsPersist() async throws {
        let container = try AppSchema.makeInMemoryContainer()
        let sut = PreferencesService(modelContainer: container)
        var patch = PreferencesPatch()
        patch.appLockEnabled = true
        patch.autoLockSeconds = 0
        patch.hideInAppSwitcher = false
        try await sut.update(patch)

        let loaded = try await sut.load()
        XCTAssertTrue(loaded.appLockEnabled)
        XCTAssertEqual(loaded.autoLockSeconds, 0)
        XCTAssertFalse(loaded.hideInAppSwitcher)
        XCTAssertEqual(AppLockLaunchCache.read(), true)
    }

    func testProductionLaunchCacheStoresEffectiveArmedState() async throws {
        let container = try AppSchema.makeInMemoryContainer()
        let sut = PreferencesService(modelContainer: container)

        try await sut.update(PreferencesPatch(
            appLockEnabled: true,
            revealPolicy: .noVerification
        ))
        XCTAssertEqual(
            AppLockLaunchCache.read(),
            false,
            "开启自动锁但选择不验证时，冷启动不得显示假锁"
        )

        try await sut.update(PreferencesPatch(revealPolicy: .biometricOrPasscode))
        XCTAssertEqual(AppLockLaunchCache.read(), true)
    }

    /// 设置页的同步开关全部走 `persist`（不在 MainActor 上 `await`）。
    /// 连拨 5 次后落盘的必须是最后一次拨的值，否则重开 App 会看到中间值。
    func testPersistKeepsLastValueWhenToggledRapidly() async throws {
        let container = try AppSchema.makeInMemoryContainer()
        let sut = PreferencesService(modelContainer: container)

        for enabled in [true, false, true, false, true] {
            sut.persist(PreferencesPatch(appLockEnabled: enabled))
        }
        sut.persist(PreferencesPatch(revealPolicy: .biometricOrPasscode, clipboardLocalOnly: false))
        sut.persist(PreferencesPatch(clipboardClearSeconds: 300))
        sut.persist(PreferencesPatch(hideInAppSwitcher: false))
        await sut.drainPendingWrites()

        let loaded = try await sut.load()
        XCTAssertTrue(loaded.appLockEnabled)
        XCTAssertEqual(loaded.revealPolicy, .biometricOrPasscode)
        XCTAssertFalse(loaded.clipboardLocalOnly)
        XCTAssertEqual(loaded.clipboardClearSeconds, 300)
        XCTAssertFalse(loaded.hideInAppSwitcher)
    }

    func testRevealPolicyUpdateDoesNotTouchDeviceAppearance() async throws {
        let container = try AppSchema.makeInMemoryContainer()
        let sut = PreferencesService(modelContainer: container)
        var appearance = PreferencesPatch()
        appearance.appearance = .dark
        try await sut.update(appearance)

        var policy = PreferencesPatch()
        policy.revealPolicy = .biometricOrPasscode
        try await sut.update(policy)

        let loaded = try await sut.load()
        XCTAssertEqual(loaded.revealPolicy, .biometricOrPasscode)
        XCTAssertEqual(loaded.appearance, .dark)
    }

    func testSectionSortPersistsOnDeviceOnly() async throws {
        let container = try AppSchema.makeInMemoryContainer()
        let sut = PreferencesService(modelContainer: container)
        var patch = PreferencesPatch()
        patch.platformSectionSort = SectionSortPreference(criterion: .createdAt, ascending: false)
        patch.consumerSectionSort = SectionSortPreference(criterion: .custom, ascending: true)
        try await sut.update(patch)

        let loaded = try await sut.load()
        XCTAssertEqual(loaded.platformSectionSort.criterion, .createdAt)
        XCTAssertEqual(loaded.platformSectionSort.ascending, false)
        XCTAssertEqual(loaded.consumerSectionSort.criterion, .custom)

        let user = try await UserPreferencesRepository(modelContainer: container).loadOrCreate()
        XCTAssertEqual(user.platformSectionSort.criterion, .name)
        XCTAssertEqual(user.consumerSectionSort.criterion, .name)
    }

    func testAvatarDefaultsPersistOnDeviceOnly() async throws {
        let container = try AppSchema.makeInMemoryContainer()
        let sut = PreferencesService(modelContainer: container)
        var patch = PreferencesPatch()
        patch.defaultKeyAvatarSymbol = "globe"
        patch.defaultKeyAvatarColor = "teal"
        try await sut.update(patch)

        let loaded = try await sut.load()
        XCTAssertEqual(loaded.defaultKeyAvatarSymbol, "globe")
        XCTAssertEqual(loaded.defaultKeyAvatarColor, "teal")

        let user = try await UserPreferencesRepository(modelContainer: container).loadOrCreate()
        XCTAssertNil(user.defaultKeyAvatarSymbol)
    }

    func testDurationListsPersistAndEmptyListIsNotReseeded() async throws {
        let container = try AppSchema.makeInMemoryContainer()
        let sut = PreferencesService(modelContainer: container)

        var patch = PreferencesPatch()
        patch.clipboardClearEnabled = false
        patch.autoLockDurationOptions = []
        patch.clipboardClearDurationOptions = [45, 90]
        patch.clipboardClearSeconds = 45
        try await sut.update(patch)

        let loaded = try await sut.load()
        XCTAssertFalse(loaded.clipboardClearEnabled)
        XCTAssertEqual(loaded.autoLockDurationOptions, [])
        XCTAssertEqual(loaded.clipboardClearDurationOptions, [45, 90])
        XCTAssertEqual(loaded.clipboardClearSeconds, 45)
    }

    func testRevealAuthEnabledDefaultsTrueAndPersistsFalse() async throws {
        let container = try AppSchema.makeInMemoryContainer()
        let sut = PreferencesService(modelContainer: container)
        let loaded = try await sut.load()
        XCTAssertTrue(loaded.revealAuthEnabled)

        try await sut.update(PreferencesPatch(revealAuthEnabled: false))
        let after = try await sut.load()
        XCTAssertFalse(after.revealAuthEnabled)
        XCTAssertEqual(after.revealPolicy, .biometricOrPasscode)
    }

    func testRuntimePolicyHasExactlyFourCases() {
        XCTAssertEqual(RevealPolicy.allCases.count, 4)
        XCTAssertEqual(
            RevealPolicy.allCases,
            [.biometricOrPasscode, .masterPassword, .biometryOrAppPassword, .noVerification]
        )
        XCTAssertEqual(
            RevealPolicy.selectableCases,
            [.biometricOrPasscode, .masterPassword, .biometryOrAppPassword, .noVerification]
        )
        XCTAssertEqual(RevealPolicyPersistence.legacyBiometricOnlyRawValue, "biometricOnly")
        XCTAssertEqual(
            RevealPolicyPersistence.resolve(RevealPolicyPersistence.legacyBiometricOnlyRawValue).policy,
            .biometricOrPasscode
        )
    }

    func testExistingMasterPasswordRawValueIsPreserved() {
        XCTAssertEqual(RevealPolicyPersistence.canonical(.masterPassword), .masterPassword)
        XCTAssertEqual(RevealPolicyPersistence.resolve("masterPassword").policy, .masterPassword)
        XCTAssertNil(RevealPolicyPersistence.resolve("masterPassword").persistRawValue)
    }

    func testQueuedPolicyPersistRefusesAfterInvalidateWithoutCoveringNewPolicy() async throws {
        for target in [RevealPolicy.masterPassword, .biometryOrAppPassword] {
            let container = try AppSchema.makeInMemoryContainer()
            let sut = PreferencesService(modelContainer: container)
            try await sut.update(PreferencesPatch(revealPolicy: .biometricOrPasscode, hideInAppSwitcher: true))
            let hold = PersistHold()
            let firstDone = expectation(description: "first-persist-\(target.rawValue)")
            sut.persist(
                PreferencesPatch(hideInAppSwitcher: false),
                authorizing: { await hold.wait() },
                expectedCurrentPolicy: nil,
                onFailure: { error in XCTFail("holder persist failed \(error)") },
                onSuccess: { firstDone.fulfill() }
            )
            let lease = AppPasswordPageLease(
                target: target,
                currentPolicy: .biometricOrPasscode
            )
            let token = try XCTUnwrap(lease.begin())
            let secondDone = expectation(description: "queued-stale-\(target.rawValue)")
            let secondReason = ReasonBox()
            sut.persist(
                PreferencesPatch(revealPolicy: target),
                authorizing: { try lease.authorize(token, step: .policyPersist) },
                expectedCurrentPolicy: .biometricOrPasscode,
                onFailure: { error in
                    if case ApiRelayError.validationFailed(_, let reason) = error {
                        secondReason.set(reason)
                    }
                    secondDone.fulfill()
                },
                onSuccess: { XCTFail("queued stale persist must not write \(target)") }
            )
            lease.invalidate()
            await hold.release()
            await fulfillment(of: [firstDone, secondDone], timeout: 5)
            await sut.drainPendingWrites()
            let loaded = try await sut.load()
            XCTAssertEqual(loaded.revealPolicy, .biometricOrPasscode, "\(target)")
            XCTAssertFalse(loaded.hideInAppSwitcher, "\(target)")
            XCTAssertEqual(secondReason.value(), "stale_page_request", "\(target)")
        }
    }

    func testQueuedPersistRejectsWhenOpenedPolicyAlreadyChanged() async throws {
        let container = try AppSchema.makeInMemoryContainer()
        let sut = PreferencesService(modelContainer: container)
        try await sut.update(PreferencesPatch(revealPolicy: .masterPassword))
        let hold = PersistHold()
        let firstDone = expectation(description: "policy-changed-first")
        sut.persist(
            PreferencesPatch(revealPolicy: .noVerification),
            authorizing: { await hold.wait() },
            expectedCurrentPolicy: nil,
            onFailure: { error in XCTFail("first persist failed \(error)") },
            onSuccess: { firstDone.fulfill() }
        )
        let lease = AppPasswordPageLease(
            target: .biometryOrAppPassword,
            currentPolicy: .masterPassword
        )
        let token = try XCTUnwrap(lease.begin())
        let secondDone = expectation(description: "policy-changed-second")
        let secondReason = ReasonBox()
        sut.persist(
            PreferencesPatch(revealPolicy: .biometryOrAppPassword),
            authorizing: { try lease.authorize(token, step: .policyPersist) },
            expectedCurrentPolicy: .masterPassword,
            onFailure: { error in
                if case ApiRelayError.validationFailed(_, let reason) = error {
                    secondReason.set(reason)
                }
                secondDone.fulfill()
            },
            onSuccess: { XCTFail("must not overwrite newer policy") }
        )
        await hold.release()
        await fulfillment(of: [firstDone, secondDone], timeout: 5)
        await sut.drainPendingWrites()
        let loaded = try await sut.load()
        XCTAssertEqual(loaded.revealPolicy, .noVerification)
        XCTAssertEqual(secondReason.value(), "stale_page_request")
        XCTAssertTrue(lease.isFresh(token, sceneActive: true))
    }

    func testOrdinaryOldSettingsPageCannotOverwriteConcurrentlyStrengthenedPolicy() async throws {
        let container = try AppSchema.makeInMemoryContainer()
        let sut = PreferencesService(modelContainer: container)
        try await sut.update(PreferencesPatch(
            revealPolicy: .biometricOrPasscode,
            hideInAppSwitcher: true
        ))
        let hold = PersistHold()
        let failed = expectation(description: "stale ordinary settings page")
        let failureReason = ReasonBox()
        sut.persist(
            PreferencesPatch(hideInAppSwitcher: false),
            authorizing: { await hold.wait() },
            committing: { operation in try operation() },
            expectedCurrentPolicy: .biometricOrPasscode,
            onFailure: { error in
                if case ApiRelayError.validationFailed(_, let reason) = error {
                    failureReason.set(reason)
                }
                failed.fulfill()
            },
            onSuccess: { XCTFail("stale page must not overwrite the newer policy") }
        )

        try await sut.update(PreferencesPatch(revealPolicy: .masterPassword))
        await hold.release()
        await fulfillment(of: [failed], timeout: 5)
        await sut.drainPendingWrites()

        let stored = try await sut.load()
        XCTAssertEqual(stored.revealPolicy, .masterPassword)
        XCTAssertTrue(stored.hideInAppSwitcher)
        XCTAssertEqual(failureReason.value(), "stale_page_request")
    }

    /// 比较已经通过后、真正进入仓库写入前，另一请求改策略也必须保留新值。
    func testPolicyChangedAfterServiceCheckCannotBeOverwritten() async throws {
        for target: RevealPolicy in [.masterPassword, .biometryOrAppPassword] {
            let container = try AppSchema.makeInMemoryContainer()
            let sut = PreferencesService(modelContainer: container)
            try await sut.update(PreferencesPatch(revealPolicy: .biometricOrPasscode))
            let calls = AuthorizationCallCounter()
            let finished = expectation(description: "conditional-commit-\(target.rawValue)")
            let reason = ReasonBox()
            sut.persist(
                PreferencesPatch(revealPolicy: target),
                authorizing: {
                    if await calls.next() == 2 {
                        try await sut.update(PreferencesPatch(revealPolicy: .noVerification))
                    }
                },
                expectedCurrentPolicy: .biometricOrPasscode,
                onFailure: { error in
                    if case ApiRelayError.validationFailed(_, let value) = error { reason.set(value) }
                    finished.fulfill()
                },
                onSuccess: { XCTFail("stale request overwrote newer policy"); finished.fulfill() }
            )
            await fulfillment(of: [finished], timeout: 5)
            await sut.drainPendingWrites()
            let stored = try await sut.load()
            XCTAssertEqual(stored.revealPolicy, .noVerification)
            XCTAssertEqual(reason.value(), "stale_page_request")
        }
    }
}

private actor AuthorizationCallCounter {
    private var value = 0
    func next() -> Int { value += 1; return value }
}

private final class ReasonBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: String?

    func set(_ value: String) {
        lock.lock()
        stored = value
        lock.unlock()
    }

    func value() -> String? {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }
}

private actor PersistHold {
    private var waiting: CheckedContinuation<Void, Never>?

    func wait() async {
        if let waiting {
            waiting.resume()
            self.waiting = nil
        } else {
            await withCheckedContinuation { continuation in
                self.waiting = continuation
            }
        }
    }

    func release() async {
        await wait()
    }
}
