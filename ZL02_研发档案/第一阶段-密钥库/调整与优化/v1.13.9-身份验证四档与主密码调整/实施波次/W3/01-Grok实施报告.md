# 阶段4：Grok实施报告（W3）

写入状态：未停止

- 阶段：4
- 波次：W3（三行设置与 App 锁）
- 时间：2026-09-15
- 分支：`v1.13.9`
- HEAD：`6ec5ff7c67547637bbd55f528276422395e28c03`
- 方法版本：`MAIC-1.3`
- 工作包：`ZL02_研发档案/第一阶段-密钥库/调整与优化/v1.13.9-身份验证四档与主密码调整/`
- 输入：经用户批准的修订版 `04-最终执行计划.md`、`05-最终检查计划.md`、`00C-任务契约.json`、`实施波次/W2/04-Codex波次复验报告.md`
- 实际授权：用户明确执行 `提示词/阶段4-Grok执行下一波.md`。W0–W2 已通过。`04`/`05` 文首仍留有阶段 3 的「等待批准」字样，但 W1/04 与 W2/04 已记录用户批准修订版；本波按该授权实施 W3，未改 `04`/`05`。

文末 `写入状态：已停止` 为交接用最终状态。

## 1. 入口核对

- 当前分支 `v1.13.9`，HEAD 仍为契约基线 `6ec5ff7c67547637bbd55f528276422395e28c03`。
- 暂存区空；单一 worktree；未提交、未上传、未换分支。
- `main` / `origin/main` = `539447ea9984608c74989da48b8770cb3fe32a6c`；`release/1.0.0` = `5c5eed3f8390f51f5a26be9737bcc11f72e7d7fd`。
- 上一写入者：W2/04 已停止且通过。本波创建前不存在 `实施波次/W3/`。
- 未读取、未修改 `tools/`。

## 2. 本波实际修改（均在 W3 精确清单内）

| 文件 | 做什么 |
| --- | --- |
| `Business/System/AppLockSession.swift` | `isAppLockArmed`：开关开着且不是不验证才上锁。冷启动、回前台、立即锁、现场改偏好都走它。 |
| `Business/System/SessionLockQuerying.swift` | `CurrentRevealPolicyAuth`（按当前档确认）；`AppPasswordPolicyGate`（未配置不得写成应用密码档；组合档密码入口同一材料闸门）。 |
| `App/AppPrivacyController.swift` | 启动缓存写武装状态；不验证不弹设备主人；组合档走真实 `confirm`；锁屏恢复接到 `AppPasswordRecovery`；persist 失败保留材料与锁态。 |
| `UI/Settings/SettingsView.swift` | 三行同组：验证方式、自动锁定、取用验证；开放组合档选择；降低/互换走当前方式；首次应用密码未设只进设密页；重置走 `resetAppPasswordAndFallToDeviceAuth`，不再落到不验证。 |
| `UI/Settings/DurationSettingsViews.swift` | 不验证时自动锁子页不置灰，显示暂停说明。 |
| `UI/Shared/AppLockCoverView.swift` | 生物不可用恢复文案口径改为组合档，不新增 W5 按钮。 |
| `Localizable.xcstrings` | 取用验证、暂停句、组合档名称/说明、降低确认框；改正自动锁 ⓘ 里「不验证仍要 Face ID」的旧句。 |
| `DebugSupport/Fakes/FakePreferences.swift` | persist 成功后按武装状态写启动缓存。 |
| `Phase06_Settings` 上述四个测试文件 | 不验证不上锁、换回验证档、当前方式确认、未配置拒绝保存、恢复 persist 失败、13.7 夹具补验证档。 |

未改但属 W3 允许：`ContentView.swift`（会话层已决定是否画锁，无需再分叉）、`RevealGateCoordinatorTests.swift` / `ScenePresenceSignalTests.swift` / `WindowPrivacyReducerTests.swift`（只回归）。

## 3. 停止点对照

- 设置三行；不验证时后两行可编辑并显示「已开启，当前不生效」，不置灰。
- 不验证 + 自动锁已保存：冷启动和回前台不进软件锁；缓存预锁会在读到不验证后解开；换回验证档不立刻锁，下次离开再生效。
- 三种互换与降低：不验证无确认；设备验证/组合档走 `confirm`；应用密码走口令，不再用 `confirmMandatory` 当降低门槛。
- persist 失败：摘要、内存、启动缓存、会话锁不提前下降。
- 首次选应用密码：本机无材料只进设密，取消/失败不写 `masterPassword`；`AppPasswordPolicyGate` 再挡一层 persist。组合档可选且不要求材料；其密码入口 `canUseAppPasswordEntry` 未配置为 false（完整「使用应用密码」界面属 W5）。
- 设置页重置与锁屏忘记密码都落到设备验证，不得落到不验证。
- 13.7：多窗遮罩、未知≠离屏、验证串行、系统验证中不误判离开、偏好读取失败保持锁态，本波回归通过。删除/备份门闩仍更严，留给 W4。

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
  -only-testing:ApiRelayTests/AppLockSessionTests \
  -only-testing:ApiRelayTests/AppPrivacyControllerTests \
  -only-testing:ApiRelayTests/RevealGateCoordinatorTests \
  -only-testing:ApiRelayTests/ScenePresenceSignalTests \
  -only-testing:ApiRelayTests/WindowPrivacyReducerTests \
  -only-testing:ApiRelayTests/SecurityPolicyChangeTests \
  -only-testing:ApiRelayTests/SecuritySettingsPersistTests
```

**TEST SUCCEEDED**：89 tests, 0 failures（AppLockSession 29 + AppPrivacyController 35 + RevealGateCoordinator 1 + ScenePresence 3 + SecurityPolicyChange 11 + SecuritySettingsPersist 6 + WindowPrivacy 4）。

xcresult：`/tmp/ApiRelayAgentDD/Logs/Test/Test-ApiRelay-2026.09.15_07-13-43-+0800.xcresult`。

未跑共享 scheme 全量测试（属 W6）。

## 5. 收尾四问

1. **外部资源**：恢复路径会写同步偏好并删除 `.masterpw` Keychain 材料。测试用 `KeychainStore.makeForTests()`，用例前后 `master.reset()`；SwiftData 走内存容器；`FakePreferences` 不碰 CloudKit；`AppLockLaunchCache` 走 `AppRuntime.userDefaultsForCurrentRuntime()`，相关测试 `setUp`/`tearDown` 调用 `resetForTests()`。未改 Keychain 同步/ACL 策略。
2. **失败路径**：降低确认取消则不变；persist 失败弹「无法保存」并 reload，锁态与档位不降；未配置应用密码拒绝写成有效档并提示；锁屏恢复取消或 persist 失败保持锁定与材料；策略已落到设备验证但删材料失败时仍按设备验证解锁并显示错误；不验证即使自动锁开着也直接进列表，用户可再选验证档让原自动锁生效。
3. **接缝**：`CurrentRevealPolicyAuth` 依赖 `RevealGateServing`，测试用 `FakeRevealGate` 日记断言走 `confirm` / `confirmWithMasterPassword` 而不是 `confirmMandatory`。`AppPasswordPolicyGate` 是纯函数。锁屏恢复 persist 失败用 `FakePreferences.setUpdateError`。
4. **文件粒度**：`SettingsView.swift` 1441 行，`AppPrivacyController.swift` 810 行，`DurationSettingsViews.swift` 566 行，`AppPrivacyControllerTests.swift` 811 行，`AppLockSessionTests.swift` 420 行。均超过 400 行建议阈值。本波不拆，留给关账后评估。

## 6. 未验证项

- 真机 Face ID / Touch ID / 生物锁定后的锁屏恢复（W6）。
- Mac Catalyst 触控 ID 与多窗手测（W6）。
- 设置页组合档「使用应用密码」完整入口与动态设备名/推荐标记（W5）。
- 设置页降低时应用密码 Alert 的真实键盘与 VoiceOver（W5/W6）。

## 7. 方法观察

`FakePreferences` 是 `actor`，工程默认 `MainActor`，不能直接构造 `AppLockPreferences(dto)` 来写启动缓存（隐式跨 actor async）。本波在假实现里用 DTO 字段计算武装状态，避免把 MainActor 类型拖进测试 actor。`04`/`05` 文首「等待批准」与后续波次已批准的事实并存，会增加恢复成本；本波未改这两份计划。

下一步负责人：Codex
是否需要用户批准：否
下一步：执行 `/Users/xitongzhili/Desktop/MacTransfer/08_Code/E02_ApiRelay_Github/ZL02_研发档案/第一阶段-密钥库/调整与优化/v1.13.9-身份验证四档与主密码调整/提示词/阶段4A-Codex波次审计.md`

写入状态：已停止
