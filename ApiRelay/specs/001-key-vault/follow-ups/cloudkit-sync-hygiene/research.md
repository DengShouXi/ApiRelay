# Research: CloudKit 同步卫生后续

**Date**: 2026-09-10  
**Feature**: `001-key-vault/follow-ups/cloudkit-sync-hygiene`

## 1. CloudKit 不能给业务字段加唯一约束

这是平台限制，不是部署配错。SwiftData 同步时每条本地对象对应系统记录名，不是业务 `id`。两台设备几乎同时写出同一账号，云端会留下两行。

**决策**：继续在应用层处理。禁止 `@Attribute(.unique)`，禁止改控制台「部署模式」当消重。

## 2. 导入发生在启动清扫之后

`CloudKitSyncMonitor.applyPipelineEvent` 在 **import 成功结束**时已发 `apiRelayCloudMetadataDidImport`。启动清扫走 `KeyVaultService.performStartupMaintenance` + `ConsumerToolService.ensurePresetsSeeded`（首页 `onAppear`）。时序上导入经常更晚。

**决策**：监听该通知，用合并窗口（建议 1–2 秒）再跑同一套 `pruneDuplicateIdentities`。写入走现有仓库，MUST NOT 在 MainActor 上 `await` CloudKit/SwiftData save（见宪法 / `architecture-boundaries`）。调度对象放 Business，由 `AppEnvironment` 在非测试路径启动。

## 3. 打平不删 vs replicaSeed

没有跨设备可见的「哪一行是哪一行」标识时，两台设备对完全相同的两行可能各删对方。

**决策**：短期保持打平不删。长期加 additive `replicaSeed: UUID`（插入生成、永不改）。旧行 nil 时本机补种一次。发出该字段前 Production additive Deploy。**当前热修不做 schema 变更。**

## 4. 不字段合并

宪法 IX：不得编造数据。把两边备注拼成一句是编造。

**决策**：展示类标量整行 LWW。指派表继续组合去重并集。不做三路 merge。`UserPreferences` 无 `updatedAt`，13.5 只读折叠、写打全，不物理删。

## 5. 指纹地区

`String(format: "%.6f", …)` 与 `String(describing: Decimal)` 都可能随 Locale 变化。

**决策**：时间用 `timeIntervalSince1970` 的整数微秒（不含小数点，与 Locale 无关）。Decimal 用 `NSDecimalNumber.description(withLocale: en_US_POSIX)`。

## 6. insert 语义

备份需要幂等；用户新增需要「写进去或报错」。

**决策**：拆 `insertIfAbsent`（仅备份，已存在返回 false）与普通 `insert`（id 碰撞抛 `validationFailed(field: "id", reason: "already_exists")`）。产品「添加」路径继续自己生成 UUID。

## 7. 规格该放哪

`specs/004-*` 会占 Stage2/3 功能号；`phases/P14-*` 会像下一个产品小迭代 `v1.14`。热修禁止开新 P0N。

**决策**：规格挂 `001-key-vault/follow-ups/`；实现提示词与 `热修-save.md` 并列，不叫 P14。
