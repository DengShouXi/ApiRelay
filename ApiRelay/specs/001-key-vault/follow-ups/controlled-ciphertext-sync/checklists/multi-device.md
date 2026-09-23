# Multi-Device Acceptance Checklist

**Status**: plan-only；只能用当前构建身份和真实设备证据勾选。

> 必须由真实设备完成；模拟通知和内存容器不能勾选。

## 基础同步

- [ ] iPhone → iPad 新增/修改/删除。
- [ ] iPad → Mac 新增/修改/删除。
- [ ] 自动调度与手动 send/fetch 分别验证。
- [ ] UI 的 local/queued/cloud accepted/device ack 与日志证据一致。

## 并发与离线

- [ ] 两台离线修改同一密钥内容，两份均保留为 conflict siblings。
- [ ] 不同普通字段并发按契约合并。
- [ ] 编辑 vs 删除不会自动复活。
- [ ] 指派 add vs remove 符合 remove-wins。
- [ ] 设备时钟相差 24 小时不改变结果。
- [ ] 一台离线至少 72 小时后上线仍正确收敛。
- [ ] 推送缺失/合并后主动 fetch 可恢复。

## 设备与恢复

- [ ] 可信设备批准新设备。
- [ ] 重复/过期/伪造加入请求被拒。
- [ ] 只有 Recovery Credential 的新设备恢复；专用 admission proof、固定 RecoveryAuthority 与旧快照提示正确。
- [ ] 重装产生新 device identity，不复用丢失 key。
- [ ] 撤销设备后新 `writeKeyEpoch` 与 roster transition 生效，旧 signer/旧 `writeKeyEpoch` 写入不进入投影。
- [ ] root rotation 在中途杀进程后恢复。
- [ ] 轮换中加入新设备可获得全部 `acceptedReadKeyEpochs`；新写只使用当前唯一 `writeKeyEpoch`。

## CloudKit 异常

- [ ] 未登录、退出、切换账号、切回。
- [ ] 网络断开、限流、配额不足、部分失败。
- [ ] change token expired 全量重建。
- [ ] active zone missing 不会自动重建旧世界。
- [ ] 单条/批次超限给出准确错误。

## 清除与迁移

- [ ] erase 后旧离线设备重连，非 active `generation`、低 `eraseEpoch`、旧 `writeKeyEpoch` 写入不复活。
- [ ] logical complete、cloud old-zone deletion observed、active registered devices ack 分开显示；从不声称未知离线设备已物理清除。
- [ ] 接收端看到更高 `eraseEpoch` 时先 durable journal/封写，再清旧 outbox/inbox/投影/key cache，按 D16 获批模式重建或退出为未配置后才回执。
- [ ] shadow copy 与增量捕获一致。
- [ ] 元数据先到、Keychain secret 后到时，重复 reconciliation 最终补齐且不把暂缺当损坏。
- [ ] 两台设备同 logical ID 持有不同 legacy secret 时生成 conflict siblings，不静默覆盖。
- [ ] cutover manifest CAS 前 crash 能回 legacy；CAS 结果未知按 cutoverID 重读。
- [ ] required participants 全部在同一 CutoverBarrier 上签名 Ready；一台离线、双 coordinator、用户排除设备与 abort/release 都不会双切换或提前解封。
- [ ] controlled-primary manifest CAS 成功后只走前滚恢复，即使本机尚未产生 controlled-only mutation。
- [ ] erase/cutover/rotation/revoke/cleanup 同时发起时只有一个 ControlOperation 获得 CAS；其他操作按优先级拒绝、abort 或 rebase。
- [ ] legacy plaintext cleanup 后迟到旧 Keychain item 被隔离/清理。
- [ ] legacy CloudKit metadata cleanup 后迟到旧记录被隔离/清理，不复活。
- [ ] 每个已登记参与设备提交签名 cleanup checkpoint；UI 不把这些回执扩大为未知离线安装已物理删除。
- [ ] active generation 出现裸 CloudKit physical delete 时保留最后良好投影并隔离；只有签名 tombstone 改变业务可见性。
- [ ] 接收 higher eraseEpoch 后同时停止/清理或隔离 legacy Keychain、local-fallback 与旧 metadata source，不只隐藏 controlled 投影。

## 平台

- [ ] iPhone 真机。
- [ ] iPad 真机。
- [ ] Mac Catalyst。
- [ ] 原生 macOS（若产品仍支持该运行形态/测试宿主）。
- [ ] iPhone↔iPad、iPhone↔原生 macOS、iPad↔Mac Catalyst 三组双向矩阵；删掉某形态必须先有产品裁决。
- [ ] Secure Enclave 可用路径。
- [ ] D17 选择拒绝时，无 Secure Enclave 真机创建/加入受控保险库会失败关闭并给出准确说明；D17 选择 fallback 时，才测试经批准的 Data Protection Keychain `ThisDeviceOnly`/`softwareExportable` 路径。两者不得同时假设已批准。
