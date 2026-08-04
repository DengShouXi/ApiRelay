# ApiRelayTests — 测试与正式代码隔离

## 原则

1. **正式 App 代码**只在 `ApiRelay/ApiRelay/`。  
2. **单元测试**只在本目录；与小迭代分支一一对应。  
3. **临时调试**放 `ApiRelay/DebugScratch/`（gitignore，不上传）。  
4. **每个小阶段写完都要上传对应分支**；只把「本迭代测试目录」一并提交。

## 对应表

### V0 规划（`v0.0.N`）

| 分支 | 目录 |
|------|------|
| `v0.0.1` | `V0/Phase01_Baseline/` |
| `v0.0.2` | `V0/Phase02_SpecsFreeze/` |
| `v0.0.3` | `V0/Phase03_PlanningExtra/` |

### V1 密钥库（`v0.1.N`）

| 分支 | 目录 |
|------|------|
| `v0.1.1` | `V1/Phase01_Setup/` |
| `v0.1.2` | `V1/Phase02_Data/` |
| `v0.1.3` | `V1/Phase03_Vault/` |
| `v0.1.4` | `V1/Phase04_Grouping/` |
| `v0.1.5` | `V1/Phase05_Entitlement/` |
| `v0.1.6` | `V1/Phase06_Settings/` |
| `v0.1.7` | `V1/Phase07_Catalyst/` |
| `v0.1.8` | `V1/Phase08_Security/` |

V2 / V3：`V2/Phase0N_*`、`V3/Phase0N_*`（预建，做到再写）。

`tasks.md` 里的测试文件名请落到对应 Phase 子目录，勿堆在 `ApiRelayTests/` 根下。
