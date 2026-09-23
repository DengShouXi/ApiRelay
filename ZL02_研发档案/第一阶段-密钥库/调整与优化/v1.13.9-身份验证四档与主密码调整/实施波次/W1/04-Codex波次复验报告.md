# 阶段4A：Codex波次复验报告（W1）

- 阶段：4A
- 波次：W1（复验 `03-Grok波次整改报告.md`）
- 时间：2026-09-15
- 分支：`v1.13.9`
- HEAD：`6ec5ff7c67547637bbd55f528276422395e28c03`
- 方法版本：`MAIC-1.3`
- 工作包：`ZL02_研发档案/第一阶段-密钥库/调整与优化/v1.13.9-身份验证四档与主密码调整/`
- 输入：修订并经用户批准的 `04-最终执行计划.md`、`05-最终检查计划.md`、`00C-任务契约.json`、`实施波次/W1/02-Codex波次审计报告.md`、`实施波次/W1/03-Grok波次整改报告.md`、实际 Git 差异与测试结果
- 实际授权：用户已明确批准修订后的 `04` 和 `05`，本次只读复验 W1，不修改被审计实现、不暂存、不提交、不上传

## 1. 入口与保护边界

- `03-Grok波次整改报告.md` 是 W1 最新奇数报告，文末声明 `写入状态：已停止`；本报告创建前不存在 W1/04。
- 当前仅有一个 worktree；当前分支和 HEAD 与契约基线一致；暂存区为空。
- `main`、`origin/main`、`release/1.0.0` 分别仍为契约登记的 `539447ea9984608c74989da48b8770cb3fe32a6c`、`539447ea9984608c74989da48b8770cb3fe32a6c`、`5c5eed3f8390f51f5a26be9737bcc11f72e7d7fd`。
- W1 的 20 个实际 Swift、测试和本地化差异全部位于修订后 W1 精确清单内；没有触碰 Keychain 策略、`tools/`、项目文件、main、tag 或远程。
- `git diff --check` 通过；项目自检红线全部通过。

## 2. 五个原阻塞复验

### W1-B01：跨波次编译接缝——已关闭

- 修订后的 W1 已精确授权 `RevealGate.swift`、`AppPrivacyController.swift`、`SettingsView.swift` 及必要本地化/测试接缝。
- `RevealGate` 对 `.biometryOrAppPassword` 直接返回 `combination_policy_not_ready`，没有调用 LocalAuthentication，不伪装设备验证、不做纯生物成功，也不回落不验证。
- `AppPrivacyController` 删除旧 `.biometricOnly` 分支；组合档只转入上述 fail-closed 接缝。
- 设置页已移除旧仅生物识别选项；W3 前没有开放新组合档选择行，仅能诚实显示已同步策略摘要。

### W1-B02：运行时四档——已关闭

- `RevealPolicy` 运行时恰有四个 case：设备验证、应用密码、生物验证或应用密码、不验证。
- 独立反搜生产和测试 Swift 代码，没有运行时 `.biometricOnly`、旧 case 或静态别名；旧字符串只由 `RevealPolicyPersistence.legacyBiometricOnlyRawValue` 在迁移层识别。
- `SecurityReviewTests` 对四个 case 的数量和集合都有明确断言。

### W1-B03：应用密码分波——已关闭

- 已删除名实不符的“未配置应用密码已就绪”测试。
- W1 只验证既有 `masterPassword` rawValue 被保留且不回落到 `none`；材料状态接口和首次选择保存闸门按修订计划分别留给 W2、W3，没有在 W1 冒充完成。

### W1-B04：旧库缺字段默认 true——已关闭

- 新测试先用不含 `revealAuthEnabled` 属性的旧 Core Data schema 写出真实旧商店，再用现行 SwiftData 模型打开。
- 旧行中的 `revealPolicy=none` 被保留，证明读取的是旧记录而非新建默认对象；新增字段读取结果为 `true`。
- Codex 独立复跑该迁移测试并通过。

### W1-B05：规范化保存失败——已关闭

- 规范化决策抽成可注入保存闭包的 `RevealPolicyCanonicalPersist.persistIfNeeded`，仓库实际规范化路径调用同一实现；失败后仓库恢复各副本的原 rawValue。
- 测试注入保存错误，验证旧值与未知值均不被假装写成规范值或 `none`，运行时保持设备验证；随后恢复保存可重试并规范化。
- Codex 独立复跑该失败与重试测试并通过。

## 3. W1其余停止条件

- 新建偏好默认为设备验证且 `revealAuthEnabled=true`。
- `none` 保持不验证；规范设备值稳定；旧 `biometricOnly` 幂等迁到设备验证；未知值 fail-closed；新组合值可往返；既有应用密码值保留。
- 多副本会一起规范化，重复加载不再产生变化。
- `SecurityPolicyChange` 已覆盖：从不验证加强无需按“降低”处理；关闭取用验证、切到不验证和三种有验证方式互换均按敏感变化处理。
- 新同步字段是模型加法；本波没有把应用密码材料加入同步数据，也没有修改 Keychain 实现。
- 测试名称与断言含义一致，没有把后续 W2/W3 功能包装成 W1 已完成。

## 4. 独立证据

- 独立解析 Grok 留下的 xcresult：iPhone 17 Pro、iOS 26.5，131 项通过、0 失败、0 跳过。
- Codex 使用独立 DerivedData 复跑 6 项关键测试：旧 schema 缺字段、规范化保存失败与重试、运行时四档集合、组合档 fail-closed、应用密码未设置失败及不验证不调用系统验证；6 项全部通过、0 失败。
- 项目自检红线通过；`git diff --check` 通过。

## 5. 阻塞问题

无。W1首次审计的五项阻塞均有实现、测试和独立复验证据。

## 6. 非阻塞建议

- 本地化资源仍保留三个未被代码引用的旧 `biometricOnly` 键。它们不会形成运行时选项或产品路牌，且修订后的 W1 对本地化文件只授权增加新摘要键，因此本波不要求越界清理；可在后续本地化清理波次按批准范围处理。

## 7. 未验证项

- 未运行 Mac Catalyst 开发证书测试。
- 未连接真实 CloudKit Production 旧记录；本波用真实旧 schema 本地商店验证兼容迁移，生产部署仍不在授权范围。
- 组合档完整验证、应用密码材料状态/恢复、首次选择保存闸门、三行设置和真实系统弹窗属于 W2—W6，W1不声称完成。

## 8. 方法观察

修订后的“计划缺陷先退回阶段3、用户批准后再由执行者整改”路由本次有效，避免了执行者自行扩权；未发现需要继续迭代的方法问题。

写入状态：已停止

波次审计通过，可以进入下一波。
