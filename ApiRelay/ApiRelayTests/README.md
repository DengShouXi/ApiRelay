# ApiRelayTests — 测试与正式代码隔离

## 原则

1. **正式 App 代码**只在 `ApiRelay/ApiRelay/`。  
2. **单元测试**只在本目录；与小迭代分支一一对应。  
3. **临时调试**放 `ApiRelay/DebugScratch/`（gitignore，不上传）。  
4. **每个小阶段写完都要上传对应分支**；只把「本迭代测试目录」一并提交。

## 对应表

### V0 规划（`plan.N`）

| 分支 | 目录 |
|------|------|
| `plan.1` | `V0/Phase01_Baseline/` |
| `plan.2` | `V0/Phase02_SpecsFreeze/` |
| `plan.3` | `V0/Phase03_PlanningExtra/` |

### V1 密钥库（`v1.N`）

| 分支 | 目录 |
|------|------|
| `v1.1` | `V1/Phase01_Setup/` |
| `v1.2` | `V1/Phase02_Data/` |
| `v1.3` | `V1/Phase03_Vault/` |
| `v1.4` | `V1/Phase04_Grouping/` |
| `v1.5` | `V1/Phase05_Entitlement/` |
| `v1.6` | `V1/Phase06_Settings/` |
| `v1.7` | `V1/Phase07_Catalyst/` |
| `v1.8` | `V1/Phase08_Security/` |
| `v1.9` | `V1/Phase09_UXHardening/` |
| `v1.10` | （UI 重设计；人工验收见 `P10-验收清单.md`） |
| `v1.11` | `V1/Phase11_AppIconAssets/`（AppSymbols / iconSymbol 回填；人工验收见 `P11-验收清单.md`） |

**上架**：Stage1→`1.0.0` / Stage2→`2.0.0` / Stage3→`3.0.0`（见 `BRANCHES.md`）。旧分支名 `v0.1.N` ≡ `v1.N`。

V2 / V3：`V2/Phase0N_*`、`V3/Phase0N_*`（预建，做到再写）。

`tasks.md` 里的测试文件名请落到对应 Phase 子目录，勿堆在 `ApiRelayTests/` 根下。
