# 阶段4：Grok实施报告（W4）

写入状态：未停止

- 阶段：4
- 波次：W4（敏感操作门闩与破坏性确认）
- 时间：2026-09-15
- 分支：`v1.13.9`
- HEAD：`6ec5ff7c67547637bbd55f528276422395e28c03`
- 方法版本：`MAIC-1.3`
- 工作包：`ZL02_研发档案/第一阶段-密钥库/调整与优化/v1.13.9-身份验证四档与主密码调整/`
- 输入：经用户批准的修订版 `04-最终执行计划.md`、`05-最终检查计划.md`、`00C-任务契约.json`、`实施波次/W3/02-Codex波次审计报告.md`
- 实际授权：用户明确执行 `提示词/阶段4-Grok执行下一波.md`。W0–W3 已通过；W3/02 文末写明可进入下一波。`04`/`05` 文首仍留有阶段 3 的「等待批准」字样，但 W1/04 与 W2/04 已记录用户批准修订版；本波按该授权只实施 W4，未改 `04`/`05`。

文末 `写入状态：已停止` 为交接用最终状态。

## 1. 入口核对

- 当前分支 `v1.13.9`，HEAD 仍为契约基线 `6ec5ff7c67547637bbd55f528276422395e28c03`。
- 暂存区空；单一 worktree；未提交、未上传、未换分支。
- `main` / `origin/main` = `539447ea9984608c74989da48b8770cb3fe32a6c`；`release/1.0.0` = `5c5eed3f8390f51f5a26be9737bcc11f72e7d7fd`。
- 上一写入者：W3/02 已停止且通过。本波创建前不存在 `实施波次/W4/`。
- 未读取、未修改 `tools/`。未改 `AppEnvironment.swift`、`SessionLockQuerying.swift`、`RevealGate.swift`、`Localizable.xcstrings`、`SettingsView.swift`。

## 2. 本波实际修改（均在 W4 精确清单内）

| 文件 | 做什么 |
| --- | --- |
| `Business/Vault/KeyVaultServing.swift` | 敏感写接口增加 `appPassword:`；1 参扩展保持旧调用；新增 `currentRevealPolicy()`。 |
| `Business/Vault/KeyVaultService.swift` | 编辑/回收站/恢复/永久删除走 `CurrentRevealPolicyAuth`；创建与头像-only patch 跳过身份；查看/复制只看 `revealAuthEnabled`；会话锁先于门闩。 |
| `Business/Vault/RecentlyDeletedBatchService.swift` | 批量恢复/永久删除先会话锁，再按 `vault.currentRevealPolicy()` 只验一次，再写本批。 |
| `Business/Vault/ConsumerToolService.swift` | 改名等敏感 patch 走当前方式；头像-only 跳过；删除/恢复/永久删除同口径。 |
| `Business/System/SecureBackupService.swift` | 导出/导入改当前方式，不再 `confirmMandatory`。 |
| `Business/System/DataLifecycleService.swift` | 清空改当前方式；会话锁先拒绝。 |
| `UI/Vault/VaultHomeViewModel.swift` | 敏感写失败若需应用密码则记下重试闭包，弹出既有主密码采集。 |
| `UI/Vault/VaultHomeView.swift` | 移入回收站本页确认；回收站单条永久删除补独立确认框（复用既有批量文案键）；主密码 sheet 接到 ViewModel 重试。 |
| `UI/Vault/KeyDetailView.swift` | 浏览态改头像走 `updateKeyAvatar`，不进编辑门闩。 |
| `UI/Settings/BackupSettingsViews.swift` | 备份口令设/拷/清在 UI 用当前方式；导出/导入把门闩留在服务以免连弹两次；应用密码档用既有 weaken 文案采集口令后重试。 |
| 五个 Fake | 协议签名跟上；`FakeKeyVault.currentRevealPolicy()` 可记录调用。 |
| 五份测试 | 见第 4 节。 |

未改但属 W4 允许且无需动：无。`FakeRevealGate` 不在本波清单，未改；测试把 `journal` 拷出 actor 再断言。

## 3. 停止点对照

- 新增账号/密钥/使用方仍直达，不验身份。
- 头像-only 的密钥 patch、使用方 patch 不验身份；改名/备注等敏感字段走当前方式。
- `revealAuthEnabled=false` 只关掉查看/复制；删除等固定门闩仍按当前档确认。
- 不验证：服务层不弹身份；单条永久删除与清空仍先有 UI 破坏性确认。
- 设备验证与组合档走 `confirm`，不走 `confirmMandatory`；应用密码档无口令时抛 `master_password_prompt_required`，不改数据。
- 回收站批量：额度预检（恢复）→ 一次当前方式 → 只处理本批；取消则零写入。
- 永久删除/清空顺序：UI 破坏性确认 → 服务层当前方式。会话已锁时业务入口先拒绝，日记无 `confirm`。
- 管理凭证合同仍只在既有 `AppEnvironment` / `AppPrivacyController` 使用 `confirmMandatory`；本波未改那些文件，也未做 V2 界面。
- 未实现同详情取用授权复用（W5）。组合档「使用应用密码」按钮仍留 W5。
- `SettingsView` 不在本波清单：清空的破坏性确认框仍在设置页；应用密码档下清空若未带口令，服务会抛错，设置页目前只显示错误文案，不采集口令。

## 4. 测试

```text
bash ApiRelay/scripts/selfcheck.sh
```

红线通过。`git diff --check` 对本波文件退出 0。

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

**TEST SUCCEEDED**：55 tests, 0 failures（KeyVaultService 28 + RecentlyDeletedBatch 10 + ConsumerToolSessionLock 3 + DataLifecycle 3 + SecureBackup 11）。

xcresult：`/tmp/ApiRelayAgentDD/Logs/Test/Test-ApiRelay-2026.09.15_08-04-33-+0800.xcresult`。

新增/加严的代表用例：创建与头像跳过身份、取用开关只影响查看复制、不验证直达、应用密码缺口令不改数据、取消当前方式零副作用、设备/组合档走 `confirm`、会话锁先于门闩、批量一次门闩、导出取消无文件、清空取消保留数据。

未跑共享 scheme 全量测试（属 W6）。未对 05 所列「每个操作 × 四档」逐格手测。

## 5. 收尾四问

1. **外部资源**：密钥明文仍只经 `KeychainStore`；本波测试一律 `KeychainStore.makeForTests()`，与 App 组隔离。SwiftData 用内存容器。备份导出/导入测的是服务层门闩，不写真实文件选择器。未改 Keychain ACL/同步策略，未碰 CloudKit Production。剪贴板自动清除路径未改语义。
2. **失败路径**：认证取消 → 零写入；会话锁 → 不弹门闩；应用密码缺材料/未输入 → 校验失败且数据不动，Vault 首页与备份页可再采集口令重试；取用开关关闭时查看/复制直达，删除仍要当前方式；不验证时身份跳过，永久删除/清空仍先确认。设置页清空在应用密码档下目前只能看到错误，不能在本波允许文件里补采集框。
3. **接缝**：`KeyVaultServing` / `RecentlyDeletedBatchServing` / `ConsumerToolServing` / `SecureBackupServing` / `DataLifecycleServing` 的 Fake 已跟上 `appPassword`。门闩日记仍用既有 `FakeRevealGate`。`CurrentRevealPolicyAuth` 是 W3 纯路由，本波复用，未改其实现文件。
4. **文件粒度**：`VaultHomeView.swift` 4515 行，`VaultHomeViewModel.swift` 989 行，`BackupSettingsViews.swift` 812 行，`KeyVaultServiceTests.swift` 767 行，`KeyVaultService.swift` 741 行，`KeyDetailView.swift` 564 行。均超过 400 行建议阈值。本波不拆。

## 6. 未验证项

- 真机 Face ID / Touch ID、组合档取消不回落设备密码的系统弹窗（W6）。
- 备份与永久删除在三端上的完整确认/取消手测（05 §八第 7 项，W6）。
- 设置页清空在应用密码档下的口令采集（`SettingsView` 属 W3 清单，本波不得改）。
- 组合档显式「使用应用密码」入口与取用授权复用（W5）。
- 共享 scheme 全量测试与 Mac Catalyst（W6）。

## 7. 方法观察

`FakeRevealGate.journal` 是 actor 隔离属性。`XCTAssertEqual(await fake.journal.callCount(...))` 会同时触碰 MainActor 自动闭包和 `await`，编译失败。本波改为先 `let journal = await fake.journal` 再断言。`04`/`05` 文首「等待批准」与后续波次已批准的事实仍并存，本波未改这两份计划。

下一步负责人：Codex
是否需要用户批准：否
下一步：执行 `/Users/xitongzhili/Desktop/MacTransfer/08_Code/E02_ApiRelay_Github/ZL02_研发档案/第一阶段-密钥库/调整与优化/v1.13.9-身份验证四档与主密码调整/提示词/阶段4A-Codex波次审计.md`

写入状态：已停止
