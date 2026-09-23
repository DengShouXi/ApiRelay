# 阶段4：Grok波次整改报告（U2-W2）

写入状态：未停止

- 阶段：4
- 修订ID：U2
- 波次：U2-W2（整改 W2/06 B01：验证等待后的材料检查过期）
- 时间：2026-09-15
- 分支：`v1.13.9`
- HEAD：`6ec5ff7c67547637bbd55f528276422395e28c03`
- 方法版本：`MAIC-1.3`
- 工作包：`ZL02_研发档案/第一阶段-密钥库/调整与优化/v1.13.9-身份验证四档与主密码调整/`
- 输入：U2 版 `04` 第八节、`05` 第十二节、`00C`、W2/05、W2/06-Codex波次复验报告、当前引擎源码
- 批准来源：W0/07 记录 2026-09-15 用户原文「同意 U2 执行计划和检查计划」。本波未要求重复批准。
- 实际授权：U2-W2/06 普通整改失败，只修本波 B01；不进 U2-W3；不覆盖旧 W2/01–06；不处理 `tools/`、xcodeproj、暂存、提交、上传。
- 保护 refs（未改）：`main` / `origin/main` = `539447ea9984608c74989da48b8770cb3fe32a6c`；`release/1.0.0` = `5c5eed3f8390f51f5a26be9737bcc11f72e7d7fd`
- 暂存区：空；单一 worktree

文末 `写入状态：已停止` 为交接用最终状态。

## 1. 入口核对

- 当前分支 `v1.13.9`，HEAD 仍为契约基线。
- U2-W0/08 通过；U2-W2/06 不通过（B01 普通整改）。最早待办仍是 W2，下一个奇数报告为本文件 `07`，配对将来是 `08`。
- 上一写入者：W2/06 已停止。未读取、未修改 `tools/`。

## 2. 针对 B01 的实际修改（均在 U2-W2 允许清单 ∩ `00C` 内）

| 文件 | 做什么 |
| --- | --- |
| `MasterPasswordService.swift` | `setPassword` 仅未设可写；已设/不可读拒绝覆盖。同 actor 材料变更加 `mutationInFlight`。`materialRevision` 在成功写入/删除后递增。`changePassword` 仍校验旧密码后覆盖。未改 PBKDF2 / KeychainStore。 |
| `RevealGateServing.swift` | `AppPasswordSetup` 每个 await 后重读共享材料状态；创建仍未设才写，已设 persist 仍须 `.set`。`AppPasswordRecovery` 在确认后、persist 后对照 revision，过期不删别人新写的材料。 |
| `AppEnvironment.swift` | 恢复入口传入 `master.materialRevision()`。创建/已设 persist 仍走上述协调器。 |
| `FakeMasterPassword.swift` / `FakeRevealGate.swift` | 同步 CAS、revision、状态覆盖、`confirmMandatory` 钩子供并发注入 |
| `RevealGateTests.swift` / `MasterPasswordServiceTests.swift` / `SecurityReviewTests.swift` | 生产接缝与真实 Keychain 协调器并发测试 |

本波未改：`ApiRelayError.swift`、`FakeSupport.swift`、`SessionLockQuerying.swift`、设置页/锁屏/Vault 普通入口。

## 3. 生产调用链（B01）

1. 创建：`AppEnvironment.createAppPasswordMaterialThenPersist` → `AppPasswordSetup.createMaterialThenPersistTarget`（确认当前方式 → 设备主人 → **重读未设** → `MasterPasswordService.setPassword` CAS）→ persist 原目标。
2. 已设切档：`persistPasswordDependentPolicyKeepingMaterial` → 确认后 **重读仍为已设** 才 persist；期间恢复/删除则拒绝 persist。
3. 恢复：`resetAppPasswordAndFallToDeviceAuth` → 确认后 revision 未变才 persist 设备验证，再 `reset`。确认或 persist 期间 revision 变了：不删新材料，抛 `stale_concurrent`。

锁屏 `AppPrivacyController.recoverFromLostMasterPassword` 仍走同一 `recoverToDeviceAuth` 默认 `revision=0`（该文件属 U2-W3）。本波引擎入口已接线；锁屏接 revision 留给 U2-W3。

## 4. 测试证据

iPhone 17 Pro 模拟器，iOS 26.5，DerivedData `/tmp/ApiRelayAgentDD`，签名保留：

```text
RevealGateTests 49
MasterPasswordServiceTests 13
SecurityReviewTests 10
CatalystAdaptationTests 4
合计 76 passed / 0 failed
xcresult: /tmp/ApiRelayAgentDD/Logs/Test/Test-ApiRelay-2026.09.15_15-22-54-+0800.xcresult
```

B01 相关测试名：

- `testCreateRejectsWhenOtherWindowSetsDuringCurrentConfirm`（两种目标）
- `testCreateRejectsWhenOtherWindowSetsDuringDeviceOwner`
- `testCreateRejectsWhenMaterialBecomesUnreadableDuringConfirm`
- `testCreateCancelLeavesMaterialAndPolicyUnchanged`
- `testCreateWriteFailureDoesNotPersist`
- `testPersistExistingAbortsWhenMaterialRemovedDuringConfirm`（两种目标）
- `testPersistExistingAbortsWhenMaterialBecomesUnreadable`
- `testConcurrentCreatesDoNotOverwriteOrDoublePersist`
- `testRecoverDoesNotDeleteNewerMaterialFromOtherWindow`
- `testRecoverSkipsResetWhenRevisionChangesDuringPersist`
- `testSetPasswordDoesNotOverwriteExistingMaterial`
- `testSetPasswordDoesNotWriteWhenMaterialUnreadable`
- `testConcurrentSetPasswordDoesNotLeaveMixedMaterial`
- `testCreateCoordinatorDoesNotOverwriteWhenOtherWindowSetsDuringConfirm`（真实 `MasterPasswordService` + 协调器）

`git diff --check` 对本波文件通过。

```text
bash ApiRelay/scripts/selfcheck.sh
红线检查：全部通过
```

未重跑全量。旧 `SecurityPolicyChangeTests` 组合档缺材料断言仍属 U2-W3。

## 5. 收尾四问

1. **外部资源：** 应用密码材料仍只在本机 `.masterpw`。测试用 `KeychainStore.makeForTests()`、内存 `FakeMasterPassword`。恢复仍不得碰 `.keys` / `.admin` / `.backuppw`。未打开 `xcodecloud/manifest.json`。
2. **失败路径：** 等待期间别人已设 → `already_set`，不覆盖、不切档。变为不可读 → `material_unreadable`，不写。已设切档时材料被恢复删掉 → 不 persist 密码档。恢复过期 → `stale_concurrent`，保留别人新材料。取消/写失败/persist 失败仍不提前改档。
3. **接缝：** 协调器、`setPassword` CAS、`materialRevision`、环境创建/切档/恢复均有假实现或真实钥匙串测试。测试调用实际协调器与共享 `FakeMasterPassword` / `MasterPasswordService`，不用局部状态变量冒充提交边界。
4. **文件粒度：** `RevealGateTests.swift` 现约 1030 行，已超过 400。本波只加测试，不拆文件。

## 6. 未验证 / 停止点

- 设置页、锁屏 revision 接线、选档导航：U2-W3。
- 普通入口去掉延迟设密：U2-W5。
- 三端手测、双设备、旧验收阻塞、工程 manifest：U2-W6。本波模拟器测试不是电脑/平板运行证据。

## 7. 方法观察

B01 的有效证据是 await 期间共享材料被另一请求改写，不是串行成功顺序。整改同时做协调器重读、钥匙串 CAS 和 revision，避免只在 UI 再查一次。测试里 `XCTAssert*` 不能包 `await`，否则本工程警告当错误。

下一步负责人：Codex
是否需要用户批准：否
下一步：执行 `/Users/xitongzhili/Desktop/MacTransfer/08_Code/E02_ApiRelay_Github/ZL02_研发档案/第一阶段-密钥库/调整与优化/v1.13.9-身份验证四档与主密码调整/提示词/阶段4A-Codex波次审计.md`

写入状态：已停止
