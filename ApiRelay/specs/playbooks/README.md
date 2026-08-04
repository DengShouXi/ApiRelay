# ApiRelay 分版本实现 Playbook

**权威依据**：[ROADMAP.md](../ROADMAP.md)  
**结论：分三个版本——V1、V2、V3。不要做 V4。**

| 版本 | 分支 | 一句话 | 风险 |
|------|------|--------|------|
| **V1** | `001-key-vault` | 密钥保管与分发（**完全不联网调上游**） | 低 |
| **V2** | `002-usage-insights` | 用量、探活、关系图、加密传递（联网调上游，无自有服务端） | 中 |
| **V3** | `003-relay-service` | 中转服务（用户自己的 Cloudflare Worker；prompt 过中转） | 高 |

**为什么不是 V4？** 全产品用户故事（US1–US10）已全部落在这三阶段；没有第四个独立交付物。若以后出现全新能力，再开 V4，而不是现在预留空文件夹。

**上架时机（DC-013）**：V1 不单独上架，与 V2 一并提交审核。

---

## 目录怎么用

```text
specs/playbooks/
├── README.md                 ← 本文
├── v1-key-vault/             ← 当前：在分支 001-key-vault 上慢慢做
├── v2-usage-insights/        ← V1 合并进 main 后再切到这里
└── v3-relay-service/         ← V2 合并进 main 后再切到这里
```

每个版本文件夹里有：

| 文件 | 用途 | 何时粘贴给 Cursor |
|------|------|-------------------|
| `00-README.md` | 本版本范围、阶段表、依赖 | 开做该版本前先读一遍 |
| `phases/P0N-*.md` | **该阶段的实现提示词** | 一次只贴一个 Phase |
| `10-verify.md` | **检测 / 验收提示词** | 该版本全部 Phase 做完后 |
| `20-push.md` | **上传（push）提示词** | 验收通过后 |
| `30-create-next-branch.md` | **创建下一版本分支提示词** | push 成功后 |
| `40-checkout-next-branch.md` | **切换到新分支提示词** | 新分支创建后 |

---

## 推荐节奏（每个版本）

```text
读 00-README
  → 按序贴 phases/P01 … Pn（每阶段做完再进下一阶段）
  → 贴 10-verify（全量检测）
  → 贴 20-push（上传本版本）
  → 贴 30-create-next-branch（从 main 切下一版本分支）
  → 贴 40-checkout-next-branch（切过去，开始下一版本）
```

**硬规则（ROADMAP）**：前一版本未验收通过，MUST NOT 开始下一版本的实现。

---

## 各版本阶段数量一览

| 版本 | 阶段数 | 来源 |
|------|--------|------|
| V1 | **8** | 已定稿于 `specs/001-key-vault/tasks.md` |
| V2 | **8**（草案） | 按 ROADMAP 范围预拆；正式 `tasks.md` 启动 V2 时用 `/speckit-tasks` 生成后以 tasks 为准 |
| V3 | **7**（草案） | 同上 |

阶段细节见各版本 `00-README.md`。
