写入状态：未停止

# 阶段4：Grok实施报告（W0）

- 阶段：4
- 波次：W0（规格唯一化与当前路牌）
- 时间：2026-09-14 22:44 CST
- 分支：`v1.13.9`
- HEAD：`6ec5ff7c67547637bbd55f528276422395e28c03`（与契约 `baselineHead` 一致，未离开基线）
- 方法版本：`MAIC-1.3`
- 工作包：`ZL02_研发档案/第一阶段-密钥库/调整与优化/v1.13.9-身份验证四档与主密码调整/`
- 输入：`00`、`00A`、`00C`、`03`、`04`、`05`、宪法 VIII、`001-key-vault` 规格包、playbook 路牌、`ZL01/04`、`ZL01/14`
- 用户授权：用户执行 `提示词/阶段4-Grok执行下一波.md`，视为对 `04`/`05` 的整体批准；**仅授权本波 W0**。不授权一次做完全部波次，不授权改 Swift，不授权暂存/提交/上传
- 当前授权范围：`04` 第三节 W0 精确文件清单；禁止 `tools/`、Swift、`BRANCHES.md`、`ZL01/10`、`ZL01/13`、ROADMAP、ZL00、xcodeproj
- 保护 refs（未改）：`main` / `origin/main` = `539447ea9984608c74989da48b8770cb3fe32a6c`；`release/1.0.0` = `5c5eed3f8390f51f5a26be9737bcc11f72e7d7fd`
- 暂存区：空
- 下一负责人：Codex
- 下一步：执行工作包 `提示词/阶段4A-Codex波次审计.md`

---

## 1. 本波做了什么

把身份验证定稿写进正式规格，使 **W0 允许修改的文件**里只有一套现行答案：

| 现行答案 | 落地 |
| --- | --- |
| 四档 | 不验证 / 设备验证 / 应用密码 / 生物验证或应用密码。无「仅生物识别」用户档 |
| 出厂 | 验证方式 = 设备验证（`biometricOrPasscode`）；取用验证 `revealAuthEnabled` 默认 true |
| 三行设置 | 验证方式 / 自动锁定 / 取用验证 |
| 同详情复用 | 查看成功后立刻复制可复用；关详情 / 换密钥 / 离前台 / 自动锁 / 会话锁后失效 |
| 降低与三档互换 | 先按**当前**验证方式确认；persist 失败不降 |
| 导出/删除 | 不再永远强制设备主人；不验证时导出可直达；永久删除/清空先破坏性确认 |
| 管理类凭证 | 仍 `confirmMandatory`（始终设备主人） |
| 路牌 | `v1.13.9` 已创建；规格已回写；代码尚未改；未声称已提交/上传 |

宪法升至 **v2.14.0**（2026-09-14）。VIII 后半 13.7 锁生命周期（会话锁、persist-then-apply、快照≠计时、按窗遮罩、未知≠离屏、验证串行）仍在。

未改任何 `.swift`。未开 W1。

---

## 2. 实际修改的文件

`git diff --stat`：20 个已跟踪文件，+189 / −132。无 Swift。

- `ApiRelay/.specify/memory/constitution.md`（v2.14.0 + Sync Impact）
- `ApiRelay/specs/001-key-vault/spec.md`
- `ApiRelay/specs/001-key-vault/data-model.md`
- `ApiRelay/specs/001-key-vault/contracts/module-interfaces.md`
- `ApiRelay/specs/001-key-vault/research.md`
- `ApiRelay/specs/001-key-vault/quickstart.md`
- `ApiRelay/specs/001-key-vault/plan.md`
- `ApiRelay/specs/001-key-vault/tasks.md`（历史完成项保留原文 +「已被 13.9 覆盖」）
- `ApiRelay/specs/001-key-vault/checklists/requirements.md`
- `ApiRelay/specs/001-key-vault/follow-ups/identity-auth/spec.md`
- `ApiRelay/specs/playbooks/身份验证方案.md`
- `ApiRelay/specs/playbooks/锁-加固计划.md`
- `ApiRelay/specs/playbooks/锁-验收矩阵.md`
- `ApiRelay/specs/playbooks/重要说明/索引.md`
- `ApiRelay/specs/playbooks/v1-key-vault/phases/P03-保管与取出.md`
- `ApiRelay/specs/playbooks/v1-key-vault/phases/P06-设置与备份.md`
- `ApiRelay/specs/playbooks/v1-key-vault/phases/P07-Catalyst.md`
- `ApiRelay/specs/playbooks/v1-key-vault/phases/P13-人工操作指南/06-TestFlight内测.md`
- `ZL01_具体说明/04-设计与规格.md`
- `ZL01_具体说明/14-项目当前状态.md`

本报告为 `00C.allowedAdd` 下新建，未覆盖任何已有报告。

---

## 3. 反搜证据（必须失败的反例）

在 **W0 允许路径**内搜索：`尚未创建的 v1.13.9`、`新安装默认不验证`、`导出永远设备主人`、`任何鉴权不得在同详情复用`、`仅生物识别是新四档`。

- 上述短语作为**现行要求**：W0 允许文件中 **0 命中**。
- 「仅生物识别 / `biometricOnly` / `confirmMandatory` / 不跨操作缓存」仍出现在历史完成项、覆盖表、迁移说明中，均紧邻「已被 13.9 覆盖」或写明「不得再当现行」。
- 宪法 HTML 历史块 v2.10.0 仍有「降低须不可关闭的设备主人」——那是 **2.10 当时修订记录**，不是现行 VIII。
- `follow-ups/identity-auth/spec.md` 与 `身份验证方案.md` 写「不要把 13.9 写成尚未创建」，是禁令，不是声称尚未创建。

### 本波未改、仍含「尚未创建 13.9」的路径（留给 W6 / 禁止本波扩大）

| 路径 | 为何没动 |
| --- | --- |
| `ApiRelay/specs/playbooks/BRANCHES.md` | `04` 明确 W6 才改；W0 清单不含它 |
| `ZL01_具体说明/10-AI对话相关记录.md` | W0 不含；对话索引不是当前路牌 |
| `ZL01_具体说明/13-上传记录.md` | W0 不含；历史上传行保留当时事实 |

若审计把「全仓库零命中尚未创建」当成 W0 停止点，会与 `04` 的精确文件清单冲突。本执行者按**精确清单**停手，不自行改 BRANCHES / 10 / 13。

---

## 4. 测试

W0 无代码。未跑 `xcodebuild`，未跑 `selfcheck.sh`。规格正确性靠对照 `04` 第一节～第二节与反搜。

---

## 5. 未验证项

- App 运行时仍是旧默认「不验证」、无 `revealAuthEnabled`、删除/备份仍走 `confirmMandatory`——这是 W1 起的代码事实，不是本波回归失败。
- 未做真机 / TestFlight / CloudKit Production Deploy（`data-model` 已注明 `revealAuthEnabled` 发出正式包前须 Deploy；本工作不部署 Production）。
- 未用 Cmd+Shift+V 抽查 `ZL01/14` 页内跳转（本页原有锚点结构未改 id）。
- `04` 文首仍写「等待用户整体批准」——那是阶段 3 产物原文；本波未改 `04`/`05`。

---

## 6. 方法观察

- 已启用 `ZL00/04`（MAIC-1.3）。Grok 执行 W0，Codex 用阶段 4A 审计。
- 单写入者：本对话只写 W0 允许文件 + 本奇数报告。
- 未读 `tools/`。未跟踪项仍是工作包目录与 `tools/`。
- 检查器只路由、不授予执行权；本报告写完后应交 Codex 审计，不得自行开 W1。

---

## 7. 建议审计结论（供 Codex，不是自批通过）

W0 在授权清单内已把正式规格收成一套现行答案，路牌改为「`v1.13.9` 已创建、规格已回写、代码未改、未上传」。请 Codex 按 `05` 第二节独立判定通过或失败。失败则只列本波阻塞；通过后下一波才是 W1（才允许改 Swift 模型）。

写入状态：已停止
