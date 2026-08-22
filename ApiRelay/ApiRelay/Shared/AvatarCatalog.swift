import Foundation

/// 头像底色标记。UI 再映射成 `Color`，本类型不依赖 SwiftUI。
enum AvatarColorToken: String, Sendable, CaseIterable {
    case accent
    case blue
    case indigo
    case teal
    case orange
    case plum
    case slate
}

/// 列表 / 详情用的方标：SF Symbol + 底色。
struct AvatarChoice: Sendable, Equatable, Hashable {
    var symbol: String
    var color: AvatarColorToken

    nonisolated static let key = AvatarChoice(symbol: "key.fill", color: .accent)
    nonisolated static let customAccount = AvatarChoice(symbol: "building.2", color: .slate)
    nonisolated static let customTool = AvatarChoice(symbol: "laptopcomputer", color: .indigo)

    nonisolated static func parse(symbol: String?, color: String?) -> AvatarChoice? {
        let trimmed = symbol?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return nil }
        let token = AvatarColorToken(rawValue: color ?? "") ?? .accent
        return AvatarChoice(symbol: trimmed, color: token)
    }

    /// 空符号表示「跟默认」；写入 SwiftData 时用 nil。
    nonisolated static func stored(symbol: String?, color: String?) -> (String?, String?) {
        guard let parsed = parse(symbol: symbol, color: color) else { return (nil, nil) }
        return (parsed.symbol, parsed.color.rawValue)
    }
}

/// 本机外观里三类默认头像（未单独改过的条目走这里）。
struct AvatarPreferenceDefaults: Sendable, Equatable {
    var key: AvatarChoice
    var customAccount: AvatarChoice
    var customTool: AvatarChoice

    nonisolated static let builtIn = AvatarPreferenceDefaults(
        key: .key,
        customAccount: .customAccount,
        customTool: .customTool
    )

    nonisolated static func from(_ prefs: PreferencesDTO) -> AvatarPreferenceDefaults {
        AvatarPreferenceDefaults(
            key: AvatarChoice.parse(symbol: prefs.defaultKeyAvatarSymbol, color: prefs.defaultKeyAvatarColor) ?? .key,
            customAccount: AvatarChoice.parse(
                symbol: prefs.defaultCustomAccountAvatarSymbol,
                color: prefs.defaultCustomAccountAvatarColor
            ) ?? .customAccount,
            customTool: AvatarChoice.parse(
                symbol: prefs.defaultCustomToolAvatarSymbol,
                color: prefs.defaultCustomToolAvatarColor
            ) ?? .customTool
        )
    }
}

/// 选择器里的预置符号（不是全量 SF Symbol）。
enum AvatarCatalog: Sendable {
    nonisolated static let symbols: [String] = [
        "key.fill",
        "sparkles",
        "building.2",
        "globe",
        "cpu",
        "terminal",
        "curlybraces.square",
        "bubble.left.and.bubble.right",
        "bolt.fill",
        "cloud",
        "leaf",
        "hammer",
        "book.closed",
        "laptopcomputer",
        "app",
        "waveform",
    ]

    nonisolated static func key(
        overrideSymbol: String?,
        overrideColor: String?,
        defaults: AvatarPreferenceDefaults
    ) -> AvatarChoice {
        AvatarChoice.parse(symbol: overrideSymbol, color: overrideColor) ?? defaults.key
    }

    nonisolated static func account(
        platform: String,
        overrideSymbol: String?,
        overrideColor: String?,
        defaults: AvatarPreferenceDefaults
    ) -> AvatarChoice {
        if let override = AvatarChoice.parse(symbol: overrideSymbol, color: overrideColor) {
            return override
        }
        if platform == PresetCatalog.customPlatformID {
            return defaults.customAccount
        }
        return AvatarChoice(
            symbol: PresetCatalog.platformSymbol(id: platform),
            color: platformColor(platform)
        )
    }

    /// 「使用默认」时预览：忽略本条覆盖。
    nonisolated static func accountDefault(
        platform: String,
        defaults: AvatarPreferenceDefaults
    ) -> AvatarChoice {
        account(platform: platform, overrideSymbol: nil, overrideColor: nil, defaults: defaults)
    }

    nonisolated static func tool(
        name: String,
        catalogSymbol: String?,
        overrideSymbol: String?,
        overrideColor: String?,
        defaults: AvatarPreferenceDefaults
    ) -> AvatarChoice {
        if let override = AvatarChoice.parse(symbol: overrideSymbol, color: overrideColor) {
            return override
        }
        if isCatalogTool(name: name) {
            return AvatarChoice(
                symbol: PresetCatalog.toolSymbol(name: name, storedSymbol: catalogSymbol),
                color: toolColor(for: PresetCatalog.toolSymbol(name: name, storedSymbol: catalogSymbol))
            )
        }
        return defaults.customTool
    }

    nonisolated static func toolDefault(
        name: String,
        catalogSymbol: String?,
        defaults: AvatarPreferenceDefaults
    ) -> AvatarChoice {
        tool(
            name: name,
            catalogSymbol: catalogSymbol,
            overrideSymbol: nil,
            overrideColor: nil,
            defaults: defaults
        )
    }

    nonisolated static func isCatalogTool(name: String) -> Bool {
        for tool in PresetCatalog.consumerTools {
            if name == tool.name { return true }
            if name.hasPrefix("\(tool.name) · ") || name.hasPrefix("\(tool.name) - ") {
                return true
            }
        }
        return false
    }

    nonisolated static func platformColor(_ platformId: String) -> AvatarColorToken {
        switch platformId {
        case "openai": return .blue
        case "anthropic": return .orange
        case "google": return .teal
        case "openrouter": return .plum
        case "deepseek": return .indigo
        case "zhipu": return .plum
        case "alibaba-bailian": return .orange
        case "volcengine": return .orange
        case "siliconflow": return .teal
        default: return .slate
        }
    }

    private nonisolated static func toolColor(for symbol: String) -> AvatarColorToken {
        switch symbol {
        case "cursorarrow": return .indigo
        case "curlybraces.square": return .blue
        case "text.bubble": return .orange
        case "book.closed": return .plum
        case "hammer": return .slate
        case "terminal": return .teal
        case "sparkles": return .blue
        case "leaf": return .teal
        default: return .indigo
        }
    }
}
