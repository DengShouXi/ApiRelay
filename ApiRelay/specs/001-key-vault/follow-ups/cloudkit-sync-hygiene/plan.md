# Implementation Plan: CloudKit 同步卫生后续

**Branch**: 文档挂在 `001-key-vault/follow-ups/cloudkit-sync-hygiene`；代码在 Git 热修 **`v1.13.5`**  
**Date**: 2026-09-10  
**Spec**: [spec.md](./spec.md)

**Input**: [spec.md](./spec.md) · [research.md](./research.md) · 已落地的 `SyncedIdentity` / 三仓库 `pruneDuplicateIdentities`

## Summary

把「启动时清扫一次」补成「启动 + CloudKit 导入成功后合并再清」；指纹改成 POSIX；新增与幂等导入拆开；同步单例同样折叠。`replicaSeed` 等 CloudKit schema 变更**现在不做**。不撤已落地的读去重 / 写打全。关账依赖双设备手测，不单靠单测。

## Technical Context

**Language/Version**: Swift 6  
**Primary Dependencies**: SwiftData, CloudKit（`NSPersistentCloudKitContainer` 事件已由 `CloudKitSyncMonitor` 收口）  
**Storage**: 同步 SwiftData 容器；Keychain 明文本功能不碰  
**Testing**: XCTest 内存容器 + 发 `apiRelayCloudMetadataDidImport`；真 CloudKit 只高手测  
**Target Platform**: iOS 18 / Mac Catalyst 15  
**Project Type**: 移动 + Catalyst App  
**Constraints**: 默认 MainActor；同步库写入不得在界面线程干等；CloudKit schema 只允许 additive  
**Scale/Scope**: 账号 / 使用方 / 密钥 / 指派 / 偏好单例

## Constitution Check

- 明文不进 SwiftData / 日志 / `@Published`。本功能只动元数据重复行。
- UI 不碰 `ModelContext`。清扫留在仓库 / Vault 启动与导入路径。
- 不给同步模型加 `@Attribute(.unique)`。
- `replicaSeed` 若做：Production additive Deploy 后再发含该字段的包（FR-063）。现在不做。
- 字段取舍不拼接备注（宪法 IX）。

通过。无 Complexity Tracking 例外。

## Project Structure

### Documentation (this feature)

```text
specs/001-key-vault/follow-ups/cloudkit-sync-hygiene/
├── spec.md
├── plan.md
├── research.md
├── tasks.md
└── quickstart.md
```

实现提示词：`specs/playbooks/热修-CloudKit同步卫生.md`（与 `热修-save.md` 并列，**不要叫 P14**）  
手测：`specs/playbooks/热修-CloudKit同步卫生-验收清单.md`

### Source Code（已有，本功能在其上补）

```text
ApiRelay/ApiRelay/Shared/SyncedIdentity.swift
ApiRelay/ApiRelay/Shared/IdentityHygieneScheduler.swift
ApiRelay/ApiRelay/Data/SwiftData/SyncedReplicaPruning.swift
ApiRelay/ApiRelay/Data/SwiftData/CloudKitSyncMonitor.swift   # 已有导入成功通知
ApiRelay/ApiRelay/Data/SwiftData/Repositories/*Repository.swift
ApiRelay/ApiRelay/Business/Vault/KeyVaultService.swift
ApiRelay/ApiRelay/Business/Vault/ConsumerToolService.swift
ApiRelay/ApiRelay/Business/Vault/CloudImportIdentityHygiene.swift
ApiRelay/ApiRelay/Business/System/SecureBackupService.swift
ApiRelay/ApiRelayTests/V1/Phase02_Data/
ApiRelay/ApiRelayTests/V1/Phase06_Settings/
```

**Structure Decision**: 不新建模块。清扫调度放 Business，比较规则留 Shared，持久化留 Data 仓库。

## 实现时禁止

- 改 `001-key-vault/tasks.md` 的 T065 或把它勾掉冒充本功能完成。
- 把本功能写成 `specs/004-*` 或 `phases/P14-*`（004 是 V2 坑位；P14 会像 `v1.14`）。
- 用 `P14-save.md` 冒充新 Phase；做完走 `热修-save.md`。
- 未 Production Deploy 就加 `replicaSeed` 并发商店包。
