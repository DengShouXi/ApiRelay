写入状态：未停止

# 阶段4：Grok波次整改报告（U2-W5）

- 阶段：4
- 修订ID：U2
- 计划修订：U2-R1（产品答案不变；本波按 04 第八节 U2-W5 实施）
- 波次：U2-W5（移除四类普通表面的设密路径；缺材料拒绝 + 独立恢复 + 待办清除；定向回归取用复用和破坏性顺序）
- 时间：2026-09-15
- 分支：`v1.13.9`
- HEAD：`6ec5ff7c67547637bbd55f528276422395e28c03`
- 方法版本：`MAIC-1.3`
- 工作包：`ZL02_研发档案/第一阶段-密钥库/调整与优化/v1.13.9-身份验证四档与主密码调整/`
- 输入：U2-R1 版 `04` 第八节（含原 W5 清单）、`05` 第十二节 D、`00C`、W3/09、W3/10
- 批准来源：W3/07 记录 2026-09-15 用户原文「明确同意 U2-R1 的 04 和 05」。本波未要求重复批准。W3/10 独立结论「波次审计通过，可以进入下一波。」
- 实际授权：用户执行 `提示词/阶段4-Grok执行下一波.md`。W3/09 存在且 W3/10 合法独立通过，故将 W3 视为通过并只实施 U2-W5。不重做 W0/W2/W3；不进 U2-W6；不覆盖 W5/01–08；不处理 `tools/`、xcodeproj、暂存、提交、上传、main/tag
- 保护 refs（未改）：`main` / `origin/main` = `539447ea9984608c74989da48b8770cb3fe32a6c`；`release/1.0.0` 对象 = `5c5eed3f8390f51f5a26be9737bcc11f72e7d7fd`
- 暂存区：空；单一 worktree；`git diff --check` 通过

文末 `写入状态：已停止` 为交接用最终状态。

## 1. 入口核对

- 当前分支 `v1.13.9`，HEAD 仍为契约基线。
- U2 链：W0/08、W2/10 通过；W3 以 W3/10 独立通过为准（W3/08 为历史失败，已被 09/10 覆盖）。旧 W5/08 通过不代替 U2-W5。
- 本文件为 `实施波次/W5/` 下一个连续奇数报告 `09`，不覆盖 01–08。配对将来是 `10-Codex波次复验报告.md`。
- 上一写入者：W3/10 已停止。未读取、未修改 `tools/`。未改四个服务透传实现、Keychain、PBKDF2。未改正式规格。

## 2. 本波实际文件（均在原 W5 清单 ∩ `00C.allowedModify` 内）

| 文件 | 做什么 |
| --- | --- |
| `Business/System/SessionLockQuerying.swift` | `AppPasswordPolicyGate.ordinaryEntryMissingMaterialMessage()`，四类普通入口共用缺材料文案 |
| `UI/Vault/VaultHomeViewModel.swift` | 删除 `completeCombinationSetupThenRetry`；缺材料拒绝、清待办、指向独立恢复；恢复先丢待办且不重试原操作 |
| `UI/Vault/VaultHomeView.swift` | 口令页不再使用设密标题；错误框提供「通过设备验证恢复」 |
| `UI/Settings/BackupSettingsViews.swift` | 口令/导出/导入去掉 `setPassword`；缺材料拒绝并给出独立恢复按钮 |
| `UI/Settings/SettingsView.swift` | 降低安全/清空：缺材料不打开口令框、不设密、清待办 |
| `Localizable.xcstrings` | 补 `appLock.combination.hint` / `notSet`、`appLock.useAppPassword` 及 W3/W5 仍在用的应用密码/取用/查看键；界面名称「应用密码」 |
| `RevealGateCoordinatorTests.swift` | 缺材料 0 写/0 删除；独立恢复不重试删除；四类表面源码不得再 `setPassword` |

未改但属允许清单：`AppLockCoverView.swift`、`AppPrivacyController.swift`（锁屏普通入口已拒绝设密，W3 已有测试）、`KeyDetailView.swift`（仍只调用 `beginCombinationAppPasswordEntry`）、`KeyVaultService.swift` / 服务透传、各 Fake。未新增生产或测试文件。

## 3. 提交定义（普通入口不得设密）

- 组合档纯生物：缺材料仍可走生物识别完成原操作。
- 显式应用密码路径：材料未设或不可读 → 拒绝、`setPassword` 次数 0、原业务副作用 0、清待办。
- 显式进入恢复：先丢原待办，再走锁屏同一套 `recoverFromLostMasterPassword`；恢复后不自动删除/导出/清空。
- 设置页专用创建/改密/恢复仍走 W3 管理页（`createAppPasswordMaterialThenPersist` / `resetAppPasswordAndFallToDeviceAuth`），不是普通入口。

## 4. 四类表面接线（共享代码，不是三端手测）

| 表面 | 用户入口 | 显式选择 | 缺材料 | 独立恢复 | 待办 |
| --- | --- | --- | --- | --- | --- |
| App 锁 | 「使用应用密码」 | `unlockWithCombinationAppPassword` | `combination.notSet`，不写材料 | `recoverFromLostMasterPassword` | 保持锁定，不执行旧解锁待办 |
| Vault | 详情/列表「使用应用密码」 | `beginCombinationAppPasswordEntry` → 已设才出口令框 | `refuseOrdinaryAppPasswordPath` | 错误框「通过设备验证恢复」 | `abandonCombinationPending` |
| 备份 | 口令/导出/导入组合档按钮 | 已设才 `showAppPasswordPrompt` | 状态文案 + 拒绝 `setPassword` | `OrdinaryMissingAppPasswordRecoveryButton` | `onDisappear` / 拒绝时清空 pending |
| 设置 | 降低安全/清空「使用应用密码」 | 已设才打开 weaken/erase 口令框 | `ordinaryEntryMissingMaterialMessage` | 首页管理行恢复（W3） | `abandonSettingsCombinationPending` |

破坏性顺序未改：仍是确认 → 身份验证 → 写入。取用复用七种失效生产方法保留。

## 5. 测试

```text
bash ApiRelay/scripts/selfcheck.sh
红线检查：全部通过
git diff --check：退出 0
```

iPhone 17 Pro / iOS 26.5 模拟器，`-derivedDataPath /tmp/ApiRelayAgentDD`，本地签名：

```text
/tmp/ApiRelayU2W5-09.xcresult
Executed 135 tests, with 0 failures
** TEST SUCCEEDED **
```

| 类 | 通过 |
| --- | --- |
| AppPrivacyControllerTests | 43 |
| ConsumerToolSessionLockTests | 5 |
| DataLifecycleTests | 8 |
| KeyVaultServiceTests | 33 |
| RecentlyDeletedBatchTests | 12 |
| RevealGateCoordinatorTests | 16 |
| SecureBackupTests | 18 |

本波新增：

- `testOrdinaryCombinationMissingMaterialDoesNotSetPasswordOrRetryDelete`
- `testOrdinaryMissingMaterialIndependentRecoveryDoesNotRetryDelete`
- `testOrdinarySurfacesDoNotCallSetPasswordOnMissingMaterialPath`

`xcodebuild test` 已编过同一 Debug 模拟器产物；未另跑 Mac Catalyst 构建。

## 6. 三端

共用逻辑在 iPhone 17 Pro 模拟器单测上验证。下列不是三端运行通过。

| 端 | 接线 | 本波结果 | 未验证 |
| --- | --- | --- | --- |
| iPhone | 上表四类 SwiftUI 入口 | 模拟器 135 项绿 | 真机 Face ID、系统弹窗、导航手测 |
| iPad | 同一套入口 | 未单独跑 | 分栏/详情关闭后的授权与待办 |
| Mac Catalyst | 同一套入口 | 未构建、未跑 | 多窗、快捷键、无 Touch ID 的设备密码路径 |

U2-W6 才填三端人工矩阵。共享测试不能冒充三端通过。

## 7. 收尾四问

1. **外部资源：** 应用密码材料仍只在本机 Keychain。本波普通入口不再写入。测试用 `FakeMasterPassword` / `FakePreferences` / `FakeRevealGate` 与 `KeychainStore.makeForTests()` 的真实 `KeyVaultService`。未打开 App 组、未处理 `tools/` 或 xcodecloud manifest。
2. **失败路径：** 缺材料点「使用应用密码」会看到「本机还没有应用密码…当前操作已取消」，原删除/备份/降低不会发生。可改走生物识别（组合档）或显式恢复。恢复失败保持原策略/锁态（W3 已有）。空口令仍拒。取消清待办。
3. **接缝：** `VaultHomeViewModel` 的拒绝/恢复可直接测。备份/设置主要靠源码接线断言 + 既有组合档正向测试。未新增 protocol。
4. **文件粒度：** `VaultHomeView.swift` 4572、`SettingsView.swift` 1994、`VaultHomeViewModel.swift` 1337、`BackupSettingsViews.swift` 1127，均超过 400 行。本波不拆。

## 8. 未验证 / 停止点

- 真机/平板/电脑导航与系统弹窗：U2-W6。
- 双设备 CloudKit、旧 W6/02 B1–B3、工程 manifest：U2-W6。
- 本波完成不可预写 W6 或上传。
- 实施中曾误用 `git checkout -- Localizable.xcstrings` 丢掉未提交的 W1–W5 文案；已按现行 Swift 引用和 U2 用词补回，并改为局部插入，避免整文件重写。若个别历史译句与丢失前不完全一致，以当前代码引用为准。

## 9. 方法观察

直接修复角色覆盖按 4D/10 把 W3 视为通过后，阶段4必须只做 U2-W5，不能回头再修 08 旧缺口。本地化文件已有累计未提交改动时，禁止 `git checkout --` 整文件；缺键只能局部插入。

下一步负责人：Codex
是否需要用户批准：否
下一步：执行 `/Users/xitongzhili/Desktop/MacTransfer/08_Code/E02_ApiRelay_Github/ZL02_研发档案/第一阶段-密钥库/调整与优化/v1.13.9-身份验证四档与主密码调整/提示词/阶段4A-Codex波次审计.md`

写入状态：已停止
