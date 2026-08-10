# V1 密钥保险库 · 小迭代 Phase 9 — 保存并上传提示词

> **硬规则**：本小阶段内容写完后，必须执行本文件，打小迭代分支并 `git push`。备注必须 English → 简体中文。  
> **补档说明**：`v1.9` 历史上已 push（tip 含 `7c77778` / `32318c2`）。若仅补 playbook/测试目录，在当前工作分支提交后，**不要**强行改写已发布的 `v1.9` tip；台账备注保持与远程 `v1.9` 一致即可。

**把下面从「请为」开始到文末整段复制给 Cursor。**  
本对话只做：写备注 + commit + 推送到**小迭代分支**。不要继续写实现代码。

---

请为 **V1 密钥保险库 · Phase 9（可用性加固 + T014b Checkpoint 2b）** 保存本小迭代并上传。

## 固定目标（写错迭代名视为失败）

| 项 | 必须使用的值 |
|----|----------------|
| 大阶段分支（第 2 层） | `v1` |
| **本小迭代分支（第 3 层 · 本次上传目标）** | `v1.9` |
| 下一小迭代（本步不要创建） | `v1.10` |
| 远程 | `origin` |
| 台账 | `ApiRelay/specs/playbooks/BRANCHES.md` |
| 实现提示词（对照，勿在本对话实现） | `phases/P09-可用性加固.md` |
| 验收 | `phases/P09-验收清单.md` |
| 本迭代测试目录 | `ApiRelay/ApiRelayTests/V1/Phase09_UXHardening/` |

## A. 更新迭代备注（必须英 → 中）

编辑 `BRANCHES.md`，为小迭代 **`v1.9`** 写入/更新：

1. **English**（2–4 句）：相对 `v1.8` 多了什么（UX 加固 + T014b 2b）、不含什么、何时 `git checkout v1.9`。  
2. **简体中文**：同样信息。  
3. tip commit（远程 `v1.9` tip hash，历史为 `32318c2` 一带）。

## B. 提交并推到小迭代分支 `v1.9`

1. 汇报：`git status -sb`、`git branch --show-current`、`git log -5 --oneline`。  
2. 若 `v1.9` **已在远程且 tip 已冻结**：补档文件可提交到当前继续开发分支（如 `v1.11`），并在汇报中注明「P09 文档补全，不改写 `v1.9` tip」。  
3. 若当时尚未 push：确保在 `v1.9` 上工作后再 push。  
4. **禁止**加入：`build/`、`DebugScratch/`、`00.md`、密钥、`.env`。  
5. 历史实现 message 示例：`feat(v1.9): close T014b CloudKit Production Checkpoint 2b` / `feat(v0.1.9): harden vault UX — multi-key, recycle bin, dual view`

## C. 完成汇报

- 小迭代 `v1.9` 已在远程（或文档补全已说明）  
- `BRANCHES.md` / `00-README.md` / `05-annotate-branch.md` 含 Phase 9  
- 测试目录：`Phase09_UXHardening/`  
- 下一步：[`P10-UI重设计.md`](./P10-UI重设计.md) → `v1.10`

## 禁止

- 用 Git tag 充当小迭代名  
- force push 改写已共享的 `v1.9` 历史（除非用户明确要求）  
- 上传 `build` / `DebugScratch`
