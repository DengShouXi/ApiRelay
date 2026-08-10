# V1 密钥保险库 · 小迭代 Phase 11 — 保存并上传提示词

> **硬规则**：本小阶段内容写完后，必须执行本文件，打小迭代分支并 `git push`。备注必须 English → 简体中文。

**把下面从「请为」开始到文末整段复制给 Cursor。**  
本对话只做：写备注 + commit + 推送到**小迭代分支**。不要继续写实现代码。

---

请为 **V1 密钥保险库 · Phase 11（App Icon + SF Symbol / 资源）** 保存本小迭代并上传。

## 固定目标（写错迭代名视为失败）

| 项 | 必须使用的值 |
|----|----------------|
| 大阶段分支（第 2 层） | `v1` |
| **本小迭代分支（第 3 层 · 本次上传目标）** | `v1.11` |
| 上一小迭代（已完成） | `v1.10`（[`P10-UI重设计.md`](./P10-UI重设计.md)） |
| 下一继续开发分支（本步按需） | 视 Stage1 收尾；商店正式材料含 **T065**；大阶段再开 `v2` |
| 远程 | `origin` |
| 台账 | `ApiRelay/specs/playbooks/BRANCHES.md` |
| 实现提示词（对照，勿在本对话实现） | `phases/P11-AppIcon与资源.md` |
| 验收 | `phases/P11-验收清单.md` |

## A. 更新迭代备注（必须英 → 中）

编辑 `BRANCHES.md`，为小迭代 **`v1.11`** 写入/更新 English + 简体中文（App Icon 全尺寸、SF 语义表、Asset 约定、T065 截图草稿）。

## B. 提交并推到小迭代分支 `v1.11`

1. 确保在 `v1.11` 上工作。  
2. 暂存本 Phase 实现 + playbook + `BRANCHES.md` + 截图草稿（若有）。  
3. **禁止**加入：`build/`、`DebugScratch/`、`00.md`、密钥、`.env`、设计源大文件。  
4. message：`feat(v1.11): App Icon, SF Symbol catalog, store screenshot drafts`  
5. `git push -u origin v1.11`  
6. 同步大阶段线：`v1` merge `v1.11` 后 push。  

## C. 完成汇报

- 小迭代 `v1.11` @ `<hash>` 已在远程  
- 上一步：`v1.10` / Phase 10 UI 重设计  
- 下一步：Stage1 上架材料精修（**T065** 等）或按产品安排开后续小迭代 / `v2`
