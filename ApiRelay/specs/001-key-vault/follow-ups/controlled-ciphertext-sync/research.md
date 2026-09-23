# Research: v1.14 受控密文同步

**Status**: 只读调研结论；不构成实现授权
**Date**: 2026-09-24
**Source policy**: 平台事实只采用 Apple 官方资料；成熟密码管理器的密钥层级参考 Bitwarden 官方白皮书。项目决策与推论明确分开。

## 1. SwiftData 自动 CloudKit 的适用边界

Apple 将 SwiftData/`NSPersistentCloudKitContainer` 自动同步定位为“不需要细粒度控制同步方式”时的方案；需要保留本地持久化并控制同步细节时，Apple 提供 `CKSyncEngine`。SwiftData 同步是机会式并发过程，CloudKit 不能替 SwiftData 强制唯一约束，关系变更也不具备业务事务原子性，生产 schema 后续只能追加。

来源：

- [Deciding whether CloudKit is right for your app](https://developer.apple.com/documentation/cloudkit/deciding-whether-cloudkit-is-right-for-your-app)
- [Syncing model data across a person's devices](https://developer.apple.com/documentation/swiftdata/syncing-model-data-across-a-persons-devices)

**项目决策**：非关键偏好可继续放独立 SwiftData 自动同步 store；保险库核心投影必须改成本机 store（`cloudKitDatabase: .none`），由新协议同步密文。不得让同一核心数据同时被自动 CloudKit 与 CKSyncEngine 管理。

## 2. CKSyncEngine 提供什么、不提供什么

`CKSyncEngine` 让 App 登记待发送变化、提供批次、处理收发事件、持久化 engine state，并可主动发起 `sendChanges`/`fetchChanges`。系统仍会根据网络、电量、负载和账号状态调度；主动调用不是跨设备 barrier。`sentRecordZoneChanges` 只证明当前批次内各记录被服务端接受或拒绝，不证明其他设备已经拉取和应用。

来源：

- [CKSyncEngine](https://developer.apple.com/documentation/cloudkit/cksyncengine-5sie5)
- [WWDC23: Sync to iCloud with CKSyncEngine](https://developer.apple.com/videos/play/wwdc2023/10188/)
- [SentRecordZoneChanges](https://developer.apple.com/documentation/cloudkit/cksyncengine-5sie5/event/sentrecordzonechanges)

后台推送不保证送达，且可能合并。因此推送只能提示“可能有变化”，正确性必须依赖 change token 与可重建抓取。

来源：

- [CKRecordZoneNotification](https://developer.apple.com/documentation/cloudkit/ckrecordzonenotification)
- [Pushing background updates to your app](https://developer.apple.com/documentation/usernotifications/pushing-background-updates-to-your-app)

**项目决策**：产品状态区分 local durable、queued、sending、cloud accepted 和 device ack。没有设备回执记录时，不显示“所有设备已同步”。

## 3. Engine state 不是业务 WAL

Apple 要求 App 自行保存 CKSyncEngine `stateSerialization`。iCloud 账号变化会重置 engine 内部状态，包括未发送变化。因此 engine pending changes 不能成为唯一待办真相源。

来源：

- [CKSyncEngine StateUpdate](https://developer.apple.com/documentation/cloudkit/cksyncenginestateupdateevent)
- [stateSerialization](https://developer.apple.com/documentation/cloudkit/cksyncenginestateupdateevent/stateserialization)
- [CKSyncEngine AccountChange](https://developer.apple.com/documentation/cloudkit/cksyncengine-5sie5/event/accountchange)

**项目决策**：业务 mutation 和 outbox 与本机投影同事务落盘；CKSyncEngine state 是可重建传输状态。账号变化时隔离旧账号投影、VRS wrapper、outbox 和 tokens，不能复用到新账号。

## 4. Custom zone、原子批次和规模上限

CloudKit 私有数据库的 custom zone 支持同一 zone 内的一批记录原子修改；`CKSyncEngine.RecordZoneChangeBatch` 也支持 `atomicByZone`。原子性只覆盖单个请求和单个 zone。CKSyncEngine 单批上限为 250 个 save + delete，单条 CKRecord 不得超过 1 MB；大型迁移、轮换和清除必然跨批。

来源：

- [CKRecordZone](https://developer.apple.com/documentation/cloudkit/ckrecordzone)
- [CKSyncEngine.RecordZoneChangeBatch](https://developer.apple.com/documentation/cloudkit/cksyncengine-5sie5/recordzonechangebatch)
- [`atomicByZone`](https://developer.apple.com/documentation/cloudkit/cksyncengine-5sie5/recordzonechangebatch/atomicbyzone)
- [`CKModifyRecordsOperation.isAtomic`](https://developer.apple.com/documentation/cloudkit/ckmodifyrecordsoperation/isatomic)
- [CKRecord](https://developer.apple.com/documentation/cloudkit/ckrecord)

**项目决策**：控制面与数据面分别建 zone；任何跨 zone、跨批操作都必须有持久阶段、幂等 mutation 和 checkpoint。实现上主动控制在低于平台极限的批次，不能把“整个保险库”描述为一个原子事务。

## 5. 冲突检测与 change token

`ifServerRecordUnchanged` 使用 record change tag 检测并发，`serverRecordChanged` 可提供 ancestor/client/server 版本供 App 决定怎样合并。CloudKit 负责发现冲突，不决定业务语义。密文 blob 无法由服务端做字段级合并。

来源：

- [CKModifyRecordsOperation savePolicy](https://developer.apple.com/documentation/cloudkit/ckmodifyrecordsoperation/savepolicy)
- [`CKError.serverRecordChanged`](https://developer.apple.com/documentation/cloudkit/ckerror/serverrecordchanged)

物理删除会出现在增量变化里，但初次/重建抓取只能看到当前存量；change token 也可能过期。

来源：

- [Fetching record zone changes](https://developer.apple.com/documentation/cloudkit/ckdatabase/recordzonechanges(inzonewith:since:desiredkeys:resultslimit:))
- [`CKError.changeTokenExpired`](https://developer.apple.com/documentation/cloudkit/ckerror/changetokenexpired)

**项目决策**：change tag 用于 CAS；业务层另带 mutation ID、因果 revision、tombstone 和 erase epoch。token 过期时先重建 canonical cache，再原子替换本机投影；物理删除不能替代长期删除事实。

## 6. iCloud 钥匙串的准确能力

Apple 的安全文档说明 iCloud 钥匙串会在用户可信设备间端到端加密同步；同一项目并发更新可能选择其中一个并最终一致。`kSecAttrSynchronizable` 控制条目是否同步，但公开 API 没有每台设备传播进度或“全局完成”回执；synchronizable 条目不能使用 `ThisDeviceOnly` 可访问性。

来源：

- [Secure keychain syncing](https://support.apple.com/en-ca/guide/security/sec0a319b35f/web)
- [`kSecAttrSynchronizable`](https://developer.apple.com/documentation/security/ksecattrsynchronizable)

macOS 的本机非同步密钥材料应显式使用 Data Protection Keychain，而不是依赖 legacy file-based Keychain。

来源：

- [`kSecUseDataProtectionKeychain`](https://developer.apple.com/documentation/security/ksecusedataprotectionkeychain)
- [TN3137: On Mac keychains](https://developer.apple.com/documentation/technotes/tn3137-on-mac-keychains)

**项目决策**：旧钥匙串同步保留为迁移来源，不再作为新架构的核心跨设备真相。设备私钥和本机认证材料使用非同步、ThisDeviceOnly 的现代 Keychain 语义。

## 7. Secure Enclave 的正确用法

Secure Enclave 支持设备内的 NIST P-256 私钥操作，私钥不以明文导出。它适合设备签名、密钥协商或解包小型 key material，不是通用 AES 密钥保险箱。

来源：

- [Protecting keys with the Secure Enclave](https://developer.apple.com/documentation/security/protecting-keys-with-the-secure-enclave)
- [Using keys for encryption](https://developer.apple.com/documentation/security/using-keys-for-encryption)
- [CryptoKit P256 KeyAgreement](https://developer.apple.com/documentation/cryptokit/secureenclave/p256/keyagreement)

**项目决策**：Secure Enclave 内使用设备 P-256 agreement/signing private key；通过 ECDH + HKDF 得到 wrapping key 解包 VRS。AES DEK/VRS 不宣称“存入 Secure Enclave”，对称密钥使用时仍会进入 App 内存，必须配套 session 生命周期与清理。没有 Secure Enclave 时只允许经过批准的 Data Protection Keychain fallback。

## 8. CloudKit 自带加密不等于 App 自控密钥

CloudKit `encryptedValues` 可让字段在客户端加解密，但已有明文字段不能原地改成加密字段，引用和部分路由结构仍需服务端可见；其恢复行为也由 iCloud 安全体系决定。Apple 对 iCloud 不同服务密钥的保护模型有明确区分。

来源：

- [Encrypting User Data](https://developer.apple.com/documentation/cloudkit/encrypting-user-data)
- [`CKRecord.encryptedValues`](https://developer.apple.com/documentation/cloudkit/ckrecord/encryptedvalues)
- [iCloud data security overview](https://support.apple.com/en-ca/guide/security/sec3cac31735/web)

**项目决策**：如果目标是“CloudKit 只见 App 密文、解密权由 App 设备协议控制”，就使用客户端 envelope encryption。文档同时列出 metadata leakage，不能夸大为零知识全部元数据。

## 9. 密钥层级的成熟参考

Bitwarden 官方白皮书描述了随机账户对称密钥、每条 vault item 独立随机 cipher key、客户端加密，以及用上层 key 包装 item key；轮换上层 key 时可重包 item key。白皮书也把密码派生 key、随机账户 key、认证 hash、设备批准和恢复 key 分成不同职责。

来源：

- [Bitwarden Security Whitepaper](https://bitwarden.com/pdf/help-bitwarden-security-white-paper.pdf)，重点见 pp. 6–15、18–19
- [Bitwarden KDF Algorithms](https://bitwarden.com/help/kdf-algorithms/)
- [Bitwarden account encryption key](https://bitwarden.com/help/account-encryption-key/)

**项目决策**：参考“每记录 DEK → vault root key → device/recovery wrapper”的层级，不照抄 Bitwarden 的算法参数、账号模型或服务端架构。应用密码 verifier 与解密材料继续分离；如果以后升级密码角色，只能派生 KEK 去包装随机 root key，不能直接逐条加密。

## 10. AEAD 与最低 envelope 契约

CryptoKit AES-GCM 的 sealed box 包含 nonce、ciphertext 和 tag，并支持 authenticated data；同一 key 下 nonce 复用会破坏安全。

来源：

- [CryptoKit AES.GCM](https://developer.apple.com/documentation/cryptokit/aes/gcm)
- [AES.GCM.Nonce](https://developer.apple.com/documentation/cryptokit/aes/gcm/nonce)

**项目决策**：envelope 至少版本化绑定 `formatVersion`、`cryptoSuite`、`vaultID`、`generation`、`eraseEpoch`、`keyEpoch`、`recordID`、`schemaVersion`、`mutationID`、revision、nonce、ciphertext、tag 和 wrapped DEK。真正的 canonical encoding 与 byte-level AAD 在 G2 冻结并产出跨版本测试向量，不能留给实现者临时拼字符串。

## 11. 分布式清除的可实现边界

CloudKit 可以删除 record zone 及其中记录，但这只改变服务端当前状态，不能远程抹掉永远离线设备上的本地副本，也没有公开服务器钩子替 App 拒绝旧版本客户端重建旧 zone。

来源：

- [Deleting a record zone](https://developer.apple.com/documentation/cloudkit/ckdatabase/delete(withrecordzoneid:completionhandler:))
- [Responding to requests to delete data](https://developer.apple.com/documentation/cloudkit/responding-to-requests-to-delete-data)

**推论**：稳定 control plane + 新 generation/erase epoch 可以保证新客户端逻辑上永不采纳旧世代；旧 data zone 再异步物理删除。若仍允许永久离线旧客户端写入，不能绝对宣称全设备物理清除。要提高保证，必须有最低 writer version、旧通道停止采纳、可信设备 roster/ack 和显式撤销。

## 12. 对当前项目的最终研究结论

`CKSyncEngine` 提供的是可发起、可观察、可重试、可处理冲突的 CloudKit 传输闭环；它不提供跨设备事务或“所有设备已完成”证明。`v1.14` 的成熟度来自应用层密文协议、durable outbox、设备信任/恢复、墓碑与 erase epoch、迁移回滚和真机故障矩阵，而不是单纯替换一个同步 API。
