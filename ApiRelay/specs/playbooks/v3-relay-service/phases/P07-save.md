# V3 中转服务 · 小迭代 Phase 7 — 保存并上传提示词

> **硬规则**：本小阶段内容写完后，必须执行本文件，打小迭代分支并 `git push`（规划线 `plan.N` 与产品线相同）。备注必须 English → 简体中文。

**把下面从「请为」开始到文末整段复制给 Cursor。**  
本对话只做：写备注 + commit + 推送到**小迭代分支**。不要继续写实现代码。

命名记法：`plan.N`（规划）或 `v{阶段}.{小迭代}`（产品）—— **开发里程碑用分支**；商店上架才打 `release/N.0.0` tag。

---

请为 **V3 中转服务 · Phase 7（隐私与收尾）** 保存本小迭代并上传。

## 固定目标（写错迭代名视为失败）

| 项 | 必须使用的值 |
|----|----------------|
| 大阶段分支（第 2 层） | `v3` |
| **本小迭代分支（第 3 层 · 本次上传目标）** | `v3.7` |
| 下一小迭代（本步不要创建） | `v3.8` |
| 远程 | `origin` |
| 台账 | `ApiRelay/specs/playbooks/BRANCHES.md` |
| 实现提示词（对照，勿在本对话实现） | `phases/P07-隐私与收尾.md` |
| 本迭代测试目录 | `ApiRelay/ApiRelayTests/V3/Phase07_Privacy/` |

## A. 更新迭代备注（必须英 → 中）

编辑 `BRANCHES.md`，为小迭代 **`v3.7`** 写入/更新：

1. **English**（2–4 句）：相对上一小迭代多了什么、不含什么、何时 `git checkout v3.7`。  
2. **简体中文**：同样信息。  
3. tip commit（push 后的 hash）。

## B. 提交并推到小迭代分支 `v3.7`

1. 汇报：`git status -sb`、`git branch --show-current`、`git log -5 --oneline`。  
2. 确保在 `v3.7` 上工作（经我确认后再执行切换/创建）：

```bash
git checkout v3
git pull
git checkout -B v3.7
```

3. 暂存：本 Phase 实现 + `ApiRelayTests/V3/Phase07_Privacy/` 下本迭代测试 + `BRANCHES.md`。  
4. **禁止**加入：`ApiRelay/build/`、`ApiRelay/DebugScratch/`、`__pycache__/`、`spec-kit-0.15.2/`、密钥、`.env`。  
5. 展示 `git diff --cached --stat`，**等我同意后再 commit**。  
6. 建议 message：`feat(v3.7): Phase 7 隐私与收尾 iteration`  
7. 上传本小迭代：

```bash
git push -u origin v3.7
```

8. （推荐）同步大阶段线：

```bash
git checkout v3
git merge v3.7
git push origin v3
git checkout v3.7
```

## C. 完成汇报

- 小迭代 `v3.7` @ `<hash>` 已在远程  
- `BRANCHES.md` 已有英 + 中备注  
- 测试仅在对应 `Phase07_Privacy/`  
- 下一步：打开下一 Phase **实现**提示词；保存时再开下一小迭代 `v3.8`  

## 禁止

- 用 Git tag 充当小迭代名（禁止；上架才打 `release/N.0.0`；迭代一律用分支）  
- 预建未开始的大阶段 / 小迭代（如 `v3.8` 要等下一 Phase 完成再开）  
- 预建未开始的下一产品大阶段（如尚无 Stage2 时预建 `v2`）；force push；上传 `build` / `DebugScratch`  
