# v1.13.10 阶段 5 · 独立审计报告

方法版本：MAIC-1.3.1  
阶段：5  
时间：2026-09-24  
分支：`v1.13.10`  
起始 HEAD：`25fe006896a816475e269e155530c1464cc19304`  
实施者：Codex 阶段 4 执行代理  
审计者：独立审计代理（非阶段 4 实施者）  
输入：本工作包 00、00B、00C、03、04、06、阶段 5 提示词、ZL00/04、实际 Git 差异与 xcresult  
授权：只读独立审计；仅写本报告，不改代码、契约、原工作树，不提交上传。

## 已核实的事实

- `06-Codex本地实施报告.md` 末行明确 `写入状态：已停止`；检查器退出 0，下一阶段为 5，暂存区为空，方法版本与历史产物身份有效，当前 HEAD 仍为基线。
- 独立读取 xcresult：签名单测 608 通过、0 失败；iPhone 16 Simulator UI 3 通过、0 失败；iPad (A16) iPadOS 26.5 Simulator UI 3 通过、0 失败。三套结果均无跳过及运行时警告。原生 Mac UI 结果为 runner 在启用自动化模式时超时，0 个应用级断言；Catalyst UI 未取得可读取的完整测试摘要。三端 build-for-testing 通过是实施报告证据，不能替代缺失的 Mac/Catalyst UI 运行结果。
- 实际差异位于契约允许范围，`git diff --check` 通过。抽查 `SecureBackupServing` 模型、`AppSwitcherSnapshotCover` 为机械迁出；KeyVault actor、WAL/提交实现及持久数据目录无差异。新增 UI fixture 使用固定 DEBUG 场景、内存假服务，`installsSnapshotCover` 和 `enablesUnlockPrompt` 均保留开启；没有发现生产密钥或 CloudKit 被 UI fixture 直接读写。
- `ApiRelay.entitlements`、`Schema.swift`、`KeychainStore.swift` 的 SHA-256 分别仍为 `8c49887c42f110a6b6f92c1f85ba1d66fbb53e04df295a6a7d91e8394532a3c0`、`0a1537ab4296c9f17f125d9bf98147912262b3c75ef25ecefb11a679ba18c3a8`、`0693a04fbfca06f874f300dda394c854716206e8f556b0f398e39aa60795b6f7`，与 04 基线一致。原主工作树仍为 `v1.13.9`／同一基线 HEAD，只读指纹仍为 `838414ac8e8eb18dc8bc878ef48624881ad69684d541f5b3e934a262e3c2b809`。

## 阻塞问题与精确整改

1. **W4 ownership 未完成。** 阶段 3 明确列出设置 committed snapshot/draft、互斥 pending action、Vault 派生/回收站、生命周期 reducer、session writer capability 五组；阶段 4 只删除策略页 `highlightedPolicy`，并自行承认其余项未完成或未证明可安全合并。当前 `SettingsView` 仍有多份 pending/认证状态，`VaultHomeView` 仍持有回收站可见集、勾选集、选择与空态投影，`AppPrivacyController` 仍有多组生命周期证据字段。阶段 6 须逐项完成经批准的 ownership 迁移并补行为回归；若某项本来就是单一权威，应提供逐项数据流、写入者和不迁移理由，不能仅以“风险高”视为已完成。若决定删减阶段 3 目标，必须先重新取得用户对计划变更的确认。
2. **Mac/Catalyst UI 验收缺证据。** `00B-自动化架构与验收口径.md` 要求 iOS、原生 macOS、Mac Catalyst 分别测试。原生 Mac xcresult 明确是 UI runner 初始化失败，不是 App 断言通过；Catalyst 也没有有效的 UI 通过结果。阶段 6 先诊断 runner、签名与宿主权限，再在用户明确同意时处理需要系统授权的权限；获得两平台实际 UI 断言结果后才可关闭此项。不得把 build-for-testing 当作 UI 测试通过，也不得静默跳过平台。
3. **既定 XCUITest“失败回滚”场景未覆盖。** `00B` 要求真实 UI 测试覆盖失败回滚；当前三个 UI 方法只测正确密码切换、重启锁屏及 Home 快返，没有输入错误应用密码后确认当前策略不变、页面不跳转、可重试的断言。阶段 6 应补该 UI 用例，在 iPhone/iPad 及能够启动的桌面 runner 上运行。
4. **安全偏好通知的顺序等价未证明。** `SecurityPreferenceCommit` 从持久化回调内同步发布通知，改为分别创建 `Task { @MainActor ... }` 异步发布；这修正了线程交付，但改变了回调与通知的时序。现有测试只等待最终通知，不验证连续成功/失败提交时的顺序、落盘后可见性或离前台撤销时旧通知不会覆盖新状态。阶段 6 应保留主线程交付，同时增加这些次序回归；若无法证明与冻结的安全语义等价，应回到阶段 3 裁决，而非把潜在时序变化算作纯机械拆分。

## 裁决

上述问题均处于已批准的 v1.13.10 范围内；本轮不得进入阶段 7 或提交上传。下一步由阶段 6 实施者只处理这四项阻塞，再交另一轮独立复验；Mac 系统权限如需变更须先获得用户明确同意。下一提示词：`/Users/xitongzhili/.codex/worktrees/v1-13-10-structural/E02_ApiRelay_Github/ApiRelay/specs/001-key-vault/follow-ups/v1.13.10-structural-stabilization/提示词/阶段6-Codex修复阻塞问题.md`。

方法观察：阶段 4 如实标注未完成 W4 和桌面 UI runner，使本轮能直接识别阻塞；现行阶段闸门有效，未发现需修改通用方法的新问题。

写入状态：已停止

审计不通过，存在阻塞问题，不得进入阶段7或8。
