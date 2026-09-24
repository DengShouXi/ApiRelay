# Quickstart: 怎样审查 v1.14 计划（不启动实施）

## 当前能做什么

当前只审查以下内容：

1. [release-sequence.md](./release-sequence.md) 的 `v1.13.9 → v1.13.10 → v1.13.11 → v1.14 → UI` 隔离顺序；`13.11` 只验收购买权益，`v1.14` 仍未获同步实施授权；
2. [spec.md](./spec.md) 的目标、非目标和 G1 产品裁决；
3. [plan.md](./plan.md) 的 G0–G7 顺序；
4. [data-model.md](./data-model.md) 的控制面/数据面/本机模型；
5. [threat-model.md](./threat-model.md) 的安全承诺和完整快照回滚边界；
6. [contracts](./contracts/) 的加密、同步、设备和迁移协议；
7. [decision-log.md](./decision-log.md) 的十七项决定与权威回写账本；
8. [tasks.md](./tasks.md) 的授权边界。

当前不能运行实施命令，不能把本目录传给 Spec Kit implement 或任何 AI 自动执行。它是产品/协议草案，不是固定执行工作包；若未来采用多 AI 实施，须另建或链接符合仓库治理的任务契约、总流程操作台、检查计划和阶段提示词。P0 的“已完成”只表示计划草案已写，不表示架构获批或代码完成。

## 建议审查顺序

先回答 G1 十七个问题：

1. 是否同意把它定为 Stage 1 的 v1.14，而不是产品 V2？
2. 是否接受“不保证固定秒数，只准确显示确认层级”？
3. 应用密码是否继续只作本机门闩？
4. 是否接受“可信设备批准 + 独立 Recovery Key”？
5. 是否接受两者都丢失时不可恢复？
6. 是否同意 Recovery Key 内部采用离线非对称 recovery keypair，使设备无需保存恢复私钥也能为新 VRS 轮换 wrapper？
7. 是否同意 v1.14 后台只同步密文，未来管理凭据后台解密另行设计？
8. 是否同意 CloudKit 明文字段只保留协议、世代、随机 ID 和状态所需的最小集合？
9. 旧版本、legacy participant grace window 至少保留几个版本/多长观察期？
10. 是否接受不新增 transparency 服务，由 CloudKit 提供最新快照、可信设备 checkpoint 做交叉发现？
11. 离线发起“清除全部数据”时，是否接受本机立即不可见并封住新写，联网完成获批清除模式的 `eraseEpoch`/control transition 后才重新开放或进入未配置？
12. 是否接受 Recovery Credential 单独不能在 CloudKit control/data 全失时恢复，v1.14 以已验证加密备份作为灾难恢复前提？
13. 控制管理员权采用任一 active device 单签（1-of-N）还是多设备 quorum；各类 control event 与单设备/Recovery-only 逃生规则是什么？
14. 普通验证方式为“不验证”时，新设备批准、撤销、Recovery Credential 替换、疑似泄露替换和 FR-061 清除/重置是否仍强制设备主人认证？
15. 是否把 routine rotation 与 compromise replacement 分开，并接受旧 VRS 仍可解其此前取得的兼容 ciphertext/wrapper、既有明文不可追回？
16. FR-061 是保留 trust 的 content wipe，还是退休旧 vault、重建 vaultID/Recovery Credential/device identities 的 vault reset；最小 anti-replay tombstone 与零残留如何取舍？
17. 没有 Secure Enclave 的受支持设备是拒绝创建/加入受控保险库，还是允许 Data Protection Keychain 中可由 App 进程导出的软件 P-256 fallback，并把硬件保护降级明确显示、写入 roster 与威胁模型？

产品裁决先写入 `decision-log.md`；随后另行取得权威回写授权，完成回写和一致性复核；再由用户确认最终计划，并只授权一个实施 gate。不能从“同意方向”直接跳到 Swift。

## 正式开工前

- v1.13.9 已完成验收、经用户授权提交/上传、通过独立远程复核，随后才登记关账与精确 closure SHA；
- v1.13.10 结构稳定化已在 `8e6c221` 关账；尚欠的真实系统边界留在发布矩阵，不冒充已测；
- v1.13.11 已单独完成购买权益验收、授权上传及远端复核，记录精确 closure SHA；此前不得把其起点 `8e6c221` 当成同步基线；
- G1 决定、权威回写和一致性复核已分别完成；
- v1.14 经另行授权只向 v1.13.11 closure SHA 纯 fast-forward；若不能纯快进则停止，不 reset/recreate/force；
- 工作树干净且现有用户改动已归属；
- 只为当前 gate 建任务/分支；
- Development/disposable CloudKit 与 Production 分离；
- feature flag 默认关闭；
- 真实数据迁移另行确认。

## 停止规则

出现任一情况立即停止，不继续“试试看”：

- 权威规格与本计划冲突未裁决；
- app password/Recovery Key 角色未定；
- crypto 字节格式没有测试向量；
- Production schema 尚未审查；
- 任何 migration mismatch；
- 任何明文进入日志、SwiftData、outbox 或诊断；
- cutover 后回滚边界无法说明；
- 旧设备写入能进入当前投影；
- 清除状态把逻辑完成误写成物理完成。
