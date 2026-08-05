import Foundation

/// 上游平台与使用方工具的内置清单。
/// 上游平台：预置选项 + 自定义。
/// 使用方工具：`consumerTools` **仅作添加表单的名称建议**，启动时不再写入数据库。
enum PresetCatalog: Sendable {
    struct Platform: Sendable, Identifiable, Hashable {
        let id: String
        let displayName: String
    }

    struct Tool: Sendable, Identifiable, Hashable {
        var id: String { name }
        let name: String
        let iconSymbol: String?
    }

    nonisolated static let customPlatformID = "custom"

    nonisolated static let platforms: [Platform] = [
        Platform(id: "openai", displayName: "OpenAI"),
        Platform(id: "anthropic", displayName: "Claude"),
        Platform(id: "google", displayName: "Google"),
        Platform(id: "openrouter", displayName: "OpenRouter"),
        Platform(id: "deepseek", displayName: "DeepSeek"),
        Platform(id: "alibaba-bailian", displayName: "阿里百炼"),
        Platform(id: "volcengine", displayName: "火山引擎"),
        Platform(id: "siliconflow", displayName: "硅基流动"),
    ]

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
            return Platform(id: customPlatformID, displayName: "自定义")
        }
        return platforms.first { $0.id == id }
    }
}
