# Mac 隐私生命周期与剪贴板系统核对

> 核对日期：2026-09-23
> 来源：电脑端真实使用后发现的非 Spec Kit 调整。
> 范围：自动锁定、应用切换遮挡、剪贴板自动清除、通用剪贴板控制及其安全偏好提交边界。
> 结论：保留现有认证架构；修复桌面生命周期适配和剪贴板边界，不重写已通过真机验证的认证执行核心。

## 根因结论

这次不是密码算法、应用密码材料或单次系统认证架构再次失效，而是四项同属“明文离开当前操作面”的功能没有被作为一条完整的桌面隐私链验收：

1. `AppPrivacyController` 原先主要按 UIKit / iPad 窗口场所判断“是否离开”。Mac 切到其它 App 后，本窗口可能仍在屏上，旧判断会把它归为 `onScreenIdle`，因此既不开始自动锁计时，也会立即摘掉遮罩。
2. 原生 macOS 分支没有与 UIKit 等价的实际窗口遮罩；状态机即使算出应遮挡，也没有 AppKit 图层落到窗口上。
3. 剪贴板计时任务取消后仍可能继续执行；连续复制时旧任务可能清掉新内容。旧所有权判断只比较文本，另一个 App 后来复制相同文本时也可能被误删。
4. “立即清除”对应 0 秒，旧实现把 `<= 0` 与“关闭自动清除”的 `nil` 混在一起，结果是不排程也不清除。
5. 密钥服务与设置页分别持有长期 SwiftData `ModelContext`，设置已保存后，复制路径仍可能读到注册在旧上下文里的旧开关值。
6. Mac Catalyst 的 `.localOnly` 写入失败后曾回退到普通剪贴板；这会在用户明确要求仅本机时悄悄降低保护。
7. 原生 AppKit 没有 UIKit `.localOnly` 的公开逐条等价接口。旧的绝对“禁用通用剪贴板”口径不能用于原生 macOS。

## 现行方案

| 功能 | 现行行为 |
| --- | --- |
| Mac 自动锁定 | macOS、Mac Catalyst、iOS-on-Mac 中，用户切到其他 App、导致整个应用失去 active，即视为离开；立即档当场静默锁，非零档从首次真实失焦时开始计时。只有本 App 发起的精确 `LocalAuthentication` 请求所造成的短暂 resign 延后判断；请求完成、取消或失效后立即复核宿主状态，若仍 inactive 则补做离场、遮挡、撤权与锁定，不能让面板期间 Cmd-Tab 绕过。 |
| 切换遮挡 | 桌面端失焦后强制把全部本 App 窗口归为离屏；UIKit/Catalyst 使用现有窗口遮罩，原生 AppKit 在每扇 `NSWindow.contentView` 顶层安装无交互遮罩。回到 App 后按窗口状态揭罩。 |
| 剪贴板自动清除 | `nil` 才表示关闭；0 秒表示写入后立即清除；正数使用应用内任务。授权检查、系统剪贴板写入与失败回滚通过 `ClipboardCommit` 在同一次同步 MainActor 提交中完成；每次成功写入再登记代次与系统 `changeCount`。旧任务、后来写入、相同文本的新写入均不得被误清；新写失败前不得先取消上一份仍有效的清理责任。正常退出继续按 `changeCount` 尽力清除；强制退出与崩溃不承诺。 |
| 设置即时生效 | `UserPreferencesRepository` 每次安全读取或条件更新前回到最新持久化快照，避免长期上下文继续返回旧安全偏好。 |
| 通用剪贴板 | iPhone/iPad/Mac Catalyst 使用 `.localOnly`；失败直接报写入失败，不回退普通剪贴板。原生 macOS 写敏感/临时标记并在设置中明确为尽力而为；需要保证时由用户在系统设置关闭“接力”。 |
| 安全降级 | 关闭自动锁、遮挡、自动清除、仅本机/减少跨设备共享，或拉长自动锁/剪贴板清除时间，均先按当前验证方式确认并在保存成功后生效。开启保护或缩短时间可立即生效。 |

## 主要落点

- 生命周期与窗口遮挡：`AppPrivacyController.swift`、`AppLockSession.swift`、`ScenePresenceSignals.swift`。
- 剪贴板所有权与计时：`ClipboardServing.swift`。
- 安全偏好新鲜度：`UserPreferencesRepository.swift`、`KeyVaultService.swift`。
- 安全降级分类：`SessionLockQuerying.swift`。
- 能力披露：`SettingsView.swift`、`SettingsGroupedChrome.swift`、`Localizable.xcstrings`。
- 正式规格回写：`spec.md`、`research.md`、`quickstart.md`。

## 自动验证

- 定向回归：30 项、0 失败，覆盖 Mac 失焦立即锁、宽限计时、Touch ID 不自锁、全部窗口遮挡、剪贴板连续写入、相同文本所有权、0 秒立即清除、设置即时传播和安全降级分类。结果包：`/tmp/ApiRelay-PrivacyAudit-Targeted-20260923.xcresult`。
- 全量 iOS 模拟器回归：463 项、0 失败，`** TEST SUCCEEDED **`。结果包：`/tmp/ApiRelay-PrivacyAudit-Full-20260923.xcresult`。
- 原生 macOS arm64 构建：`** BUILD SUCCEEDED **`，Derived Data：`/tmp/ApiRelay-PrivacyAudit-macOS-Final`。
- Mac Catalyst arm64 构建：`** BUILD SUCCEEDED **`，Derived Data：`/tmp/ApiRelay-PrivacyAudit-Catalyst-Final`。
- `git diff --check` 与本地化 JSON 解析通过。
- 上述 30/463 是本页修复完成时的原始证据，必须保留。随后的整体架构加固继续覆盖剪贴板最终提交、写后失败回滚、离焦撤权与设置实际落盘；最新三平台全量结果、构建身份和设备观察统一见 [`22 §8`](./22-密码与身份验证整体架构审计与加固.md#8-验证记录)，本页不复制第二份易过期台账。

## 边界与维护决定

- 这次不改 `RevealGate` 的单次设备主人认证顺序，不恢复旧的双上下文 Face ID 流程。
- iPad 同组窗口仍按窗口焦点治理；Mac 切到其它 App 必须按整个应用失焦治理。两种平台语义不得再共用一个“窗口仍可见所以没有离开”的结论。
- 原生 macOS 不得宣称逐条绝对关闭 Universal Clipboard；这是平台能力边界，不得用禁用复制冒充实现。
- 旧阶段提示词与历史实现仍只作审计材料；本文件、[`20-现行需求与代码核对.md`](./20-现行需求与代码核对.md)、[`22-密码与身份验证整体架构审计与加固.md`](./22-密码与身份验证整体架构审计与加固.md) 和正式规格构成当前口径。
- 本轮不提交、不上传、不改 `main`、不打 tag。
