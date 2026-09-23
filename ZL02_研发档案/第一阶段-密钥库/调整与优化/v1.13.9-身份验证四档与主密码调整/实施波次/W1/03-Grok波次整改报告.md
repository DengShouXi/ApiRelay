写入状态：未停止

# 阶段4：Grok波次整改报告（W1）

- 阶段：4
- 波次：W1（只修 `02-Codex波次审计报告.md` 列出的本波阻塞；未进入 W2）
- 报告文件：`实施波次/W1/03-Grok波次整改报告.md`（未覆盖 `01` / `02`）
- 时间：2026-09-15 06:18 CST
- 分支：`v1.13.9`
- HEAD：`6ec5ff7c67547637bbd55f528276422395e28c03`（与契约 `baselineHead` 一致，未离开基线）
- 方法版本：`MAIC-1.3`
- 工作包：`ZL02_研发档案/第一阶段-密钥库/调整与优化/v1.13.9-身份验证四档与主密码调整/`
- 输入：修订后 `04`/`05`、`00C`、`实施波次/W1/01-Grok实施报告.md`、`实施波次/W1/02-Codex波次审计报告.md`
- 用户授权：当前消息明确「同意并批准修订后的04和05」，并执行 `提示词/阶段4-Grok执行下一波.md`。按阶段4例外：较新 `04`/`05` 已引用 `02` 并覆盖计划缺口，仅授权在新版精确范围内整改 W1 阻塞。不授权 W2、不授权暂存/提交/上传
- 当前授权范围：修订版 `04` 第三节 W1 精确文件清单与括号限制
- 保护 refs（未改）：`main` / `origin/main` = `539447ea9984608c74989da48b8770cb3fe32a6c`；`release/1.0.0` = `5c5eed3f8390f51f5a26be9737bcc11f72e7d7fd`
- 暂存区：空
- worktree：仅本仓库一份
- 下一负责人：Codex
- 下一步：执行工作包 `提示词/阶段4A-Codex波次审计.md`

---

## 1. 对照 `02` 的五处阻塞

### W1-B01：计划外生产文件

修订后的 W1 已把三处接缝列入精确范围。按新边界改完：

- `RevealGate.swift`：组合档 **fail-closed**，抛 `combination_policy_not_ready`，不调用 LA、不伪装设备验证、不纯生物成功、不回落不验证。
- `AppPrivacyController.swift`：删除旧 `.biometricOnly` 死局分支；组合档解锁转调上述接缝。缺生物识别不再把设备验证当死局。
- `SettingsView.swift`：去掉仅生物识别选择入口；组合档摘要用新键，不再显示成设备验证短名；W3 前不开放组合档选择行。
- `Localizable.xcstrings`：只增加 `settings.policy.biometryOrAppPassword.short` 中英文。

### W1-B02：运行时必须四档

`RevealPolicy` 现仅四 case：`biometricOrPasscode` / `masterPassword` / `biometryOrAppPassword` / `noVerification`。旧值 `biometricOnly` 只作为 `RevealPolicyPersistence.legacyBiometricOnlyRawValue` 在解码层识别。生产与测试代码反搜 `.biometricOnly`：**0 命中**。`SecurityReviewTests.testRevealPolicySingleSwitchSemantics` 恢复四 case 断言。

### W1-B03：未配置应用密码闸门

按修订计划：W1 不查询本机材料、不实现首次选择闸门（改到 W3）。删除名实不符的 `testUnconfiguredMasterPasswordMustNotCountAsReady`，改为 `testExistingMasterPasswordRawValueIsPreserved`（既有 `masterPassword` rawValue 保持、不写成 `none`）。

### W1-B04：缺字段默认 true

新增 `testLegacyStoreMissingRevealAuthEnabledLoadsAsTrue`：用 Core Data 写出 **没有** `revealAuthEnabled` 属性的 `UserPreferences` 商店（`revealPolicy = none`），再以现行 SwiftData `UserPreferences` 打开。加载结果：`revealPolicy` 仍为不验证（证明读到旧行，不是新建默认对象），`revealAuthEnabled == true`。

### W1-B05：规范化 persist 失败可注入

抽出 `RevealPolicyCanonicalPersist.persistIfNeeded`；仓库规范化写回走它。`testCanonicalPersistFailureKeepsOriginalRawAndFailClosedRuntime` 注入 `save` 抛错：原 rawValue 保留、不写 `none`、运行时仍设备验证；恢复后重试可规范化。

---

## 2. 实际修改的文件

相对基线的 Swift / 测试 / 本地化：`git diff --stat` 20 个文件，+623 / −196。均在修订版 W1 清单内。

未改 `FakePreferences.swift`、Keychain 策略、`04`/`05` 正文、`tools/`。未开 W2。

---

## 3. 测试

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
  -only-testing:ApiRelayTests/SecuritySettingsPersistTests \
  -only-testing:ApiRelayTests/RevealGateTests \
  -only-testing:ApiRelayTests/KeyVaultServiceTests \
  -only-testing:ApiRelayTests/AppPrivacyControllerTests \
  -only-testing:ApiRelayTests/CatalystAdaptationTests \
  -only-testing:ApiRelayTests/SecurityReviewTests
```

**TEST SUCCEEDED**：Selected tests **131** 个，0 failure。xcresult：`/tmp/ApiRelayAgentDD/Logs/Test/Test-ApiRelay-2026.09.15_06-16-05-+0800.xcresult`。

---

## 4. 未验证项

- Mac Catalyst 本波仍未用开发证书跑测试。
- 真实 CloudKit 旧记录缺字段（本任务不部署 Production）；B04 证据是本机旧 schema 商店，不是 iCloud 生产库。
- 组合档完整验证、三行设置、首次设应用密码闸门属 W2/W3。
- 共享 scheme 全量测试未作为本整改停止点重跑（已含 `SecurityReviewTests` 四 case 断言）。

---

## 5. 方法观察

- 已启用 `ZL00/04`（MAIC-1.3）。用户批准修订计划后，阶段4例外才允许在新范围内修 `02` 的阻塞，而不是执行者自行扩权。
- `04`/`05` 文首仍写「等待用户明确批准」——那是阶段3产物原文；本波未改这两份文件。
- 未读、未改 `tools/`。单写入者：本对话只写修订版 W1 允许文件 + 本奇数报告。

---

## 6. 建议审计结论（供 Codex，不是自批通过）

请 Codex 按修订后 `05` 第三节与 `02` 五条阻塞独立复验。失败则只列本波剩余阻塞；通过后才可进入 W2。

写入状态：已停止
