# Contract Draft: Device Lifecycle and Recovery

**Status**: G1/G2A/G3 草案；须经 G3F 统一冻结，新设备与恢复产品选择尚待用户批准

## 1. 设备状态

    unregistered
      → keyGenerated
      → registrationPending
      → awaitingApproval | awaitingRecovery
      → activating
      → active
      → revokePending
      → revoked

设备记录不得因卸载或长时间离线自动删除；只有显式撤销才从 active ack 集合移除。

### 1.1 五类世代不得混用

| 名称 | 变化原因 | 允许的判断 |
| --- | --- | --- |
| `generation` | 建立新的 data zone / 全量清除后的新数据世界 | 选择数据命名空间；不能推导密钥是否新旧 |
| `eraseEpoch` | 全量清除完成控制面激活 | 拒绝更低清除世代的数据；不能代替 generation 或 root key epoch |
| `writeKeyEpoch` | VRS/root key 轮换并切换新写 | 规定新 mutation 唯一允许使用的 root key epoch |
| `acceptedReadKeyEpochs` | 轮换窗口开始或旧 key 完成退役 | 明确列出当前仍可读的 root key epochs；它是集合，不得由 `writeKeyEpoch` 推算 |
| `activeRecoveryEpoch` | Recovery Credential 激活/轮换/紧急停用 | 规定哪一版 Recovery Credential 可发起 recovery admission；普通 root rotation 不得改变它 |

`writeKeyEpoch` 必须属于 `acceptedReadKeyEpochs`，但两者不等价。`activeRecoveryEpoch` 与 root key epoch 是两个独立命名空间：一个 Recovery Credential epoch 在轮换窗口内必须分别持有每个 accepted-read key epoch 的 `RecoveryKeyShare`。所有 request、transcript、wrapper、checkpoint 和 control event 都要使用字段全名，禁止继续用含糊的单数 `epoch` 或 `key epoch` 代指多种状态。

## 2. 首台设备 bootstrap

仅在固定 control zone / manifest record ID 经服务端 CAS 确认不存在现有 vault，且账号状态稳定时允许：

1. 建立持久 `BootstrapRecoveryJournal`，生成 `bootstrapID`、随机 vaultID、generation 1、erase epoch 1、write key epoch 1、`acceptedReadKeyEpochs={1}`、recovery epoch 1；journal 只记 key reference 和公开摘要，不记 Recovery Credential 私钥；
2. 生成本机 agreement/signing keys；
3. 生成随机 VRS 与 Recovery Credential keypairs；
4. recovery signing private key 创建固定 RecoveryAuthority 承诺，绑定 vaultID、两把 recovery public keys、recovery epoch 与 genesis parent/result head；再创建首台 DeviceRecord、DeviceKeyShare、RecoveryKeyShare、初始 control event 和 manifest；
5. 在同一 control zone 原子批次写入可原子组合的 **pending bootstrap** 记录；固定 manifest 一经占位就阻止另一个 root，但在最终 activation CAS 前不提供 active vault 权限。恢复端必须从自己持有的 Recovery Credential 导出预期 public keys 并验证 RecoveryAuthority 签名，不能信云端自报公钥。若另一设备先创建固定 manifest，当前 bootstrap 必须中止并转入加入/恢复，不能另建第二个 root；
6. 本机验证能从 DeviceKeyShare 解开 VRS；
7. 要求用户保存面向用户显示的 Recovery Key（即版本化 Recovery Credential 私钥材料），随后必须从用户保存的表示重新扫描/输入，而不是复用仍在生成流程内存中的对象；从该输入导出两把 public keys，核对 RecoveryAuthority，并真实解开 `acceptedReadKeyEpochs` 中每一个 RecoveryKeyShare，再与设备路径解出的 VRS 逐项常量时间比对；
8. 将 round-trip proof 的 canonical unsigned-body digest、独立 proof signature 与完成阶段持久写入 journal；只有上述验证成功，才允许以 pending manifest 的 change tag、bootstrapID、预期 parent/result control head 为条件做 CAS，把 vault、首台设备和 `activeRecoveryEpoch=1` 一次性切为 active；
9. 写 signed DeviceCheckpoint，并在确认 control plane 已接受后完成 journal。

如果任一步失败，必须按 journal 恢复或隔离未激活 bootstrap，不得留下“云上有半个 vault、本机又创建第二个”的状态。activation CAS 之前可以取消并清理与 `bootstrapID` 匹配的 pending 记录；activation CAS 之后是不可回退点，只能向前补 checkpoint 或走正式清除/撤销流程，不能回滚成“未创建”。

### 2.1 bootstrap 崩溃恢复顺序

启动时先读取 ThisDeviceOnly Keychain 的 install nonce/key references/pinned head，再打开 local store 并核对 journal 的 install nonce digest，最后才访问 CloudKit：

1. Keychain 与 journal 均存在且 nonce 匹配：按 `bootstrapID`、manifest change tag 和 stage 幂等继续；
2. Keychain 已固定 activation head、local journal 尚未完成：把本机 store 视为落后副本，从已认证 control head 重建并补 checkpoint，绝不能降低 Keychain high-water mark；
3. local journal 声称已激活但 Keychain 未固定对应 head：fail closed，重新验证完整 control chain 和 activation CAS 后才能推进 Keychain；不得用 local store 自报值覆盖 anchor；
4. install nonce 不匹配或 Keychain 身份材料不存在：把它当作新安装，旧 local store 只可隔离/删除，不能恢复为原设备身份；
5. pending bootstrap 超时也不能只凭时间删除。必须先按固定 manifest 查明 CAS 状态；无法证明未激活时保持隔离并要求联网/人工恢复。

## 3. 新设备加入

### 3.1 已有可信设备批准（推荐主路径）

新设备：

- 本机生成两对 P-256 keys；
- 创建短时 registration request，包含 vaultID（已知时）、deviceID、长期 agreement/signing public keys、协议/crypto suite 能力、随机 challenge、过期时间、requestID 和自签名；
- 计算 canonical request digest。二维码只承载版本化公开 `JoinRequestQRV1`（不含 VRS/私钥，也不含自身 digest），至少包含 requestID、challenge、expiry、目标 deviceID/公钥、能力与 request signature；最终 approval transcript 绑定该 QR payload 的 hash；
- 两台设备基于完整 OOB transcript hash 显示相同的 SAS（短认证串）。用户必须在两台设备逐字核对后批准；只扫到二维码但未核对 SAS 不算批准。

批准设备：

- 必须由用户显式发起并按当前高风险认证确认；
- 从 CloudKit 与近距离 OOB transcript/SAS 两个来源核对 request；任一 digest、expiry 或 capability 不一致即取消；
- 为本次 request 和每个目标 read key epoch 生成全新、不可复用的 sender ephemeral key；按冻结的 KDF/AAD 用 ECDH 结果包装相应 VRS。可否采用标准 HPKE 以及具体 suite 必须在 G2A 评估、G3F 冻结；在此之前不得实现自定义“近似 HPKE”；
- 生成目标设备 DeviceKeyShare 和 roster approval mutation；批准 transcript 必须绑定批准方最新 control head hash/revision、generation/erase/write/read key epochs、active recovery epoch、data checkpoint、requestID/challenge/expiry、双方长期公钥、每个 share 的 sender ephemeral public key、协商 suite、完整 OOB transcript hash/SAS digest 和审批 mutation ID；
- 不把 VRS、Recovery Credential 私钥或设备私钥放入二维码/剪贴板。

新设备：

- 沿不可变 control history 验证批准设备在 transcript 绑定的 roster/control revision 当时处于 active，并核对批准方 control head/data checkpoint；
- 验证 request ID、challenge、目标 deviceID、过期时间和签名；
- 重新计算 OOB transcript hash/SAS；以相同 transcript hash、两端身份、sender ephemeral public key、control head 和完整 epoch 集合验证 KDF info 与 wrapper AAD，禁止接受未绑定 transcript 的 share；
- 解包 VRS，拉取并验证当前 generation；
- 固定批准 transcript 的 control head 为本机初始高水位，回写 signed checkpoint；
- 只有 checkpoint 被 control plane 接受后才显示“设备已加入”。

重复请求、重复批准和迟到批准必须按 request/mutation ID 幂等；已撤销或过期请求拒绝。

### 3.2 Recovery Credential（无其他设备）

- 用户输入版本化、高熵、离线保存的 Recovery Credential；默认内部包含独立 agreement/signing private keys，云端只有对应 public keys；
- 本机生成全新 device agreement/signing keys 与随机 challenge，创建 recovery admission request；
- recovery agreement private key 从当前 RecoveryKeyShare 解包 VRS；recovery signing private key 对专用 admission proof 签名；
- admission proof 必须绑定 vaultID、新 deviceID 与两把公钥、requestID/challenge/expiry、父 control head hash/revision、`generation`、`eraseEpoch`、`writeKeyEpoch`、完整 `acceptedReadKeyEpochs`、`activeRecoveryEpoch` 和目标协议版本；
- 新设备先保持 `activating`。它可以用自己的 signing key 写一条 **pending activation checkpoint**，但该 checkpoint 只有和上述 recovery proof、新 DeviceKeyShare、DeviceRecord 与 manifest CAS 在同一已验证激活事务中才有效；不能用来签其他 control/data mutation；
- control plane 接受激活后，该设备才成为 active；proof/requestID 一次性消费，重复、过期、旧 parent head 或跨 vault 重放全部拒绝；
- 恢复成功后建议轮换 Recovery Credential，并按风险单独发起 root-key rotation 更新 `writeKeyEpoch`/`acceptedReadKeyEpochs`；新凭据 round-trip 成功前不得废止旧 recovery public keys/share；
- 错误输入必须限速且不能泄漏“部分正确”；
- 如果 control plane 表明旧 recovery share 已废止，则不得离线强行打开旧世代。

“能解出 VRS”不是一般控制权。Recovery Credential 只授权绑定到这一次请求的新设备入网；后续 control mutation 仍由 active device identity 按 roster/control history 签名。

没有可信设备且没有 Recovery Credential 时，按零托管目标应明确不可恢复。若产品不能接受这一点，必须先选择托管恢复方案并重写隐私/威胁模型，不能由实现临时加后门。

Recovery Credential 也不是 CloudKit 全量备份：若 control zone/RecoveryKeyShare 和 data records 均永久丢失，它无法凭空恢复。v1.14 推荐在 legacy cleanup 前强制完成独立加密备份 round-trip；自动更新 Recovery Kit 如需承诺，必须另立格式、更新、过期和恢复协议。

### 3.3 Recovery Credential 轮换

Recovery Credential 轮换是独立控制面状态机，不得偷用 root rotation 的 `rotationState`：

    idle(activeRecoveryEpoch = N)
      → prepared(targetRecoveryEpoch = N+1)
      → allAcceptedReadSharesPrepared
      → privateRoundTripVerified
      → activationCASCommitted(activeRecoveryEpoch = N+1)
      → oldCredentialRetired
      → idle

强制顺序和边界：

1. `prepared`：生成全新的 recovery agreement/signing keypairs 和 RecoveryAuthority candidate；candidate 由新 recovery signing key 自签，并由当前有权 active device 对基于旧 head 的 prepare event 联合认证。此时 epoch N 仍是唯一 admission authority；
2. `allAcceptedReadSharesPrepared`：为 manifest 中 **每一个** `acceptedReadKeyEpochs` 创建并验证 epoch N+1 的 RecoveryKeyShare；集合中缺任意一个都禁止继续；
3. `privateRoundTripVerified`：要求用户从已经保存的新版 Recovery Key 重新输入/扫描，重新导出 public keys，验证 authority candidate，逐一解开全部 shares 并与设备已知 VRS 比对，再由新 recovery signing key 对一次性 activation challenge 签名。生成流程内存中的私钥不能替代这次 round-trip；
4. `activationCASCommitted`：以 prepare parent head、目标 recovery epoch、share-set digest、round-trip proof 的 unsigned-body digest（proof signature 单独验证，不进入 eventID）和 manifest change tag 做 CAS；CAS 原子地令 N+1 成为唯一可签 recovery admission 的 `activeRecoveryEpoch`，并把 N 标为 `retiring`。从此即使旧 share 暂留审计，也不能再接受 epoch N proof；
5. `oldCredentialRetired`：观察 control event/必要 checkpoints 后将 N 标为 retired，最后才允许按保留策略 GC 旧 share/public key。物理删除不是权限失效点。

崩溃与取消规则：

- 每一步先写 account/vault/install 绑定的 durable rotation journal，再做副作用；恢复时以已认证 manifest/control head 为准幂等继续；
- activation CAS 前崩溃：旧 epoch 仍 active，可继续或取消；取消只能删除/retire 与 rotationID 精确匹配的 candidate，不能影响旧 credential；
- activation CAS 后崩溃：新 epoch 已 active，只能向前补 retirement/checkpoint，禁止把 manifest 回滚到 N；用户所谓“取消”必须表现为再发起一次新轮换；
- 并发 rotation 依 expected parent head + CAS 只允许一个胜出；迟到 candidate 永不自动激活；
- 如果旧 Recovery Key 疑似泄露，active device 可经高风险认证做 **emergency disable CAS**，把 `activeRecoveryEpoch` 原子设为 `none`、先暂停全部 recovery admission 并永久拒绝旧 epoch，再走完整的新凭据准备、全 read-share round-trip 和激活；暂停期间必须明确提示“只能靠现有可信设备恢复”。不得为了快速替换跳过新凭据私钥 round-trip；
- 如果没有 active device，不能安全紧急停用/替换 Recovery Credential。产品必须说明需先用仍可信的旧凭据恢复一台新设备；旧凭据已经丢失或不能信任且无 active device 时不可恢复。

普通 VRS/root key 轮换只改变 write/read key epochs，并为当前 `activeRecoveryEpoch` 增补 RecoveryKeyShare；它不得递增 `activeRecoveryEpoch`。Recovery Credential 轮换默认也不改变 generation、eraseEpoch 或 writeKeyEpoch。

## 4. 重装与设备密钥丢失

每次安装在 ThisDeviceOnly Keychain 生成随机 `installNonce`；local store 只保存它的 domain-separated digest。App 卸载、设备抹除、install nonce 不匹配或 Secure Enclave key 丢失后，即使 deviceID 记录仍在，也不得把新 key 当作原设备继续：

- 原 DeviceRecord 标为 lost/revokePending（由用户在可信设备上确认）；
- 新安装生成新 deviceID/keys；
- 走可信设备批准或 Recovery Credential；
- 完成后撤销旧设备并执行 root-key rotation；
- 旧 outbox 若只存在本机且没有导出，无法从云端恢复，产品须如实说明。

启动和重装恢复必须遵循“Keychain install binding → local journal/store mirror → Cloud control chain”的固定顺序；Cloud 或 local store 都无权单独重建原设备身份或降低 pinned head。跨存储 crash 的具体 prepared/keychainAdvanced/localFinalized 状态由 `PinnedHeadAdvanceJournal` 恢复。

## 5. 设备撤销

用户必须看到：设备名称、最近回执、协议版本和“撤销不能抹掉此前已复制内容”的说明。

状态机：

    active
      → revokePending
      → nextRosterPrepared
      → nextVRSGenerated
      → remainingDeviceSharesVerified
      → manifestEpochActivated
      → revoked
      → DEKRewrap
      → oldEpochGCEligible

约束：

- 当前唯一设备不得在没有已验证 Recovery Credential/新设备的情况下自我撤销；
- revokePending 后旧设备不能批准新设备；
- 新 `writeKeyEpoch` 激活前必须验证当前设备实际可解，并验证所有 wrapper 都由已认证的目标 public key 正确构造；普通 root-key rotation 不得为了“验证恢复”读取 Recovery Credential 私钥。只有新 Recovery Credential 激活/轮换，或它即将成为唯一剩余恢复路径时，才必须由用户提供私钥材料完成真实 round-trip；
- 旧设备签名的当前 write-key mutation 拒绝；不在 `acceptedReadKeyEpochs` 的 mutation 隔离；
- 若撤销发生在轮换中，依 journal 合并到同一目标 epoch，不能并发开两次 rotation。

## 6. 设备失联和墓碑 GC

- DeviceCheckpoint 的更新时间只用于提醒“该设备很久没上线”，不是自动撤销依据；
- 只要设备仍 active，墓碑/root-key epoch GC 就必须把它算入；
- 用户可在再次认证后显式撤销失联设备；
- 撤销后才允许它从 all-active-device ack 条件排除；
- 如果旧版本根本没有 DeviceRecord，迁移期必须有明确的 enrollment grace window；窗口后 legacy 写入只隔离、不自动采纳。

## 7. iCloud 账号变化

账号变化不是“新设备加入”：

- 清空内存 VRS/DEK；
- 停止当前账号 send/fetch；
- 原账号本机数据保持加密隔离；
- 新账号若无 vault，须显式选择创建；不得静默上传原账号数据；
- 切回原账号可恢复绑定；
- 用户若要把数据迁到另一个 iCloud 账号，必须使用显式加密导出/导入或未来专门迁移协议。

## 8. 应用密码、设备验证和 Recovery Key

| 概念 | 作用 | 能否跨设备 | 忘记/丢失后果 |
| --- | --- | --- | --- |
| 设备验证 | Apple 系统确认设备主人 | 系统自身能力 | 由 Apple/设备恢复 |
| 应用密码 | 本机 App 门闩 verifier | 否 | 经设备主人显式重置；不丢 vault |
| Recovery Key（内部为 Recovery Credential） | 解包 VRS并对一次性恢复入网 proof 签名的离线因子 | 用户手工持有 | 无可信设备且丢失时不可恢复 |
| 备份口令 | 加密导出文件 | 文件随用户转移 | 只影响该备份文件 |

UI 必须使用这四个名字，不能把 Recovery Key 称为“应用密码”，也不能让用户误以为应用密码能恢复云端密文。

## 9. 后台访问的边界

v1.14 推荐只允许后台下载、验证外层结构和持久保存密文；涉及 VRS 解包或业务明文的后台能力不新增。

产品 V2 若要在锁定时自动读取管理凭据，必须另作裁决：

- 安全优先：只在用户解锁 vault 后刷新；
- 自动化优先：为管理凭据建立独立、最小权限、AfterFirstUnlock 的 automation key domain，并披露其本机威胁边界。

不得把所有 vault key 改成后台可读，只为了省掉这项决策。

### 9.1 设备私钥保存参数是 G1 阻断项

实现前必须由 G1 对每个平台/OS 版本逐项冻结：Secure Enclave 的 key 类型和用途、`kSecAttrAccessible`、`SecAccessControl` flags、access group、是否要求 user presence、备份/迁移行为、钥匙失效行为，以及 Data Protection Keychain 软件 key fallback 是否允许及其完全相同的属性。当前文档只确认以下不变量：

- agreement 与 signing 分钥；production key 必须 ThisDeviceOnly、不可同步。Secure Enclave key 要求硬件不可导出；若 G1 允许软件 fallback，只能由最小化 key-provider 接口执行运算、不得向业务层返回 raw key，并必须明确其不能提供同等硬件不可导出保证；
- 不得因为 Secure Enclave 创建失败而静默降级到普通文件、UserDefaults、可同步 Keychain 或无访问控制的 raw key；
- 如果 G1 允许 DP Keychain fallback，UI/遥测必须能区分其安全等级，迁移不能把既有 Secure Enclave identity 悄悄替换成软件 identity；
- 模拟器/测试 key provider 不得进入 Production entitlement/path；
- 在 G1 参数矩阵、最小 OS 实机探针和 key invalidation 测试通过前，G2/G3 只能做 disposable prototype，不能生成 Production 设备身份。

## 10. 验收场景

- 同一加入请求重复发送/批准；
- 请求过期、批准设备在过程中被撤销；
- 伪造 public key、替换目标 deviceID、重放旧 DeviceKeyShare；
- 新设备解包成功但 checkpoint 上传前崩溃；
- 唯一设备尝试自撤销；
- 撤销中断在每个阶段；
- 离线旧设备在新 epoch 后上传；
- Recovery Credential 正确、错误、旧版、已轮换；admission proof 取消、过期、重放、旧 parent head 与跨 vault；
- Recovery Credential rotation 在上述每个状态崩溃；CAS 前取消、CAS 后“取消”、并发轮换、emergency disable，以及 accepted-read share 缺一条时拒绝激活；
- bootstrap 在 pending cloud batch、私钥 round-trip 前后、activation CAS 前后崩溃；确认不会出现 active vault + 未验证 Recovery Key；
- OOB QR 被替换、SAS 不同、transcript 字段降级、sender ephemeral key 重用、KDF/AAD 少绑定一个字段；
- root rotation/紧急撤销在本机不持有 recovery private material 时仍能用 public key 建立新 wrapper；
- 重装后旧 device record/local store 仍在；install nonce 不匹配、Keychain ahead/local ahead 的跨存储恢复；
- iCloud 账号退出、切换、切回；
- Secure Enclave 不可用/密钥失效 fallback；
- 所有恢复因子丢失的明确不可恢复路径。
