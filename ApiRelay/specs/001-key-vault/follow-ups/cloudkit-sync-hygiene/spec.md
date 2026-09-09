# Feature Specification: CloudKit 同步卫生（Stage1 后续）

**Feature Directory**: `specs/001-key-vault/follow-ups/cloudkit-sync-hygiene`  
**Git**：现行热修线 **`v1.13.5`**（从已推的 `v1.13.4` 开出），**不是**新的产品小迭代，**不是** `004-*` / `P14` / `v1.14`。

**Created**: 2026-09-10

**Status**: Active — 实现入口见 [`../../../playbooks/热修-CloudKit同步卫生.md`](../../../playbooks/热修-CloudKit同步卫生.md)

**Input**: 首页因 CloudKit 重复业务 `id` 崩溃的止血已落地；本规格只收**尚未关账**的卫生后续。

## 与已落地工作的边界

下列已在 **`v1.13.5` 工作区**实现（2026-09-10；远程 `v1.13.4` **没有**这些代码），**本功能 MUST NOT 撤掉**：

- 搜索 / 分组禁止 `Dictionary(uniqueKeysWithValues:)`。
- 账号 / 使用方 / 密钥仓库读取按业务 `id` 折叠；改删恢复打全部副本。
- 启动巡检 `pruneDuplicateIdentities`：仅当赢家规则能跨设备一致分出唯一输家时本机删除。
- 完全打平的克隆故意不删（防两台设备互删后一条不剩）。
- 免费额度 `countActiveNonDeleted` 按业务 `id` 去重。
- 使用方软删 bump `updatedAt`。

`001-key-vault` 的 `tasks.md` 里未勾的 **T065（商店截图）不是本功能**。对本目录跑 implement 时 MUST `export SPECIFY_FEATURE_DIRECTORY=specs/001-key-vault/follow-ups/cloudkit-sync-hygiene`。

## User Scenarios & Testing

### User Story 1 — 导入结束后再清扫 (Priority: P1)

用户打开 App 后 CloudKit 仍在导入。启动巡检可能已经跑过；随后云端又写入同 `id` 的第二行。列表此时已去重、不崩，但幽灵行要等下次冷启动才物理删除。

**Why this priority**: 不补这一层，当前方案对「打开后才同步进来的重复行」永远慢一拍。

**Independent Test**: 内存种双行发生在「模拟 import 成功通知」之后，断言清扫被合并执行且只跑一次。

**Acceptance Scenarios**:

1. **Given** 启动巡检已跑完且当时无重复行，**When** `apiRelayCloudMetadataDidImport` 发出，**Then** 在短暂合并窗口后再次执行与启动相同的 `pruneDuplicateIdentities`（账号 / 密钥 / 使用方）。
2. **Given** 导入通知在 2 秒内连发多次，**When** 窗口结束，**Then** 清扫只落地一次（合并执行，不在 MainActor 上 `await` SwiftData save）。
3. **Given** 导入失败或未镜像，**When** 无成功导入事件，**Then** MUST NOT 额外清扫。

---

### User Story 2 — 完全相同的克隆可安全收掉 (Priority: P2)

两台设备几乎同时插入同一业务 `id`，内容也相同。当前规则故意不删。配额与下一次漏网的字典构造会一直被喂弹。

**Why this priority**: 不增加跨设备稳定的副本标识，就无法在不互删的前提下收掉真克隆。

**Independent Test**: 两条指纹完全相同的 SwiftData 行，在写入稳定 `replicaSeed` 后，两台设备算出同一个赢家并删除输家。

**Acceptance Scenarios**:

1. **Given** 同步模型尚无副本标识，**When** 实现本故事，**Then** 以 **additive** CloudKit 字段补上（建议名 `replicaSeed: UUID`，插入时生成、之后只读）。发出含该字段的包前 MUST 再 Production additive Deploy（FR-063）。
2. **Given** 两条同业务 `id`、业务字段全等、但 `replicaSeed` 不同，**When** 清扫，**Then** 保留 `replicaSeed` 字典序较小者，删除另一条；两台设备结果相同。
3. **Given** 旧数据没有 `replicaSeed`（nil），**When** 本机首次读到，**Then** 只给**缺字段的行**补种一次并保存；MUST NOT 给已有种子的行换新值。

**现在不要做**：未 Deploy 不得改 schema、不得发包。打平克隆继续不删。

---

### User Story 3 — 冲突字段取舍写死 (Priority: P2)

两条记录各改了不同字段（一边备注、一边头像）。当前是整行 LWW，输家整行丢掉，独有字段可能丢失。

**Why this priority**: 不写死取舍，实现者会发明字符串拼接，违反宪法 IX。

**Independent Test**: 规格表可被单测断言（给定两行字段，赢家各字段取值唯一确定）。

**Acceptance Scenarios**:

1. **Given** `updatedAt` 不同，**When** 选赢家，**Then** 展示类标量（名称、备注、头像、平台、lifecycle、删除态）**整行采用较新者**，MUST NOT 把两边非空字符串拼成新备注。
2. **Given** `updatedAt` 相同且一条已删一条未删，**When** 选赢家，**Then** 墓碑整行胜（与已落地规则一致）。
3. **Given** 指派表，**When** 读取，**Then** 仍按 `(keyId, consumerToolId)` 去重并集，不按账号那套整行 LWW。
4. **Given** 产品未出现「两边各改了不同字段还都要留」的真实投诉，**When** 实现本故事，**Then** MUST NOT 做字段级三路合并引擎。

---

### User Story 4 — 指纹跨地区一致 (Priority: P1)

排名指纹若随系统地区把小数点写成逗号，两台设备会选出不同赢家。

**Why this priority**: 已落地的清扫依赖指纹；地区不一致会把「谨慎不删」变成「互删」。

**Independent Test**: 在 `en_US` 与 `fr_FR` 地区格式下对同一 `Date` / `Decimal` 生成的指纹字符串相等。

**Acceptance Scenarios**:

1. **Given** 任意 `Locale`，**When** 生成 `SyncedIdentity` 指纹，**Then** 时间戳用 POSIX / 固定小数点（禁止 `String(format:)` 走当前地区）；`Decimal` 用规范字符串或二进制，禁止 `String(describing:)`。
2. **Given** 指纹函数变更，**When** 跑单测，**Then** 用固定样例钉死输出，避免以后又滑回地区格式。

---

### User Story 5 — 新增与幂等导入拆开 (Priority: P2)

`insert(id:)` 在 id 已存在时直接返回该 id，调用方会以为草稿已写入。

**Why this priority**: 备份导入需要幂等；用户点「添加」必须失败或开新 id，不能静默丢草稿。

**Independent Test**: 普通 `create*` 在 id 碰撞时不得静默成功；备份导入同 id 仍跳过。

**Acceptance Scenarios**:

1. **Given** 用户添加账号/使用方/密钥，**When** 未传已有 id（产品路径本来如此），**Then** 行为与现在一致：始终新 UUID。
2. **Given** 备份导入，**When** 业务 `id` 已存在，**Then** 走显式 `insertIfAbsent`，返回「未写入」而不是假装 insert 成功。
3. **Given** 测试或错误调用把已有 id 传进普通 insert，**When** 该路径仍存在，**Then** MUST 抛 `already_exists` 或等价校验，MUST NOT 再静默 return。

---

### User Story 6 — 真机双设备手测清单 (Priority: P1)

内存容器单测覆盖不到 CloudKit 导入时序。

**Why this priority**: 评审明确：编译、全量测试、双设备验证之前不能关账。

**Independent Test**: 清单在 [`热修-CloudKit同步卫生-验收清单.md`](../../../playbooks/热修-CloudKit同步卫生-验收清单.md)；由产品负责人在两台已登录同一 iCloud 的设备上勾。Agent MUST NOT 用假绿单测代替。

**Acceptance Scenarios**:

1. 离线导入备份后恢复网络，重复 id 不崩，最终规范成一条。
2. 两台设备同时改同一账号不同字段，结果符合本规格 LWW，不崩。
3. 一台删除后另一台离线再上线，不出现「删了又活」；或出现后清扫能在导入成功后收掉。
4. 连续重启两次，列表条数稳定。

---

### User Story 7 — 同步单例同样折叠 (Priority: P3)

`UserPreferences` 是同步库 + 曾用 `fetchLimit = 1`，同类重复不会崩首页，但会打偏设置。`EntitlementSnapshot` 是本机库，同类 `fetchLimit = 1` 同样随机。

**Independent Test**: 内存种两条同 `singletonID` 的偏好，读取折叠、写入打全；13.5 物理清扫后行数不变。权益快照有 `updatedAt`，能分出输家则删。

---

### Edge Cases

- 导入通知在测试宿主发出：MUST 用注入的 monitor / 通知名，禁止测试碰生产 CloudKit。
- `replicaSeed` 未 Deploy 到 Production 就发含该字段的包：同步会丢字段。实现提示词必须写进 Deploy 闸门。
- 备份「合并导入 vs 替换恢复」若本功能要做产品分流：MUST 另开设置/确认文案，不得静默清空云端。默认保持现有「已存在则跳过」。

## Requirements

- **CKH-001**: CloudKit **成功导入**结束后，MUST 合并、延迟再跑一遍与启动相同的身份清扫。失败导入 MUST NOT 清扫。
- **CKH-002**: 完全相同的业务行，长期 MUST 用跨设备稳定的副本标识决定输家；未部署该字段前，保持「打平不删」。
- **CKH-003**: 账号 / 使用方 / 密钥的冲突取舍 MUST 是整行 LWW（较新 `updatedAt`，平手墓碑优先）。MUST NOT 拼接备注。指派表保持组合去重并集。
- **CKH-004**: 排名指纹 MUST 在任意 Locale / 系统版本下对同一输入得到同一字符串。
- **CKH-005**: 用户新增与备份幂等导入 MUST 是两条 API，不得共用「id 已存在就当成功」。
- **CKH-006**: 关账前 MUST 有双设备 CloudKit 手测清单且由产品负责人勾过；单测全绿不够。
- **CKH-007**: 同步单例（偏好）MUST 读去重、写打全。13.5 起 `UserPreferences` MUST NOT 按指纹物理删冲突行（无 `updatedAt`）。本机权益快照有 `updatedAt`，可分出输家才删。
- **CKH-008**: MUST NOT `@Attribute(.unique)`、MUST NOT 改 CloudKit 控制台当消重、MUST NOT 把业务 `id` 换成记录名。

## Success Criteria

- **SC-CKH-001**: 导入成功后无需第二次冷启动，能分出的输家在本机会被删并同步出去。
- **SC-CKH-002**: `fr_FR` 与 `en_US` 下指纹单测全绿。
- **SC-CKH-003**: 备份再导一次仍跳过已有 id；用户「添加」不会因隐蔽 insert 丢掉草稿。
- **SC-CKH-004**: 验收清单上的双设备项全部勾选后才允许说本功能关账。
