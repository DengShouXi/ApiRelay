# V1 — 大阶段收尾核对提示词

把下面整段复制给 Cursor（仅在 8 个 Phase 的 Checkpoint 与 tag 都完成后）。

---

请核对 **产品大阶段 1（密钥库）** 是否可收尾。

## 必须核对

| 检查项 | 期望 |
|--------|------|
| 工作分支 | 本地与远程均为 `v0.1` |
| tags | 远程存在 `v0.1.1` … `v0.1.8`（已完成的 Phase；未做的不要假装有） |
| 台账 | `BRANCHES.md` 每个已打 tag 都有 **English + 简体中文** 备注与 commit hash |
| 工作区 | 无应提交却未提交的源码；`build/` 等已被 ignore |

命令建议：`git branch -vv`、`git tag -l 'v0.1.*'`、`git ls-remote --tags origin 'v0.1.*'`、对照 `tasks.md` Checkpoint。

## 通过后

提示我打开 [`30-create-next-branch.md`](./30-create-next-branch.md) —— **那时才**创建分支 `v0.2`。  
现在不要创建 `v0.2`/`v0.3`/`v0.4`。禁止 force push。
