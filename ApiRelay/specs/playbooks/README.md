# ApiRelay 实现 Playbook

**迭代规则**：[BRANCHES.md](./BRANCHES.md)

## 唯一记法

`v0.大阶段.小迭代` —— **全是分支**。

**每个小阶段写完 → 必须用对应 `P0N-save.md` 打分支并上传**（规划 `v0.0.3` 也一样）。

## 目录

| 目录 | 大阶段 | 小迭代例子 |
|------|--------|------------|
| [`v0-planning/`](./v0-planning/) | `v0.0` | `v0.0.1` … `v0.0.3` … |
| [`v1-key-vault/`](./v1-key-vault/) | `v0.1` | `v0.1.1` … `v0.1.8` |
| [`v2-usage-insights/`](./v2-usage-insights/) | `v0.2` | `v0.2.1` … |
| [`v3-relay-service/`](./v3-relay-service/) | `v0.3` | `v0.3.1` … |

## 每个小迭代两份文件

| 文件 | 用途 |
|------|------|
| `P0N-某某.md` | 写/实现 |
| `P0N-save.md` | 备注（英→中）+ commit + `git push -u origin v0.Y.N` |

测试：`ApiRelay/ApiRelayTests/V*/Phase*/`。临时调试：`DebugScratch/`（不上传）。
