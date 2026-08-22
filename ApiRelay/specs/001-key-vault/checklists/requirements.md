# Specification Quality Checklist: 密钥保管、分发与用量统计（阶段一）

**Purpose**: Validate specification completeness and quality before proceeding to planning
**Created**: 2026-08-04
**Feature**: [spec.md](../spec.md)

## Content Quality

- [x] CHK001 No implementation details (languages, frameworks, APIs)
- [x] CHK002 Focused on user value and business needs
- [x] CHK003 Written for non-technical stakeholders
- [x] CHK004 All mandatory sections completed

## Requirement Completeness

- [x] CHK005 No blocking [NEEDS CLARIFICATION] markers remain
- [x] CHK006 Requirements are testable and unambiguous
- [x] CHK007 Success criteria are measurable
- [x] CHK008 Success criteria are technology-agnostic
- [x] CHK009 All acceptance scenarios are defined
- [x] CHK010 Edge cases are identified
- [x] CHK011 Scope is clearly bounded (Out of Scope FR-OUT-001～007)
- [x] CHK012 Dependencies and assumptions identified

## Feature Readiness

- [x] CHK013 All functional requirements have clear acceptance criteria
- [x] CHK014 User scenarios cover primary flows
- [x] CHK015 Feature meets measurable outcomes defined in Success Criteria
- [x] CHK016 No implementation details leak into specification
- [x] CHK017 Out-of-scope items are separated from functional requirements
- [x] CHK018 Deferred stories are explicitly marked and excluded from the paywall

## Notes

**Rewrite (2026-08-04)**: 产品方向发生根本性变更，规范整体重写。

原规范（「密钥管理 + OpenAI 兼容流式中转 + iCloud 同步」）与产品负责人的实际意图不符，已整体作废。
核心差异：

| 项 | 原规范 | 本规范 |
|----|--------|--------|
| 「中转」方向 | App 自己调用上游（App 是消费者） | 阶段一不做中转；产品只保管与分发密钥，不介入流量 |
| App 内聊天窗口 | US2 核心功能 | 明确排除（FR-OUT-001） |
| 一工具一密钥 | 无此概念 | US2 核心；依靠上游平台原生多密钥能力实现 |
| 使用方（消费方）维度 | 无 | US2 / US4 的第二个统计维度 |
| 统计数据来源 | 本地记录自己发起的调用 | 读取各上游平台接口，能力因平台而异 |
| 付费结构 | 订阅式多项能力解锁 | 一次性买断解锁无限密钥（单档） |
| 自建中转 | MVP 内 | 降为 US7（P3 — Deferred），不排期、不进付费墙 |

**跨产物一致性状态（2026-08-04 更新）**：全部产物已重生成，与本规范一致。

| 产物 | 状态 |
|------|------|
| `research.md` | ✅ 已重写（Phase 0）。核心发现：Keychain iCloud 同步与系统级生物识别 ACL 互斥 |
| `data-model.md` | ✅ 已重写（Phase 1） |
| `contracts/module-interfaces.md` | ✅ 已重写（Phase 1） |
| `contracts/platform-adapters.md` | ✅ 新建，替代已删除的 `openai-relay-http.md` |
| `quickstart.md` | ✅ 已重写（Phase 1） |
| `plan.md` | ✅ 已重写，含 Constitution Check |
| `tasks.md` | ✅ 已重写（Phase 2），仅拆解阶段一，87 项任务 |

**宪法依赖**：本规范要求宪法 ≥ v2.0.0（剪贴板条件许可、iCloud 明文同步许可、数据真实性原则）。
宪法已于同日修订至 v2.0.0，无遗留冲突。

**验收口径说明**：CHK005 记为通过是因为剩余待定项均不阻塞架构——`CL-003`（使用方工具预置列表）
在实现阶段定稿；`CL-004`（应用专属主密码）本期明确不做。影响架构的 `CL-001` / `CL-002` 已由产品
负责人裁决为 `DC-001` / `DC-002`，门闩与刷新的分工裁决为 `DC-006`。

**后续修订（2026-08-04 晚）**：依据 `DC-006` 补充 FR-003（三档验证方式）、FR-003a（生物识别类型
由硬件决定，不作为用户选项）、FR-021a（自动刷新不需验证、后台不承诺时效）。同时修正宪法 VIII 的一处
逻辑漏洞——原文允许「复制门闩可关闭而查看门闩不可关闭」，但二者产出同一份明文，分设开关会使查看
门闩可被复制绕过，故合并为单一门闩与单一设置项。

**第三次修订（2026-08-04 深夜）**：产品负责人补充六项要求，全部已回填：

| 变更 | 影响 | 落点 |
|------|------|------|
| **中转的精髓已更正**（DC-010） | 中转价值从「隔离」升级为「上游轮换不动下游配置 + 统计自主」 | US7、ROADMAP V3 |
| **分三阶段实施**（DC-009） | V1 边界收窄为「完全不联网调上游」 | ROADMAP、tasks.md |
| **指派改为多对多**（DC-011） | **数据模型破坏性变更**，新增 `KeyAssignment` 中间表 | data-model §3.3a、FR-007、FR-008a |
| **两类平台都可自定义添加**（DC-012） | 新增术语表；上游平台扩至 8 家预置 | 术语表、FR-007a |
| **关系图**（DC-008） | 新增 US8，形态定为三列桑基图 | US8、FR-039～041 |
| **应用主密码**（DC-007） | 门闩由三档变四档 | FR-036～038、research §1.2 |
| **上架时机**（DC-013） | **已废止**；现行：每阶段独立上架 Stage N→`N.0.0`（DC-009） | ROADMAP、tasks Phase 8、BRANCHES.md |

**多对多引入的新约束（V2 实现时最易踩）**：上游平台只按密钥提供用量，无法拆分同一把密钥在
不同工具间的消耗。因此共享密钥的用量 MUST 单列「共享密钥」小计，**禁止摊分、禁止重复计数**
（FR-008a）。SC-005 的自洽口径已相应修正。

**第四次修订（2026-08-04 深夜二）**：再补四项：

| 变更 | 影响 | 落点 |
|------|------|------|
| **语言范围与全球上架**（DC-014） | 英语 + 简体中文；**开发语言必须为英语**（已核实工程为 `en`）；语义化 key；法律文本禁机翻；加密出口合规声明 | FR-042～046、宪法 v2.1.0「本地化」节、T005a |
| **中转密钥格式**（DC-015） | 自定义前缀 + 系统随机后缀；后缀不可自定义 | US7 |
| **分享分两层**（DC-016） | V2「加密传递」不可撤回；V3「共享」可撤回；不做团队功能 | US9、FR-047～050 |
| 预置工具清单定稿（CL-003） | 10 个预置工具 | FR-007a、T014a |

**本次识别出的一个非 schema 的破坏性风险**：加密文件格式必须自 V1 起就写入 `purpose`
（`fullBackup` / `transfer`）与 `scope` 字段。该格式**不受 `SchemaMigrationPlan` 保护**，
V1 若遗漏，V2 的加密传递将被迫做破坏性格式升级，且已导出的文件会失去用途标识。
已写入 FR-022、T046、data-model §10。

**第五次修订（2026-08-04 深夜三）**：再补九项，全部已回填至 spec / ROADMAP / 宪法 v2.2.0：

| 变更 | 影响 | 落点 |
|------|------|------|
| **密钥可用性检测**（DC-017） | 纳入 V2；仅手动；失效带感叹号；429/断网归「未能确认」；V1 只预留健康度字段 | US10、FR-051～055、ROADMAP V2 专节、data-model `healthState` |
| **工程标识符统一**（DC-018） | `com.dsx.*` → `com.apirelay.*`；含 PrivacyInfo 工程卡点 | FR-058、plan A5、T004 |
| **Swift 6 + iOS 18 / macOS 15**（DC-019） | 写业务代码前切换；上架后不可随意抬版本 | 宪法稳定性节、T002 |
| **Mac Catalyst 不可改**（DC-020） | 原生 macOS 无剪贴板过期机制，迁形态会破坏 FR-005 | research §3 |
| **偏好同步边界**（DC-021） | 安全偏好同步、外观/默认视角仅本机 | FR-060 |
| **用量时区口径**（DC-022） | 字段自 V1 进数据模型 | FR-019a |
| **内购不可逆配置**（DC-023） | 家庭共享、产品 ID、V3 第二档独立非消耗型 | FR-062 |
| **无障碍与明文朗读**（DC-024） | 修正「禁止 VoiceOver 读明文」的错误；门闩才是安全边界 | FR-059、T060 |
| **密钥录入正确性**（DC-025） | 关自动更正/智能标点；弱重复提示且禁明文哈希 | FR-056～057 |

**第七次修订（2026-08-04）**：删除语义对齐系统「密码」App——

| 变更 | 裁决 | 落点 |
|------|------|------|
| **最近删除回收站 30 天**（DC-029） | **推翻**「删除即毁 Keychain」。默认删除=进回收站并保留明文 30 天；可恢复；到期/立即删除才永久清除。清除全部数据仍立即清空。 | FR-006 重写、SC-015、US1 场景 5/5a/5b、data-model `purgeAfter`、T024/T024a/T025 |

**第六次修订（2026-08-04）**：拍板此前三条未决项：

| 变更 | 裁决 | 落点 |
|------|------|------|
| **清除全部数据**（DC-026） | **做，归 V1**。门闩不可关闭 + 二次确认；不碰 StoreKit；同步清除会跨设备 | FR-061、SC-014、US6 场景 6、T048a/b、`DataLifecycleServing` |
| **CloudKit 生产 schema 硬门槛**（DC-027） | **做**。Checkpoint **2a** 后可进 Phase 3；**2b**（Deploy Production）为 TF/1.0.0 同步硬门槛（早期「不得进 Phase 3」误写已废） | FR-063、data-model §7.1、T014b |
| **KeyHealthServing 契约预留**（DC-028） | **V1 预留协议与 DTO，不实现、不进 UI** | contracts §3.1a、T009a、`KeyRecordDTO.health` |

此前第五次修订列出的下游漂移（版本号 / Bundle ID / VoiceOver / PrivacyInfo）已在同轮对齐。

**第八次修订（2026-08-04，`/speckit-analyze` 缺口回填）**：不改需求编号，只对齐不可逆取值与覆盖缺口：

| 缺口 | 处理 |
|------|------|
| iCloud 容器 ID 冲突 | 定稿 `iCloud.com.apirelay.ApiRelay`（plan A5、data-model、T004） |
| tasks 漏 `DevicePreferences` | T012→十实体；T013/T014/T045/T050 |
| `KeychainService` 缺 `masterpw` | contracts + data-model §2 三类 Item |
| `PreferencesDTO` / 核心枚举未定义 | contracts §2 补全 |
| FR-056/057、FR-062 无任务 | T028a、T044a；产品 ID / 家庭共享写入 plan A5 |
| 文案漂移 | plan Summary/Tab、quickstart 四档与 SC-012/013、spec 产品概述阶段边界 |

**结论（截至第十一次修订）**: analyze 文档债已回填。Stage1 代码与 **T014b（2b）** 已关；上架前仍开：
**T063–T066**、**T062**（授权后）。商店材料在 playbook **P13 / `v1.13`**。

**第九次修订（2026-08-05，版本/上架/分支命名对齐）**：

| 变更 | 影响 | 落点 |
|------|------|------|
| **DC-013 废止** | Stage N 独立上架为 App Store **N.0.0**；与 DC-009 一致 | ROADMAP、spec、tasks Phase 8、quickstart §9、V1/V2 P08 |
| **分支命名** | `plan.N` / `v1.N` / `v2.N` / `v3.N`；旧 `v0.Y.N` 仅历史对照 | BRANCHES.md、全量 playbooks save、ApiRelayTests README |
| **发布 tag** | 仅上架打 `release/N.0.0`；小迭代仍用分支 | BRANCHES、constitution v2.3.0、`.cursor/rules/versioning-release.mdc` |

**第十次修订（2026-08-05，`/speckit-analyze` Top6 回填）**：

| 变更 | 影响 | 落点 |
|------|------|------|
| Checkpoint 2 拆 2a/2b | 功能开发可在 2a 继续；T014b 仍为 1.0.0 同步硬门槛 | tasks.md |
| 商店材料任务 T063–T066 | Stage1 上架材料可勾选；T062 收紧为发布动作 | tasks.md、quickstart §9、P08 |
| P07 去掉「V1 不上架」 | 与 DC-013 废止对齐 | P07-Catalyst.md |
| plan Summary 承认 V3 中转 | 消除「最终形态不含中转」漂移 | plan.md |
| plan A5 / Constitution Check 刷新 | 现状表与已完成 tasks 一致 | plan.md |
| SC-003 对齐 FR-005 | 剪贴板清除含进程存活例外 | spec.md |

**第十一次修订（2026-08-11，`/speckit-analyze` 剩余计划回填）**：

| 变更 | 影响 | 落点 |
|------|------|------|
| DC-027 对齐 2a/2b | 废止「未 Deploy 不得进 Phase 3」误写 | spec.md、P02、本清单第六次表 |
| T014b 过时阻塞 | plan / 结论去掉已完成的 2b | plan.md、本清单结论 |
| FR-025 / SC-001 覆盖 | 新增 T028b + quickstart §1.1b | tasks.md、quickstart.md |
| T014b 补记 FR-019a/031 | `periodTimeZone` / `dataSource` 写入核对笔记 | tasks.md、data-model §7.1 称 2b |
| Phase 8 执行序 + P13 分流 | T063–T066→P13；P08 仅 T056–T061 | tasks.md、P08 |
| CL-005 定案 | 主密码最小长度 4、不强制复杂度 | spec.md |
| 「V1 不做」表 | 拆开 FR-055/031 的 V1 预留 vs 实现 | tasks.md |
