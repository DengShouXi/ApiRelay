# 阶段4A：Codex波次复验（U2-W3 / U2-R1）

- 阶段：4A
- 修订ID：U2
- 计划修订：U2-R1
- 波次：W3
- 时间：2026-09-15
- 分支：`v1.13.9`
- HEAD：`6ec5ff7c67547637bbd55f528276422395e28c03`
- 方法版本：`MAIC-1.3`
- 输入：W3/07、W3/06、04第八节第五小节、05第十二节F及实际协调器、请求许可、材料服务、偏好服务与测试
- 授权：用户调用阶段4A；只新增本报告，不修改实现或计划
- 批准依据：W3/07记录2026-09-15用户“明确同意 U2-R1 的 04 和 05”，批准版本为U2-R1；不是沿用W0/07旧批准。本轮核对文件记录，未另行读取其他编辑器对话。
- 写入状态：已停止

## 一、恢复与保护

W3/07为最新待审奇数，01—07连续，开始时不存在08；文末明确已停止，开头未停止为报告声明的过程标记。06历史计划阻塞已被U2-R1覆盖，不据此反复回阶段3。

实际HEAD、main/origin-main（539447ea9984608c74989da48b8770cb3fe32a6c）、release/1.0.0对象（5c5eed3f8390f51f5a26be9737bcc11f72e7d7fd）未变；单一worktree、暂存空、git diff --check通过。本轮仅新增报告，未改实现、业务测试、规格、tools、工程、Git或远程。累计差异仍不等于实施前逐文件快照，不能完全独立归因本波所有修改。

## 二、已修部分与证据

- 页面与锁屏向生产环境传入同一请求上下文，设备主人确认后协调器再次授权；材料创建/预期版本删除在材料服务排他提交边界内授权，W3/06设备确认后失效仍写入的旧缺口已获得实际保护。
- lease授权与invalidate在同一同步锁下检查，请求ID递增，保存前台有效性；NSLock不跨await。DEBUG便捷环境重载被条件编译隔离，仍生成请求；生产环境入口必填request。
- 偏好persist新增队列出队授权和expectedCurrentPolicy检查，排队前失效/较早策略变化可拒绝。B01—B03修复保持，未将恢复改回自动解锁。
- 独立读取原始xcresult：`/tmp/ApiRelayAgentDD/Logs/Test/Test-ApiRelay-2026.09.15_17-34-28-+0800.xcresult`，186通过、0失败、0跳过；`/tmp/ApiRelayAgentDD/Logs/Test/Test-ApiRelay-2026.09.15_17-36-13-+0800.xcresult`，29通过、0失败、0跳过。均为iPhone17 Pro iOS26.5模拟器，与07自述一致。不是三端手测。

## 三、B04残余阻塞：当前策略条件检查与实际写入仍分离

失败类型：普通整改

PreferencesService.persist实际顺序：出队authorize → await load得到当前策略 → 比较expectedCurrentPolicy → 再await authorizing → 另一次await update(patch)。最后授权回调只核对页面lease，没有把策略比较与仓库写入放入同一条件提交。load/update内部又跨userRepo/deviceRepo await；SerialWriteChain只串行本链persist，不排他直接update或其他写入来源。

因此读取旧策略并比较成功后，另一更新可先修改策略；旧请求仍凭有效页面lease调用无条件update覆盖新值。07新增testQueuedPersistRejectsWhenOpenedPolicyAlreadyChanged覆盖的是前一个排队写入完成后、读取时已经不同，不覆盖“读取完成与真正提交之间”的变化。lease上授权/invalidate的线性化只解决页面请求取消竞争，不能代替存储当前策略的条件提交。

### Codex独立生产原码边界验证

原样提取实际PreferencesService.persist及SerialWriteChain，置于最小Swift actor服务替身（load/update仅存内存）中执行。初始masterPassword，旧请求目标biometryOrAppPassword、expected为masterPassword；第二次authorizing回调注入另一请求先update为noVerification，模拟读取/比较后、真正写入前的外部变化，页面许可保持有效。实际persist仍成功写回旧目标，输出：

```text
final_policy=biometryOrAppPassword, writes=2
exit=0
```

预期旧请求应拒绝覆盖另一更新，最终保留noVerification。此验证复用生产队列/提交控制流，不是完整SwiftData或CloudKit跨设备黑盒测试；生产无条件update与条件观察分离的结构缺口和输出一致。

### 限定整改

1. 在实际存储提交接缝保障“核对打开时策略/代际 + 条件写入”的一致顺序，不只再加一次外部load，也不能声称所有写入都经过本SerialWriteChain。盘点本地直接update与同步变化的实际来源，明确哪些可在比较后插入。
2. 保留请求取消许可及W2材料版本/排他保护；请求许可和策略条件是两种保证。不能靠页面异步onChange或与target相同时不失效的处理充当最终策略检查。失效先于提交许可则该步不写；提交已开始允许完成但必须如实说明，不能把外部旧快照包装成不可撤销许可。
3. 为上述最后比较后/实际提交前窗口增加生产接缝可重复失败测试，两种目标均覆盖，断言旧请求拒绝、新策略保留、无旧业务副作用；复验已提交不盲回退、材料已写而策略拒绝的部分结果及恢复保持锁定。
4. 按U2-R1现有允许文件先设计最小修复。PreferencesService已获批准，故当前是普通整改，不重修计划；若必须进入未批准仓库/模型路径或改变同步/产品语义，则实施者先停止回阶段3，不擅自扩权。
5. 只整改W3本阻塞，生成连续W3/09-Grok波次整改报告，标U2及U2-R1、引用本报告；完成停止交4A配对10，不进入W5、提交或上传。

## 四、未验证与方法观察

没有因确定的提交结构阻塞再次重复昂贵全量测试；保留已核实186+29结果，新增上述独立边界验证。本轮没有运行全局工作链范围检查器，不宣称全局已绿。三端系统验证/导航、多窗、双设备、普通入口U2-W5及原W6/02闸门仍未完成；工程manifest问题保留，不读取处理它或tools。

非阻塞建议：无新增必须优化项，不扩展无限整改。

方法观察：请求许可线性化不等于偏好条件提交线性化；检查器/测试应覆盖最后观察之后的更新，而不只覆盖排队期间较早变化。已批准接缝范围内明确缺陷交Grok最小整改，必要越界才再回计划，避免无谓重复规划。

下一步负责人：Grok

是否需要用户批准：否；沿用U2-R1已批准范围，仍须用户调用下一提示词；必要计划外路径先停止。

下一步：执行 `/Users/xitongzhili/Desktop/MacTransfer/08_Code/E02_ApiRelay_Github/ZL02_研发档案/第一阶段-密钥库/调整与优化/v1.13.9-身份验证四档与主密码调整/提示词/阶段4-Grok执行下一波.md`

波次审计不通过，只能整改本波阻塞。
