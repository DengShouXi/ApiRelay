# ApiRelay 分版本实现 Playbook

**权威依据**：[ROADMAP.md](../ROADMAP.md) · **分支台账**：[BRANCHES.md](./BRANCHES.md)  
**结论：产品分三个大阶段——对应分支第二位 `1` / `2` / `3`。不要做第四大阶段。**

## Git 分支命名（与 ROADMAP「V1/V2/V3」的关系）

ROADMAP 里的 V1/V2/V3 = 产品大阶段。Git 分支用：

`v{是否上架}.{大阶段}.{小修订}` → 例：`v0.1.3` = 未上架 · 第 1 大阶段 · 第 3 个小检查点（常对齐 Phase 3）

| 产品大阶段 | 分支第二位 | Playbook 目录 | 一句话 |
|------------|------------|---------------|--------|
| 规划/规格 | `0` | （已冻在 `v0.0.1` / `v0.0.2`） | 只写文档，不实现产品阶段代码 |
| **V1 密钥库** | `1` | `v1-key-vault/` | 完全不联网调上游 |
| **V2 用量看板** | `2` | `v2-usage-insights/` | 联网调上游，无自有服务端 |
| **V3 中转** | `3` | `v3-relay-service/` | 用户自己的 Cloudflare Worker |

详情与三分支中英备注见 [BRANCHES.md](./BRANCHES.md)。

**上架时机（DC-013）**：产品 V1 不单独上架，与 V2 一并提交；故发布前分支第一位保持 `0`。

---

## 目录怎么用

```text
specs/playbooks/
├── README.md              ← 本文
├── BRANCHES.md            ← 分支命名规则 + 中英备注台账（必读）
├── v1-key-vault/
├── v2-usage-insights/
└── v3-relay-service/
```

每个大阶段文件夹里有：

| 文件 | 用途 | 何时粘贴给 Cursor |
|------|------|-------------------|
| `00-README.md` | 本阶段范围与 Phase 表 | 开做前先读 |
| `phases/P0N-*.md` | **实现**提示词 | 一次只贴一个 Phase |
| `05-annotate-branch.md` | **写分支备注**（英+中，更新 BRANCHES.md） | 每次准备推里程碑分支前 |
| `15-phase-push.md` | **每个小 Phase 上传**到 `v0.{大阶段}.{N}` | 该 Phase Checkpoint 通过后 |
| `10-verify.md` | 大阶段全量检测 | 全部 Phase 做完后 |
| `20-push.md` | 大阶段收尾上传 / 核对远程 | verify 通过后 |
| `30-create-next-branch.md` | 创建下一里程碑分支 | 需要进入下一 Phase 或下一大阶段时 |
| `40-checkout-next-branch.md` | 切换到新分支 | 新分支创建并推送后 |

---

## 推荐节奏

### 每个小 Phase（例：V1 的 Phase 3 → 分支 `v0.1.3`）

```text
贴 phases/P0N-*.md 实现
  → Checkpoint 通过
  → 贴 05-annotate-branch.md（英+中写入 BRANCHES.md）
  → 贴 15-phase-push.md（提交、建/推 v0.1.N）
```

### 整个大阶段收尾（例：V1 八个 Phase 都完）

```text
贴 10-verify.md
  → 贴 20-push.md
  → 贴 30-create-next-branch.md（切到 v0.2.1）
  → 贴 40-checkout-next-branch.md
```

**硬规则**：前一大阶段未验收通过，MUST NOT 开始下一大阶段实现。
