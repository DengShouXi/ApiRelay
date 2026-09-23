# Feature Specification: v1.14 受控密文同步

**Status**: 评审草案（plan-only）
**Date**: 2026-09-24
**Target line**: 建议归入 Stage 1 小迭代 `v1.14`，不占用产品路线图的 V2（2.0 用量看板）
**Implementation authorization**: **没有**。本文不授权改 Swift、改生产 CloudKit、迁移真实数据、切换分支、提交或上传。
**Depends on**: `v1.13.9` 最终关账后，先完成并关账纯结构稳定化 `v1.13.10`；顺序见 [release-sequence.md](./release-sequence.md)；另依赖[现行 Stage 1 规格](../../spec.md)与[旧同步卫生包](../cloudkit-sync-hygiene/spec.md)

## 1. 结论与边界

本项目现有的 SwiftData 自动 CloudKit + iCloud 钥匙串不是错误选型，但它只能提供 Apple 管理的最终一致同步，无法让 App 准确控制、观察并确认“密钥记录与明文作为一个整体已经到达”。`v1.14` 的建议目标不是继续给旧双通道增加重试，而是新增一套独立、可迁移、可回滚的受控密文同步协议：

- CloudKit 只保存客户端生成的密文、包装后的密钥和最少路由字段；
- `CKSyncEngine` 管理自定义 zone 的收发、增量、冲突事件和重试调度；
- 每条保险库记录使用随机 DEK；DEK 由 vault root key 包装；root key 再按设备或恢复因子包装；
- SwiftData 继续用于本机投影，但保险库核心投影不得再由 SwiftData 自动 CloudKit 镜像；
- 应用密码在本方案中继续只是本机门闩，不直接派生保险库密钥；
- 新设备加入、设备撤销、密钥轮换、恢复、删除墓碑、全量清除和迁移回滚都是协议正文，不是实现后的补丁。

旧 `cloudkit-sync-hygiene` 工作包继续代表旧架构的 v1.13.5 卫生修复，不能改名或扩写成 `v1.14`。其中 T008 仍是旧路径的独立发布证据；T006 `replicaSeed` 是否取消，要等新架构获批后另行裁决，不能假勾完成。

## 2. 目标

1. **消除双通道半成功**：保险库核心内容与密钥材料由同一个加密记录协议承载，不再出现“元数据到了、钥匙串明文没到”的正常态。
2. **可控且可观察**：能区分本机提交、持久入队、发送中、CloudKit 接受、当前设备应用、指定设备回执和冲突。
3. **离线正确性**：重复、乱序、并发、长时间离线和重启不得造成静默丢失、删除复活或旧世代污染当前投影。
4. **云端内容保密**：CloudKit 不持有可直接解密保险库内容的根密钥；Apple 账号登录本身不等同于获得保险库解密权。
5. **迁移可恢复**：旧数据先影子复制和核对，经过双设备观察后再切换；不可逆删除旧钥匙串明文必须是最后一步。
6. **不破坏现行认证**：`v1.13.9` 已冻结的四档验证、应用密码重置和会话门闩语义不在本阶段被暗改。

## 3. 非目标与不能承诺的事

- 不承诺后台同步在固定秒数内完成；手动发送/拉取也只是立即发起一次尝试。
- “CloudKit 已接受”不等于“所有设备已收到并应用”。没有设备回执时不得显示后者。
- 不承诺 CloudKit、本机数据库和钥匙串之间存在跨存储 ACID 事务。
- 不承诺撤销设备能抹掉该设备此前已经缓存的明文或旧密钥。持有旧 VRS 的一方可继续解密其在撤销/轮换前已取得且由对应旧 `writeKeyEpoch` VRS 可解的 ciphertext/wrapper；常规轮换只保护后续写入，不能让历史副本重新变成不可解。疑似泄露时必须走独立的 compromise replacement，并承认此前明文不可追回。
- 不承诺永远离线且仍运行旧版本的设备已被远程物理擦除。协议必须保证旧世代逻辑上不复活，并如实显示物理清理是否收敛。
- 不宣称“零元数据泄漏”。record/zone 标识、记录大小、时间和少量路由字段仍可能对 CloudKit 可见。
- 不在没有外部最新性锚点时承诺全新设备能识别云端提供的“一整套旧但当时有效的快照”；详见 [threat-model.md](./threat-model.md)。
- 不承诺 Recovery Credential 能在 CloudKit control/data 全部永久丢失时凭空恢复数据；没有仍可信设备或已验证加密备份/未来 Recovery Kit 时必须明确不可恢复。
- 不在本阶段做跨用户共享、组织保险库、V2 用量看板或整体 UI 重设计。
- 不把现有应用密码、备份口令或设备密码悄悄改成解密根因子。

## 4. 术语和确认层级

| 术语 | 含义 |
| --- | --- |
| VRS | Vault Root Secret；每个 `writeKeyEpoch` 对应一份随机保险库根秘密；旧 VRS 只可能出现在 `acceptedReadKeyEpochs` 对应的受限读取路径 |
| DEK | 每条记录独立随机生成的数据加密密钥 |
| Device Wrapper | 用设备 P-256 密钥协商得到的包装密钥，将 VRS 包装给一台可信设备 |
| Recovery Credential | 用户离线持有的高熵恢复凭据；推荐为独立 agreement/signing recovery keypair，云端只存公钥和 VRS wrapper；与应用密码、备份口令分离 |
| `generation` | 数据 zone/命名空间世代；只表示当前内容写入哪个数据世代，不是密钥版本，也不自动表示已清除 |
| `eraseEpoch` | 内容销毁的单调水位；低于当前值的记录和 mutation 永不进入当前投影，不代替 `generation` 或 key rotation |
| `writeKeyEpoch` | 当前新 payload/DEK wrapper 唯一允许使用的 VRS 世代；任何旧值只读不可写 |
| `acceptedReadKeyEpochs` | 轮换过渡期仍允许解读历史 envelope 的有限集合；它不是可写集合，也不恢复已撤销 signer 的写权限 |
| mutation | 一次幂等业务变更，具有唯一 `mutationID` 和因果基线 |
| durable outbox | 与本机业务提交同一事务写入的待发送队列；CKSyncEngine pending state 不是它的替代品 |

同步状态必须至少区分：

```text
本机事务完成
→ 已进入持久 outbox
→ 正在发送
→ CloudKit 已接受
→ 当前设备已拉取并应用
→ 某台可信设备已回执（仅在确有 DeviceCheckpoint 时）
```

任何界面和日志都不得把前一层扩大成后一层。

## 5. 用户场景与验收语义

### US1 — 本机保存不等待云端

用户新增或修改记录时，App 先完成本机投影、密文信封和 outbox 的原子提交，随后异步发送。网络不可用时本机操作仍可成功，并明确显示“已保存在本机，等待上传”。

**验收**：在本机提交、outbox 写入、CKSyncEngine 登记、CloudKit 接受四个崩溃点逐一终止进程，重启后要么没有业务变更，要么变更和 outbox 都存在；不得出现已改投影但永久没有待发送 mutation。

### US2 — 新设备以明确的信任流程加入

新设备不能仅凭登录同一 iCloud 就获得 VRS。它先生成本机设备密钥和加入请求，由现有可信设备明确批准，或使用独立恢复密钥恢复。批准、取消、超时和重复批准均幂等。

**验收**：未批准设备只能拉取密文；CloudKit 中被伪造的设备公钥或旧审批不能获得当前 VRS。

### US3 — 并发修改不静默吞数据

两台设备离线修改同一条记录时，协议使用 `recordChangeTag` 发现服务器并发，再依据 mutation 因果关系与实体冲突矩阵处理。密钥明文冲突和更新/删除冲突必须保留可恢复证据，不得只按设备时间戳静默丢弃一边。

**验收**：设备时钟相差 24 小时仍得到同一结果；重复与乱序 mutation 不重复应用；无法自动决定的密钥冲突进入显式 conflict sibling。

### US4 — 删除和全量清除不会被旧设备复活

普通删除写长期墓碑。G1 必须先在“保留信任根的内容清空”和“退休旧 vault 的完整重置”之间裁决 FR-061 的映射；两种候选都必须推进 `eraseEpoch`，并推荐用最小认证 anti-replay/retirement tombstone 阻止旧 mutation 复活；若产品选择绝对零残留，则必须明示无法同时可靠阻止未知离线副本复活。两种候选对 `generation`、vaultID、Recovery Credential 与 device identity 的处理不同。物理删除分批重试，状态与逻辑不可见分开呈现。

**验收**：一台设备离线删除前的副本在清除后数日上线，其旧记录仍被拒绝或隔离；不能重新出现在列表。物理 GC 未完成时界面不得声称“所有设备和云端都已永久删除”。

### US5 — iCloud 账号与同步状态变化失败关闭

退出 iCloud、切换账号、zone 被删、change token 过期、配额满、限流或部分失败时，当前账号的投影、root wrapper 和 engine state 必须隔离。outbox 仍是可重建权威，错误必须分成可重试、需用户操作和永久不兼容三类。

**验收**：账号 A 的本机投影和 VRS 不得在账号 B 会话中打开或上传；token 失效后的全量重建不得复活墓碑前数据。

### US6 — 旧架构安全迁移

迁移依次经过 `legacyOnly → shadowCopy → shadowVerified → cutoverPending → controlledPrimary → observation → cleanupEligible → legacySecretPlaintextDeleted → legacyMetadataRecordsDeletionObserved → legacyRetired`。在 cleanup gate 前，不删除任何旧同步钥匙串明文或旧 CloudKit 元数据记录；control manifest 接受 controlled-primary cutover 后只能前滚，不得假装可以无损降回旧版本。

**验收**：迁移可重复、可中断、可核对；缺明文、孤儿元数据、重复业务 ID、软删除和指派关系都有单独隔离结果，不以伪造空值通过。

## 6. 功能要求

### 6.1 架构和存储

- **CES-001**：保险库核心必须使用独立 custom zone 与 `CKSyncEngine`；旧 SwiftData 自动 CloudKit store 不得与新核心同步引擎共同管理同一份记录。
- **CES-002**：SwiftData 只作为新架构的本机读取投影和本机事务存储；普通非敏感偏好可以继续留在独立自动同步 store，但必须先完成分类表。
- **CES-003**：本机业务提交必须在同一个 controlled local store 的同一持久事务中写投影、密文信封、mutation 和 durable outbox；若原型证明框架做不到，必须改用 durable journal 明确前滚/回滚，不得把跨 store 尽力补偿称为原子。
- **CES-004**：CKSyncEngine `stateSerialization` 必须持久化；它丢失或账号变化后，可从 outbox 和本机 envelope cache 重建 pending changes。
- **CES-005**：CloudKit Production 只做 additive 变更。新协议使用新 record type/zone；旧 schema 标记 deprecated/ignored，不原地改类型、不假装删除。

### 6.2 加密与设备信任

- **CES-006**：每条记录使用独立随机 256-bit DEK 和带认证加密；同一 DEK 下 nonce 不得复用。
- **CES-007**：DEK 由当前 VRS 派生的 wrapping key 包装；VRS 再分别包装给每台可信设备和恢复公钥，禁止每条记录乘以设备数逐一包装。恢复私钥/种子默认只由用户离线持有；active 设备必须能只凭已批准的 recovery public key 为新 VRS 生成恢复 wrapper，不能在撤销时静默丢掉恢复路径。
- **CES-008**：Secure Enclave 仅保存/使用设备 P-256 私钥用于签名或密钥协商，不得声称把 AES DEK/VRS 直接存入 Secure Enclave。G1/D17 必须在无 Secure Enclave 设备上明确选择：拒绝创建/加入受控保险库，或使用 Data Protection Keychain `ThisDeviceOnly` 软件 P-256 fallback。后者必须承认私钥对本 App 进程可导出，roster/UI/诊断标记 `softwareExportable`，不得同步、备份或宣称等同硬件不可导出；未经裁决不得静默 fallback。
- **CES-009**：加密信封必须把不可变内容的 `payloadAAD` 与每个 wrapper 自己的不可变 `wrapAAD` 分开：前者绑定 record/content revision，后者绑定 wrapperID、创建时 `writeKeyEpoch`/control revision 和内容 digest；集合级 wrap mutation/revision 只进入外层签名。content mutation/revision 与 wrap mutation/revision 必须分离，新增或删除 wrapper 不得使未变化的 payload tag 或既有 wrapper tag 失效。任何头部替换、跨记录搬运、降级或篡改都必须验证失败并隔离。
- **CES-010**：应用密码继续是本机门闩；不得用于派生 VRS/DEK，不得改变现行“经设备主人显式恢复且不删除密钥”的语义。若未来要升级为解密因子，必须另立产品裁决和迁移。
- **CES-011**：新设备加入必须证明持有自己的私钥，并由当前可信设备授权或恢复凭据恢复；仅登录 iCloud 不足以解密。Recovery-only 入网还必须提供专用 recovery-admission proof，绑定新设备两把公钥、request/challenge、父 control head/revision、`generation`、`eraseEpoch`、`writeKeyEpoch`、`acceptedReadKeyEpochs`、`recoveryEpoch` 与过期边界；pending 设备不得仅因已解出 VRS 就获得一般控制权。
- **CES-012**：设备撤销必须递增 roster revision 并激活新的 `writeKeyEpoch`；旧设备基于旧 control head/roster/`writeKeyEpoch` 的写入不得进入当前投影。轮换期间 manifest 必须把唯一 `writeKeyEpoch` 与有限 `acceptedReadKeyEpochs` 分开，每条记录允许并存旧/新 DEK wrappers；撤销后的新内容版本必须生成新 DEK 且只用当前 `writeKeyEpoch` 包装。重包/轮换必须可中断并恢复，不能靠单一 `keyEpoch` 字段假装原子完成，也不能用 `generation` 或 `eraseEpoch` 代替密钥轮换。
- **CES-012A**：控制面必须保留不可变、hash-linked、签名的 membership/control history；ControlEvent N 的授权只由已认证父状态 N−1 决定，不能用它自报的 after-state 给自己授权。每个 data mutation 还须绑定 controlHeadHash、actor 单调 sequence 与 actorPrevMutationHash。撤销或明确的 `eraseEpoch`/`writeKeyEpoch` transition 冻结每个 actor 最后已接纳的可验证 data frontier/head；旧 signer 的历史记录只有落在该冻结 frontier 的链上才可重建，撤销后用旧 key/VRS 回填并伪装成旧 revision 的 mutation 必须隔离。当前新写另按当前 control head/roster/`generation`/`eraseEpoch`/`writeKeyEpoch` 接纳。
- **CES-012B**：控制面管理员权不能由实现临时决定。G1 必须在“任一 active device 可单签（1-of-N）”与“多设备 quorum”之间选择，并分别定义新设备批准、撤销、正常轮换、Recovery Credential 替换和 compromise replacement 的授权门槛、单设备/全部设备丢失时的逃生路径及审计证据。未经 D13 裁决不得冻结控制事件格式。
- **CES-012C**：普通内容取用的四档验证与同步信任管理必须分域。G1 必须裁决：即使当前验证方式是“不验证”，新设备批准、设备撤销、Recovery Credential 替换、compromise replacement 和 FR-061 清除/重置是否仍强制 `deviceOwnerAuthentication`。在 D14 和相应 FR-061/接口权威回写完成前，不得把任一候选写成现行产品事实。
- **CES-012D**：必须区分 routine rotation 与 compromise replacement。前者可只生成新 VRS、切换 `writeKeyEpoch` 并在 `acceptedReadKeyEpochs` 中暂留旧值、分批重包 DEK；它不治疗旧 VRS 泄露。后者须排除被怀疑的 device/recovery identities，对所有仍存活内容生成全新 DEK、nonce 和 ciphertext，并在完成前保持失败关闭/明确降级状态。两者都不能追回攻击者已取得的明文或历史 ciphertext/wrapper；D15 未批准前不得向用户承诺“轮换后历史数据重新安全”。

### 6.3 同步、冲突和删除

- **CES-013**：所有 mutation 必须有全局唯一 `mutationID`、actor device ID、因果 revision 和幂等应用记录；设备墙钟只能用于展示，不能作为唯一冲突裁决。
- **CES-014**：默认使用 CloudKit `ifServerRecordUnchanged`/change tag 检测并发；密文冲突由客户端解密后按实体冲突矩阵解决。
- **CES-015**：同一 mutation 重放不得重复产生记录、额度或指派副作用。
- **CES-016**：密钥内容的并发更新不得静默 LWW；必须保留 conflict sibling，待用户选择。普通元数据可在确有共同祖先时做字段级三路合并，否则同样保留 sibling。
- **CES-017**：指派关系使用稳定关系 ID 和版本化墓碑；删除不得因为离线旧副本重新出现。
- **CES-018**：普通删除产生 remove-wins 墓碑。GC 仅在所有仍可信设备确认相应 `generation`、`eraseEpoch` 和 data checkpoint 且满足最低保留期后执行；失联设备必须先由用户显式撤销，不能自动当作已确认。
- **CES-019**：清除协议必须分别携带 `source/target generation`、`source/target eraseEpoch`、清除前后 `writeKeyEpoch` 与 `acceptedReadKeyEpochs`；不得把任一字段简称为可互换的“新 epoch”。发起端与每个接收端都必须有 account/vault/eraseID/上述源目标值绑定的 durable journal；观察到更高 `eraseEpoch` 时先封写、停止旧世代 outbox/inbox、清除旧明文投影与内存 key，再按获批模式重建或退出为未配置。账号切换不得把 A 的清除 journal 重放到 B。跨批、跨 zone 操作必须有可恢复阶段和 checkpoint。
- **CES-019A**：G1 必须裁决 FR-061 的清除语义。候选 A“内容清空”保留 vaultID、Recovery Credential、device identities/control history，只推进 `eraseEpoch` 并切换 `generation`；候选 B“保险库重置”退休旧 vault，清除其内容和本机信任材料，后续以全新 vaultID、Recovery Credential 和 device identities bootstrap。两者都建议保留不含业务内容的最小认证 anti-replay/retirement tombstone；若要求绝对零残留，必须明确接受未知离线旧副本将来可能无法被可靠识别的风险。当前 FR-061 仍是权威，D16 未批准并完成权威回写前不得把候选 A 或 B 当作已生效要求。
- **CES-020**：拉取到未知版本、认证失败、缺包装密钥、非 active `generation`、低于当前 `eraseEpoch`、不在 `acceptedReadKeyEpochs` 或结构损坏的记录必须进入隔离区，不得覆盖最后一份已知良好投影。
- **CES-020A**：每台设备必须在 ThisDeviceOnly 本机状态固定其已接受的最高 control revision/head hash。manifest/control event 形成 signed/MACed parent-hash 链；较低 revision、同 revision 异 hash 或断链必须失败关闭。可信设备批准和 DeviceCheckpoint 必须绑定批准方最新 control/data checkpoint。只有 Recovery-only 且无任何其他锚点的全新设备保留已披露的完整快照回滚例外。

### 6.4 状态、错误和产品诚实性

- **CES-021**：状态模型至少包含 `localOnly`、`queued`、`sending`、`cloudAccepted`、`peerAcknowledged`、`conflict`、`blocked` 和 `failedPermanent`；每个状态有可验证来源。
- **CES-022**：CloudKit 接受只说明该批次已保存；没有 `DeviceCheckpoint` 时不得显示“其他设备已同步”。
- **CES-023**：推送只作为“可能有变化”的提示；正确性必须来自持久 change token/全量重建，不依赖推送必达。
- **CES-023A**：锁定态后台收到的远端变化必须先进入 durable inbound spool。只有“该批入站密文字节/删除标记与对应 CKSyncEngine `stateSerialization`”已在同一持久边界提交后，才允许推进接收游标；解锁后的验签、解密、冲突与投影应用是第二阶段。`needsUnlock` 不是 quarantine，DeviceCheckpoint 只能在第二阶段成功后写。
- **CES-024**：错误必须分类：自动重试、等待网络/账号、等待解锁/审批、用户需处理冲突、协议永久不兼容。不得统一显示“同步失败”。
- **CES-025**：日志、诊断、分析和崩溃报告不得含明文、DEK、VRS、恢复密钥、完整密文或可用于离线猜测的验证材料。

### 6.5 迁移与兼容

- **CES-026**：先按 [release-sequence.md](./release-sequence.md) 关账 `v1.13.9`，再用独立 `v1.13.10` 完成“不改功能”的拆文件、状态单一来源和真实 XCUITest；同步实现必须以最终关账的 `v1.13.10` 为精确基线。当前停在 v1.13.6 tip 的 parked `v1.14` 不得直接开发。
- **CES-027**：影子阶段旧通道仍是真相源，新通道只写密文并做只读核对；任何核对失败都阻止切换。
- **CES-028**：迁移以稳定 migration ID 幂等；每条记录记录来源、结果、缺明文/孤儿/冲突原因和核对摘要，但摘要不得由密钥明文本身派生后上传。
- **CES-029**：切换前必须验证至少两台真实设备，并冻结 `LegacyParticipant` 集合及各自签名 inventory checkpoint；本机 fallback store 的独有元数据候选也必须上报。旧架构没有可证明完整的全局设备 roster，因此只能声称“所有已登记迁移参与设备已核对”，未知永久离线设备风险必须通过 grace window 与用户逐项排除裁决。旧版本仍可写时，新架构不得再次导入旧域 mutation；切换后的 legacy 数据只可作为人工恢复源，不再是自动真相源。
- **CES-029A**：全局不可回退点只能是 control manifest 以 CAS 接受 `migrationPhase=controlledPrimary`、`cutoverID`、fencing revision 与 minimum writer version 的那一刻。本机 routing 只有观察到该 head 后才切换；CAS 结果未知时按 `cutoverID` 重读裁决。不可回退点前可以撤回 legacy，不可回退点后 kill switch 只能暂停新写/传输并前滚，绝不能恢复 legacy 为真相源。
- **CES-030**：删除旧 synchronizable Keychain 明文必须晚于受控主路径、跨版本观察、恢复演练、设备撤销和全量清除验收；该动作单独授权并记录为不可逆闸门。
- **CES-031**：老版本、旧 data zone/generation、历史 `writeKeyEpoch`/`acceptedReadKeyEpochs` 的支持期限、最低 writer protocol 与淘汰条件必须在发布前明确，不得由代码默认值临时决定。

## 7. 待用户批准的产品裁决（G1）

以下推荐值写入计划，**尚未改写现行权威规格**：

| 决策 | 推荐 | 若不批准的影响 |
| --- | --- | --- |
| 版本归属 | `v1.14` 是 Stage 1 同步架构维护，不是产品 V2 | 必须另开产品阶段并调整路线图依赖 |
| 同步时效与状态承诺 | 不保证固定秒数；只显示有实际证据的本机、CloudKit 和指定设备确认层级 | 若承诺“实时/已全部完成”，现有平台能力无法可靠证明 |
| 应用密码角色 | 保持本机门闩 | 若改为解密因子，忘记/重置/四档验证全部需要重设计 |
| 新设备信任 | 现有可信设备批准 + 独立 Recovery Credential | 只靠 iCloud 会降低“App 自控密钥”的安全目标 |
| 无设备恢复 | 允许凭高熵 Recovery Credential 恢复；没有恢复凭据则不可恢复 | 若必须保证找回，需要引入托管恢复及新的隐私承诺 |
| 恢复凭据结构 | 推荐离线非对称 recovery agreement/signing keypair；云端只存公钥，使 active 设备可在 root rotation 时生成新 wrapper | 若坚持对称 Recovery Key，每次轮换/撤销都必须重输，且必须单独解决丢失时的紧急撤销，不能静默取消恢复能力 |
| 后台秘密读取 | v1.14 先只做密文后台同步；未来管理凭证自动刷新另设受限 automation domain | 若要求锁定时解密全部秘密，会削弱认证绑定并扩大攻击面 |
| 旧版本窗口 | 至少一个影子版本 + 一个 controlled-primary 观察版本；同时冻结 legacy participant grace window 与未知离线设备风险说明 | 太短增加丢数据风险，太长延后删除旧明文 |
| 路由元数据 | 单一通用 record type，公开字段只保留协议/世代/ID/状态所必需内容 | 更多明文字段提升查询便利但扩大元数据泄漏 |
| 云端主动回滚 | v1.14 不新增 transparency 服务；防泄露和记录级篡改，最新快照依赖 CloudKit，可信设备间用 checkpoint 交叉发现回退 | 若要求抵抗完整历史回滚，须新增外部锚点并重评无服务端边界 |
| 离线发起全量清除 | 推荐本机立即使旧内容不可见并封住新写，显示“本设备已清除，iCloud 待联网完成”；获批模式的 `eraseEpoch`/control transition 激活前不得创建新 vault 或重新开放写入 | 若要求离线后立即重建新 vault，会出现无法安全确定云端 control head/`eraseEpoch`/并发清除的分叉 |
| CloudKit 控制面灾难恢复 | v1.14 明确 Recovery Credential 单独不足；legacy cleanup 前必须有已验证加密备份。自动更新 Recovery Kit 另案设计 | 若要求只凭 Recovery Credential 在云端全失时恢复，必须扩展格式、更新/托管与回滚协议 |
| 控制管理员权 | 推荐个人保险库首版采用任一 active device 单签（1-of-N），但每项高风险 control event 都留下签名审计；若选择 quorum，必须同时定义仅一台设备、设备丢失和 Recovery-only 的逃生路径 | 单签可用性高但 active device compromise 的控制面影响更大；quorum 更强但会锁死单设备用户并显著扩展协议 |
| “不验证”与高风险操作 | 推荐“不验证”只作用于普通 App 内容门闩；设备加入/撤销、Recovery Credential 替换、compromise replacement 与 FR-061 清除/重置仍强制设备主人认证 | 若完全继承“不验证”，拿到已解锁设备的人可接管或销毁整个 vault；若批准推荐项，必须显式修订 FR-061 和接口，不得偷改 |
| 密钥轮换模式 | 推荐拆成 routine rotation 与 compromise replacement；后者全量换 DEK/nonce/ciphertext并替换被怀疑信任因子，且 UI 披露历史副本不可追回 | 只做重包无法治疗 VRS/设备密钥泄露，会产生虚假安全感 |
| FR-061 清除语义 | 推荐把现行“清除全部数据”映射为 vault reset：退休旧 vault，完成远端销毁意图后进入未配置状态；重新使用时生成新 vaultID、Recovery Credential 和 device identities，并只保留最小 anti-replay/retirement tombstone。若还需要保留信任的内容清空，应作为名称、确认和语义均不同的独立操作 | 保留信任根不符合用户对“全部数据”的通常理解；零残留则无法同时可靠阻止未知离线旧副本复活，必须选边并回写 FR-061 |
| 无 Secure Enclave 设备 | 推荐对明确支持的无 SE 设备允许 Data Protection Keychain `ThisDeviceOnly` 软件 P-256 fallback，并在 roster/UI 显示硬件保护降级；不得同步/备份或称为不可导出 | 若拒绝则安全边界更简单但缩小设备支持；若允许却不披露，会形成虚假硬件安全承诺 |

任一项未批准，不能进入实现阶段。

最终选择、未采用方案、批准人/证据、权威回写位置与 `ZL01/14` 更新状态统一登记在 [decision-log.md](./decision-log.md)。本表的“推荐”不是已经批准的产品事实。

## 8. 成功标准

- **SC-CES-001**：两台真实设备上，普通新增/修改/删除最终一致，且每一步状态文案与实际确认层级一致。
- **SC-CES-002**：CloudKit 记录、日志、SwiftData 核心投影和诊断导出中，API 密钥明文与可离线猜测派生物出现次数为 0。
- **SC-CES-003**：并发更新密钥内容时，两份输入均可恢复，静默丢失次数为 0。
- **SC-CES-004**：随机选取本地提交、入队、发送、服务端成功、远端应用、轮换和清除阶段注入崩溃，重启后可幂等继续，状态不倒退。
- **SC-CES-005**：设备时钟大幅偏差、重复/乱序事件、推送丢失、token 失效与账号切换均不改变安全结论。
- **SC-CES-006**：清除后旧离线设备上线，旧 generation、低 `eraseEpoch`、旧 `writeKeyEpoch` 写入进入当前投影次数均为 0；物理 GC 未收敛时不会显示绝对完成。
- **SC-CES-007**：迁移逐记录核对 100% 通过或明确隔离；任何缺明文/孤儿/冲突都不会被伪造成成功。
- **SC-CES-008**：旧钥匙串明文删除前完成恢复密钥演练、新设备加入、设备撤销、root rotation、双/三设备、重装与跨版本观察矩阵。

## 9. 进入实现前的硬门槛

闸门分成三层，不能合并授权：先由 G1 批准产品决定；再精确授权并完成权威回写与一致性复核；最后由用户只授权一个实施 gate。以下事项按顺序全部完成后，代码仍须取得该 gate 的单独实施授权；“批准方案”本身不等于授权 Git、CloudKit 或真实数据操作：

1. `v1.13.9` 尚欠验收与证据完成，在此之前只标“待关账”；
2. 用户单独授权后完成 `v1.13.9` 提交/上传；独立远程复核通过后，才登记已关账及精确 closure SHA；
3. `v1.13.10` 仅按 `release-sequence.md` 做结构稳定化，真实 XCUITest、三平台/真机回归、独立审查、授权上传与远端复核完成后，登记自己的 closure SHA；
4. §7 全部 D01–D17 产品裁决（含控制管理员权、高风险认证、两类轮换、FR-061 清除语义与无 Secure Enclave 设备策略）已逐项签字；
5. G1 决定已完整写入 `decision-log.md`；ROADMAP、宪法、现行 spec/plan/research/data-model/interfaces 的冲突回写清单另获授权并实际回写，一致性复核通过；legacy T006/T008 有明确且不造假的处置；
6. 用户另行授权后，当前无独有提交的 parked `v1.14` 只以 fast-forward 前移到最终 `v1.13.10` closure SHA 并记录精确 base SHA；若不能纯快进则停止并重新裁决；
7. 加密信封、设备生命周期、同步状态机、迁移/回滚契约完成统一冻结与独立安全/迁移审查；
8. Development 环境 schema、feature flag、测试账号和真实设备矩阵准备完成；
9. 明确本次只进入哪个实施 gate，不能一次授权直接跨到删除旧钥匙串明文或旧 CloudKit 元数据。
