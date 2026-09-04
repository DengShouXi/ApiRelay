@preconcurrency import XCTest
@testable import ApiRelay
import SwiftData

@MainActor
final class PreferencesServiceTests: XCTestCase {
    func testDefaultsAndAppearanceIsolation() async throws {
        let container = try AppSchema.makeInMemoryContainer()
        let sut = PreferencesService(modelContainer: container)
        let loaded = try await sut.load()
        XCTAssertEqual(loaded.clipboardClearSeconds, 120)
        XCTAssertEqual(loaded.revealPolicy, .noVerification)
        XCTAssertFalse(loaded.appLockEnabled)
        XCTAssertEqual(loaded.autoLockSeconds, 60)
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
    }

    /// 设置页的同步开关全部走 `persist`（不在 MainActor 上 `await`）。
    /// 连拨 5 次后落盘的必须是最后一次拨的值，否则重开 App 会看到中间值。
    func testPersistKeepsLastValueWhenToggledRapidly() async throws {
        let container = try AppSchema.makeInMemoryContainer()
        let sut = PreferencesService(modelContainer: container)

        for enabled in [true, false, true, false, true] {
            sut.persist(PreferencesPatch(appLockEnabled: enabled))
        }
        sut.persist(PreferencesPatch(revealPolicy: .biometricOnly, clipboardLocalOnly: false))
        sut.persist(PreferencesPatch(clipboardClearSeconds: 300))
        sut.persist(PreferencesPatch(hideInAppSwitcher: false))
        await sut.drainPendingWrites()

        let loaded = try await sut.load()
        XCTAssertTrue(loaded.appLockEnabled)
        XCTAssertEqual(loaded.revealPolicy, .biometricOnly)
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
        policy.revealPolicy = .biometricOnly
        try await sut.update(policy)

        let loaded = try await sut.load()
        XCTAssertEqual(loaded.revealPolicy, .biometricOnly)
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
}
