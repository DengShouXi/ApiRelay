# 阶段4A：Codex波次复验（U2-W2）

- 阶段：4A
- 修订ID：U2
- 波次：W2
- 时间：2026-09-15
- 分支：`v1.13.9`
- HEAD：`6ec5ff7c67547637bbd55f528276422395e28c03`
- 方法版本：`MAIC-1.3`
- 输入：W2/05-Grok波次整改报告、U2-W0/08、04第八节、05第十二节、00C、真实源码与本波测试
- 授权：用户执行阶段4A；仅独立审计及新增本报告
- 写入状态：已停止

## 一、恢复与边界

U2-W0/08已通过；本轮待审为U2-W2/05，末尾写入已停止、批准来源引用W0/07的U2批准；W2/01—05连续且开始时不存在06。不审旧W6或覆盖旧报告。

HEAD、main/origin-main、release/1.0.0对象符合契约；暂存区空、只有一个worktree。只新增本报告；没有修改Swift、业务测试、规格、tools、工程、历史、分支或远程。独立测试/Swift验证使用临时产物和隔离替身，未访问真实密码。累计工作区差异仍含旧实施，缺少本波前快照，不以Grok声明替代逐波差异归因证据。

## 二、正确部分

- MasterPasswordService.materialStatus将找不到材料区分为unset、其他读取错误为unreadable，错误不再冒充未设。
- AppPasswordPolicyGate对masterPassword与biometryOrAppPassword均要求set；未设/不可读拒绝持久化。
- 创建协调器保留原目标，当前确认→设备主人→写入复查→persist，persist失败保留材料；已有材料路径不直接setPassword。
- 恢复保持设备主人→persist设备验证→删除本机材料，不回落none；普通RevealGate确认未新增设密。
- 现行引擎接缝在本波允许文件内。设置页三态接线、普通界面延迟设密移除和三端手测仍属于后续波次，不冒称已实现。

## 三、阻塞B01：等待验证后的材料检查过期

失败类型：普通整改

生产证据：`RevealGateServing.swift`第86—97行只在验证前检查unset，此后两个await完成就直接setAndVerifyMaterial；`AppEnvironment.swift`第242—244行回调直接master.setPassword，后者调用Keychain保存可覆盖现有材料。没有重新确认/共享并发保护，不能保证“已设不覆盖”。

Codex执行独立内存验证：从真实RevealGateServing.swift提取原样AppPasswordSetup代码（未复制改写算法），只补最小类型/材料状态替身。初始状态unset；在confirmCurrentIfNeeded回调模拟另一窗口把材料改为set；设备主人返回成功。实际输出：

```text
writes_after_other_window_set=1, target_persists=1
```

即协调器在材料已经变成set后仍调用写入与保存目标。此验证证明共享协调器接受过期状态，不是三端硬件攻击演示；结合生产回调可确认存在覆盖风险。不能推迟到W3只靠按钮isSaving解决跨窗口/恢复并发。

同类静态风险：persistExistingMaterialTarget第110—122行只在当前方式验证前确认set；等待期间材料被恢复/删除后仍persist密码依赖档。必须处理同一共享状态与提交边界，而非简单在UI多查一次。再查一次与真正防并发是不同保证，不得留下检查与写入之间的竞态。

限定整改要求：

1. 在U2-W2允许的共享协调/密码服务文件内安全协调创建、保留材料切档与恢复，拒绝已过期/并发变更；创建不能覆盖另一请求新设材料，保留材料切档不能在材料已消失/不可读后保存。
2. 不重写PBKDF2、不修改KeychainStore/accessibility/service/rawValue、不新增计划外文件，不使用none兜底。若安全方案必需计划外文件或产品改变，停止并回阶段3，不自行扩大范围。
3. 补生产接缝测试：两种目标；验证期间unset→set、unset→unreadable、set→unset/unreadable；并发创建/恢复、取消/验证失败、写入/复查/persist失败。断言不覆盖他人材料、过期请求不persist、旧策略/材料安全、无业务副作用，必要部分成功准确上抛。测试调用实际协调器，不用局部变量手动清零冒充。
4. 下一个W2奇数报告07标U2，引用B01并列实际文件、生产调用链、并发测试名及结果路径。整改后交阶段4A，不进入W3。

## 四、独立测试与证据局限

- Grok结果已通过xcresulttool独立核实：`/tmp/ApiRelayAgentDD/Logs/Test/Test-ApiRelay-2026.09.15_14-50-22-+0800.xcresult`，62通过/0失败/0跳过，iPhone17 Pro iOS26.5模拟器。现有绿未覆盖B01复现。
- Codex独立重跑RevealGateTests/MasterPasswordServiceTests：`/tmp/ApiRelayCodexU2W2Audit.xcresult`，49项，29通过/20失败，退出65。失败集中keychainFailure(-34018)，另材料三态预期unset却unreadable；本次命令使用CODE_SIGNING_ALLOWED=NO，很可能导致测试宿主缺Keychain entitlement。不能把该运行标通过，也不能将其直接归因产品算法错误。整改后应使用保留正常测试宿主签名/权限的模拟器配置重新独立运行，不能修改权限策略或吞掉失败来凑绿。
- 因B01已独立复现，停止重复昂贵全量运行；待修复后再测。内存竞态验证不依赖Keychain entitlement。
- `git diff --check`通过。旧SecurityPolicyChangeTests组合档缺材料允许断言明确列为W3修改项；本波未跑/未通过全量，不掩盖该已知依赖。
- 手机/平板/Mac系统交互、双设备与工程manifest范围问题仍未完成，继续保留至既定后续停止点，不提前消除。

## 五、方法观察与路由

方法观察：设密安全不能只看首次快照与串行成功顺序，必须覆盖await期间状态变更；独立测试运行也必须保留测试宿主Keychain权限，本次无签名运行属于验证配置问题，保留失败事实，不误报实现全绿或凭自述放行。

下一步负责人：Grok
是否需要用户批准：本波批准范围内整改无需重批，仍须用户调用；计划外必要变更须另回阶段3
下一步：执行 `/Users/xitongzhili/Desktop/MacTransfer/08_Code/E02_ApiRelay_Github/ZL02_研发档案/第一阶段-密钥库/调整与优化/v1.13.9-身份验证四档与主密码调整/提示词/阶段4-Grok执行下一波.md`

波次审计不通过，只能整改本波阻塞。
