# ApiRelay 实现 Playbook

**迭代规则**：[BRANCHES.md](./BRANCHES.md)（**统一三层分支，不用 tag 做里程碑**）  
**产品范围**：[ROADMAP.md](../ROADMAP.md)

## 记法

`v0.大阶段.小迭代` —— 全是分支。例：`v0.1.1` → 下一迭代 `v0.1.2`。

## 每个小迭代两份提示词

| 文件 | 干什么 |
|------|--------|
| `phases/P0N-某某.md` | 实现 |
| `phases/P0N-save.md` | 备注（英→中）+ 推到小迭代分支 `v0.Y.N` |

## 目录

| Playbook | 大阶段分支 | 小迭代 |
|----------|------------|--------|
| `v1-key-vault/` | `v0.1` | `v0.1.1` … `v0.1.8` |
| `v2-usage-insights/` | `v0.2` | `v0.2.1` …（做到再开） |
| `v3-relay-service/` | `v0.3` | `v0.3.1` …（做到再开） |

测试与迭代对齐：`ApiRelay/ApiRelayTests/V*/Phase*/`。
