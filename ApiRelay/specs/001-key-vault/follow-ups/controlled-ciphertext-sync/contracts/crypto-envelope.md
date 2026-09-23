# Contract Draft: Crypto Envelope

**Status**: G2A/G3 设计草案；须经 G3F 统一冻结，不得据此处理真实数据
**Purpose**: 固定安全不变量和需要产出测试向量的格式，防止实现阶段临时发明密码协议。

## 1. 密钥层级

    Recovery agreement public key ─┐
                                    ↓
    Device P-256 private key ────→ wrapped VRS (per device / recovery / rootKeyEpoch)
                                ↓
                  VRS-derived record wrapping key
                                ↓
                     one or more wrapped DEKs by rootKeyEpoch
                                ↓
                   AES-256-GCM encrypted payload

- VRS：每个 `rootKeyEpoch` 随机 256 bit；manifest 用 `writeKeyEpoch`/`acceptedReadKeyEpochs` 指向这些版本。
- DEK：每条记录每个内容加密世代随机 256 bit。
- device agreement/signing private keys：P-256，设备本地、不可同步。
- 应用密码 verifier、备份口令和 Recovery Credential 是三个不同概念，禁止复用。
- 推荐 Recovery Credential 含独立 agreement/signing keypair：云端只保存公钥；用户离线保存版本化私钥材料。active 设备只需 recovery agreement public key 就能在 root rotation 时包装新 VRS。
- 加设备只增加 DeviceKeyShare，不给每条记录新增设备 wrapper。

### 1.1 世代命名是协议类型，不是可互换整数

- `generation` 选择 data zone/数据世界；只有全量清除或显式 generation transition 改变；
- `eraseEpoch` 是全量清除的不可逆逻辑屏障；低值数据不得进入新投影；
- `writeKeyEpoch` 是新 mutation 必须使用的 VRS/root-key epoch；
- `acceptedReadKeyEpochs` 是读取与 rewrap 期间允许的 root-key epoch 集合，必须显式签入控制面；
- `activeRecoveryEpoch` 选择唯一有权签 recovery admission 的 Recovery Credential 版本；仅紧急停用状态允许显式 `none`，此时所有 recovery admission fail closed。

这些字段使用独立 domain/type，禁止比较数值大小来推导另一字段。`writeKeyEpoch ∈ acceptedReadKeyEpochs` 是必须验证的不变量；普通 root rotation 不改变 `activeRecoveryEpoch`，Recovery Credential 轮换也不暗改 generation、erase 或 write/read key epochs。

## 2. 暂定 crypto suite

| 用途 | 暂定算法 | 冻结要求 |
| --- | --- | --- |
| payload encryption | AES-256-GCM | CryptoKit；系统 CSPRNG nonce；同 key 不复用 |
| DEK wrapping | AES-256-GCM | wrapping key 由 VRS + record context 经 HKDF-SHA256 派生 |
| device VRS wrapping | P-256 ECDH + HKDF-SHA256 + AES-256-GCM | ephemeral sender key；绑定目标 device/vault/epoch |
| device signatures | P-256 ECDSA/SHA-256 | canonical bytes；固定 64-byte `r || s` big-endian 编码并强制 low-S；按签名发生时的 roster/control revision 验证历史合法性，再按当前 head 判断新写可否采纳 |
| recovery wrapping | recovery P-256 ECDH + HKDF-SHA256 + AES-256-GCM | 云端只存 recovery agreement public key；用户持私钥；不使用 app password verifier |
| recovery admission | recovery P-256 ECDSA/SHA-256 | 专用 domain；只授权绑定请求的一次入网，不泛化为任意 control mutation |

这不是最终算法批准。G3F 必须补齐 recovery credential 编码、domain separation labels、salt/info、nonce 生成、错误行为、canonical encoding 和跨版本测试向量；不得从任意用户口令直接映射椭圆曲线私钥。所有 P-256 ECDSA 验证器必须拒绝 DER、可变长度、越界 `r/s` 和 high-S 表示，防止同一签名有多个字节身份；CryptoKit/API 返回格式必须在适配层转换并用固定向量核对。

## 3. Payload seal

输入：

- 完整业务 payload；
- 随机 DEK；
- canonical `payloadAAD`；
- crypto suite/format version。

输出：

- payload nonce；
- ciphertext；
- authentication tag；
- 一个或多个独立 wrapped DEK envelopes；
- 绑定 sealed payload 与完整 wrapper 集合的外层 mutation signature。

任何以下情况必须返回统一的完整性错误并进入 quarantine，不能部分解析后继续：

- tag 不匹配；
- payloadAAD/wrapAAD 中 vault/record/generation/revision/digest 任一不匹配；
- signer 在签名绑定的 `rosterVersion/controlRevision` 当时不处于 active interval；
- 新写不是基于当前 control head/roster/write epoch；
- format/algorithm 不支持；
- payload schema 无法安全迁移；
- canonical bytes 与签名不一致。

## 4. DEK wrapping

建议派生：

    recordWrappingKey = HKDF(
      inputKeyMaterial: VRS,
      salt: vaultID || rootKeyEpoch,
      info: protocolDomain || recordID || schemaVersion
    )

然后以独立 nonce 的 AES-GCM 包装 DEK。每个 wrapper 使用独立且创建后不变的 `wrapAAD`，至少绑定 vaultID、recordID、payload sealed-box digest、content revision、随机 wrapperID、wrapper `rootKeyEpoch` 和 `createdAtWrapRevision`。集合级 wrap mutation ID/revision 不进入既有 wrapper 的 AEAD AAD，否则新增一个 wrapper 会让全部旧 wrapper tag 失效。最终 byte layout、domain label 和上下文长度编码必须在 G3F 测试向量中逐字节固定。

`payloadAAD` 只绑定不可随重包变化的内容身份：format/crypto suite、vaultID、recordID、protocol/schema version、generation、erase epoch、content mutation ID、content parent/revision 和 envelope 内容状态。它不得绑定整个 wrapper 集合、write key epoch 或 wrap revision。

外层 mutation signature 绑定 `payloadAAD`、payload nonce/ciphertext/tag digest、canonical wrapper 集合、content 与集合级 wrap 两组 mutation/revision、signer deviceID、`rosterVersion/controlRevision`、control head hash、actor sequence 和 actor previous-mutation hash。这样 root rotation 可以只新增/删除 wrapper 而不伪造业务内容变更；任何 wrapper 替换仍会被 wrap AEAD 或外层签名发现。

禁止：

- 用 VRS 直接加密所有 payload；
- 从 API key 明文、名称、末位或长度派生 record ID/DEK/nonce；
- 复用 payload nonce 作为 DEK wrapper nonce；
- 忽略 wrapper `rootKeyEpoch` 或 record ID；
- 用 wrapper 集合作 payload AEAD 的 AAD，导致合法 rewrap 必须重加密 payload；
- 把 wrap mutation/revision 当成业务 content mutation/revision 并制造假冲突；
- 在错误日志打印 sealed box、密钥或恢复输入。

## 5. DeviceKeyShare

加入设备 B 时：

1. B 在本机生成 agreement/signing key pair，并用 signing key 签加入请求；
2. 已信任设备 A 验证请求与用户确认；
3. A 与 B agreement public key 做 ECDH，使用固定 domain-separated HKDF 得到 one-time wrapping key；
4. A 分别包装 `acceptedReadKeyEpochs` 中的 VRS，生成 DeviceKeyShare，绑定 vaultID、B deviceID、目标 `rootKeyEpoch`、roster/control revision、当前 control head hash、`generation`、`eraseEpoch`、完整 write/read/recovery epoch 状态、requestID/challenge/expiry 和审批 mutation ID；
5. A 对 share canonical bytes 签名；
6. B 验证批准链、解包 VRS，并回写 signed checkpoint；
7. 未收到有效 checkpoint 前，B 不算 active 完成。

CloudKit 中单独出现 B 的公钥或 DeviceKeyShare 不足以建立信任；必须同时通过 manifest/roster 与批准签名链。

### 5.1 OOB transcript 与包装派生

设备加入必须先构造不可歧义的 canonical `JoinTranscriptV1`，至少包含：

- protocol/crypto suite 与 capability negotiation 结果；
- vaultID（若请求阶段未知，则使用明确的 absent tag，批准时必须绑定最终 vaultID）；
- requestID、challenge、createdAt/expiry；
- requester/approver deviceID 与双方长期 agreement/signing public keys；
- approver 为每个 share 独立生成的 sender ephemeral public key；
- parent control revision/head hash、roster version、generation、erase epoch、write key epoch、完整 accepted read key epoch 集合与 active recovery epoch；
- data checkpoint digest、approval mutation ID 和二维码 payload digest。

二维码只可携带公开、限时、版本化的 `JoinRequestQRV1` 请求子集或其定位信息；该 payload 不含自身 digest，最终 `JoinTranscriptV1` 绑定其 canonical hash，避免自引用。二维码不得携带 VRS/DEK/任何 private material。两端显示的 SAS 必须从 `Hash(domain="ApiRelay/JoinSAS/v1", canonical JoinTranscriptV1)` 派生；用户确认前不得产生有效 approval。CloudKit request 与二维码/SAS 任一不一致均 fail closed。

每个 DeviceKeyShare 使用新的 sender ephemeral key。若最终采用现有标准 HPKE，G2A 必须验证 Apple 平台库、suite、exporter/context 和 canonical key encoding；若不采用 HPKE，则 ECDH + HKDF + AEAD 组合的全部细节必须在 G3F 以测试向量冻结，不能由实现者自行拼装。最低派生边界为：

    sharedSecret = ECDH(senderEphemeralPrivate, targetDeviceAgreementPublic)
    shareKey = HKDF-SHA256(
      IKM: sharedSecret,
      salt: Hash("ApiRelay/JoinSalt/v1" || canonical JoinTranscriptV1),
      info: "ApiRelay/DeviceKeyShare/v1" || vaultID || targetDeviceID || targetReadKeyEpoch
    )

对应 wrapper AAD 必须绑定完整 transcript hash、sender ephemeral public key、目标长期 agreement public key、目标 deviceID、目标 read key epoch、wrapperID、approval mutation ID 和 suite。任何 sender ephemeral key 重用、suite 降级、transcript hash 缺失或 KDF/AAD 字段不一致都拒绝；日志不得记录 shared secret、派生 key 或完整二维码。

## 6. Mutation signature

每个 envelope/control mutation 的签名至少绑定：

- vaultID；
- recordID；
- protocol/schema version；
- `generation`/`eraseEpoch`/`writeKeyEpoch`/完整 `acceptedReadKeyEpochs`/`activeRecoveryEpoch`；
- contentMutationID/content parent/revision；
- wrapMutationID/wrap revision；
- rosterVersion/controlRevision/control head hash；
- actor sequence / actor previous-mutation hash；
- envelope state；
- encrypted payload/wrapped DEK 的 digest；
- signer deviceID。

验证顺序：

1. 结构/长度上限；
2. protocol/version；
3. `generation` 与各类型 epoch 的合法组合；
4. hash-linked control history、rosterVersion 与 signer 当时的 active interval；
5. signature；
6. AEAD；
7. payload schema/业务验证；
8. 幂等/冲突处理。

任何一步失败都不能覆盖现有良好投影。

### 6.1 ControlEvent ID、canonical body 与 ECDSA 唯一编码

ControlEvent 的身份不得依赖签名随机性，也不得把 signature 字段递归纳入自己的 hash：

    unsignedBody = CanonicalEncode(ControlEvent fields excluding eventID and every signature byte field)
    bodyHash = SHA-256("ApiRelay/ControlEventBody/v1" || unsignedBody)
    eventID = "ApiRelay/ControlEvent/v1" || bodyHash
    signatureInput = "ApiRelay/ControlEventSignature/v1" || unsignedBody

`eventID` 在 wire format 中由固定 domain/version tag 与 32-byte canonical unsigned-body hash 组成；接收端必须重算，不能信服务端字段。`unsignedBody` 必须包含 event kind、parent eventID/head hash/revision、before/after 状态摘要、actor frontier、被要求的 signer/authority identities 与其 unsigned proof bodies、mutation nonce，以及所有适用的 generation/erase/write/read/recovery epochs；它明确排除 `eventID`、外层 event signature、RecoveryAuthority signature 和其他 authorization signature 的字节或 digest。这样可先确定 result eventID，再让 RecoveryAuthority/设备签名绑定该 result head，不产生自引用；验证时必须把所有要求的 signatures 分别验完。

签名统一编码为 P-256 ECDSA 的 64 bytes：32-byte big-endian `r` 后接 32-byte big-endian `s`，前导零保留到固定宽度，且 `1 ≤ r,s < n`、`s ≤ n/2`。签名端把 high-S 规范化为 low-S；验证端直接拒绝 high-S、DER、变长或非 canonical 表示。eventID 去重只在重算 body hash、验证 parent chain 和 signature 之后进行；相同 unsigned body 的不同签名字节不能形成第二个事件。

## 7. Recovery Credential

推荐使用随机生成、版本化编码的非对称 recovery agreement/signing keypair，而不是用户自选口令。云端仅保存两把 recovery public keys；用户离线保存私钥材料。产品必须：

- 只显示一次并要求用户确认保存；
- 提供打印/离线记录的安全说明；
- 不把 recovery private material 写入日志、剪贴板历史、CloudKit 或分析；
- 明确“没有可信设备且丢失 Recovery Key，数据不可恢复”；
- 允许轮换；新 recovery public keys 激活并实际 round-trip 后，旧 recovery share 才失效；
- root rotation/设备撤销由 active 设备用 recovery agreement public key 为新 VRS 创建 wrapper，无需也不得读取 recovery private material；
- recovery signing private key 只签专用 admission proof，不等同于一般设备控制签名；
- 恢复成功后生成新的设备身份，不复用旧设备私钥。

agreement 与 signing 必须分钥，不能同一 P-256 private key 跨 ECDH/ECDSA 使用。首次 bootstrap 时，recovery signing private key 对固定 `RecoveryAuthority` 承诺签名，绑定 vaultID、两把 recovery public keys、recovery epoch 以及 credential 激活的 parent/result control head；以后 root rotation 不改这份 activation 承诺。轮换 Recovery Credential 时产生新的 activation event/固定承诺，由新 recovery signing private key 与当时 active device 共同认证。恢复端从手中私钥导出预期 public keys并验证该固定承诺，不能信任云端自报的 recovery public key。

轮换必须遵循 `prepared → allAcceptedReadSharesPrepared → privateRoundTripVerified → activationCASCommitted → oldCredentialRetired`。candidate epoch 的 agreement key 必须能真实解开 manifest 中每个 `acceptedReadKeyEpochs` 对应的 VRS share，新 signing key 必须对绑定 rotationID、share-set digest、parent/result head 和一次性 challenge 的 proof 签名；不得用刚生成但尚未离开内存的私钥冒充用户保存后的 round-trip。activation CAS 前旧 recovery epoch 是唯一有效 admission authority；CAS 原子切换 `activeRecoveryEpoch` 后旧 epoch 立即失去 admission 权限，旧记录即使为审计暂留也只是 retired material。CAS 后不得回退；所谓取消必须产生下一次轮换。

首次 bootstrap 同样适用：pending RecoveryAuthority/RecoveryKeyShares 写入后，必须从用户保存并重新提供的 credential 完成全 accepted-read share round-trip，保存 canonical unsigned proof body、其 digest 和独立 signature，才可执行 vault activation CAS。eventID 只绑定 unsigned proof body/digest，不能绑定 signature 字节或其 digest。若产品选择允许离线完成后再上传，必须有覆盖 `bootstrapID`、install nonce digest、candidate key references、云端 change tags、expected parent/result head、unsigned round-trip proof-body digest、独立 proof signature 和阶段的完整 durable journal；只靠内存状态不合格。

Recovery Credential 的可打印编码、校验、二维码/恢复文件和两把私钥的封装格式必须在 G3F 以测试向量冻结。是否允许复制到剪贴板或保存到系统密码 App，必须分别做产品与安全裁决；本草案不默认授权。

## 8. Root/key rotation

### 常规 root rotation

- 生成新 VRS/`rootKeyEpoch`；
- 为所有 active device 创建新 root wrappers，并使用已批准的 recovery agreement public key 创建新 recovery wrapper；
- 验证所有仍 active 设备至少能取得新 wrapper，当前设备实际可解；recovery wrapper 必须绑定已验证过的 recovery public key。若本次操作会让 Recovery Credential 成为唯一剩余路径，激活前必须要求用户重新输入并实际 round-trip；
- manifest 进入双读状态：accepted read epochs 含旧+新，并把 write epoch 切到新；此后新业务 mutation 只用新 epoch；
- 分批给每条既有 DEK 增加新 epoch wrapper；payload ciphertext 不变，content revision 不变，另增 wrap revision；
- 新设备在轮换完成前必须取得所有 accepted read epochs；
- 所有记录重包完成并观察 active device checkpoints 后，从 accepted read epochs 移除旧值；
- 最后才删除旧 DEK wrappers、DeviceKeyShares 和旧 VRS 内存/缓存材料。

通常只重包 DEK，不重加密 payload。若单条 DEK 或 payload 可能泄露，则该记录生成新 DEK并重加密。单一 activeKeyEpoch + 单一 wrappedDEK 无法安全表达中断轮换，禁止采用。

### 设备撤销

- 先发布 revokePending 与新 roster；
- 生成新 VRS/`rootKeyEpoch`，只给仍 active 设备与已批准的 recovery public key 包装；
- write epoch 切到新值后，旧设备 mutation 因旧 epoch/roster 被忽略或 quarantine，新写不得再附旧 wrapper；
- 撤销后的任何内容变更都必须生成新 DEK 与新 payload nonce，并只用新 write epoch 包装；不得沿用旧 DEK 后仅删除旧 wrapper，因为被撤销设备可能已缓存旧 DEK；
- accepted read epochs 暂时保留旧值供合法设备读取历史记录，再完成 DEK rewrap 和旧 key GC。

撤销不能消除旧设备已读取的内容；安全说明必须如实写明。

## 9. 本机访问策略

四档认证与应用密码语义必须继续成立。候选方案是由应用层会话门闩控制用户可见明文，device private key 不在每次解包时额外弹出 userPresence；但这一访问控制参数尚未获 G1 批准，当前不得把候选方案实现为 Production 默认值。

若 G1 最终批准上述候选方案，这意味着：

- 云端泄露与跨设备密钥注入保护显著增强；
- 但已解锁设备上、以本 App 身份执行的恶意代码仍可能绕过应用层门闩；
- 产品不得宣称每次解密都由 Secure Enclave 生物识别强制。

若未来要求 cryptographic user-presence binding，必须同时重设计“应用密码”“不验证”和后台管理凭据，不得在本次暗改。

### 9.1 Secure Enclave / Data Protection Keychain 决策闸门

当前只冻结“生产私钥不得同步、不得落普通文件、不得从最小 key-provider 接口向业务层导出 raw key”这一安全边界；Secure Enclave 提供硬件不可导出性，软件 fallback 不得宣称具备同等级保证。以下参数必须在 G1 形成逐平台矩阵并经实机探针批准，不能由代码默认值决定：

| 决策项 | 必须冻结的内容 |
| --- | --- |
| Secure Enclave key | signing/agreement 各自的 P-256 API、key tag/application label、permanent 属性、access group、最小 OS 与失效错误 |
| Data Protection | 精确 `kSecAttrAccessible`（候选为 WhenUnlockedThisDeviceOnly）、`SecAccessControl` flags、是否要求 user presence、锁屏/重启行为 |
| 软件 fallback | 是否允许、允许的平台/错误类别、software private key 的 Keychain 封装、只暴露签名/ECDH 的最小接口、用户可见降级提示与较弱威胁边界；默认不得静默启用 |
| 测试实现 | simulator/in-memory provider 的编译隔离与 Production 不可达证明 |

G1 未裁决前，Production 路径遇到 Secure Enclave 不支持只能 fail closed 或停留在不可激活状态。不得把 DP Keychain fallback、测试 key 或 raw `Data` 文件存储当作当然可用。若最终允许软件 fallback，其 key identity/security class 必须签入 DeviceRecord capability，后续迁移为 Secure Enclave 时按新设备身份/正式轮换处理，不能原地冒充同一 private key。

## 10. 必须产出的 G3F 测试向量

- 固定 VRS/DEK/nonce/payloadAAD/wrapAAD 的 seal/open 字节结果；
- 只增删 DEK wrapper 时 payload ciphertext/tag/content revision 保持不变，外层签名与 wrap revision 正确变化；
- DeviceKeyShare ECDH/HKDF/wrap/unwrap；
- `JoinTranscriptV1` QR 编解码、SAS、每字段篡改、ephemeral key 重用拒绝；HPKE 候选与显式 ECDH/HKDF/AEAD 候选的互操作/降级测试；
- recovery wrapper、Recovery Credential 编解码和 recovery-admission proof；
- bootstrap credential round-trip、完整 pending journal crash matrix；
- Recovery Credential 轮换每一状态的 crash/cancel/CAS-race/emergency-disable、缺任一 accepted-read share 时拒绝激活；
- mutation canonical bytes、historical roster/control revision 与 signature；ControlEvent eventID 重算、signature excluded hash、raw `r||s`、low-S 与 DER/high-S 拒绝；
- 每个 AAD 字段单独篡改；
- record swap、vault swap、epoch rollback、algorithm downgrade；
- 空 payload、最大 payload、Unicode/时区/locale 无关编码；
- v1 reader 对未知 future version 的 fail-closed 行为；
- key rotation 前后读取与旧 key 拒绝。
