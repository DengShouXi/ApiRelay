# Phase 0 技术调研

**Feature**: 密钥保管、分发与用量统计（阶段一）
**Branch**: `v1`（文档目录 `specs/001-key-vault/`）
**Date**: 2026-08-04
**Spec**: [spec.md](./spec.md) | **Constitution**: v2.0.0

---

## 1. Keychain 的 iCloud 同步与生物识别保护互斥【阻塞决策】

### 结论

**`kSecAttrAccessControl`（系统级生物识别 ACL）与 `kSecAttrSynchronizable`（iCloud 同步）不能同时使用。**

证据：

- 二者同时传入 `SecItemAdd` 返回 `errSecParam`（-50，参数无效）。
- WWDC 2014 Session 711 明确表述：`ACL Protected Items — No Synchronization, No Backup`。
- Apple 文档：标记为 synchronizable 的条目，其 `kSecAttrAccessible` **不得**使用以 `ThisDeviceOnly`
  结尾的取值；而 Apple 为生物识别条目推荐的正是
  `kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly`。
- Apple 文档（`kSecAttrSynchronizable`）：同步条目不能指定基于 `SecAccess` 的访问控制。

### 影响

规范 DC-001 裁决「密钥明文经 iCloud 在用户本人设备间同步」，隐含假设了「同步 + 系统级生物识别」
可以并存。**该假设不成立**，必须在两者间取舍。

### Decision（现行 V1）

采用**分级保护**方案：

**全部凭证均不使用 `kSecAttrAccessControl`（系统级 ACL），门闩统一在应用层实现。** 两类凭证的差异
体现在可访问性等级与门闩策略上：

| 凭证类型 | Keychain 配置 | 同步 | 门闩策略 |
|----------|---------------|------|----------|
| 普通 API 密钥明文 | `kSecAttrAccessibleWhenUnlocked` + `kSecAttrSynchronizable = true` | ✅ iCloud 钥匙串 | 应用层。**仅在用户显式「查看明文 / 复制」时**触发；验证方式由用户在设置中选择，**可选关闭**（DC-006） |
| 管理类高权限凭证（Admin / Management Key） | `kSecAttrAccessibleAfterFirstUnlock` + `kSecAttrSynchronizable = true` | ✅ iCloud 钥匙串 | 应用层。**仅在用户查看或修改该凭证本身时**触发，且此门闩 **MUST NOT 可被用户关闭**（宪法 VIII）。自动刷新读取该凭证时**不触发**任何验证 |

**为何管理类凭证用 `AfterFirstUnlock` 而普通密钥用 `WhenUnlocked`**：管理类凭证需要被按间隔自动
刷新的后台任务读取，而后台刷新可能发生在设备锁定状态下；`WhenUnlocked` 在锁屏时不可读，
`AfterFirstUnlock` 在开机后首次解锁之后即可读。普通密钥只在用户显式操作时读取（此时设备必然已解锁），
用更严格的 `WhenUnlocked` 即可。二者均不以 `ThisDeviceOnly` 结尾，故都可同步。

**保护强度对比**：管理类凭证的存储配置与普通密钥同级，但其门闩**不可关闭**，而普通密钥的门闩可由
用户关闭。因此管理类凭证的实际保护强度**严格高于**普通密钥，满足宪法 v2.0.0 第 VII 条
「管理类高权限凭证 MUST 受到不低于普通密钥的保护」。

### Rationale

- 普通密钥的核心使用场景是「在 Mac 上复制、粘贴到 VS Code」（规范 DC-002 已确认 Mac 本期必做）。
  若不同步，Mac 上只能看到条目而取不出明文，主流程直接断裂——这个代价不可接受。
- 管理类凭证必须能被**按间隔自动刷新的任务无人值守读取**（用量与余额刷新是自动的，不应打断用户）。
  系统级 `.userPresence` ACL 会使后台读取必然失败——后台无法弹出 Face ID。因此管理类凭证也不能用
  系统级 ACL，其保护改由「不可关闭的应用层门闩 + 仅在查看/修改凭证本身时触发」来实现。
- 宪法 v2.0.0 第 VIII 条规定门闩「使用 `LAContext` 调用 Face ID / Touch ID」，未要求必须是 Keychain
  级 ACL，故应用层门闩不违宪。
- 门闩的**触发点**与**读取点**必须区分：自动刷新读取管理类凭证属于系统行为，不是用户查看凭证，
  故不触发门闩；用户在设置中查看或替换该凭证才触发，且不可关闭。

### 安全代价（必须向用户如实披露）

应用层门闩弱于系统级 ACL：条目在设备解锁后即可被本应用进程读取，门闩由应用代码强制而非系统强制。
若攻击者能在已解锁设备上以本应用身份执行代码，理论上可绕过门闩。它适合当前 V1 的“普通设备上的
应用隐私锁”，但**不能据此宣称达到成熟密码管理器的认证绑定解密强度**，也不得对用户宣称“系统级强制”。
OWASP MASWE-0020 明确把“只依据本地认证成功回调、没有把受保护操作绑定到钥匙串密钥”列为可绕过模式。

### Alternatives considered

- **方案 B 保护优先（不同步）**：`WhenPasscodeSetThisDeviceOnly` + `.userPresence`，跨设备靠加密
  导出导入。安全性最强，但 Mac 端无法取出明文，与 DC-002 冲突，主流程价值大幅折损。**已否决。**
- **方案 D 信封加密层**：同步层只保存密文；每个保险库使用随机数据加密密钥（DEK），每台设备再用
  Secure Enclave / Data Protection Keychain 中受本机认证约束的包装密钥解开 DEK；应用密码则使用独立
  KDF 产生的 KEK 包装同一 DEK，并配套恢复或新设备迁移流程。该方案不是“把问题递归一层”，而是成熟
  高保障架构常见的密钥层级；其代价是恢复、设备绑定、轮换和迁移都必须作为完整产品协议设计。
  **V1 不可静默加装，列为 V2 独立迁移项目。**

### 1.1 验证方式的可选项（对应 DC-006）

产品负责人要求「复制密钥时需要面容 / 指纹 / 密码验证，也可以设置为不验证，由用户自选」。落到
`LocalAuthentication` 的实际能力，需要修正两点认知：

**「面容」与「指纹」不是用户可选项。** `LAPolicy` 只区分「是否使用生物识别」，具体用 Face ID 还是
Touch ID 由**设备硬件决定**——iPhone 是 Face ID，多数 MacBook 是 Touch ID，用户无法在应用内切换。
因此设置项不应呈现为「Face ID / 指纹」两个并列选项，否则在只有一种硬件的设备上必有一项无效。

**「密码」有两种含义，须区分**：

- **设备密码**：系统提供，`LAPolicy.deviceOwnerAuthentication` 在生物识别失败或不可用时**自动回退**
  到它。无需额外开发。
- **应用专属主密码**：用户在本产品内单独设置的一个口令。这是一项**独立功能**（需自行存储口令验证
  材料、处理找回与修改），不由系统提供。

### Decision

设置项呈现为**四档**。验证方式列表使用固定产品名。现行权威：[`follow-ups/identity-auth/spec.md`](./follow-ups/identity-auth/spec.md) 与 [`playbooks/身份验证方案.md`](../playbooks/身份验证方案.md)（`v1.13.9` 回写宪法 v2.15.0）。

| 档位 | 实现 | 说明 |
|------|------|------|
| 不验证 | 不调用 `LAContext` | 仍可选，**不是**出厂默认。自动锁定与取用验证配置保留并暂停 |
| 设备验证（设备验证档，**出厂默认**，推荐） | `LAPolicy.deviceOwnerAuthentication` | 系统可回落设备 / Mac 登录密码。列表标题固定，不随硬件改名；ⓘ 可用官方译名 |
| 应用密码 | 见 §1.2 | 独立于设备密码；校验材料不同步（FR-038）。未设则选档时立即准备，成功后才 persist |
| 设备验证或应用验证 | 系统路径只调用一次 `deviceOwnerAuthentication`，由 Apple 先生物识别并在同一流程直接回落设备密码；App 内显式入口才走**已配置**应用密码 | 不得在生物失败后新建第二个 `LAContext`，否则会重新触发生物识别。系统取消不自动改走应用密码。未设则选档时立即准备，目标不得改写成应用密码档。普通入口不得设密。旧 `biometricOnly` 迁到设备验证，不得复用该 rawValue |

下表为 **2026-08 当时裁决**，已被上表覆盖，不得再当现行：不验证曾为默认；曾含「仅生物识别」档。

### 1.2 应用专属主密码（DC-007，产品负责人裁决为「做」）

我最初建议不做，理由是与设备密码功能重叠。产品负责人明确要求做，因此需要解决三个技术问题。

**口令派生函数的选择**：`CryptoKit` **没有** PBKDF2。它提供的 `HKDF` 是从**高熵密钥**派生子密钥
用的，直接拿来处理低熵的人类口令会缺少抗暴力破解所需的计算成本。原生可用的正确选项是
`CommonCrypto` 的 `CCKeyDerivationPBKDF`（`kCCPRFHmacAlgSHA256`），它是系统库的一部分，
不违反宪法第 III 条「零第三方 SDK」。

### Decision

| 项 | 方案 |
|----|------|
| 派生 | `CCKeyDerivationPBKDF` + SHA256，随机 16 字节 salt；新材料至少 600,000 次并以约 250ms 为校准目标，旧材料验证成功后升级 |
| 存储 | 版本 + salt + 迭代次数 + 派生结果 + 连续失败数/下次允许时间存 Keychain，Service `com.apirelay.keychain.masterpw` |
| 可访问性 | `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`，**不同步**（FR-038） |
| 校验 | 恒定时间比较，避免时序侧信道 |
| 在线猜测防护 | 失败状态跨重启保存；第 3 次起指数等待，最多 10 次，达到上限后只能走设备主人恢复并重新登记 |
| 用途 | **仅作门闩的一档，不用于加密任何数据** |

**为何 V1 主密码不直接加密密钥明文**：若没有 DEK 包装、恢复和设备迁移协议，直接用它派生密钥加密
明文会让忘记密码等同于永久丢失全部密钥。当前产品裁决是“多一种本机验证方式”，不是“无恢复的整库
再加密”。高保障 V2 应按上面的信封加密方案独立迁移，不能在现有同步条目上临时叠一层后冒充完成。

**为何不同步**：主密码可被重置（见下），若校验材料随 iCloud 同步，在 A 设备重置会静默改变 B 设备的
行为，用户预期会被打破。每台设备独立设置更容易理解。

**忘记主密码的恢复路径（必须有）**：用户显式确认后，经设备主人验证可重置。缺材料不得要求一个不存在的旧密码。

这带来一个必须诚实披露的后果：**应用密码的实际安全强度不高于设备密码**——攻击者若能通过设备密码，
就能走显式恢复重置应用密码。它是本机门闩，不是整库再加密。若不提供恢复路径，用户遗忘后将无法按该档解锁。
因此设置时 MUST 明确告知恢复路径的存在，MUST NOT 让用户误以为它是不可绕过的
最强保护（宪法 IX）。

选中密码依赖档 MUST 进入同一应用密码页（已设也进）；本机未设时 MUST 立即准备，MUST NOT 在普通解锁/取用/删除入口新建密码。
设置首页仅在已 persist 为「应用密码」或「设备验证或应用验证」时显示「应用密码」行；切出隐藏且 MUST NOT 删除材料。用户界面称「应用密码」，内部 `.masterpw` 不机械重命名。

---

## 2. 剪贴板自动清除与通用剪贴板控制

### 结论

`UIPasteboard.setItems(_:options:)` 在 **iPhone** 上原生支持本产品所需的两个选项：

- **`.expirationDate`**：由系统在指定时刻移除剪贴板内容。执行方是系统时，应用被终止后清除**仍可能**生效。
- **`.localOnly`**：阻止内容经 Handoff / 通用剪贴板同步到其他设备。

可用性：iOS 10+、Mac Catalyst 13.1+（API 存在 ≠ Mac 上能被其他 App 稳定粘贴）。原生 AppKit 的 `NSPasteboard` 没有与 `.localOnly` 对等的公开逐条选项；Apple 文档反而明确说明 general pasteboard 会参与 Universal Clipboard，且没有用于直接控制该功能的 macOS API。

### Decision（现行，落地后修订）

- **iPhone**：主机制 `.expirationDate`，辅以应用内计时（进程存活时兜底；连续复制时系统过期不稳定）。
- **Mac Catalyst**：`setItems` + `.expirationDate` 常无法被其他 App 粘贴。现行 MUST **不写**系统过期，清除只有应用内存活时的计时与正常退出（含 ⌘Q）。强制退出与崩溃清不掉。此局限 MUST 在设置处披露。MUST NOT 为通过「杀掉 App 后仍清除」验收而给 Mac 加回系统过期。
- **原生 macOS**：自动清除使用应用内计时，正常退出用 `changeCount` 尽力清除；强制退出/崩溃不承诺。所谓“仅本机”只能写入业界通用的 `org.nspasteboard.ConcealedType` / `org.nspasteboard.TransientType` 敏感与临时标记，属于防御性尽力而为，不是 Apple 提供的 Universal Clipboard 保证。UI MUST 改用非绝对标题并引导用户关闭系统接力来获得保证。
- 兜底清除前 MUST 校验剪贴板当前内容仍是本产品写入的那一份（FR-005）。
- 「仅本机剪贴板」暴露为用户可选开关：UIKit 映射 `.localOnly`；原生 AppKit 写敏感/临时标记并显示能力上限。默认**关闭**（即允许通用剪贴板），因为「iPhone 复制、Mac 粘贴」是用户的真实场景；但须在设置处披露该路径会使明文离开本机。

### 当时论据（规划期，部分过时）

规划时认为 Catalyst 上 `.expirationDate` 能使 Mac 与 iPhone 同等「杀掉仍清」，因而「规范无需下调」。
落地后 Mac 粘贴与系统过期互斥，已下调为上面的现行 Decision。FR-005 / 宪法 VII 的「平台无法保证则披露」条款覆盖此上限。

### Alternatives considered

- 纯应用内计时：应用一退出即失效。iPhone 上仍用系统过期作主机制；Mac 上这是能力上限，不是偷懒。

---

## 3. Mac 实现方式：Mac Catalyst

### Decision

采用 **Mac Catalyst**（单 iOS target 开启 `SUPPORTS_MACCATALYST`），而非独立的原生 macOS target。

### Rationale

- **当时决定性因素（规划期）**：指望 Catalyst 上 `UIPasteboard.expirationDate` 让 Mac 也能「杀掉仍清」；原生 `NSPasteboard` 没有等价机制。
- **落地后**：Catalyst 上系统过期与「其他 App 能粘贴」不能两全，Mac 改为不写系统过期（见 §2）。选 Catalyst 的**现行**理由是单 target、业务/数据层复用，**不是**剪贴板过期。
- 业务层与数据层 100% 复用，符合宪法第 IV 条。
- Mac 专项适配限于 UI 层：窗口尺寸、菜单栏 `Commands`、右键菜单、hover 状态、键盘快捷键。

### Alternatives considered

- 原生 macOS target：Mac 端体验上限更高，但双份 UI，且仍然没有可靠系统过期。**不因剪贴板而改形态（DC-020）。**

---

## 4. 上游平台能力矩阵

各平台对「程序化创建密钥」与「按密钥查询用量」的支持差异极大。这是规范 US4 与宪法第 IX 条
「数据真实性」的事实基础。

| 平台 | 程序化创建/禁用密钥 | 按密钥用量 | 所需凭证 | 关键接口 |
|------|--------------------|-----------|----------|----------|
| **OpenRouter** | ✅ 支持 | ✅ 累计 / 日 / 周 / 月 + 额度剩余 | Management Key | `POST/GET /api/v1/keys` |
| **OpenAI** | ❌ 需官网创建 | ✅ token 数（按 `api_key_id` 分组） | Admin Key | `GET /v1/organization/usage/completions?group_by=api_key_id` |
| **Claude** | ❌ 需官网创建 | ✅ token 数（按 `api_key_id` 分组） | Admin Key | `GET /v1/organizations/usage_report/messages?group_by[]=api_key_id` |
| **DeepSeek** | ❌ 需官网创建 | ❌ **仅账户级余额** | 普通 Key | `GET /user/balance` |

### 关键细节

- **OpenRouter 创建接口的明文只返回一次**，无法事后取回。对应规范 FR-010：创建成功但本地保存失败
  时必须明确告警并指引用户前往平台处理，禁止静默丢失。
- **OpenAI / Claude 只给 token 数，不给按密钥的费用**。Claude 的 `cost_report` 仅支持按 workspace 或
  description 分组，**不支持** 按 `api_key_id`。故费用必须由本产品依据单价规则估算（FR-015），
  并标注口径。
- **DeepSeek 无官方按密钥用量接口**。社区流传的 `/v1/usage` 不在官方文档中，权限与稳定性均不可靠，
  **不予采用**（另见 FR-OUT-006：不做网页抓取或模拟登录）。该平台在密钥级显示能力限制说明
  （FR-016）。
- Admin / Management Key 是**组织级高权限凭证**，与普通密钥保护级别不同，见 §1 的分级方案。

### Decision

- 平台适配抽象为统一的「平台能力描述 + 平台适配器」，每个平台声明自己支持哪些能力，UI 依据声明
  决定按钮可用性与说明文案（FR-011、FR-016）。
- 单平台解析失败或接口变更 MUST 被隔离，不影响其他平台（宪法第 V 条、FR-018）。

---

## 5. 业务元数据的存储与多设备一致

### Decision

- **明文**：Keychain（见 §1）。
- **业务元数据**（密钥元信息、使用方工具、平台账号配置、用量快照、单价规则、偏好）：
  SwiftData + CloudKit Private Database 自动同步。
- **纯本机状态**（同步健康度、UI 临时状态）：UserDefaults，不入 SwiftData schema。
- **权益状态**：StoreKit 2 的 `Transaction.currentEntitlements` 为唯一真相源；本地仅存离线兜底快照，
  **不同步**（避免双真相源与调试态污染其他设备）。

### Rationale

沿用原设计中已验证的结论。CloudKit 要求所有同步属性 optional 或有默认值；用量快照采用
append-only 或按 (密钥, 周期) 幂等 upsert，避免 LWW 覆盖丢历史。

---

## 6. 内购与权益

### Decision

StoreKit 2，**单个非消耗型内购**解锁无限密钥。权益枚举按三级设计（`free` / `unlimitedKeys` /
`relay`），第三级本期不可达且 MUST NOT 出现在付费界面（FR-032）。

必须实现「恢复购买」（FR-028）——苹果审核会专门检查非消耗型内购的恢复入口。

放行只看：苹果 `.verified`、产品 ID 匹配、未退款。正式包额外只挡 `.xcode`（本地假商店）。
TestFlight / 审核的 `.sandbox` 与正式店的 `.production` 都放行。MUST NOT 要求
`transaction.environment == AppTransaction.environment`（环境和 App 包偶发不一致时会变成
「钱扣了却不是会员」）。苹果已返回购买成功后，MUST NOT 因本地再查档位失败而把这次购买报成失败。
`debugOverride` MUST 仅 `#if DEBUG`，MUST NOT 做界面/启动参数后门。

### Rationale

规范已裁决单档买断，无升级差价包，无订阅，权益判断收敛为一个枚举加一个 `canUse(_:)` 判断函数。
阶段三上线时新增一个内购项与一个枚举分支即可，无需改动既有权益逻辑。

---

## 7. 自动刷新与通知

### Decision

用量与余额的刷新是**自动的，按用户设定的时间间隔执行，不需要任何身份验证**。分两条路径：

| 场景 | 机制 | 时效保证 |
|------|------|----------|
| 应用在前台 / 刚进入前台 | 应用内计时器按用户设定间隔触发 | **精确**，可按设定间隔执行 |
| 应用在后台 | `BGAppRefreshTask`，向系统**申请**最小间隔 | **不保证**，由系统按设备状态、电量、用户使用习惯调度 |

用户可设置的间隔档位建议：15 分钟 / 1 小时 / 6 小时 / 每天 / 仅手动。另 MUST 提供手动刷新入口
（FR-021）。

余额不足、密钥失效、每周摘要三类本地通知由刷新结果驱动。

### Rationale 与已知局限

- 刷新读取管理类凭证时**不触发**任何身份验证门闩（见 §1）。这是本节与 §1 配套的关键设计：门闩挡的是
  「用户查看/复制凭证」，不是「系统自动读取凭证去调接口」。
- iOS 对后台刷新只接受「最小间隔申请」，**实际调度时机由系统决定**，无法保证。因此：
  - 前台刷新的文案可以说「每 {间隔} 自动刷新」；
  - 后台驱动的通知文案 MUST 表述为「在下次刷新时检查」，MUST NOT 承诺实时（FR-023）。
  - 用户设定「15 分钟」不等于后台真的每 15 分钟跑一次；设置项说明须避免这一误解。

---

## 8. 费用估算口径

### Decision

内置单价规则种子数据（模型匹配、输入/输出单价、生效日、来源）；写入用量记录时**快照所用单价规则的
标识**，历史值不随单价变更而改写（FR-019、宪法第 IX 条）。允许用户覆写单价（FR-021 中的单价规则管理）。

---

## 9. 待解决问题（需在 Phase 1 设计中定案）

- ~~**RQ-001 后台刷新与管理类凭证 ACL 的冲突**~~ → **已定案（2026-08-04）**：全部凭证均不使用系统级
  ACL，门闩统一在应用层且只挡「用户取出凭证」这一动作；自动刷新读取管理类凭证不触发验证。
  见 §1 与 §7。
- **RQ-002 使用方工具预置列表**：对应规范 CL-003，不阻塞架构。
- ~~**CL-004 应用专属主密码**~~ → **已定案（2026-08-04）**：**做**，见 §1.2。
  用 `CommonCrypto` 的 PBKDF2，不同步，仅作门闩的一档而非加密层，且必须提供经设备密码的重置路径。
- ~~**CL-005 应用密码的口令强度要求**~~ → **V1 已定案**：按本机 activation secret 语义保留最短
  4 位、不强制字符混搭，并加入持久化重试限制；NIST SP 800-63B 要求至少 4 位、建议至少 6 位，后续若
  提升为 6 位须作为明确产品迁移，不能让已有 4/5 位用户突然无法验证。
- **RQ-003 `.expirationDate` 连续复制的不稳定行为**：需在真机上以多次连续复制场景实测，确认兜底
  `Timer` 的介入条件。

---

## 变更记录

- 2026-08-04：整体重写。原 research.md 面向「OpenAI 兼容 SSE 流式中转」，与现规范无关，已作废。
  本版核心新增：§1 Keychain 同步与生物识别互斥（阻塞决策）、§2 剪贴板原生过期能力、
  §4 上游平台能力矩阵。
