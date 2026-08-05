# V1 密钥保险库 · 小迭代 Phase 10 — 保存并上传提示词

> **硬规则**：本小阶段内容写完后，必须执行本文件，打小迭代分支并 `git push`。备注必须 English → 简体中文。

**把下面从「请为」开始到文末整段复制给 Cursor。**  
本对话只做：写备注 + commit + 推送到**小迭代分支**。不要继续写实现代码。

---

请为 **V1 密钥保险库 · Phase 10（UI 重设计）** 保存本小迭代并上传。

## 固定目标（写错迭代名视为失败）

| 项 | 必须使用的值 |
|----|----------------|
| 大阶段分支（第 2 层） | `v1` |
| **本小迭代分支（第 3 层 · 本次上传目标）** | `v1.10` |
| 下一产品大阶段（本步可按 `30-create-next-branch.md` 创建 tip） | `v2` |
| 远程 | `origin` |
| 台账 | `ApiRelay/specs/playbooks/BRANCHES.md` |
| 实现提示词（对照，勿在本对话实现） | `phases/P10-UI重设计.md` |
| 验收 | `phases/P10-验收清单.md` |

## A. 更新迭代备注（必须英 → 中）

编辑 `BRANCHES.md`，为小迭代 **`v1.10`** 写入/更新 English + 简体中文。

## B. 提交并推到小迭代分支 `v1.10`

1. 确保在 `v1.10` 上工作。  
2. 暂存本 Phase 实现 + playbook + `BRANCHES.md`。  
3. **禁止**加入：`build/`、`DebugScratch/`、`00.md`、密钥、`.env`。  
4. message：`feat(v1.10): Phase 10 UI redesign iteration`  
5. `git push -u origin v1.10`  
6. 同步大阶段线：`v1` merge `v1.10` 后 push。  

## C. 完成汇报

- 小迭代 `v1.10` @ `<hash>` 已在远程  
- 下一步：按 `30-create-next-branch.md` / `40-checkout-next-branch.md` 进入 `v2`，打开 `v2-usage-insights/00-README.md`
