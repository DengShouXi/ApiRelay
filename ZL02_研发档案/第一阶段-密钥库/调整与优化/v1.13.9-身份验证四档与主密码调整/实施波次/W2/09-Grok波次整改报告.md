# 阶段4：Grok波次整改报告（U2-W2 第三轮）

写入状态：未停止

- 阶段：4
- 修订ID：U2
- 波次：U2-W2（整改 W2/08 B01：版本比较与删除仍非同一原子动作）
- 时间：2026-09-15
- 分支：`v1.13.9`
- HEAD：`6ec5ff7c67547637bbd55f528276422395e28c03`
- 方法版本：`MAIC-1.3`
- 工作包：`ZL02_研发档案/第一阶段-密钥库/调整与优化/v1.13.9-身份验证四档与主密码调整/`
- 输入：U2 版 `04` 第八节、`05` 第十二节、`00C`、W2/07、W2/08-Codex波次复验报告、当前引擎源码
- 批准来源：W0/07 记录 2026-09-15 用户原文「同意 U2 执行计划和检查计划」。本波未要求重复批准。
- 实际授权：U2-W2/08 普通整改失败，只修本波 B01；不进 U2-W3；不覆盖旧 W2/01–08；不处理 `tools/`、xcodeproj、暂存、提交、上传。
- 保护 refs（未改）：`main` / `origin/main` = `539447ea9984608c74989da48b8770cb3fe32a6c`；`release/1.0.0` = `5c5eed3f8390f51f5a26be9737bcc11f72e7d7fd`
- 暂存区：空；单一 worktree

文末 `写入状态：已停止` 为交接用最终状态。

## 1. 入口核对

- 当前分支 `v1.13.9`，HEAD 仍为契约基线。
- U2-W0/08 通过；U2-W2/08 不通过（B01 普通整改）。最早待办仍是 W2，下一个奇数报告为本文件 `09`，配对将来是 `10`。
- 上一写入者：W2/08 已停止。未读取、未修改 `tools/`。未改锁屏 `AppPrivacyController.swift`（属 U2-W3）。

## 2. 针对 B01 的实际修改（均在 U2-W2 允许清单 ∩ `00C` 内）

| 文件 | 做什么 |
| --- | --- |
| `MasterPasswordService.swift` | 保留无参 `reset()` 给测试清理与锁屏旧入口（**不宣称它有版本保护**）。新增 `reset(expectedRevision:)`：在 `mutateMaterial` 同一排他提交里核对版本再删。新增 `withUnchangedSetMaterial`：占住排他权、核对版本且材料为已设，执行 persist，**不递增 revision**。未改 PBKDF2 / KeychainStore / rawValue。未新增文件。 |
| `RevealGateServing.swift` | 产品恢复改走 `resetIfRevision` + `snapshotRevision`：persist 后**不再**额外读 revision，把开始版本交给材料服务。创建/已设 persist 增加 `commitPersist(policy, revision)`。旧 `resetMaterial` 重载保留给锁屏编译，不是新的静默绕过入口。 |
| `AppEnvironment.swift` | `resetAppPasswordAndFallToDeviceAuth` 接 `master.reset(expectedRevision:)`。创建/已设切档的 persist 包在 `withUnchangedSetMaterial` 内。 |
| `FakeMasterPassword.swift` | 同步条件删除与 lease。`setBeforeExclusiveResetHook` 在取得材料变更排他权**之前**运行（可重入 `changePassword`）。`setDuringLeaseHook` 在持锁期间注入。 |
| `RevealGateTests.swift` / `MasterPasswordServiceTests.swift` / `SecurityReviewTests.swift` | 覆盖最后一次版本读取完成后、reset 真正取得排他权前的变更；真实 `MasterPasswordService` 与环境接缝；两种密码依赖目标。 |

本波未改：`ApiRelayError.swift`、`FakeSupport.swift`、`SessionLockQuerying.swift`、`RevealGate.swift`、设置页/锁屏/Vault 普通入口。未新增生产或测试文件。

## 3. 生产调用链（本轮关闭的缺口）

W2/08 指出：persist 之后再 `await materialRevision()` 比较，然后另一次 `await reset()`，比较与删除不是同一排他提交。最后一次查询读到旧版本后，另一请求可 `changePassword` 再被旧恢复删掉。

关闭方式：

1. 恢复：`resetAppPasswordAndFallToDeviceAuth` → 确认后 persist 设备验证 → `reset(expectedRevision: 开始版本)`。版本核对与删除在 `mutationInFlight` 同一提交内。不匹配/忙碌抛 `stale_concurrent`，**不删他人新材料**。设备策略可能已保存，这是部分成功，如实上抛。
2. 创建/已设切档：最后一次材料版本读取后，persist 在 `withUnchangedSetMaterial` 持锁区内完成。持锁期间 `reset(expectedRevision:)` 因 inFlight 拒绝。材料若已被恢复删掉或版本已变，拒绝保存密码依赖档。
3. 无参 `reset()` 仍无版本条件。锁屏 `AppPrivacyController.recoverFromLostMasterPassword` 仍走旧 `resetMaterial` + 默认 `revision=0`。**不得声称锁屏恢复已有版本保护**。U2-W3 必须接同一 `reset(expectedRevision:)`。

## 4. 测试证据

iPhone 17 Pro 模拟器，iOS 26.5，DerivedData `/tmp/ApiRelayAgentDD`，签名保留：

```text
RevealGateTests 52
MasterPasswordServiceTests 15
SecurityReviewTests 11
CatalystAdaptationTests 4
合计 82 passed / 0 failed
xcresult: /tmp/ApiRelayAgentDD/Logs/Test/Test-ApiRelay-2026.09.15_16-00-09-+0800.xcresult
```

本轮针对 W2/08 窗口新增/改写：

- `testResetExpectedRevisionDoesNotDeleteAfterLaterChange`（真实 `MasterPasswordService`：先改密再按旧版本 reset，新材料保留）
- `testSetMaterialLeaseBlocksResetInsideCommit`（真实服务：lease 持锁期内 reset 被拒，材料与 revision 不变）
- `testRecoverSkipsResetWhenRevisionChangesDuringPersist`（改走 `resetIfRevision`；persist 期间改密后仍会调用条件删除，但删除被拒）
- `testRecoverDoesNotDeleteWhenMaterialChangesBeforeExclusiveReset`（环境接缝：最后一次 revision 读取且 persist 完成后、取得排他权前改密；新材料保留；设备档可能已 persist，抛 `stale_concurrent`，未落到不验证）
- `testPersistExistingLeaseBlocksResetDuringCommit` / `testCreateLeaseBlocksResetDuringCommit`（两种目标：`.masterPassword`、`.biometryOrAppPassword`）
- `testRecoveryCommitUsesExpectedRevisionOnRealKeychain`（真实 Keychain + 协调器：persist 回调里改密，条件删除失败，新材料保留）

失败/取消路径：取消与写失败仍零业务副作用。部分成功（设备策略已保存、材料因过期未删）由 `stale_concurrent` 上抛，测试断言新密码仍可校验。

`git diff --check` 对本波文件通过。

```text
bash ApiRelay/scripts/selfcheck.sh
红线检查：全部通过
```

未重跑全量。旧 `SecurityPolicyChangeTests` 组合档缺材料断言仍属 U2-W3。本波模拟器结果不是电脑/平板运行证据。未声称锁屏恢复已有版本保护。

## 5. 收尾四问

1. **外部资源：** 应用密码材料仍只在本机 `.masterpw`。真实服务测试用 `KeychainStore.makeForTests()`；环境接缝用内存 `FakeMasterPassword`。条件删除与无参删除都只清 `.masterpw`，不得碰 `.keys` / `.admin` / `.backuppw`。未打开 `xcodecloud/manifest.json`。
2. **失败路径：** 预期版本已变或材料变更进行中 → `stale_concurrent`，不删新材料。lease 期间恢复删除被拒，切档 persist 可完成且材料仍在。恢复 persist 已成功但删除因过期失败：设备验证档可能已保存，调用方看到错误而不是“已全部恢复”；材料仍是别人新写的。取消/写失败/persist 失败仍不提前改档、不落到不验证。锁屏旧入口仍无此保护。
3. **接缝：** `MasterPasswordServing` 仍有 `FakeMasterPassword`。新接口由假实现与真实 `MasterPasswordService` 同时覆盖。测试注入点是“最后观察与真正取得排他权之间”，不是只测协调器前半段。
4. **文件粒度：** `RevealGateTests.swift` 现 1113 行，已超过 400。本波只加测试，不拆文件。`MasterPasswordService.swift` 300 行、`RevealGateServing.swift` 248 行，未超。

## 6. 未验证 / 停止点

- 设置页、锁屏 revision 接线、选档导航：U2-W3。
- 普通入口去掉延迟设密：U2-W5。
- 三端手测、双设备、旧验收阻塞、工程 manifest：U2-W6。

## 7. 方法观察

W2/08 的有效证据是“最后一次版本读取完成之后、删除提交取得排他权之前”仍能写新材料。只再加一次外部 `materialRevision()` 不够。本轮把条件删除放进材料服务同一排他提交，并用 Fake 在取得排他权之前注入改密；真实服务用 persist 回调里改密覆盖同一窗口。测试闭包必须先 `let service = sut!`，不能把 XCTestCase 捕获进 `@Sendable`。

下一步负责人：Codex
是否需要用户批准：否
下一步：执行 `/Users/xitongzhili/Desktop/MacTransfer/08_Code/E02_ApiRelay_Github/ZL02_研发档案/第一阶段-密钥库/调整与优化/v1.13.9-身份验证四档与主密码调整/提示词/阶段4A-Codex波次审计.md`

写入状态：已停止
