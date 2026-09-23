# Requirements Review Checklist

**Status**: plan-only；未经 G1/G3F 批准不得勾作实施完成或交给自动执行。

## 范围与权威

- [ ] v1.14 被明确为 Stage 1 同步架构维护；产品 V2 仍是 2.0 用量看板。
- [ ] v1.13.9 已关账；v1.13.10 已只做结构稳定化并完成真正 XCUITest、授权上传和远端复核；其 closure SHA 是 v1.14 唯一基线。
- [ ] parked v1.14 已经另行授权后纯 fast-forward 到 v1.13.10 closure SHA；不能纯快进时已停止而非 reset/recreate/force。
- [ ] 旧 cloudkit-sync-hygiene 保留为 legacy 包，T006/T008 处置明确。
- [ ] ROADMAP、constitution、spec、research、plan、data-model、interfaces 的回写清单获批。
- [ ] 本次授权明确到 gate，没有用“执行计划”一次性授权不可逆 cleanup。

## 产品语义

- [ ] 同步状态分清本机、outbox、CloudKit、当前设备和其他设备。
- [ ] 没有固定同步时限承诺。
- [ ] 应用密码、设备验证、Recovery Key、备份口令四者语义不混淆。
- [ ] 无可信设备且无 Recovery Key 的不可恢复结果已由用户批准。
- [ ] 设备撤销与远程清除的能力上限已披露。
- [ ] metadata leakage 已列明，没有“零元数据”夸大。
- [ ] 后台只传密文；未来管理凭据自动读取另作裁决。
- [ ] 控制管理员权已在 1-of-N 单签与 quorum 之间明确裁决；正常轮换、撤销、Recovery Credential 替换、compromise replacement 及单设备/Recovery-only 逃生门槛均无默认空白。
- [ ] “不验证”是否仍强制高风险 `deviceOwnerAuthentication` 已裁决；如改变现行 FR-061/SC-014/接口，已先完成获授权的权威回写，而不是由下位合同偷改。
- [ ] routine rotation 与 compromise replacement 已被命名并分开验收；用户明确知道旧 VRS 仍可解其此前取得的兼容 ciphertext/wrapper，既有明文不可追回。
- [ ] FR-061 已明确映射为 content wipe 或 vault reset；vaultID、Recovery Credential、device identities 与最小 anti-replay/retirement tombstone 的去留均经产品批准，“零残留”和“防旧副本复活”没有被同时虚假承诺。
- [ ] 无 Secure Enclave 设备已明确选择“拒绝受控保险库”或“允许 `softwareExportable` P-256 fallback”；支持设备清单、用户可见降级和迁移/备份边界一致。

## 数据正确性

- [ ] 核心记录不被 SwiftData 自动 CloudKit 和 CKSyncEngine 双重管理。
- [ ] 本机投影、envelope、mutation、outbox 同事务。
- [ ] mutation 幂等、因果 revision、冲突 sibling、墓碑和 `eraseEpoch` 均有契约。
- [ ] 设备时间不是唯一冲突依据。
- [ ] product recycle bin 与 sync tombstone 生命周期分开。
- [ ] change token 过期、zone 删除、账号切换不会用空数据覆盖良好数据。
- [ ] old client、非 active `generation`、低 `eraseEpoch`、旧 `writeKeyEpoch` 写入不能进入当前投影；`acceptedReadKeyEpochs` 不恢复写权。
- [ ] `generation`、`eraseEpoch`、唯一 `writeKeyEpoch` 与 `acceptedReadKeyEpochs` 分别定义、分别签名/持久化；任一项变化不会被实现误推断为其余三项变化。

## 迁移

- [ ] 影子复制、增量捕获、final delta 和 cutover write gate 均有方案。
- [ ] waiting secret、orphan、duplicate、soft-deleted、corrupt 均有分类。
- [ ] 核对不持久化 secret hash/长度/末位。
- [ ] controlled-only mutation 后的 forward-only 边界清楚。
- [ ] 旧备份格式兼容期明确。
- [ ] 删除旧 Keychain 明文是最后一步、单独授权。
- [ ] 清除/重置迁移记录携带四类 source/target 值与获批模式；content wipe 不冒充 FR-061 vault reset，vault reset 不错误复用旧 vault/device/recovery identity。
