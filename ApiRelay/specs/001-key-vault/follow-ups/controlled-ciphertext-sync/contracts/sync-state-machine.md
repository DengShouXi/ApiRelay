# Contract Draft: Sync State Machine

**Status**: G2A/G3 设计草案；须经 G3F 统一冻结，描述未来行为，不代表已实现

## 1. 不变量

1. 本机业务成功 = 投影、canonical envelope、mutation、outbox 同一事务已经持久化。
2. CloudKit 网络结果不得回滚已经成功的本机业务事务。
3. outbox 是业务待办权威；CKSyncEngine pending state 可从 outbox 重建。
4. 只有逐记录 server success 才能标 cloudAccepted。
5. 只有某台设备签名的 DeviceCheckpoint 才能标该设备 acknowledged。
6. 任何未知/损坏/旧世代远端记录都不得覆盖最后良好投影。
7. 设备时间不决定数据胜负。
8. 入站传输持久化与业务应用分成两阶段；锁定态可以收密文，但不能前移“已应用”checkpoint。
9. 只有入站批次每一项和对应 CKSyncEngine stateSerialization 都持久化，才允许推进接收游标。

### 1.1 四类世代/时期

以下字段是正交状态，不允许用笼统 `epoch` 或 `keyEpoch` 互相代替：

| 字段 | 状态机职责 | 单调/集合规则 |
| --- | --- | --- |
| `generation` | 选择 active data zone/命名空间 | 只在已认证 control transition 后切换；旧 generation 不自动等于已擦除 |
| `eraseEpoch` | 拒绝销毁水位之前的内容/mutation | 单调递增；低值永不重新 live |
| `writeKeyEpoch` | 规定新 payload/DEK wrapper 使用哪个 VRS 世代 | 同一 control head 只能有一个当前可写值 |
| `acceptedReadKeyEpochs` | 规定轮换期间哪些历史 VRS 世代仍可读 | 有限集合；成员资格只授予读取，不授予写入或设备 membership |

每个 mutation、control event、approval/checkpoint、inbound batch 与 erase/rotation journal 都必须保存并验证适用的四项。正常 root rotation 不自动推进 `generation` 或 `eraseEpoch`；清除推进 `eraseEpoch`，是否切换/退休 `generation` 与 trust root 取决于 D16。

## 2. 启动状态机

    unconfigured
      → loadingAccountBinding
      → loadingDeviceIdentity
      → loadingPinnedStateAndBoundJournals
      → constructingFailClosedMutationGate
      → recoveringControlOperation
      → restoringEngineState
      → fetchingControlPlane
      → validatingManifestAndRoster
      → fetchingActiveGeneration
      → rebuildingProjectionIfNeeded
      → ready

阻塞分支：

- accountUnavailable
- accountChanged
- deviceApprovalRequired
- recoveryRequired
- unsupportedProtocol
- controlIntegrityFailure
- localRecoveryRequired

启动顺序是安全边界：必须先取得 ThisDeviceOnly install nonce/device references/pinned head，再打开并核对 local store，装载所有 account/vault 绑定的 bootstrap、pinned-head、migration、cleanup、rotation、erase journal，并按未完成阶段封住 mutation gate；完成 ControlOperation 仲裁后才可按当前账号/generation 实例化或恢复 CKSyncEngine、ModelContainer 投影和业务服务。现有 v1.13.9 的 journal/gate 只能作为迁移输入，未证明具备上述绑定前不能原样复用。进入阻塞状态后不得用空数据覆盖本机，不得自动创建新 vault 冒充原 vault。

## 3. 本机 mutation

    requested
      → authorizationValidated
      → controlAndEpochsPinned
      → encrypted
      → localTransactionCommitting
      → localDurable
      → queued
      → inFlight
      → cloudAccepted

分支：

- authorization/session revision 失效：在 local commit 前拒绝，零副作用；
- control head、generation、eraseEpoch 或 writeKeyEpoch 在加密/提交前变化：丢弃未提交结果并基于新状态重试；不得把 acceptedReadKeyEpoch 当成可写值；
- local transaction 失败：整体不成立；
- CKSyncEngine 登记前崩溃：启动从 durable outbox 重建；
- inFlight 崩溃/结果未知：同 mutationID 安全重试；
- serverRecordChanged：conflictDetected；
- 永久 schema/size 错误：failedPermanent，保留本机数据并要求用户处理。

## 4. 远端接收与业务应用

### 4.1 传输落盘（允许锁定态）

1. 接收 fetched control/data changes 与 state update，先校验 account binding、zone、大小和外层可解析版本；
2. 把每个 save 的原始密文/CloudKit system fields 或 transport-level physical-delete marker 写入 durable `PendingInboundChange`；
3. 在同一 local transaction 中写完整 `InboundBatch` 与对应的新 CKSyncEngine `stateSerialization`；
4. 若任一项或 state 写入失败，整个 batch 不成立，不保存新 engine state，允许系统重投并以 itemID 幂等；
5. 锁定且需要 VRS 时标 `needsUnlock`，不是 `missingWrapper`、`quarantine` 或“已应用”。

### 4.2 解锁后验证与应用

对 durable inbound 按以下顺序处理：

1. 验证账号、zone、generation、eraseEpoch、writeKeyEpoch、acceptedReadKeyEpochs、协议版本和本机 pinned control high-water mark；
2. 逐 event 先用已认证父状态授权 control transition；再按 envelope 绑定的 roster/control revision 验证 signer 当时 active，并验证 actor sequence/previous-hash 落入相应冻结 data frontier；最后按当前 head 判断新写可否采纳；
3. 验证/解包 VRS、DEK 与 payloadAAD/wrapAAD；
4. 检查 content/wrap mutationID、actor sequence/hash-chain 幂等与 fork；
5. 依据内容因果 revision 判定 newer/concurrent/stale；wrapper-only mutation 不制造内容冲突；
6. 运行实体冲突规则；
7. 在一个本机事务中写 canonical envelope、projection、AppliedMutation、Conflict/Quarantine，并把 inbound 项标记 applied/quarantined；
8. 事务完成后才发布业务层变化；只有应用 frontier 可验证地前移后，才写 DeviceCheckpoint。

如果验证/应用失败，写 quarantine/diagnostic state，但不前移“已应用”checkpoint、不覆盖良好投影。崩溃测试必须覆盖：记录已取但 batch/state 未存、batch/state 已存但尚未解密、锁定态重启后解锁继续。

CloudKit 的 record-deleted callback 本身没有应用层签名，不是业务删除证明。普通业务删除只接受仍可验证 signer、因果链、generation/erase/key epochs 和 payload AAD 的**签名 tombstone envelope**；active generation 中意外收到裸 physical-delete marker 时，必须隔离该事件、保留最后良好 canonical envelope/投影、重新抓取 control/data 状态并提示完整性故障。只有已认证 manifest/control event 明确授权旧 generation GC，且本机已越过对应 checkpoint 时，才能把该 generation 的 physical delete 记为传输层 GC 回执；不得由裸 marker 生成业务 tombstone。

## 5. 冲突状态机

    conflictDetected
      → loadAncestorClientServer
      → verifyAndDecryptAll
      → classify
        ├─ duplicateMutation → acknowledgeExisting
        ├─ causallyStale → ignoreAndRecord
        ├─ autoMergeSafe → createMergedMutation → requeued
        ├─ deleteConflict → tombstonePrimary + recoverableSibling
        └─ manualRequired → persistConflictSiblings

自动合并只允许规格列出的确定性规则。不得因为 UI 尚未实现冲突页就退回 updatedAt LWW。

## 6. 冲突矩阵

| 类型 | 规则 |
| --- | --- |
| 密钥/admin secret 同时变更 | 手工选择；保留所有密文 siblings |
| 同记录不同普通字段 | 有共同 ancestor 且字段不相交时三路合并；否则 sibling |
| 同字段并发 | sibling；不拼接、不猜测 |
| 编辑 vs 普通删除 | tombstone 主导不可见；编辑作为回收/冲突 sibling |
| 指派 present vs delete | remove-wins；保存审计，显式重新添加产生新 mutation |
| 低 `eraseEpoch` vs 当前 | 当前 `eraseEpoch` 无条件胜；旧 mutation quarantine/ignore；不得据此推断 `generation`、`writeKeyEpoch` 或 `acceptedReadKeyEpochs` |
| 完全相同 mutationID | 幂等去重 |
| 安全偏好 | 走独立保守合并契约；安全降低不得被不确定冲突自动采用 |

## 7. 发送与批次

- 从 durable outbox 选择当前 account/zone/generation 且未阻塞的 mutation；
- 保持同一 record 的因果顺序；
- control mutation 与依赖的数据 mutation 不混成不可解释的批次；
- 只有明确需要的同 zone 记录组使用 atomicByZone；
- 批次产品上限低于 CloudKit 250 条硬上限；
- 逐记录处理 success/failure，不能用“批次请求返回”统一标成功；
- partial failure 后只重试可重试项；永久错误隔离；
- 遵守 CloudKit retry-after，不做无上限立即循环。

## 8. 用户可见状态

| 内部证据 | 可显示文案 |
| --- | --- |
| localDurable，尚未入发送 | 已保存在本机 |
| queued/offline | 等待上传 |
| inFlight | 正在发送到 iCloud |
| 当前 mutation server success | iCloud 已接受 |
| 本设备拉取并应用远端变化 | 此设备已更新 |
| 指定 DeviceCheckpoint 越过 mutation | 设备“名称”已确认 |
| 所有当前 active 设备均确认 | 所有已登记设备已确认；必须列出集合和时间 |
| conflict | 需要处理同步冲突 |
| accountUnavailable | 请登录 iCloud 后继续 |
| recoveryRequired | 此设备尚未获得保险库密钥 |
| permanentFailure | 此项无法同步；显示安全的具体原因 |

禁止单独显示无来源的“同步完成”“实时同步”“全部设备已更新”。

## 9. 账号、token 与 zone 异常

### Account change

- 立即停止当前发送；
- 锁定 UI 的敏感读取；
- 保存未发送 outbox，但绑定原账号；
- 保留未应用 inbound，以及 bootstrap/pinned-head/migration/cleanup/rotation/erase journals，但全部绑定原账号；不得在新账号继续；
- 清除内存 VRS/DEK；
- 隔离原账号 projection/cache/engine state；
- 新账号不得自动上传原账号 outbox；
- 用户切回原账号后才恢复，或走明确的本机导出/删除。

### Change token expired

- 不删除良好 projection；
- 对 active control/data zones 做全量抓取到 durable inbound/rebuild store；
- 沿不可变 control history 分别完成历史 roster、签名/AEAD、generation、eraseEpoch、writeKeyEpoch、acceptedReadKeyEpochs 与 tombstone 验证；
- 与本机 pending mutations 做冲突重放；
- 原子切换 canonical store + projection + 新 engine state。

### Zone missing/deleted

- 先读取 control manifest；
- 合法旧 generation 删除：确认 GC；
- active data zone 缺失：进入 recovery，不得拿本机旧记录自动重建；
- control zone 缺失：区分首次创建、账号变化和异常删除，须用户确认；Recovery Credential 单独没有 RecoveryKeyShare/manifest 不能凭空恢复，只有仍可信设备、已验证加密备份或未来获批 Recovery Kit 才能恢复，否则失败关闭并明确不可恢复。

## 10. 高风险控制授权与密钥替换（G1 待裁决）

### 10.1 管理员权

本合同尚不能假定“任一 active device 都能管理一切”，也不能擅自引入 quorum。D13 必须选择并冻结：

- **1-of-N 单设备管理员权（推荐候选）**：任一 active device 可签一个 control event，适合个人/单设备恢复，但单台 active device compromise 的控制面影响更大；
- **quorum**：指定高风险 event 需要 M-of-N active devices；必须同时定义 N=1、设备丢失、全部其他设备离线和 Recovery-only 的逃生规则，不能用实现默认降回单签。

无论采用哪一项，ControlEvent N 仍只能由父状态 N−1 授权。D14 还必须独立决定：普通验证方式为“不验证”时，新设备批准、撤销、Recovery Credential 替换、compromise replacement 和清除/重置是否仍强制 `deviceOwnerAuthentication`。当前 FR-061 尚未修改，候选规则不得提前落地。

### 10.2 routine rotation 与 compromise replacement

常规轮换状态：

    routineRequested
      → nextVRSAndWrappersPrepared
      → writeKeyEpochActivated
      → oldEpochKeptInAcceptedReadSet
      → DEKRewrap
      → activeDeviceAckObservation
      → oldReadEpochRemoved

常规轮换可以保持 payload ciphertext/DEK 不变，只增新 wrapper；因此持有旧 VRS 的人仍可解其已取得的旧 DEK wrapper/ciphertext。它不得显示为“历史数据已重新安全”。

疑似泄露替换状态：

    compromiseDeclared
      → highRiskAuthorizationSatisfied
      → suspectedDeviceAndRecoveryIdentitiesExcluded
      → nextVRSAndWriteKeyEpochPrepared
      → allLivePayloadsReencryptedWithFreshDEKAndNonce
      → replacementManifestActivated
      → remainingDeviceAckObservation
      → oldReadEpochAndWrappersRetired

compromise replacement 必须为全部仍存活内容生成新 DEK、nonce 和 ciphertext，而不是只重包；若 Recovery Credential 也疑似泄露则必须更换 `recoveryEpoch`/keypairs。它只能保护替换完成后的内容版本，不能追回攻击者在此前已取得的明文、ciphertext 或 wrapper。D15 未裁决前，两个流程均不得进入实现或共享一个含糊的“轮换”按钮。

### 10.3 ControlOperation 互斥与优先级

erase/reset、cutover、root/recovery rotation、device revoke 和 legacy cleanup 都必须先通过 manifest CAS 获取唯一 `ControlOperation` 槽，并绑定 operationID、base control head、四类世代、授权与 durable journal。规则如下：

| 当前 active operation | 新操作 | 状态机结果 |
| --- | --- | --- |
| 任意非 erase | erase/reset | 高风险授权后，先持久化 supersede/abort 旧 journal，再由认证 control event 让 erase 接管 |
| erase/reset | 任意 | 拒绝到 erase 完成或按合同安全取消 |
| cutover | rotation/revoke/cleanup | 拒绝并要求先完成或 abort barrier；之后重做 Production shadow checkpoint |
| rotation/revoke | cutover | 拒绝；新 control head/roster/key 集合稳定后重做 shadow/barrier |
| cleanup | cutover/rotation/revoke | 拒绝；不可逆 cleanup 不并发 |
| rotation | revoke | 涉及目标/签署者时 abort/rebase；其他情况也必须以新 head 新建 operation |

CAS loser 必须重新 fetch、恢复/仲裁现有 journal 并重验授权，不能凭本机队列继续。operation 只有在完成、认证 abort 或认证 supersede event 落盘并释放 manifest 槽后才结束；崩溃恢复时 mutation gate 在仲裁完成前保持关闭。

## 11. 删除与 erase

### 普通记录

    live
      → tombstoneLocalDurable
      → tombstoneQueued
      → cloudAccepted
      → retained
      → gcEligible
      → payloadCryptoErased
      → minimalTombstonePurged

产品回收站到期可以销毁 payload/DEK，但最小 tombstone 是否可 GC 取决于设备 checkpoints 和保留期。

恢复与级联必须显式建模：

- 回收站内恢复创建新的 `restore` mutation，绑定被恢复 tombstone ID/revision，并成为其因果后继；不能把旧 live envelope 原样上传；
- 与 tombstone 真并发的 edit 只保存为 recoverable sibling，不自动等同于用户恢复；显式 restore 与另一个设备的新 edit 再按普通因果/冲突规则处理；
- 到期 purge 先持久化不可恢复决定，再销毁 payload DEK，保留最小认证 purge tombstone；此后 restore 必须明确失败；
- 账号/工具级联删除使用稳定 `cascadeID`，为受影响实体/关系生成可恢复 tombstone mutation；部分上传、重试和恢复都以同一 cascadeID 幂等，不能依赖物理 cascade delete；
- 恢复父实体不会默认恢复全部子实体/指派；产品必须在 G3 冻结“整组恢复”或“逐项恢复”，并为并发 child edit/remove 定义结果。

### G1 待选的两种清除语义

当前现行 FR-061 要求“清除全部数据”；下列两种协议不是同义词，D16 和权威回写完成前不得任选其一实现。

**候选 A：内容清空（保留信任）**

- 保留 vaultID、Recovery Credential、device identities、roster/control history；
- 推进 `eraseEpoch`，切换到新 `generation`，明确准备新的 `writeKeyEpoch`/`acceptedReadKeyEpochs`；
- 适合“清空保险库内容后继续使用”，但不能宣称已清除全部身份/信任数据，也不应沿用 FR-061 名称。

**候选 B：保险库重置（推荐映射 FR-061）**

- 退休旧 vault；删除其业务内容、本机 Recovery Credential/设备身份材料和普通偏好；完成后进入 `unconfigured`；
- 用户以后重新启用时，以全新 vaultID、Recovery Credential、device identities，以及全新的 `generation`/`eraseEpoch`/`writeKeyEpoch`/`acceptedReadKeyEpochs` 初始状态 bootstrap，不能把旧 vault 的值递增后冒充新 vault；
- 在 control plane/本机只保留不含业务内容的最小认证 anti-replay/retirement tombstone，使旧设备/旧 outbox 无法把退休 vault 恢复为当前 vault；其字段、保留期和用户披露必须在 G3F 冻结；
- 如果产品要求真正“零残留”，必须显式接受无法可靠识别未知离线旧副本的风险，不能同时承诺永不复活。

下列状态机是两种候选共享的“退休旧内容”骨架；`contentWipeNextGenerationPrepared` 只属于候选 A。候选 B 在远端 retirement 被确认后进入 `unconfigured`，以后另走全新 bootstrap。

发起端：

    reauthenticated
      → localMutationGateSealed
      → accountVaultBoundEraseJournalCommitted
      → localOldProjectionHiddenAndContentKeyCacheCleared
      → waitingForNetworkIfNeeded
      → contentWipeNextGenerationPrepared | vaultRetirementPrepared
      → contentWipeNextVRSAndWrappersVerified | vaultRetirementVerified
      → contentWipeEraseEpochActivated | vaultRetirementActivated
      → legacyCleanupQueued
      → oldDataZoneDeletionQueued
      → deviceAckObservation
      → logicallyComplete
      → cloudOldZoneDeletionObserved
      → activeRegisteredDevicesAcked
      → readyWithPreservedTrust | unconfiguredWithRetirementTombstone

接收端观察到更高 `eraseEpoch`：

    higherEraseEpochObserved
      → receiverEraseJournalCommitted
      → localMutationGateSealed
      → oldGenerationOutboxInboxStoppedOrSuperseded
      → oldProjectionHiddenAndKeyCacheCleared
      → contentWipeNewWrapperAndGenerationFetched | vaultRetirementAccepted
      → signedEraseCheckpoint
      → contentWipeNewGenerationRebuilt | localTrustMaterialDestroyed
      → mutationGateReopened | unconfigured

- manifest 清除 transition 激活后，低于当前 `eraseEpoch` 的内容永远不得进入投影；旧 `writeKeyEpoch` 也不得再用于新写，但是否还能读取只由 `acceptedReadKeyEpochs` 决定；
- journal 必须绑定 account/vault/eraseID、source/target generation、source/target eraseEpoch、清除前后 writeKeyEpoch/acceptedReadKeyEpochs、base manifest tag/control head 与 D16 已批准的模式；账号切换只保持封锁，绝不在另一个账号重放；
- 离线发起时推荐立即让本机旧内容不可见并封住新写，显示“本设备已清除，iCloud 待联网完成”；在 manifest CAS 成功前不得创建新 vault 或重新开放写入。候选 B 还不得在旧 vault retirement 获得确定结果前销毁完成远端 retirement 所需的最后授权材料；该材料只能受限于 journal、不能重新开放普通读取；
- CAS 结果未知时以 eraseID 重读 manifest 裁决，不重复创建另一世代；
- 非 active `generation` 或低 `eraseEpoch` 的 outbox/inbox 必须标 superseded/隔离，不能在当前 generation/eraseEpoch 发送或应用；需要保留的取证只保留密文与脱敏状态；
- erase receiver 还必须根据当前 migration phase 停止 legacy import，并通过绑定本账号/vault 的 cleanup/erase journal 清理或隔离 legacy synchronizable Keychain items、legacy SwiftData local-fallback 与旧 CloudKit metadata/secret source；只隐藏新投影不算接收完成。无法证明安全删除时保持隔离并在 signed erase checkpoint 中明确未完成范围；绝不在另一个 iCloud 账号重放；
- `logicallyComplete`、`cloudOldZoneDeletionObserved` 与 `activeRegisteredDevicesAcked` 必须分开；不存在证明未知永久离线设备本地副本已物理消失的正向 oracle，禁止显示 `physicallyConverged` 或“所有设备永久删除”；
- 候选 A 只有在新 generation/VRS/wrappers 验证后才能重新开放普通写；候选 B 不重新开放旧 vault，而是进入 unconfigured；
- 任一步崩溃由 journal 继续，普通写在安全阶段保持封锁；
- 永久离线/未知 legacy 设备以后上线时，其旧写仍因非 active `generation`、低 `eraseEpoch`、旧 `writeKeyEpoch` 或无效 signer 被拒绝或隔离。

## 12. 重试分类

| 类别 | 例子 | 行为 |
| --- | --- | --- |
| transient | 网络、服务不可用、限流 | 退避重试 |
| accountAction | 未登录、账号变化 | 等用户恢复账号 |
| vaultAction | 待审批、缺 Recovery Key、设备撤销 | 进入设备/恢复流程 |
| conflict | serverRecordChanged、因果并发 | 自动安全合并或用户解决 |
| quarantine | 签名/AEAD/未知版本、非 active generation、低 eraseEpoch、不可读 writeKeyEpoch | 隔离，不重试覆盖 |
| permanentData | 记录超限、无法编码、schema 不兼容 | 阻止该项并给可操作错误 |

所有错误日志只记录错误类别、record opaque ID、mutation ID 和阶段，不记录用户内容或密钥材料。
