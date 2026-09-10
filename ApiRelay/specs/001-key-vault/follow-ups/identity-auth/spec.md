# Feature Specification: 身份验证方案（Stage1 后续）

**Feature Directory**: `specs/001-key-vault/follow-ups/identity-auth`  
**Git**：现行热修线 **`v1.13.8`**（从已关账的 `v1.13.7` 开出），**不是** `v1.14` / `P14`。  
锁加固 Wave 1–3 已关在 `v1.13.7`，MUST NOT 写回那条。

**Created**: 2026-09-10

**Status**: Active — 定稿入口 [`../../../playbooks/身份验证方案.md`](../../../playbooks/身份验证方案.md)。宪法 / `001-key-vault/spec.md` 的 **FR 编号正文尚未改**（W0）。实现本热修时以本目录与 playbook 为准，不要按已覆盖的旧句写新代码。

**Input**: 2026-09-10 拍板三句——管理类凭证仍强制设备主人；出厂默认 **设备验证**；取用复用按「同一详情且未离开」，不另做秒数。

对本目录跑 implement 时 MUST `export SPECIFY_FEATURE_DIRECTORY=specs/001-key-vault/follow-ups/identity-auth`。

## 已覆盖、不得再当现行

| 旧句（仍写在宪法 / FR 正文里） | 13.8 定稿 |
|---|---|
| 出厂默认「不验证」（FR-003、data-model `none`、quickstart §1.2） | 出厂默认 **设备验证**；「不验证」仍可选 |
| 四档含「仅生物识别」`biometricOnly` | 四档：不验证 / 设备验证 / 应用密码 / 生物验证或应用密码。旧 `biometricOnly` 迁到设备验证 |
| 加密导出、永久删除的门闩 MUST NOT 可关（宪法 VIII、FR-006 `confirmMandatory`） | 不验证时导出直接走；永久删除只留破坏性确认。其他档按当前验证方式。管理类凭证仍强制设备主人 |
| 降低安全一律不可关闭的设备主人（FR-066、锁矩阵「改为不验证」） | 降低用 **当前** 验证方式确认；persist 失败界面不降 |
| 鉴权不得缓存超过单次操作（宪法 VIII、P03） | 同一详情且未离开：看完立刻复制不二弹；关详情 / 换密钥 / 离前台 / 自动锁后失效 |
| 设置只有「验证方式」管查看+复制 | 用户选三行：验证方式 / 自动锁定 / 取用验证。编辑、回收站、备份、删除不另开开关 |

编号不重排、不复用。W0 再改宪法版本与 FR-003 / FR-006 / FR-021 / FR-061 / FR-066 等正文。

## 与 13.7 的边界

13.7 已入库且关账：降级须 persist 成功、写入口过闸、快照 ≠ 计时、每窗遮罩、通知只订一处、未知 ≠ 离屏。本功能 MUST NOT 撤掉。生命周期误判规则沿用。
