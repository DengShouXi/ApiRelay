@preconcurrency import XCTest
@testable import ApiRelay

@MainActor
final class AvatarCatalogTests: XCTestCase {
    func testKeyOverrideBeatsSettingsDefault() {
        var defaults = AvatarPreferenceDefaults.builtIn
        defaults.key = AvatarChoice(symbol: "globe", color: .teal)
        let resolved = AvatarCatalog.key(
            overrideSymbol: "sparkles",
            overrideColor: "blue",
            defaults: defaults
        )
        XCTAssertEqual(resolved.symbol, "sparkles")
        XCTAssertEqual(resolved.color, .blue)
    }

    func testKeyWithoutOverrideUsesSettingsDefault() {
        var defaults = AvatarPreferenceDefaults.builtIn
        defaults.key = AvatarChoice(symbol: "globe", color: .teal)
        let resolved = AvatarCatalog.key(
            overrideSymbol: nil,
            overrideColor: nil,
            defaults: defaults
        )
        XCTAssertEqual(resolved, defaults.key)
    }

    func testPresetPlatformKeepsCatalogUnlessOverridden() {
        let openai = AvatarCatalog.account(
            platform: "openai",
            overrideSymbol: nil,
            overrideColor: nil,
            defaults: .builtIn
        )
        XCTAssertEqual(openai.symbol, "sparkles")
        XCTAssertEqual(openai.color, .blue)

        let custom = AvatarCatalog.account(
            platform: PresetCatalog.customPlatformID,
            overrideSymbol: nil,
            overrideColor: nil,
            defaults: .builtIn
        )
        XCTAssertEqual(custom, AvatarChoice.customAccount)
    }

    func testCatalogToolKeepsPresetSymbol() {
        let vs = AvatarCatalog.tool(
            name: "VS Code · 电脑 1",
            catalogSymbol: "curlybraces.square",
            overrideSymbol: nil,
            overrideColor: nil,
            defaults: .builtIn
        )
        XCTAssertEqual(vs.symbol, "curlybraces.square")

        var defaults = AvatarPreferenceDefaults.builtIn
        defaults.customTool = AvatarChoice(symbol: "hammer", color: .orange)
        let custom = AvatarCatalog.tool(
            name: "我的 IDE",
            catalogSymbol: nil,
            overrideSymbol: nil,
            overrideColor: nil,
            defaults: defaults
        )
        XCTAssertEqual(custom.symbol, "hammer")
        XCTAssertEqual(custom.color, .orange)
    }
}
