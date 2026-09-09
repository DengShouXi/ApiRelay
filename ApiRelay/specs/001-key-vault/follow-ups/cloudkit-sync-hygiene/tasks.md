# Tasks: CloudKit 同步卫生后续

**Input**: [plan.md](./plan.md) · [spec.md](./spec.md) · [research.md](./research.md)

**Git**：现行热修分支。保存走 `specs/playbooks/热修-save.md`，不要开 `P14-save` 冒充新 Phase。

路径相对 Spec Kit 根目录 `ApiRelay/`。

---

## Phase 1: 指纹与导入后再清（P1，先做）

- [x] **T001** [P] [US4] 改 `ApiRelay/Shared/SyncedIdentity.swift`：`dateStamp` / Decimal 指纹改 POSIX（整数微秒 / `en_US_POSIX`），禁止当前 Locale 的 `String(format:)` / `String(describing:)`。单测钉死输出。文件：`ApiRelayTests/V1/Phase02_Data/SyncedIdentityTests.swift`。
- [x] **T002** [US1] 在 Business 调度对象监听 `Notification.Name.apiRelayCloudMetadataDidImport`，合并延迟 1–2 秒后再调用已有 `pruneDuplicateIdentities`。MUST NOT 在 MainActor 上 `await` 同步库 save。测试：短时间连发只清扫一次。
- [x] **T003** [P] [US6] 写手测项进 `specs/playbooks/热修-CloudKit同步卫生-验收清单.md`：离线导入、双机同时改、删除后旧机上线、连续重启。Agent 勾不了这些框。

**Checkpoint 1**：指纹单测绿；导入通知触发的清扫有单测；手测清单在仓库里。此时仍不能关账。

---

## Phase 2: API 语义与冲突表（P2）

- [x] **T004** [US5] 拆仓库 API：普通 `insert` 遇到已有业务 `id` 抛 `already_exists`（项目既有 `validationFailed`）；备份走显式 `insertIfAbsent`。改 `UpstreamAccountRepository` / `ConsumerToolRepository` / `APIKeyRecordRepository` 与 `SecureBackupService.applyVaultJSON`。补单测：用户路径碰撞失败；导入跳过。
- [x] **T005** [P] [US3] 在 `001-key-vault/data-model.md` 的「重复行」段补一张**字段取舍表**（整行 LWW、备注不拼接、指派并集）。不新写合并引擎。冲突样例单测锁住「较新行的备注胜、较旧行独有头像丢弃」。

**Checkpoint 2**：备份再导入仍幂等；误用 insert(id:) 不再静默成功。

---

## Phase 3: 真克隆与单例（P2 / P3，可后做）

- [ ] **T006** [US2] 给 `UpstreamAccount` / `ConsumerTool` / `APIKeyRecord` 增加 additive `replicaSeed: UUID?`（默认 nil）。插入时生成。清扫在业务字段打平时用 `replicaSeed` 字典序较小者胜。**发含该字段的包前** CloudKit Production additive Deploy。旧行 nil → 本机补种一次且永不更换。**当前热修不做。**
- [x] **T007** [US7] `UserPreferencesRepository` / `EntitlementSnapshotRepository` 复用读去重 / 写打全。`fetchLimit = 1` 改为全量再选赢家。`UserPreferences` **13.5 不物理删冲突行**（无 `updatedAt`）。`EntitlementSnapshot` 有 `updatedAt`，可分出输家才删。`DevicePreferences` 本轮不改。

**Checkpoint 3**：schema 已 Deploy 才能把 T006 标完成；单例双行单测绿。

---

## Phase 4: 关账闸门

- [ ] **T008** [US6] 产品负责人按验收清单完成双设备 CloudKit 手测并勾选。全量 `xcodebuild test`（Mac Catalyst，独立 DerivedData）绿。本条未勾 = 本功能未关账。

依赖：T001–T002 建议先于 T006。T004 不依赖 T006。T008 最后。
