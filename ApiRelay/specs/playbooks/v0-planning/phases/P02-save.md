# V0 规划 · 小迭代 Phase 2 — 保存并上传提示词

> **硬规则**：本小阶段内容写完后，必须执行本文件，打小迭代分支并 `git push`（规划线 `v0.0.N` 与产品线相同）。备注必须 English → 简体中文。

**把下面从「请为」开始到文末整段复制给 Cursor。**  
本对话只做：写备注 + commit + 推送到小迭代分支 `v0.0.2`。不要夹带产品实现代码（除非该迭代本身需要）。

命名：`v0.0.{小迭代}` —— 规划大阶段下的第 N 次迭代；**写完也要打分支上传**（与 v0.1.N 同规则）。

---

请为 **V0 规划 · Phase 2（规格冻住）** 保存本小迭代并上传。

## 固定目标

| 项 | 必须使用的值 |
|----|----------------|
| 大阶段分支 | `v0.0` |
| **本小迭代分支（本次上传目标）** | `v0.0.2` |
| 下一小迭代（本步不要创建，除非我另说） | `v0.0.3` |
| 台账 | `ApiRelay/specs/playbooks/BRANCHES.md` |
| 说明提示词 | `phases/P02-规格冻住.md` |
| 测试目录（可空） | `ApiRelay/ApiRelayTests/V0/Phase02_SpecsFreeze/` |

> 已存在于历史提交 `a62244d`（约 20:47 规格冻住）。补备注即可；不要改写历史。


## A. 更新迭代备注（必须英 → 中）

编辑 `BRANCHES.md`，为 **`v0.0.2`** 写入/更新：

1. **English**（2–4 句）  
2. **简体中文**  
3. tip commit hash  

## B. 提交并推到 `v0.0.2`

1. 汇报 `git status` / 当前分支 / `git log -5`。  
2. 经我确认后：

```bash
git checkout v0.0
git pull
git checkout -B v0.0.2
```

3. 暂存本迭代文档/规划改动 + `BRANCHES.md`（及 `V0/Phase02_SpecsFreeze/` 若有测试）。  
4. 禁止：`build/`、`DebugScratch/`、密钥、`spec-kit-0.15.2/`。  
5. 展示 cached diff，**同意后再 commit**：`docs(v0.0.2): Phase 2 规格冻住 iteration`  
6. `git push -u origin v0.0.2`  
7. 推荐同步大阶段：`git checkout v0.0 && git merge v0.0.2 && git push origin v0.0 && git checkout v0.0.2`

## C. 汇报

- `v0.0.2` @ `<hash>` 已在远程  
- 备注英+中已写  
- 下一步：若还要规划 → `P03` / `v0.0.3`；若开始产品实现 → 到 `v0.1` / `v0.1.N` 线  

## 禁止

- 用 tag 代替 `v0.0.2`  
- 未做完就预建更后面的迭代  
- force push  
