# V1 · Phase 2 — Data 层（实现提示词）

把下面整段复制给 Cursor，一次只做这一阶段。

---

请**只实现 V1 Phase 2（Data 层）**。不要实现门闩 UI、列表 UI、StoreKit 等 Phase 3+ 内容。

## 必读

- `tasks.md` → **Phase 2**（T010–T014b）
- `data-model.md`（十个实体、§7.1 CloudKit）
- `contracts/`（KeychainStoring、Repository 边界）
- `research.md` §1（ACL 与 synchronizable 互斥）

## 本阶段要点

- `KeychainStore` 必须是 **`actor`**；三类 Service（keys / admin / masterpw）
- **禁止** `kSecAttrAccessControl`；用单测固化「ACL + synchronizable 会失败」
- 十个 SwiftData 实体一次建齐；`APIKeyRecord` 无 `consumerToolId`；外观/默认视角在 `DevicePreferences`
- 双 `ModelConfiguration`（synced + local）
- V1 Repository + `PresetCatalog` 常量
- **T014b 硬门槛**：CloudKit Dashboard 把 schema **Deploy to Production**，并核对 §7.1

## 硬约束

- Data 层不得依赖 SwiftUI；不得向上层泄露 `ModelContext`。
- 完成后勾选 `tasks.md`；`xcodebuild test` 全绿。
- **未完成 T014b MUST NOT 进入 Phase 3。**

汇报：Checkpoint 2 是否通过（含 Production schema 证据说明）。
