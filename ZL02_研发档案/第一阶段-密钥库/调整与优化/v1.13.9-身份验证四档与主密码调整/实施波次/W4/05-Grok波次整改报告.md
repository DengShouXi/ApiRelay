# 阶段4：Grok波次整改报告（W4）

写入状态：未停止

- 阶段：4
- 波次：W4（只修 `04-Codex波次复验报告.md` 的剩余 W4-B02；未进入 W5）
- 报告文件：`实施波次/W4/05-Grok波次整改报告.md`（未覆盖 `01`–`04`）
- 时间：2026-09-15
- 分支：`v1.13.9`
- HEAD：`6ec5ff7c67547637bbd55f528276422395e28c03`
- 方法版本：`MAIC-1.3`
- 工作包：`ZL02_研发档案/第一阶段-密钥库/调整与优化/v1.13.9-身份验证四档与主密码调整/`
- 输入：用户已批准的 W4 修订版 `04-最终执行计划.md`、`05-最终检查计划.md`、`00C-任务契约.json`、`实施波次/W4/04-Codex波次复验报告.md`
- 实际授权：用户明确执行 `提示词/阶段4-Grok执行下一波.md`。W4/04 `失败类型：普通整改`，按阶段4只修该报告列出的本波阻塞。

文末 `写入状态：已停止` 为交接用最终状态。

## 1. 入口核对

- 当前分支 `v1.13.9`，HEAD 仍为契约基线。暂存区空；单一 worktree。
- `main` / `origin/main` = `539447ea9984608c74989da48b8770cb3fe32a6c`；`release/1.0.0` = `5c5eed3f8390f51f5a26be9737bcc11f72e7d7fd`。
- 上一写入者：W4/04 已停止。本报告为该波下一个奇数号 `05`。
- 未读取、未修改计划外文件。未实现 W5 取用复用或组合档按钮。未改 `Localizable.xcstrings`。

## 2. 阻塞关闭

W4/04 剩余 **W4-B02**：备份口令管理缺少会话锁闸门。

`BackupCurrentPolicyAuth.confirm` 在加载偏好和调用 `confirm` / `confirmWithMasterPassword` **之前**检查 `environment.appPrivacy.session.isSessionLocked`；已锁定则抛 `sessionLocked`。保存、复制、清除都先走这个帮助器，因此锁定时不会弹身份框，也不会读写/清除备份口令或写剪贴板。

界面把确认后的写入收到 `BackupPassphraseSensitiveOps.perform`，测试直接驱动同一入口。

## 3. 本波实际修改（均在修订后 W4 清单内）

| 文件 | 做什么 |
| --- | --- |
| `UI/Settings/BackupSettingsViews.swift` | 会话锁先拒绝；保存/复制/清除共用 `BackupPassphraseSensitiveOps` |
| `ApiRelayTests/.../SecureBackupTests.swift` | 保存/复制/清除锁定态零副作用；复制取消零副作用 |

## 4. 操作 × 证据映射（本轮补齐的格子）

| 格子 | 测试 | 生产路径 |
| --- | --- | --- |
| 备份口令保存 · 会话锁 | `testBackupPassphraseSaveCopyClearSessionLockHasZeroSideEffects` `save` | `BackupPassphraseSensitiveOps.perform(.save)` → `BackupCurrentPolicyAuth.confirm` |
| 备份口令复制 · 会话锁 | 同上 `copy` | `.copy` |
| 备份口令清除 · 会话锁 | 同上 `clear` | `.clear` |
| 备份口令复制 · 身份取消零副作用 | `testBackupPassphraseCopyCancelLeavesPassphraseAndClipboardUntouched` | `.copy` 在设备档取消 `confirm` |
| 备份口令当前方式路由（既有） | `testBackupPassphraseManagementUsesCurrentPolicy` | 仅证明未锁定时的档位路由，不代替锁定态 |

锁定态断言：`confirm` / `confirmMandatory` / `confirmWithMasterPassword` 次数不增加；`set` / `plaintext` / `clear` / 剪贴板 `write` 次数不增加；已有口令仍在；剪贴板仍空。

## 5. 测试

```text
bash ApiRelay/scripts/selfcheck.sh
```

```text
════════════════════════════════════════════════════
 ApiRelay 项目自检    2026-09-15 09:20
 目录：.../ApiRelay
════════════════════════════════════════════════════
【红线 1】测试是否绕过 KeychainStore.makeForTests()
  ✓ 通过
 红线检查：全部通过
════════════════════════════════════════════════════
```

`git diff --check` 对本波文件退出 0。

```text
xcodebuild test -scheme ApiRelay \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -derivedDataPath /tmp/ApiRelayAgentDD \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=YES CODE_SIGNING_REQUIRED=YES \
  -only-testing:ApiRelayTests/KeyVaultServiceTests \
  -only-testing:ApiRelayTests/RecentlyDeletedBatchTests \
  -only-testing:ApiRelayTests/ConsumerToolSessionLockTests \
  -only-testing:ApiRelayTests/DataLifecycleTests \
  -only-testing:ApiRelayTests/SecureBackupTests
```

**TEST SUCCEEDED**：68 tests, 0 failures（KeyVaultService 31 + RecentlyDeletedBatch 11 + ConsumerToolSessionLock 4 + DataLifecycle 7 + SecureBackup 15）。相对 W4/04 的 66 项，本轮新增 2 项。

xcresult：`/tmp/ApiRelayAgentDD/Logs/Test/Test-ApiRelay-2026.09.15_09-16-59-+0800.xcresult`。

未跑共享 scheme 全量测试（属 W6）。

## 6. 收尾四问

1. **外部资源**：本轮只读会话锁标志，不写 Keychain / SwiftData / CloudKit。备份口令测试用 `FakeBackupPassphrase` 与 `FakeClipboard`；偏好用 `FakePreferences` 内存 DTO。锁定态用 `launchAppLockEnabled` 注入，测试前后 `AppLockLaunchCache.resetForTests()`，避免污染其它套件。
2. **失败路径**：会话已锁时用户点保存/复制/清除会得到 `sessionLocked`，不弹身份框、不改口令、不写剪贴板。身份取消时口令仍在、剪贴板仍空。其它错误仍走原失败提示。
3. **接缝**：`BackupPassphraseSensitiveOps` 与 `BackupCurrentPolicyAuth` 可在测试中直接驱动；门闩、口令、剪贴板均为 Fake，不必碰生产 Keychain。
4. **文件粒度**：`BackupSettingsViews.swift` 763 行，已超过 400 行。本波不拆。

## 7. 未验证项

- 真机 Face ID / Touch ID、三端手测、共享 scheme 全量（W6）。
- 组合档显式「使用应用密码」与取用授权复用（W5）。
- 未把每个共享路由错误码再复制到备份口令入口；本轮按 W4/04 停止点只补锁定态与一条取消零副作用。

## 8. 方法观察

共享认证帮助器若只接当前验证方式、不接会话锁，所有调用它的界面会一起绕过业务锁。锁定态必须作为身份调用之前的固定前置，不能靠页面是否还挂着来推断。

下一步负责人：Codex
是否需要用户批准：否
下一步：执行 `/Users/xitongzhili/Desktop/MacTransfer/08_Code/E02_ApiRelay_Github/ZL02_研发档案/第一阶段-密钥库/调整与优化/v1.13.9-身份验证四档与主密码调整/提示词/阶段4A-Codex波次审计.md`

写入状态：已停止
