# 阶段4A：Codex波次审计报告（W1）

- 阶段：4A
- 波次：W1（数据模型、默认值与幂等迁移）
- 日期：2026-09-14
- 分支：`v1.13.9`
- 基线 HEAD：`6ec5ff7c67547637bbd55f528276422395e28c03`
- 方法版本：`MAIC-1.3`
- 审计对象：`01-Grok实施报告.md`及当前工作区实际差异
- 审计性质：独立只读审计；除本报告外未修改任何文件

## 1. 接管条件

- W0最新偶数报告`04-Codex波次复验报告.md`明确通过，W1前置成立。
- W1最新奇数报告`01-Grok实施报告.md`末行是`写入状态：已停止`，Grok已经停止写入。
- 报告中的阶段、波次、分支、HEAD、方法版本和输入匹配；审计前W1目录不存在偶数报告。
- 当前分支仍是`v1.13.9`，HEAD仍为基线；暂存区为空；只有一个worktree。
- `main`、`origin/main`、`release/1.0.0`仍为契约保护值；未提交、未上传。

## 2. 已通过的证据

- 独立复跑`ApiRelay/scripts/selfcheck.sh`，红线检查通过。
- 独立复跑`git diff --check`，退出码为0且无输出。
- Grok留下的xcresult可读取：测试动作状态为`succeeded`，测试数66，测试失败摘要0；覆盖其报告列出的五个W1测试类。
- 新建偏好默认设备验证和`revealAuthEnabled=true`、`none`保留、旧`biometricOnly`规范化、未知值运行时fail-closed、重复加载和多副本同值迁移、取用开关patch、三种有验证方式互换判为敏感切换，均有对应实现和普通成功路径测试。
- 没有修改Keychain策略、Xcode工程、`main`、tag或暂存区；本审计未读取或修改`tools/`。

## 3. 阻塞问题

### W1-B01：三个计划外生产文件已经被修改

W1精确清单之外新增了以下生产差异：

- `ApiRelay/ApiRelay/Business/Vault/RevealGate.swift`（W2范围）
- `ApiRelay/ApiRelay/App/AppPrivacyController.swift`（W3范围）
- `ApiRelay/ApiRelay/UI/Settings/SettingsView.swift`（W3/W5范围）

这些修改不仅是声明补齐：`RevealGate`已经给组合档落了临时纯生物行为，`AppPrivacyController`已经接入组合档解锁，`SettingsView`把组合档暂时显示成设备验证短名。最终计划第四节明确规定，任何计划外必要文件都必须停止、退回Codex修订计划并重新取得用户批准。全局任务契约允许未来修改这些文件，不能替代W1的精确波次授权。

现有W1计划确有依赖缺口：新增/替换枚举档位会迫使现有穷举分支同步编译。因此不能让Grok在原计划下自批这三处，也不能简单删掉后带着不可编译状态放行；必须先由Codex修订W1精确范围和“仅编译接缝”的行为边界，再由用户批准。

### W1-B02：运行时`RevealPolicy`仍是五个枚举case，不符合四档正式合同

`RevealPolicy`当前同时保留：

- `biometricOrPasscode`
- `biometricOnly`
- `masterPassword`
- `biometryOrAppPassword`
- `noVerification`

另设`selectableCases`过滤旧档，只解决了界面候选集合，没有实现W0合同和W1计划要求的“四档规范枚举；旧值只在解码/迁移层识别”。现有`SecurityReviewTests.testRevealPolicySingleSwitchSemantics`要求`allCases.count == 4`，当前已知会失败。

整改方向应由修订计划明确：`biometricOnly`只作为旧raw字符串被迁移，不继续作为现行运行时枚举case；不得通过修改安全测试把五档合理化。

### W1-B03：“未配置应用密码不得写成有效档”没有实现，也没有对应测试

W1停止点要求：首次选择应用密码时，未配置状态不得写成有效档。新增的`testUnconfiguredMasterPasswordMustNotCountAsReady`只断言`masterPassword`能被解析并保持原rawValue，既没有注入`MasterPasswordServing`状态，也没有执行“未配置时尝试选择”的保存路径。

Grok报告也明确承认数据层仍接受该patch，并把真正拦截留给W2/W3。因此当前测试名称与证据不相符，W1停止点尚未满足。由于W1清单没有提供检查本机密码材料所需接缝，这也是计划分波缺口；修订计划应明确将该闸门放到哪一波、由哪个服务负责及在哪个波次成为阻塞证据。

### W1-B04：既有同步记录“缺字段默认true”没有被真实验证

`testMissingRevealAuthEnabledTreatsAsTrue`和`CloudSyncTests.testSyncedUserPreferencesAddsRevealAuthEnabledWithoutReplacingRevealPolicy`都在当前模型下新建`UserPreferences`，只能证明新对象默认true，不能证明升级前本地库或CloudKit旧记录缺少该字段时会得到true。

该字段控制取用保护且默认错误会直接降低安全，不能用同版本新对象代替迁移证据。W1必须增加能代表旧schema/缺字段记录的迁移或兼容性测试；真实CloudKit Production部署仍不属于本任务。

### W1-B05：规范化持久化失败路径没有测试

`persistCanonicalRevealPolicies`捕获`modelContext.save()`失败并恢复原rawValue，但没有测试能触发该catch。现有`SecuritySettingsPersistTests`只覆盖用户设置更新失败，不覆盖旧值/未知值规范化保存失败。

最终计划W1停止点明确要求“persist失败”测试通过，检查计划也要求失败时原安全状态不变。仅阅读catch代码不足以证明。需要可注入的保存失败证据，并断言：运行时仍按设备验证保护、原rawValue没有被误写为`none`、第二次恢复后可重试规范化。

## 4. 非阻塞建议

- `DTOs.swift`已超过自检建议的400行，但本轮拆分会扩大高风险迁移范围；保持为后续独立重构候选，不作为本波整改内容。
- W2清单中的`SecurityReviewTests`当前已知会因五case失败；修正W1-B02后应恢复该测试原意，而不是先扩大执行全量W2。

## 5. 未验证项

- Codex尝试独立重跑同一模拟器测试，但当前执行环境无法连接CoreSimulatorService，未找到指定模拟器；这是审计环境限制，不记作产品测试失败。已独立读取Grok留下的xcresult确认66项成功。
- Mac Catalyst测试仍因开发证书要求未运行；共享scheme全量测试未运行。W1-B02已经提供一个确定的已知全量失败项。
- 真机、双设备CloudKit、组合档行为、三行设置和运行时恢复属于后续波次，不能在W1声称完成。

## 6. 方法观察

- 本轮暴露出计划把“新增规范枚举”放在W1，却把所有受其穷举影响的生产文件放到W2/W3；同时把“未配置应用密码闸门”列为W1停止点，却没有给W1相应依赖。这是会造成执行者越界和重复返工的计划缺陷。
- 现有阶段4A固定路由把所有失败都送回Grok，但本次按`04`与操作台规则必须先由Codex修订计划并重新取得用户批准。不得直接再次调用原阶段4提示词让Grok自行决定扩范围。

波次审计不通过，只能整改本波阻塞。
