# ApiRelay 实现 Playbook

> 本页的“大阶段进度”及 Stage1 端到端顺序是早期规划快照，不是当前发布状态或自动执行链。实时状态先查 [`ZL01/14`](../../../ZL01_具体说明/14-项目当前状态.md) 并在目标工作树核对 Git／ASC；操作授权见 [`ZL00/03`](../../../ZL00_项目总控/03-关账与发布闸门.md)。

**迭代规则**：[BRANCHES.md](./BRANCHES.md)  
**上架**：[ROADMAP.md](../ROADMAP.md)（Stage N → App Store `N.0.0`）  
**中文入口**：[重要说明/索引.md](./重要说明/索引.md)

## 唯一记法

`plan.N`（规划）· `v{阶段}.{小迭代}`（产品）—— **开发里程碑全是分支**；商店发布才打 `release/N.0.0` tag。

历史小阶段使用对应 `P0N-save.md` 建分支与留证。**完成、提交、推送、移动大阶段 tip 是不同操作**；只在本次授权和验收条件满足时执行，不能把“小阶段写完”当成自动上传授权。现行上传闸门以 [`ZL00/03`](../../../ZL00_项目总控/03-关账与发布闸门.md) 和 [`ZL01/09`](../../../ZL01_具体说明/09-上传流程.md) 为准。
**已关账 / 已上架后的修 bug → [`热修-save.md`](./热修-save.md)**（例：`v1.13.1`）；`release/*` 只当 tag，不要建成分支。

**禁止**再新建旧名 `v0.0.N` / `v0.1.N` / `v0.2.N` / `v0.3.N`（现行名见 [BRANCHES.md](./BRANCHES.md)）。

## 历史大阶段规划快照（不可用于当前关账）

| 阶段 | 目录 | tip | 状态 | 商店版本 |
|------|------|-----|------|----------|
| 规划 | [`v0-planning/`](./v0-planning/) | `plan` | **已完成**（`plan.1`–`plan.2`） | — |
| Stage1 密钥库 | [`v1-key-vault/`](./v1-key-vault/) | `v1` | 早期计划到 `v1.13`；后续热修与购买验收另见当前工作包 | 当时目标 **1.0.0** |
| Stage2 用量看板 | [`v2-usage-insights/`](./v2-usage-insights/) | `v2` | 早期规划；是否开工须现场核对 | 当时目标 **2.0.0** |
| Stage3 中转 | [`v3-relay-service/`](./v3-relay-service/) | `v3` | 早期规划；是否开工须现场核对 | 当时目标 **3.0.0** |

### Stage1 已完成意味着什么

- 小迭代 **`v1.1` … `v1.13`** 全部关账：实现、安全审查、本地化、商店材料（T063–T066）与上架前产品收口均已到位。  
- 上述只描述早期计划在该节点的含义；`main`、tag、ASC 的**当前事实不得从这段历史文字推断**。

**Stage1 历史收尾顺序（仅供追溯）**：

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
| `P0N-save.md` | 对应阶段的历史分支与保存提示；实际 commit／push 仍须核对本次授权、现行闸门和目标引用 |
| [`热修-save.md`](./热修-save.md) | 已关账 / 上架后修 bug：核对现有热修分支和授权；不盖冻结 tip，commit／push 不自动执行 |

测试：`ApiRelay/ApiRelayTests/V*/Phase*/`。临时调试：`DebugScratch/`（不上传）。
