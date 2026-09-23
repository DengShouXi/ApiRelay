# Security Review Checklist

**Status**: plan-only；须由独立审查者在 G3F 复核，作者不得自勾通过。

## 威胁模型

- [ ] CloudKit 数据泄露/恶意替换。
- [ ] 全新恢复设备面对完整旧快照的 rollback 边界已明确；是否需要外部 transparency anchor 已裁决。
- [ ] iCloud 账号被接管但没有可信设备/Recovery Key。
- [ ] 设备丢失、重装、Secure Enclave key 丢失。
- [ ] active trusted device 被攻破。
- [ ] revoked/legacy device 重放旧 mutation。
- [ ] 旧 VRS 持有者解密撤销前已取得 ciphertext/wrapper 的边界已作为“不保证”明确披露；没有把重包/删 wrapper 描述为追回历史保密性。
- [ ] 已解锁设备上以本 App 身份运行的恶意代码。
- [ ] 日志、崩溃报告、诊断、剪贴板和内存残留。

## 密码学

- [ ] CSPRNG 生成 VRS/DEK/nonce；同 key nonce 不复用。
- [ ] AES-GCM、P-256、HKDF 的参数和 domain separation 已冻结。
- [ ] canonical encoding 和 byte-level 测试向量已冻结。
- [ ] payloadAAD 与每-wrapper immutable wrapAAD 分离；集合 mutation/revision 只进外层签名，重包不破坏 payload 或未变 wrapper tag。
- [ ] device approval、mutation、checkpoint 都绑定 control head、actor sequence/hash；历史 signer 必须落入撤销事件冻结的 accepted data frontier。
- [ ] ControlEvent N 只由已认证父状态 N−1 授权，不能用 after-state 自授权。
- [ ] 任何未知版本、降级、tag/signature 失败均 fail-closed。
- [ ] Recovery Credential 不复用应用密码 verifier/备份口令；agreement/signing 分钥，RecoveryAuthority 固定绑定 credential activation heads。
- [ ] Recovery-only admission proof 只授权绑定的一次设备加入；“知道 VRS”不是一般控制权。
- [ ] 本机 pinned control high-water mark 能拒绝已知历史回退；无锚点 Recovery-only 的例外已披露。
- [ ] Secure Enclave 没有被错误描述为存放 AES key。
- [ ] 无 Secure Enclave 时不会静默降级：要么拒绝受控保险库，要么仅按 D17 使用 Data Protection Keychain `ThisDeviceOnly` 软件 P-256，并明确其可被本 App 进程导出、不得同步/备份、roster/UI 标为 `softwareExportable`。
- [ ] `generation`、`eraseEpoch`、`writeKeyEpoch`、`acceptedReadKeyEpochs` 四类值在 canonical encoding、签名、journal、checkpoint 与拒绝矩阵中严格分开。

## 密钥生命周期

- [ ] 首设备 bootstrap 原子/可恢复。
- [ ] 新设备 request/approval 有 challenge、过期、重放防护。
- [ ] 唯一设备撤销有防自锁条件。
- [ ] root rotation 可中断恢复，先验证新 wrapper 再激活。
- [ ] routine rotation 只承诺后续写入/重包语义；compromise replacement 对全部 live payload 使用全新 DEK/nonce/ciphertext并排除被怀疑 device/recovery identities，且承认既有明文/历史副本不可追回。
- [ ] manifest 区分唯一 `writeKeyEpoch` 与 `acceptedReadKeyEpochs`；记录支持轮换期多 DEK wrappers 和独立 wrap revision。
- [ ] revoked device 的旧 signer/旧 `writeKeyEpoch` 写入拒绝；旧值出现在 `acceptedReadKeyEpochs` 也不恢复写权限。
- [ ] historical control/public key/actor frontier 只在无任何存活引用且保留期结束后 GC。
- [ ] 锁定态 durable inbound 与 CKSyncEngine state 同边界落盘；needsUnlock 不冒充 quarantine/ack。
- [ ] 发起端与接收端 distributed erase journal 均绑定 account/vault/eraseID，账号切换不会误重放。
- [ ] VRS/DEK 内存缓存有清理点且不夸大绝对擦除。
- [ ] 日志/诊断不含密钥、完整密文或离线猜测材料。
- [ ] 控制管理员权（1-of-N 或 quorum）及所有单设备/失联/Recovery-only 逃生规则已由产品裁决，不存在实现自动降级。
- [ ] 普通验证方式为“不验证”时，高风险设备信任与销毁操作是否仍强制 device-owner 已显式裁决；若强制，FR-061/SC-014/接口已同步回写。
- [ ] content wipe 与 vault reset 是两个不同威胁模型；vaultID、Recovery Credential、device identity 与最小 anti-replay/retirement tombstone 的生命周期和零残留取舍已冻结。

## 独立审查

- [ ] 密码协议由非实现作者审查。
- [ ] 测试向量由独立实现/工具交叉验证。
- [ ] 迁移与 cleanup 另做数据安全审查。
- [ ] 所有 P0/P1 发现项在实现前清零或显式接受。
