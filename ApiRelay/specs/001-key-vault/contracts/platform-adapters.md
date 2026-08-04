# 上游平台适配契约

**Feature**: 密钥保管、分发与用量统计（阶段一）
**Date**: 2026-08-04
**依据**: [research.md](../research.md) §4 · [module-interfaces.md](./module-interfaces.md) §4

> 每个平台一个 `PlatformAdapting` 实现（`actor`）。**不支持的能力 MUST 抛
> `capabilityUnsupported`，MUST NOT 返回空数据或零值**（宪法 IX）。
> 所有请求 HTTPS only，MUST 设置超时（宪法 Security / Stability）。

---

## 能力总表

| 平台 | issueKeyInApp | revokeKeyInApp | perKeyUsage | accountBalance | spendLimitPerKey | 凭证类型 |
|------|:---:|:---:|:---:|:---:|:---:|----------|
| `openrouter` | ✅ | ✅ | ✅ | ✅ | ✅ | Management Key |
| `openai` | ❌ | ❌ | ✅ | ❌ | ❌ | Admin Key |
| `anthropic` | ❌ | ❌ | ✅ | ❌ | ❌ | Admin Key |
| `deepseek` | ❌ | ❌ | ❌ | ✅ | ❌ | 任一普通 Key |
| `custom` | ❌ | ❌ | ❌ | ❌ | ❌ | — |

---

## 1. OpenRouter

**Base**: `https://openrouter.ai/api/v1`
**Auth**: `Authorization: Bearer <Management Key>`
**凭证获取路径**：OpenRouter 后台的 Management API Keys 页面（与普通调用密钥不同，须在 UI 中说明）。

### 1.1 列出密钥（含用量）— `perKeyUsage` + `revokeKeyInApp` 的数据来源

```http
GET /keys?include_disabled=true&offset=0
```

响应 `data[]` 每项关键字段：

| 字段 | 映射到 |
|------|--------|
| `hash` | `APIKeyRecord.providerKeyRef` |
| `name` | 平台侧名称（用于与本地 `displayName` 对照） |
| `label` | 掩码片段 → `maskedHint` |
| `disabled` | `true` → `lifecycle = .revokedUpstream` |
| `limit` / `limit_remaining` / `limit_reset` | `spendLimit` 与余额展示 |
| `usage` / `usage_daily` / `usage_weekly` / `usage_monthly` | `UsageSnapshot.reportedCostUSD`，粒度 `total`/`day`/`week`/`month` |
| `created_at` / `updated_at` / `expires_at` | 元信息 |

**要点**

- `usage*` 字段单位是 **USD 金额**，不是 token 数。故映射到 `reportedCostUSD`，
  `inputTokens`/`outputTokens` 保持 **nil**（平台不提供 token 拆分），MUST NOT 填 0。
- `byok_usage*` 是自带上游密钥的外部消费，与 `usage*` 分开统计。本期**不合并**二者，
  若非零则在 UI 单独标注，避免口径混淆。
- 分页用 `offset`；MUST 循环取完，否则密钥多时会静默丢失条目。
- 本机不存在对应 `APIKeyRecord` 的远端密钥 → 视为**平台侧新增**，提示用户可导入（不自动导入，
  因为明文无法取回，导入后 `secretAvailable = false`）。

### 1.2 创建密钥 — `issueKeyInApp`

```http
POST /keys
{ "name": "VS Code", "limit": 10 }
```

**响应中的 `key` 字段是明文，且仅此一次返回，事后无法取回。**

实现顺序 MUST 为：① 调用创建 → ② 立即写 Keychain → ③ 写 `APIKeyRecord`。
若 ② 或 ③ 失败，MUST 抛 `createdUpstreamButLocalSaveFailed(providerKeyRef: hash, platform: "openrouter")`，
**MUST NOT 调用删除接口回滚**（可能误删同名密钥），并 MUST 向用户展示不可忽略的指引（FR-010）。

### 1.3 禁用/删除密钥 — `revokeKeyInApp`

```http
DELETE /keys/{hash}
```

成功后置 `lifecycle = .revokedUpstream`（或按用户意图软删除），并删除本机 Keychain 条目。

---

## 2. OpenAI

**Base**: `https://api.openai.com/v1`
**Auth**: `Authorization: Bearer <Admin Key>`
**约束**：Admin Key **不能**用于普通推理端点；反之普通密钥**不能**调用本节接口。UI 须明确区分。

### 2.1 按密钥用量 — `perKeyUsage`

```http
GET /organization/usage/completions
    ?start_time=<unix>&bucket_width=1d&group_by[]=api_key_id&limit=<n>
```

响应 `data[]` 为时间桶，桶内 `results[]` 每项：`api_key_id`、`input_tokens`、`output_tokens`、
`input_cached_tokens`、`num_model_requests`、`model`（当 group_by 含 model 时）。

**要点**

- 返回的是 **token 数，不含费用**。`reportedCostUSD` 保持 nil，
  `estimatedCostUSD` 由 `PricingRule` 计算并标注口径（FR-015、`CapabilityNote.costNotProvidedByPlatform`）。
- `api_key_id` 是平台内部标识（形如 `key_...`），须与 `APIKeyRecord.providerKeyRef` 对应。
  **用户在官网创建密钥时无法直接看到该 id**，故录入密钥后首次刷新 MUST 提供
  「把远端 api_key_id 关联到本地密钥」的匹配流程（候选依据：平台侧密钥名称）。未关联的用量
  MUST 归入「未关联的用量」而非丢弃（宪法 IX）。
- 不设 `group_by` 时多数字段返回 null，故 `group_by[]=api_key_id` 为必传。
- 分页用响应中的 `next_page` 游标，MUST 取完。

### 2.2 不支持的能力

- **无账户余额接口** → `accountBalance` 抛 `capabilityUnsupported`。
- **本期不做 App 内签发密钥** → `issueKeyInApp` / `revokeKeyInApp` 抛 `capabilityUnsupported`，
  UI 提供跳转官网入口（FR-011）。

---

## 3. Anthropic（Claude）

**Base**: `https://api.anthropic.com/v1`
**Auth**: `x-api-key: <Admin Key>` + `anthropic-version: 2023-06-01`

### 3.1 按密钥用量 — `perKeyUsage`

```http
GET /organizations/usage_report/messages
    ?starting_at=<RFC3339>&ending_at=<RFC3339>&group_by[]=api_key_id&bucket_width=1d
```

`results[]` 每项：`api_key_id`、`uncached_input_tokens`、`cache_read_input_tokens`、
`cache_creation{ephemeral_5m_input_tokens, ephemeral_1h_input_tokens}`、`output_tokens`、
`model`、`workspace_id`、`service_tier`、`context_window`。

### 3.2 费用无法按密钥获取（重要限制）

`GET /organizations/cost_report` 的 `group_by` **仅支持** `workspace_id` 与 `description`，
**不支持** `api_key_id`。因此按密钥的费用只能由本产品估算。

**Token 类型口径**：Claude 有四类输入 token（未缓存输入、缓存读取、5 分钟缓存写入、1 小时缓存写入），
单价各不相同。本期估算口径 MUST 明确：

- 计入 `uncached_input_tokens` 与 `output_tokens`，按 `PricingRule` 常规单价计算；
- 缓存类 token **单独展示数量**但**不计入费用估算**，并标注「缓存部分未计入估算」；
- MUST NOT 把缓存 token 按常规输入单价计算（会显著高估），也 MUST NOT 静默忽略其存在。

### 3.3 密钥名称映射

`GET /organizations/api_keys` 可列出密钥及其 id 与名称，用于把 `api_key_id` 映射为可读名称，
辅助 §2.1 所述的关联流程。

### 3.4 不支持的能力

无账户余额接口；本期不做 App 内签发/作废 → 均抛 `capabilityUnsupported`。

---

## 4. DeepSeek

**Base**: `https://api.deepseek.com`
**Auth**: `Authorization: Bearer <任一该账号下的普通 API Key>`

### 4.1 账户余额 — `accountBalance`

```http
GET /user/balance
```

响应：`is_available`（余额是否足够调用）、`balance_infos[]`（`currency`、`total_balance`、
`granted_balance`、`topped_up_balance`）。

**要点**

- 余额是**账户级**的，与用哪把密钥查询无关。适配器 MUST 从该 `UpstreamAccount` 下任一
  `lifecycle == .active` 且本机有明文的密钥中取一把用于查询；若一把都取不到，
  抛 `secretMissingOnDevice` 并在 UI 说明原因。
- 该查询**不需要**管理类凭证——这是 DeepSeek 与其他三家的显著差异，UI 文案须区分。
- 映射到 `BalanceSnapshot`，`accountId` 为键。

### 4.2 按密钥用量：不支持

DeepSeek **没有官方的按密钥用量接口**。

- `perKeyUsage` MUST 抛 `capabilityUnsupported`；
- 该平台下每把密钥的用量位置 MUST 显示 `CapabilityNote.perKeyUsageUnsupported`
  对应的说明文案，**MUST NOT 留空或显示 0**（FR-016、宪法 IX）；
- 社区流传的 `/v1/usage` **不在官方文档中**，权限与稳定性不可靠，**MUST NOT 调用**；
- 官网后台的 CSV/ZIP 导出需浏览器登录态，属 `FR-OUT-006` 明确排除范围，**MUST NOT 实现**。

---

## 5. 通用约定

### 5.1 错误映射

| HTTP / 情况 | 映射 |
|-------------|------|
| 401 / 403 | `upstreamRejected(status:message:)`，UI 提示「凭证无效或权限不足」 |
| 404（密钥不存在） | 置 `lifecycle = .revokedUpstream`（FR-020） |
| 429 | `upstreamRejected`，MUST 退避重试，MUST NOT 无限重试 |
| 5xx | `upstreamRejected`，保留上次数据（FR-017） |
| 无网络 | `networkUnavailable` |
| JSON 结构不符预期 | `upstreamResponseUnparsable(detail:)`，**该平台降级为「暂不可用」，不影响其他平台**（FR-018、宪法 V） |

### 5.2 隔离要求

单平台适配器的异常 MUST 被 `UsageServing.refresh` 捕获并转为该账号的 `RefreshOutcome.failed`，
MUST NOT 向上抛出导致整次刷新失败（宪法 V）。

### 5.3 新增平台

新增平台 = 新增一个 `PlatformAdapting` 实现 + 在能力矩阵登记，**不得修改既有适配器或上层协议**
（宪法 II）。
