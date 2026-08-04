# V1 密钥保险库 · Phase 5 — 检查点保存与上传提示词

**把下面从「请为」开始到文末整段复制给 Cursor。**  
本对话只做：写备注 + commit + 打 tag + push。**不要**继续写本 Phase 或下一 Phase 的实现代码。

---

请为 **V1 密钥保险库 · Phase 5（付费解锁）** 做检查点保存并上传到远程。

## 固定目标（写错分支/tag 视为失败）

| 项 | 必须使用的值 |
|----|----------------|
| 工作分支（第 2 层） | `v0.1` |
| 检查点 tag（第 3 层） | `v0.1.5` |
| 远程 | `origin` |
| 台账 | `ApiRelay/specs/playbooks/BRANCHES.md` |
| 对应实现提示词 | `phases/P05-付费解锁.md`（仅作对照，本对话不实现） |

## A. 更新分支备注（必须英 → 中）

编辑 `BRANCHES.md`：在 checkpoint tags 表（或「Current refs」下）为 **`v0.1.5`** 写入/更新一条：

1. **English**（2–4 句）：相对上一检查点多了什么、刻意不含什么、何时该 `git checkout v0.1.5` 回看。  
2. **简体中文**：同样信息，口语清楚。  
3. 表格字段：`Tag` = `v0.1.5`，`Commit` = 本步 commit 后的 hash（先占位，commit 后补全），`Phase` = Phase 5 付费解锁。

同时确认台账仍写明：大阶段用分支 `v0.1`；小阶段用 tag；不预建未开始的大阶段；无 `v0.4`。

## B. 提交（在分支 `v0.1` 上）

1. 运行并汇报：`git status -sb`、`git branch --show-current`、`git log -5 --oneline`。  
2. **当前分支必须是 `v0.1`**。若不是：先说明现状，经我确认后再 `git checkout v0.1`（不要擅自从别的大阶段分支乱切）。  
3. 暂存本 Phase 实现改动 + `BRANCHES.md`（及本 playbook 若有改）。  
4. **禁止**加入：`ApiRelay/build/`、`__pycache__/`、`spec-kit-0.15.2/`、密钥、`.env`、含明文的调试文件。  
5. 展示 `git diff --cached --stat`，**等我明确同意后再 commit**。  
6. Commit message 建议：

```text
feat(v0.1): Phase 5 付费解锁 checkpoint

Freeze Phase 5 on stage branch v0.1; ledger updated for tag v0.1.5.
```

## C. 打 tag 并上传

1. Annotated tag（第三层是 **tag**，禁止新建同名分支 `v0.1.5`）：

```bash
git tag -a v0.1.5 -m "Phase 5 checkpoint: 付费解锁"
```

2. 推送分支与 tag：

```bash
git push -u origin v0.1
git push origin refs/tags/v0.1.5
```

3. 用 `git ls-remote --heads origin v0.1` 与 `git ls-remote --tags origin v0.1.5` 核对远程已有；把 **commit hash** 写回 `BRANCHES.md` 后若有改动再补一次小 commit + `git push origin v0.1`（**不要**移动已推送的 tag，除非我明确要求）。

## D. 完成汇报

- 分支：`v0.1` @ `<hash>`  
- tag：`v0.1.5` @ `<hash>`  
- `BRANCHES.md` 是否已含英+中备注  
- 下一步：打开下一 Phase 的**实现**提示词（不是本 save 文件）；人仍留在 `v0.1`。

## 禁止

- 新建分支 `v0.1.5` / `v0.2` / `v0.3` / `v0.4`（未轮到的大阶段不要建）  
- `git push --force` / 删除远程 tag  
- 把实现代码与上传步骤混在同一轮未确认的大改里强行推送  
