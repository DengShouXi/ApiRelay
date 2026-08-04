# Git Branch Ledger / 分支台账

**Scheme authority / 命名与层级以本文为准。**  
Product stages follow [ROADMAP.md](../ROADMAP.md).

---

## Important: Git has no nested folders / 先纠正一个误解

**English**  
Git branches are **flat pointers** to commits. Names like `v0.1.1` look hierarchical, but there is no real parent/child branch tree in Git. Hierarchy is a **naming convention** only.

**简体中文**  
Git 分支是指向提交的**扁平指针**。`v0.1.1` 看起来像子文件夹，但 Git **没有**真正的「父分支套子分支」。层级只靠**命名约定**表达。

---

## Recommended model (standard) / 推荐结构（通用做法）

```text
含义上的三层（不是 Git 真文件夹）:

v0                          ← 第 1 层：未上架（一般不单独建分支）
├── v0.0                    ← 第 2 层：长期「大阶段分支」（规划）
│   ├── tag v0.0.1
│   └── tag v0.0.2
├── v0.1                    ← 第 2 层：产品大阶段 1（密钥库）← 当前干活
│   ├── tag v0.1.1
│   ├── tag v0.1.2 …        ← 第 3 层：小阶段检查点用 tag，不是新分支
│   └── tag v0.1.8
├── v0.2                    ← 用到第 2 大阶段时再创建（现在不要建）
└── v0.3                    ← 用到第 3 大阶段时再创建
    （不设 v0.4：ROADMAP 只有三大产品阶段）
```

| Layer / 层 | What to create / 建什么 | When / 何时建 |
|------------|-------------------------|---------------|
| 1 — `v0` | Usually **nothing** (concept only) | — |
| 2 — `v0.0` / `v0.1` / `v0.2` / `v0.3` | **Branch** (long-lived while that stage is active) | **When you start that stage** — lazy, not upfront |
| 3 — `v0.1.1` … | **Tag** (immutable checkpoint) | **When a Phase checkpoint passes** |

### Why not pre-create all branches? / 为什么不要事先建好全部？

**English**  
Empty future branches (`v0.2`, `v0.3`, `v0.4`) add noise, go stale, and confuse “where do I commit?”. Create the stage branch when you actually start that work; save checkpoints with tags as you go.

**简体中文**  
提前建空的 `v0.2`/`v0.3`/`v0.4` 只会干扰「到底往哪提交」。**做到那个大阶段再开对应分支**；小阶段完成时用 **tag 保存**，不要每做完一小步就永久留一个第三层分支。

### Why tags for the 3rd level? / 为什么第三层用 tag？

Industry default: **branch = moving workline**, **tag = frozen milestone**.  
业界常规：**分支继续往前改**，**tag 钉住历史检查点**（可回看、不改写）。

---

## Digit meanings / 各位数字含义

`v{release}.{stage}.{checkpoint}`

| Digit | Meaning |
|-------|---------|
| 1st = `0` | Not App Store published yet |
| 2nd = `0`–`3` | `0` planning; `1` key vault; `2` insights; `3` relay. **No `4`.** |
| 3rd | Phase/revision checkpoint → recorded as a **tag** on the stage branch |

---

## Current refs / 当前仓库状态

### Stage branches（第 2 层 · 分支）

#### `v0.0` — planning stage tip

**English**  
Long-lived tip of the planning/spec line. Points at the post-spec freeze (same commit as historical tag `v0.0.2`). Do not keep implementing product Phase code here.

**简体中文**  
规划/规格线的长期尖端。停在规格冻住点（与历史 tag `v0.0.2` 同提交）。不要在这里继续写产品 Phase 实现代码。

#### `v0.1` — product stage 1 (current work)

**English**  
Active workline for key vault. Commit here daily. When Phase N passes, tag `v0.1.N` and push the tag — stay on `v0.1`.

**简体中文**  
密钥库大阶段的**当前工作分支**。日常提交都在这里。Phase N 通过后打 tag `v0.1.N` 并推送，**人仍留在 `v0.1` 上继续做**。

### Checkpoint tags（第 3 层 · 标签）

| Tag | Commit | English | 简体中文 |
|-----|--------|---------|----------|
| `v0.0.1` | `2cf6803` | Earliest engineering baseline | 最初工程基线 |
| `v0.0.2` | `a62244d` | Specs/planning freeze @ 20:47 | 20:47 前规格快照 |
| `v0.1.1` | *(tip of `v0.1` when tagged)* | Playbooks + Phase 1 scaffold checkpoint | playbooks + Phase 1 脚手架检查点 |

### Deprecated / 已废弃的旧用法

Older refs named `v0.0.1` / `v0.0.2` / `v0.1.1` **as branches** mixed layer-2 and layer-3. Prefer stage **branches** + checkpoint **tags** going forward.  
以前把第三层也建成分支，会和第 2 层搅在一起；以后统一为「大阶段分支 + 小阶段 tag」。

---

## Workflow / 日常怎么做

1. **Now**: work on `v0.1` only.  
2. Finish a Phase → update this ledger (EN + 中文) → commit on `v0.1` → `git tag v0.1.N` → push branch + tag.  
3. **Do not** create `v0.2` / `v0.3` until that ROADMAP stage starts.  
4. **Do not** create `v0.4`.  
5. **Do not** create an empty parent branch `v0` unless you later want it as a trunk alias.

Playbook prompts: `05-annotate-branch.md`（写备注）→ `15-phase-push.md`（提交 + **打 tag** + 推送）。
