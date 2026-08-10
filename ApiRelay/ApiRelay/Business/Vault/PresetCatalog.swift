import Foundation

/// 上游平台与使用方工具的内置清单。
/// 上游平台：预置选项 + 自定义。
/// 使用方工具：`consumerTools` **仅作添加表单的名称建议**，启动时不再写入数据库。
/// 平台 / 工具 SF Symbol 在此定义；UI 经 `AppSymbols` 收口引用。
enum PresetCatalog: Sendable {
    struct Platform: Sendable, Identifiable, Hashable {
        let id: String
        let displayName: String
        /// 品类隐喻 SF Symbol（无商标）。
        let iconSymbol: String
    }

    struct Tool: Sendable, Identifiable, Hashable {
        var id: String { name }
        let name: String
        let iconSymbol: String?
    }

    nonisolated static let customPlatformID = "custom"

    /// 未知 / 自定义上游账号兜底符号。
    nonisolated static let platformFallbackSymbol = "building.2"
    /// 用户自建使用方兜底符号。
    nonisolated static let toolFallbackSymbol = "laptopcomputer"
    nonisolated static let toolCustomSymbol = "app"

    /// 每次访问按当前语言解析显示名（勿用 `static let` 冻住首次语言）。
    nonisolated static var platforms: [Platform] {
        [
            Platform(id: "openai", displayName: "OpenAI", iconSymbol: "sparkles"),
            Platform(id: "anthropic", displayName: "Claude", iconSymbol: "bubble.left.and.bubble.right"),
            Platform(id: "google", displayName: "Google", iconSymbol: "globe"),
            Platform(id: "openrouter", displayName: "OpenRouter", iconSymbol: "arrow.triangle.branch"),
            Platform(id: "deepseek", displayName: "DeepSeek", iconSymbol: "waveform"),
            Platform(id: "alibaba-bailian", displayName: String(localized: "preset.platform.alibabaBailian"), iconSymbol: "cloud"),
            Platform(id: "volcengine", displayName: String(localized: "preset.platform.volcengine"), iconSymbol: "bolt.fill"),
            Platform(id: "siliconflow", displayName: String(localized: "preset.platform.siliconflow"), iconSymbol: "cpu"),
        ]
    }

    /// CL-003 定稿。
    nonisolated static let consumerTools: [Tool] = [
        Tool(name: "VS Code", iconSymbol: "chevron.left.forwardslash.chevron.right"),
        Tool(name: "Cursor", iconSymbol: "cursorarrow"),
        Tool(name: "OpenCode", iconSymbol: "terminal"),
        Tool(name: "Trae", iconSymbol: "sparkles"),
        Tool(name: "Cline", iconSymbol: "hammer"),
        Tool(name: "Roo Code", iconSymbol: "bird"),
        Tool(name: "Cherry Studio", iconSymbol: "leaf"),
        Tool(name: "Zed", iconSymbol: "z.square"),
        Tool(name: "Continue", iconSymbol: "arrow.right.circle"),
    ]

    nonisolated static func platform(id: String) -> Platform? {
        if id == customPlatformID {
            return Platform(
                id: customPlatformID,
                displayName: String(localized: "vault.custom.platform"),
                iconSymbol: platformFallbackSymbol
            )
        }
        return platforms.first { $0.id == id }
    }

    /// 平台 id → SF Symbol（含未知兜底）。
    nonisolated static func platformSymbol(id: String) -> String {
        platform(id: id)?.iconSymbol ?? platformFallbackSymbol
    }

    /// 使用方显示名 → SF Symbol；优先 `storedSymbol`，再匹配预置基名。
    nonisolated static func toolSymbol(name: String, storedSymbol: String? = nil) -> String {
        if let stored = storedSymbol, !stored.isEmpty { return stored }
        if let exact = consumerTools.first(where: { $0.name == name })?.iconSymbol {
            return exact
        }
        for tool in consumerTools {
            guard let symbol = tool.iconSymbol else { continue }
            if name.hasPrefix("\(tool.name) · ") || name.hasPrefix("\(tool.name) - ") {
                return symbol
            }
        }
        return toolFallbackSymbol
    }

    /// 新建使用方时，按所选基名解析应写入的 `iconSymbol`。
    nonisolated static func toolIconForNewBase(_ baseName: String) -> String {
        consumerTools.first(where: { $0.name == baseName })?.iconSymbol ?? toolCustomSymbol
    }
}
