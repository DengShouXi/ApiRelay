import Foundation

/// 全应用 SF Symbol 语义表（UI 单一映射源）。
/// View 只引用这里的常量或解析函数，禁止散落魔法字符串。
/// 平台 / 工具符号权威在 `PresetCatalog`，此处转发以保持调用面统一。
enum AppSymbols: Sendable {

    // MARK: - Navigation (Tabs)

    enum Tab {
        /// 正电荷（⊕），与 App Icon 左极语义对齐。
        nonisolated static let byPlatform = "plus.circle"
        /// 负电荷（⊖），与 App Icon 右极语义对齐。
        nonisolated static let byConsumer = "minus.circle"
        nonisolated static let trash = "trash"
        nonisolated static let settings = "gearshape"
    }

    // MARK: - Common actions

    enum Action {
        nonisolated static let more = "ellipsis.circle"
        nonisolated static let account = "person.crop.circle.fill"
        nonisolated static let add = "plus"
        nonisolated static let addInline = "plus.circle"
        nonisolated static let addFilled = "plus.circle.fill"
        nonisolated static let search = "magnifyingglass"
        nonisolated static let searchClear = "xmark.circle.fill"
        nonisolated static let copy = "doc.on.doc"
        nonisolated static let reveal = "eye"
        nonisolated static let assign = "link"
        nonisolated static let chevronRight = "chevron.right"
        nonisolated static let chevronDown = "chevron.down"
        nonisolated static let checkmark = "checkmark"
        nonisolated static let warning = "exclamationmark.triangle"
    }

    // MARK: - Key / vault

    enum Key {
        nonisolated static let `default` = "key.fill"
        /// 空态等次要语境（线框钥匙）。
        nonisolated static let outline = "key"
        nonisolated static let unavailable = "key.slash"
        nonisolated static let missingSecret = "exclamationmark.icloud"
        nonisolated static let shared = "person.2.fill"
        nonisolated static let unassigned = "tray"
        nonisolated static let ready = "checkmark.shield.fill"
    }

    // MARK: - Sync / iCloud（文案不得夸大「系统级强制」）

    enum Sync {
        nonisolated static let iCloud = "icloud.fill"
        nonisolated static let lockedCloud = "lock.icloud"
        nonisolated static let refresh = "arrow.triangle.2.circlepath"
        nonisolated static let openSystemSettings = "gearshape"
    }

    // MARK: - Settings rows

    enum Settings {
        nonisolated static let appearance = "circle.lefthalf.filled"
        nonisolated static let defaultGrouping = "square.grid.2x2"
        nonisolated static let assignFilter = "arrow.triangle.branch"
        nonisolated static let revealPolicy = "faceid"
        nonisolated static let masterPassword = "key.fill"
        nonisolated static let appLock = "lock.fill"
        nonisolated static let autoLock = "timer"
        nonisolated static let clipboardClear = "doc.on.clipboard"
        nonisolated static let clipboardLocalOnly = "laptopcomputer.and.iphone"
        nonisolated static let hideInAppSwitcher = "eye.slash.fill"
        nonisolated static let manageTools = "wrench.and.screwdriver.fill"
        nonisolated static let backup = "externaldrive.fill.badge.checkmark"
        nonisolated static let eraseAll = "trash.fill"
        nonisolated static let account = Action.account
        nonisolated static let disclosure = Action.chevronRight
        nonisolated static let checkmark = Action.checkmark
    }

    // MARK: - Entity fallbacks

    enum Entity {
        nonisolated static let account = PresetCatalog.platformFallbackSymbol
        nonisolated static let accountFill = "building.2.fill"
        nonisolated static let tool = PresetCatalog.toolFallbackSymbol
        nonisolated static let toolCustom = PresetCatalog.toolCustomSymbol
    }

    // MARK: - Resolvers（转发 PresetCatalog）

    nonisolated static func platform(id: String) -> String {
        PresetCatalog.platformSymbol(id: id)
    }

    nonisolated static func tool(name: String, storedSymbol: String? = nil) -> String {
        PresetCatalog.toolSymbol(name: name, storedSymbol: storedSymbol)
    }

    nonisolated static func toolIconForNewBase(_ baseName: String) -> String {
        PresetCatalog.toolIconForNewBase(baseName)
    }
}
