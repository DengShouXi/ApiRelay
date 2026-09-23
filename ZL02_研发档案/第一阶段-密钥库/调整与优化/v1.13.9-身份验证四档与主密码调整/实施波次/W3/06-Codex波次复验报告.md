# 阶段4A：Codex波次复验（U2-W3第一轮整改）

- 阶段：4A
- 修订ID：U2
- 波次：W3
- 时间：2026-09-15
- 分支：`v1.13.9`
- HEAD：`6ec5ff7c67547637bbd55f528276422395e28c03`
- 方法版本：`MAIC-1.3`
- 输入：W3/05、W3/04、U2-W2/10、04第八节、05第十二节、阶段4A提示词及实际源码/测试
- 授权：用户调用阶段4A；只新增审计报告，不修计划或实现
- 写入状态：已停止

## 一、恢复与保护

W3/05是当前最早待办的最新U2奇数报告；01—05连续，开始时不存在06。05声明以文末“写入状态：已停止”为最终交接状态，已核对。沿用W0/07的U2批准，不以旧版通过替代本轮。

实际HEAD、main/origin-main（539447ea9984608c74989da48b8770cb3fe32a6c）、release/1.0.0对象（5c5eed3f8390f51f5a26be9737bcc11f72e7d7fd）未变；暂存空、单一worktree、git diff --check通过。本轮没有修改实现、业务测试、规格、tools、Git或远程。独立内存验证只生成临时编译缓存，无真实密码/CloudKit访问。累计工作区差异仍不能证明逐文件波次归因。

## 二、已解决部分与核实证据

- B01：实际页面将旧密码确认和改新密码分开；当前master切combo已有输入框，当前combo切master有纯生物/显式应用密码两种继续入口；已设非当前档也可改密。AppPasswordSettingsFlow接现行验证接口，没有偷偷回落设备密码。
- B02：AppPasswordPageSurface.showsRecover在材料查询完成后对unset/set/unreadable均成立，页面实际连接既有设备主人恢复；加载状态不再默认冒充unset。
- B03：recoverFromLostMasterPassword不再调用finishUnlockSucceeded；成功/部分成功同步实际偏好和材料状态，保持锁定。错误分支保留unlockError，旧恢复后自动解锁断言已调整。
- B04部分改进：页面有请求代际、防重入、离屏/scenePhase/策略变更回调及确认前后检查，失效后不弹成功；但这不是整个写入流程已经受控，见下节。
- 独立读取`/tmp/ApiRelayAgentDD/Logs/Test/Test-ApiRelay-2026.09.15_16-55-16-+0800.xcresult`：192通过、0失败、0跳过，iPhone17 Pro iOS26.5模拟器。结果真实，不等于新增遗漏窗口已覆盖。

## 三、B04仍阻塞：失效保护未覆盖设备主人验证之后的写入

失败类型：计划修订

### 生产依据

SettingsView.makeConfirmCurrent仅在“当前方式确认”前后检查lease。创建设密之后转入AppEnvironment.createAppPasswordMaterialThenPersist，内部依次执行设备主人验证、材料写入/复查、材料租约内persist；这些回调没有页面请求新鲜度参数，也没有设备主人验证结束后的同请求失效检查。reset同样只在进入恢复前检查，设备主人验证之后的persist/条件删除没有接收页面lease。

abandonPageRequest使lease失效并调用cancelCurrentAuthentication，但取消系统验证不是事务取消保证：系统验证若已成功返回，旧请求仍可在恢复调度之后继续调用setPassword/persist。finishPageRequest只抑制成功提示，无法阻止过期请求写入。05末尾已承认未修改AppEnvironment；“不倒转已落盘事务”不能豁免尚未开始的写入在失效后继续执行。

### 独立边界验证

直接读取并原样提取生产AppPasswordSetup和AppPasswordPageLease，在Swift内存程序中补最小类型与actor材料/策略替身。当前确认回调按页面做前后lease检查并成功；设备主人回调在返回时使lease失效（模拟成功验证返回与后续写入之间退出页面的调度窗口）；材料仍unset，随后生产协调器继续写入并persist。输出：

```text
writes_after_invalidation=1, persists_after_invalidation=1
page_request_fresh=false
exit=0
```

这是生产协调器的可重复控制流验证，不是物理设备系统验证攻击测试。它证明请求失效信息没有传入后半段；W2材料保护仍有效，但材料未被他人修改时不会拦截过期页面请求。

现有testKeepExistingInvalidatedDuringConfirmDoesNotPersist只在当前确认期间失效；testCommittedKeepExistingRemainsAfterLaterInvalidation是在persist完成后才失效。它们分别覆盖较早/较晚窗口，不能证明设备主人成功后、写入/策略提交前失效安全。

### 为什么回计划而不是继续让Grok盲改

U2-W3精确范围未包含AppEnvironment/RevealGateServing的创建设密与恢复提交接缝。当前缺口跨页面与该接缝，05也明确因范围没有改它。按阶段4A规则，安全停止点缺少必要提交依赖时应回阶段3；不能临场将“页面增加lease”当作已解决，也不能让Grok以编译接缝扩权。

阶段3应限定修订当前工作包04/05及对应提示词：明确请求失效如何贯穿当前确认、设备主人确认、材料创建、策略保存、恢复条件删除，以及哪些准确文件属于必要实施/检查范围。无需重做已通过B01—B03或改产品四档。明确不可取消提交的开始边界与部分结果；不得仅再加外部查询却宣称原子提交。新增边界测试至少覆盖设备主人成功返回后失效、恢复确认后失效、等待材料/偏好提交时失效、另一窗口改策略及已经提交后不盲目回退。修订后等待用户批准，不在本阶段实施。

## 四、未验证、非阻塞与方法观察

未验证：三端真实页面/系统弹窗、iPad分栏、Mac多窗、双设备同步、U2-W5普通入口及原W6阻塞。manifest范围问题仍保留，本轮不处理它或tools；没有运行全局工作链范围检查器，不声称全局已绿。

非阻塞：旧测试名称仍有UnlocksAfterDeviceOwnerAuth但断言已改为保持锁定，后续可在合法范围改名以免误导，不为此另开整改。

方法观察：此次遗漏不是“更多测试数量”，而是停止条件与精确范围没把请求身份贯穿到真正提交接缝。已证实结构阻塞后不再重跑昂贵全量；保留192项真实结果，追加生产原码内存边界验证并回计划一次性补足依赖。不得自动改长期治理或递归追求完美。

下一步负责人：Codex

是否需要用户批准：需要用户先调用修订提示词；修订04/05后仍须批准新版才允许Grok实施。

下一步：执行 `/Users/xitongzhili/Desktop/MacTransfer/08_Code/E02_ApiRelay_Github/ZL02_研发档案/第一阶段-密钥库/调整与优化/v1.13.9-身份验证四档与主密码调整/提示词/阶段3-Codex确定最终计划.md`

波次审计不通过，只能整改本波阻塞。
