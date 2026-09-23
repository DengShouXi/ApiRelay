# 阶段4：Grok波次整改报告（U2-W2）

写入状态：未停止

- 阶段：4
- 修订ID：U2
- 波次：U2-W2（验证引擎：材料三态、两种目标保存闸门、设备主人设密与恢复接缝）
- 时间：2026-09-15
- 分支：`v1.13.9`
- HEAD：`6ec5ff7c67547637bbd55f528276422395e28c03`
- 方法版本：`MAIC-1.3`
- 工作包：`ZL02_研发档案/第一阶段-密钥库/调整与优化/v1.13.9-身份验证四档与主密码调整/`
- 输入：U2 版 `04` 第八节、`05` 第十二节、`00C`、W0/07–08、当前引擎源码与既有 W2 测试
- 批准来源：W0/07 记录 2026-09-15 用户原文「同意 U2 执行计划和检查计划」。本波未要求重复批准。
- 实际授权：U2 链 W0 已通过；本波只改原 W2 列明文件 + SessionLockQuerying / AppEnvironment / FakeSupport（后者本波无新改）；不进 U2-W3；不覆盖旧 W2/01–04；不处理 `tools/`、xcodeproj、暂存、提交、上传。
- 保护 refs（未改）：`main` / `origin/main` = `539447ea9984608c74989da48b8770cb3fe32a6c`；`release/1.0.0` = `5c5eed3f8390f51f5a26be9737bcc11f72e7d7fd`
- 暂存区：空；单一 worktree

文末 `写入状态：已停止` 为交接用最终状态。

## 1. 入口核对

- 当前分支 `v1.13.9`，HEAD 仍为契约基线。
- U2-W0/08 通过，最早待办是 W2。旧 W2/04 通过不代替 U2-W2。
- 本文件为 `实施波次/W2/` 下一个连续奇数报告 `05`，配对将来是 `06`，不覆盖 01–04。
- 上一写入者：W0/08 已停止。

## 2. 本波实际修改（均在原 W2 + U2-W2 增列 ∩ `00C` 内）

| 文件 | 做什么 |
| --- | --- |
| `RevealGateServing.swift` | `AppPasswordMaterialStatus` 三态；`appPasswordMaterialStatus()`；`AppPasswordSetup` 创建/已设 persist 协调 |
| `RevealGate.swift` | 转发材料三态 |
| `MasterPasswordService.swift` | `materialStatus()`：找不到=未设，其他 Keychain 错=不可读；不重写 PBKDF2 |
| `SessionLockQuerying.swift` | `AppPasswordPolicyGate`：应用密码档与组合档都要材料已设才能 persist；不可读不得 persist |
| `AppEnvironment.swift` | `createAppPasswordMaterialThenPersist`（设备主人→写入复查→persist 原目标）；`persistPasswordDependentPolicyKeepingMaterial`（已设不 `setPassword`）；恢复入口保持设备主人→persist 设备验证→再删材料 |
| `FakeMasterPassword.swift` / `FakeRevealGate.swift` | 三态与故障注入 |
| `RevealGateTests.swift` / `MasterPasswordServiceTests.swift` / `SecurityReviewTests.swift` / `CatalystAdaptationTests.swift` | 闸门矩阵、创建顺序、目标绑定、persist 失败留材料、已设不覆盖、普通 confirm 不设密 |

本波未改：`ApiRelayError.swift`、`FakeSupport.swift`（无新错误枚举、无新假实现原语）。未改设置页 / 锁屏 / Vault 普通入口。未改 PBKDF2 与 KeychainStore。

## 3. 回写的现行引擎行为

- 材料三态：`unset` / `set` / `unreadable`。读取失败不是未设，不得覆盖。
- 两种目标 `.masterPassword` 与 `.biometryOrAppPassword` 未设或不可读时均不得 persist 为当前档。
- 未设创建：调用方注入的当前方式确认 → `confirmMandatory`（设备主人）→ `setPassword` 并复查 → persist **传入的原目标**（组合档不会被写成应用密码档）。
- 已设：只走当前方式确认后 persist；`setPassword` 次数为 0。
- persist 失败：材料保留、旧档不变、错误上抛。
- 日常改密仍校验旧密码；错旧密码不覆盖。
- 普通 `confirm` 不 `setPassword`。组合档取消仍不回落设备密码。恢复顺序仍是设备主人 → persist 设备验证 → 再删 `.masterpw`。

## 4. 测试证据

iPhone 17 Pro 模拟器，iOS 26.5，DerivedData `/tmp/ApiRelayAgentDD`，本波测试类：

```text
RevealGateTests 39
MasterPasswordServiceTests 10
SecurityReviewTests 9
CatalystAdaptationTests 4
合计 62 passed / 0 failed
xcresult: /tmp/ApiRelayAgentDD/Logs/Test/Test-ApiRelay-2026.09.15_14-50-22-+0800.xcresult
```

`git diff --check` 对本波文件通过。

```text
bash ApiRelay/scripts/selfcheck.sh
红线检查：全部通过
```

未重跑全量 372。旧 358 绿不是 U2 实现证据。

## 5. 收尾四问

1. **外部资源：** 应用密码材料仍只在本机 `.masterpw`。测试用 `KeychainStore.makeForTests()`、内存假钥匙串、`FakeMasterPassword`。恢复仍不得碰 `.keys` / `.admin` / `.backuppw`（既有测试保留）。未打开 `xcodecloud/manifest.json`。
2. **失败路径：** 读取失败显示为不可读，不能当未设去覆盖。取消设备主人不写密码、不切档。Keychain 已写但策略没存上：密码在、档位旧、错误可重试。设置页仍可能用 `try? isAppPasswordMaterialSet() ?? false` 把读取失败当成未设——那是下一波界面接线，本波已提供三态接缝。
3. **接缝：** `MasterPasswordServing.materialStatus`、`RevealGateServing.appPasswordMaterialStatus`、`AppPasswordSetup`、`AppEnvironment` 两个协调入口均有假实现或故障注入测试。
4. **文件粒度：** `RevealGateTests.swift` 现约 721 行，已超过 400。本波只加测试，不拆文件。

## 6. 未验证 / 停止点

- 设置页、锁屏、选档导航、首页「应用密码」行：U2-W3。
- 普通入口去掉延迟设密：U2-W5。
- 三端手测、双设备、旧验收阻塞、工程 manifest：U2-W6。本波模拟器测试不是电脑/平板运行证据。
- `SecurityPolicyChangeTests.testUnconfiguredAppPasswordCannotPersistAsPolicy` 仍按旧规则断言「组合档未设密也可 persist」。该文件属 U2-W3 清单，本波未改。U2-W3 须把那两处断言改成与现行闸门一致。本波引擎测试不依赖该文件。

## 7. 方法观察

两种目标闸门改在共享 `AppPasswordPolicyGate` 后，旧设置测试会立刻暴露 U1「组合档可未设密保存」。按清单不改 W3 测试文件，把失败记给下一波，避免本波扩大范围。

下一步负责人：Codex
是否需要用户批准：否
下一步：执行 `/Users/xitongzhili/Desktop/MacTransfer/08_Code/E02_ApiRelay_Github/ZL02_研发档案/第一阶段-密钥库/调整与优化/v1.13.9-身份验证四档与主密码调整/提示词/阶段4A-Codex波次审计.md`

写入状态：已停止
