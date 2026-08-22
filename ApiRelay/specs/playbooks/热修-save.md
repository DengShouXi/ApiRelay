# 上架后热修 — 保存并上传提示词

> **何时用**：某个小迭代（如 `v1.13`）**已经关账**，并且商店那一包已经打了 tag（如 `release/1.0.0`），现在只是修 bug / 改文案，不是开新的 P0N。  
> **权威**：[`BRANCHES.md`](./BRANCHES.md)「分支 vs tag」+ 保护约定。中文说明：[`重要说明/分支与版本.md`](./重要说明/分支与版本.md)。

**你下次只要把下面从「请按」开始到文末整段发给 Cursor**（或只说：「按热修-save 保存并上传」）。  
本对话只做：开热修分支 + 写台账 + commit + push。不要继续写实现，不要送审、不要打新 tag。

---

请按本文件保存并上传**当前工作区已确认可入库的改动**（上架后热修，不是新的 P0N）。

## 固定目标（写错视为失败）

先看当前 HEAD 所在的**已冻结**小迭代（例：现在停在 `v1.13`，与 tag `release/1.0.0` / `main` 同 tip），然后：

| 项 | 必须使用的值 |
|----|----------------|
| **本次上传的 Git 分支** | `v{阶段}.{小迭代}.{热修}`（例：冻结的是 `v1.13` → 开 **`v1.13.1`**；已有 `.1` 则 `.2`） |
| 大阶段 tip | 对应 `v1` / `v2` / `v3`（只 fast-forward 前进） |
| 远程 | `origin` |
| 台账 | `ApiRelay/specs/playbooks/BRANCHES.md`（English → 简体中文） |
| 商店版本 | **本次默认不改** `MARKETING_VERSION` |
| 上架 tag | **本次不打**；已有的 `release/N.0.0` 不准移动 |

先例：`v1.11` 关账后开 `v1.11.1`。

## 禁止（常见误操作）

- 在已冻结的 `v1.13`（或任何已关账 `v1.N` / `plan.N`）上继续 commit 再 push，盖掉旧 tip。  
- 新建 **分支** `release/1.0.0` 或 `release/1.0.1`（`release/*` 只允许当 **tag**；`release/1.0.0` tag 已经存在）。  
- 把 `v1.13` 改名为 `release/1.0.0`。  
- 开 `v1.14` 来装这次修 bug（那是下一整块产品小迭代的名字，不是热修）。  
- force push；移动已有 tag；未另授权就把 `main` 推到热修 tip。  
- 把 `ZL03_原始素材/相关展示截图/`、`ZL03_原始素材/icon素材/`、`DebugScratch/`、`build/`、密钥、`.env`、含真实密钥的截图加进提交。
  （`ZL03_原始素材/README.md` 可以入库；整棵素材二进制不要进。）  
- 打开某个 `P0N-save.md` 冒充新 Phase。  
- 改宪法 / `spec.md` / `ROADMAP.md`（决策没变就不动）。

## A. 开热修分支（带着未提交改动离开冻结 tip）

```bash
git rev-parse --abbrev-ref HEAD    # 若是已冻结的 v1.13 / main，不要在上面 commit
git checkout -b v1.13.1            # 分支名按上表替换；工作区改动一起带走
```

若已经在正确的热修分支上，不要再开一条。

## B. 更新 `BRANCHES.md`

- 「当前分支」写明：工作分支是本热修；`v1.13` 与 tag `release/1.0.0` **冻住不动**。  
- 表格新增本热修一行：**English → 简体中文**，写清修了什么、不覆盖哪条冻结分支、未改商店号。  
- 大阶段 tip（`v1`）改为对齐本热修；`main` 仍指向已上架的 `1.0.0`，除非用户**另句授权**把 `main` 跟过来。

## C. 提交并推送

1. 暂存本次热修相关代码 / 测试 / `BRANCHES.md` / 若有的根目录 README 等说明改动。  
2. commit message 用热修分支名，例如：  
   `fix(v1.13.1): …` 或 `docs(v1.13.1): …`  
3. `git push -u origin v1.13.1`  
4. 大阶段 tip 只 fast-forward：

```bash
git checkout v1
git merge --ff-only v1.13.1
git push origin v1
git checkout v1.13.1
```

5. **不要** `git push origin v1.13`。不要改 tag。不要默认 push `main`。

## D. 完成汇报

- 热修分支 `v1.13.1` @ `<hash>` 已在远程  
- 冻结未动：`v1.13`、tag `release/1.0.0`、（默认）`main`  
- 大阶段 tip `v1` 是否已前进  
- 确认：未新建 `release/*` 分支；未改 `MARKETING_VERSION`；未打新 tag；未 force push  
- 下次若要再送审：另授权 bump 商店 **1.0.1**、Archive，再考虑 ff `main` 并打 tag `release/1.0.1`
