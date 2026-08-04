# Git Branch Ledger / 分支台账

**Scheme authority / 命名规则以本文为准。**  
Product stage scope still follows [ROADMAP.md](../ROADMAP.md)（产品三大阶段范围仍以 ROADMAP 为准）。

---

## Version scheme / 版本号规则

Format: `v{release}.{stage}.{revision}`

| Digit / 位 | English | 简体中文 |
|------------|---------|----------|
| 1st — release | `0` = not published to the App Store yet. Flip only when you actually ship. | `0` = 尚未正式上架。真正发布后再改这一位。 |
| 2nd — stage | `0` = planning/spec writing only (no product-stage implementation). `1` / `2` / `3` = ROADMAP product stages (key vault / insights / relay). | `0` = 仅规划与规格文档阶段。`1` / `2` / `3` = 产品三大阶段（密钥库 / 用量看板 / 中转）。 |
| 3rd — revision | Patch or checkpoint inside that stage. For stage `1`, prefer aligning with Phase 1…8 → `v0.1.1` … `v0.1.8`. | 该大阶段内的修订/检查点。大阶段 `1` 建议与 Phase 1…8 对齐 → `v0.1.1` … `v0.1.8`。 |

**Is this reasonable? / 这样是否合理？**  
Yes for a **pre-release personal milestone trail**: each branch freezes a readable snapshot you can check out later.  
可以：适合「尚未上架」时用分支当里程碑快照，方便以后回看。  

Trade-off: GitHub’s usual default is a long-lived `main`; here milestones are the branches themselves. Keep one “current work” branch checked out locally; do not rewrite history on older `v0.*.*` branches.  
代价：和常见的长期 `main` 不同。本地只在「当前工作」分支上继续改；**不要**改写旧里程碑分支的历史。

---

## Current branches / 当前三分支备注

### `v0.0.1` (was `main`)

**English**  
Earliest engineering baseline after the initial ApiRelay app + Spec Kit tooling landed. Almost no product specs/playbooks yet. Use when you need “empty-ish project before the big spec write-up.”

**简体中文**  
最初工程基线：ApiRelay 应用骨架与 Spec Kit 工具已就位，但产品规格/playbook 基本还没有。需要回到「大规格撰写之前的工程起点」时用这个分支。

| | |
|--|--|
| Tip commit | `2cf6803` |
| Role | Planning stage, revision 1（规划阶段 · 第 1 次落盘） |

---

### `v0.0.2` (was `archive/baseline-20260804`, cutoff 2026-08-04 20:47 +0800)

**English**  
Frozen snapshot **before** the implement-playbooks conversation. Contains ROADMAP, `001-key-vault` specs (spec/plan/tasks/…), constitution updates, and Cursor rules. No `specs/playbooks/` and no Phase 1 scaffold code. This is the “design/spec complete, implementation playbooks not started” bookmark.

**简体中文**  
上一对话（约 20:47）**之前**冻住的快照。含 ROADMAP、`001-key-vault` 全套规格、宪法修订、Cursor 规则。**不含** `specs/playbooks/`，也**不含** Phase 1 脚手架代码。相当于「规划/规格已定稿，实现提示词与写码尚未开始」的书签。

| | |
|--|--|
| Tip commit | `a62244d` |
| Role | Planning stage, revision 2（规划阶段 · 第 2 次落盘） |

---

### `v0.1.1` (was `001-key-vault`, current work)

**English**  
Start of **product stage 1** (key vault). Adds implement playbooks under `specs/playbooks/` plus early Phase 1 engineering scaffold (Shared/DTOs, entitlements, empty tests, etc.). Continue Phase work here; when a Phase checkpoint passes, bump the 3rd digit (e.g. finish Phase 2 → push `v0.1.2`) per playbook `15-phase-push.md`.

**简体中文**  
**产品第 1 大阶段**（密钥保险库）的起点。新增 `specs/playbooks/` 实现提示词，以及 Phase 1 早期工程脚手架。后续 Phase 在此线上推进；某 Phase 的 Checkpoint 通过后，按 playbook 的 `15-phase-push.md` 把第 3 位加一并上传（例如 Phase 2 完成 → 推送 `v0.1.2`）。

| | |
|--|--|
| Tip commit | `d1be607`（含 BRANCHES / playbook 上传流程；此前脚手架为 `c83f213`） |
| Role | Product stage 1, revision/Phase checkpoint 1（大阶段 1 · 小阶段/修订 1） |

---

## Lineage / 演进关系

```text
v0.0.1  (engineering baseline)
  └── v0.0.2  (specs & planning freeze @ 20:47)
        └── v0.1.1  (playbooks + Phase 1 scaffold)  ← current
              └── v0.1.2 … v0.1.8  (future Phase checkpoints)
```

---

## How to write future branch notes / 以后怎么写分支备注

When creating or pushing a milestone branch, update **this file** with a new section:

1. **English** — 2–4 sentences: what changed, what is *not* included, when to check it out.  
2. **简体中文** — same content, plain language.  
3. Tip commit hash + role in the `vX.Y.Z` scheme.

Prompt templates live in each playbook folder: `05-annotate-branch.md` and `15-phase-push.md`.
