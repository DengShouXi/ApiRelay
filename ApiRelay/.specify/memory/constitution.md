<!--
Sync Impact Report
==================
Version change: 0.0.0 → 1.0.0 (MAJOR: initial constitution ratification)
Added sections:
  - Core Principles (I-VIII)
  - Platform Experience Standards
  - Stability & Compatibility Requirements
  - Security Requirements
  - Development Discipline
Removed sections: none (initial creation)
Follow-up TODOs: none
-->

# ApiRelay Constitution

## Core Principles

### I. 三层架构解耦 (Three-Layer Architecture Decoupling)

系统 MUST 严格纵向分为三层：界面层 (UI Layer) → 业务层 (Business Layer) → 数据层 (Data Layer)：

- 仅允许上层调用下层接口，MUST NOT 反向依赖或跨层直接读写数据。
- 每层对外暴露协议/接口，隐藏内部实现细节。
- 数据层 MUST NOT 包含任何 UI 框架引用（SwiftUI/UIKit/AppKit）。

**Rationale**: 层间硬约束是架构可维护性的根基。违反此规则将导致代码纠缠、测试困难和重构成本指数增长。

### II. 模块化横向隔离 (Modular Horizontal Isolation)

横向按功能拆分为独立模块：

- 模块间 MUST 仅通过公开的固定接口（protocol/API）通信。
- MUST NOT 直接修改其他模块的内部数据、私有方法或文件。
- 新增功能 MUST 优先创建新模块，不得修改已有模块的对外接口定义。
- 对外接口变更 MUST 遵循语义化版本规则，MAJOR 变更需在 constitution 中记录。

**Rationale**: 接口即契约。隔离模块边界保障独立开发、测试和替换能力。

### III. Apple 原生优先 (Apple Native First)

技术选型 MUST 遵循以下优先级：

- 优先使用 Apple 官方原生框架（SwiftUI, AppKit, UIKit, SwiftData, CloudKit, Keychain 等）。
- 引入第三方 SDK 前 MUST 评估：是否 Apple 原生框架可替代？是否增加不可接受的维护负担？
- MUST NOT 引入仅用于单一便捷功能的重量级第三方依赖。

**Rationale**: 原生框架保障最佳平台体验、最小体积和长期兼容性。

### IV. 跨平台复用与平台适配 (Cross-Platform Reuse with Platform-Specific UI)

代码组织 MUST 遵循：

- 业务层 (Business) 和数据层 (Data) 代码 MUST iPhone/Mac 全端复用，不得包含平台条件编译的 UI 代码。
- 界面层 (UI) 可按平台单独做原生交互适配，允许使用 `#if os(iOS)` / `#if os(macOS)` 条件编译。
- 跨平台共享类型和协议 MUST 放在独立于平台的公共模块。

**Rationale**: 最大化代码复用减少维护负担，同时保障各平台最佳原生体验。

### V. 故障隔离 (Fault Isolation)

单个模块异常 MUST 可被捕获和隔离：

- 模块级错误 MUST NOT 导致应用整体崩溃。
- 业务模块异常 MUST 向 UI 层返回明确的 Error 类型或 Result 类型，不得吞噬错误静默失败。
- 后台任务（网络请求、数据处理）故障 MUST NOT 牵连其他功能模块运行。
- 关键路径（如 API 密钥访问）MUST 有 fallback 策略。

**Rationale**: 用户不应因非关键模块异常而丢失整个应用的功能。

### VI. 向下兼容 (Backward Compatibility)

数据变更 MUST 保证用户升级无缝：

- 数据结构变更（SwiftData Model, UserDefaults, Keychain 等）MUST 做向下兼容处理，不得丢失用户本地数据。
- 新增字段 MUST 设置合理的默认值；废弃字段 MUST 保留解析能力至少一个 MAJOR 版本。
- 调用系统新 API MUST 加版本判断（`@available` / `if #available`），保留最低兼容系统版本声明。

**Rationale**: 用户数据是不可逆资产，升级过程中的数据丢失信任不可恢复。

### VII. 密钥安全 (Key Security)

API 密钥 MUST 受到硬性保护：

- 密钥明文 MUST ONLY 存储于系统 Keychain（`SecItemAdd` / `SecItemCopyMatching`）。
- MUST NOT 将密钥明文写入：SwiftData、CloudKit、UserDefaults、文件系统、日志、第三方 SDK 存储、剪贴板。
- 密钥明文获取后 MUST 在使用完成后及时清理内存引用（将 `String` 置 nil 或使用 `Data` 的 `resetBytes(in:)`）。
- 密钥 MUST NOT 在界面层（View/ViewModel）长期持有或作为 `@Published` 属性持久化。

**Rationale**: 密钥泄露是不可逆安全事故。Keychain 是 Apple 平台唯一经系统级加密保护的存储方案。

### VIII. 生物识别鉴权 (Biometric Authentication Gate)

查看或导出密钥明文 MUST 通过生物识别鉴权：

- 使用 `LAContext` (LocalAuthentication) 调用 Face ID / Touch ID 验证用户身份。
- 鉴权结果 MUST NOT 被缓存复用超过单次操作生命周期。
- 鉴权失败时 MUST 提供降级方案（设备密码），不得完全锁死用户访问。

**Rationale**: 即使设备已解锁，密钥访问仍需二次身份确认，防范未授权物理访问。

## Platform Experience Standards

交互与视觉 MUST 遵循 Apple 系统设计规范：

- iOS 端遵循 iOS Human Interface Guidelines；macOS 端遵循 macOS Human Interface Guidelines。
- 导航模式、手势、动画 MUST 匹配对应平台的系统原生行为。
- 字体、颜色、间距 MUST 优先使用系统动态值（`Font.TextStyle`, `Color.accentColor`），支持 Dynamic Type 和 Dark Mode。
- 第三方 UI 库引入 MUST 通过上述 Apple Native First 原则的评估。

## Stability & Compatibility Requirements

应用稳定性 MUST 通过以下保障：

- 最低系统版本：iOS 17.0 / macOS 14.0（声明在 Xcode 项目部署目标中）。
- 所有异步操作 MUST 使用 Swift Concurrency（`async/await`）或 Combine，不得使用 GCD 裸调。
- 网络请求 MUST 设置超时并处理可达性变化（`NWPathMonitor`）。
- 崩溃上报 MUST 集成（不在此项目范围，但架构预留 hook 点）。

## Security Requirements

安全底线 MUST 零妥协：

- 不得在 Git 提交中包含任何密钥、证书、Token。
- `.gitignore` MUST 排除 `.env`、`*.xcconfig`（如含敏感信息）、`GoogleService-Info.plist` 等价文件。
- HTTPS ONLY — 所有网络通信 MUST 使用 TLS 1.2+，不得降级到 HTTP。
- Certificate Pinning 建议但非初始版本强制。

## Development Discipline

开发过程 MUST 遵守：

- 单功能开发完成即提交 Git 存档，提交信息 MUST 清晰描述变更模块和原因。格式：`<type>(<scope>): <description>`（如 `feat(relay): add request forwarding`）。
- 单次提交 MUST 仅改动对应模块，不得跨模块大范围无关修改。
- 每次提交前 MUST 确认项目编译通过（`xcodebuild` 或 Xcode Build）。
- 功能分支 MUST 从 `main` 拉出，合并前 MUST 确保 `main` 最新无冲突。

## Governance

本宪法是 ApiRelay 项目的最高开发准则，所有设计决策、代码审查和架构变更 MUST 以本文为准：

- 任何原则变更 MUST 经版本号递增（MAJOR/MINOR/PATCH 遵循语义化版本）并在 Sync Impact Report 中记录。
- MAJOR 变更（原则删除或重新定义）MUST 以独立分支提交，并在合并前经过评审。
- 所有代码审查 MUST 验证是否符合本宪法规定，发现违规 MUST 在合入前修正。
- 如需豁免某条原则（如紧急修复不可抗力），MUST 在提交信息中明确标注豁免理由和失效期限。

**Version**: 1.0.0 | **Ratified**: 2026-08-04 | **Last Amended**: 2026-08-04
