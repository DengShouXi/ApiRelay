# V0 — 规划大阶段 Playbook

**大阶段分支**：`v0.0`  
**规则**：每写完一个规划小阶段，也要打小迭代分支并上传（与产品阶段相同）。  
台账：[BRANCHES.md](../BRANCHES.md)

记法：`v0.0.N` = 规划线第 N 个小迭代。

| 小迭代 | 主题 | 说明提示词 | 保存/上传 | 状态 |
|--------|------|------------|-----------|------|
| `v0.0.1` | 工程基线 | [`phases/P01-工程基线.md`](./phases/P01-工程基线.md) | [`phases/P01-save.md`](./phases/P01-save.md) | 已完成（历史） |
| `v0.0.2` | 规格冻住 | [`phases/P02-规格冻住.md`](./phases/P02-规格冻住.md) | [`phases/P02-save.md`](./phases/P02-save.md) | 已完成（历史） |
| `v0.0.3` | 规划补充（下一规划迭代） | [`phases/P03-规划补充.md`](./phases/P03-规划补充.md) | [`phases/P03-save.md`](./phases/P03-save.md) | **模板：写完再上传** |
| `v0.0.4+` | 继续规划时再加 | 复制 P03 模式新建 `P0N` + `P0N-save` | 同左 | 做到再开 |

索引：[`05-annotate-branch.md`](./05-annotate-branch.md) · [`15-phase-push.md`](./15-phase-push.md)

规划线一般改 `specs/`、`constitution`、playbooks 备注；测试目录 `ApiRelayTests/V0/Phase0N_*/` 可空。
