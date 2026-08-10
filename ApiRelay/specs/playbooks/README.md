# ApiRelay 实现 Playbook

**迭代规则**：[BRANCHES.md](./BRANCHES.md)  
**上架**：[ROADMAP.md](../ROADMAP.md)（Stage N → App Store `N.0.0`）  
**中文入口**：[重要说明/索引.md](./重要说明/索引.md)

## 唯一记法

`plan.N`（规划）· `v{阶段}.{小迭代}`（产品）—— **开发里程碑全是分支**；商店发布才打 `release/N.0.0` tag。

**每个小阶段写完 → 必须用对应 `P0N-save.md` 打分支并上传**（规划 `plan.3` 也一样）。

**禁止**再新建旧名 `v0.0.N` / `v0.1.N` / `v0.2.N` / `v0.3.N`（现行名见上表）。

## 目录

| 目录 | 大阶段 tip | 小迭代例子 |
|------|------------|------------|
| [`v0-planning/`](./v0-planning/) | `plan` | `plan.1` … `plan.3` … |
| [`v1-key-vault/`](./v1-key-vault/) | `v1` | `v1.1` … `v1.13`（材料）→ `10-verify` → `12-release-T062` … |
| [`v2-usage-insights/`](./v2-usage-insights/) | `v2` | `v2.1` … |
| [`v3-relay-service/`](./v3-relay-service/) | `v3` | `v3.1` … |

## 每个小迭代两份文件

| 文件 | 用途 |
|------|------|
| `P0N-某某.md` | 写/实现 |
| `P0N-save.md` | 备注（英→中）+ commit + `git push -u origin v1.N`（或 `plan.N` / `v2.N` / `v3.N`） |

测试：`ApiRelay/ApiRelayTests/V*/Phase*/`。临时调试：`DebugScratch/`（不上传）。
