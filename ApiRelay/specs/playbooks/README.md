# ApiRelay 实现 Playbook

**迭代规则**：[BRANCHES.md](./BRANCHES.md)  
**上架**：[ROADMAP.md](../ROADMAP.md)（Stage N → App Store `N.0.0`）  
**中文入口**：[重要说明/索引.md](./重要说明/索引.md)

## 唯一记法

`plan.N`（规划）· `v{阶段}.{小迭代}`（产品）—— **开发里程碑全是分支**；商店发布才打 `release/N.0.0` tag。

**每个小阶段写完 → 必须用对应 `P0N-save.md` 打分支并上传**（规划 `plan.3` 也一样）。  
**已关账 / 已上架后的修 bug → [`热修-save.md`](./热修-save.md)**（例：`v1.13.1`）；`release/*` 只当 tag，不要建成分支。

**禁止**再新建旧名 `v0.0.N` / `v0.1.N` / `v0.2.N` / `v0.3.N`（现行名见 [BRANCHES.md](./BRANCHES.md)）。

## 大阶段进度

| 阶段 | 目录 | tip | 状态 | 商店版本 |
|------|------|-----|------|----------|
| 规划 | [`v0-planning/`](./v0-planning/) | `plan` | **已完成**（`plan.1`–`plan.2`） | — |
| Stage1 密钥库 | [`v1-key-vault/`](./v1-key-vault/) | `v1` | **开发 + 上架材料已完成**（末迭代 `v1.13`） | 目标 **1.0.0**（尚未 T062 送审） |
| Stage2 用量看板 | [`v2-usage-insights/`](./v2-usage-insights/) | `v2` | tip 已开；Stage1 送审就绪后再深做 | 目标 **2.0.0** |
| Stage3 中转 | [`v3-relay-service/`](./v3-relay-service/) | `v3` | 未开工 | 目标 **3.0.0** |

### Stage1 已完成意味着什么

- 小迭代 **`v1.1` … `v1.13`** 全部关账：实现、安全审查、本地化、商店材料（T063–T066）与上架前产品收口均已到位。  
- **不等于**已上架：未合并 `main`、未打 `release/1.0.0`、未点 ASC「提交以供审核」。

**Stage1 收尾顺序（仍须按序）**：

```text
P13-save → v1.13 + tip v1
  → 10-verify（总验收）
  → 12-release-T062（须明确授权：main + release/1.0.0 + 提交审核）
  → 20-push → 30/40 → 进入 Stage2
```

入口：[`v1-key-vault/00-README.md`](./v1-key-vault/00-README.md)

## 目录速查

| 目录 | 大阶段 tip | 小迭代例子 |
|------|------------|------------|
| [`v0-planning/`](./v0-planning/) | `plan` | `plan.1` … `plan.3` … |
| [`v1-key-vault/`](./v1-key-vault/) | `v1` | `v1.1` … **`v1.13`（已完成）** → `10-verify` → `12-release-T062` … |
| [`v2-usage-insights/`](./v2-usage-insights/) | `v2` | `v2.1` … |
| [`v3-relay-service/`](./v3-relay-service/) | `v3` | `v3.1` … |

## 每个小迭代两份文件

| 文件 | 用途 |
|------|------|
| `P0N-某某.md` | 写/实现 |
| `P0N-save.md` | 备注（英→中）+ commit + `git push -u origin v1.N`（或 `plan.N` / `v2.N` / `v3.N`） |
| [`热修-save.md`](./热修-save.md) | 已关账 / 上架后修 bug：开 `v1.N.M`、更新台账、push；不盖冻结 tip |

测试：`ApiRelay/ApiRelayTests/V*/Phase*/`。临时调试：`DebugScratch/`（不上传）。
