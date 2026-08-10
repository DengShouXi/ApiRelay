# V1 密钥保险库 · 小迭代 Phase 13 — 保存并上传提示词

> **硬规则**：本小阶段内容写完后，必须执行本文件，打小迭代分支并 `git push`。备注必须 English → 简体中文。

**把下面从「请为」开始到文末整段复制给 Cursor。**  
本对话只做：写备注 + commit + 推送到**小迭代分支**。不要继续写实现代码，不要执行 T062。

---

请为 **V1 密钥保险库 · Phase 13（Stage1 上架材料 T063–T066）** 保存本小迭代并上传。

## 固定目标（写错迭代名视为失败）

| 项 | 必须使用的值 |
|----|----------------|
| 大阶段分支（第 2 层） | `v1` |
| **本小迭代分支（第 3 层 · 本次上传目标）** | `v1.13` |
| 上一小迭代（已完成） | `v1.12`（本地化验收） |
| 下一继续开发 | [`../10-verify.md`](../10-verify.md) →（授权后）[`../12-release-T062.md`](../12-release-T062.md)；**勿**擅自开 `v2` 实现 |
| 远程 | `origin` |
| 台账 | `ApiRelay/specs/playbooks/BRANCHES.md` |
| 实现提示词（对照，勿在本对话实现） | `phases/P13-上架材料.md` |
| 验收 | `phases/P13-验收清单.md` |
| 草稿 | `store-drafts/v1.13/` |

## A. 更新迭代备注（必须英 → 中）

编辑 `BRANCHES.md`，为小迭代 **`v1.13`** 写入/更新 English + 简体中文：

- 交付：T063–T066 上架材料（元数据 / 隐私问卷对齐 / 截图 / `MARKETING_VERSION=1.0.0` 等）  
- **明确未执行** T062（无 `main` 合并、无 `release/1.0.0`、无提交审核）  
- tip commit（push 后的 hash）与时间  

同步更新：`00-README.md`「当前小迭代」行（`v1.13` 已关账 / 下一步 10-verify）。

## B. 提交并推到小迭代分支 `v1.13`

1. 确保在 `v1.13` 上工作。  
2. 暂存：`store-drafts/v1.13/**`、版本号改动、本 Phase playbook（`P13-*`）、收尾链若本阶段已改（`10-verify` / `12-release-T062` 等）、`BRANCHES.md`、`00-README.md`。  
3. **禁止**加入：`build/`、`DebugScratch/`、`00.md`、密钥、`.env`、含真实密钥的截图、设计源大文件。  
4. message：`docs(v1.13): Stage1 store materials T063-T066`  
5. `git push -u origin v1.13`  
6. 同步大阶段线：`v1` fast-forward 对齐 `v1.13` tip 后 push（只前进、不回退）。  

## C. 完成汇报

- 小迭代 `v1.13` @ `<hash>` 已在远程  
- 上一步：`v1.12`  
- 下一步：**[`../10-verify.md`](../10-verify.md)**；通过后须用户明确授权才打开 **[`../12-release-T062.md`](../12-release-T062.md)**  
- 确认：本对话**未**执行 T062；**未**创建 `v2.N` 实现小迭代
