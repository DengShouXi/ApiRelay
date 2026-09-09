# 数据模型定义

**Feature**: 密钥保管、分发与用量统计（阶段一）
**Branch**: `v1`（文档目录 `specs/001-key-vault/`）
**Date**: 2026-08-04
**依据**: [spec.md](./spec.md) · [research.md](./research.md) · Constitution v2.2.0

---

## 1. 存储划分总览

| 数据 | 存储位置 | 同步 | 依据 |
|------|----------|------|------|
| API 密钥明文 | Keychain（`WhenUnlocked` + synchronizable） | ✅ iCloud 钥匙串 | FR-033、research §1 |
| 管理类高权限凭证明文 | Keychain（`AfterFirstUnlock` + synchronizable） | ✅ iCloud 钥匙串 | FR-012、research §1 |
| 上游平台账号 | SwiftData `UpstreamAccount` | ✅ CloudKit | — |
| 密钥元信息 | SwiftData `APIKeyRecord` | ✅ CloudKit | FR-001 |
| 使用方工具 | SwiftData `ConsumerTool` | ✅ CloudKit | FR-007 |
| **密钥↔使用方指派** | SwiftData `KeyAssignment`（**多对多中间表**） | ✅ CloudKit | FR-007 |
| 用量快照 | SwiftData `UsageSnapshot` | ✅ CloudKit | FR-014 |
| 余额快照 | SwiftData `BalanceSnapshot` | ✅ CloudKit | FR-016 |
| 单价规则 | SwiftData `PricingRule` | ✅ CloudKit | FR-015 |
| 用户偏好（**安全相关**） | SwiftData `UserPreferences` | ✅ CloudKit | FR-021、FR-060 |
| 设备偏好（**界面相关**） | SwiftData `DevicePreferences`（**local 配置**） | ❌ | FR-060、DC-021 |
| 权益状态 | SwiftData `EntitlementSnapshot`（**local 配置**） | ❌ | research §6 |
| 刷新健康度 | **UserDefaults** `RefreshHealth`（Codable） | ❌ | FR-017 |
| 平台能力矩阵 | **代码内静态表**，不持久化 | — | 见 §6 |

### 双 ModelConfiguration

`EntitlementSnapshot` 与 `DevicePreferences` 归 local 配置，其余实体归 synced 配置，
并存于同一 `ModelContainer`：

```swift
// 概念配置（非实现代码）
let synced = ModelConfiguration("synced", schema: syncedSchema,
                                cloudKitDatabase: .private("iCloud.com.apirelay.ApiRelay"))
let local  = ModelConfiguration("local",  schema: localSchema,
                                cloudKitDatabase: .none)   // EntitlementSnapshot、DevicePreferences
ModelContainer(for: fullSchema, configurations: synced, local)
```

> **iCloud 容器 ID（不可逆，已定稿）**：`iCloud.com.apirelay.ApiRelay`
> （= `iCloud.$(CFBundleIdentifier)`，Bundle ID 定稿为 `com.apirelay.ApiRelay`）。
> 权威登记见 [plan.md](./plan.md) A5。MUST NOT 使用 `iCloud.com.apirelay.app` 或其他别名。

**权益不同步的理由**：StoreKit 2 的 `Transaction.currentEntitlements` 是 Apple ID 级、跨设备自动
一致的真相源。再经 CloudKit 同步一份快照会造成双真相源，且调试用的 `debugOverride` 状态会污染
其他设备。

**设备偏好不同步的理由**：外观与默认视角是**每台设备各自的选择**——「在 Mac 上改深色导致 iPhone
也变深色」是用户并不想要的联动。而验证方式、剪贴板时长这类安全设置正相反，必须各设备一致
（FR-060、DC-021）。

> ⚠️ **配置名 `"synced"` / `"local"` 与 store 文件路径属不可逆决策**：更改等于新建空库，
> 旧数据不迁移。见 §7.1 与宪法「不可逆决策」节。

---

## 2. Keychain 存储结构

### 2.1 三类 Item

| 属性 | 普通 API 密钥 | 管理类高权限凭证 | 应用主密码校验材料 |
|------|---------------|------------------|---------------------|
| Class | `kSecClassGenericPassword` | `kSecClassGenericPassword` | `kSecClassGenericPassword` |
| Service | `com.apirelay.keychain.keys` | `com.apirelay.keychain.admin` | `com.apirelay.keychain.masterpw` |
| Account | `{APIKeyRecord.id}` | `{UpstreamAccount.id}` | 固定 singleton account（如 `master`） |
| Accessible | `kSecAttrAccessibleWhenUnlocked` | `kSecAttrAccessibleAfterFirstUnlock` | `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` |
| Synchronizable | `true` | `true` | **`false`（MUST NOT 同步）** |
| AccessControl | **不设置** | **不设置** | **不设置** |
| Access Group | `$(AppIdentifierPrefix)group.com.apirelay.shared` | 同左 | 同左 |
| 门闩 | 应用层，方式用户可选（含关闭） | 应用层，**不可关闭**；自动刷新读取时不触发 | 由 `MasterPasswordService` 校验；材料本身不同步（FR-038） |

**为何不设置 `kSecAttrAccessControl`**：它与 `kSecAttrSynchronizable` 互斥（`errSecParam`）。
详见 research.md §1。这是本设计最关键的约束，实现时 MUST NOT 尝试同时设置二者。

**为何管理类凭证用 `AfterFirstUnlock`**：需被按间隔自动刷新的后台任务在设备锁定状态下读取。

**为何主密码校验材料不同步**：一台设备上「忘记主密码→重置」不得静默改写其他设备的预期（FR-038）。
Payload 为 salt + 迭代次数 + 派生结果，**不是**主密码明文，也 **MUST NOT** 用于加密任何数据。

### 2.2 Payload

普通密钥与管理凭证：原始凭证字符串以 UTF-8 `Data` 直存，不做 JSON 包装（减少解析攻击面）。
读取后转 `String` 仅存在于局部作用域，用完即清（宪法 VII）。

主密码：存派生校验材料（见 research §1.2），MUST NOT 存可逆明文。

### 2.3 操作与 SwiftData 的一致性

| 操作 | Keychain | SwiftData |
|------|----------|-----------|
| 新增密钥 | `SecItemAdd`（keys） | Insert `APIKeyRecord` |
| 替换明文 | `SecItemUpdate` | 更新 `updatedAt` |
| 移入回收站 | （**不删** Keychain） | `lifecycle = .softDeleted`，写 `deletedAt` / `purgeAfter` |
| 永久清除密钥 | `SecItemDelete`（keys） | 删除 `APIKeyRecord` + `KeyAssignment` |
| 取出明文 | `SecItemCopyMatching` + 应用层门闩 | 不涉及 |
| 配置管理凭证 | `SecItemAdd`/`Update`（admin） | 更新 `UpstreamAccount.hasManagementCredential` |
| 设置/重置主密码 | `SecItemAdd`/`Update`/`Delete`（masterpw） | 不涉及（仅本机） |
| 清除全部数据 | 删除 keys / admin / masterpw 三类 | 清空用户实体（FR-061） |

`hasManagementCredential` 是**布尔冗余标记**，用于在不读取 Keychain 的前提下渲染界面状态。
它 MUST NOT 被当作权威来源——权威判断是 Keychain 中是否存在对应 Item。

---

## 3. SwiftData 模型

> **CloudKit 约束**：所有同步属性 MUST 为 optional 或带默认值；CloudKit **不支持唯一性约束**，
> 故所有唯一性与配额校验在 Business 层完成（宪法 II）。

### 3.1 UpstreamAccount（上游平台账号）

**术语**：这是**上游 API 提供方**的账号，不是消费端工具。见 spec.md 术语表。

| 字段 | 类型 | 同步 | 约束 |
|------|------|------|------|
| id | UUID | ✅ | 主键。CloudKit 无唯一约束，见下方「重复行」 |
| platform | String | ✅ | 平台标识，见下方预置清单；用户自定义平台为 `custom` |
| customPlatformName | String? | ✅ | `platform == custom` 时的用户自定义平台名称（FR-007a） |
| displayName | String | ✅ | 1…64 字符，非空。**允许同平台多账号** |
| customBaseURL | String? | ✅ | 自定义平台必填；预置平台可选覆写 |
| hasManagementCredential | Bool | ✅ | 冗余标记，默认 false。V2 才使用 |
| notes | String? | ✅ | 可选备注 |
| avatarSymbol | String? | ✅ | 用户覆盖的 SF Symbol；nil = 跟产品写死的默认 / 平台预置（不跟设置里的默认头像） |
| avatarColor | String? | ✅ | 底色标记；与 `avatarSymbol` 同进同出 |
| createdAt / updatedAt | Date | ✅ | `updatedAt` 为 LWW 冲突依据 |
| sortOrder | Int | ✅ | 列表排序，默认 0；自定义分区顺序（FR-064） |

**预置上游平台清单**（内置常量，随应用更新扩充，不持久化为用户数据）：

`openai` · `anthropic` · `google` · `openrouter` · `deepseek` · `zhipu` · `alibaba-bailian` ·
`volcengine` · `siliconflow` · `custom`

用户 MUST 能通过 `custom` + `customPlatformName` + `customBaseURL` 自行添加任何未预置的平台
（FR-007a）。自定义平台的能力矩阵默认为**全部不支持**（无 App 内签发、无用量、无余额），
在 V2 的界面上如实呈现为「该平台能力未知」而非「功能故障」。

**重复行（CloudKit）**：`id` 在业务上应唯一。CloudKit 无唯一约束，同步竞态会留下业务 `id` 相同、记录名不同的多行。仓库读取时按 `id` 去重：冲突留 `updatedAt` 较新者；时间戳相同则带 `deletedAt` 的墓碑优先；仍打平则按业务字段指纹。用户改 / 软删 / 恢复 / 永久删除 MUST 打到同 `id` 全部本地行。完全相同的克隆 MUST NOT 在卫生清扫中删除（两台设备若各删「另一行」，同步后会一条不剩）。MUST NOT 给同步模型加 `@Attribute(.unique)`。

**冲突字段取舍（整行 LWW，禁止拼接）**：

| 实体 | 冲突时保留 | 禁止 |
|------|------------|------|
| `UpstreamAccount` / `ConsumerTool` / `APIKeyRecord` | 较新 `updatedAt` 的**整行**（名称、备注、头像、平台、lifecycle、删除态一并采用）。时间戳相同则墓碑整行胜。较旧行上独有的字段随整行丢掉。 | 把两边非空备注/名称拼成新字符串；做字段级三路合并 |
| `KeyAssignment` | 按 `(keyId, consumerToolId)` **去重并集**（同一组合只计一次；不同组合都保留） | 用账号那套整行 LWW 丢掉另一条合法指派 |
| `UserPreferences` | 读取按指纹确定性折叠；写入打全部副本。**13.5 不物理删除冲突行**（无 `updatedAt`，指纹赢家不是最后修改者优先）。有可靠版本时间或 `replicaSeed` 后再清。 | 拼接时长 JSON；按指纹自动删行 |
| `EntitlementSnapshot` | 本机库；较新 `updatedAt` 整行胜，打平不删 | 把两档权益拼成第三档 |

未 Deploy additive `replicaSeed` 之前，业务字段完全相同的克隆继续不删。

**状态**：无生命周期状态。删除账号 MUST 级联处理其下密钥（见 §9）。

### 3.2 APIKeyRecord（密钥元信息）

| 字段 | 类型 | 同步 | 约束 |
|------|------|------|------|
| id | UUID | ✅ | 主键；同时是 Keychain Account。CloudKit 无唯一约束，见账号「重复行」同一套规则 |
| accountId | UUID | ✅ | → `UpstreamAccount.id` |
| displayName | String | ✅ | 1…64 字符，去首尾空白后非空 |
| maskedHint | String? | ✅ | CloudKit 遗留字段（不可删）。**MUST 保持 nil**；禁止存末位等密钥片段。列表不读此字段 |
| origin | String | ✅ | `manualEntry`（V1）/ `providerIssued`、`receivedFromTransfer`（V2）/ `relayIssued`（V3）。V1 只可写 `manualEntry` |
| providerKeyRef | String? | ✅ | 平台侧标识（OpenRouter `hash`、OpenAI/Claude `api_key_id`），用于关联用量 |
| lifecycle | String | ✅ | `active` / `revokedUpstream` / `softDeleted` |
| spendLimit | Decimal? | ✅ | 平台支持时的消费上限（FR-009） |
| notes | String? | ✅ | 备注 |
| avatarSymbol | String? | ✅ | 用户覆盖的 SF Symbol；nil = 跟产品写死的密钥默认（设置不再改默认） |
| avatarColor | String? | ✅ | 底色标记；与 `avatarSymbol` 同进同出 |
| createdAt / updatedAt | Date | ✅ | — |
| deletedAt | Date? | ✅ | 移入回收站的时间（FR-006 / DC-029） |
| purgeAfter | Date? | ✅ | 永久清除截止时间；移入回收站时写 `deletedAt + 30 天`。到期由启动巡检物理清除 |
| lastVerifiedAt | Date? | ✅ | 最近一次**经管理凭证对账**确认平台侧仍存在的时间（FR-020，V2） |
| **healthState** | String | ✅ | `unknown`（默认） / `valid` / `invalid` / `indeterminate`。见下方专节（FR-052、FR-055） |
| **lastCheckedAt** | Date? | ✅ | 最近一次**主动检测**的时间。nil = 从未检测 |
| **lastCheckNote** | String? | ✅ | 不可判定时的原因文案键（如 `rateLimited`、`networkUnavailable`、`probeUnsupported`），供 UI 呈现可读原因 |
| **secretLength** | Int? | ✅ | CloudKit 遗留字段（不可删）。**MUST 保持 nil**；禁止存明文字符长度 |

**验证规则**

- 免费权益下 `lifecycle != .softDeleted` 的记录数 ≤ 3（FR-026）；权益失效后超额部分只读保留
  （FR-029），计数用于**阻止新增**而非删除既有数据。计数 MUST 按业务 `id` 去重，MUST NOT 把 CloudKit 重复行算成两把密钥。
- `providerKeyRef` 在同一 `accountId` 内应唯一；因 CloudKit 无唯一约束，冲突时以 `updatedAt` 较新者
  为准并记录一次冲突提示。
- 明文 MUST 在写入前去除首尾空白，MUST 拒绝含空格、制表符或换行的内容（FR-056）。
  `secretLength` 不再写入。
- 新增或换密时若同一 `accountId` 下本机 Keychain 已有完全相同的明文，MUST 提示可能重复
  （FR-057）。本机暂无明文的记录不参与比对。**MUST NOT 存储明文哈希、末位片段或任何其他派生物**（宪法 VII）。

#### ⚠️ 健康度为何独立于 `lifecycle`（FR-055，V1 必须预留）

| | `lifecycle` | `healthState` |
|---|---|---|
| 语义 | 这把密钥在产品内的**生命周期** | 最近一次**主动检测**的结果 |
| 数据来源 | 用户操作（删除），或经**管理凭证对账**发现平台侧已不存在（V2、FR-020） | 用**密钥自己**向上游发一次最小请求（V2、FR-051） |
| 置信度 | 高。`revokedUpstream` 是已确认的事实 | 中。401 只说明「当前不被接受」，可能是禁用、可能是删除、也可能是平台侧临时故障 |
| 谁写它 | `KeyVaultServing`、`ProviderKeyServing` | `KeyHealthServing` |

把二者压进一个字段，会让「已失效」同时代表两种置信度完全不同的判断，界面无法如实呈现
（宪法 IX）。因此 **MUST 分开**。

**四态的呈现规则**（FR-052，最容易做错的地方）：

| `healthState` | 何时写入 | 列表呈现 |
|---|---|---|
| `unknown` | 默认值；平台未接入检测时保持 | **无任何标记**。MUST NOT 显示感叹号——未检测不等于失效 |
| `valid` | 探测返回 2xx | 「密钥有效（上次检测 {时间}）」。MUST NOT 表述为「可用」 |
| `invalid` | 探测返回 401 / 403 / 密钥不存在 | 醒目标记（感叹号），MUST NOT 仅依赖颜色区分 |
| `indeterminate` | 429、超时、5xx、无网络 | 「未能确认」+ `lastCheckNote`。**MUST 保留上一次的结论与 `lastCheckedAt`** |

**为何健康度要经 CloudKit 同步**（与 `RefreshHealth` 不同步形成对照）：密钥失效是**平台侧的客观
事实**，一台设备检测出来其他设备也应看到感叹号；而 `RefreshHealth` 是本机的网络状况，同步它本身
自相矛盾（见 §3.9）。

**V1 的写入约束**：V1 不联网，故 `healthState` MUST 恒为 `unknown`，`lastCheckedAt` 恒为 nil。
字段存在的唯一目的是让 V2 无需变更 CloudKit 生产 schema。

**状态转换**

```
draft(创建中) → active ──┬─→ revokedUpstream   (刷新发现平台侧已删除/禁用)
                         └─→ softDeleted        (用户删除 → 进入「最近删除」回收站)
revokedUpstream → softDeleted
softDeleted ──┬─→ active              (用户恢复；清 deletedAt / purgeAfter)
              └─→ (物理清除)          (purgeAfter 到期，或用户「立即删除」，或 FR-061)
```

`revokedUpstream` 与 `softDeleted` 均 MUST NOT 计入可用密钥与免费额度。

**回收站期间（`softDeleted` 且未到 `purgeAfter`）**（DC-029）：

| 项 | 行为 |
|----|------|
| Keychain 明文 | **保留**（否则无法恢复——这是对旧「删除即毁明文」语义的纠正） |
| `KeyAssignment` | **保留**（恢复后指派关系不丢） |
| 主列表 / 复制 / 探活 | MUST NOT 包含该密钥 |
| 用量快照 | 保留；永久清除后仍保留并标注已删除 |

**永久清除后**：删 Keychain 条目 + 删 `KeyAssignment` + 删（或 tombstone）`APIKeyRecord`；`UsageSnapshot` 保留。

### 3.3 ConsumerTool（使用方工具 / 消费端平台）

**术语警告**：本产品有**两类平台**，不可混淆。`ConsumerTool` 是**消费端**
（VS Code、Cursor、OpenCode、Trae…），`UpstreamAccount.platform` 是**上游 API 提供方**
（OpenAI、Anthropic、DeepSeek、智谱 AI、火山引擎…）。见 spec.md 术语表。

| 字段 | 类型 | 同步 | 约束 |
|------|------|------|------|
| id | UUID | ✅ | 主键。CloudKit 无唯一约束，见账号「重复行」同一套规则 |
| name | String | ✅ | 1…48 字符，非空。用户可自定义新增（FR-007a） |
| iconSymbol | String? | ✅ | 预置/目录 SF Symbol 名称 |
| avatarSymbol | String? | ✅ | 用户覆盖的头像；nil = 预置工具跟目录，自建工具跟产品写死的默认（设置不再改默认） |
| avatarColor | String? | ✅ | 底色标记；与 `avatarSymbol` 同进同出 |
| isPreset | Bool | ✅ | 是否来自内置预置清单，默认 false |
| isHidden | Bool | ✅ | 预置项可被隐藏而非删除，默认 false |
| createdAt / updatedAt | Date | ✅ | `updatedAt` 为资料变更时间（改名/备注/图标）；调整 `sortOrder` MUST NOT 改写（FR-064） |
| sortOrder | Int | ✅ | 默认 0；自定义分区顺序（FR-064） |

预置清单对应 spec CL-003；预置项 MUST 可被用户重命名或隐藏，用户 MUST 能自定义新增任意名称
（FR-007a）。**预置清单是内置常量而非用户数据**，随应用更新扩充；用户新增的项 `isPreset = false`，
**MUST NOT 因应用更新而被覆盖或删除**。

### 3.3a KeyAssignment（密钥 ↔ 使用方，多对多）

**一把密钥 MAY 被指派给多个使用方工具**（DC-011）。因此指派关系不能是 `APIKeyRecord` 上的
单个外键，必须是独立的中间表。

| 字段 | 类型 | 同步 | 约束 |
|------|------|------|------|
| id | UUID | ✅ | 主键 |
| keyId | UUID | ✅ | → `APIKeyRecord.id` |
| consumerToolId | UUID | ✅ | → `ConsumerTool.id` |
| createdAt | Date | ✅ | — |

**验证规则**

- `(keyId, consumerToolId)` 组合应唯一。CloudKit 无唯一约束，故在 Business 层去重；
  同步竞态产生的重复行 MUST 在读取时按组合去重并集，MUST NOT 导致该密钥被计算两次，
  MUST NOT 套用账号/密钥的整行 LWW（见 §3.1 冲突字段取舍表）。
- **「未分配」的定义**：不存在任何 `KeyAssignment` 引用该 `keyId`。

#### ⚠️ 多对多引入的统计口径约束（V2 必须遵守）

上游平台只按**密钥**提供用量，无法拆分「这把密钥的 12 美元里有多少是 VS Code 花的」。因此：

| 场景 | 按使用方维度的归属 |
|------|-------------------|
| 密钥仅指派给 1 个工具（独占） | 全额归入该工具 |
| 密钥指派给 ≥2 个工具（共享） | **MUST NOT 摊分到各工具**。归入独立的「共享密钥」小计项，并说明原因 |
| 密钥未指派 | 归入「未分配」小计项 |

- **MUST NOT 平均摊分或按任何比例估算** ——那是编造数据（宪法 IX）。
- **MUST NOT 把共享密钥的用量重复计入每个工具** ——会使按使用方维度的总量大于按平台维度的总量。
- 因此 SC-005 的自洽口径为：
  `按使用方维度总量 = 独占密钥之和 + 共享密钥小计 + 未分配小计 = 按平台维度总量`

**这个限制只有 V3 的中转能真正解除**：中转可为同一把原始密钥向两个工具签发两把不同的中转密钥，
逐笔归属自然清晰。V1/V2 期间它是上游平台能力的硬限制，产品的责任是如实呈现而非掩盖。

### 3.4 UsageSnapshot（用量快照 · 周期聚合）

按 (密钥, 周期粒度, 周期起点) 幂等 upsert，**不是** append-only 明细。

| 字段 | 类型 | 同步 | 约束 |
|------|------|------|------|
| id | UUID | ✅ | 主键 |
| keyId | UUID | ✅ | → `APIKeyRecord.id` |
| granularity | String | ✅ | `day` / `week` / `month` / `total` |
| periodStart | Date | ✅ | 周期起点（存储一律 UTC 对齐） |
| **periodTimeZone** | String? | ✅ | **该平台给出这个周期时所用的口径**，如 `UTC`、`Asia/Shanghai`。nil = 平台未说明。见下方专节（FR-019a、DC-022） |
| inputTokens | Int? | ✅ | nil = 平台未提供 |
| outputTokens | Int? | ✅ | nil = 平台未提供 |
| totalTokens | Int? | ✅ | nil = 平台未提供 |
| reportedCostUSD | Decimal? | ✅ | 平台直接给出的费用（如 OpenRouter），nil = 平台不提供 |
| estimatedCostUSD | Decimal? | ✅ | 本产品按单价估算，nil = 无法估算 |
| pricingRuleId | UUID? | ✅ | 估算所用单价快照（FR-019） |
| modelName | String? | ✅ | 平台支持按模型拆分时填写 |
| dataSource | String | ✅ | `platformAPI` / `relayLedger`（阶段三保留） |
| fetchedAt | Date | ✅ | 本条数据的获取时间（FR-017 时间戳来源） |
| capabilityNote | String? | ✅ | 平台能力限制说明键（如 `perKeyUnsupported`），驱动 FR-016 文案 |

**验证规则**

- Token 字段不可为负；未知则 nil，**MUST NOT 以 0 代替**（宪法 IX）。
- `reportedCostUSD` 与 `estimatedCostUSD` MUST 分别存储、分别呈现，不得混为一个字段——
  前者是平台数字，后者是本产品估算（FR-015、宪法 IX）。
- upsert 键为 `(keyId, granularity, periodStart)`。重复拉取同一周期 MUST 覆盖而非追加。

#### ⚠️ 时区口径必须随数据记录（FR-019a，字段 V1 必须预留）

各上游平台的周期口径不一致：OpenAI 的日桶按 **UTC** 划分，DeepSeek 的账单按**北京时间**出，
OpenRouter 的 `usage_daily` 又是另一套。若不记录口径：

- 用户看到的「今天花了多少」会与平台后台对不上，进而判定本产品统计有误；
- 而 FR-019 禁止静默改写历史估算值，**事后统一口径将无法在不违反 FR-019 的前提下完成**——
  要么重算历史（违规），要么让两套口径并存（更糟）。

因此：`periodStart` 的**存储**一律 UTC 对齐（保证 upsert 键稳定），`periodTimeZone` 记录该平台的
**原始口径**，展示层 MUST 据此标注（如「按 OpenAI 口径 / UTC」）。**MUST NOT 把不同口径的数据
相加后呈现为一个「今天」的数字**而不加说明。

**阶段三扩展（FR-031）**：逐笔明细以**新增独立实体** `UsageDetail` 承载（additive schema 变更，
非破坏性），并与本实体共用同一读取协议，故 UI 层与聚合查询无需改动。本期不创建该实体。

### 3.5 BalanceSnapshot（账户级余额快照）

| 字段 | 类型 | 同步 | 约束 |
|------|------|------|------|
| id | UUID | ✅ | 主键 |
| accountId | UUID | ✅ | → `UpstreamAccount.id` |
| currency | String | ✅ | `USD` / `CNY` 等 |
| totalBalance | Decimal? | ✅ | nil = 平台不提供 |
| grantedBalance | Decimal? | ✅ | 赠送余额（DeepSeek 提供） |
| toppedUpBalance | Decimal? | ✅ | 充值余额（DeepSeek 提供） |
| isSufficient | Bool? | ✅ | 平台给出的可用性判断 |
| fetchedAt | Date | ✅ | 获取时间 |

DeepSeek 仅支持本实体、不支持 `UsageSnapshot` 的按密钥拆分——这是 FR-016 的直接依据。

### 3.6 PricingRule（单价规则）

| 字段 | 类型 | 同步 | 说明 |
|------|------|------|------|
| id | UUID | ✅ | 主键 |
| platform | String | ✅ | 所属平台 |
| modelPattern | String | ✅ | 如 `gpt-4o*` |
| inputPricePer1M | Decimal | ✅ | USD |
| outputPricePer1M | Decimal | ✅ | USD |
| effectiveFrom | Date | ✅ | 生效日 |
| source | String | ✅ | `bundled` / `userOverride` |

估算公式：`estimatedCost = inputTokens/1e6 × inputPrice + outputTokens/1e6 × outputPrice`。
写入 `UsageSnapshot` 时 MUST 快照 `pricingRuleId`；单价变更 MUST NOT 改写既有快照（FR-019、宪法 IX）。

### 3.7 UserPreferences（singleton，**同步** — 安全相关偏好）

| 字段 | 类型 | 同步 | 说明 |
|------|------|------|------|
| id | UUID | ✅ | 固定 singleton 逻辑 id |
| appLockEnabled | Bool | ✅ | 打开 App 需身份确认 / 自动锁定开关 |
| autoLockSeconds | Int | ✅ | 当前选中的自动锁定时长 |
| autoLockDurationOptionsJSON | String? | ✅ | 时长列表 JSON；`nil` 首次预填 `[0,60]`；`[]` 表示用户删光 |
| revealPolicy | String | ✅ | `none`（默认） / `biometricOrPasscode` / `biometricOnly` / `masterPassword`（FR-003 四档） |
| clipboardClearEnabled | Bool | ✅ | 剪贴板自动清除开关，默认 true（FR-005） |
| clipboardClearSeconds | Int | ✅ | 当前选中的清除时长，默认 120（FR-005） |
| clipboardClearDurationOptionsJSON | String? | ✅ | 时长列表 JSON；`nil` 首次预填 `[30,120]`；`[]` 表示用户删光 |
| clipboardLocalOnly | Bool | ✅ | 禁用通用剪贴板（FR-004） |
| hideInAppSwitcher | Bool | ✅ | — |
| refreshIntervalMinutes | Int | ✅ | 0 = 仅手动（FR-021a，V2 使用） |
| displayCurrency | String | ✅ | `USD` / `CNY`（V2 使用） |
| usdToDisplayRate | Decimal? | ✅ | 用户可维护的汇率（V2 使用） |
| notifyLowBalance / notifyKeyRevoked / notifyWeeklyDigest | Bool | ✅ | 三类提醒开关（V2 使用） |
| lowBalanceThreshold | Decimal? | ✅ | 余额提醒阈值（V2 使用） |

`revealPolicy` **单一字段同时管辖查看与复制**——不设两个开关（FR-003、宪法 VIII）。

CloudKit 无唯一约束，同步竞态可能留下多条同 `singletonID` 的行。读取按指纹选赢家（本实体无 `updatedAt`）；写入打到全部副本。**13.5 起卫生清扫 MUST NOT 物理删除冲突行**——指纹赢家不是最后修改者优先。见 §3.1 冲突字段取舍表。

**本实体只放需要在各设备间保持一致的偏好**。安全策略若各设备不同，用户会误判自己的实际保护
等级，因此必须同步。

### 3.7a DevicePreferences（singleton，**local 配置，不同步** — 界面相关偏好）

| 字段 | 类型 | 同步 | 说明 |
|------|------|------|------|
| id | UUID | ❌ | 固定 singleton 逻辑 id |
| appearance | String | ❌ | `system` / `light` / `dark`（FR-021） |
| defaultGrouping | String | ❌ | `byPlatform` / `byConsumer`（FR-008） |
| lastWindowWidth / lastWindowHeight | Double? | ❌ | Mac 窗口尺寸记忆，iOS 不使用 |
| platformSectionSortCriterion / Ascending | String / Bool | ❌ | 按平台分区排序（FR-064）；默认 `name` + 升序 |
| consumerSectionSortCriterion / Ascending | String / Bool | ❌ | 按使用方分区排序（FR-064）；默认 `name` + 升序 |
| defaultKeyAvatarSymbol / Color | String | ❌ | **遗留字段**（本机模型不可删）。界面 MUST NOT 读；设置 MUST NOT 提供改默认入口。空或有值都不影响展示，未单独覆盖的条目走产品写死的紫钥匙 |
| defaultCustomAccountAvatarSymbol / Color | String | ❌ | 同上；产品写死的默认是深灰建筑 |
| defaultCustomToolAvatarSymbol / Color | String | ❌ | 同上；产品写死的默认是蓝电脑 |

**为何不同步**（FR-060、DC-021）：外观与默认视角是**每台设备各自的选择**。「在 Mac 上切成深色
导致 iPhone 也变深色」是用户并不想要的联动；窗口尺寸更是与 iPhone 无关。

**为何现在就拆而不是以后再拆**：事后把字段从 `synced` 配置搬到 `local` 配置，是**跨
`ModelConfiguration` 的数据搬迁**——要在迁移代码里读旧库、写新库、并处理两台设备各有一份不同旧值
时以谁为准。这比新增字段麻烦得多，属于典型的「越晚做越贵」。

### 3.8 EntitlementSnapshot（local 配置，不同步）

| 字段 | 类型 | 同步 | 说明 |
|------|------|------|------|
| id | UUID | ❌ | singleton |
| tier | String | ❌ | `free` / `unlimitedKeys` / `relay`（第三级本期不可达，FR-032） |
| source | String | ❌ | `storekit` / `debugOverride` |
| updatedAt | Date | ❌ | 最近一次从 StoreKit 刷新的时间 |

**刷新时机**：启动、进入前台、购买/恢复完成、`Transaction.updates` 推送。快照仅作离线兜底，
联网时以 StoreKit 结果覆盖。

**权限推导**：`tier != .free` → 解除密钥数量上限。`tier == .relay` 本期 MUST NOT 可达，
且 MUST NOT 出现在付费界面。

### 3.9 RefreshHealth（UserDefaults，非 SwiftData）

`Codable` 结构存 `UserDefaults`，key = `com.apirelay.refreshHealth`。按平台账号分别记录：

| 字段 | 类型 | 说明 |
|------|------|------|
| perAccount | [UUID: AccountHealth] | 按账号隔离（宪法 V、FR-018） |
| AccountHealth.lastSuccessAt | Date? | 最近成功刷新时间 |
| AccountHealth.state | String | `healthy` / `refreshing` / `degraded` / `unsupported` |
| AccountHealth.lastErrorMessage | String? | 用户可读失败原因（FR-017） |

**理由**：纯本机 UI 状态，同步它本身自相矛盾；放进带 CloudKit 的 schema 会形成「不同步的特例」，
徒增配置复杂度。**按账号隔离**是宪法第 V 条「单平台失效不影响其他平台」的落点。

---

## 4. 实体关系

```text
UpstreamAccount 1 ──< APIKeyRecord                           [synced]
APIKeyRecord    n >──< KeyAssignment >──< n ConsumerTool      [synced]  ← 多对多
UpstreamAccount 1 ──< BalanceSnapshot                        [synced]
APIKeyRecord    1 ──< UsageSnapshot                          [synced]
PricingRule     1 ──< UsageSnapshot (optional 快照引用)       [synced]
UserPreferences (singleton)                                  [synced]   ← 安全相关偏好
DevicePreferences (singleton)                                [local，不同步]  ← 界面相关偏好
EntitlementSnapshot (singleton)                              [local，不同步]
RefreshHealth                                                [UserDefaults]
```

**共十个实体**：`synced` 配置八个（`UpstreamAccount`、`APIKeyRecord`、`ConsumerTool`、
`KeyAssignment`、`UsageSnapshot`、`BalanceSnapshot`、`PricingRule`、`UserPreferences`），
`local` 配置两个（`DevicePreferences`、`EntitlementSnapshot`）。

**两类平台位于关系的两端，不可混淆**：左端 `UpstreamAccount` 是**上游 API 提供方**，
右端 `ConsumerTool` 是**消费端工具**。中间的 `APIKeyRecord` 是二者的连接物。
这也是 US8 关系图三列布局的数据依据。

**双视角同源**：`byPlatform` 视角按 `APIKeyRecord.accountId` 分组；`byConsumer` 视角经
`KeyAssignment` 分组。**两个视角读同一批 `APIKeyRecord`，不存在两份数据**——这是 FR-008
与 SC-005 的结构性保证。

**多对多下的分组语义**（务必按此实现，否则总量必然不自洽）：

| 密钥的指派数 | `byPlatform` | `byConsumer` |
|-------------|--------------|--------------|
| 0 | 归入其平台 | 归入「未分配」 |
| 1 | 归入其平台 | 归入该工具 |
| ≥2 | 归入其平台 | 归入「共享密钥」，**不重复计入各工具** |

在**列表视图**中，共享密钥 MAY 同时显示在多个工具的展开项下（方便查看）；
但在**汇总计算**中 MUST 只计一次，归入「共享密钥」项。**显示可以重复，计数不可以。**

---

## 5. CloudKit 同步边界

### 同步 ✅（`synced` 配置）

`UpstreamAccount`、`APIKeyRecord`、`ConsumerTool`、`KeyAssignment`、`UsageSnapshot`、
`BalanceSnapshot`、`PricingRule`、`UserPreferences`

### 不同步 ❌

- Keychain 内容（由 **iCloud 钥匙串**独立同步，不经 CloudKit）
- `DevicePreferences`（外观与默认视角是每台设备各自的选择，FR-060）
- `EntitlementSnapshot`（StoreKit 为真相源）
- `RefreshHealth`（UserDefaults，本机 UI 状态）
- 内存中的临时明文
- **任何明文派生物**（哈希、指纹、校验和）以及密钥末位片段、字符长度——宪法 VII 明令禁止写入
  CloudKit / SwiftData / 导出物。这是 FR-057 改为本机 Keychain 相等比较、不存末四位的原因。

### 同步与否的判据

一条数据该不该同步，取决于**它描述的是客观事实还是本机状况**：

| 数据 | 描述的是 | 结论 |
|------|----------|------|
| `APIKeyRecord.healthState` | 平台侧的客观事实（这把密钥被不被接受） | ✅ 同步。A 设备检测出失效，B 设备也该看到 |
| `RefreshHealth` | 本机的网络与刷新状况 | ❌ 不同步。同步它自相矛盾 |
| `UserPreferences.revealPolicy` | 用户的安全策略 | ✅ 同步。各设备不一致会让用户误判保护等级 |
| `DevicePreferences.appearance` | 这台设备的界面选择 | ❌ 不同步 |

### 约束

SwiftData 自动生成 CloudKit record type；**禁止**手动混用 `CKRecord` API 写业务数据（避免双写）。

---

## 6. 平台能力矩阵（代码内静态表，不持久化）

**这里的「平台」指上游 API 提供方，与消费端工具无关。**

| 上游平台 | 可在 App 内签发密钥 | 按密钥用量 | 账户余额 | 所需凭证 |
|----------|--------------------|-----------|----------|----------|
| `openrouter` | ✅ | ✅（累计/日/周/月 + 额度剩余） | ✅ | Management Key |
| `openai` | ❌ | ✅（token 数） | ❌ | Admin Key |
| `anthropic` | ❌ | ✅（token 数） | ❌ | Admin Key |
| `deepseek` | ❌ | ❌ | ✅ | 普通 Key |
| `google` | ⚠️ 待调研 | ⚠️ 待调研 | ⚠️ 待调研 | 待定 |
| `alibaba-bailian` | ⚠️ 待调研 | ⚠️ 待调研 | ⚠️ 待调研 | 待定 |
| `volcengine` | ⚠️ 待调研 | ⚠️ 待调研 | ⚠️ 待调研 | 待定 |
| `siliconflow` | ⚠️ 待调研 | ⚠️ 待调研 | ⚠️ 待调研 | 待定 |
| `zhipu` | ⚠️ 待调研 | ⚠️ 待调研 | ⚠️ 待调研 | 待定 |
| `custom` | ❌ | ❌ | ❌ | — |

标 ⚠️ 的平台在 **V1 只需支持密钥保管**（保管不需要知道任何平台能力）。
其接口能力属 **V2 的调研任务**，未调研完成前其能力矩阵 MUST 全部标记为不支持，
界面如实呈现为「该平台能力未接入」——**MUST NOT 呈现为功能故障或数据为零**（宪法 IX）。

**为何不持久化**：能力随平台接口演进而变，应随应用更新而更新；若持久化则老设备会保留过期能力声明，
导致界面呈现与实际不符。UI 依据本表决定按钮可用性与说明文案（FR-011、FR-016）。

---

## 7. Schema 版本与迁移

| SchemaVersion | 变更 |
|---------------|------|
| v1 | 阶段一初始模型（含 V2 预留的 `healthState` / `lastCheckedAt` / `lastCheckNote` 等） |
| v2（阶段三） | **仅 additive**：新增 `UsageDetail` 实体；`APIKeyRecord.origin` 启用 `relayIssued` 取值 |

### 7.1 CloudKit 生产 schema 部署（不可逆；FR-063 / DC-027）

Development 与 Production 是**两套独立 schema**。下列清单 MUST 在 **Production** 侧一次性部署完成，
方可通过 tasks.md Checkpoint **2b**（T014b；功能开发可在 Checkpoint **2a** 后继续）：

| Record type（≈ `@Model` 类名） | 关键预留字段（漏了就要再部署） |
|-------------------------------|-------------------------------|
| `UpstreamAccount` | 自定义接入地址等 |
| `APIKeyRecord` | `healthState`、`lastCheckedAt`、`lastCheckNote`、`secretLength`、`origin`、`deletedAt`、`purgeAfter` |
| `ConsumerTool` | `isPreset`、`isHidden` |
| `KeyAssignment` | `(keyId, consumerToolId)` |
| `UsageSnapshot` | 时区口径字段（FR-019a）、`dataSource` |
| `BalanceSnapshot` | — |
| `PricingRule` | — |
| `UserPreferences` | 仅安全相关偏好（FR-060）。热修 additive：`autoLockDurationOptionsJSON`、`clipboardClearDurationOptionsJSON`（2026-08 的 2b **未含**这两项；**2026-09-10** Production 的 `CD_UserPreferences` 已确认有这两字段，Deploy 差异为 0。此后新 additive 字段发出正式包前仍 MUST Deploy Production） |

**不进 CloudKit 的**：`EntitlementSnapshot`、`RefreshHealth`、`DevicePreferences`、Keychain。

生产 schema 字段**不可删、类型不可改**；此后只允许 additive。Deploy 操作本身在 Dashboard
中执行，本仓库无法用代码代替——故以 Checkpoint 人工确认。

### 迁移规则（宪法 VI）

1. **Additive**：新字段 MUST optional 或带 `@Attribute(.defaultValue)`；新实体为非破坏性变更。
2. **Rename**：用 `SchemaMigrationPlan.willMigrate` 拷贝旧值，保留至少 1 个 MAJOR 版本可读。
3. **删除字段**：先标 deprecated 并保留解析，下一大版本再移除。
4. **Keychain**：Service 名与 Account UUID 不变，无版本号概念。
5. **降级**：不支持。

### 触发

```text
App 启动 → ModelContainer 初始化 → 自动 lightweight migration
失败 → 阻塞启动，展示「数据升级失败」+ 本地备份路径说明
```

---

## 8. 索引与查询

| 查询 | 描述 |
|------|------|
| 按平台分组的密钥列表 | `lifecycle != softDeleted`，按 `accountId` 分组，`sortOrder` 排序 |
| 按使用方分组的密钥列表 | 经 `KeyAssignment` 分组；无指派记录的密钥归「未分配」 |
| 某密钥的指派数 | `KeyAssignment` 中 `keyId == ?` 去重计数，用于判定独占 / 共享 |
| 单密钥用量 | `keyId == ? && granularity == ?`，`periodStart` 降序 |
| 平台维度汇总 | 取该账号下全部 `keyId`，按 `keyId IN` 聚合（内存聚合） |
| 使用方维度汇总 | 取该使用方下**独占**密钥聚合；共享密钥单列小计（见 §3.3a） |
| 免费额度计数 | `lifecycle != softDeleted` 全表计数 |

两个维度的汇总 MUST 走**同一套聚合函数**，仅分组键与「共享/未分配」的归集规则不同——
这是 SC-005 的实现保证。**MUST NOT 为两个视角各写一份聚合逻辑。**

---

## 9. 数据完整性约束

- **删除密钥（移入回收站，FR-006 / DC-029）**：`lifecycle = softDeleted`，写 `deletedAt` 与
  `purgeAfter = deletedAt + 30 天`；**保留 Keychain 明文**；**保留 `KeyAssignment`**；
  主列表不再展示。若平台支持且用户选择「同时在平台侧禁用」（V2、FR-009），那是独立动作，
  MUST NOT 与移入回收站默认捆绑。
- **恢复密钥**：`lifecycle = active`，清空 `deletedAt` / `purgeAfter`；Keychain 与指派原样可用。
- **永久清除密钥**：删除 Keychain Item + 删除全部 `KeyAssignment` + 删除 `APIKeyRecord`；
  `UsageSnapshot` **保留**并标注归属已删除。触发：`purgeAfter` 到期（启动时巡检）、
  用户在回收站选「立即删除」、或「清除全部数据」（FR-061）。
- **删除上游账号**：MUST 级联将其下密钥**移入回收站**（同上，保留各密钥 Keychain）；
  账号自身软删并设 30 天清除；管理类凭证在账号永久清除时一并删 Keychain。
  用量与余额快照保留。删除前 MUST 二次确认并说明影响范围。
- **删除使用方工具**：MUST NOT 级联删除密钥；只删除指向它的 `KeyAssignment` 行。
  仅被该工具指派的密钥回到「未分配」；同时指派给其他工具的密钥保持已分配状态。
- **预置项的删除**：`isPreset == true` 的使用方工具与上游平台 MUST NOT 可被物理删除
  （应用更新会重新引入），只能 `isHidden = true` 隐藏。用户自建项可物理删除。
- **创建密钥的两步一致性**（FR-010）：平台侧创建成功但 Keychain 写入失败时，MUST 保留
  `APIKeyRecord` 并标记为需人工处理，同时明确提示用户前往平台后台处理；**MUST NOT** 回滚删除
  平台侧密钥（可能误删），也 MUST NOT 静默丢弃。
- **免费额度**：在 Business 层校验，不依赖数据库约束（CloudKit 无唯一/检查约束）。
- **明文与元信息的孤儿处理**：启动时的一致性巡检——元信息存在而 Keychain 缺失，标记为
  `明文缺失`；Keychain 存在而元信息缺失，视为孤儿并提示用户（可能来自被卸载重装或同步竞态）。
- **清除全部数据**（FR-061）：物理删除本产品写入的全部 Keychain 条目（`keys` / `admin` /
  `masterpw` 三类 Service）+ 清空同步 SwiftData 实体 + 清空本机 `EntitlementSnapshot` /
  `RefreshHealth` / 设备偏好。**不**撤销 StoreKit 交易。开启 iCloud 同步时，CloudKit 与
  iCloud 钥匙串的删除会传播到用户其他设备——这是预期行为，UI MUST 事前告知。
  用量快照随用户数据一并清除（与「删除单把密钥仍保留该密钥历史用量」不同：全量清除是用户
  主动销毁全部资产，不保留历史）。

---

## 10. 阶段三扩展点（本期只留接口，不实现）

| 扩展点 | V1 实现 | 后续阶段新增 | 是否破坏性 |
|--------|---------|-------------|-----------|
| **凭证来源**（FR-030） | `APIKeyRecord.origin` = `manualEntry` | V2 启用 `providerIssued` 与 `receivedFromTransfer`；V3 启用 `relayIssued` | 否（枚举加值） |
| **用量来源**（FR-031） | `UsageSnapshot.dataSource` = `platformAPI` | V3 新增实体 `UsageDetail`；`dataSource` 加 `relayLedger` | 否（additive 实体） |
| **权益等级**（FR-032） | `tier` = `free` / `unlimitedKeys` | V3 启用 `relay` | 否（枚举加值） |
| **加密文件用途**（FR-022、FR-047） | 格式含 `purpose` = `fullBackup` 与 `scope` 字段 | V2 启用 `purpose = transfer` | 否（**前提是 V1 就留好这两个字段**） |
| **密钥健康度检测**（FR-055、DC-028） | 字段 + `KeyHealthServing` 协议预留；V1 不实现 | V2 填入实现与 UI | 否 |
| **指派关系** | `KeyAssignment` 中间表（多对多） | 无需变更 | — |

全部扩展点均为**枚举加值、新增实体或已预留字段**，不涉及既有字段的语义或类型变更，故不产生破坏性迁移。

**⚠️ 最容易漏的一项是加密文件格式的 `purpose` 字段。** 它不在 SwiftData schema 里，因此不受
`SchemaMigrationPlan` 保护——一旦 V1 导出的文件缺少该字段，V2 无法区分「这是备份还是别人传给我的」，
只能靠猜或强制升级格式，届时已导出的文件会失去正确的用途标识。

---

## 变更记录

- 2026-08-21：预置上游平台扩至 9 家 + `custom`（新增 `zhipu`）；清单顺序固定为 OpenAI → Anthropic → Google → OpenRouter → DeepSeek → 智谱 → 阿里百炼 → 火山引擎 → 硅基流动。显示名：Anthropic 不再用模型名 Claude；中国厂家中文界面用中文名（DeepSeek 除外）。
- 2026-08-04（晚，第二次修订）：
  - **指派关系改为多对多**（DC-011）。移除 `APIKeyRecord.consumerToolId`，新增中间表
    `KeyAssignment`。连带写入「共享密钥的用量不可摊分」这一统计口径约束（§3.3a）。
  - **扩充上游平台预置清单**至 8 家 + `custom`，并把「用户自定义添加平台」提为一等能力
    （两类平台都支持自定义添加）。
  - 明确 `isPreset` 项不可物理删除、只能隐藏，且不因应用更新覆盖用户自建项。
  - 全文强化**两类平台的术语区分**（上游 API 提供方 vs 消费端工具）。


- 2026-08-04：整体重写。原 data-model.md 面向「OpenAI 兼容流式中转 + 逐笔调用记录」，与现规范无关，
  已作废。核心变更：Keychain 由「ACL + 不同步」改为「无 ACL + 同步」（research §1）；
  `RelayCallRecord`（逐笔）替换为 `UsageSnapshot`（周期聚合）；新增 `UpstreamAccount`、
  `ConsumerTool`、`BalanceSnapshot`；`RefreshHealth` 改为按账号隔离。
