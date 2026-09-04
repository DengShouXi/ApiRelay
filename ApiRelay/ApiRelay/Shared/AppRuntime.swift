import Foundation

/// 运行环境的唯一权威入口。
///
/// 「是不是在跑 XCTest」只允许在这里读宿主注入的配置路径环境变量。
/// 其它文件 MUST 通过本类型查询，不得再各自 `ProcessInfo…environment[…]`。
///
/// 工程默认 MainActor 隔离；本类型供 `KeychainStore` / `CloudKitSyncMonitor` 等
/// actor 在非隔离上下文使用，因此成员一律 `nonisolated`。
enum AppRuntime: Sendable {
    /// 单元测试宿主（`TEST_HOST` = ApiRelay.app）时为 true。
    nonisolated static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    /// 测试专用 UserDefaults suite。MUST 与生产 `.standard` 不同名。
    nonisolated static let testUserDefaultsSuiteName = "com.apirelay.tests.defaults"

    /// 按运行环境给出应使用的 UserDefaults。
    nonisolated static func userDefaultsForCurrentRuntime() -> UserDefaults {
        if isRunningTests {
            guard let defaults = UserDefaults(suiteName: testUserDefaultsSuiteName) else {
                preconditionFailure("AppRuntime: 无法创建测试 UserDefaults suite \(testUserDefaultsSuiteName)")
            }
            return defaults
        }
        return .standard
    }
}
