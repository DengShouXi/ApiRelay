写入状态：未停止

# 阶段4：Grok实施报告（W1）

- 阶段：4
- 波次：W1（数据模型、默认值与幂等迁移）
- 时间：2026-09-14 23:50 CST
- 分支：`v1.13.9`
- HEAD：`6ec5ff7c67547637bbd55f528276422395e28c03`（与契约 `baselineHead` 一致，未离开基线）
- 方法版本：`MAIC-1.3`
- 工作包：`ZL02_研发档案/第一阶段-密钥库/调整与优化/v1.13.9-身份验证四档与主密码调整/`
- 输入：`00`、`00C`、`04`、`05`、`实施波次/W0/04-Codex波次复验报告.md`（结论：波次审计通过，可以进入下一波）、宪法 VIII、W1 允许的 Swift / 测试文件
- 用户授权：用户执行 `提示词/阶段4-Grok执行下一波.md`，视为对 `04`/`05` 的整体批准；**仅授权本波 W1**。不授权 W2、不授权暂存/提交/上传
- 当前授权范围：`04` 第三节 W1 精确文件清单；禁止 Keychain 实现、产品 UI、`tools/`、ROADMAP、ZL00、xcodeproj
- 保护 refs（未改）：`main` / `origin/main` = `539447ea9984608c74989da48b8770cb3fe32a6c`；`release/1.0.0` = `5c5eed3f8390f51f5a26be9737bcc11f72e7d7fd`
- 暂存区：空
- worktree：仅本仓库一份
- 下一负责人：Codex
- 下一步：执行工作包 `提示词/阶段4A-Codex波次审计.md`

---

## 1. 本波做了什么

把四档持久值、出厂默认和旧值映射落到数据层；取用验证独立同步字段出厂开启；安全变化判定按 2026-09-14 锁定语义更新。

| 输入 | 落地 |
| --- | --- |
| 新建偏好 | `revealPolicy = biometricOrPasscode`，`revealAuthEnabled = true` |
| `none` | 保留，不强迁 |
| `biometricOrPasscode` | 稳定，不改 rawValue |
| `biometricOnly` | 运行时与写回均为 `biometricOrPasscode`；重复加载幂等 |
| `masterPassword` | 保留 rawValue，即使本机无密码材料也不写成 `none` |
| `biometryOrAppPassword` | 新 rawValue 往返；**不**复用 `biometricOnly` |
| 未知字符串 | 运行时 fail-closed 为设备验证；成功 save 后才规范化；**不得**写成 `none`；save 失败回滚原 rawValue |
| 多副本 | 全部副本一起迁；第二次加载不再产生新变化 |
| `revealAuthEnabled` | 模型加法默认 true；patch 可写成 false |
| 切换矩阵 | 从 none 加强不 weaken；关锁/延长/关取用/改 none 为 weaken；三种有验证方式互换为 weaken |

`RevealPolicy.selectableCases` 不含遗留 `biometricOnly`。`FakePreferences.swift` 在清单内但未改逻辑，默认走 `PreferencesDTO.fakeDefault()`。

未改 Keychain 策略。未实现设置页三行、组合档完整门闩、同详情复用。

---

## 2. 实际修改的文件

Swift / 测试 `git diff --stat`：14 个已跟踪文件，+434 / −67。

### 2.1 W1 清单内（11 个，+415 / −67）

- `ApiRelay/ApiRelay/Shared/DTOs/DTOs.swift`（现 521 行，超过 400 行，本波未拆）
- `ApiRelay/ApiRelay/Data/SwiftData/Models/UserPreferences.swift`
- `ApiRelay/ApiRelay/Data/SwiftData/Repositories/UserPreferencesRepository.swift`
- `ApiRelay/ApiRelay/Business/System/PreferencesService.swift`
- `ApiRelay/ApiRelay/Business/System/SessionLockQuerying.swift`
- `ApiRelay/ApiRelay/DebugSupport/Fakes/FakeSupport.swift`
- `ApiRelay/ApiRelayTests/V1/Phase02_Data/SwiftDataRepositoryTests.swift`
- `ApiRelay/ApiRelayTests/V1/Phase06_Settings/PreferencesServiceTests.swift`
- `ApiRelay/ApiRelayTests/V1/Phase06_Settings/CloudSyncTests.swift`
- `ApiRelay/ApiRelayTests/V1/Phase06_Settings/SecurityPolicyChangeTests.swift`
- `ApiRelay/ApiRelayTests/V1/Phase06_Settings/SecuritySettingsPersistTests.swift`

清单内未改：`ApiRelay/ApiRelay/DebugSupport/Fakes/FakePreferences.swift`（仍委托 `fakeDefault()`）。

### 2.2 计划外编译接缝（3 个，+19 / −0）——请 Codex 按范围独立判定

新增 `RevealPolicy.biometryOrAppPassword` 后，同模块 exhaustive `switch` 无法编译。为让 App 目标与 W1 测试能编过，补了 case，**没有**实现 W2/W3/W5 产品行为：

- `ApiRelay/ApiRelay/Business/Vault/RevealGate.swift`（W2 文件）：组合档暂走 `deviceOwnerAuthenticationWithBiometrics`
- `ApiRelay/ApiRelay/App/AppPrivacyController.swift`（W3 文件）：解锁 switch 增加组合档，转调 `gate.confirm(policy: .biometryOrAppPassword)`
- `ApiRelay/ApiRelay/UI/Settings/SettingsView.swift`（W3/W5 文件）：摘要暂用设备验证短名，避免缺本地化键

`04` 第四节原文：「任何计划外必要文件或新产品决定都必须停止，退回Codex修订本计划并重新取得用户批准。」本波没有改 `04`，也没有当作自己已获扩范围批准。三处接缝保留在工作区，是为了编译与测试证据可复核；**不是**自批通过的理由。

本报告为 `00C.allowedAdd` 下新建 `实施波次/W1/01-Grok实施报告.md`，未覆盖任何已有报告。

---

## 3. 对照 `05` 第三节

| 检查项 | 证据 |
| --- | --- |
| 新建偏好默认 | `SwiftDataRepositoryTests.testNewUserPreferencesDefaultToDeviceAuthAndRevealAuthEnabled`、`PreferencesServiceTests.testDefaultsAndAppearanceIsolation` |
| `none` 不强迁 | `testNoneRevealPolicyIsKeptAndNotForceMigrated` |
| `biometricOnly` 一次迁到设备验证且幂等 | `testBiometricOnlyMigratesIdempotentlyToDeviceAuth` |
| `masterPassword` 有/无本机材料均保留值 | 数据层 `testMasterPasswordRawValueIsKeptEvenWithoutLocalMaterial`；本机材料恢复路径属 W2/W3 |
| 组合档不复用 `biometricOnly` | `testBiometryOrAppPasswordRoundTripsWithoutReusingBiometricOnly` |
| 未知值不转 `none`、成功后规范化 | `testUnknownRevealPolicyFailClosedToDeviceAuthAndNormalizesOnce`；save 失败回滚在 `persistCanonicalRevealPolicies`，无单独注入 `save` 失败的仓库测试 |
| 多副本 / 重复加载 | `testDuplicateReplicasMigrateBiometricOnlyTogether` |
| 同步 Bool 缺字段为 true | 模型默认 true + `testMissingRevealAuthEnabledTreatsAsTrue` + `CloudSyncTests.testSyncedUserPreferencesAddsRevealAuthEnabledWithoutReplacingRevealPolicy`。未对真实 CloudKit 缺字段解码做集成验证 |
| persist 失败不降 | `SecuritySettingsPersistTests.testWeakeningRevealAuthKeepsEnabledWhenPersistFails` 与既有关锁/改 none 失败用例 |
| 从 none 加强直写 | `testStrengthenFromNoVerificationIsNotWeakening` |
| 关锁/延长/关取用/改 none | `SecurityPolicyChangeTests` 对应用例 |
| 三种有验证方式互换须确认 | `testAuthenticatedPolicySwapsAreSensitive`（`weakens == true`，供后续设置页先验证） |

「设置首次应用密码时不得把未配置状态写成有效档」：W1 未把 `MasterPasswordServing` 接到 `PreferencesService`（`AppEnvironment` 属 W2）。数据层仍接受 `revealPolicy = masterPassword` 的 patch；`testUnconfiguredMasterPasswordMustNotCountAsReady` 只证明**不会**把该 rawValue 改写成 `none`。真正拦截首次未配置写入留给 W2/W3。

---

## 4. 测试

```text
bash ApiRelay/scripts/selfcheck.sh
```

红线通过。`git diff --check` 退出 0。

```text
xcodebuild test -project ApiRelay.xcodeproj -scheme ApiRelay -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -derivedDataPath /tmp/ApiRelayAgentDD \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=YES CODE_SIGNING_REQUIRED=YES \
  -only-testing:ApiRelayTests/SwiftDataRepositoryTests \
  -only-testing:ApiRelayTests/PreferencesServiceTests \
  -only-testing:ApiRelayTests/CloudSyncTests \
  -only-testing:ApiRelayTests/SecurityPolicyChangeTests \
  -only-testing:ApiRelayTests/SecuritySettingsPersistTests
```

**TEST SUCCEEDED**：Selected tests 66 个，0 failure（CloudSync 16、PreferencesService 10、SecurityPolicyChange 7、SecuritySettingsPersist 5、SwiftDataRepository 28）。xcresult：`/tmp/ApiRelayAgentDD/Logs/Test/Test-ApiRelay-2026.09.14_23-43-04-+0800.xcresult`。

Mac Catalyst 同 scheme 加 `CODE_SIGN_IDENTITY="-"` 在测试启动前失败：`ApiRelay has entitlements that require signing with a development certificate`（exit 65），不是断言失败。本波未用开发证书重跑 Catalyst。

未跑共享 scheme 全量测试。已知：`SecurityReviewTests.testRevealPolicySingleSwitchSemantics` 仍断言 `RevealPolicy.allCases.count == 4`，现为 5（保留遗留 `biometricOnly` + 新组合档）。该文件在 **W2** 清单，W1 未改；全量会红。

---

## 5. 未验证项

- 真机 / TestFlight / CloudKit Production Deploy（`revealAuthEnabled` 发出正式包前须 Deploy；本工作不部署）。
- 双设备同步「应用密码档到无本机材料设备」的运行时恢复（W2/W3）。
- 组合档取消不回落设备密码、显式应用密码入口（W2）；三行设置与 persist-then-apply 界面（W3）。
- 仓库 `save()` 在规范化写回时失败的注入测试（实现有回滚，测试未打到该 catch）。
- Mac Catalyst 本波因签名未跑通测试。
- 全量测试（W2 的 `allCases.count` 会红）。

---

## 6. 方法观察

- 已启用 `ZL00/04`（MAIC-1.3）。Grok 执行 W1，Codex 用阶段 4A 审计。
- W1 要求「增加四档规范枚举」，但精确清单未包含对该枚举做 exhaustive switch 的生产文件。这是计划与编译现实的缺口，不是执行者应擅自扩 W2/W3 产品行为的授权。
- 单写入者：本对话只写 W1 相关文件 + 本奇数报告。未读、未改 `tools/`。未跟踪项仍是工作包目录与 `tools/`。
- 检查器只路由、不授予执行权。本报告写完后应交 Codex 审计，不得自行开 W2。

---

## 7. 建议审计结论（供 Codex，不是自批通过）

数据层默认、四旧值、未知值、多副本、取用开关与切换矩阵的 **W1 指定测试已绿**。同时存在 **3 个清单外文件** 的编译接缝，与 `04` 第四节「计划外必要文件必须停止并退回修订计划」冲突。

请 Codex 按 `05` 第三节与精确范围独立判定。失败则只列本波阻塞，不得进入 W2。若认为必须扩 W1 清单或改枚举落地方式，应回阶段 3 修订 `04` 并再取得用户批准，而不是把产品门闩提前做进 W2/W3。

写入状态：已停止
