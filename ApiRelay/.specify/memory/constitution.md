<!--
Sync Impact Report（最新：v2.10.0 → v2.11.0）
==========================================
Version change: 2.10.0 → 2.11.0 (MINOR: 降级须落盘成功才改锁态；写入口收口；快照≠计时；认证中不当闲置)

Modified principles / requirements:
  - VIII. 身份确认门闩
      * 降低已同步安全等级 MUST 在 persist 成功后才改内存锁态、启动缓存、界面；失败保持原状。
      * 会话锁住时用户发起的写（使用方 CRUD、回收站恢复/永久删、指派、排序）MUST 在业务入口拒绝；过期清扫 MUST 跳过。
      * 快照遮罩与自动锁计时拆开；同组闲置不得锁/计时/白屏。
      * 系统验证进行中视为验证接管，MUST NOT 当同组闲置去 cancel。

Templates / downstream sync:
  - `specs/001-key-vault/spec.md`（FR-069～FR-072、宪法修订记录）
  - `specs/001-key-vault/contracts/module-interfaces.md`
  - `specs/playbooks/锁-验收矩阵.md`
  - `specs/playbooks/锁-加固计划.md`

Follow-up TODOs: none

历史记录
========
Version change: 2.9.0 → 2.10.0 (MINOR: 安全偏好失败锁住；降低同步安全等级须再认证；会话锁为业务闸)

Modified principles / requirements:
  - V. 故障隔离
      * 安全偏好读取失败 MUST 保持上一次已知锁态，MUST NOT 静默落到默认关锁。
  - VIII. 身份确认门闩
      * 降低已同步的安全等级 MUST 再经不可关闭的设备主人认证。
      * 会话锁住时敏感动作 MUST 在业务入口拒绝；遮罩不得作为唯一闸。
      * 系统验证同一时间只服务一个请求。

Templates / downstream sync:
  - `specs/001-key-vault/spec.md`（FR-065～FR-068、宪法修订记录）
  - `specs/001-key-vault/contracts/module-interfaces.md`
  - `specs/playbooks/锁-验收矩阵.md`

Follow-up TODOs: none

历史记录
========
Version change: 2.8.0 → 2.9.0 (MINOR: VII 剪贴板时长改为可增删列表；澄清 Mac/强制退出清不掉)

Modified principles / requirements:
  - VII. 密钥安全
      * 自动清除出厂预填与默认选中 MUST 含 2 分钟；用户 MUST 能增删改列表（含删掉 2 分钟）。
        废止「可选时长 MUST 永远包含 2 分钟」的固定档读法。
      * 进程仍存活时 MUST 在时限内清除；系统终止、强制退出、崩溃、Mac 无可靠系统过期
        MUST 在设置处如实说明。MUST NOT 为在 Mac 上写 `.expirationDate` 而破坏其他 App 粘贴。

Templates / downstream sync:
  - `specs/001-key-vault/spec.md`（FR-005、FR-021、DC-003、DC-020、SC-003、宪法修订记录）
  - `specs/001-key-vault/plan.md`
  - `specs/001-key-vault/research.md` §2 / §3
  - `specs/001-key-vault/contracts/module-interfaces.md`
  - `specs/001-key-vault/data-model.md`（默认头像遗留字段）
  - `specs/001-key-vault/quickstart.md`、`tasks.md`
  - `specs/ROADMAP.md`

Follow-up TODOs: none

历史记录
========
Version change: 2.7.0 → 2.8.0 (MINOR: 设置列表行 ⓘ 改紧贴标题；未删除 〉 规则)

Modified principles / requirements:
  - Platform Experience Standards → 设置列表行
      * 子页行从左到右改为 `图标　标题　ⓘ　当前值（可空）　〉`。
        ⓘ MUST 紧贴标题右侧，MUST NOT 贴在 〉 旁。
        空间不足时 MUST 截断标题、保留当前值与 〉。
      * 本页控件行仍为 `图标　标题　ⓘ　控件`，并明确 ⓘ 紧贴标题。
      * 〉 仍仅用于 NavigationLink 子页行，点 ⓘ 仍只出示说明。

Templates / downstream sync:
  - `.cursor/rules/settings-row-chrome.mdc`
  - `specs/001-key-vault/plan.md` Constitution Check
  - `specs/001-key-vault/spec.md`（FR-021、宪法修订记录）
  - `specs/playbooks/重要说明/索引.md`

Follow-up TODOs: none

Version change: 2.6.0 → 2.7.0 (MINOR: 剪贴板自动清除改为默认开启、用户可关；关掉时 MUST 披露风险)

Modified principles / requirements:
  - VII. 密钥安全
      * 写入剪贴板的条件从「必须限时清除」改为「默认限时清除，用户可关」。
        关闭后 MUST 在设置处披露其他 App 读取与通用剪贴板同步的风险。
        未删除剪贴板条件许可，也未取消限时清除能力。

Templates / downstream sync:
  - `specs/001-key-vault/spec.md`（FR-005、FR-021、US1 3a、DC-003）
  - `specs/001-key-vault/data-model.md`
  - `specs/001-key-vault/contracts/module-interfaces.md`
  - `specs/001-key-vault/plan.md` Constitution Check

Follow-up TODOs: none

Version change: 2.5.0 → 2.6.0 (MINOR: VII 去重改为本机 Keychain 相等比较，禁止末位片段入同步库与未过门闩界面；无原则删除)

Modified principles / requirements:
  - VII. 密钥安全
      * 去重 MUST 在本机对 Keychain 明文做相等比较，MUST NOT 把末位片段或字符长度写入
        SwiftData / CloudKit / 导出物，也 MUST NOT 在未过门闩的界面展示。
  - 无障碍
      * 列表与详情 MUST NOT 展示或朗读密钥的任何字符片段。

Templates / downstream sync:
  - `.cursor/rules/key-security.mdc`
  - `specs/001-key-vault/spec.md`（FR-002、FR-057、DC-025）
  - `specs/001-key-vault/data-model.md`
  - `specs/001-key-vault/contracts/module-interfaces.md`
  - `specs/001-key-vault/quickstart.md`
  - `specs/001-key-vault/plan.md` Constitution Check

Follow-up TODOs: none

Version change: 2.4.0 → 2.5.0 (MINOR: Platform Experience 新增「界面呈现」，无原则删除或重定义)

Modified principles / requirements:
  - Platform Experience Standards
      * 新增「界面呈现」：设置下一层用导航推入；一次性任务用 sheet/对话框；本页控件不另开界面。

Templates / downstream sync:
  - `.cursor/rules/settings-row-chrome.mdc`
  - `specs/playbooks/重要说明/索引.md`
  - `specs/001-key-vault/plan.md` Constitution Check

Follow-up TODOs: none

Version change: 2.3.0 → 2.4.0 (MINOR: Platform Experience 新增「设置列表行」，无原则删除或重定义)

Modified principles / requirements:
  - Platform Experience Standards
      * 新增「设置列表行」：仅子页行显示 〉；当时顺序为 标题　当前值　ⓘ　〉（现行见 v2.8.0）。

Templates / downstream sync:
  - `.cursor/rules/settings-row-chrome.mdc`（改为指向本条，不再另立准则）
  - `specs/playbooks/重要说明/索引.md`
  - `specs/001-key-vault/plan.md` Constitution Check 增一行

Follow-up TODOs: none

Version change: 2.2.0 → 2.3.0 (MINOR: 开发纪律与发布拓扑对齐，无安全/架构原则删除或重定义)

Modified principles / requirements:
  - Development Discipline
      * 功能分支按 playbooks/BRANCHES（plan.N / v1.N / v2.N / v3.N）命名；
        Stage 上架后合并 main，仅上架时打 tag release/N.0.0。

Templates / downstream sync:
  - ROADMAP、spec DC-013（废止）、playbooks/BRANCHES、`.cursor/rules/versioning-release.mdc`
  - tasks T062–T066、Checkpoint 2a/2b（analyze Top6 回填）

Follow-up TODOs: none

Version change: 2.1.0 → 2.2.0 (MINOR: 新增章节与补充条款)

Modified principles:
  - VII. 密钥安全 — 新增「明文派生物」条款
  - VIII. 身份确认门闩 — 探活不触发门闩
  - IX. 数据真实性 — 未知与否定必须区分
Added sections: 无障碍；不可逆决策
Modified requirements: iOS 18 / macOS 15；Swift 6

Version change: 1.0.0 → 2.0.0 (MAJOR: 原则重新定义)

Modified principles:
  - VII. 密钥安全 (Key Security) — 重新定义
      * 剪贴板：由绝对禁令 (MUST NOT) 改为条件许可（显式操作 + 身份确认 + 限时自动清除 + 风险披露）。
        理由：产品交付密钥的唯一可行通道。在不做中转与系统级 AutoFill 的前提下，剪贴板是 Apple
        平台上把密钥交给外部工具的唯一手段；原禁令使产品主流程无法成立。
      * iCloud 同步：新增允许 Keychain 的 iCloud 同步（明文在用户本人的 Apple 设备间由系统端到端
        加密同步），并要求隐私表述与实际行为一致，不得再声称「明文永不离开本机」。
      * 新增「管理类高权限凭证」条款（Admin / Management Key 保护等级与披露义务）。
  - VIII. 生物识别鉴权 → VIII. 身份确认门闩 (Identity Confirmation Gate) — 重命名并扩展
      * 门闩覆盖范围由「查看或导出明文」扩展到「取出密钥明文、配置或查看管理类高权限凭证」。
      * 「查看明文」与「复制到剪贴板」合并为**同一个门闩**，共用同一个用户设置。
        理由：二者产出同一份明文，对其中之一强制门闩而允许另一个关闭不产生实际安全收益——
        用户关掉复制验证后直接复制即可绕过查看验证。分设两个开关是自相矛盾的。
      * 明确「取出密钥明文」的验证方式可由用户选择（含「不验证」）；「加密导出」与
        「管理类高权限凭证」的门闩 MUST NOT 可关闭。
      * 明确系统自动刷新读取管理类凭证 MUST NOT 触发门闩（后台无法完成生物识别，
        且该行为不属于「用户取出凭证」）。

Added sections:
  - IX. 数据真实性 (Data Honesty) — 新增原则。禁止伪造与掩盖平台能力差异，要求估算标注口径、
    历史数据不被静默改写。

Removed sections: none

Follow-up TODOs: none
-->

# ApiRelay Constitution

## Core Principles

### I. 三层架构解耦 (Three-Layer Architecture Decoupling)

系统 MUST 严格纵向分为三层：界面层 (UI Layer) → 业务层 (Business Layer) → 数据层 (Data Layer)：

- 仅允许上层调用下层接口，MUST NOT 反向依赖或跨层直接读写数据。
- 每层对外暴露协议/接口，隐藏内部实现细节。
- 数据层 MUST NOT 包含任何 UI 框架引用（SwiftUI/UIKit/AppKit）。

**Rationale**: 层间硬约束是架构可维护性的根基。违反此规则将导致代码纠缠、测试困难和重构成本指数增长。

### II. 模块化横向隔离 (Modular Horizontal Isolation)

横向按功能拆分为独立模块：

- 模块间 MUST 仅通过公开的固定接口（protocol/API）通信。
- MUST NOT 直接修改其他模块的内部数据、私有方法或文件。
- 新增功能 MUST 优先创建新模块，不得修改已有模块的对外接口定义。
- 对外接口变更 MUST 遵循语义化版本规则，MAJOR 变更需在 constitution 中记录。

**Rationale**: 接口即契约。隔离模块边界保障独立开发、测试和替换能力。

### III. Apple 原生优先 (Apple Native First)

技术选型 MUST 遵循以下优先级：

- 优先使用 Apple 官方原生框架（SwiftUI, AppKit, UIKit, SwiftData, CloudKit, Keychain 等）。
- 引入第三方 SDK 前 MUST 评估：是否 Apple 原生框架可替代？是否增加不可接受的维护负担？
- MUST NOT 引入仅用于单一便捷功能的重量级第三方依赖。

**Rationale**: 原生框架保障最佳平台体验、最小体积和长期兼容性。

### IV. 跨平台复用与平台适配 (Cross-Platform Reuse with Platform-Specific UI)

代码组织 MUST 遵循：

- 业务层 (Business) 和数据层 (Data) 代码 MUST iPhone/Mac 全端复用，不得包含平台条件编译的 UI 代码。
- 界面层 (UI) 可按平台单独做原生交互适配，允许使用 `#if os(iOS)` / `#if os(macOS)` 条件编译。
- 跨平台共享类型和协议 MUST 放在独立于平台的公共模块。

**Rationale**: 最大化代码复用减少维护负担，同时保障各平台最佳原生体验。

### V. 故障隔离 (Fault Isolation)

单个模块异常 MUST 可被捕获和隔离：

- 模块级错误 MUST NOT 导致应用整体崩溃。
- 业务模块异常 MUST 向 UI 层返回明确的 Error 类型或 Result 类型，不得吞噬错误静默失败。
- 安全偏好读取失败 MUST 保持上一次已知锁态（含本机「曾开锁」缓存），MUST NOT 回落到默认关锁，也 MUST NOT 把失败写成「不验证」。
- 后台任务（网络请求、数据处理）故障 MUST NOT 牵连其他功能模块运行。
- 单个上游平台的接口失败或格式变更 MUST NOT 影响其他平台的功能或产品的本地能力。
- 关键路径（如 API 密钥访问）MUST 有 fallback 策略。

**Rationale**: 用户不应因非关键模块异常而丢失整个应用的功能。上游平台不受我方控制，其变更必须被隔离。

### VI. 向下兼容 (Backward Compatibility)

数据变更 MUST 保证用户升级无缝：

- 数据结构变更（SwiftData Model, UserDefaults, Keychain 等）MUST 做向下兼容处理，不得丢失用户本地数据。
- 新增字段 MUST 设置合理的默认值；废弃字段 MUST 保留解析能力至少一个 MAJOR 版本。
- 调用系统新 API MUST 加版本判断（`@available` / `if #available`），保留最低兼容系统版本声明。

**Rationale**: 用户数据是不可逆资产，升级过程中的数据丢失信任不可恢复。

### VII. 密钥安全 (Key Security)

API 密钥明文与管理类高权限凭证 MUST 受到硬性保护：

- 明文 MUST ONLY 存储于系统 Keychain（`SecItemAdd` / `SecItemCopyMatching`）。
- **允许** 启用 Keychain 的 iCloud 同步（`kSecAttrSynchronizable`），使明文在**同一用户本人的 Apple
  设备之间**由系统端到端加密同步。启用同步后，产品内与上架材料的隐私表述 MUST 与实际行为一致，
  MUST NOT 声称「明文永不离开本机」。
- MUST NOT 将明文写入：SwiftData、CloudKit 业务数据库、UserDefaults、应用文件系统（受口令保护的
  加密导出物除外）、日志、崩溃上报、第三方 SDK 存储、分析事件。
- **剪贴板为条件许可**。仅当以下两条同时满足时，允许将明文写入剪贴板：
  1. 由用户显式操作触发（MUST NOT 自动或后台写入）；
  2. 已按第 VIII 条完成身份确认（当用户开启该选项时）。
  系统 MUST 提供可关闭的自动清除，默认开启。出厂预填与默认选中 MUST 含 2 分钟；用户 MUST 能增删改
  时长列表（含删掉 2 分钟），MUST NOT 把 2 分钟做成不可删的固定档。用户关闭自动清除时，产品 MUST
  在设置处披露风险：其他 App 可能读取剪贴板、内容可能经由通用剪贴板同步到用户的其他设备。
  用户开启自动清除且进程仍存活时，写入内容 MUST 在所选时限内被自动清除。
  产品 MUST 在相关设置处披露剪贴板的固有风险：系统会提示粘贴行为、其他 App 可能读取剪贴板、
  内容可能经由通用剪贴板同步到用户的其他设备。
- 自动清除 MUST NOT 误清用户在此之后复制的其他内容。若因应用被系统终止、强制退出、崩溃，
  或因平台无可靠系统过期（Mac）导致清除无法执行，产品 MUST 在设置处如实说明该局限，MUST NOT
  暗示清除是绝对保证。MUST NOT 为在 Mac 上写入 `.expirationDate` 而破坏其他 App 粘贴。
- **管理类高权限凭证**（可创建密钥、可产生消费、可读取组织级用量的凭证）MUST 受到不低于普通密钥的
  保护，且其配置界面 MUST 明确披露权限范围与风险。
- 明文获取后 MUST 在使用完成后及时清理内存引用（将 `String` 置 nil 或使用 `Data` 的
  `resetBytes(in:)`）。
- 明文 MUST NOT 在界面层（View/ViewModel）长期持有或作为 `@Published` 属性持久化；交付路径中的
  临时持有 MUST NOT 超过单次操作生命周期。
- **明文派生物**（哈希、指纹、校验和、任何由明文单向计算得到的值）MUST NOT 写入 CloudKit、
  SwiftData 或导出物。密钥的末位片段、字符长度亦 MUST NOT 写入上述位置或出现在未过门闩的界面。
  需要比对或去重时，MUST 在本机对 Keychain 已有明文做相等比较（该读取 MUST NOT 触发门闩，
  因明文未交给用户），MUST NOT 存储全量哈希或任何足以缩小暴力搜索空间的派生物。

**Rationale**: 密钥泄露是不可逆安全事故，Keychain 是 Apple 平台唯一经系统级加密保护的存储方案。
但绝对禁令若使产品主流程无法成立，就会被实现阶段以更差的方式绕过。剪贴板与 iCloud 同步改为
「带强制约束的许可」，比「禁止但实际违反」更安全，也更诚实。

### VIII. 身份确认门闩 (Identity Confirmation Gate)

门闩挡的是「**用户取出凭证明文**」这一动作，而非系统内部的读取行为。

以下操作 MUST 经过门闩：**取出密钥明文**（查看明文与复制到剪贴板共用同一门闩）、执行加密导出、
查看或配置管理类高权限凭证。

- 使用 `LAContext` (LocalAuthentication) 调用 Face ID / Touch ID 验证用户身份。
- 鉴权结果 MUST NOT 被缓存复用超过单次操作生命周期。
- 鉴权失败时 MUST 提供降级方案（设备密码），不得完全锁死用户访问。
- 「取出密钥明文」的门闩，其**验证方式**MAY 由用户在设置中选择，包含「不验证」。
- 「加密导出」与「查看或配置管理类高权限凭证」的门闩 MUST NOT 可被用户关闭。
- 系统按间隔自动刷新用量或余额时读取管理类凭证，**MUST NOT** 触发门闩——该行为不是用户取出凭证，
  且后台无法完成生物识别。
- 系统为**判定凭证是否仍然有效**而向上游发起探测（探活）时读取密钥明文，**MUST NOT** 触发门闩——
  同上，明文没有被交给用户，且批量探活若逐次弹出生物识别会使该功能不可用。
- 上述两类例外的读取路径 MUST 以**显式命名**体现（如 `readCredentialForAutomatedRefresh`、
  `readSecretForHealthProbe`），使后续维护者不会误加门闩而破坏功能。
- 降低已同步的安全等级（关闭 App 锁、改为更弱的验证方式、关闭多任务隐藏、关闭剪贴板自动清除、
  拉长自动锁）MUST 先完成不可关闭的设备主人认证。加强安全 MUST 立即生效。
  降低等级 MUST 在同步偏好 persist **成功后**才改内存锁态、启动缓存与界面；失败 MUST 保持原状
  （含会话仍锁、缓存仍为开）。加强仍可先改内存。
- 会话锁住时，取出明文、复制、新建、编辑、删除、导入导出、打开设置、使用方 CRUD、回收站恢复
  与永久删除、指派、排序 MUST 在业务或命令入口拒绝。界面遮罩 MUST NOT 作为唯一拦截。
  过期回收站清扫若会话锁住 MUST 跳过本轮，MUST NOT 弹门闩。
- 快照遮罩与自动锁计时 MUST 拆开。台前同组闲置 MUST NOT 上锁、MUST NOT 开始计时、MUST NOT 留下
  白色锁屏；确认离屏才计时或立即锁。
- 系统身份验证同一时间 MUST 只服务一个请求；新请求 MUST 取消未完成的旧请求；真正离开 App 时
  MUST 取消全部未完成请求。系统验证进行中视为验证接管，MUST NOT 当同组闲置去 cancel。

**Rationale**: 即使设备已解锁，取出凭证仍需二次身份确认，防范未授权物理访问。
「查看明文」与「复制」产出的是**同一份明文**，对其中之一强制门闩而允许另一个关闭不产生任何实际
安全收益，只会造成设置项自相矛盾（用户关掉复制验证后，直接复制即可绕过查看验证），故二者合并为
一个门闩、共用一个用户设置。加密导出与管理类凭证的风险等级更高（前者产出可离线暴力破解的文件，
后者可创建密钥并产生消费），不提供关闭选项。

### IX. 数据真实性 (Data Honesty)

向用户呈现的数据 MUST 真实且可追溯：

- MUST NOT 伪造、猜测或以占位值填充无法获得的数据。不可用的数据 MUST 被显式标记为不可用。
- 当上游平台不提供某个维度的数据时，MUST 明确告知该平台的能力限制；MUST NOT 留空、显示为零或
  呈现为功能故障。
- 估算值 MUST 与权威值区分呈现，并 MUST 标注估算口径（所依据的规则及其生效时间）。
- 已向用户展示过的历史数据 MUST NOT 因口径或规则变更而被静默改写。
- **「未知」与「否定」MUST 区分呈现。** 尚未检测、无法判定（限流、网络失败、平台未接入该能力）
  MUST NOT 被呈现为否定结论。具体地：MUST NOT 给从未检测过的对象加失效标记；MUST NOT 把
  「本次无法确证」记为「已失效」。无法判定时 MUST 保留上一次的结论及其时间戳。
- **一项检查通过 MUST NOT 被表述为超出该检查范围的结论。** 例如凭证探测返回成功只能表述为
  「凭证有效」，MUST NOT 表述为「可用」——余额、配额、模型权限均未被检查。

**Rationale**: 本产品的数据真相源在各上游平台，且各平台能力参差不齐。把差异如实呈现是产品的核心
义务——掩盖差异会让用户把平台限制误判为产品缺陷，伪造数字则会让用户基于错误信息做成本决策。

## Platform Experience Standards

交互与视觉 MUST 遵循 Apple 系统设计规范：

- iOS 端遵循 iOS Human Interface Guidelines；macOS 端遵循 macOS Human Interface Guidelines。
- 导航模式、手势、动画 MUST 匹配对应平台的系统原生行为。
- 字体、颜色、间距 MUST 优先使用系统动态值（`Font.TextStyle`, `Color.accentColor`），支持
  Dynamic Type 和 Dark Mode。
- 第三方 UI 库引入 MUST 通过上述 Apple Native First 原则的评估。

### 设置列表行 (Settings List Rows)

设置列表 MUST 用分组卡片；每一行的行尾只表达一种动作，不得混用。

- **只有**会推进去另一整页（`NavigationLink`）的行 MUST 显示披露指示符 〉。此类行 MUST 复用
  `settingsDisclosureRow`，MUST NOT 手写一条能进子页却不画 〉 的行。
- 本页即可完成的控件（菜单、开关、步进器）、点一下即执行的操作、以及弹层（非推入导航）
  MUST NOT 显示 〉。
- 子页行从左到右 MUST 为：`图标　标题　ⓘ　当前值（可空）　〉`。〉 MUST 在最右。ⓘ MUST 紧贴
  标题右侧，MUST NOT 贴在 〉 旁；点 ⓘ MUST 只出示说明，MUST NOT 进入下一页。当前值（若有）
  MUST 靠右、位于 〉 左侧；空间不足时 MUST 截断标题，MUST 保留当前值与 〉。
- 本页控件行从左到右 MUST 为：`图标　标题　ⓘ　控件`。ⓘ MUST 紧贴标题右侧；控件在最右，无 〉。

**Rationale**: 同一设置页里「有的子页有 〉、有的没有」会让用户无法预判点按结果。与系统设置对齐：
〉 只表示还能进去；ⓘ 解释「这一项是什么」，不是导航。

### 界面呈现 (Presentation)

打开下一级内容 MUST 按任务类型选择呈现方式，MUST NOT 为了视觉「看起来都一样」而只用一种。

- **设置层级的下一页**（选项列表、表单、用户还要返回继续改设置）MUST 用导航推入
  （`NavigationLink` / 导航栈）。此类行 MUST 显示 〉；关闭用系统「返回」，MUST NOT 用「取消」关掉整页设置。
- **一次性任务**（购买、危险操作确认、系统文件选取）MUST 盖在当前界面上（sheet、
  `confirmationDialog`、系统面板）。此类行 MUST NOT 显示 〉。关掉后 MUST 回到原来的设置页，
  MUST NOT 把设置页从导航栈清掉。
- **本页即可完成**（菜单、开关、步进器）MUST NOT 打开新界面。
- 设置子页在 iPhone 与 Mac 上 MUST 使用与设置首页相同的分组底与卡片；MUST NOT 在 Mac Catalyst 上
  用会漂在白底中间的裸 `Form` / `List` 充当设置子页。
- 一次性任务的 sheet 在 iPhone 与 Mac 上 MUST 是系统 sheet，并有明确关闭入口；MUST NOT 改成推入
  导航来「对齐」子页。

**Rationale**: 〉 表示还能进入一层设置；盖层表示做完就关。呈现方式与行尾信号必须一致，
不能把付费墙推进设置层级，也不能把备份表单改成盖在设置上的多层 sheet。

### 本地化 (Localization)

产品面向全球上架，界面语言为**英语与简体中文两种**。

- **开发语言（development language）MUST 为英语。** App Store 与系统在用户语言未被覆盖时会回退到
  开发语言——若开发语言为中文，非中文用户会看到中文界面。
- 界面字符串 MUST 使用 **String Catalog（`.xcstrings`）** 管理，MUST 使用**语义化 key**
  （如 `vault.reveal.button`）而非以英文原文作 key。原因：以原文作 key 时，修改英文文案等于更换
  key，会静默丢失已有的中文翻译；产品处于持续迭代期，这个代价不可接受。
- MUST NOT 在代码中硬编码任何面向用户的字符串。
- 日期、数字、货币 MUST 使用 `FormatStyle` 按用户 `Locale` 格式化，MUST NOT 手工拼接。
- Apple 专有名词 MUST 使用 Apple 官方译名（Face ID → 「面容 ID」，Touch ID → 「触控 ID」，
  Keychain → 「钥匙串」），MUST NOT 自行翻译。
- 布局 MUST 容忍两种语言的长度差异（英文通常更长），MUST NOT 依赖固定宽度容纳文案。
- **隐私政策与法律文本 MUST 由人工提供英语与简体中文两个版本**，MUST NOT 使用机器翻译——
  法律文本的机翻错误会直接构成合规风险。

**Rationale**: 只维护两种语言可控且质量可保证；把英语设为开发语言是全球上架的正确回退策略；
语义化 key 是为了让文案迭代不破坏既有翻译，与项目「避免返工」的核心诉求一致。

### 无障碍 (Accessibility)

- 全部界面 MUST 支持 Dynamic Type，MUST NOT 使用固定字号或固定高度容纳文本。
- 全部可交互元素 MUST 有 VoiceOver 标签；仅靠颜色传达的状态（如失效标记）MUST 同时有文字或形状区分。
- **密钥明文的朗读规则**（本条修正了一处方向性错误）：
  - 列表与详情 MUST NOT 展示或朗读密钥的任何字符片段（含末四位）。
  - 通过门闩后的**明文展示区** MAY 被 VoiceOver 读出，且 MUST 提供**逐字符朗读**
    （密钥是随机字符串，连读无法辨识）。
  - MUST NOT 一概禁止 VoiceOver 读出明文——那会使视障用户完全无法使用本产品。

**Rationale**: 无障碍是事后极难补的一类工作，且「不让 VoiceOver 读明文」这种看似安全的规则
实际上是把一类用户排除在外。安全边界应落在**门闩**上，而不是落在辅助功能上。

## Stability & Compatibility Requirements

应用稳定性 MUST 通过以下保障：

- 最低系统版本：**iOS 18.0 / macOS 15.0**（声明在 Xcode 项目部署目标中）。
- **Swift 语言模式 MUST 为 Swift 6**（`SWIFT_VERSION = 6.0`），并保持
  `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`。理由：本项目大量跨 actor 传递
  （Keychain 与各平台适配器是 `actor`，界面在 `MainActor`），若先以 Swift 5 模式写完再迁移，
  严格并发检查会一次性产生大量 `Sendable` 错误；语言模式属**越晚切换代价越高**的决策。
- 所有异步操作 MUST 使用 Swift Concurrency（`async/await`）或 Combine，不得使用 GCD 裸调。
- 网络请求 MUST 设置超时并处理可达性变化（`NWPathMonitor`）。
- 崩溃上报 MUST 集成（不在此项目范围，但架构预留 hook 点）。

## Security Requirements

安全底线 MUST 零妥协：

- 不得在 Git 提交中包含任何密钥、证书、Token。
- `.gitignore` MUST 排除 `.env`、`*.xcconfig`（如含敏感信息）、`GoogleService-Info.plist` 等价文件。
- HTTPS ONLY — 所有网络通信 MUST 使用 TLS 1.2+，不得降级到 HTTP。
- Certificate Pinning 建议但非初始版本强制。

## Development Discipline

开发过程 MUST 遵守：

- 单功能开发完成即提交 Git 存档，提交信息 MUST 清晰描述变更模块和原因。格式：
  `<type>(<scope>): <description>`（如 `feat(vault): add clipboard auto-clear`）。
- 单次提交 MUST 仅改动对应模块，不得跨模块大范围无关修改。
- 每次提交前 MUST 确认项目编译通过（`xcodebuild` 或 Xcode Build）。
- 功能分支按 [playbooks/BRANCHES.md](../../specs/playbooks/BRANCHES.md) 命名（`plan.N` / `v1.N` / `v2.N` / `v3.N`）。
  Stage 上架后 MUST 合并进 `main`，并仅在上架时打 tag `release/N.0.0`。
  新小迭代 SHOULD 从对应大阶段 tip（`plan` / `v1` / `v2` / `v3`）或已更新的 `main` 拉出；合并前 MUST 确保目标 tip 最新无冲突。

## Governance

本宪法是 ApiRelay 项目的最高开发准则，所有设计决策、代码审查和架构变更 MUST 以本文为准：

- 任何原则变更 MUST 经版本号递增（MAJOR/MINOR/PATCH 遵循语义化版本）并在 Sync Impact Report 中记录。
- MAJOR 变更（原则删除或重新定义）MUST 以独立分支提交，并在合并前经过评审。
- 所有代码审查 MUST 验证是否符合本宪法规定，发现违规 MUST 在合入前修正。
- 如需豁免某条原则（如紧急修复不可抗力），MUST 在提交信息中明确标注豁免理由和失效期限。

### 不可逆决策 (Irreversible Decisions)

以下决策一旦生效便**无法回退，或回退代价为用户数据丢失**。它们 MUST 在写第一行业务代码之前定稿，
且 MUST 在 `specs/001-key-vault/plan.md` 中登记确切取值：

| 类别 | 一旦生效后的后果 |
|------|------------------|
| Bundle Identifier | 上架后更改等于换一个 App，已有用户无法升级 |
| Development Team ID | 变更会改变 `$(AppIdentifierPrefix)`，**已存的全部 Keychain 条目读不出来** |
| `keychain-access-groups` | 有用户数据后更改，已存明文全部读不出来 |
| App Group 标识符 | 全 Apple 生态唯一，注册后不可改名；被他人占用时只能换名 |
| iCloud 容器标识符 | 同上；更改等于换一个空数据库 |
| CloudKit 生产环境 schema | 字段**不可删除**、类型**不可更改**；`@Model` 类名即 record type 名，不可改 |
| `ModelConfiguration` 名称与 store 路径 | 更改等于新建空库，旧数据不迁移 |
| 内购产品 ID | 创建后不可删除、不可复用 |
| 内购的家庭共享开关 | **一旦开启不可关闭** |
| 最低系统版本（上架后） | 抬高版本会把已有用户挡在升级之外 |

对上表任一项的变更 MUST 按 MAJOR 处理：独立分支、评审、并在本文件记录。

**Rationale**: 这些不是「以后再优化」的选项，而是只有一次机会的选择。把它们集中登记，是为了避免
它们被当成普通工程配置在实现阶段随手决定。

**Version**: 2.11.0 | **Ratified**: 2026-08-04 | **Last Amended**: 2026-09-10

<!--
v2.11.0（MINOR，降级事务 + 写入口收口 + 快照≠计时 + 认证中态）：
  - VIII：降低已同步安全等级须 persist 成功才改内存锁态；使用方/回收站/指派/排序过闸；
    过期清扫锁下跳过；快照与计时拆开；验证进行中不得当闲置 cancel。
  - Sync Impact：spec FR-069～072、module-interfaces、playbooks/锁-验收矩阵.md、锁-加固计划.md。

v2.10.0（MINOR，锁失败安全 + 设置降级再认证 + 业务闸）：
  - V：安全偏好读失败保持已知锁态，不得落到默认关锁。
  - VIII：降低已同步安全等级须再认证；会话锁在业务入口生效；系统验证单通道。
  - Sync Impact：spec FR-065～068、module-interfaces、playbooks/锁-验收矩阵.md。

v2.9.0（MINOR，剪贴板时长列表 + Mac 清除上限）：
  - VII：出厂默认 2 分钟，列表可增删（含删掉 2 分钟）；进程存活才保证按时清。
    Mac / 强制退出 / 崩溃 MUST 披露，MUST NOT 为凑系统过期破坏粘贴。
  - Sync Impact：spec FR-005/021/DC-003/DC-020、plan、research、contracts、data-model、
    quickstart、tasks、ROADMAP、`.cursor/rules/key-security.mdc`（每次对话加载，不得再写「必须限时」）。

v2.8.0（MINOR，设置列表行 ⓘ 紧贴标题）：
  - 子页行顺序改为 `标题　ⓘ　当前值　〉`；ⓘ 解释项名，不贴在 〉 旁。
  - 〉 规则未改：仅 NavigationLink 子页显示；点 ⓘ 仍只出示说明。
  - Sync Impact：settings-row-chrome.mdc、plan.md Constitution Check、spec.md FR-021、playbooks 中文索引。

v2.7.0（MINOR，剪贴板自动清除可关）：
  - VII：写入剪贴板仍须显式操作与门闩；自动清除改为默认开启、用户可关，关掉时 MUST 披露风险。
  - Sync Impact：spec FR-005/FR-021、data-model、module-interfaces、plan.md。

v2.6.0（MINOR，密钥列表不展示片段）：
  - VII：去重改为本机 Keychain 相等比较；禁止末位片段 / 长度写入同步库或未过门闩界面。
  - 无障碍：列表与详情不展示、不朗读任何密钥字符片段。
  - 无既有原则被删除或重定义，故为 MINOR。
  - Sync Impact：key-security.mdc、spec FR-002/FR-057、data-model、module-interfaces、quickstart、plan.md。

v2.5.0（MINOR，界面呈现）：
  - Platform Experience Standards 下新增「界面呈现 (Presentation)」。
    设置下一层推入；一次性任务 sheet/对话框；本页控件不另开界面。
  - 无既有原则被删除或重定义，故为 MINOR。
  - Sync Impact：settings-row-chrome.mdc、playbooks 中文索引、plan.md Constitution Check。

v2.4.0（MINOR，设置列表行）：
  - Platform Experience Standards 下新增「设置列表行 (Settings List Rows)」。
    仅 NavigationLink 子页显示 〉；当时顺序 标题　当前值　ⓘ　〉（现行见 v2.8.0）。
  - 无既有原则被删除或重定义，故为 MINOR。
  - Sync Impact：`.cursor/rules/settings-row-chrome.mdc` 改为指向本条；
    playbooks 中文索引、`specs/001-key-vault/plan.md` Constitution Check 已同步。

v2.3.0（MINOR，开发纪律与发布拓扑对齐）：
  - Development Discipline：功能分支命名与 `main` / `release/N.0.0` 对齐
    playbooks（Stage N → App Store N.0.0；废止 DC-013 捆发）。
  - 无安全/架构原则删除或重定义，故为 MINOR。
  - Sync Impact：ROADMAP、spec DC-013、playbooks/BRANCHES、`.cursor/rules/versioning-release.mdc`
    已同步；模板无强制改动。

v2.2.0（MINOR，新增章节与补充条款）：
  - Platform Experience Standards 下新增「无障碍 (Accessibility)」小节，
    并修正「MUST NOT 让 VoiceOver 读出明文」这一会排除视障用户的错误规则。
  - Governance 下新增「不可逆决策 (Irreversible Decisions)」小节。
  - Stability：最低版本提升为 iOS 18.0 / macOS 15.0；新增 Swift 6 语言模式要求。
  - VII 新增「明文派生物不得进入同步存储」；VIII 新增「探活不触发门闩」；
    IX 新增「未知与否定必须区分」与「检查通过不得外推结论」。
  - 无既有原则被删除或重新定义，故为 MINOR。

v2.1.0（MINOR，新增章节）：
  - Platform Experience Standards 下新增「本地化 (Localization)」小节。
    英语为开发语言、String Catalog + 语义化 key、Apple 官方译名、法律文本禁用机翻。
  - 无既有原则被删除或重定义，故为 MINOR。
  - 模板一致性：plan-template 的 Constitution Check 需增加「本地化」一行。
-->

