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
        XCTAssertEqual(loaded.revealPolicy, .none)
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
