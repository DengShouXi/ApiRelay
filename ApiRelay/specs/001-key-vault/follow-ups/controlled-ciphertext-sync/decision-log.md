# G1 Decision Record: v1.14 受控密文同步

**Status**: 待产品负责人裁决；本文件目前只是记录模板，不代表批准
**Rule**: 一项决定只有在“最终选择、未采用方案、批准证据、权威回写、一致性复核”全部可追溯后才算关闭。

## 1. 当前冲突

| 冲突 | 当前权威/证据 | 候选改变 | 状态 |
| --- | --- | --- | --- |
| 同步阶段归属 | `ROADMAP.md` 的产品 V2 是 2.0 用量看板；现行 key-vault `research.md` 仍把信封加密描述为产品 V2 独立迁移 | 建议把受控密文同步定义为 Stage 1 的 `v1.14` 维护线，不占用产品 V2 | 未裁决 |
| 同步前是否先稳定结构 | 当前 v1.13.9 仍有 4,595 行 View、1,893 行 privacy controller，且没有 XCUITest target | 按用户要求先做不改功能的 v1.13.10：拆文件、统一状态来源、补真正 UI 自动测试；关账后才做同步 | 待权威回写 |
| 核心同步真相源 | 现行规格使用 SwiftData 自动 CloudKit + synchronizable Keychain 双通道 | 建议迁移为客户端加密 envelope + custom zone + CKSyncEngine；旧通道先影子、后退休 | 未裁决 |
| 应用密码角色 | 现行语义是本机门闩 | 建议保持，不把 verifier/口令改作 KEK | 未裁决 |
| 分布式清除承诺 | 现有本机收敛不能证明永久离线设备已物理删除 | 建议区分逻辑失效与物理收敛，以独立的 `generation` 与 `eraseEpoch` 阻止复活，不拿 `writeKeyEpoch`/`acceptedReadKeyEpochs` 代替 | 未裁决 |
| 高风险控制权限 | 现行四档验证主要定义内容取用；新同步控制面尚无“单设备管理员还是 quorum”权威决定 | 建议首版个人保险库采用 1-of-N active device 单签，并把所有高风险 event 留下签名审计；quorum 作为未采用候选但须由产品明确裁决 | 未裁决 |
| “不验证”的边界 | 现行 FR-061 在“不验证”时不再按当前方式确认，接口也沿用该语义 | 建议“不验证”不豁免设备加入/撤销、Recovery Credential 替换、compromise replacement 与 FR-061 清除/重置的 device-owner 认证；这会要求显式权威修订 | 未裁决，不得偷改 FR-061 |
| 轮换安全承诺 | 草案已有重包流程，但若旧 VRS 已泄露，仅重包不能保护攻击者已经取得的历史 ciphertext/wrapper | 建议拆为 routine rotation 与 compromise replacement，后者为仍存活内容全量更换 DEK/nonce/ciphertext，并披露历史副本不可追回 | 未裁决 |
| FR-061 清除语义 | 现行要求“全部用户数据”清除；受控同步草案曾默认保留 vault trust 并新建 generation | 建议 FR-061 映射为退休旧 vault 的完整 reset；保留 trust 的内容清空若需要，应另设不同名称；两者都需裁决最小 anti-replay tombstone 与零残留取舍 | 未裁决，不得覆盖现行权威 |

## 2. G1 决策表

产品负责人审查时逐行填写；不得用“整体同意”掩盖未决安全边界。

| ID | 待裁决问题 | 推荐选择 | 最终选择 | 未采用方案及理由 | 批准人/日期/证据 |
| --- | --- | --- | --- | --- | --- |
| D01 | 版本归属与顺序 | v1.13.9 关账 → v1.13.10 纯结构稳定化 → Stage 1 v1.14 受控同步；产品 V2 仍为 2.0 用量看板；UI 重设计最后单列 | 待定 | 待定 | 待定 |
| D02 | 同步时效与状态 | 不保证固定秒数，只显示可证明确认层级 | 待定 | 待定 | 待定 |
| D03 | 应用密码角色 | 继续仅作本机门闩，不作 KEK | 待定 | 待定 | 待定 |
| D04 | 新设备信任 | active 可信设备批准 + 独立 Recovery Key | 待定 | 待定 | 待定 |
| D05 | 无设备恢复 | 无可信设备但有 Recovery Key 可恢复；两者都丢失则不可恢复 | 待定 | 待定 | 待定 |
| D06 | 后台秘密读取 | v1.14 只后台传密文；自动化解密域另立方案 | 待定 | 待定 | 待定 |
| D07 | 公开路由元数据 | 只保留协议、世代、随机 ID 和状态所需最小集合 | 待定 | 待定 | 待定 |
| D08 | 旧版本与观察窗口 | 至少一个 shadow 版本 + 一个 controlled-primary 版本；具体时长另填 | 待定 | 待定 | 待定 |
| D09 | 完整快照回滚 | 不新增 transparency 服务；保留 Recovery-only 全新设备无外部最新性锚点的已披露边界 | 待定 | 待定 | 待定 |
| D10 | Recovery Credential 结构 | 离线非对称 agreement/signing keypair；云端仅公钥，active 设备可为新 VRS 创建 wrapper | 待定 | 待定 | 待定 |
| D11 | 离线全量清除 | 本机立即不可见并封写；联网完成获批模式的 `eraseEpoch`/control transition 后才重新开放或进入未配置 | 待定 | 待定 | 待定 |
| D12 | CloudKit 全失恢复 | Recovery Credential 单独不足；v1.14 要求已验证加密备份，自动更新 Recovery Kit 另案 | 待定 | 待定 | 待定 |
| D13 | 控制管理员权 | 个人保险库 v1.14 采用任一 active device 单签（1-of-N）；新设备批准、撤销、正常轮换、Recovery Credential 替换和 compromise replacement 分别记录签名 event。若改用 quorum，必须同时批准 N=1、设备丢失、全离线与 Recovery-only 逃生规则 | 待定 | 待定 | 待定 |
| D14 | “不验证”与高风险认证 | “不验证”只豁免普通内容门闩；新设备批准、撤销、Recovery Credential 替换、compromise replacement 和 FR-061 清除/重置仍强制 `deviceOwnerAuthentication`。如采纳，先修订 FR-061、验收场景与接口 | 待定 | 待定 | 待定 |
| D15 | routine rotation 与 compromise replacement | 分成两个流程：routine 只切 `writeKeyEpoch`/重包并暂留 `acceptedReadKeyEpochs`；疑似泄露时全量生成新 DEK/nonce/ciphertext并替换可疑 device/recovery identities。两者都明确“不追回旧明文；旧 VRS 可解撤销前已取得的兼容 ciphertext/wrapper” | 待定 | 待定 | 待定 |
| D16 | FR-061 清除模式 | 推荐 FR-061 = vault reset：退休旧 vault，完成后进入未配置；再次使用生成全新 vaultID、Recovery Credential 与 device identities，只保留最小认证 anti-replay/retirement tombstone。保留信任的 content wipe 如需提供则另设操作；若要求零残留，必须接受旧离线副本无法可靠阻止复活的风险 | 待定 | 待定 | 待定 |
| D17 | 无 Secure Enclave 设备 | 推荐在明确列入支持范围的无 SE 设备上允许 Data Protection Keychain `ThisDeviceOnly` 软件 P-256 fallback，但必须把 roster 设备标为 `softwareExportable`、向用户显示“缺少硬件不可导出保护”的降级，不得同步/备份私钥或宣称等同 SE；另一候选是直接拒绝创建/加入受控保险库 | 待定 | 待定 | 待定 |

## 3. 权威回写账本

只有 D01–D17 全部裁决后，才能另行授权此表的回写动作。

| 权威文件 | 应回写内容 | 已授权 | 实际结果/提交 | 一致性复核 |
| --- | --- | --- | --- | --- |
| `ApiRelay/specs/ROADMAP.md` | 阶段归属和依赖 | 否 | 未执行 | 未执行 |
| `.specify/memory/constitution.md` | 如提升为安全原则，记录版本与影响 | 否 | 未执行 | 未执行 |
| `001-key-vault/spec.md` | 同步、清除、迁移产品要求；尤其按 D14/D16 显式修订 FR-061 与验收语义，不能靠下位合同覆盖 | 否 | 未执行 | 未执行 |
| `research.md` | 替换与产品 V2 冲突的旧结论 | 否 | 未执行 | 未执行 |
| `plan.md` / `data-model.md` / interfaces | 正式模块、存储和协议边界 | 否 | 未执行 | 未执行 |
| `tasks.md` / playbooks | 只生成获准 gate 的实施任务 | 否 | 未执行 | 未执行 |
| `ZL01_具体说明/14-项目当前状态.md` | 只更新真实当前状态和下一步 | 否 | 未执行 | 未执行 |

## 4. 旧任务处置

| 任务 | 允许的结果 | 当前结果 |
| --- | --- | --- |
| legacy hygiene T006 | 继续完成；或经 G1 后标 `superseded` 并说明新协议如何取代 | 未裁决、不得勾完成 |
| legacy hygiene T008 | 继续作为旧路径独立真机证据；除非正式发布边界明确取消并留下理由 | 未完成、不得用新协议测试代替 |

## 5. 关闭条件

- D01–D17 无“待定”；
- 每项有批准人、日期和可定位证据；
- 采用与未采用方案都已写明；
- 权威回写另获授权并实际完成；
- `ZL01/14` 只记录真实发生状态；
- 链接、路牌、版本名称和安全语义一致性检查通过；
- 最终计划再次由用户确认；此后仍只按单个 gate 单独授权实施。
