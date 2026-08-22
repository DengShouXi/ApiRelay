import XCTest
@testable import ApiRelay

/// v1.11：App Icon / SF Symbol 语义收口（不测 PNG 像素，测映射表契约）。
@MainActor
final class AppSymbolsTests: XCTestCase {

    func testTabSymbolsMatchDesignTable() {
        XCTAssertEqual(AppSymbols.Tab.byPlatform, "plus.circle")
        XCTAssertEqual(AppSymbols.Tab.byConsumer, "minus.circle")
        XCTAssertEqual(AppSymbols.Tab.trash, "trash")
        XCTAssertEqual(AppSymbols.Tab.settings, "gearshape")
    }

    func testKeyActionSymbols() {
        XCTAssertEqual(AppSymbols.Action.copy, "doc.on.doc")
        XCTAssertEqual(AppSymbols.Action.reveal, "eye")
        XCTAssertEqual(AppSymbols.Action.sort, "arrow.up.arrow.down")
        XCTAssertEqual(AppSymbols.Action.overflow, "ellipsis")
        XCTAssertEqual(AppSymbols.Action.reorderHandle, "line.3.horizontal")
        XCTAssertEqual(AppSymbols.Action.chevronBackward, "chevron.backward")
        XCTAssertEqual(AppSymbols.Action.sidebarLeading, "sidebar.leading")
        XCTAssertEqual(AppSymbols.Action.unchecked, "circle")
        XCTAssertEqual(AppSymbols.Action.checked, "checkmark.circle.fill")
        XCTAssertEqual(AppSymbols.Key.default, "key.fill")
    }

    func testPlatformMetaphorSymbols() {
        XCTAssertEqual(AppSymbols.platform(id: "openai"), "sparkles")
        XCTAssertEqual(AppSymbols.platform(id: "anthropic"), "bubble.left.and.bubble.right")
        XCTAssertEqual(AppSymbols.platform(id: "google"), "globe")
        XCTAssertEqual(AppSymbols.platform(id: "openrouter"), "arrow.triangle.branch")
        XCTAssertEqual(AppSymbols.platform(id: "deepseek"), "waveform")
        XCTAssertEqual(AppSymbols.platform(id: "zhipu"), "brain.head.profile")
        XCTAssertEqual(AppSymbols.platform(id: "alibaba-bailian"), "cloud")
        XCTAssertEqual(AppSymbols.platform(id: "volcengine"), "bolt.fill")
        XCTAssertEqual(AppSymbols.platform(id: "siliconflow"), "cpu")
        XCTAssertEqual(AppSymbols.platform(id: "custom"), "building.2")
        XCTAssertEqual(AppSymbols.platform(id: "unknown-vendor"), "building.2")
    }

    func testPresetCatalogPlatformIconsAligned() {
        for platform in PresetCatalog.platforms {
            XCTAssertEqual(
                platform.iconSymbol,
                AppSymbols.platform(id: platform.id),
                "platform \(platform.id) symbol drift"
            )
            XCTAssertFalse(platform.iconSymbol.isEmpty)
        }
        XCTAssertEqual(
            PresetCatalog.platform(id: PresetCatalog.customPlatformID)?.iconSymbol,
            AppSymbols.platform(id: "custom")
        )
    }

    func testConsumerToolSymbolsAndFallback() {
        XCTAssertEqual(AppSymbols.tool(name: "Cursor"), "cursorarrow")
        XCTAssertEqual(AppSymbols.tool(name: "VS Code · 电脑 1"), "curlybraces.square")
        XCTAssertEqual(AppSymbols.tool(name: "Claude Code"), "text.bubble")
        XCTAssertEqual(AppSymbols.tool(name: "Codex · 电脑 1"), "book.closed")
        XCTAssertEqual(AppSymbols.tool(name: "自建工具"), "laptopcomputer")
        XCTAssertEqual(AppSymbols.tool(name: "x", storedSymbol: "hammer"), "hammer")
        XCTAssertEqual(AppSymbols.toolIconForNewBase("Zed"), "z.square")
        XCTAssertEqual(AppSymbols.toolIconForNewBase("全新工具"), "app")
    }

    func testSettingsSymbolsAreUniquePerSemantic() {
        let symbols = [
            AppSymbols.Settings.appearance,
            AppSymbols.Settings.avatars,
            AppSymbols.Settings.defaultGrouping,
            AppSymbols.Settings.assignFilter,
            AppSymbols.Settings.revealPolicy,
            AppSymbols.Settings.masterPassword,
            AppSymbols.Settings.appLock,
            AppSymbols.Settings.autoLock,
            AppSymbols.Settings.clipboardClear,
            AppSymbols.Settings.clipboardLocalOnly,
            AppSymbols.Settings.hideInAppSwitcher,
            AppSymbols.Settings.backupPassphrase,
            AppSymbols.Settings.backupExport,
            AppSymbols.Settings.backupImport,
            AppSymbols.Settings.eraseAll,
        ]
        XCTAssertEqual(Set(symbols).count, symbols.count, "settings row symbols must not collide")
    }
}
