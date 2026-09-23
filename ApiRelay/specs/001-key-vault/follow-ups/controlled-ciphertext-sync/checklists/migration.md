# Migration and Rollback Checklist

**Status**: plan-only；只有真实 gate 获批并有证据时才能勾选。

## Preflight

- [ ] v1.13.9 与 v1.13.10 closure SHA 均已记录；v1.14 精确基于后者。Bundle ID、Team ID、Keychain group、iCloud container、store paths 已记录。
- [ ] legacy WAL/erase journal/quarantine 无未完成状态。
- [ ] 当前 vault 加密备份 round-trip 通过。
- [ ] Recovery Credential 可用并完成一次恢复演练；control zone 丢失时 Recovery Kit/不可恢复边界已裁决。
- [ ] pre-cutover disable 与 post-cutover pause 分离；后者不能恢复 legacy 真相源。
- [ ] Development 真机矩阵已完成，Production 未提前切换。

## Shadow

- [ ] 全量扫描闭合图，不只迁移 APIKeyRecord。
- [ ] 每项进入唯一分类。
- [ ] secret 只在内存核对，无持久 hash/长度/末位。
- [ ] shadow 期间增量写不会遗漏。
- [ ] 已考虑 iCloud Keychain 无逐条到达通知：启动/前台/元数据导入/手动/cutover 前会重复 reconciliation。
- [ ] LegacyParticipant set revision 已冻结；每台签名 inventory 包含 mirrored/local-fallback 模式、metadata candidates 和 secret availability，未上线设备已逐项处置。
- [ ] 两台设备记录数、逻辑 ID、关系、删除态和可解密内容一致。
- [ ] waiting/orphan/conflict/corrupt 均为 0 或有明确用户处置。

## Cutover

- [ ] write gate 先持久化，再等待旧事务结束。
- [ ] final delta 与最后核对通过。
- [ ] 每个真实 Production vault 自己达到 productionShadowVerified；Development/其他 vault 结果不代替。
- [ ] productionShadowVerified 已绑定 account/vault、control head、四类世代、participant-set revision、data frontier 与 graph digest；绑定项变化会强制失效。
- [ ] CutoverBarrier 明确列出 required participants；每台设备已在 durable gate、final reconciliation 后提交同一 barrier 的签名 Ready。
- [ ] 离线设备只经用户逐台排除，并重建 participant revision、shadow checkpoint 和 barrier；没有在原 barrier 静默缩小集合。
- [ ] manifest 接受 controlledPrimary + cutoverID + fencing revision 的 CAS 是唯一全局 PONR；结果未知会按同一 ID 重读。
- [ ] erase/rotation/revoke/cleanup 与 cutover 的 ControlOperation CAS 竞争、优先级和 abort/rebase 已演练。
- [ ] 本机只在观察到该 control head 后切 routing；PONR 后无论是否产生本机新写都只前滚。
- [ ] 旧客户端写入只隔离、不自动采纳。
- [ ] cutover 每个持久点都做过 crash/restart。

## Observation and cleanup

- [ ] 满足已批准的版本数与时间窗口。
- [ ] 长期离线设备、重装、账号切换、撤销、轮换、清除均实测。
- [ ] active device checkpoints 达标；失联设备由用户显式撤销。
- [ ] DeviceCheckpoint 的 data frontier/root 可验证，不是更新时间或自报计数。
- [ ] conflict/quarantine/waiting secret 清零。
- [ ] 独立迁移审计通过。
- [ ] legacy Keychain 删除得到单独用户授权。
- [ ] legacy CloudKit 明文元数据 records 的删除另获授权并逐 record/zone 观察；schema deprecated 不冒充记录已删。
- [ ] cleanup journal 中断可前滚恢复。
- [ ] migration/cleanup journal 绑定 account/vault/install nonce/control head/participant revision；旧 DataEraseJournal 未被直接当作迁移 journal 复用。
- [ ] 每个 required participant 已签名证明本机 Keychain、local-fallback 和可见 legacy metadata 的精确处置结果；未知离线安装仍明确显示未知。
- [ ] 迟到 synchronizable item 不会复活。
- [ ] 产品/商店声明只在事实切换后更新。
- [ ] 声明只覆盖 CloudKit old-zone 删除观察与 active registered/legacy participant 设备确认，不声称未知离线设备本地副本物理消失。
- [ ] CloudKit 全失恢复只从已验证加密备份建立全新 vault；旧 tag、control head、设备身份、generation/epoch 均未复用。
