# Contract Draft: Legacy Migration and Rollback

**Status**: G3 草案；不授权读取、迁移或删除真实数据

## 1. 核心原则

1. 先关账 v1.13.9，再完成“不改功能”的 v1.13.10 结构稳定化；最终关账的 v1.13.10 是唯一迁移输入基线。
2. 旧 SwiftData/CloudKit 与 synchronizable Keychain 在 shadow 阶段仍是权威。
3. 先复制、再逐条核对、再切换；旧明文最后才删。
4. 所有迁移步骤幂等、有 stable migration ID、有持久 checkpoint。
5. 缺明文、孤儿、重复、损坏和并发写必须显式分类，不能用空值凑成功。
6. control manifest 接受 controlled-primary cutover 前可以回 legacy；该全局不可回退点之后默认只能前滚，与某一台设备是否已产生本机新写无关。
7. UI/业务层只能通过统一服务读写，不得自己做 legacy/new 双读。

## 2. 前置闸门

- v1.13.9 已冻结、测试、授权上传、远端复核并关账；
- v1.13.10 已按 `release-sequence.md` 完成结构稳定化、真正 XCUITest、三平台/真机、授权上传与远端复核，并形成精确 closure SHA；
- parked v1.14 已在另行授权下纯 fast-forward 到 v1.13.10 closure SHA；若不能纯快进则已经停止并重新裁决；
- legacy 的未完成 CrossStore WAL、DataEraseJournal 和 integrity quarantine 已清零或人工处置；
- 旧 Keychain service/access group、iCloud container、ModelConfiguration 名称和 store path 保持不变；
- Recovery Credential 已生成并验证；控制面永久丢失时是“明确不可恢复”还是提供加密 Recovery Kit 已在 G1/G3 裁决；
- 本机加密备份已通过 round-trip；
- Development 环境全矩阵已过，Production schema 还未切换真实用户；
- pre-cutover feature flag 默认关闭且可安全退回 legacy；post-cutover 只有“暂停写入/传输并前滚”的安全开关，不存在恢复 legacy 真相源的 kill switch；
- 用户明确同意影子迁移，产品文案说明仍处观察期。

## 3. 阶段状态机

    legacyOnly
      → shadowCopy
      → shadowVerified
      → cutoverPending
      → controlledPrimary
      → observation
      → cleanupEligible
      → legacySecretPlaintextDeleted
      → legacyMetadataRecordsDeletionObserved
      → legacyRetired

每次阶段变化先持久写 migration journal，再执行副作用，完成核对后提交下一阶段。

## 4. legacyOnly

行为：

- 现有系统完全照常；
- 新协议可以建立本机空 store、crypto test vector 和 disposable transport，但不读真实数据；
- 不创建用户真实 control/data zone；
- 不改变产品同步文案。

回滚：删除新本机空 store/测试配置即可，不碰用户数据。

## 5. shadowCopy

### 5.1 全量扫描

按闭合图顺序：

1. UpstreamAccount；
2. APIKeyRecord + 对应 Keychain keys item；
3. admin credential + account 标记；
4. ConsumerTool；
5. KeyAssignment；
6. 被批准进入受控域的其他实体；
7. 回收站/墓碑状态。

原 APIKeyRecord logical UUID 必须保留。新的 cloud recordID 只是传输 ID。

### 5.2 结果分类

| 分类 | 行为 |
| --- | --- |
| verified | envelope seal/open 后所有业务字段与内存中的 legacy 输入一致 |
| waitingForLegacySecret | 元数据存在，当前设备尚无 Keychain secret；等待旧同步/其他设备，不判损坏 |
| metadataOnlyAllowed | 规格明确允许没有 secret 的实体 |
| orphanSecret | Keychain 有 item、没有可识别元数据；quarantine |
| duplicateIdentity | 同 logical ID 多行；保留候选，按敏感冲突规则处理 |
| softDeleted | 连同 payload 和回收站时间迁移，另建同步删除语义 |
| corrupt/unknown | quarantine；保留 legacy 原件 |
| blockedByLegacyRecovery | 旧 WAL/erase 未完成，停止整个迁移 |

### 5.3 核对

- 在内存中用原始字段和解密后 payload 逐字段比较；
- secret 仅作恒定时间内存比较；
- ledger 只记 verified/false、结构计数、opaque IDs 和错误类别；
- 不持久化 secret hash、长度、末位或摘要；
- 图一致性检查：外键、指派、回收站、账号级联、配额计数。

### 5.4 增量捕获

全量扫描后不能直接切换。shadow 期间每个 legacy 业务写必须在现有成功提交后产生可恢复 migration delta，或由统一 coordinator 同事务双写新 outbox。

iCloud Keychain 没有可供 App 订阅的逐条到达/change token，因此远端 legacy secret 的迟到不能靠事件流证明“已经收齐”。迁移协调器必须在启动、回前台、legacy CloudKit 元数据导入成功、用户手动重试和 cutover 前执行可重复的 Keychain reconciliation；单次查不到只能标 waitingForLegacySecret，不能标“云端不存在”。

每台升级并登记的设备应提交签名的 `LegacyParticipant + LegacyInventoryCheckpoint`：install/device ID、build、legacy store 模式（CloudKit mirrored 或因初始化失败落入 local fallback）、扫描世代、opaque logical ID 集合/受审计计数、secret availability 与 metadata candidate 状态；不得包含 secret 派生物。能读取 secret 的设备生成同一 logical ID 的加密候选；内容相同则幂等合并，内容不同则形成 conflict siblings。本机 fallback store 中只在该设备存在的账号、名称、备注、URL、工具和指派也必须成为候选，不能只补 secret。

cutover 前冻结 participant-set revision。所有已登记参与者必须提交该 revision 的 inventory，或由用户逐台明确撤销/排除并接受其独有数据可能无法迁移的风险；不能用某个 quiet window 推断 iCloud Keychain 已全局完成。旧架构没有全局 roster，未知永久离线安装永远无法被证明不存在，所以对外只能说“所有已登记迁移参与设备已核对”。

若无法安全把 legacy 与 shadow 纳入同一可恢复协调器，cutoverPending 必须短时封住新写：

1. sealed write gate；
2. 等待已开始 legacy transaction 结束；
3. 扫最后 delta；
4. 逐条核对；
5. 切换或撤销 gate。

## 6. shadowVerified

进入条件：

- 所有可迁移记录 verified；
- waiting/orphan/conflict 数量为 0，或每项都有用户明确处置；
- 所有被纳入迁移的设备已提交当前扫描世代的 legacy inventory；未上线设备已由用户明确等待、撤销或排除；
- participant-set revision 已冻结；未知 legacy 安装无法证明不存在的风险和 grace window 已由用户接受；
- 至少两台真实设备能解密同一 shadow 数据；
- record graph、回收站和关系计数一致；
- shadow outbox 为 0 或所有 mutation cloudAccepted；
- Recovery Credential、设备批准和重装恢复演练通过；若产品承诺 control zone 灾难恢复，加密 Recovery Kit 也已演练。

此阶段仍从 legacy 读取并写 legacy。新系统只做比较，不向 UI 提供秘密。

回滚：关闭 feature flag、丢弃 shadow zone/store。legacy 未被删除。

### 6.1 Production 每保险库 shadow 闸门

Development/disposable container 通过只能证明协议和 schema 原型，不等于真实保险库可切换。Production additive schema 部署后，每个获准 canary/opt-in 的真实 vault 必须在 **仍由 legacy 提供 UI/业务读写** 的前提下独立完成 Production shadowCopy → shadowVerified：

- 逐条 round-trip、闭合图和 participant inventories 全部通过；
- Production control/data zone、配额、推送、账号变化和多设备行为留下该 vault 自己的证据；
- mismatch、waiting、conflict、quarantine 任一未清零即阻止该 vault cutover，不以其他测试 vault 的结果代替；
- 此阶段仍可用 pre-cutover disable 回到 legacy；不得提前生成 controlled-primary 独有写。

只有取得该真实 vault 的 `productionShadowVerified` checkpoint，才允许进入下一节。checkpoint 必须绑定 account/vault、migrationID、control head、manifest revision、四类世代、recovery epoch、participant-set revision、可验证 data frontier 与 shadow graph digest；任何 roster、control head、世代、participant set 或 shadow 内容变化都会使其失效并要求重新核对。因此 Production schema deploy、Production shadow 和 controlled-primary cutover 是三个独立 gate。

## 7. cutoverPending

步骤：

1. 当前验证方式重新确认；coordinator 以 manifest CAS 创建唯一 `CutoverBarrier`，绑定 cutoverID、base control head/change tag、冻结 participant-set revision、required participants、四类世代、ProductionShadowCheckpoint digest 与 final-delta 起点；
2. 每个 required participant 先持久写自己的 `MigrationOperationJournal` 和 sealed mutation gate，拒绝新的敏感写；
3. 每台设备排空本机 legacy in-flight 操作；
4. 每台设备读取 CloudKit/Keychain legacy 最后一轮并等待规定 quiet window，但不把 quiet 当全局完成；
5. 每台设备应用最后 delta、执行 Keychain/local-fallback reconciliation，并核对同一 shadow checkpoint、inventory 和可验证 data frontier；
6. 只有本机 gate、final delta 和核对均已持久完成，设备才提交绑定同一 barrier/base head 的签名 `CutoverReadyCheckpoint`；
7. coordinator 必须收齐全部 required participant 的合法 Ready；缺失设备只能由用户逐台明确排除并接受风险，同时生成新的 participant-set revision、ProductionShadowCheckpoint 和 barrier，不能在旧 barrier 上缩小集合；
8. coordinator 重新核对 manifest 未出现 erase/rotation/revoke/cleanup 等互斥 ControlOperation 后，以 CAS 提交唯一 cutover control event/manifest：`migrationPhase=controlledPrimary`、同一 `cutoverID`、active generation、minimum writer version、fencing revision 与 participant-set revision；
9. **第 8 步服务端接受是全局唯一不可回退点（PONR）**。若请求结果未知，重读 manifest/control history，以同一 cutoverID 判断已接受或重试，禁止创建第二个 cutover；
10. 各设备只有观察并验证该 control head 后，才原子切换本机 service routing 到 controlled store；
11. 产生 signed controlled-only checkpoint，解除本机 gate；旧 writer 的 mutation 只隔离。

第 8 步 CAS 被服务端接受前失败：必须提交已认证 barrier abort/release，各参与设备观察到同一 abort 后才解除本机 gate 并回 legacy；coordinator 单方面消失或只清除本机 flag 不构成释放。CAS 接受后，无论某台设备是否已有本机新 mutation，都只能前滚；本机 routing 落后只表示需要追上 control head，不能成为全局回滚理由。

## 8. controlledPrimary

- UI/业务只读写新 transaction coordinator；
- legacy CloudKit/Keychain 不再自动导入为当前数据；
- 为兼容回滚而保留的 legacy 写桥必须在 G3 明确，且不得无限期双写真相；
- 旧版 App 上传的变化进入 legacy 隔离报告，不自动覆盖新记录；
- minimum writer version 以下客户端的记录由新客户端忽略；
- 所有新业务写都拥有 mutation ID/revision/tombstone/epoch。
- post-cutover 安全开关只能暂停新写和/或网络传输、保持本机 controlled 数据可恢复，并等待修复前滚；绝不能把 legacy 路径重新打开为真相源。

### 回滚规则

允许：

- feature/transport 故障时继续使用本机 controlled store，修复后前滚；
- 将 controlled vault 显式导出为加密备份，用户选择在旧版本导入（会丢失新协议状态，须警告）；
- 在专门实现并测试 reverse bridge 后回写 legacy。

禁止：

- 仅切一个 flag 就让旧系统重新成为真相；
- 把旧版迟到写当作更“新”的 updatedAt 自动采纳；
- 在无损证明前删除 controlled mutation。

## 9. observation

至少覆盖：

- 一个 shadow-capable 发布版本；
- 一个 controlled-primary 发布版本；
- G1 冻结的最低观察时间；
- iPhone/iPad/Mac 至少两台、关账前三平台；
- 一台长期离线设备；
- 老版本写入、升级、重装、账号变化；
- root rotation、Recovery Credential、设备撤销；
- 普通删除、回收站、全量清除；
- 旧备份 v1 与新备份格式；
- 所有已知 P0/P1 故障注入。

观察期内旧 synchronizable Keychain 明文仍保留，但不再自动成为新真相。迟到旧项由 ledger 标记并提示清理。

## 10. cleanupEligible

进入条件全部满足：

- 所有 active 设备 checkpoints 达到 controlled generation/key/erase epoch；
- checkpoint 的 data frontier 已按 G3F 定义并可验证，不能用自报计数或更新时间代替；
- 长期失联设备已上线或被用户显式撤销；
- 冻结 participant-set 中所有已登记 legacy 安装已确认或由用户逐项排除；文案不扩展到未知离线安装；
- Recovery Credential 与至少一份加密备份 round-trip 通过；
- conflict/quarantine/waiting secret 为 0；
- forward-only 恢复演练通过；
- 独立安全审查和迁移审查通过；
- 隐私政策、帮助、商店问卷准备好但尚未提前声称完成；
- 用户单独批准不可逆 cleanup。

## 11. legacySecretPlaintextDeleted → legacyMetadataRecordsDeletionObserved → legacyRetired

秘密和 legacy 云端元数据分开清理，两个不可逆 gate 都必须幂等并有绑定 account/vault/install nonce/cleanupID/migrationID/base control head/participant set/批准证据的 `LegacyCleanupJournal`：

1. 再次验证 controlled vault 可解密；
2. 创建最终加密备份建议/确认；
3. sealed mutation gate；
4. 标记 cleanup irreversible decision；
5. 删除 legacy synchronizable Keychain keys/admin items；
6. 每个已登记参与设备重新枚举精确 service/access group、admin items 与 local-fallback store，提交签名 `LegacyCleanupCheckpoint`；核对秘密删除结果与迟到 synchronizable Keychain 项，只有 required participant checkpoints 齐全才达到 `legacySecretPlaintextDeleted`；
7. 另经授权后删除 legacy CloudKit private database 中 UpstreamAccount/APIKeyRecord/ConsumerTool/KeyAssignment 等旧记录，包含名称、备注、URL 和关系等明文元数据；逐 record/zone 记录结果，不把“schema 仍存在”误当“记录仍需保留”；
8. Production schema/record type 不能删除时只标 deprecated/ignored；它不等于保留用户旧 CKRecord；
9. CloudKit 查询/删除回执和已登记参与设备更新后的签名 cleanup checkpoints 均通过后，标 `legacyMetadataRecordsDeletionObserved`；iCloud Keychain 没有全局删除确认接口，不能把本机枚举为空扩大成所有未知设备已清除；
10. 解除 gate并进入 `legacyRetired`；
11. 观察迟到旧设备；任何 legacy Keychain/CloudKit 写只清理/隔离，不复活；
12. 更新产品与商店声明为已切换事实，但只声称云端旧记录删除已观察、列明的已登记设备已提交 cleanup checkpoint，不声称未知离线设备本地副本物理消失。

任一删除中断，启动保持 fail-closed，继续对应 journal；不得回到 legacy 读路径。secret cleanup 成功而 metadata cleanup 未完成时必须显示分阶段状态，不能笼统写“旧数据全部删除”。

## 12. 多设备迁移协调

不依赖单一设备永久 leader。建议：

- migration ID 与每条 shadow recordID 确定且幂等；
- control manifest 用 CAS 选出临时 coordinator lease；
- lease 有逻辑 revision/过期条件，但设备墙钟不能单独决定所有权；
- coordinator 只能提出 durable CutoverBarrier，不能代替其他 required participants 声称 ready；
- 每台 required participant 的 Ready 必须绑定同一 base control head、participant-set revision、ProductionShadowCheckpoint digest 和 final-delta frontier；
- barrier 未全员 Ready、被互斥 ControlOperation 抢占或 base head 变化时只能 abort/rebuild，不能“尽量切换”；
- 其他设备可协助补齐自己持有的 legacy secret，但不能覆盖已 verified envelope；
- 同一 logical ID 出现不同 secret 时形成 conflict siblings；
- coordinator 消失后另一 active device 根据 ledger/manifest 继续。

具体 lease 算法必须在 G2A/G3 设计并于 G3F 证明不会双切换；若证明成本过高，首版改为用户指定当前设备执行 cutover，其他设备只辅助并在切换时暂停写。

## 13. 备份兼容

- 旧备份格式 v1 至少保留一个完整迁移周期的导入能力；
- 新备份格式必须版本化，可包含 controlled envelopes、设备/恢复元数据或解密后的逻辑数据，但语义必须明确；
- 导出文件仍由独立备份口令加密，不能直接塞 VRS/Recovery Credential 私钥明文；
- 备份导入先进入 staging，验证后生成新的本机 mutation，不能把旧 server change tag 原样复用；
- 从备份恢复不自动绕过设备 roster/Recovery Credential 规则。

若用户明确确认 control/data CloudKit 已整体永久丢失，且不存在可继续信任的 manifest/control history，灾难恢复不能把备份原样回写成旧 vault：

1. 仅接受通过格式、AEAD、口令和完整性 round-trip 的加密备份进入隔离 staging；
2. 明确告知旧 vault 的设备 roster、最新性和未知离线写无法继续证明，并要求高风险用户确认；
3. 走全新 bootstrap，创建新的 vaultID、VRS、Recovery Credential、device identities、control genesis、generation 与各类 epoch；
4. 将备份中的逻辑实体解密后以新的 record IDs、DEK/nonce、mutation IDs、签名和因果起点重新加密导入；不得复用旧 change tags、control heads、device identities、wrapper、generation 或 epoch；
5. 旧 vault 只作为 retired/quarantined provenance 记录，任何以后出现的旧 CloudKit/离线设备数据都不得自动并入新 vault。

## 14. 逐崩溃点测试

每个步骤都要在“副作用前/后、journal 前/后、checkpoint 前/后”注入终止，并至少覆盖以下组合：

- 全量扫描每种分类；
- seal/open 核对；
- shadow upload；
- legacy 增量捕获；
- write gate；
- final delta；
- 一台设备在 barrier 后仍尝试写、两台 coordinator 同时提案、required participant 离线、用户排除设备后 participant revision 重建、barrier abort/release；
- erase × cutover、rotation × cutover、revoke × cutover、cleanup × 任一控制操作的 CAS 竞争和优先级；
- routing cutover CAS 请求已被服务端接受但回调丢失，以及 routing 尚未切换时重启；
- 第一条 controlled-only mutation；
- migration/cleanup journal 的每个 stage 遇到 iCloud account 切换、install nonce 不匹配、磁盘写满与首次解锁前启动；
- cleanup Keychain delete、每个 required participant 的签名 cleanup checkpoint，以及本机枚举为空但未知设备仍离线；
- 迟到 legacy item；
- old zone GC；
- 仅有已验证加密备份、control/data CloudKit 全失时建立全新 vault，验证旧身份/世代/tag 从未复用。

重启后必须落入已定义阶段，不得靠“重新跑一遍看看”或人工修改数据库。
