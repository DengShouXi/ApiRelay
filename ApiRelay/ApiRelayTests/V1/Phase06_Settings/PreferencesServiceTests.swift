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

        var patch = PreferencesPatch()
        patch.appearance = .dark
        try await sut.update(patch)

        let user = try await UserPreferencesRepository(modelContainer: container).loadOrCreate()
        // UserPreferences repository returns placeholder appearance; device holds truth.
        XCTAssertEqual(user.appearance, .system)

        let device = try await DevicePreferencesRepository(modelContainer: container).loadOrCreate()
        XCTAssertEqual(device.appearance, .dark)
    }
}
