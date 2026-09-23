# 阶段4：Grok实施报告（U2-W3）

写入状态：未停止

- 阶段：4
- 修订ID：U2
- 波次：U2-W3（三行设置、应用密码页、锁屏接到安全恢复）
- 时间：2026-09-15
- 分支：`v1.13.9`
- HEAD：`6ec5ff7c67547637bbd55f528276422395e28c03`
- 方法版本：`MAIC-1.3`
- 工作包：`ZL02_研发档案/第一阶段-密钥库/调整与优化/v1.13.9-身份验证四档与主密码调整/`
- 输入：U2 版 `04` 第八节、`05` 第十二节、`00C`、U2-W2/10、当前设置/锁屏源码
- 批准来源：W0/07 记录 2026-09-15 用户原文「同意 U2 执行计划和检查计划」。本波未要求重复批准。
- 实际授权：U2-W2/10 通过后用户调用阶段4；只实施 U2-W3；不进 U2-W5；不覆盖旧 W3/01–02；不处理 `tools/`、xcodeproj、暂存、提交、上传。
- 保护 refs（未改）：`main` / `origin/main` = `539447ea9984608c74989da48b8770cb3fe32a6c`；`release/1.0.0` = `5c5eed3f8390f51f5a26be9737bcc11f72e7d7fd`
- 暂存区：空；单一 worktree

文末 `写入状态：已停止` 为交接用最终状态。

## 1. 入口核对

- 当前分支 `v1.13.9`，HEAD 仍为契约基线。
- U2-W0/08、U2-W2/10 通过。没有 U2-W3 报告，旧 W3/01–02 不能代替本修订。本文件为 `实施波次/W3/` 下一个连续奇数报告 `03`，配对将来是 `04`。
- 上一写入者：W2/10 已停止。未读取、未修改 `tools/`。未改 Vault/备份普通入口（属 U2-W5）。

## 2. 本波实际修改（均在 U2-W3 允许清单 ∩ `00C` 内）

| 文件 | 做什么 |
| --- | --- |
| `SessionLockQuerying.swift` | `AppPasswordSettingsRouting`：两种密码依赖档都进同一应用密码页并绑定原目标；首页管理行只看已 persist 的当前档；状态区分已设/未设/读取失败。 |
| `SettingsView.swift` | 选「应用密码」或「生物验证或应用密码」都进入同一页，进入不改当前档。未设走 `createAppPasswordMaterialThenPersist`（保存原目标，不再写死应用密码档）。已设切档走「保留现有密码并继续」。管理行三态。降低安全/清空不再顺手设密。 |
| `AppPrivacyController.swift` | 锁屏恢复接 `reset(expectedRevision:)`。锁屏普通入口不再设密。 |
| `AppLockCoverView.swift` | 组合档缺材料：生物识别仍可解锁；应用密码路径拒绝并提供独立恢复。 |
| `Localizable.xcstrings` | 设置页标题/状态改为「应用密码」；补读取失败、保留现有、部分成功文案。 |
| `SecurityPolicyChangeTests.swift` | 组合档未设/不可读不得 persist；选档路由与管理行可见性。 |
| `AppPrivacyControllerTests.swift` | 锁屏不设密；恢复不删别人刚改的新材料。 |

本波未改：`ContentView.swift`、`DurationSettingsViews.swift`、`FakePreferences.swift`、`AppLockSession.swift`、Vault/备份。未新增文件。

## 3. 生产调用链

1. 选档：`RevealPolicySettingsView.selectPolicy` → `AppPasswordSettingsRouting.destination`。密码依赖档只导航，不 persist。
2. 未设：`MasterPasswordSettingsView` → `AppEnvironment.createAppPasswordMaterialThenPersist(target:)`。当前方式确认 → 设备主人 → 写材料 → persist **原目标**。persist 失败保留材料，提示「应用密码已设置，验证方式未切换」。
3. 已设且不是当前档：`persistPasswordDependentPolicyKeepingMaterial`。已是当前档：只管理（改密/重置），不制造切换。
4. 首页管理行：仅 `masterPassword` / `biometryOrAppPassword` 已 persist 时显示。
5. 设置重置：仍走 `resetAppPasswordAndFallToDeviceAuth`（W2 已接条件删除）。
6. 锁屏忘记：`recoverFromLostMasterPassword` → 同一条件删除。组合档缺材料不 `setPassword`。

## 4. 测试证据

iPhone 17 Pro 模拟器，iOS 26.5，DerivedData `/tmp/ApiRelayAgentDD`，签名保留：

```text
AppLockSessionTests 29
AppPrivacyControllerTests 42
RevealGateCoordinatorTests 13
ScenePresenceSignalTests 3
WindowPrivacyReducerTests 4
SecurityPolicyChangeTests 11
SecuritySettingsPersistTests 6
MasterPasswordServiceTests 15
RevealGateTests 52
CatalystAdaptationTests 4
合计 179 passed / 0 failed
xcresult: /tmp/ApiRelayAgentDD/Logs/Test/Test-ApiRelay-2026.09.15_16-25-40-+0800.xcresult
```

本波要点：

- `testUnconfiguredAppPasswordCannotPersistAsPolicy`（含组合档未设/不可读、两种目标都进应用密码页、管理行显示条件）
- `testCombinationLockSetupDoesNotWritePassword`
- `testLockRecoveryDoesNotDeleteNewerMaterial`
- 既有忘记密码 persist 失败保留材料、不落到不验证

`git diff --check` 对本波文件通过。

```text
bash ApiRelay/scripts/selfcheck.sh
红线检查：全部通过
```

未重跑全量。本波模拟器结果不是平板/电脑运行证据，也不是真实系统弹窗手测。

## 5. 收尾四问

1. **外部资源：** 应用密码材料仍只在本机 `.masterpw`。锁屏恢复测试用 `FakeMasterPassword` + `FakePreferences`；其余恢复回归仍用 `KeychainStore.makeForTests()`。未打开 `xcodecloud/manifest.json`。
2. **失败路径：** 选档取消不改当前档。创建 persist 失败：材料保留、验证方式不切、提示部分成功。锁屏缺材料：生物识别仍可用，应用密码路径拒绝并给独立恢复。恢复过期：不删新材料；若设备验证档已保存则按部分成功处理，不落到不验证。
3. **接缝：** `AppPasswordSettingsRouting` 为纯函数，测试直接覆盖。锁屏恢复走与设置页同一材料服务实例的 `reset(expectedRevision:)`。`MasterPasswordServing` / `RevealGateServing` 仍有假实现。
4. **文件粒度：** `SettingsView.swift` 现 1828 行，已超过 400。本波只改设置状态机，不拆文件。`AppPrivacyController.swift` 895 行，同样超限，未拆。

## 6. 未验证 / 停止点

- 普通入口去掉延迟设密（Vault/备份/取用）：U2-W5。
- iPhone/iPad/Mac 选档与锁屏手测、双设备、旧验收阻塞、工程 manifest：U2-W6。
- 本波未在电脑或平板跑过界面。

## 7. 方法观察

锁屏旧恢复入口若继续无条件删除，设置页接上条件删除也闭环不了。本波把锁屏接到同一接口，并用 Fake 在取得排他权前改密，避免只测设置页协调器。

下一步负责人：Codex
是否需要用户批准：否
下一步：执行 `/Users/xitongzhili/Desktop/MacTransfer/08_Code/E02_ApiRelay_Github/ZL02_研发档案/第一阶段-密钥库/调整与优化/v1.13.9-身份验证四档与主密码调整/提示词/阶段4A-Codex波次审计.md`

写入状态：已停止
