写入状态：已停止

> 2026-09-15 Codex经用户授权修正交接状态：依据本报告原文末及元数据的已停止声明，移除遗留的运行标记。只修记录，不代替Grok独立结论，也不保证外部编辑器当前没有启动新工作。

# 阶段4A：Grok集中修复独立复核（U2-W5 / 4F）

- 阶段：4A（Codex 集中检查与直接修复后的独立只读复核；不是执行者自测，不能给 10 自己签字）
- 修订ID：U2
- 计划修订：U2-R1
- 波次：U2-W5
- 时间：2026-09-15
- 分支：`v1.13.9`
- HEAD：`6ec5ff7c67547637bbd55f528276422395e28c03`
- 方法版本：`MAIC-1.3`
- 工作包：`ZL02_研发档案/第一阶段-密钥库/调整与优化/v1.13.9-身份验证四档与主密码调整/`
- 输入：`00C`、`04` 第八节 U2-W5、`05` 第十二节 D、W5/09、W5/10 及 10 列出的五份实际文件
- 实际授权：用户调用 `提示词/阶段4F-Grok集中修复独立复核.md`。只读检查，不修改被审对象，不处理 `tools/` 或工程 manifest，不暂存、不提交、不上传
- 保护 refs（未改）：`main` / `origin/main` = `539447ea9984608c74989da48b8770cb3fe32a6c`；`release/1.0.0` 标签对象 = `5c5eed3f8390f51f5a26be9737bcc11f72e7d7fd`（剥到提交 `539447ea`）
- 暂存区：空；单一 worktree；本轮未改实现/测试/规格
- 写入状态：已停止（文末再次标明）

## 1. 入口与 10 范围诚实性

- W5/09、W5/10 均已停止。开始时不存在 11，本文件新建不覆盖。
- 10 写明：阶段 4A 检查后按用户「如果还存在什么问题，立刻帮我修复了」转直接实施；**是实施者自测，不能由 Codex 给自己独立签字。**
- 10 实际五文件（均在原 W5 清单 ∩ `00C.allowedModify`）：`VaultHomeViewModel.swift`、`BackupSettingsViews.swift`、`Localizable.xcstrings`、`RevealGateCoordinatorTests.swift`、`SecureBackupTests.swift`。未改服务透传、模型、算法、Keychain、`tools/`、xcodeproj。
- 四类普通表面的现场接线一并核对（App 锁 / 设置不在 10 五文件内，但属于 `05` D 必查入口）；不把源码关键词断言当成全部界面证据。

## 2. 集中核对（现场函数/回调）

### 组合档普通纯生物仍可用

`CurrentRevealPolicyAuth.confirm`：组合档且 `appPassword == nil` 只走 `gate.confirm(.biometryOrAppPassword)`；非空才 `confirmCombinationWithAppPassword`。独立复跑 `testCombinationConfirmWithoutPasswordUsesBiometricsOnce` 通过。

### 两种密码依赖档：缺材料显式密码路径

| 档 | 现场 | setPassword | 原业务 | 独立恢复 |
| --- | --- | --- | --- | --- |
| 组合档显式应用密码 | `VaultHomeViewModel.beginCombinationAppPasswordEntry` 异步查询后再次确认仍有绑定待办，否则 `refuseOrdinaryAppPasswordPath`（先 `abandonCombinationPending`） | 0（`submitMasterPassword` 在 `combinationNeedsSetup` 时同样 refuse；生产 UI 无 `masterPassword.setPassword`） | 删除未发生 | 错误框「通过设备验证恢复」→ `recoverIndependentAppPasswordFromOrdinaryEntry`（先丢待办再 `recoverFromLostMasterPassword`） |
| 仅应用密码档 | `prepareSensitiveAuth` 材料未设则 refuse，不打开口令框 | 0 | `deleteKey` 未进门闩 | 同上 |
| 备份仅应用密码 | `BackupCurrentPolicyAuth.confirm` 材料未设抛 `master_password_not_set`，**不当** `master_password_prompt_required` | 0 | 不进入口令框 | `OrdinaryMissingAppPasswordRecoveryButton` |
| App 锁组合档 | `unlockWithCombinationAppPassword` 缺材料拒绝；`setupCombinationAppPasswordFromLock` 仍无写入 | 0 | 保持锁定 | 缺材料按钮走 `onRecoverFromLostMasterPassword` |
| 设置组合档降低/清空 | `beginSettingsCombinationPassword` 缺材料写 `ordinaryEntryMissingMaterialMessage` 并 `abandonSettingsCombinationPending` | 0 | 待办清除 | 首页管理行（W3） |

### 备份五处缺材料：清待办 + 恢复取消/失败提示

现场五处 `BackupCurrentPolicyAuth.isMissingMaterial` 捕获（不是关键词扫描代替）：

1. `finishPassphraseAction`（口令保存/复制/清除）
2. `exportWithStored`
3. `performExport`
4. `importWithStored`
5. `importData`

每处：`pending* = nil`、关闭普通密码框、`status = ordinaryEntryMissingMaterialMessage()`、`showIndependentRecovery = true`。三处 `begin*CombinationPassword` 在材料不可用时同样清待办、不弹框。

`OrdinaryMissingAppPasswordRecoveryButton`：防重入；点击先 `onDiscardPending`；不立即卸掉组件。`unlockError` 显示失败；取消路径 `recoverFromLostMasterPassword` 对 `authenticationCancelled` 置空错误并 return，按钮因策略仍非设备验证而显示 `gate.cancel`，**不**用 `settings.masterPassword.resetDone` 伪报成功；仅当本机策略已是 `.biometricOrPasscode` 才显示恢复完成文案。

### 恢复不自动重试原操作

Vault：`recoverIndependentAppPasswordFromOrdinaryEntry` 先 `abandonCombinationPending`。`testOrdinaryMissingMaterialIndependentRecoveryDoesNotRetryDelete`：密钥仍在，待办空，策略落到设备验证，`setPassword` 0。生产恢复仍走 `applyRecoveryOutcomeKeepingLock`，不调用 `finishUnlockSucceeded`（复用 W3：`testForgotMasterPasswordKeepsLockWhenPersistFails` / `DoesNotFallToNoVerification` 本轮复跑仍绿）。

### 已有密码认证未被放松

10 首次 `/tmp/ApiRelayCodexW5DirectFix.xcresult` 独立读取：142 项中 141 通过、1 失败，失败为 `SecureBackupTests/testBackupPassphraseManagementUsesCurrentPolicy`：`master_password_not_set` ≠ 期望的 `master_password_prompt_required`。现测试在仅应用密码档先 `setAppPasswordMaterialSet(true)`，仍断言未提交口令要 prompt、提交后走 `confirmWithMasterPassword`。本轮该用例通过。没有把缺材料改成可直接确认。

### 中文用词 / 提示键

现行 `zh-Hans` value 中搜不到「主密码」。`appLock.combination.notSet` / `hint`、`appLock.useAppPassword`、`settings.appPassword.recover`、`settings.weakenConfirm.appPassword.*` 键存在且中文为应用密码/设备验证恢复语义。内部 `MasterPassword` 符号与键名未要求改。

英文仍有用户可见残留：`vault.masterPassword.title` = `Enter Master Password`（锁屏/口令标题在用）；若干 `stale` 键仍写 Master Password。10 所称「英文对应名称同步修正」不完整。不构成 `05` D 中文阻塞，也不把丢失前全部历史译句伪称为已逐字恢复。

## 3. 证据

Codex 自测最终包（独立读取摘要，非转述）：

```text
/tmp/ApiRelayCodexW5DirectFixFinal.xcresult
iPhone 17 Pro / iOS 26.5 模拟器
142 passed, 0 failed, 0 skipped
含本波新增：testMasterOnlyMissingMaterialOffersRecoveryWithoutBusinessRetry
testBackupMasterOnlyMissingMaterialIsNotPasswordPrompt
以及 09 的三条 ordinary* 用例
```

首次失败包保留且与 10 描述一致：`/tmp/ApiRelayCodexW5DirectFix.xcresult`（141/1，上列 SecureBackup 用例）。

本轮独立复跑（`-derivedDataPath /tmp/ApiRelayAgentDD`，本地签名，同一模拟器）：

```text
/tmp/ApiRelayU2W5-11.xcresult
39 passed, 0 failed, 0 skipped
RevealGateCoordinatorTests 18
SecureBackupTests 18
AppPrivacyControllerTests 3（锁屏不写密 + 恢复不落 none + persist 失败保持锁）
** TEST SUCCEEDED **
```

`git diff --check` 对 10 五文件退出 0。未重跑无关全量，未重读旧对话。W3/10 独立通过仍作 W3 关闭与恢复锁态引用，不重新审核 W3/09。

## 4. 未验证 / 残差（不把本复核升级成三端验收）

- 三端导航、系统弹窗、分栏/多窗、双设备 CloudKit、旧 W6/02 B1–B3、工程 manifest：U2-W6。
- 设置页仅应用密码档降低/清空：组合档显式入口已拒绝；仅应用密码档仍可能先出口令框，确认失败才停。0 设密、0 写入，恢复走 W3 管理行。不是 10 五文件范围，不在本只读复核中改代码。
- 备份 SwiftUI 五处靠现场回调核对；没有单独把五个 View 再各跑一遍 UI 驱动测试。
- `SettingsView.combinationNeedsSetup` 从未置 true，相关 finish 分支是死防御，活路径是 `beginSettingsCombinationPassword`。
- 独立复核通过不等于三端最终验收，也不等于上传授权。

## 5. 方法观察

用户允许同阶段直接修复后，10 必须保留真实失败包，11 只独立核对补丁与现有 09，不能让 Codex 自签。翻译文件被整文件回退后，不能只证明「键还在」，必须读实际中英文 value。不为英文残留或设置页口令框体验在只读复核里扩大整改。

下一步负责人：Grok
是否需要用户批准：否
下一步：执行 `/Users/xitongzhili/Desktop/MacTransfer/08_Code/E02_ApiRelay_Github/ZL02_研发档案/第一阶段-密钥库/调整与优化/v1.13.9-身份验证四档与主密码调整/提示词/阶段4-Grok执行下一波.md`（只 W6 证据/验收准备，不自动执行、不上传）

波次审计通过，可以进入下一波。

写入状态：已停止
