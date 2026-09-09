# 热修 — CloudKit 同步卫生后续（实现提示词）

**用法**：把下方「复制给 Cursor 的整段」原样粘贴进对话。一次只做本功能的 `tasks.md`。  
**这不是新的产品小迭代**。Git 走热修 **`v1.13.5`**；做完按 [`热修-save.md`](./热修-save.md) 保存。  
**不要叫 P14**，不要开 `v1.14`，不要把规格放进 `specs/004-*`。  
**不要**改 `.specify/feature.json`（它仍指向 `001-key-vault`，里面未勾的是商店截图 T065）。实现时用环境变量覆盖目录。

配套手测：[`热修-CloudKit同步卫生-验收清单.md`](./热修-CloudKit同步卫生-验收清单.md)（双设备 CloudKit 由你勾；Agent 代不了）。  
规格：[`../001-key-vault/follow-ups/cloudkit-sync-hygiene/`](../001-key-vault/follow-ups/cloudkit-sync-hygiene/)

---

## 复制给 Cursor 的整段（从下一行开始）

请按 **`/speckit.implement`** 的纪律执行 **`specs/001-key-vault/follow-ups/cloudkit-sync-hygiene`（CloudKit 同步卫生后续）**。  
本功能**不是**开 V2、**不是** T065 商店截图、**不是**撤掉已落地的仓库读去重 / 写打全 / 启动清扫。  
规格挂在 Stage1 后续目录，**不是** `004-*`，实现提示词也**不是** P14。

### 0. Spec Kit 前置（必须先跑命令，再改代码）

在 **Spec Kit 根目录**（含 `.specify/` 的 `ApiRelay/`，不是外层 Git 仓库根）执行，并把 JSON 贴进汇报：

```bash
git rev-parse --abbrev-ref HEAD
export SPECIFY_FEATURE_DIRECTORY=specs/001-key-vault/follow-ups/cloudkit-sync-hygiene
python3 .specify/scripts/python/check_prerequisites.py --json --require-tasks --include-tasks
```

期望：`FEATURE_DIR` 指向 `.../specs/001-key-vault/follow-ups/cloudkit-sync-hygiene`，且存在 `plan.md` / `tasks.md`。  
若 `FEATURE_DIR` 仍是 `001-key-vault`：停下来，不要去勾 T065。

然后：

1. 解析 `FEATURE_DIR` / `AVAILABLE_DOCS`（绝对路径）。  
2. 本目录无 `checklists/` 则跳过清单闸门。  
3. **必读**（按顺序）：  
   - `ApiRelay/.specify/memory/constitution.md`（明文红线、宪法 IX）  
   - `ApiRelay/specs/001-key-vault/follow-ups/cloudkit-sync-hygiene/spec.md`  
   - `ApiRelay/specs/001-key-vault/follow-ups/cloudkit-sync-hygiene/plan.md`  
   - `ApiRelay/specs/001-key-vault/follow-ups/cloudkit-sync-hygiene/research.md`  
   - `ApiRelay/specs/001-key-vault/follow-ups/cloudkit-sync-hygiene/tasks.md`  
   - `ApiRelay/specs/playbooks/热修-CloudKit同步卫生-验收清单.md`  
4. 只实现 `tasks.md` 里仍是 `- [ ]` 的项；已落地的读去重不要重写。  
5. T006（`replicaSeed`）未做 Production additive Deploy 前，MUST NOT 把该任务标完成，也 MUST NOT 发出含新字段的商店包。当前热修默认跳过 T006。  
6. T008 只能由产品负责人在手测后勾；Agent 勾了视为失败。  
7. 测试：`xcodebuild` MUST 带 `-derivedDataPath /tmp/ApiRelayAgentDD`；优先 Mac Catalyst。  
8. 做完走热修-save，不要开 `P14-save`，不要默认改 `MARKETING_VERSION`。

### 1. 本阶段目标

| 目标 | 任务 |
|------|------|
| 指纹跨 Locale 一致 | T001 |
| 导入成功后再合并清扫 | T002 |
| 手测清单在仓库里 | T003 |
| insert vs 幂等导入拆开 | T004 |
| 字段取舍表（整行 LWW，不拼接） | T005 |
| replicaSeed（additive + Deploy） | T006（现在跳过） |
| 同步单例同样折叠 | T007 |
| 双设备手测关账 | T008（产品负责人） |

### 2. 允许 / 禁止

| 允许 | 禁止 |
|------|------|
| `SyncedIdentity`、三仓库、启动/导入清扫调度、备份 insertIfAbsent | `@Attribute(.unique)`、改 CloudKit 控制台消重 |
| 偏好/权益单例去重 | 未 Deploy 就加 `replicaSeed` 并发包 |
| 验收清单 | 拼接备注当「合并」 |
| 规格放在 `001-key-vault/follow-ups/` | 把本功能写成 `004-*` 或 `phases/P14-*` / 把 T065 当成本功能 |

汇报：改了哪些文件、tasks 勾了哪几条、自检四问、双设备项仍欠谁勾。
