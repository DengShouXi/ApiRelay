# 阶段4A：Codex波次复验（U2-W2第二轮）

- 阶段：4A
- 修订ID：U2
- 波次：W2
- 时间：2026-09-15
- 分支：`v1.13.9`
- HEAD：`6ec5ff7c67547637bbd55f528276422395e28c03`
- 方法版本：`MAIC-1.3`
- 输入：W2/07-Grok波次整改报告、W2/06审计、U2-W0/08、04第八节、05第十二节、00C及实际生产源码
- 授权：用户调用阶段4A；只独立审计并新增本报告
- 写入状态：已停止

## 一、恢复与保护边界

U2-W0已通过，U2-W2/07是当前待审奇数，末尾写入已停止；编号01—07连续，开始审计时不存在08。批准来源沿用同版U2记录，不沿用旧U1。HEAD、main/origin-main、release/1.0.0对象符合契约；暂存空、只有一个worktree。

本轮只新增本报告，不修改实现、测试、规格、tools、工程、Git历史/refs或远程。测试摘要与Swift验证仅使用工具临时缓存和隔离内存替身，不读取真实密码。累计工作区差异仍不能替代实施前快照来证明每项波次归因。

## 二、已修复部分与测试证据

- 创建协调器在当前确认、设备主人确认后重新查询材料；MasterPasswordService.setPassword经同actor mutationInFlight排他检查，只在unset时写入，已设/不可读拒绝。原“验证期间别人设好后直接覆盖”的路径已得到保护。
- changePassword仍先校验旧密码；set/change/reset成功后递增本服务revision；恢复在确认后、persist后比较revision。
- 已设切档在确认后重读set；新增故障注入与并发测试调用实际协调器或真实密码服务接缝。
- 独立读取xcresult摘要：`/tmp/ApiRelayAgentDD/Logs/Test/Test-ApiRelay-2026.09.15_15-22-54-+0800.xcresult`，76通过、0失败、0跳过，iPhone17 Pro iOS26.5模拟器。结果可核实，不等于所有提交竞态已经覆盖。
- git diff --check通过。没有因已确认结构阻塞再重复整套昂贵测试；本轮追加下述独立生产代码边界验证。

## 三、B01尚未完全关闭：版本比较与删除仍非同一原子动作

失败类型：普通整改

真实生产链：AppPasswordRecovery在persist之后await materialRevision、比较startRevision，然后另一次await resetMaterial；环境回调调用无expectedRevision参数的master.reset。MasterPasswordService.reset虽然有mutationInFlight，但只排他本次删除，没有在这次排他动作内比较恢复请求持有的版本。

因此最后一次查询读到旧版本之后，另一请求可成功changePassword并递增revision，再由旧恢复请求进入reset删除新材料。请求互相不同时处于mutationInFlight，并不代表旧请求仍有权删新版本。报告所谓CAS仅是同服务实例内的创建排他检查，不是“版本比较+删除”已原子化的证据。

Codex独立内存验证：直接从真实RevealGateServing.swift提取原样AppPasswordRecovery恢复函数和版本比较实现，补最小类型/actor材料替身。第一次读取版本0；确认和persist成功；第三次读取记录版本0快照后注入另一请求写新材料并变为版本1，返回旧快照（模拟读取完成与删除提交之间的调度窗口）。恢复仍调用reset，输出：

```text
newer_material_retained=false, resets=1, revision=2
```

这证明协调器允许在最后观察点与真正提交删除之间消费过期快照。不是物理设备攻击测试；生产reset不校验预期版本这一缺口与替身验证一致。已有testRecoverDoesNotDeleteNewerMaterialFromOtherWindow/testRecoverSkipsResetWhenRevisionChangesDuringPersist覆盖的是较早变更，未覆盖最后检查之后的变更。

### 限定整改与停止点

1. 将恢复的预期版本核对与条件删除放到同一个共享材料服务的排他提交边界内；不能仅再加一次外部revision查询。任何不匹配/忙碌/过期请求必须拒绝删除他人新材料，并准确上抛部分成功（设备策略可能已保存）。内部接口适配在现有U2-W2允许文件内完成，不改算法/Keychain策略、rawValue或新增文件。
2. 同步检查创建/保留材料切档的最后材料查询与persist之间是否仍允许另一恢复删除材料后保存密码依赖档；对于原B01要求的提交竞态必须提供共享协调/提交边界证据，不能把“每次await之后再查”当作全部原子保证。若安全方案必需计划外路径或新产品决定，先停止回阶段3，不擅自扩权。
3. 新测试必须准确注入最后一次revision读取完成后、reset真正取得材料变更排他权前的变更，断言新材料保留、旧请求失败；同时覆盖真实MasterPasswordService/环境接缝，不能只测协调器前半段。对最后材料检查与策略保存边界补提交竞态用例，两种目标都覆盖，失败/取消零业务副作用，部分成功如实记录。
4. 锁屏旧调用默认revision=0暂属W3接线，但不得把它声明为恢复已具备版本保护；W3必须接同一安全条件恢复接口。不得为编译而新增一个静默绕过保护的新入口。需修改W3文件才能安全编译则先修计划。
5. Grok只修本波B01，生成W2/09连续奇数报告，标U2并引用本报告；修后停止交阶段4A。不要进入W3、提交或上传。

## 四、仍未验证与方法观察

本波没有完成设置/锁屏导航、界面显示条件、普通界面去除延迟设密或三端硬件测试；它们继续按W3/W5/W6处理。工程manifest范围问题、原W6人工/双设备闸门保留，不借目标测试绿宣布整体验收。

方法观察：并发测试应以“最后观察与真正提交之间”而非仅系统验证回调为注入点；排他变更与带预期版本的条件提交是不同保证。本轮保留76项真实通过证据，只增加已证实遗漏的边界测试，不重新制造无关优化或修改长期治理方法。

下一步负责人：Grok
是否需要用户批准：同版本波范围内普通整改无需重批，仍须用户调用；计划外必要变更先回阶段3
下一步：执行 `/Users/xitongzhili/Desktop/MacTransfer/08_Code/E02_ApiRelay_Github/ZL02_研发档案/第一阶段-密钥库/调整与优化/v1.13.9-身份验证四档与主密码调整/提示词/阶段4-Grok执行下一波.md`

波次审计不通过，只能整改本波阻塞。
