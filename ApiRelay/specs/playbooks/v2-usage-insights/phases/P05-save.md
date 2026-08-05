# V2 用量看板与关系图 · 小迭代 Phase 5 — 保存并上传提示词

> **硬规则**：本小阶段内容写完后，必须执行本文件，打小迭代分支并 `git push`（规划线 `plan.N` 与产品线相同）。备注必须 English → 简体中文。

**把下面从「请为」开始到文末整段复制给 Cursor。**  
本对话只做：写备注 + commit + 推送到**小迭代分支**。不要继续写实现代码。

命名记法：`plan.N`（规划）或 `v{阶段}.{小迭代}`（产品）—— **开发里程碑用分支**；商店上架才打 `release/N.0.0` tag。

---

请为 **V2 用量看板与关系图 · Phase 5（签发与作废）** 保存本小迭代并上传。

## 固定目标（写错迭代名视为失败）

| 项 | 必须使用的值 |
|----|----------------|
| 大阶段分支（第 2 层） | `v2` |
| **本小迭代分支（第 3 层 · 本次上传目标）** | `v2.5` |
| 下一小迭代（本步不要创建） | `v2.6` |
| 远程 | `origin` |
| 台账 | `ApiRelay/specs/playbooks/BRANCHES.md` |
| 实现提示词（对照，勿在本对话实现） | `phases/P05-签发与作废.md` |
| 本迭代测试目录 | `ApiRelay/ApiRelayTests/V2/Phase05_Issuance/` |

## A. 更新迭代备注（必须英 → 中）

编辑 `BRANCHES.md`，为小迭代 **`v2.5`** 写入/更新：

1. **English**（2–4 句）：相对上一小迭代多了什么、不含什么、何时 `git checkout v2.5`。  
2. **简体中文**：同样信息。  
3. tip commit（push 后的 hash）。

## B. 提交并推到小迭代分支 `v2.5`

1. 汇报：`git status -sb`、`git branch --show-current`、`git log -5 --oneline`。  
2. 确保在 `v2.5` 上工作（经我确认后再执行切换/创建）：

```bash
git checkout v2
git pull
git checkout -B v2.5
```

3. 暂存：本 Phase 实现 + `ApiRelayTests/V2/Phase05_Issuance/` 下本迭代测试 + `BRANCHES.md`。  
4. **禁止**加入：`ApiRelay/build/`、`ApiRelay/DebugScratch/`、`__pycache__/`、`spec-kit-0.15.2/`、密钥、`.env`。  
5. 展示 `git diff --cached --stat`，**等我同意后再 commit**。  
6. 建议 message：`feat(v2.5): Phase 5 签发与作废 iteration`  
7. 上传本小迭代：

```bash
git push -u origin v2.5
```

8. （推荐）同步大阶段线：

```bash
git checkout v2
git merge v2.5
git push origin v2
git checkout v2.5
```

## C. 完成汇报

- 小迭代 `v2.5` @ `<hash>` 已在远程  
- `BRANCHES.md` 已有英 + 中备注  
- 测试仅在对应 `Phase05_Issuance/`  
- 下一步：打开下一 Phase **实现**提示词；保存时再开下一小迭代 `v2.6`  

## 禁止

- 用 Git tag 充当小迭代名（禁止；上架才打 `release/N.0.0`；迭代一律用分支）  
- 预建未开始的大阶段 / 小迭代（如 `v2.6` 要等下一 Phase 完成再开）  
- 预建未开始的下一产品大阶段（如尚无 Stage2 时预建 `v2`）；force push；上传 `build` / `DebugScratch`  
