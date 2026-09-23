写入状态：未停止

# 阶段4：Grok波次整改报告（W2）

- 阶段：4
- 波次：W2（只修 `02-Codex波次审计报告.md` 列出的本波阻塞；未进入 W3）
- 报告文件：`实施波次/W2/03-Grok波次整改报告.md`（未覆盖 `01` / `02`）
- 时间：2026-09-15 06:54 CST
- 分支：`v1.13.9`
- HEAD：`6ec5ff7c67547637bbd55f528276422395e28c03`（与契约 `baselineHead` 一致，未离开基线）
- 方法版本：`MAIC-1.3`
- 工作包：`ZL02_研发档案/第一阶段-密钥库/调整与优化/v1.13.9-身份验证四档与主密码调整/`
- 输入：修订并经用户批准的 `04`/`05`、`00C`、`实施波次/W2/01-Grok实施报告.md`、`实施波次/W2/02-Codex波次审计报告.md`
- 用户授权：用户执行 `提示词/阶段4-Grok执行下一波.md`。`02` 失败类型为**普通整改**。仅授权整改 W2-B01/W2-B02。不授权 W3、不授权暂存/提交/上传
- 当前授权范围：修订版 `04` 第三节 W2 精确文件清单
- 保护 refs（未改）：`main` / `origin/main` = `539447ea9984608c74989da48b8770cb3fe32a6c`；`release/1.0.0` = `5c5eed3f8390f51f5a26be9737bcc11f72e7d7fd`
- 暂存区：空
- worktree：仅本仓库一份
- 下一负责人：Codex
- 下一步：执行工作包 `提示词/阶段4A-Codex波次审计.md`

---

## 1. 对照 `02` 的两处阻塞

### W2-B01：真实生物锁定被预检查压成不可用

组合档不再用 `availableBiometry()` 做提前退出。生产预检查改为 `canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics)`，结果一律交给 `RevealGate.interpretBiometricsAvailability`：

- `canEvaluate == true` → 再走纯生物 `evaluate`
- `LAError.biometryLockout` → `biometryLockout`，**不**调用 evaluate、**不**回落设备密码
- 其它失败（未录入、不可用）→ `biometryUnavailable`，同样不弹设备密码

测试注入只替换 `canEvaluatePolicy` 的返回值/`NSError`，仍走同一套 interpret。新增：

- `testInterpretBiometricsLockoutIsNotUnavailable`
- `testCombinationPreflightLockoutDoesNotCallEvaluate`（锁定 NSError、evaluate 调用次数为 0）
- 保留 evaluate 路径锁定：`testCombinationEvaluateLockoutDoesNotFallBackToDevicePasscode`

### W2-B02：恢复入口可等待、顺序固定、失败可报错

删除协议上的 `resetAppPasswordMaterial`（设备主人后立刻删材料、容易留下「策略仍是应用密码、材料已无」）。

唯一产品入口：`AppEnvironment.resetAppPasswordAndFallToDeviceAuth()`，内部只调用 `AppPasswordRecovery.recoverToDeviceAuth`：

1. `confirmMandatory`
2. `awaitPersist`（等非阻塞 `persist` 回调，不在 MainActor 上 `await update()`）
3. 成功后才 `masterPassword.reset()`

persist 失败抛错并保留材料；删除失败在策略已落到设备验证后把 Keychain 错误抛给调用方。调用者可以 `try await` 等到最终结果。

测试覆盖：协调器顺序、persist 失败跳过 reset、`AppEnvironment.resetAppPasswordAndFallToDeviceAuth` 的 persist 失败 / 删除失败 / 成功完成。

---

## 2. 实际修改的文件

本整改只动 W2 清单内文件。相对基线，本波相关 diff 主要在：

- `RevealGate.swift` / `RevealGateServing.swift`
- `AppEnvironment.swift`
- `MasterPasswordService.swift`（注释）
- `FakeRevealGate.swift` / `FakeMasterPassword.swift`
- `RevealGateTests.swift` / `SecurityReviewTests.swift` / `CatalystAdaptationTests.swift`

未改设置页、锁屏、`KeychainStore`、`04`/`05`。未开 W3。已删除公开分拆入口 `resetAppPasswordMaterial`。

---

## 3. 测试

```text
bash ApiRelay/scripts/selfcheck.sh
```

红线通过。`git diff --check` 对本波相关文件退出 0。

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

**TEST SUCCEEDED**：48 tests, 0 failures（RevealGate 29 + MasterPassword 8 + SecurityReview 8 + Catalyst 3）。

---

## 4. 实现收尾四问

1. **外部资源**：仍只碰测试前缀 Keychain（`makeForTests()`）与可注入的 LA 预检查。恢复路径用 `FakePreferences.persist` 回调，不写生产 CloudKit。UserDefaults / App Group / StoreKit 未新增。

2. **失败路径**：预检查锁定 → `biometryLockout` 且不调 evaluate；不可用 → `biometryUnavailable`；恢复时取消不 persist/不删材料；persist 失败保留材料并抛错；删材料失败在策略已是设备验证后把错误交给调用方，不写成不验证。

3. **接缝**：`FakeRevealGate` 去掉分拆重置；`FakeMasterPassword.fail` 注入删除失败；`AppEnvironment.makePreview()` 走真实 `resetAppPasswordAndFallToDeviceAuth`。

4. **文件粒度**：生产文件未超 400 行。`RevealGateTests.swift` 现为 **533 行**，超过 400；本整改未拆，留给用户决定。

---

## 5. 未验证

- 真机 Face ID 锁定时系统 `canEvaluatePolicy` 的 NSError 是否始终为 `biometryLockout`（代码已按该 code 识别）。
- W3 把锁屏/设置页接到 `resetAppPasswordAndFallToDeviceAuth`。
- 全量 scheme、Catalyst 证书构建属 W6。

---

## 6. 方法观察

`02` 指出的问题成立：把 `availableBiometry()` 的 `.none` 当成组合档预检查，等于丢掉 `canEvaluatePolicy` 的 NSError。整改把 interpret 提成生产与测试共用函数，注入只替换 canEvaluate 结果，不再用「强制 faceID + 第二次闭包抛锁定」冒充预检查。

写入状态：已停止
