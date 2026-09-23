# Data Model Draft: v1.14 受控密文同步

**Status**: G2A/G3 设计草案；须经 G3F 统一冻结，字段名和编码尚不可用于 Production schema
**Rule**: 所有 CloudKit 变更只能 additive；新协议不得手写或复用 SwiftData 自动 CloudKit 生成的旧 record type。

## 1. 存储拓扑

| 存储域 | 内容 | 同步 | 真相角色 |
| --- | --- | --- | --- |
| Legacy synced SwiftData | 当前账号、密钥元数据、工具、指派、安全偏好等 | 自动 CloudKit | 迁移期 legacy source；切换后核心域 deprecated |
| Legacy synchronizable Keychain | 当前 API key/admin 明文 | iCloud Keychain | 迁移期 legacy source；最后才删除 |
| Controlled control zone | manifest、不可变 control history、设备 roster、VRS wrappers、recovery public keys/wrappers、device checkpoints | CKSyncEngine | 当前协议控制面 |
| Controlled data zone(generation) | 通用 encrypted envelope、墓碑 | CKSyncEngine | 跨设备保险库真相源 |
| Controlled local transaction store | 已验证 envelope、outbox、durable inbound spool、applied mutation、engine state、erase/migration ledger、conflict/quarantine 与 UI 投影 | 不同步 | 同一 local store 内完成原子业务提交和入站落盘；投影是可重建部分 |
| Device Keychain / Secure Enclave | agreement/signing private keys、随机 install nonce、本机 wrapper/账号绑定、pinned control high-water mark、现有 app password verifier | 不同步、ThisDeviceOnly | 本机设备身份、安装绑定、回滚锚点与门闩材料 |

核心规则：账号、API key、管理凭据、工具和指派关系作为闭合图进入同一个加密 payload 协议。Usage/Balance/Pricing 及安全偏好是否进入该域，在 G1 分类表中逐项裁决，不能默认一起搬或默认继续旧同步。

为满足“投影 + envelope + mutation + outbox 同一事务”，这些本机模型必须落在同一个新 local ModelConfiguration/store 中。若 SwiftData 原型证明无法提供所需事务语义，G2A 原型必须改为单一 SQLite/其他 Apple 原生本机 store，或引入先记 journal 再投影的明确协议；禁止把它们拆成两个 store 后仍声称原子。

## 2. CloudKit zone

### 2.1 Control zone

当前产品每个 iCloud private database 只有一个个人 vault，建议使用固定、版本化的 control zone 名（例如 ApiRelayVaultControlV1）与固定 manifest record ID。这样全新设备不必先知道 vaultID 才能发现控制面；bootstrap 也能用同一 record ID 的 CAS 阻止并发创建两个根。它不随普通“清除全部数据”一起删除，否则旧设备可能把旧世界当作首次创建重建。最终名称必须在 G3F 冻结。

包含：

- VaultManifest
- VaultDevice
- DeviceKeyShare
- RecoveryKeyShare
- DeviceCheckpoint
- 不可变 ControlEvent / roster history
- LegacyParticipant / LegacyInventoryCheckpoint（仅迁移窗口）
- CutoverBarrier / CutoverReadyCheckpoint / ProductionShadowCheckpoint（仅迁移窗口）
- LegacyCleanupCheckpoint（仅旧通道退休窗口）
- 必要的控制 mutation/tombstone

### 2.2 Data zone generation

每个 active generation 使用独立 custom zone，包含通用 EncryptedEnvelope。全量清除先准备下一 generation，再在 control manifest 中激活；旧 zone 随后异步删除。

跨 zone 不具备原子性，故 activation 必须是持久状态机：

    preparingGeneration
    → generationReady
    → activatingManifest
    → active
    → deletingPriorGeneration
    → gcObserved

任何中断都根据 manifest 与本机 journal 幂等继续，不能根据“某个 zone 是否存在”猜阶段。

## 3. 控制面记录

### 3.1 VaultManifest

| 字段 | 公开/密文 | 用途 |
| --- | --- | --- |
| vaultID | 公开随机 ID | 绑定所有记录，不由 Apple ID、设备名或密钥明文派生 |
| protocolVersion | 公开 | 协议兼容性与升级 |
| minimumWriterVersion | 公开 | 低版本只能读/隔离，不能写当前世代 |
| activeGeneration | 公开 | 指向当前 data zone |
| eraseEpoch | 公开 | 低 epoch 数据永不进入当前投影 |
| writeKeyEpoch | 公开 | 新 mutation 必须使用的 VRS/wrapping 世代 |
| acceptedReadKeyEpochs | 公开集合 | 轮换期间仍可读取的旧/新世代；不得用单一 active epoch 冒充轮换已完成 |
| rotationState | 公开枚举 | none/prepared/newWritesActive/rewrapping/awaitingAcks/retiringOld |
| activeRecoveryEpoch | 公开/认证，可显式 none | 当前唯一可签 recovery admission 的 Recovery Credential epoch；与 root key epoch 无关；none 只用于紧急停用并拒绝全部 recovery admission |
| recoveryRotationState / targetRecoveryEpoch / recoveryRotationID | 公开/认证 | idle/prepared/allAcceptedReadSharesPrepared/privateRoundTripVerified/activationCASCommitted/oldCredentialRetired，以及候选 epoch/幂等 ID |
| vaultLifecycleState / bootstrapID | 公开/认证 | bootstrapPending/active；pending root 先占位防并发，但未通过 credential round-trip + activation CAS 前不得使用 |
| rosterVersion | 公开 | 设备成员关系版本 |
| migrationPhase / cutoverID / fencingRevision | 公开 | 跨版本切换、全局不可回退点和旧 writer 栅栏 |
| controlOperationKind / controlOperationID / operationBaseControlHead / operationState | 公开/认证 | 同一 vault 同一时间唯一高风险控制操作、优先级仲裁与崩溃恢复 |
| manifestRevision | 公开单调逻辑值 | 控制记录 CAS/回执 |
| priorManifestHash | 公开 digest | 把本次 manifest 变更连接到前一已认证版本 |
| controlHeadRevision / controlHeadHash | 公开 | 指向不可变 control history 的唯一当前 head |
| lastMutationID | 公开随机 ID | 幂等与审计 |
| authenticatedControlPayload | 密文 | 其余敏感控制信息、摘要和批准链 |
| controlMAC/signature | 公开认证材料 | 绑定全部公开头部，防服务端/记录替换 |

Manifest 不能只信任 CloudKit change tag；客户端还必须验证当前 VRS/设备签名产生的认证材料、parent hash 与不可变 control head。每台设备把已接受的最高 revision/head hash 固定在 ThisDeviceOnly 本机状态；较低 revision、同 revision 异 hash 或断链失败关闭。只有 Recovery-only 的全新设备在没有其他锚点时无法排除完整旧快照，必须按威胁模型披露。
`minimumWriterVersion` 只是兼容客户端执行的协议规则，不是 CloudKit 服务端 ACL；它不能阻止旧 App 往 legacy zone 写入。真正的隔离来自新协议不再采纳 legacy 域、generation/epoch 校验和用户完成设备升级/撤销。

#### 3.1.1 世代字段语义

| 字段 | 独立语义 | 禁止的推断 |
| --- | --- | --- |
| `activeGeneration` | 当前 data zone/数据世界 | 不能推断 erase 或 key 状态 |
| `eraseEpoch` | 全量清除的逻辑屏障 | 不能代替 generation；zone 删除完成与否也不能由它推断 |
| `writeKeyEpoch` | 新 mutation 唯一允许使用的 VRS/root-key epoch | 不能代表全部仍可读 key |
| `acceptedReadKeyEpochs` | 显式、经认证的可读 root-key epoch 集合 | 不能由 write epoch 的前后数字范围生成 |
| `activeRecoveryEpoch` | 当前 Recovery Credential admission authority | 不能用作 VRS key epoch，也不随普通 root rotation 自动递增 |

强制不变量：`writeKeyEpoch` 必须属于 `acceptedReadKeyEpochs`；每个 active device 和 active Recovery Credential 必须具有覆盖完整 accepted-read 集合的有效 shares；这些字段分别进入 manifest/control-event canonical body 与相关 request/transcript/checkpoint。任何只写 `keyEpoch` 而无法由 schema 上下文唯一判定为 wrapper/root epoch 的记录均不合格。

### 3.1A ControlEvent / roster history

每次 roster、write/read key epoch、erase epoch、generation、migration phase、recovery public key/active recovery epoch 或 minimum writer version 变化都追加不可变 ControlEvent：

- `eventID`、`controlRevision`、`parentEventID`/`parentControlHash`、event kind、canonical unsigned-body digest；
- 变更前后 roster、generation、erase/write/read/recovery epoch、migration 摘要；
- signer deviceID、signer 当时的 roster version、签名；
- 每个 actor 已接纳的 `(maxSequence, actorHeadHash)` 或等价可验证 data frontier；roster/key/erase transition 以它冻结旧 writer 的历史边界；
- 对恢复入网事件，canonical unsigned recovery-admission proof-body digest 与一次性 requestID 进入 event body；proof signature 单独保存/验证，不进入 eventID；
- 对 cutover/erase，保存 cutoverID/eraseID 和 fencing revision。

ControlEvent N 必须先验证 parent hash，再只用已认证的父状态 N−1 判断 signer/阈值是否有权执行该 transition；事件 N 自报的 after-state 不能给自己授权。VaultDevice 被撤销后仍保留 public keys 与 `joinedRosterVersion…revokedRosterVersion`。历史 envelope 除了验证签名当时 membership，还必须沿 actor sequence/hash chain 落入相应撤销/epoch event 冻结的 accepted frontier；超出 frontier 的“倒填旧 revision”隔离。是否接纳一条**新写**再以当前 manifest/head/roster/write epoch 判断。

ControlEvent 的 ID/签名格式必须唯一：

    unsignedBody = CanonicalEncode(all event fields except eventID and every signature byte field)
    bodyHash = SHA-256("ApiRelay/ControlEventBody/v1" || unsignedBody)
    eventID = "ApiRelay/ControlEvent/v1" || bodyHash
    signatureInput = "ApiRelay/ControlEventSignature/v1" || unsignedBody

外层 event signature、RecoveryAuthority signature 与其他 authorization signature 的字节/digest 都明确不进入 eventID/bodyHash；unsigned body 仍须包含被要求的 signer/authority identities 和各 proof 的无签名正文。由此可先确定 result eventID，再让各方签名绑定它而不产生自引用。ECDSA 固定为 64-byte big-endian `r || s` 且只接受 low-S；DER、变长、high-S 或 eventID 重算不一致全部拒绝。canonical body 必须含 mutation nonce 和所有适用世代，防止同一语义因签名随机性或可塑性生成多个 eventID。

ControlEvent、VaultDevice public key 和 actor frontier 的 GC 由仍存活引用机械决定：任何保留的 envelope、tombstone、conflict、checkpoint、migration/erase journal、accepted read epoch 或审计窗口仍引用某 control revision/actor chain 时，对应 parent chain 与 public key 不得删除。只有压缩证明自身被更新 head 认证、所有 active registered devices 已确认且最低恢复/审计保留期结束后，才可用 checkpoint summary 替代早期明细。

### 3.2 VaultDevice

| 字段 | 用途 |
| --- | --- |
| deviceID | App 生成的随机 ID，不使用硬件序列号 |
| agreementPublicKey | P-256 密钥协商公钥 |
| signingPublicKey | P-256 mutation/审批签名公钥 |
| state | pending / active / revokePending / revoked |
| joinedRosterVersion | 生效时 roster version |
| revokedRosterVersion | 撤销时版本，可空 |
| maxProtocolVersion | 设备支持的最高协议 |
| lastAckedGeneration/eraseEpoch/writeKeyEpoch/readKeyEpochs/activeRecoveryEpoch | 分类型回执边界；不得合并成单一 epoch |
| keyStorageClass / keyCapabilityVersion | Secure Enclave 或经 G1 批准的软件 fallback 能力；不能由客户端自报后直接信任 |
| encryptedLabel | 用户可识别名称，避免明文暴露设备名 |
| approvalProof | 新设备请求、批准 mutation 和签名链 |

设备 state 不可通过删除记录表达；撤销必须有持久事实，避免离线旧副本重现 active。

### 3.3 DeviceKeyShare

每台 active 设备、每个 accepted-read root key epoch 一条：

| 字段 | 用途 |
| --- | --- |
| deviceID / rootKeyEpoch | 唯一逻辑键；rootKeyEpoch 对应 manifest 的 write/read key epoch，不是 recovery epoch |
| cryptoSuite | P-256 ECDH、HKDF、AEAD 的版本 ID |
| senderEphemeralPublicKey / targetAgreementPublicKeyDigest | 包装方为每个 share 新生成一次性 key，并绑定目标长期 agreement key；sender key 禁止重用 |
| wrappedVRS / nonce / tag | 给目标设备的 VRS envelope |
| createdByDeviceID | 批准设备 |
| approvalMutationID / signature | 防伪造、幂等与审计 |
| joinTranscriptHash / sasDigest / requestID / challenge / expiry | 绑定 OOB QR/SAS 与 Cloud request；任何一项不一致拒绝 |
| parentControlHead / generation / eraseEpoch / writeKeyEpoch / acceptedReadKeyEpochs / activeRecoveryEpoch | 冻结批准时上下文，防降级、跨世代重放 |
| revokedAtRosterVersion | 旧 share 失效边界 |

DeviceKeyShare 的 KDF salt/info 与 AEAD AAD 必须绑定 canonical join transcript hash、双方身份/长期 public keys、sender ephemeral public key、目标 device/rootKeyEpoch、suite、control head 和 approval mutation。二维码只保存公开 transcript；SAS 从完整 transcript hash 派生并由用户在两端核对。标准 HPKE 是否采用、采用何种 suite 由 G2A 评估并在 G3F 冻结；未冻结前禁止实现自定义近似方案。

### 3.4 RecoveryKeyShare

| 字段 | 用途 |
| --- | --- |
| recoveryVersion / recoveryEpoch | 恢复格式与凭据轮换版本 |
| agreementPublicKey / signingPublicKey | 云端保存的 recovery public keys；私钥只在用户离线凭据中 |
| rootKeyEpoch | 对应 VRS 世代；每个 recoveryEpoch 必须覆盖 manifest 的全部 acceptedReadKeyEpochs |
| ephemeralPublicKey | active 设备为 recovery agreement public key 包装 VRS 时使用 |
| wrappedVRS / nonce / tag | 由 recovery ECDH + domain-separated HKDF 得到的 key 包装 |
| publicKeyProof / activationControlRevision | 防替换并绑定获批 control history |
| recoveryAuthoritySignature | 由 recovery signing private key 绑定 vaultID、两把 recovery public keys、recovery epoch 和 credential activation 的固定 parent/result control head；普通 root rotation 不改写 |
| credentialState / rotationID | candidate/active/retiring/retired/disabled 及所属幂等轮换；candidate 不得签 admission |
| shareSetDigest / privateRoundTripProofBodyDigest / privateRoundTripProofSignature | 覆盖该 recovery epoch 全部 accepted-read shares 及用户重新提供私钥后的验证；只有 unsigned proof-body digest 进入 ControlEvent eventID，signature 单独验证 |
| supersededAtControlRevision | 恢复凭据轮换历史；权限失效由 activation/disable control event 决定，物理删除延后到审计窗口结束 |

Recovery Credential 中 agreement 与 signing 必须是独立 keypair，不能同钥跨 ECDH/ECDSA。恢复端从自己持有的私钥导出预期 public keys，并核对 recovery-authority signature；只从云端读取一个“看起来可解”的 wrapper 不足以证明它属于原 vault。Recovery Credential 私钥默认不存入 CloudKit 或本机明文。是否允许用户选择保存到系统密码管理器是另一项明确产品功能，不能暗中执行。仅有恢复私钥但 control zone/RecoveryKeyShare 已永久丢失时，默认无法凭空找回 wrapped VRS；若产品要求灾难恢复，G1/G3 必须另选加密 Recovery Kit（含版本化 manifest/checkpoint 和 wrapped VRS）或外部托管，而不能在实现时假定 CloudKit 总能提供控制面。

轮换必须严格按 `prepared → allAcceptedReadSharesPrepared → privateRoundTripVerified → activationCASCommitted → oldCredentialRetired`。激活 CAS 之前旧 epoch 是唯一 admission authority；CAS 原子切换 `activeRecoveryEpoch` 后，旧 epoch 即使尚未物理 GC 也不能再 admission。CAS 前可取消 candidate，CAS 后只能向前完成或开始下一次轮换。疑似泄露时允许 active device 先提交 emergency-disable CAS，把 recovery admission 暂停，再完整建立并 round-trip 新 credential；不允许跳过私钥 round-trip。

### 3.5 DeviceCheckpoint

| 字段 | 用途 |
| --- | --- |
| deviceID | 回执设备 |
| generation/eraseEpoch/writeKeyEpoch/acceptedReadKeyEpochs/activeRecoveryEpoch | 已理解并应用的分类型世代 |
| manifestRevision | 已应用控制面版本 |
| controlHeadHash | 已验证并固定的控制链 head |
| mutationWatermark | 已应用边界；必须是可验证 frontier/root，具体编码在 G3F 冻结 |
| dataCheckpointDigest | 设备实际应用的数据 frontier；必须可验证，不得只用设备自报计数 |
| protocolVersion | 设备写入协议 |
| updatedAt | 只用于状态展示和失联提醒，不作冲突唯一依据 |
| signature | 设备签名，防伪造回执 |

Checkpoint 只能证明这台设备明确回执的边界，不能推导未登记设备或永久离线旧版本已完成。

## 4. EncryptedEnvelope

为减少云端元数据，所有业务实体优先使用单一通用 record type。建议公开字段如下，最终字段名和类型必须在 disposable container 验证后冻结：

| 字段 | 用途 |
| --- | --- |
| vaultID | 防跨 vault 搬运 |
| recordID | 随机稳定 ID；不由 API key 明文派生 |
| protocolVersion / schemaVersion | 格式与 payload 演进 |
| generation / eraseEpoch | 内容所属 data-zone/清除世代；两个字段分别验证 |
| contentMutationID | 业务内容幂等 ID |
| contentParentRevision / contentRevision | 业务因果与冲突检测；重包时不变 |
| wrapMutationID / wrapRevision | 仅描述 wrapper 集合变化，不制造业务内容冲突 |
| actorSequence / actorPreviousMutationHash | 同一 signer 的单调 hash chain；防撤销后倒填旧 revision |
| state | live / tombstone / conflictSibling；若可放入密文则进一步减少公开字段 |
| cryptoSuite / aadVersion | 算法敏捷性 |
| dekWraps | 一个或多个 `{wrapperID,rootKeyEpoch,createdAtWrapRevision,wrappedDEK,nonce,tag}`；rootKeyEpoch 必须在签名绑定的 accepted-read 集合中，轮换期允许旧+新 |
| payloadNonce / ciphertext / payloadTag | 业务 payload AEAD |
| signerDeviceID / signerRosterVersion / signerControlRevision | 沿历史 control chain 验证 signer 当时合法；另按当前 head 判断新写可否接纳 |
| controlHeadHash / mutationSignature | 外层签名绑定 payload sealed box 与 canonical wrapper 集合 |

### 4.1 Encrypted payload

payload 至少包含：

- entity type；
- 原有稳定逻辑 UUID；
- 完整业务字段；
- API key/admin credential secret（若该实体持有）；
- version vector/parent set；
- created/updated display time；
- tombstone 的产品删除语义；
- 可选 conflict provenance。

APIKeyRecord.id 当前同时是关系外键和 Keychain account。迁移必须原样保留该逻辑 UUID，不能因为生成新 recordID 而重建业务 ID。

### 4.2 Payload AAD、Wrap AAD 与外层签名

`payloadAAD` 只绑定不会因 root rewrap 改变的内容身份：

    formatVersion
    cryptoSuite
    vaultID
    recordID
    protocolVersion
    schemaVersion
    generation
    eraseEpoch
    contentMutationID
    contentParentRevision/contentRevision
    envelope state

每个 `wrapAAD` 单独绑定：

    vaultID/recordID
    payload sealed-box digest
    contentRevision
    wrapperID
    wrapper rootKeyEpoch
    createdAtWrapRevision

外层签名再绑定 payload sealed box、排序后的完整 wrapper 集合、content/wrap 两组 revision、signerRosterVersion/controlRevision、controlHeadHash、actorSequence 和 actorPreviousMutationHash。新增/删除 wrapper 只改变集合级 wrap revision 与外层签名，payload ciphertext/tag/content revision 以及未变化 wrapper 的 AEAD tag 必须保持不变。

字段必须采用长度前缀、固定字节序和固定顺序的 canonical encoding；禁止 JSON 字符串随手拼接。byte-level 格式和测试向量在 G3F 统一冻结。

### 4.3 记录大小

- 平台硬上限不是产品上限；实现必须预留 envelope、索引和未来字段空间。
- 计划建议单条 payload 的产品上限先定为 256 KiB，批次最多 200 条，再由原型测量调整。
- 超限在本机业务提交前返回明确错误，不能先写投影后等 CloudKit 拒绝。

## 5. 同一 Controlled Local Store 内的持久模型

### 5.1 LocalEnvelope

- recordID
- 最近验证通过的完整 envelope
- server change tag/system fields
- verification status
- received/applied timestamps（仅诊断）
- 当前 projection revision

存密文，不存 API key 明文。

### 5.2 PendingMutation

| 字段 | 用途 |
| --- | --- |
| mutationID | 本机幂等主键 |
| recordID | 目标 |
| kind | save/delete/control/ack |
| encryptedEnvelope | 待发送 canonical record 数据 |
| baseServerChangeTag | CAS 基线 |
| localTransactionID | 与投影提交关联 |
| state | durable/queued/inFlight/accepted/conflict/permanentFailure |
| attemptCount/nextAttemptAt | 重试策略 |
| lastErrorClass | 脱敏错误类别 |
| createdAt | UI 等待时长，不用于冲突 |

只有收到逐记录 CloudKit success 才能标 accepted。进程崩溃时，inFlight 回到可重试；同一 mutation ID 重放不产生重复业务副作用。

### 5.3 AppliedMutation

- mutationID
- recordID
- revisionStamp
- generation/eraseEpoch/rootKeyEpoch
- 应用结果（applied/ignoredOldEpoch/conflict/quarantined）

用于幂等和诊断；保留/压缩策略在 G3F 定义，不能无界增长也不能过早忘记离线窗口。

### 5.4 ConflictSibling

- 冲突的多个 envelope/revision；
- common ancestor（可得时）；
- 冲突类别；
- 当前主投影选择；
- 用户解决 mutation；
- 解决后保留的审计/GC 边界。

密钥内容冲突必须保存两份密文 sibling。不得把 loser 丢掉后只留一条错误日志。

### 5.5 QuarantineEntry

- 原始 envelope/legacy locator；
- 原因：unknownVersion、badSignature、authFailed、missingWrapper、oldEpoch、orphan、corrupt；
- 首次/最近观察时间；
- 用户可执行动作；
- 是否阻塞迁移或只阻塞该记录。

Quarantine 不得把完整密文或密钥材料输出到普通日志。

### 5.6 SyncEngineState

- iCloud account binding（不可记录可识别账号明文）；
- CKSyncEngine state serialization；
- zone/generation；
- 持久化 revision；
- last successful fetch/send checkpoint。

远端批次的每个 durable inbound item 和新 state serialization 必须在同一个本机事务边界中落盘，避免 token 前进而入站数据未持久化；业务解密/投影应用可在解锁后的第二事务完成。

### 5.7 PendingInboundChange / InboundBatch

锁定态也能持久接收密文，但不能假装已经完成业务应用：

| 字段 | 用途 |
| --- | --- |
| inboundBatchID / itemID | 幂等落盘与批次关联 |
| accountBinding / vaultID | 防账号切换串用 |
| zoneID / generation | 绑定来源世代 |
| recordID / changeKind | save 或 transportPhysicalDelete；后者不是业务删除证明 |
| encryptedRecordAndSystemFields | 原始密文记录和以后 CAS 所需字段；业务删除必须以签名 tombstone envelope 表达，裸 physical delete 只保留传输取证 |
| fetchedEngineRevision | 对应 CKSyncEngine state 更新 |
| state | durable / needsUnlock / validating / applied / quarantined / supersededByErase |
| receivedAt / errorClass | 仅诊断，不用于冲突胜负 |

同一 fetched batch 的每一项必须和对应的新 `stateSerialization` 在同一个本机持久边界落盘；做不到就不保存新 engine state，允许系统重投并依 itemID 去重。解锁后的验签、解密、冲突、投影更新与 AppliedMutation 是第二个事务。`needsUnlock` 是正常等待态，不得伪装成 missing wrapper 或 quarantine；DeviceCheckpoint 只能在第二阶段成功后前移。

### 5.8 PinnedControlState

- accountBinding / vaultID / installNonceDigest；
- highestControlRevision / controlHeadHash；
- manifest hash / roster version / generation / eraseEpoch / writeKeyEpoch / acceptedReadKeyEpochs / activeRecoveryEpoch；
- 初始锚点来源：bootstrap、可信设备 approval transcript 或 Recovery-only；
- trusted-device approval 传入的 data checkpoint digest；
- 最后验证结果。

高水位的关键 anchor 与随机 `installNonce` 必须放 ThisDeviceOnly Keychain，local store 只保存可核对镜像和 nonce 的 domain-separated digest。install nonce 不是 deviceID、不得同步；不匹配表示本地数据库来自另一安装，不能据此恢复旧设备身份。降 revision、同 revision 异 hash 或断链时 fail closed；删除 App 后只凭 Recovery Credential 重装属于已披露的“无本地最新性锚点”恢复边界。

由于 local store 与 Keychain 不能原子提交，必须增加 `PinnedHeadAdvanceJournal`：

| 字段 | 用途 |
| --- | --- |
| advanceID / accountBinding / vaultID / installNonceDigest | 幂等且绑定当前安装 |
| fromRevision/fromHead → toRevision/toHead | 只允许沿已验证 parent chain 单调推进 |
| manifest/controlEvent digest | 允许重启后重新验证候选 head |
| stage | prepared / keychainAdvanced / localFinalized |
| createdAt / errorClass | 诊断，不参与信任判断 |

恢复顺序固定为 Keychain → local journal/store → Cloud：

1. 先读取 Keychain 的 install nonce、device key references 与 pinned head；
2. 再打开 local store，要求 nonce digest/account/vault 匹配；
3. `prepared` 且 Keychain 仍在 fromHead：丢弃或重新验证后重试；
4. Keychain 已在 toHead、local 尚未 finalized：从已认证 envelope/control chain 重建 local mirror 后 finalize，绝不降低 Keychain；
5. local 声称 finalized/toHead 但 Keychain 仍旧：fail closed，只有重新验证完整链并先推进 Keychain 才可完成；local 自报值不能覆盖 anchor；
6. 最后才从 Cloud 接受 toHead 的后继并重复上述协议。

### 5.9 BootstrapRecoveryJournal / RecoveryRotationJournal

`BootstrapRecoveryJournal` 至少包含：accountBinding、installNonceDigest、bootstrapID、candidate vaultID、device key references、pending manifest/control record IDs 与 change tags、expected parent/result head、generation/erase/write/read/recovery epochs、RecoveryAuthority/share-set digests、private round-trip unsigned proof-body digest、独立 proof signature、stage、cleanup status。stage 为：

    prepared
    → pendingCloudWritten
    → deviceShareVerified
    → recoveryPrivateRoundTripVerified
    → activationCASCommitted
    → checkpointCommitted
    → complete

journal 不得保存 Recovery Credential private material。activation CAS 前取消只清理与 bootstrapID 精确匹配且能证明未激活的 pending records；CAS 后只能向前恢复。若 Keychain 已固定 activation head 而 local journal 落后，必须按已认证云端状态重建，不能回滚为未创建。

`RecoveryRotationJournal` 至少包含：accountBinding/vaultID/installNonceDigest、rotationID、source/target recovery epochs、base manifest change tag/control head、冻结的 acceptedReadKeyEpochs、candidate public-key/authority/share-set digests、private round-trip unsigned proof-body digest、独立 proof signature、activation eventID、stage、cleanup/checkpoint status。stage 与 manifest 的状态机一致：

    prepared
    → allAcceptedReadSharesPrepared
    → privateRoundTripVerified
    → activationCASCommitted
    → oldCredentialRetired

CAS 前旧 epoch 保持唯一 active，可幂等继续或取消 candidate；CAS 后 target epoch 是唯一 active，崩溃恢复只向前。`emergencyDisabled` 是独立、经高风险认证的控制事件：它立即让旧 epoch 失去 admission 权限，但不能把未 round-trip 的 candidate 直接激活。

### 5.10 DistributedEraseJournal

- accountBinding / vaultID / eraseID；
- role：initiator 或 receiver；
- source/target generation 与 erase epoch；
- base manifest change tag/control head、目标 manifest revision；
- stage、sealed mutation gate、旧 outbox/inbox 处置进度；
- projection/key-cache 清理、new wrapper/generation 获取、checkpoint 与 cloud zone deletion 状态。

账号切换时 journal 保持封锁并只按原 accountBinding 恢复，不得在账号 B 重放账号 A 的清除。发起端离线时只完成本机逻辑不可见和封写，云端激活待联网；接收端观察到更高 erase epoch 后也必须先写 journal 再做副作用。

### 5.11 MigrationLedger / LegacyParticipant

- stable migration ID；
- legacy logical ID/service/account locator；
- 分类：verified/waitingForLegacySecret/metadataOnlyAllowed/orphanSecret/duplicateIdentity/conflict/softDeleted/corrupt/unknown/blockedByLegacyRecovery；
- shadow envelope record ID；
- round-trip 结果；
- last legacy revision/增量捕获点；
- phase/checkpoint/error class。

ledger 不得存 secret hash、末位、长度或明文。核对只在内存完成，结果记录为布尔与结构计数。

每台 shadow 版本设备还要登记 `LegacyParticipant` 与签名 `LegacyInventoryCheckpoint`：install/device ID、build/protocol、legacy store 模式（CloudKit mirrored 或 local fallback）、scan generation、opaque logical ID 集合或受审计计数、secret availability、metadata candidate 状态和签名。cutover 前冻结 participant-set revision；每个已登记参与者必须确认，或由用户逐台显式排除并接受风险。旧架构没有全局 roster，不能把“未发现其他设备”当作它们不存在，也不能把 cleanup 文案扩大成未知离线设备已清理。

### 5.12 MigrationOperationJournal / LegacyCleanupJournal

迁移和旧通道清理必须使用各自的新 journal，不能直接复用 v1.13.9 的 `DataEraseJournal`。旧 journal 没有 migration/cutover/cleanup ID、participant-set revision、control head 和四类世代绑定，复用会把“本机删除恢复”误当成“跨设备协议恢复”。

`MigrationOperationJournal` 至少包含：

- accountBinding / vaultID / installNonceDigest / migrationID / cutoverID；
- base manifest change tag/control head、participant-set revision、ProductionShadowCheckpoint digest；
- source/target generation、eraseEpoch、writeKeyEpoch、acceptedReadKeyEpochs；
- 当前 phase、sealed mutation gate、final-delta frontier、CutoverBarrier/Ready checkpoint 集合；
- 每项已执行副作用、CAS 结果、routing 切换、abort/release 与 error class。

`LegacyCleanupJournal` 至少包含：

- accountBinding / vaultID / installNonceDigest / cleanupID / migrationID；
- base control head、participant-set revision、获批 secret/metadata 范围与不可逆批准证据；
- legacy Keychain service/access group、legacy SwiftData/CloudKit store identity 的固定摘要；
- 每个本机/云端存储的扫描、删除、迟到项处置和逐参与设备 checkpoint；
- sealed mutation gate、stage、重试/失败类别与最终可对外声明的精确边界。

两个 journal 在账号、vault、install nonce、base control head、participant set 或世代任一不匹配时都必须保持 fail-closed；只能由对应账号恢复或由人工执行已定义的安全处置，不能在新账号/新 vault 上继续。

### 5.13 迁移屏障与签名 checkpoint

`ProductionShadowCheckpoint` 必须绑定 vaultID/accountBinding、migrationID、control head、manifest revision、generation、erase/write/read/recovery epochs、participant-set revision、可验证 data frontier、shadow graph digest、checkpoint ID 与签名。上述任一绑定值变化都会使 checkpoint 失效，必须重新完成 Production shadow 核对；一个 vault/环境的 checkpoint 不能代替另一个。

`CutoverBarrier` 必须包含 cutoverID、base control head/change tag、冻结 participant-set revision、required participant IDs、四类世代、final-delta frontier、状态（proposed/collectingReady/committed/aborted）和逻辑过期/替换 revision。每个 required participant 只有在本机 gate 已持久封写、旧事务排空、最后 reconciliation 完成并核对同一 shadow checkpoint 后，才可提交签名 `CutoverReadyCheckpoint`。全体 required participants 对同一 barrier ready 后，coordinator 才能执行 controlled-primary CAS；缺一项、签名不合法或 base head 变化都禁止切换。排除离线设备只能通过用户逐台确认并生成新的 participant-set revision/barrier，不能静默缩小集合。

`LegacyCleanupCheckpoint` 是每个已登记参与设备的签名事实，至少绑定 cleanupID、control head、participant-set revision、scan generation、legacy store mode，并分别证明：本机匹配 service/access group 的 Keychain key/admin items 枚举为空、local-fallback store 已处置、legacy SwiftData/CloudKit 当前可见记录已处置，以及迟到项策略仍生效。它不能证明未知或永久离线安装已经物理删除；产品状态必须继续显示这些未知边界。

### 5.14 ControlOperation 仲裁

同一 vault/control head 同时只能有一个 active `ControlOperation`。操作种类至少包括 erase/reset、cutover、root/recovery rotation、device revoke 和 legacy cleanup；每个操作绑定 operationID、base control head、四类世代、发起授权、journal ID 与状态。所有提议通过 manifest CAS 获取操作槽；CAS loser 必须重新抓取并按新 head 重验，禁止在本机排队后盲目执行。

优先级与互斥规则：

| 已在执行 | 新请求 | 结果 |
| --- | --- | --- |
| 任意操作 | erase/reset | 高风险授权后由 erase 明确 supersede/abort 旧操作；旧 journal 先持久记录被替代，再进入 erase |
| erase/reset | 任意其他操作 | 拒绝，直到 erase 完成或按合同安全取消 |
| cutover | rotation/revoke/cleanup | 拒绝；先完成或中止 barrier，重新建立 shadow checkpoint |
| rotation/revoke | cutover | 拒绝；控制 head/roster/key 集合稳定后重新 shadow 核对 |
| cleanup | cutover/rotation/revoke | 拒绝；不可逆 cleanup 不与其他控制变更并行 |
| rotation | revoke | 若撤销涉及轮换目标/签署者则 abort/rebase rotation；否则也必须以新 head 建新 operation，不能沿用旧 CAS |

操作完成、abort 或 supersede 都必须产生已认证 ControlEvent 并释放槽；只清理本机 flag 不算释放。

## 6. 本机 SwiftData 投影

新投影可以复用现有领域概念，但必须：

- 配置 cloudKitDatabase: .none；
- 将 API key/admin credential 明文排除；
- 由 VaultProjectionRepository 从已认证 envelope 构建；
- 带 sourceRecordID、projectionRevision、generation、conflictState；
- 可以整体丢弃并从 canonical envelopes 重建；
- 不能反过来绕过 transaction coordinator 直接写云端。

是否继续以现有 synced/local ModelConfiguration 名称承载 legacy store，必须在迁移计划中保持稳定。新 store 使用新名称和路径，不能改名冒充旧库，否则会像空库。

## 7. 设备本机密钥材料

| 材料 | 保存位置 | 同步 | 说明 |
| --- | --- | --- | --- |
| agreement private key | Secure Enclave；仅当 G1 明确批准时才允许 DP Keychain fallback | 否 | P-256；用于解包 VRS；禁止静默降级 |
| signing private key | Secure Enclave；仅当 G1 明确批准时才允许 DP Keychain fallback | 否 | P-256；签 mutation/ack/approval；禁止静默降级 |
| public keys | Cloud control zone | 是 | 不敏感，但必须由批准链绑定 |
| VRS raw bytes | 仅短生命周期内存 | 否 | 不长期落盘 |
| wrapped VRS | Cloud + local cache | 是/本机 | 只能由目标设备或 recovery factor 解开 |
| DEK raw bytes | 单次加解密内存 | 否 | 每记录随机 |
| 应用密码 verifier | 现有 ThisDeviceOnly Keychain | 否 | 继续只作本机门闩 |
| Recovery Credential private key material | 用户离线持有；默认不落盘 | 否 | agreement/signing 两个角色分钥；与应用密码/备份口令分离 |
| recovery public keys / RecoveryKeyShare | Cloud control zone + local cache | 是/本机 | public key 不敏感，但必须由 Recovery Credential 自签 anchor 与 control history 认证 |
| pinned control high-water mark | ThisDeviceOnly Keychain | 否 | 防已知历史回退；账号/vault 绑定 |
| install nonce | ThisDeviceOnly Keychain | 否 | 每次安装随机生成；local store 只留 domain-separated digest，不作为 deviceID |

锁定、退出账号、切换 vault、会话撤权和内存压力时，VRS/DEK 缓存策略必须有明确清理点。Swift Data 无法提供绝对内存擦除保证，文档只能承诺尽力缩短生命周期，不能夸大。

G1 必须先冻结设备私钥参数矩阵：每个平台/最小 OS 的 Secure Enclave signing/agreement API、key tag/application label、`kSecAttrAccessible`、`SecAccessControl` flags、access group、user-presence 语义、锁屏/重启/备份/迁移/失效行为，以及是否允许 Data Protection Keychain 软件 fallback。若允许 fallback，还要冻结允许触发的错误类别、精确 ThisDeviceOnly 属性、只向业务层暴露签名/ECDH 而不返回 raw key 的最小接口、较弱威胁边界与 UI 安全等级提示，以及升级为 Secure Enclave 时的新身份/轮换协议；不得把软件 key 描述成硬件不可导出。模拟器测试 provider 必须与 Production 编译路径隔离。矩阵和实机探针未批准前，Production 只能 fail closed，不能生成普通文件/raw `Data`/可同步 Keychain 私钥。

## 8. 墓碑与 GC

产品回收站（30 天）与同步墓碑是两个不同生命周期：

- 产品回收站决定用户能否恢复；
- 同步墓碑阻止离线副本复活，可能保留更久；
- 回收站到期可销毁 payload/DEK，使内容不可恢复，但仍保留最小认证 tombstone；
- tombstone GC 要求所有 active device checkpoints 越过边界 + 最低保留期；
- 长期失联设备必须由用户显式撤销后才能从 ack 集合排除；
- eraseEpoch 胜过所有 record tombstone，是全量清除的世代屏障。

## 9. 仍需在 G3F 统一冻结的字段

以下不能由实现者临场决定：

- record names 是否随机 UUID 或由非秘密 logical ID 规范映射；
- revision 采用紧凑 version vector、hybrid logical clock 或 parent DAG；
- canonical binary encoding；
- control record 的认证方式（VRS-derived MAC 与设备签名各负责什么）；
- control parent-hash chain、历史 roster 保留与本机 high-water mark 的精确验证规则；
- ControlEvent unsigned canonical body、domain-separated eventID、64-byte raw low-S ECDSA 编码与测试向量；
- 只有 Recovery Credential 的全新设备如何处理完整有效旧快照回滚；是否接受 CloudKit 最新性，还是新增外部 anchor；
- Recovery Credential 的双 key 编码、校验位、genesis/recovery-authority 签名、完整轮换/CAS/紧急停用与可选 Recovery Kit；
- generation/eraseEpoch/writeKeyEpoch/acceptedReadKeyEpochs/activeRecoveryEpoch 的 wire type 与拒绝非法组合规则；
- bootstrap round-trip journal、install nonce 与 PinnedHeadAdvanceJournal 的跨存储 crash 恢复向量；
- OOB JoinTranscript/QR/SAS、ephemeral sender、KDF/AAD 字段以及 HPKE suite 取舍；
- Secure Enclave/Data Protection Keychain 参数矩阵和软件 fallback 的 G1 结论；
- checkpoint/watermark 的可验证定义；
- durable inbound 与 CKSyncEngine stateSerialization 的同一持久边界；
- cutoverID/fencing revision、participant-set revision 与 distributed erase journal；
- tombstone/applied mutation 的最低保留期；
- production 字段名、索引、大小与批次产品上限；
- Usage/Balance/Pricing/UserPreferences 的最终存储分类。

这些条目未清零前，禁止创建 Production schema。
