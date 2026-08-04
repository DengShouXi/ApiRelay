# Git Branch Ledger / 分支台账

**按你的命名（第三层也是分支，不是 tag）。**  
产品范围仍以 [ROADMAP.md](../ROADMAP.md) 为准。

---

## 命名（你的规则）

```text
v0                        ← 未上架（概念，可不建分支）
├── 分支 v0.0             ← 规划大阶段
│   ├── 分支 v0.0.1
│   └── 分支 v0.0.2
├── 分支 v0.1             ← 产品大阶段 1（密钥库）工作线
│   ├── 分支 v0.1.1       ← 小阶段 1 检查点（当前）
│   ├── 分支 v0.1.2       ← 小阶段 2（做到再创建/推送）
│   └── …
├── 分支 v0.2             ← 做到再创建
└── 分支 v0.3
    （无 v0.4）
```

| 层 | Git 对象 | 例子 |
|----|----------|------|
| 未上架 | 概念 / 可选 | `v0` |
| 大阶段 | **分支** | `v0.1` |
| 小阶段 | **分支** | `v0.1.1` |

上传小阶段时：推送到 **`v0.1.N`**；可同时把 `v0.1` fast-forward 到同一提交。

---

## English notes / 简体中文备注

### `v0.0` / `v0.0.1` / `v0.0.2`

**English**  
Planning line. `v0.0.1` = earliest engineering baseline (`2cf6803`). `v0.0.2` = specs freeze before playbooks (`a62244d`).  

**简体中文**  
规划线。`v0.0.1` 最早工程基线；`v0.0.2` 为 20:47 前规格冻住点。

### `v0.1`（大阶段工作线）

**English**  
Stage-1 tip; keep it equal to the latest finished small-stage branch when you sync.

**简体中文**  
大阶段 1 尖端；每完成一个小阶段，可把本分支 merge/快进到最新 `v0.1.N`。

### `v0.1.1`（当前小阶段 · Phase 1）

**English**  
Phase 1 checkpoint branch: playbooks (implement + per-phase save prompts), test folder layout under `ApiRelayTests/V1/…`, gitignore for build/DebugScratch. Upload target for “Phase 1 done” saves.

**简体中文**  
Phase 1 小阶段分支：实现/保存提示词已统一；测试按 `ApiRelayTests/V1/Phase01_Setup/` 隔离；构建与 DebugScratch 不上传。当前改动应落在本分支。

| | |
|--|--|
| Tip | 以 `origin/v0.1.1` 为准 |

---

## 测试隔离

正式代码：`ApiRelay/ApiRelay/`  
阶段测试：`ApiRelay/ApiRelayTests/V{大阶段}/Phase{小阶段}_*/`（见该目录 README）  
本地乱写：`ApiRelay/DebugScratch/`（gitignore，不上传）

Playbook：每个小阶段用 `phases/P0N-save.md` 推到对应 **`v0.Y.N` 分支**。
