# 阶段4A：Codex波次复验（U2-W2第三轮）

- 阶段：4A
- 修订ID：U2
- 波次：W2
- 时间：2026-09-15
- 分支：`v1.13.9`
- HEAD：`6ec5ff7c67547637bbd55f528276422395e28c03`
- 方法版本：`MAIC-1.3`
- 输入：W2/09-Grok波次整改报告、W2/08复验报告、U2-W0/08、04第八节、05第十二节、阶段4A提示词及实际源码与测试
- 授权：用户调用阶段4A；只独立审计并新增本报告，不实施整改
- 写入状态：已停止

## 一、阶段恢复与保护边界

U2-W0已通过；W2/09为当前最早待办波次的最新奇数报告，01—09编号连续，审计开始时不存在10。09开头保留“未停止”的过程标记，但正文明确文末为最终交接状态，文末为“写入状态：已停止”；据此接收最终报告，不将过程标记误当仍在实施。

U2批准来源沿用W0/07，不能用旧U1通过替代本轮证据。实际核对HEAD、main/origin-main与release/1.0.0对象均符合契约；暂存区为空、只有当前一个worktree。git diff --check通过。

本次仅新增本报告。没有修改实现、业务测试、正式规格、tools、暂存区、Git历史、refs或远程。测试只产生临时测试产物和工具缓存。工作区仍包含以前多波累计修改，没有实施前逐文件快照，无法仅凭累计差异独立证明09自述的每项波次归因；本报告不宣称整个工作区只改了W2文件。

## 二、W2/08 B01关闭依据

### 1. 版本核对与删除进入同一受保护提交

真实生产调用为AppEnvironment.resetAppPasswordAndFallToDeviceAuth → AppPasswordRecovery带resetIfRevision的重载 → MasterPasswordService.reset(expectedRevision:)。

恢复请求保存开始版本；设备主人确认之后先校验版本，设备验证策略保存之后将开始版本直接交给条件删除。服务在同一个withExclusiveAccess/mutateMaterial边界内核对版本，再删除.masterpw。mutationInFlight在所有await期间保持为true，其他同实例set/change/reset不能插入成功变更；版本不符或忙碌时拒绝删除。因此08所指出“最后外部版本读取后另一次无条件reset删掉新密码”的生产环境接缝已修复，不是仅增加一次外部查询。

设备验证策略可能已保存而条件删除被拒，此时上抛stale_concurrent并保留新材料。属于已记录的部分成功，不宣称已全部恢复，也不落到不验证。

### 2. 保存密码依赖档期间保护材料

创建与保留已有密码的生产环境回调均将策略persist放入MasterPasswordService.withUnchangedSetMaterial(expectedRevision:perform:)。同一排他边界先核对版本、确认材料为set，再等待持久化完成；期间其他同实例材料变更被拒。该操作不递增材料版本，成功/失败均释放排他标记。

PreferencesService的persist使用串行写入链及成功/失败回调，没有反向调用密码变更服务形成上述租约的循环等待。材料已不存在、不可读、版本过期时不能通过此提交保存密码依赖档。两种目标masterPassword与biometryOrAppPassword均有对应测试。

### 3. 不超额宣称保护范围

无参reset及旧恢复重载仍存在；锁屏AppPrivacyController旧接线仍未获得条件删除保护，09已明确列为U2-W3，不将其冒充本波完成。保护依据是共用同一个密码服务实例，不是跨进程或跨设备的通用事务。本波不宣称全部UI调用点、多窗口生命周期或同步竞态已经闭环；这些继续按U2-W3/W5/W6验收。

## 三、独立测试与检查证据

- 独立读取Grok原始xcresult：`/tmp/ApiRelayAgentDD/Logs/Test/Test-ApiRelay-2026.09.15_16-00-09-+0800.xcresult`。摘要82通过、0失败、0跳过，iPhone 17 Pro、iOS26.5模拟器，与09数量一致。
- Codex另外实际复跑RevealGateTests与MasterPasswordServiceTests，保留模拟器签名，结果`/tmp/ApiRelayCodexW2Round3Audit.xcresult`。独立读取摘要：67通过、0失败、0跳过，测试命令退出0。复用编译缓存节省成本，但测试重新执行，不把Grok报告当作独立复跑。
- 核对真实服务测试testResetExpectedRevisionDoesNotDeleteAfterLaterChange、testSetMaterialLeaseBlocksResetInsideCommit；环境/协调器测试testRecoverDoesNotDeleteWhenMaterialChangesBeforeExclusiveReset、testRecoveryCommitUsesExpectedRevisionOnRealKeychain及两种目标的创建/保留lease测试。测试包含取得排他权前改密和持有lease期间尝试删除的边界，不仅是验证回调早期变化。
- 独立运行`bash ApiRelay/scripts/selfcheck.sh`退出0，红线检查全部通过。大文件与try?等报告不是本波阻塞，也不授权顺手重构。
- 本轮未重复全量测试、未进行真实设备黑盒验证。项目红线自检不是工作包范围/路由检查器，不据此声称全局范围检查已绿。

## 四、阻塞、非阻塞与未验证项

本波阻塞：无。W2/08 B01在上述限定引擎与环境接缝范围关闭。

非阻塞交接要求（已有U2范围，不另增产品决定）：

1. U2-W3必须将设置/锁屏实际生产入口接到安全协调接口，并核实共享服务实例、当前请求目标与取消/过期请求处理；不能在UI继续走旧无条件恢复却声称安全闭环。
2. 继续完成立即设置、已有密码管理、仅当前成功保存的密码依赖档显示管理行及部分失败提示；旧SecurityPolicyChangeTests断言必须按U2产品答案调整。
3. U2-W5处理普通业务入口不得延迟创建密码；U2-W6逐格完成iPhone/iPad/Mac与双设备证据。无数据线不等于豁免。
4. 工程manifest范围/来源问题及原W6阻塞仍保留至后续闸门；本次不读取其内容、不处理它，也不处理tools。

本报告通过的是U2-W2，不是App三端体验已修好，不恢复原W6验收，不进入4B、提交或上传。

## 五、方法观察与唯一下一步

本次确认的有效改进是：最后观察点和真正提交点之间的竞态，应由服务内条件提交保护，再用真实服务及环境接缝测试核对。先前结构阻塞明确时不重复全套昂贵测试；结构修复后复跑67项直接相关测试并复用82项已核实证据，质量优先且避免无关重测。本轮无需修改长期方法文件，保留此经验供同类并发交接使用。

下一步负责人：Grok

是否需要用户批准：否；沿用已批准U2范围，仍须用户调用下一提示词，不自动实施。计划外必要变更须先停止回阶段3。

下一待办波次：U2-W3。沿既有编号创建下一份U2奇数实施/整改报告，不覆盖旧报告，不重做已通过U2-W2。

下一步：执行 `/Users/xitongzhili/Desktop/MacTransfer/08_Code/E02_ApiRelay_Github/ZL02_研发档案/第一阶段-密钥库/调整与优化/v1.13.9-身份验证四档与主密码调整/提示词/阶段4-Grok执行下一波.md`

波次审计通过，可以进入下一波。
