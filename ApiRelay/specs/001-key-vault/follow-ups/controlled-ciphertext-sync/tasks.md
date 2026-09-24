# Tasks: v1.14 受控密文同步

**Status**: 计划清单；当前只允许 P0 文档审查。P1 起均未授权。
**Input**: [release sequence](./release-sequence.md) · [spec](./spec.md) · [plan](./plan.md) · [decision record](./decision-log.md) · [research](./research.md) · [data model](./data-model.md) · [contracts](./contracts/)

## P0 — 计划草案与审查（本轮）

- [x] **T000** 只读核对现有代码、legacy 同步卫生包、当前状态、分支台账和权威冲突。
- [x] **T001** 用 Apple 官方资料核对 SwiftData、CKSyncEngine、custom zone、state serialization、冲突、Keychain 与 Secure Enclave 边界。
- [x] **T002** 用成熟密码管理器官方材料校正 DEK/root key/device wrapper 分层，且不照抄参数。
- [x] **T003** 写出 plan-only spec、威胁模型、目标架构、数据模型、四份协议草案、迁移/回滚和验收矩阵。
- [ ] **T004** 产品负责人审查并批准/修改 G1 决策表。
- [ ] **T005** 确认本计划是否作为 v1.14 Stage 1 维护的正式输入。

**Checkpoint P0**：T004/T005 未完成时只能继续改计划，不得进入代码。

## P1 — G0 前序关账与只读盘点（13.9/13.10 已完成，13.11 进行中；同步写操作仍需另授权）

- [x] **T010** v1.13.9 已完成本轮身份验证验收、上传并冻结认证主链；尚欠的系统边界全矩阵继续作为发布闸门，不阻塞纯结构分支，也不得写成已通过。
- [x] **T011** 已盘点原工作树归属、parked v1.14 的旧 13.6 指向、legacy hygiene T006/T008 的真实状态；v1.13.10 使用独立干净 worktree，未移动 v1.14。
- [x] **T012** 已只读清点不可逆标识、store path、Keychain service/access group 与 schema；基线写入 `follow-ups/v1.13.10-structural-stabilization/04-不可逆标识基线.md`，实施后必须逐项复核不漂移。
- [x] **T013** v1.13.9 已按授权完成内容提交 A、记账 B 和上传；closure SHA 为 `25fe006896a816475e269e155530c1464cc19304`。
- [x] **T014** 已核对本地/远端 `v1.13.9` 与 `v1` 均指向同一 closure SHA；原工作树剩余差异均未带入下一线。
- [x] **T015** 产品负责人已批准 `release-sequence.md` 并授权实施；已从 closure SHA 建立独立 `v1.13.10` 分支与干净 worktree。
- [x] **T016** v1.13.10 已补 characterization 与真正的 `ApiRelayUITests` target/fixture/accessibility identifiers；系统认证真机边界另列发布闸门。
- [x] **T017** 已按职责拆分超大 View、ViewModel、service 与 privacy controller，并保留等价验证证据。
- [x] **T018** 已统一本阶段已证实重复的运行期状态来源；未把冻结密码语义或同步协议带入。
- [x] **T019** v1.13.10 已完成自动回归、三平台构建、独立审查、授权提交上传及远端复核；closure SHA 为 `8e6c22109b9f5851dacb31b96e8915d855b0e0f3`。iPhone/iPad/Mac 真实系统边界全矩阵未完成，继续作为发布闸门，不能因本项勾选视为通过。
- [x] **T019A** 已对照 `v1.13.10@8e6c221` 关账证据核对 T016–T019 的结构范围与未完成真机边界；不把自动测试冒充真机验收。
- [ ] **T019B** `v1.13.11` 在独立工作树只做购买权益验收；待测试、独立复核、授权上传和远端核对真实完成后，才记录其 closure SHA。工作包在 `ZL02_研发档案/第一阶段-密钥库/调整与优化/v1.13.11-购买权益验收/`。

## P2 — G1 产品与威胁模型（未来，需另授权）

- [ ] **T020** 批准 v1.14 阶段归属、同步状态承诺和不承诺。
- [ ] **T021** 批准应用密码继续作本机门闩，不作 KEK。
- [ ] **T022** 批准可信设备 + Recovery Key 的加入/恢复模型及不可恢复边界。
- [ ] **T022A** 批准 Recovery Credential 的内部结构；推荐离线非对称 agreement/signing keypair，并明确轮换、撤销、取消、输错和恢复材料丢失路径。
- [ ] **T023** 批准后台只传密文；管理凭据 automation domain 延后单独裁决。
- [ ] **T024** 批准最小公开路由字段与 metadata leakage 说明。
- [ ] **T025** 批准旧版本支持窗口、minimum writer version、观察版本/时间和淘汰条件。
- [ ] **T026** 完成 threat model：云端泄露、恶意记录替换、设备丢失、可信设备被攻破、旧客户端、运行期 App compromise。
- [ ] **T027** 裁决是否接受无 transparency 服务的完整快照回滚边界；若不接受，先扩展产品/服务范围。
- [ ] **T027A** 裁决离线全量清除语义；推荐本机立即不可见并封写，等待获批模式的 `eraseEpoch`/control transition 激活后再开放或进入未配置。
- [ ] **T027B** 裁决 CloudKit control/data 全失恢复边界；推荐 v1.14 要求已验证加密备份，Recovery Kit 另案。
- [ ] **T027C** 裁决控制管理员权：任一 active device 单签（1-of-N）或多设备 quorum；分别定义正常轮换、设备撤销、Recovery Credential 替换与 compromise replacement 的门槛，以及单设备/设备丢失/Recovery-only 逃生路径。
- [ ] **T027D** 裁决“不验证”是否仍对新设备批准、撤销、Recovery Credential 替换、compromise replacement 与 FR-061 清除/重置强制 `deviceOwnerAuthentication`；若采纳推荐项，登记对 FR-061、SC-014 与接口的待授权回写，不能由下位合同偷改。
- [ ] **T027E** 裁决并命名 routine rotation 与 compromise replacement；后者必须为仍存活内容全量换 DEK/nonce/ciphertext并替换可疑信任因子，产品文案必须披露旧 VRS 仍可解其此前取得的兼容 ciphertext/wrapper、既有明文不可追回。
- [ ] **T027F** 裁决 FR-061 是“保留 vault trust 的内容清空”还是“退休旧 vault 的完整 reset”；同时决定最小 anti-replay/retirement tombstone 的字段/保留承诺与“绝对零残留会失去防复活证据”的取舍。
- [ ] **T027G** 裁决无 Secure Enclave 设备：拒绝受控保险库，或允许 Data Protection Keychain `ThisDeviceOnly` 软件 P-256 fallback；若允许，批准 `softwareExportable` roster/UI 降级标识、不得同步/备份私钥及相应威胁模型。
- [ ] **T028** 把最终选择、未采用方案、批准人/证据、回写位置和 ZL01/14 状态记入 `decision-log.md`；只批准决定，不自动授权回写。
- [ ] **T029** 获得精确文档回写授权后，按计划 §10 回写 ROADMAP/constitution/current spec 等权威；消除 v1.14 与产品 V2 命名冲突，并做链接/语义一致性复核。
- [ ] **T02A** 裁决 legacy hygiene T006/T008：未完成项继续做、被新协议正式取代或保留为旧路径证据；每项写明理由。被取代记 `superseded`，不得假勾为完成。
- [ ] **T02B** 在 v1.13.11 也已关账、G1 产品裁决、权威回写、一致性复核和用户单独前移分支授权都完成后，才评估将 parked v1.14 纯 fast-forward 至 v1.13.11 closure SHA；若不能纯快进则停止，禁止 reset/recreate/force，并记录真实 base SHA。
- [ ] **T02C** 用户再次确认最终计划和本次仅授权的实施 gate；此前不得创建 Swift 实施任务。

**Checkpoint G1**：产品负责人逐项确认；不能由开发者默认。

## P3 — G2A 协议原语候选（未来，需另授权）

- [ ] **T030** 起草 crypto suite、canonical encoding、payloadAAD/wrapAAD、domain labels、format agility 和测试向量。
- [ ] **T031** 用 disposable CloudKit container 验证 control/data zones、record types、索引、大小和原子批次。
- [ ] **T032** 起草 device bootstrap/join/approval/recovery/revoke/rotation 与 recovery-authority 协议。
- [ ] **T033** 起草 control parent-hash、actor sequence/frontier、mutation signature、幂等和冲突矩阵；为 `generation`、`eraseEpoch`、`writeKeyEpoch`、`acceptedReadKeyEpochs` 建立互不替代的状态转移与拒绝矩阵。
- [ ] **T034** 按 D16 起草 tombstone、restore/purge/cascade、content wipe 或 vault reset、erase receive、generation activation、device ack 和 GC 条件；若保留最小 retirement tombstone，冻结其非业务内容字段和保留期。
- [ ] **T035** 起草 durable outbox/inbound/engine state 的本机事务边界及 account/token/zone 恢复；冻结 journals-first 启动顺序、fail-closed gate 与裸 physical delete 不构成业务 tombstone 的处理。
- [ ] **T035A** 冻结全局 ControlOperation 槽、erase/cutover/rotation/revoke/cleanup 优先级、CAS loser rebase 和每类 supersede/abort 的认证事件。
- [ ] **T036** 起草 UserPreferences、Usage/Balance/Pricing 是否进入 controlled domain 的分类表。

**Checkpoint G2A**：候选原语和 disposable 证据足以支持迁移设计；仍允许 G3 反向修订，不得声明冻结。

## P4 — G3 迁移设计 + G3F 统一冻结（未来，需另授权）

- [ ] **T040** 冻结 legacy 分类与 MigrationLedger。
- [ ] **T041** 冻结 shadow 增量捕获、ProductionShadowCheckpoint 全绑定/失效规则与 final delta write gate。
- [ ] **T042** 冻结多设备 migration coordinator/lease、required-participant CutoverBarrier/Ready/abort 协议；若首版单设备 cutover，也必须明确排除设备与新 participant revision，不能静默降级。
- [ ] **T043** 冻结 manifest cutoverID/fencing revision 的全局 PONR、pre-cutover disable 与 post-cutover pause/forward-only 边界。
- [ ] **T044** 冻结 LegacyParticipant/inventory、旧客户端写入隔离、旧 Keychain/本机 fallback 迟到项和 old zone GC。
- [ ] **T045** 冻结备份 v1、新备份格式、control zone 丢失时是否存在加密 Recovery Kit，以及 CloudKit 全失后从已验证备份建立全新 vault 的身份/世代不复用协议。
- [ ] **T046** 写齐每个迁移阶段的 crash-injection 表与人工恢复手册，包含账号切换、磁盘写满、首次解锁、双 coordinator、离线 participant、CAS accepted/回调丢失和控制操作竞争。
- [ ] **T046A** 冻结 MigrationOperationJournal、LegacyCleanupJournal 与逐参与设备签名 cleanup checkpoint；明确 v1.13.9 DataEraseJournal 不可直接复用。
- [ ] **T047** 合并 G2A 与 G3，统一冻结四份 contract、四类世代/时期、控制管理员权、routine/compromise 两类轮换、可验证 data frontier、Production per-vault shadow、获批清除模式、distributed erase 和分阶段 legacy cleanup。
- [ ] **T048** 进行独立密码学/协议/隐私审查和独立迁移审查，解决全部 P0/P1；由产品负责人再次确认最终计划。

**Checkpoint G3F**：迁移状态机可逐阶段演练，四份 contract 无“实现时再定”，测试向量可运行，独立审查通过；仍不代表获准实现。

## P5 — G4 本机基础实现（当前禁止）

- [ ] **T050** feature flag、local canonical store、projection、outbox 和 transaction coordinator。
- [ ] **T051** crypto envelope/device keys/recovery primitives，只用固定测试向量。
- [ ] **T052** fake transport 下 mutation、conflict、tombstone、erase、account state machine。
- [ ] **T053** 全部逐崩溃点与数据泄漏扫描。

## P6 — G5 Development CloudKit 与影子迁移（当前禁止）

- [ ] **T060** 仅在 Development/disposable zones 接入 CKSyncEngine。
- [ ] **T061** partial failure、token expired、zone deleted、quota/rate-limit/error matrix。
- [ ] **T062** shadow migration dry-run，legacy 仍权威。
- [ ] **T063** 两台与三台真实设备矩阵。
- [ ] **T064** 独立审查 G5 证据，所有 mismatch 清零。

## P7 — G6 Production 影子与受控切换（当前禁止）

- [ ] **T070** additive deploy Production schema 并核对。
- [ ] **T071** TestFlight 小范围 opt-in；每个真实 vault 在 legacy 仍权威时完成 Production shadowVerified，pre-cutover disable 可安全撤回。
- [ ] **T072** 以 manifest cutover CAS 进入 controlledPrimary；演练结果未知重读、旧通道停止采纳、post-cutover pause 与 forward-only，禁止 flag 回 legacy。
- [ ] **T073** UI/本地化准确区分 cloud accepted/device ack/conflict/recovery。

## P8 — G7 观察与旧明文退休（当前禁止）

- [ ] **T080** 跨版本/长期离线/账号切换/重装/撤销/轮换/清除观察期。
- [ ] **T081** 独立安全与迁移审计。
- [ ] **T082** Recovery Key 与加密备份最终演练。
- [ ] **T083** 产品负责人单独批准不可逆 legacy secret cleanup。
- [ ] **T084** 依 journal 删除旧 synchronizable Keychain 明文并验证迟到项，记录 `legacySecretPlaintextDeleted`。
- [ ] **T085** 再单独批准并清理旧 CloudKit 用户记录中的名称/备注/URL/关系等明文元数据；schema/type 仅 deprecated，逐记录/zone 验证删除观察结果。
- [ ] **T086** 重新核对加密出口合规声明，并更新隐私政策、帮助、商店问卷和用户说明。

## 依赖关系

    P0 → P1 → P2 → P3 → P4 → P5 → P6 → P7 → P8

不得并行跨越硬闸门。可以在同一阶段内并行做独立研究/测试，但阶段 Exit 未满足时，后续任何代码与真实数据操作均无授权。
