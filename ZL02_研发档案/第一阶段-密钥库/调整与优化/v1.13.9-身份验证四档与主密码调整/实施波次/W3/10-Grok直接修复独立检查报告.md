写入状态：未停止

# 阶段4A：Grok直接修复独立检查（U2-W3 / U2-R1）

- 阶段：4A（Codex 直接修复后的独立只读复核，不是执行者自测）
- 修订ID：U2
- 计划修订：U2-R1
- 波次：W3
- 时间：2026-09-15
- 分支：`v1.13.9`
- HEAD：`6ec5ff7c67547637bbd55f528276422395e28c03`
- 方法版本：`MAIC-1.3`
- 输入：`00C`、`04` 第八节第五小节、`05` 第十二节 F、W3/08、W3/09 及 09 列出的三份实际文件
- 实际授权：用户调用 `提示词/阶段4D-Grok直接修复后独立检查.md`。只读检查，不修改被审对象，不提交、不上传。09 已停止后才开始。
- 保护 refs（未改）：`main` / `origin/main` = `539447ea9984608c74989da48b8770cb3fe32a6c`；`release/1.0.0` 对象 = `5c5eed3f8390f51f5a26be9737bcc11f72e7d7fd`
- 暂存区：空；单一 worktree；本轮未改实现/测试/规格/`tools/`
- 写入状态：已停止（文末再次标明）

## 1. 入口与 09 范围诚实性

- W3/09 文末 `写入状态：已停止`。01—09 连续，开始时不存在 10，本文件新建不覆盖。
- 09 实际文件：`UserPreferencesRepository.swift`、`PreferencesService.swift`、`PreferencesServiceTests.swift`。09 写明仓库文件是用户「直接修复」下的必要依赖，**不伪称**原 U2-R1 精确新增清单已经包含它。`00C.allowedModify` 含该仓库路径（W1 文件），但 U2-R1 第五小节原先只批到 `PreferencesService` 队列接缝。本检查按 09 记录的直接修复授权核对，不把仓库改动改写成「原清单已覆盖」。
- 保证边界与 09 一致：同一 `@ModelActor` 仓库实例内的本机条件提交；**不是** CloudKit 跨设备事务，也不是全局多进程 CAS。

## 2. 条件比较 / apply / save 之间无 await

`UserPreferencesRepository.update(_:expectedCurrentPolicy:)` 是同步 `throws`，不是 `async`：

1. `fetchSingletons()`
2. 若带 `expectedCurrentPolicy`，按现行 `SyncedIdentity.winner` 比较规范策略，不匹配则 `stale_page_request`
3. 空集合则 insert
4. `apply` 打补丁
5. `modelContext.save()`

该函数体内无 `await`。服务层 `PreferencesService.update(_:expectedCurrentPolicy:)` 把期望策略传到 `userRepo.update`；公开 `update(_ patch:)` 仍传 `nil`，默认无条件路径兼容。`persist` 里服务层 `load` 只作尽早拒绝，注释与代码均写明不是最终提交依据。

## 3. 08 反例窗口

08 独立验证：最后一次授权回调里另一请求先 `update` 为 `noVerification`，旧目标仍凭有效页面许可无条件写入。现生产路径在仓库同步操作内再次核对 `expectedCurrentPolicy`。`testPolicyChangedAfterServiceCheckCannotBeOverwritten` 对 `.masterPassword` 与 `.biometryOrAppPassword` 两种目标注入同一窗口，断言拒绝 `stale_page_request` 且最终策略仍为 `noVerification`。

## 4. 证据

Codex 自测 xcresult（独立读取，非转述）：

```text
/tmp/ApiRelayCodexDirectW3Fix.xcresult
iPhone 17 Pro / iOS 26.5 模拟器
145 passed, 0 failed, 0 skipped
含 testPolicyChangedAfterServiceCheckCannotBeOverwritten Passed
```

本轮独立复跑（`-derivedDataPath /tmp/ApiRelayAgentDD`，本地签名）：

```text
/tmp/ApiRelayAgentDD/Logs/Test/Test-ApiRelay-2026.09.15_18-44-45-+0800.xcresult
PreferencesServiceTests 13 passed（含新增关键用例及默认 update/连拨/隔离回归）

/tmp/ApiRelayAgentDD/Logs/Test/Test-ApiRelay-2026.09.15_18-45-29-+0800.xcresult
MasterPasswordServiceTests + AppPrivacyControllerTests + RevealGateTests + SecuritySettingsPersistTests
132 passed, 0 failed
```

W2 材料：`testResetExpectedRevisionDoesNotDeleteAfterLaterChange`、`testSetPasswordDoesNotOverwriteExistingMaterial`、`testRecoverDoesNotDeleteNewerMaterialFromOtherWindow` 仍绿。恢复锁态：`recoverFromLostMasterPassword` 仍走 `applyRecoveryOutcomeKeepingLock`，不调用 `finishUnlockSucceeded`；`testForgotMasterPasswordKeepsLockWhenPersistFails` / `DoesNotFallToNoVerification` 仍绿。`git diff --check` 对 09 三文件通过。

## 5. 未验证

- 三端导航、系统弹窗、分栏/多窗手测、双设备 CloudKit：U2-W6。
- 普通入口延迟设密：U2-W5，尚未开始。
- 工程 manifest / `tools/`：未读、未处理。
- 独立复核通过不等于三端最终验收，也不等于上传授权。

## 6. 方法观察

用户改由 Codex 直接修 08 证实缺口后，独立检查应核对仓库同步提交边界和原反例测试，而不是再开一轮 Grok 09 去重复同一修复。必要依赖一次写进 09，本报告只确认记录属实。不为「还能更好」扩大整改。

下一步负责人：Grok
是否需要用户批准：否
下一步：执行 `/Users/xitongzhili/Desktop/MacTransfer/08_Code/E02_ApiRelay_Github/ZL02_研发档案/第一阶段-密钥库/调整与优化/v1.13.9-身份验证四档与主密码调整/提示词/阶段4-Grok执行下一波.md`（本次 W5，不自动执行）

波次审计通过，可以进入下一波。

写入状态：已停止
