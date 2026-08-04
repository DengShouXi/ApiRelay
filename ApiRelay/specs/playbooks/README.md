# ApiRelay 分版本实现 Playbook

**权威依据**：[ROADMAP.md](../ROADMAP.md) · **分支台账**：[BRANCHES.md](./BRANCHES.md)

## 分支结构（请按这个理解，不要建成真·文件夹树）

```text
v0（含义：未上架；通常不单独建分支）
├── 分支 v0.0     规划     + tag v0.0.1 / v0.0.2 …
├── 分支 v0.1     产品阶段1 + tag v0.1.1 … v0.1.8   ← 现在在这干
├── 分支 v0.2     产品阶段2（做到再创建）
└── 分支 v0.3     产品阶段3（做到再创建）
    （无 v0.4）
```

- **第 2 层** = Git **分支**（长期工作线，做到该大阶段才创建）  
- **第 3 层** = Git **tag**（小 Phase 检查点，通过后再打）  
- **不要**事先把 `v0.2`/`v0.3`/`v0.4` 全部建空

| 产品 | 工作分支 | Playbook |
|------|----------|----------|
| 规划 | `v0.0` | （已冻，用 tag 回看） |
| V1 密钥库 | `v0.1` | `v1-key-vault/` |
| V2 用量 | `v0.2` | `v2-usage-insights/` |
| V3 中转 | `v0.3` | `v3-relay-service/` |

## 每个大阶段文件夹里

| 文件 | 用途 |
|------|------|
| `00-README.md` | 范围与 Phase 表 |
| `phases/P0N-*.md` | 实现提示词 |
| `05-annotate-branch.md` | 写英+中备注到 BRANCHES.md |
| `15-phase-push.md` | 提交当前大阶段分支 + **打 tag** `v0.Y.N` 并推送 |
| `10-verify.md` / `20-push.md` | 大阶段收尾核对 |
| `30-create-next-branch.md` | **开始**下一大阶段时才创建 `v0.{Y+1}` |
| `40-checkout-next-branch.md` | 切到新大阶段分支 |

## 节奏

```text
在 v0.1 上贴 phases/P0N 实现
  → Checkpoint 通过
  → 05 写备注 → 15 提交并 tag v0.1.N、push
  → 继续下一 Phase（仍在 v0.1）
全部 Phase 完 → 10 verify → 20 → 30 创建 v0.2 → 40 切换
```
