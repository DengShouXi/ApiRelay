# Threat Model Draft: v1.14 受控密文同步

**Status**: G1 待批准
**Scope**: 只定义受控同步与设备密钥的安全承诺，不替代现有身份门闩、剪贴板和备份威胁模型。

## 1. 保护资产

- API key 与管理凭证明文；
- VRS、每记录 DEK、Recovery Key、设备私钥；
- 账号/工具/名称/备注/指派等保险库内容；
- 删除、撤销、设备 roster、`generation`、`eraseEpoch`、`writeKeyEpoch` 与 `acceptedReadKeyEpochs` 的完整性；
- 同步状态与迁移结果的真实性。

## 2. 对手与预期保证

| 场景 | v1.14 目标保证 |
| --- | --- |
| CloudKit 数据库/备份泄露，攻击者没有设备私钥或 Recovery Key | 无法解密保险库 payload/VRS |
| 云端插入、替换或跨记录搬运单条数据 | signer、AAD、`generation`/`eraseEpoch`/`writeKeyEpoch`、AEAD 校验失败并 quarantine |
| 恶意云端拿 recovery public key 自造 VRS、wrapper、genesis/roster | 恢复端从离线私钥导出预期双公钥并验证固定 RecoveryAuthority activation 签名；假 vault 无法通过 |
| 被撤销设备上传旧 mutation | 因 roster、`generation`、`eraseEpoch`、`writeKeyEpoch` 与 actor frontier 检查拒绝，不进入当前投影 |
| 被撤销设备事后用旧 key/VRS 倒填成“撤销前 revision” | actor sequence/previous-hash 与撤销 event 冻结的 accepted data frontier 不匹配，隔离 |
| 推送丢失、乱序、重复、token 过期 | 通过 change fetch、mutation ID、重建和 tombstone 保持正确 |
| 丢失且锁定的设备 | 依赖 Secure Enclave/Data Protection Keychain、系统设备安全和 App sandbox |
| 普通第三方 App | 依赖系统 sandbox/Keychain；不应取得设备私钥或本 App 数据 |
| 旧版 ApiRelay 客户端 | 新协议不自动采纳 legacy 写入；minimum writer version 与 generation/eraseEpoch/writeKeyEpoch 分别隔离 |

## 3. 明确不保证

- 已解锁设备上若攻击者能以被篡改的 ApiRelay 二进制/进程执行代码，应用层门闩可能被绕过；v1.14 不宣称系统级每次解密强制。
- 已被可信设备读取、复制或导出的明文，撤销设备无法追溯抹除。
- 持有旧 VRS 的攻击者，仍能解开其在撤销/轮换前已经取得、且由该旧 VRS 世代可解的任意 ciphertext、DEK wrapper 或设备 wrapper；删除云端旧 wrapper、切换 `writeKeyEpoch` 或完成常规重包都不能让这些历史副本重新变成不可解。常规轮换只能保护后续写入，只有“疑似泄露替换”流程对仍存活内容生成全新 DEK/nonce/ciphertext 并排除旧信任因子，才能保护替换完成后的版本；攻击者先前已取得的明文仍不可追回。
- CloudKit 不可用、限流或账号冻结时，不保证可用性和固定恢复时间。
- record/zone ID、大小、数量、时间、协议世代等最少元数据可能可见。
- 永久离线设备本地副本不能被远程物理擦除。
- 用户主动选择“不验证”会降低本机界面访问保护；它是否仍必须对设备加入、撤销、恢复凭据替换、全量清除/保险库重置等高风险控制操作强制 `deviceOwnerAuthentication`，属于 G1 尚未批准的独立产品裁决，不能由实现默认继承普通取用策略。
- 无 Secure Enclave 时，Data Protection Keychain 中的软件 P-256 私钥不具备硬件不可导出保证，可能被以本 App 身份执行的恶意代码导出。是否拒绝这类设备或允许带显式降级的 fallback 是 D17 待裁决项，当前草案不承诺已选择任一方案。

## 3.1 四类世代/时期不得混用

| 名称 | 唯一作用 | 不代表什么 |
| --- | --- | --- |
| `generation` | 数据 zone/命名空间世代；隔离一次已激活的内容世代或不兼容迁移 | 不是密钥版本，也不自动表示发生清除 |
| `eraseEpoch` | 对旧内容和旧 mutation 的单调销毁水位；低于当前值的数据永不恢复为 live | 不是 data-zone ID，也不能代替 key rotation |
| `writeKeyEpoch` | 当前新 payload/DEK wrapper 唯一允许使用的 VRS 世代 | 不说明旧记录是否仍可读 |
| `acceptedReadKeyEpochs` | 轮换过渡期仍获准解读历史 envelope 的有限集合 | 不是可写集合；集合中有旧值也不授权旧设备写入 |

控制事件、审批 transcript、mutation、checkpoint 与清除 journal 必须分别绑定这四项；不得用笼统的 `keyEpoch`/`epoch` 推断其他三项。正常 root rotation 通常只推进 `writeKeyEpoch` 并暂时扩展 `acceptedReadKeyEpochs`；内容清除会推进 `eraseEpoch`，并通常切换 `generation`；是否同时重置信任根取决于 G1 的清除语义裁决。

## 4. 完整快照回滚问题

设备签名、AEAD 和分别绑定的 `generation`/`eraseEpoch`/`writeKeyEpoch`/`acceptedReadKeyEpochs` 只能发现单条伪造或替换；要让“当前设备已知历史的回退”真正可发现，控制面还必须形成 signed/MACed parent-hash chain，每台设备在 ThisDeviceOnly 状态固定已接受的最高 control revision/head hash。看到更低 revision、同 revision 异 hash 或无法接续的 fork 时失败关闭，不以 CloudKit change tag 代替密码学历史。

可信设备批准必须把批准方最新 control head、roster revision、`generation`、`eraseEpoch`、`writeKeyEpoch`、`acceptedReadKeyEpochs` 和 data checkpoint 带入 out-of-band transcript；新设备以此建立初始本机高水位。这样已有设备和经可信设备加入的新设备可以发现已知历史回退。但一台全新设备若只持有 Recovery Credential，又没有任何本地或外部最新 checkpoint，面对云端返回的“一整套较旧但当时完全有效的 manifest + wrappers + records”，仍无法仅凭该旧快照证明它不是最新版本。

要抵抗这种恶意服务端全历史回滚，至少需要一项外部最新性锚点：

- 用户持有并随每次控制面变更更新的签名 checkpoint；
- 独立 transparency/notary 服务；
- 另一台仍持有更新 checkpoint 的可信设备。

这些都会引入新的服务或显著恢复复杂度。

**v1.14 推荐威胁模型**：防云端内容泄露与记录级篡改，依赖 CloudKit 提供最新状态/可用性，不额外建设 transparency 服务。恢复时若有可信设备，以设备 checkpoint 交叉确认；只有 Recovery Key 时如实标注“已恢复 CloudKit 当前返回版本”，并在其他设备上线后逐项检查 control head、`generation`、`eraseEpoch`、`writeKeyEpoch` 与 `acceptedReadKeyEpochs` 是否存在差异。

如果产品负责人要求抵抗 CloudKit 主动提供完整旧快照，G1 必须改为“新增外部最新性锚点”，并重新评估 Stage 1 无自建服务边界。

## 5. 设备私钥访问与现行四档认证

为了保留应用密码和“不验证”两档，v1.14 推荐的 Secure Enclave 设备私钥不在每次解包时强制 userPresence；它提供不可导出和设备绑定，用户可见操作仍由现有 session gate 管理。

因此保护目标分两层：

1. 云端/跨设备层：没有可信设备私钥或 Recovery Key 就不能解密；
2. 已解锁本机层：继续依赖系统 sandbox、Keychain 可访问性、代码完整性和现有应用门闩。

若要让每次 VRS 解包都绑定 Face ID/Touch ID/设备密码，就必须为应用密码和“不验证”设计另外的加密 wrapper，并重新决定后台访问。这不是本阶段的隐含功能。

## 6. 信任根

- 首台设备建立初始 roster 和 RecoveryKeyShare；
- 后续设备必须由 active device 批准或 Recovery Credential 恢复；
- Recovery-only 加入以 recovery signing key 的专用 admission proof 授权一个绑定 request；知道 VRS 不自动获得任意控制权；
- 每个 mutation/approval/checkpoint 绑定 `rosterVersion/controlRevision/controlHeadHash`、actor sequence 与 previous-mutation hash；验证者沿不可删的 control history 确认 signer 在该版本的 active interval，并要求该 mutation 落入撤销或明确的 `eraseEpoch`/`writeKeyEpoch` transition 冻结的 accepted data frontier，防止撤销设备事后伪造“旧 revision”；
- ControlEvent N 的授权只用已认证父状态 N−1 判断，不能让 event N 自报的新 roster 给自己授权；
- 新业务写还必须基于当前 control head、当前 active roster 和当前 `writeKeyEpoch`；`acceptedReadKeyEpochs` 只授权读，历史合法与当前可写是两次独立判断；
- VRS 对其对应的 `writeKeyEpoch`/`acceptedReadKeyEpochs` 控制面提供额外认证；
- CloudKit change tag 只做并发 CAS，不是密码学信任根；
- iCloud 登录证明存储账号可访问，不等于保险库解密授权。

## 7. 日志与诊断

允许记录：

- opaque vault/record/mutation/device ID；
- 协议/阶段/错误类别；
- 不含内容的计数与耗时。

禁止记录：

- API key/admin secret；
- VRS/DEK/Recovery Key/设备私钥；
- 应用密码 verifier；
- 完整 ciphertext/wrapped key/signature payload；
- secret hash、长度、末位、字符集或可用于离线猜测的信息；
- 用户名称、备注、设备明文名称（除非用户主动导出且再次确认）。

## 8. G1 必须批准的威胁模型问题

- [ ] 是否接受“防泄露/记录级篡改，但不增加独立 transparency 服务”的范围？
- [ ] 是否接受已解锁同身份恶意代码不在 v1.14 可防范围？
- [ ] 是否接受撤销设备不能追回既有明文？
- [ ] 是否接受最少元数据泄漏？
- [ ] 是否接受永久离线设备无法远程物理擦除？
- [ ] 是否接受 Recovery Key 与可信设备都丢失时不可恢复？
- [ ] 是否批准非对称 Recovery Credential，使 root rotation 不需要 App 保存或重新索取恢复私钥？
- [ ] 是否接受离线清除先本机不可见并封写、联网完成获批模式的 `eraseEpoch` 与 control transition 后才重新开放或进入未配置？
- [ ] 单用户保险库的控制管理员权采用“任一 active device 单签（1-of-N）”还是多设备 quorum？正常轮换与疑似泄露的紧急替换是否采用不同门槛？
- [ ] 即使普通验证方式是“不验证”，新设备批准、设备撤销、Recovery Credential 替换、疑似泄露替换与 FR-061 清除是否仍强制设备主人认证？该选择若改变现行 FR-061，必须先做权威回写。
- [ ] 是否批准把常规轮换与疑似 VRS/设备密钥泄露的紧急替换拆成两个产品流程，并在 UI 明示旧 VRS 对历史已取得密文仍然有效？
- [ ] 现行 FR-061 最终映射为“仅清空内容但保留 vaultID/Recovery Credential/device trust”，还是“退休旧 vault 并重建 vaultID/Recovery Credential/device identity”？是否按推荐保留最小认证 anti-replay/retirement tombstone，还是接受彻底零残留但旧离线副本可能重新出现的风险？
- [ ] 无 Secure Enclave 设备是拒绝受控保险库，还是允许 `ThisDeviceOnly` 软件 P-256 fallback并向用户明确“可被本 App 进程导出”的保护降级？
