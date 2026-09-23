写入状态：未停止

# 阶段4：Grok实施报告（W2）

- 阶段：4
- 波次：W2（验证引擎与应用密码恢复；未进入 W3）
- 报告文件：`实施波次/W2/01-Grok实施报告.md`
- 时间：2026-09-15 06:36 CST
- 分支：`v1.13.9`
- HEAD：`6ec5ff7c67547637bbd55f528276422395e28c03`（与契约 `baselineHead` 一致，未离开基线）
- 方法版本：`MAIC-1.3`
- 工作包：`ZL02_研发档案/第一阶段-密钥库/调整与优化/v1.13.9-身份验证四档与主密码调整/`
- 输入：修订并经用户批准的 `04-最终执行计划.md`、`05-最终检查计划.md`、`00C-任务契约.json`、`实施波次/W1/04-Codex波次复验报告.md`
- 用户授权：用户执行 `提示词/阶段4-Grok执行下一波.md`。W1 复验已通过。仅授权本波 W2。不授权 W3、不授权暂存/提交/上传
- 当前授权范围：修订版 `04` 第三节 W2 精确文件清单
- 保护 refs（未改）：`main` / `origin/main` = `539447ea9984608c74989da48b8770cb3fe32a6c`；`release/1.0.0` = `5c5eed3f8390f51f5a26be9737bcc11f72e7d7fd`
- 暂存区：空
- worktree：仅本仓库一份
- 下一负责人：Codex
- 下一步：执行工作包 `提示词/阶段4A-Codex波次审计.md`

---

## 1. 本波做了什么

按 `05` 第四节把组合档从 W1 的 `combination_policy_not_ready` 换成可测试的四档引擎：

- **不验证**：不调用 LA，也不查询/校验应用密码。
- **设备验证**：只走 `LAPolicy.deviceOwnerAuthentication`。
- **应用密码**：`confirm` 在已设材料时抛 `master_password_prompt_required`（由 UI 采集）；成功/错误/限速走 `confirmWithMasterPassword`，不弹系统设备密码。
- **组合档**：有生物识别时只走 `deviceOwnerAuthenticationWithBiometrics`；取消、锁定、系统失败都只记这一次政策，**不**回落 `deviceOwnerAuthentication`。无生物识别时抛 `biometryUnavailable`，不调用 LA。显式应用密码必须另调 `confirmCombinationWithAppPassword`。
- **`confirmMandatory`**：始终 `deviceOwnerAuthentication`，忽略用户档和是否有生物识别。
- **材料状态**：`isAppPasswordMaterialSet()` 委托 `MasterPasswordServing.isSet()`。
- **重置**：`resetAppPasswordMaterial` 先设备主人，再只删 `.masterpw`。恢复补丁 `AppPasswordRecovery.deviceAuthPatch` 固定为设备验证，不得为不验证。`AppEnvironment.resetAppPasswordAndFallToDeviceAuth` 先设备主人，**persist 成功后**才清材料；persist 失败保留材料，不会写成不验证。

未重写 PBKDF2 / 盐 / 恒定时间比较 / 3 次失败限速。未改 Keychain 实现、设置页、锁屏 UI、`Localizable.xcstrings`。

---

## 2. 实际修改的文件

相对本波，`git diff --stat` 仅下列 11 个文件，+597 / −71，均在 W2 清单内：

- `ApiRelay/ApiRelay/Business/Vault/RevealGate.swift`
- `ApiRelay/ApiRelay/Business/Vault/RevealGateServing.swift`
- `ApiRelay/ApiRelay/Business/System/MasterPasswordService.swift`（只改 `reset` 注释；未改派生）
- `ApiRelay/ApiRelay/Shared/ApiRelayError.swift`（`biometryLockout`、`systemAuthenticationFailed`；文案复用已有键，未改 xcstrings）
- `ApiRelay/ApiRelay/App/AppEnvironment.swift`
- `ApiRelay/ApiRelay/DebugSupport/Fakes/FakeRevealGate.swift`
- `ApiRelay/ApiRelay/DebugSupport/Fakes/FakeMasterPassword.swift`
- `ApiRelay/ApiRelayTests/V1/Phase03_Vault/RevealGateTests.swift`
- `ApiRelay/ApiRelayTests/V1/Phase03_Vault/MasterPasswordServiceTests.swift`
- `ApiRelay/ApiRelayTests/V1/Phase08_Security/SecurityReviewTests.swift`
- `ApiRelay/ApiRelayTests/V1/Phase07_Catalyst/CatalystAdaptationTests.swift`

未改 `SettingsView.swift`、`AppPrivacyController.swift`、`KeychainStore.swift`、`04`/`05` 正文。未开 W3。

---

## 3. 对照 `05` 第四节的停止点

| 要求 | 证据 |
| --- | --- |
| 不验证不调 LA / 应用密码 | `testPolicyNoneDoesNotCallLAOrAppPassword` |
| 设备验证只用 `deviceOwnerAuthentication` | `testDeviceAuthUsesDeviceOwnerAuthenticationOnSuccess`；取消/系统失败各一次、不重试 |
| 应用密码不调系统设备密码；盐/限速回归 | `testMasterPassword*`；`MasterPasswordServiceTests` 原盐/限速/错误口令 + `testResetDoesNotDeleteKeysAdminOrBackupPassphrase` |
| 组合档纯生物；取消不回落设备密码 | `testCombinationUsesBiometricsOnlyOnSuccess`、`testCombinationCancelDoesNotFallBackToDevicePasscode`；Catalyst / SecurityReview 各有一条同类断言 |
| 生物不可用 / 锁定 / 系统错误可区分 | `biometryUnavailable`（无生物、不调 LA）、`biometryLockout`、`systemAuthenticationFailed` |
| 显式应用密码：未设 / 错误 / 成功 | `testCombinationExplicitAppPassword*` |
| `confirmMandatory` 不被改成当前档 | `testConfirmMandatoryAlwaysDeviceOwnerAuthentication`（无生物仍走设备主人） |
| 可测试材料状态；缺材料不静默放行 | `isAppPasswordMaterialSet`；未设走 `master_password_not_set` |
| 重置只删门闩材料、落到设备验证、失败不落到不验证 | `testResetAppPasswordRequiresDeviceOwnerAndLeavesOtherKeychainItems`；取消重置材料仍在；补丁 `revealPolicy == biometricOrPasscode` |
| 无日志秘密 | 门闩/主密码路径无 `print`；`testWrongPasswordErrorDoesNotEmbedSecret` |

---

## 4. 测试

```text
bash ApiRelay/scripts/selfcheck.sh
```

红线通过。`git diff --check` 对本波 11 个文件退出 0。

```text
xcodebuild test -project ApiRelay.xcodeproj -scheme ApiRelay -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -derivedDataPath /tmp/ApiRelayAgentDD \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=YES CODE_SIGNING_REQUIRED=YES \
  -only-testing:ApiRelayTests/RevealGateTests \
  -only-testing:ApiRelayTests/MasterPasswordServiceTests \
  -only-testing:ApiRelayTests/SecurityReviewTests \
  -only-testing:ApiRelayTests/CatalystAdaptationTests
```

**TEST SUCCEEDED**：41 tests, 0 failures（RevealGate 22 + MasterPassword 8 + SecurityReview 8 + Catalyst 3）。

未跑共享 scheme 全量测试（属 W6）。

---

## 5. 实现收尾四问

1. **外部资源**：本波碰到 Keychain `.masterpw` / `.keys` / `.admin` / `.backuppw`（只读断言未误删）和可注入的 LA 钩子。测试一律 `KeychainStore.makeForTests()`，与生产 servicePrefix 隔离；`setUp`/`tearDown`/`addTeardownBlock` 只清测试前缀。未在本波写 SwiftData/CloudKit（`AppEnvironment` 的 persist 走既有 `PreferencesServing` 非阻塞链，本波测试未驱动真实 CloudKit）。UserDefaults / App Group / StoreKit 未新增。

2. **失败路径**：取消 → `authenticationCancelled`；无生物 → `biometryUnavailable`（组合档不弹设备密码）；生物锁定 → `biometryLockout`；未设应用密码 → `master_password_not_set`；口令错误 → `authenticationFailed`；连续失败限速 → `masterPasswordRetryDelayed`；其它 LA 失败 → `systemAuthenticationFailed`。重置取消则材料仍在。persist 失败时 `resetAppPasswordAndFallToDeviceAuth` 不清材料、不写不验证。用户在 W3 前还没有组合档「使用应用密码」按钮和锁屏新文案；引擎已区分错误，界面分键留给 W5。

3. **接缝**：`FakeRevealGate` 补齐新协议方法；组合档矩阵用真实 `RevealGate` + 可注入 LA/生物识别，避免只能打真机弹窗。`FakeMasterPassword` 无限速，限速回归仍走真实 `MasterPasswordService`。

4. **文件粒度**：本波改动的生产文件均未超过 400 行（`RevealGate.swift` 217，`AppEnvironment.swift` 249，`RevealGateTests.swift` 367）。`DTOs.swift` 仍为 556 行，但本波未改它，未拆。

---

## 6. 未验证 / 留给后续波次

- 真机 Face ID / Mac Touch ID：取消后系统是否真的不改弹登录密码（本波用注入 `LAPolicy` 证明引擎不会发第二次 `deviceOwnerAuthentication`）。
- 设置页三行、首次选择应用密码不得写成有效档、锁屏「使用应用密码」按钮（W3/W5）。
- `AppPrivacyController` 仍留有 W1「组合档 fail-closed」注释；该文件不在 W2 清单，未改。引擎 `confirm(.biometryOrAppPassword)` 现已可走纯生物成功，若已同步到组合档，解锁会按新引擎走生物识别。
- `AppEnvironment.resetAppPasswordAndFallToDeviceAuth` 的 persist 成功回调未做独立注入测试。
- 全量测试、Release / Catalyst 构建属 W6。

---

## 7. 方法观察

- `04`/`05` 文首仍写「W1修订版，等待用户明确批准」——那是阶段 3 原文。W1/04 已记录用户批准，本波按该修订范围执行 W2，未改 `04`/`05`。
- 完成一波即停。请 Codex 按 `05` 第四节与精确范围独立审计。失败则只列本波阻塞；通过后才可进入 W3。

写入状态：已停止
