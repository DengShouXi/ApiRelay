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
    /// 顺序全球唯一，不随语言变：西方厂家英文名；中国厂家中文界面用中文名（DeepSeek 除外）。
    nonisolated static var platforms: [Platform] {
        [
            Platform(id: "openai", displayName: "OpenAI", iconSymbol: "sparkles"),
            Platform(id: "anthropic", displayName: "Anthropic", iconSymbol: "bubble.left.and.bubble.right"),
            Platform(id: "google", displayName: "Google", iconSymbol: "globe"),
            Platform(id: "openrouter", displayName: "OpenRouter", iconSymbol: "arrow.triangle.branch"),
            Platform(id: "deepseek", displayName: "DeepSeek", iconSymbol: "waveform"),
            Platform(id: "zhipu", displayName: String(localized: "preset.platform.zhipu"), iconSymbol: "brain.head.profile"),
            Platform(id: "alibaba-bailian", displayName: String(localized: "preset.platform.alibabaBailian"), iconSymbol: "cloud"),
            Platform(id: "volcengine", displayName: String(localized: "preset.platform.volcengine"), iconSymbol: "bolt.fill"),
            Platform(id: "siliconflow", displayName: String(localized: "preset.platform.siliconflow"), iconSymbol: "cpu"),
        ]
    }

    /// CL-003 定稿。Roo Code 已退出预置，用户已建项不删除。
    nonisolated static let consumerTools: [Tool] = [
        Tool(name: "VS Code", iconSymbol: "curlybraces.square"),
        Tool(name: "Cursor", iconSymbol: "cursorarrow"),
        Tool(name: "Claude Code", iconSymbol: "text.bubble"),
        Tool(name: "Codex", iconSymbol: "book.closed"),
        Tool(name: "Cline", iconSymbol: "hammer"),
        Tool(name: "OpenCode", iconSymbol: "terminal"),
        Tool(name: "Trae", iconSymbol: "sparkles"),
        Tool(name: "Cherry Studio", iconSymbol: "leaf"),
        Tool(name: "Zed", iconSymbol: "z.square"),
        Tool(name: "Continue", iconSymbol: "arrow.right.circle"),
    ]

    /// VS Code 旧符号（三截 `</>`）。存量若仍存此值则回填为 `curlybraces.square`。
    nonisolated static let retiredVSCodeSymbol = "chevron.left.forwardslash.chevron.right"

    /// 仅迁移 VS Code 族上的废止符号，不覆盖用户自选的其他图标。
    nonisolated static func isRetiredVSCodeSymbol(_ stored: String, toolName: String) -> Bool {
        guard stored == retiredVSCodeSymbol else { return false }
        return toolName == "VS Code"
            || toolName.hasPrefix("VS Code · ")
            || toolName.hasPrefix("VS Code - ")
    }

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
