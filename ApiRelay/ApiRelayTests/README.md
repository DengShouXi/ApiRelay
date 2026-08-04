# ApiRelayTests — 测试与正式代码隔离

## 原则

1. **正式 App 代码**只在 `ApiRelay/ApiRelay/`（Business / Data / UI / Shared…）。  
2. **单元测试**只在本目录 `ApiRelay/ApiRelayTests/`。  
3. **临时调试/一次性脚本**放 `ApiRelay/DebugScratch/`（已 gitignore，**不会上传**）。  
4. 上传小阶段分支时：只提交「本 Phase 对应子目录」里的测试，避免把别的 Phase 或 DebugScratch 塞进去。

## 与小阶段一一对应（V1）

| 小阶段分支 | 测试目录 | 说明 |
|------------|----------|------|
| `v0.1.1` | `V1/Phase01_Setup/` | 工程/测试 target 冒烟 |
| `v0.1.2` | `V1/Phase02_Data/` | Keychain / SwiftData |
| `v0.1.3` | `V1/Phase03_Vault/` | 门闩 / 保管 |
| `v0.1.4` | `V1/Phase04_Grouping/` | 分组计数 |
| `v0.1.5` | `V1/Phase05_Entitlement/` | 内购权益 |
| `v0.1.6` | `V1/Phase06_Settings/` | 设置 / 清除数据 |
| `v0.1.7` | `V1/Phase07_Catalyst/` | Catalyst 相关（可空） |
| `v0.1.8` | `V1/Phase08_Security/` | 安全回归（可空） |

V2 / V3 同理：`V2/Phase0N_*`、`V3/Phase0N_*`（目录已预建，做到再写测试）。

## 和 tasks.md 的关系

`tasks.md` 里的文件名（如 `KeychainStoreTests.swift`）请**放到对应 Phase 子目录**，不要堆在 `ApiRelayTests/` 根下，以免后期删改时和别的阶段搅在一起。

Xcode：把新测试文件加入 `ApiRelayTests` target 即可；目录分组不影响编译，但方便你按阶段清理。
