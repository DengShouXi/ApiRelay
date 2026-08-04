# ApiRelay 分版本实现 Playbook

**权威依据**：[ROADMAP.md](../ROADMAP.md) · **分支台账**：[BRANCHES.md](./BRANCHES.md)

## 分支结构（命名约定；Git 无真文件夹）

```text
v0（未上架 · 通常不建分支）
├── 分支 v0.0   + tag v0.0.1 / v0.0.2
├── 分支 v0.1   + tag v0.1.1 … v0.1.8   ← 当前
├── 分支 v0.2   + tag v0.2.1 …          （做到再创建）
└── 分支 v0.3   + tag v0.3.1 …          （做到再创建；无 v0.4）
```

| 层 | Git 对象 | 何时创建 |
|----|----------|----------|
| 大阶段 `v0.Y` | **分支** | 开始该大阶段时 |
| 小阶段 `v0.Y.N` | **tag** | 该 Phase Checkpoint 通过后 |

## 每个小 Phase 两份提示词（必须分开复制）

| 文件 | 用途 |
|------|------|
| `phases/P0N-某某.md` | **只实现**（复制给 Cursor） |
| `phases/P0N-save.md` | **只保存/上传**：写 `BRANCHES.md` 英→中备注 + 在大阶段分支 commit + 打对应 tag + push |

`05-annotate-branch.md` / `15-phase-push.md` 是索引表，指向各 `P0N-save.md`。

## 大阶段目录

| 目录 | 工作分支 |
|------|----------|
| `v1-key-vault/` | `v0.1` |
| `v2-usage-insights/` | `v0.2` |
| `v3-relay-service/` | `v0.3` |

另有：`10-verify` / `20-push`（大阶段收尾）/ `30-create-next-branch`（懒创建下一 `v0.Y`）/ `40-checkout-next-branch`。

## 节奏

```text
复制 P0N-实现.md → Checkpoint 通过
  → 复制同目录 P0N-save.md（备注 + tag v0.Y.N + push）
  → 下一 Phase 实现（人仍在 v0.Y）
全部 Phase 完 → 10 → 20 → 30 创建下一分支 → 40
```
