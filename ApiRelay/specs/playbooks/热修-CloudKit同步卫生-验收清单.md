# 热修验收清单 — CloudKit 同步卫生

**谁勾**：双设备 / 真 iCloud 项 = 产品负责人。Agent 只勾能在内存单测证明的项。  
**关账**：本页双设备表 + `001-key-vault/follow-ups/cloudkit-sync-hygiene/tasks.md` 的 T008 都勾完，才能说本功能关账。

规格：[`../001-key-vault/follow-ups/cloudkit-sync-hygiene/`](../001-key-vault/follow-ups/cloudkit-sync-hygiene/) · 实现提示词：[`热修-CloudKit同步卫生.md`](./热修-CloudKit同步卫生.md)

## Agent 可证（单测 / 构建）

命令（Spec Kit 根目录 `ApiRelay/`）：

```bash
xcodebuild -scheme ApiRelay -destination 'platform=macOS,variant=Mac Catalyst' -derivedDataPath /tmp/ApiRelayAgentDD test
```

记录：2026-09-10，**Executed 204 tests, with 0 failures**，`TEST SUCCEEDED`。另 `bash ApiRelay/scripts/selfcheck.sh` 红线通过。

- [x] Mac Catalyst 全量测试绿（独立 DerivedData `/tmp/ApiRelayAgentDD`）— 204 tests, 0 failures（2026-09-10）
- [x] 指纹在 POSIX / 整数微秒下不含地区小数点；`Decimal` 不用当前 Locale（`SyncedIdentityTests`）
- [x] 导入成功通知后清扫会跑，且短时间连发只跑一次（`IdentityHygieneSchedulerTests`）
- [x] 备份再导入跳过已有 id；普通 insert 撞 id 不再静默成功（`SwiftDataRepositoryTests`）
- [x] 清扫逐步隔离：前一步失败不阻止后续类型（`testRunIsolatedContinuesAfterAStepFails`）
- [x] 偏好冲突行读取折叠、写入打全、13.5 物理清扫后行数不变（`testUserPreferencesDuplicateRowsReadWinnerAndWriteAll`）
- [x] 错误类型名不含 `userInfo` / 文案（`testErrorTypeNameOmitsUserInfoAndDescription`）

## 产品负责人 · 双设备 CloudKit（同一 iCloud）

- [ ] 离线在一台导入备份，恢复网络后两台都不崩；重复业务 id 最终规范成一条（或仅余打平克隆且界面仍一条）
- [ ] 两台几乎同时改同一账号的不同字段：结果符合整行 LWW；不崩；没有「改了没保存」的幽灵行
- [ ] 一台删除账号后，另一台先离线再上线：不得稳定「删了又出现」；若短暂出现，导入成功后的清扫能收掉
- [ ] 连续重启两次，首页账号/密钥条数稳定
- [ ] 搜索重复账号名称不崩
- [ ] （仅 T006 Deploy 并发包之后）完全相同的双行会在清扫后变成一行

## 未勾时的结论

机器项已过。双设备项未勾 = **不能**宣布同步卫生关账。下一步：Archive **1.0.1 (7)**（(6) 已被 9 月 9 日那包占用；时长 JSON 已在 Production）→ T008。`replicaSeed` / T006 仍跳过。
