# Implementation Plan: v1.14 受控密文同步

**Status**: 评审草案；本轮只编写/审查 G0–G3 的文档，G0–G7 均不执行
**Spec**: [spec.md](./spec.md)
**Research**: [research.md](./research.md)
**Threat model**: [threat-model.md](./threat-model.md)
**Data model**: [data-model.md](./data-model.md)
**Decision record**: [decision-log.md](./decision-log.md)
**Release sequence**: [v1.13.9 → v1.13.10 → v1.13.11 → v1.14 → UI](./release-sequence.md)
**Contracts**: [crypto-envelope](./contracts/crypto-envelope.md) · [sync-state-machine](./contracts/sync-state-machine.md) · [device-lifecycle](./contracts/device-lifecycle.md) · [migration-protocol](./contracts/migration-protocol.md)

## 1. 总体判断

建议保留现有 App 的 UI → Business → Data 分层、身份门闩、会话授权、存储写栅栏和本机事务恢复基础；替换的是“保险库核心怎样跨设备同步”这一条底座，而不是推倒整个 App。

目标结构：

```text
UI
  ↓ 只读状态/发业务命令
Business（现有门闩、session lease、StorageMutationGate）
  ↓
Vault Transaction Coordinator
  ├─ 同一 controlled-local transaction store
  │    ├─ SwiftData 读取投影（cloudKitDatabase: .none）
  │    ├─ canonical envelope cache
  │    └─ durable outbox / inbound spool / conflict / quarantine / erase+migration ledger / engine state
  └─ Crypto & Device Trust
       ├─ 每记录 DEK
       ├─ VRS/writeKeyEpoch + acceptedReadKeyEpochs
       └─ Secure Enclave P-256 或 Data Protection Keychain 设备私钥
  ↓
Controlled Sync Engine
  ├─ CKSyncEngine state serialization
  ├─ Control custom zone
  └─ Generation data custom zone(s)
```

旧 SwiftData 自动 CloudKit 与 synchronizable Keychain 在迁移期只作为 legacy source。进入 `controlledPrimary` 后，新协议是唯一跨设备真相源；旧通道不能继续自动回灌。

## 2. 为什么不是继续小修

现有代码已经尽力补上读去重、写打全、导入后清扫、本机 WAL 和全量清除恢复，但仍有平台级边界无法靠重试修掉：

- SwiftData 元数据与钥匙串明文是两条互不原子的同步通道；
- App 无法得知 synchronizable Keychain 在哪台设备完成；
- SwiftData 自动 CloudKit 不提供业务 mutation、按记录提交确认和可编排冲突协议；
- 本机 `CloudEraseConvergence` 明确只是进程内收敛，离线设备未来仍可写回；
- 当前冲突依赖设备墙钟 LWW，关系物理删除没有长期墓碑；
- 现有持久 WAL 只覆盖部分跨存储操作，不能作为分布式 outbox。

因此“再加一次轮询/延迟/清扫”只能缩小窗口，不能形成新的正确性保证。

## 3. 技术选型

| 领域 | 选择 | 理由 |
| --- | --- | --- |
| 云传输 | CloudKit Private DB + `CKSyncEngine` | 保留 Apple 原生、私有账号存储，同时获得显式 pending change、发送/拉取事件、冲突和 state serialization |
| 云分区 | 稳定 control zone + generation data zone | 控制面不随普通清除消失；数据世代可隔离旧写并最终整 zone GC |
| 本机存储 | 同一独立 local transaction store 承载投影 + envelope/outbox/inbound/engine state | 保证业务提交和入站落盘边界；UI 仍用领域投影，核心记录不再被自动 CloudKit 接管 |
| 内容加密 | 每记录 AES-256-GCM DEK | 单条泄露/轮换边界清晰，支持记录独立更新 |
| 密钥层级 | VRS → 包装 DEK；设备 wrapper → 包装 VRS | 加设备只新增 root wrapper，不形成 records × devices 膨胀 |
| 设备密钥 | Secure Enclave P-256 agreement/signing；无 SE 时由 D17 在“拒绝”与 DP Keychain 软件 fallback 中裁决 | 私钥不跨设备；SE 适合 P-256，不把 AES key 误写成“存进 SE”，也不把软件 key 冒充硬件不可导出 |
| 冲突检测 | CloudKit change tag + 业务因果 revision + mutation ID | change tag 发现并发，业务协议决定语义；不依赖墙钟 |
| 恢复 | 可信设备批准 + 高熵 Recovery Key | 不把 Apple 账号或本机应用密码偷换成解密权 |
| 迁移 | 影子复制、逐条核对、分阶段切换、最后删旧明文 | 数据损失风险最低，回滚边界可说明 |

协议必须把四类值分开建模，字段名、状态转移、签名输入和 UI 诊断都不得只写含糊的 `epoch`：

| 值 | 推进原因 | 对其他值的影响 |
| --- | --- | --- |
| `generation` | 切换 active data zone/命名空间，或获批的不兼容迁移 | 不自动轮换 VRS，也不自动证明发生清除 |
| `eraseEpoch` | 表达不可逆内容销毁水位 | 低值永不恢复为 live；不代替 `generation`、`writeKeyEpoch` 或 `acceptedReadKeyEpochs` |
| `writeKeyEpoch` | 为新写激活新的 VRS 世代 | 同一 control head 只有一个可写值 |
| `acceptedReadKeyEpochs` | 常规轮换时临时保留历史读取能力 | 是有限只读集合；成员不获得写权限或 roster 身份 |

同一个 control transition 可以有意同时改变多项，但必须逐字段声明 source/target 和验证条件，不能因为“epoch 增加”推断其他字段也已改变。

## 4. 模块边界

计划中的名称是契约角色，不是本轮要创建的 Swift 文件。

| 模块 | 单一职责 | 禁止 |
| --- | --- | --- |
| `VaultTransactionCoordinator` | 在一个本机事务中提交投影、信封、mutation、outbox | 直接等待 CloudKit 才算本机保存成功 |
| `VaultCryptoService` | 生成 DEK、封装 payload、验证 AAD、包装/解包 VRS | 持久化明文；自行发明无版本格式 |
| `DeviceTrustService` | 首设备建立、加入、审批、撤销、恢复和轮换 | 把“同 iCloud”当作可信设备证明 |
| `ControlledSyncStore` | canonical envelope、outbox/inbox、conflict、quarantine、engine state | 把 CKSyncEngine pending state 当 durable WAL |
| `ControlledSyncEngine` | CKSyncEngine delegate、批次、重试、账号/zone/token 事件 | 修改旧 SwiftData 自动生成的 CKRecord |
| `VaultProjectionRepository` | 由已验证 envelope 更新本机可读投影 | 成为新的云真相源；保存 API key 明文 |
| `MigrationCoordinator` | legacy 扫描、影子写、增量捕获、核对、切换、回滚 | 在核对前删旧 Keychain；让 UI 自己双读 |
| `SyncStatusService` | 汇总可证明的确认层级和阻塞原因 | 用“已同步”笼统覆盖不同状态 |

UI 继续只依赖业务协议，不得同时知道 legacy Keychain、CKRecord、outbox 和新投影的细节。

## 5. 分阶段实施与硬闸门

### G0 — 前序版本关账与只读盘点（`13.11` 尚未关账；本轮不执行 v1.14 Git 动作）

目标：`v1.13.9` 与纯结构稳定化 `v1.13.10` 已关账；接着用独立 `v1.13.11` 只验收购买权益。同步正式实施只能以未来经关账及远端复核的 `v1.13.11` closure SHA 为基线。在新同步方案尚未获批时，只写计划和盘点，不移动 parked `v1.14` 或修改同步产品语义。

- **G0a（历史已完成）**：`v1.13.9` 认证代码已冻结；工作树归属、旧任务状态、不可逆标识、store path、Keychain service/access group 和 Production schema 已盘点。尚欠的真实系统边界全矩阵继续是发布闸门，不追写成已通过。
- **G0b（历史已完成）**：`v1.13.9` 经用户授权按精确范围提交上传，独立远端复核后记录关账 SHA `25fe006896a816475e269e155530c1464cc19304`。原工作树未提交差异仍保留且不带入后续分支；原包检查器退出 4 仍是其自身隔离阻塞。
- **G0c（已完成）**：从 `v1.13.9` closure SHA 建立 `v1.13.10`，只做结构稳定化和真正的 XCUITest；其 closure SHA 为 `8e6c22109b9f5851dacb31b96e8915d855b0e0f3`。真实系统边界仍须发布前验证，不把自动测试扩大为真机全矩阵。
- **G0d（进行中）**：从 `v1.13.10` closure SHA 建立干净独立 `v1.13.11`，只做购买权益验收；其真实 closure SHA 需等实施、测试、独立复核、授权上传和远端核对后记录。
- 当前 parked `v1.14` 无独有提交但停在 13.6，只记录该事实；G0 不前移、不重建、不切换它。
- 旧同步卫生包保留；G0 只如实登记 T006/T008 未完成状态，不在新方案获批前替它们作产品处置。
- 只记录现行权威冲突；未获 G1 批准前，不把建议改写成产品事实。

**Exit**：`v1.13.9`、`v1.13.10`、`v1.13.11` 均完成各自验收、授权提交上传、独立远程复核与关账；工作区差异均有归属；三个 closure SHA、工作树归属、旧任务现状和不可逆配置清单均有书面记录。在 `13.11` 未关账前，G0 对同步仍未完成，不得用其本机起点冒充最终同步基线。

### G1 — 产品与威胁模型裁决

目标：先决定产品承诺，再冻结密码和恢复语义。

必须批准：

1. `v1.14` 是 Stage 1 架构维护，不占用产品 V2；
2. 状态文案只承诺实际确认层级，不承诺固定时间；
3. 应用密码继续本机门闩；
4. 新设备采用可信设备批准 + Recovery Key；
5. 没有可信设备且没有恢复密钥时，数据不可恢复；
6. Recovery Credential 推荐使用离线非对称 agreement/signing keypair，云端只存公钥；若不用，必须先解决 root rotation/紧急撤销时恢复路径会被阻断的问题；
7. v1.14 只在后台传输密文，不新增锁定态后台解密；未来管理凭证自动刷新另作 security domain 裁决；
8. 明文路由字段最小集合；
9. 旧版本兼容、legacy participant grace window 与淘汰窗口；
10. 是否接受“不新增外部 transparency 服务”，即防内容泄露和记录级篡改，但 Recovery-only 全新设备仍依赖 CloudKit 提供当前最新快照；
11. 离线发起全量清除时，是否接受“本机立即不可见并封写，联网完成获批模式的 `eraseEpoch`/control transition 后才重新开放或进入未配置”；
12. 是否接受 Recovery Credential 单独不能抵抗 CloudKit control/data 全失；v1.14 以已验证加密备份作为灾难恢复前提，自动 Recovery Kit 另案；
13. 控制管理员权采用任一 active device 单签（1-of-N）还是多设备 quorum；正常轮换、撤销、Recovery Credential 替换与 compromise replacement 是否采用相同门槛，以及单设备/设备丢失/Recovery-only 的逃生规则；
14. 即使普通验证方式是“不验证”，新设备批准、撤销、Recovery Credential 替换、compromise replacement 与 FR-061 清除/重置是否仍强制 `deviceOwnerAuthentication`；若采纳推荐项，必须先显式修订 FR-061、SC-014 和接口；
15. 是否把 routine rotation 与 compromise replacement 分成两个产品流程：前者只切换 `writeKeyEpoch`/重包，后者为全部仍存活内容生成新 DEK/nonce/ciphertext并排除可疑身份；两者都必须披露旧 VRS 仍可解其此前取得的兼容 ciphertext/wrapper；
16. FR-061 映射为保留 vaultID/Recovery Credential/device identities 的“内容清空”，还是退休旧 vault、以后用全新身份 bootstrap 的“保险库重置”；是否保留最小认证 anti-replay/retirement tombstone，或接受零残留导致未知离线副本无法可靠防复活的风险；
17. 不支持 Secure Enclave 的设备是拒绝受控保险库，还是允许 Data Protection Keychain `ThisDeviceOnly` 软件 P-256 fallback；若允许，是否接受私钥对本 App 进程可导出、必须在 roster/UI/诊断中显示硬件保护降级，且不得同步或备份该私钥。

获批后才执行以下激活动作：

- 按 §10 顺序回写产品权威并做一致性复核，明确处置 legacy hygiene T006/T008；被取代只能记 `superseded` 和理由，未完成项不得假勾；
- 另经用户明确授权后，只允许把当前无独有提交的 parked `v1.14` **fast-forward** 到最终 `v1.13.11` closure SHA；若届时不能纯快进，立即停止并重新裁决，禁止隐含删除、重建、reset 或 force push；
- 记录新分支 base SHA、权威版本和只允许进入的下一 gate。

**Exit**：`spec.md §7` 无未决项并写入 [decision-log.md](./decision-log.md)；威胁模型与承诺/不承诺表经用户批准；权威回写、一致性复核、旧任务处置与 `v1.14` 精确基线均完成。仅批准产品方向不等于授权回写、建分支、改代码或迁移数据；每一步都服从其单独授权边界。

### G2A — 协议原语候选与 disposable 原型

目标：先把密码、控制链、状态与存储原语写成可验证候选，并用 disposable 环境验证平台边界；此时**不宣称四份 contract 已冻结**，因为迁移/cutover 会反向约束它们。

- 起草 crypto suite、payloadAAD/wrapAAD、canonical encoding、format version 和测试向量；
- 起草 control/data zone、record type、hash-linked control history、actor frontier、durable inbox/outbox 与本机事务边界；为 `generation`、`eraseEpoch`、`writeKeyEpoch`、`acceptedReadKeyEpochs` 分别定义状态与拒绝矩阵；
- 按 D13/D14 起草 control event 的单签或 quorum 授权证据及独立高风险 device-owner authentication receipt；不得从普通“取用验证”策略推断；
- 按 D17 用 disposable 真机/支持矩阵验证 Secure Enclave 能力探测、拒绝路径或软件 P-256 fallback 的 `ThisDeviceOnly`/不迁移属性与降级标识；不得用模拟器结果冒充硬件保证；
- 用 disposable container 验证 CloudKit 字段、批次、CAS、state serialization、账号/token/zone 异常；
- 把仍受 migration/cutover 影响的字段显式列为 open issue，不允许提前写“冻结”。

**Exit**：候选协议能支持 G3 设计，平台假设有原型证据，所有未决项都有 owner；尚不授权 Production schema 或实现。

### G3 — 迁移、回滚与跨版本演练设计

目标：确定在哪一刻还能回滚，在哪一刻只能前滚。

```text
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
```

- `shadowCopy` 前：旧系统唯一真相源，可随时撤掉新空区；
- `shadowCopy`/`shadowVerified`：旧读写继续，新系统只影子写和比对；失败可回到 legacy；
- `cutoverPending`：短暂写栅栏，排空 legacy 增量并完成最后核对；失败仍回 legacy；
- control manifest 的 controlled-primary cutover CAS 被接受后：无论某台设备是否已有新 mutation，普通回滚都不得重新启用 legacy 自动写；只能修复后前滚，或执行经过设计的反向导出；
- `legacySecretPlaintextDeleted`：删除旧 synchronizable Keychain secret 的不可逆门槛，单独授权；
- `legacyMetadataRecordsDeletionObserved`：再清理旧 CloudKit 用户记录中的名称、备注、URL 和关系等明文元数据；与 schema/type 仅标 deprecated 分开取证。

**Exit**：每个阶段有进入条件、持久 checkpoint、崩溃恢复、退出条件和用户可见状态；旧版本写回不会成为新真相源。

### G3F — 四份协议统一冻结与独立审查

- 把 G2A 原语与 G3 migration lease、participant set、全局 cutover PONR、Recovery Kit 选择、管理员授权、routine/compromise rotation、D16 获批清除模式、distributed erase、rollback/cleanup 一次性合并；
- 冻结 crypto bytes、control/data schema、可验证 data frontier、状态转移、迁移/回滚和错误语义；
- 运行密码学测试向量与完整故障/崩溃矩阵；
- 由独立安全审查者与独立迁移审查者分别复核，P0/P1 清零；实现作者不得自己宣布通过。

**Exit**：四份 contract 无“实现时再定”，测试向量和状态转移可被自动测试消费；产品负责人再次确认最终计划，并只授权一个后续 gate。

### G4 — 基础实现（本轮禁止）

- 只在 feature flag 后实现 crypto、local stores、outbox 和 fake transport；
- 先完成纯本机/内存协议测试和逐阶段 crash injection；
- 不连接生产 zone，不触碰 legacy 数据。

### G5 — Development CloudKit 与影子迁移（本轮禁止）

- 创建 disposable Development zones；
- 跑两台/三台真机、账号变化、网络与错误矩阵；
- 开启 shadowCopy，旧通道仍权威；
- 任何记录核对失败则停止，不得自动跳过。

### G6 — Production 影子与受控切换（本轮禁止）

- **G6A** additive deploy Production schema；小范围 opt-in/TestFlight 的每个真实 vault 必须在 legacy 仍权威时完成 Production shadowCopy → shadowVerified，不能用 Development 或另一保险库结果替代；
- **G6B** 只对本 vault 有 `productionShadowVerified` checkpoint 的用户执行全局 cutover CAS；
- manifest 接受 `controlledPrimary + cutoverID + fencing revision` 后旧通道停止自动采纳且只能前滚；
- UI 准确显示 `cloudAccepted` 与 device ack；
- 演练 forward-only 恢复。

### G7 — 观察与旧明文退休（本轮禁止）

- 至少跨一个影子版本和一个 controlled-primary 观察版本；具体时间在 G1 冻结；
- 完成旧设备离线、重装、撤销、轮换、全量清除、账号切换和恢复密钥演练；
- 独立安全/迁移审计通过；
- 单独授权后才删除 synchronizable Keychain 明文；
- 再单独清理 legacy CloudKit 中名称、备注、URL、关系等旧明文元数据记录；Production record type/schema 只能 deprecated 不等于保留用户记录；
- 重新核对加密出口合规声明，并更新隐私政策、商店问卷、帮助文案和旧版本支持说明。

## 6. 迁移数据分类

每个 legacy 对象必须落入一个且仅一个结果：

| 分类 | 处理 |
| --- | --- |
| 元数据 + 本机明文齐全 | 生成 envelope，round-trip 解密核对后标 verified |
| 元数据存在、明文暂未到 | `waitingForLegacySecret`；继续等旧钥匙串同步或让用户处理，不伪造空值 |
| 只有明文、无元数据 | quarantine；展示不可识别条目数，不自动创建假名称 |
| 同业务 ID 多副本 | 先按 legacy 规则列出候选；敏感内容冲突不静默 LWW |
| 软删除/回收站 | 迁移完整 payload + 产品删除日期；另生成同步墓碑生命周期 |
| 已永久删除但有旧副本 | 由 erase/tombstone 规则屏蔽，不作为新 live 记录 |
| 未完成 legacy WAL/erase journal | 先完成或人工处置旧恢复，禁止同时迁移 |
| 未知/损坏数据 | quarantine 并保留原始旧存储，不扩大损坏 |

核对在内存中解密比较。不得把 API key 明文的 hash、末位、长度或其他派生物写入 CloudKit、SwiftData 或迁移报告。

## 7. 冲突策略摘要

| 对象 | 因果上较新 | 真并发 |
| --- | --- | --- |
| API key / 管理凭证内容 | 应用较新 mutation | 两份都保留为 siblings，用户选择；不静默覆盖 |
| 名称、备注、头像等元数据 | 三路合并无冲突字段；或应用较新整条 | 同字段冲突保留 sibling；不拼接字符串 |
| 指派关系 | 稳定 edge record 的较新 present/deleted 状态 | remove-wins 并保留冲突审计，避免旧离线 add 复活 |
| 普通删除 vs 编辑 | tombstone 控制主列表不可见 | 更新作为可恢复 sibling 放入回收/冲突界面，不自动复活 |
| 全量清除 vs 任意旧写 | 当前 `eraseEpoch` 胜 | 非 active `generation` 或低 `eraseEpoch` 直接隔离，不能进入投影 |
| 安全偏好 | 继续独立分类；降低安全必须保守 | 不跟保险库密文记录共用一套 LWW |

## 8. 故障与恢复策略

| 故障 | 处理 |
| --- | --- |
| 无网络/限流/临时服务错误 | durable outbox 保留，指数退避并尊重服务端建议；本机状态不回滚 |
| CloudKit 未登录/账号切换 | 锁定并隔离账号绑定，停止上传；不得用空账号覆盖本地数据 |
| `serverRecordChanged` | 进入冲突解析，保留 client/server/ancestor，不 `allKeys` 强盖 |
| change token 过期 | 全量重建 canonical cache，再分别验证 tombstone、generation、eraseEpoch、writeKeyEpoch 与 acceptedReadKeyEpochs；投影最后切换 |
| zone 被删除 | 按 manifest/generation 判断是合法清除还是异常；不得自动把本机旧数据重建成 live zone |
| 包装密钥缺失 | `recoveryRequired`；只能走批准/恢复，不删除密文 |
| AEAD/签名失败 | quarantine；保留最后良好投影并提示数据完整性错误 |
| CKSyncEngine state 丢失 | 从 canonical store/outbox 重建 pending changes，重新 fetch |
| 进程中断 | 依据本机 journal/checkpoint 幂等继续；禁止仅靠内存 flag |
| 记录/批次超限 | 单条在本机先拒绝；批次切小重试，不能假定整个保险库一个原子批次 |

## 9. 验证计划

### 9.1 自动测试

- 密码学：round-trip、随机 nonce、AAD 错绑、record swap、tag 篡改、降级、未知版本、测试向量；
- 设备：加入、重复审批、过期审批、伪造请求、恢复、撤销、轮换中断，以及旧 generation/eraseEpoch/writeKeyEpoch/read-set 的组合；
- mutation：重复、乱序、并发、错误父 revision、时钟偏差、partial save；
- 删除：关系 tombstone、普通删除、回收恢复、GC、`eraseEpoch`、旧 `generation`/`writeKeyEpoch` 设备写回；
- 控制安全：1-of-N 或 quorum 的获批矩阵、“不验证”下的高风险 device-owner 强制路径、正常轮换与 compromise replacement 的差异、旧 VRS 历史解密边界；
- 设备密钥保护：有 SE 时私钥不可导出；无 SE 时按 D17 验证拒绝或 `softwareExportable` fallback、卸载/备份/迁移/恢复行为及用户可见降级；
- 清除模式：按 D16 对 content wipe 或 vault reset 做全状态崩溃测试；验证 generation/erase/write/read 四项不串位，以及最小 retirement tombstone/零残留选择与产品承诺一致；
- crash matrix：创建、编辑、换密、指派、删除、迁移、轮换、撤销、清除的每个持久阶段；
- cutover barrier：participant 在封写前后竞争写、两个 coordinator、required participant 离线、显式排除后重建 revision、abort/release、CAS accepted 但回调丢失；
- 控制操作互斥：erase × cutover/rotation/revoke/cleanup、cutover × rotation/revoke/cleanup，以及每种 CAS loser 重读/rebase；
- journal 绑定：migration/cleanup/erase/rotation 的每一 stage 遇到账号切换、install nonce 不匹配、首次解锁前启动、磁盘写满和进程终止；
- 入站原子性：记录到达但 batch/state 未落盘、batch/state 已落盘但未应用、state serialization 写入失败、解锁后继续；
- 删除真实性：active generation 裸 CloudKit physical delete 必须隔离，只有签名 tombstone 才改变业务可见性；
- cleanup 证明：每个 required participant 的 Keychain/local-fallback/legacy metadata 签名 checkpoint，未知离线安装保持未知；
- 灾难恢复：control/data CloudKit 全失后只从已验证加密备份建立全新 vault，不复用旧 tag、身份、世代或 epoch；
- 30 天回收站：restore、并发 edit、到期 purge、cascade partial retry 与最小认证 tombstone 保留；
- CloudKit 错误：未登录、账号变化、token 失效、zone 删除、配额、限流、批次/记录超限；
- 数据泄漏：日志、投影、outbox、journal、UserDefaults、诊断包扫描；
- 兼容：旧备份 v1、新备份格式、旧 schema、旧客户端写入隔离。

### 9.2 真机矩阵

至少 iPhone + iPad/Mac 两台，关账前增加第三种平台：

1. 自动调度和手动 send/fetch；
2. 同记录并发编辑、换密、编辑 vs 删除、指派 add/remove；
3. 一台离线数日后上线；
4. 推送缺失、杀进程、重启、锁屏和首次解锁前；
5. 新设备批准、Recovery Key、重装、撤销、轮换；
6. iCloud 退出、换账号、临时不可用；
7. 清除后旧 outbox/旧设备重连；
8. shadow migration、cutover 中断、forward-only 恢复、legacy cleanup；
9. Secure Enclave 不可用设备/环境的明确 fallback。

平台组合至少覆盖 iPhone↔iPad、iPhone↔原生 macOS、iPad↔Mac Catalyst 的双向新增/编辑/删除/冲突；若某运行形态不再是产品支持目标，必须先在 G1 明确移除，不能用另一 Mac 形态代替。

### 9.3 发布闸门

- 测试全绿不代替真实 CloudKit 真机证据；
- Development 通过不等于 Production schema 已部署；
- 单设备通过不等于多设备收敛；
- `cloudAccepted` 不等于 peer ack；
- 旧明文未删不等于迁移失败，而是观察期的安全设计；
- 未完成恢复演练不得进入 legacy plaintext deletion。

## 10. 权威文件回写顺序（获批后才执行）

1. `ROADMAP.md`：把 `v1.14` 明确为 Stage 1 同步架构维护；产品 V2 仍为 2.0 用量看板；
2. constitution：若把“客户端密文同步”提升为安全原则，升级版本并写 Sync Impact；应用密码角色不变；
3. `001-key-vault/spec.md`：替换 FR-033/DC-001 的唯一强制方案；按 D14/D16 显式修订 FR-061、SC-014 及“不验证”对高风险操作的边界，并说明最小 anti-replay/retirement tombstone，禁止用本包下位合同静默覆盖；
4. `research.md`：把过去“V2 信封加密”改称 `v1.14`，避免和产品 V2 混淆；
5. 现行 `plan.md` / `data-model.md` / [`contracts/module-interfaces.md`](../../contracts/module-interfaces.md)：写入获批的新旧并存和最终目标；本包 `release-sequence.md` 保留版本隔离证据；
6. `tasks.md` / playbooks：只生成当前获批 gate 的实施任务，不把 G4–G7 一次性全授权；
7. `ZL01/14` 与分支台账只更新当前状态和路牌，不复制第二份正文。

## 11. 本轮停止条件

本轮完成计划文档、研究依据、契约草案、任务分段和审查清单后立即停止。以下均不做：

- 不改 Swift / Xcode 工程；
- 不创建、移动或切换 `v1.14`；
- 不创建 CloudKit zone 或 deploy schema；
- 不迁移、读取或删除真实用户明文；
- 不改商店隐私声明为已经启用新架构；
- 不创建/切换/上传 v1.14 实施分支，不打 tag；本计划文档可以随获授权的 v1.13.9 关账提交上传，但该动作不等于批准任一 G1 决策或后续实现。
