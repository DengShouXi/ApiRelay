# R03 · Grok 整改报告

写入状态：已停止

## 0. 身份

- 阶段：7S（执行 R03 整改）
- 轮次：`R03`
- 时间：2026-09-14 21:05 CST
- 分支：`v1.13.8`
- 起始 / 当前 HEAD：`bb5257fd28baf7e06c9da916fe48b278e15ec384`
- 方法版本：MAIC-1.2
- 输入：`整改轮次/R03/01-Codex整改定稿.md`、`整改轮次/R02/03-Codex复验报告.md`
- 授权：用户执行阶段 7S 提示词，确认 `R03/01`；不是提交、上传或创建 `v1.13.9` 授权
- 定稿指纹：开始前与结束后均为 `72405e27b30ebef2fc1be47a624b81f20a655261253ee9243a0e23cb278dd0a6`，与批准文件完全相等

## 1. 逐条结果

### R02-T1 协作意图不得升级为当前阶段执行授权

ZL00/04 现将唤醒、路由、执行拆成三层权限，并写明不可被后文弱化：仅协作意图只允许声明启用、绑定项目根、读取治理入口、运行只读检查器和给出下一提示词；检查器返回的下一阶段、负责人、`需要用户批准` 和提示词路径永远不是执行授权。只读检查器成功输出增加 `checkerGrantsExecutionAuthority: false`、固定 `authorizationNote` 以及文本独立一行同义提醒。AGENTS、Cursor 入口和本机技能改为短路由：仅协作意图不得读取并执行下一阶段提示词。本阶段不宣布 B7-1 / B7-3 通过；R03 黑盒留给 Codex 在 7T 用新的 `local` 任务和新对话独立重测。

### R02-T2 项目根隔离落实为工具调用边界

绑定当前项目根后，除已安装全局技能和用户明确提供的外部文件外，默认只在该根内搜索与读取。未经当前任务明确授权，不得对父目录、兄弟目录或其他仓库执行 `find` / `rg` / 文件枚举 / Git 探测，也不得调用任务列表、来源任务、父任务或其他窗口恢复需求；`source_thread_id` 只是传输信息。本机技能已写入同一边界，且静态检查不含 `ApiRelay`、`v1.13.8`、E02 路径或本工作包名称。本阶段不宣布 B7-5 通过。

### 方法版本迁移

ZL00/04 与 `00C` 现行版本为 `MAIC-1.2`。`legacyArtifactMethodVersions.MAIC-1.0` 精确路径清单保持 R03 开始时不变。新增 `MAIC-1.1` 精确清单，仅含 `R02/02`、`R02/03`、`R03/01`。`00B`、`00C` 身份和 `测试用例/01` 已改为 1.2，未列入 1.1。`R03/02` 声明 1.2。单元测试覆盖双层精确兼容、路径串版/前缀不能放行子路径、未来报告冒用 1.1、当前版本回列和损坏映射。

## 2. 实际文件

修改：

- `ZL00_项目总控/04-双AI协作与独立审计.md`
- `ZL00_项目总控/自动化/check_multi_ai_workflow.py`
- `ZL00_项目总控/自动化/test_check_multi_ai_workflow.py`
- `ZL00_项目总控/自动化/README.md`
- `AGENTS.md`
- `.cursor/rules/project-governance.mdc`
- 本包 `00-总流程操作台.md`
- 本包 `00B-自动化架构与验收口径.md`
- 本包 `00C-任务契约.json`
- 本包 `测试用例/01-唤醒与误触发测试.md`
- 本机 `/Users/xitongzhili/.agents/skills/multi-ai-collaboration/SKILL.md`（不入库）

新增：本文件。

未改：`R03/01` 与第 4.2 节全部冻结文件、提示词、契约模板、测试用例 02—04、Swift、spec、constitution、ROADMAP、`tools/`。未暂存、未提交、未创建 worktree 或 `v1.13.9`。

### 执行前基线（与 `R03/01` 第 4.1 节一致）

| 路径 | SHA-256 |
| --- | --- |
| `ZL00_项目总控/04-双AI协作与独立审计.md` | `6e0e9a26ccf448c6eba4e4827379afb46580d434d49e3dec36df30327aa4ed3b` |
| `ZL00_项目总控/自动化/README.md` | `473ca45e3f646345e84c668affc4f781eef71d2ce829da3b107a40d7b23a1617` |
| `ZL00_项目总控/自动化/check_multi_ai_workflow.py` | `366167b48bcd2c0c09975281a9640925f61337e3700b4aec202b8ce6b4c774e7` |
| `ZL00_项目总控/自动化/test_check_multi_ai_workflow.py` | `11289bdee948c1cd2b9357631881580700a250ff0e43463ba7ddb69617de6980` |
| `AGENTS.md` | `191a77a5058c844d6abc3e0afb063c3aa28d8875440a6a86cc99582e73be7068` |
| `.cursor/rules/project-governance.mdc` | `bc4f816e707da2bf69cb4f9c18e522d4d0bc717788cb5d3baa0049b5942e9007` |
| `00-总流程操作台.md` | `d30c180f0b5f3e06aca3ed87b7bf341c3dbad43103e5ef705750ffbc57b850f7` |
| `00B-自动化架构与验收口径.md` | `64ee777ff668dc44c966a45298efc7d31acd60f7e0dab07e00090874648c4b62` |
| `00C-任务契约.json` | `a585209b6413febf5079a15cc6b8b054c3dbad7196e08546f303e900e08922d4` |
| `测试用例/01-唤醒与误触发测试.md` | `3604afce0a7aeae1be410f32d86cefb647c0133a534aced842e051a9ed63870d` |
| 本机 `SKILL.md` | `ce98d801fb57821df2ce9966ef21241881e8c178792085eaf0dd8c10db8481eb` |

### 执行后指纹（供 7T 复核）

| 路径 | SHA-256 |
| --- | --- |
| `ZL00_项目总控/04-双AI协作与独立审计.md` | `4df64bb6c6589624636ac2bc35f73d459c4fd240f26fd36b145d89aa6743d0cb` |
| `ZL00_项目总控/自动化/README.md` | `5cd20ea4b6a860c89f9b4cce3ac9ad10117bbba4ea41934e38846cdc2a8eadbf` |
| `ZL00_项目总控/自动化/check_multi_ai_workflow.py` | `778a3e8f8ba6465ec9f358839765c5879daf4702f3197beb11f3b466e1a38cdd` |
| `ZL00_项目总控/自动化/test_check_multi_ai_workflow.py` | `b68b71e6520f46108c9294949907046e6cfc34efabf660f16e99d12162bbe9b4` |
| `AGENTS.md` | `bfb9bc5a5fc0b6595c244e7c2c74a6011eeb6d704bfe63f9a1a3e1c5ce8578ab` |
| `.cursor/rules/project-governance.mdc` | `b92b8ecf9e01695272dfbf9e01530ba9a4591959ba4c39b3a79c656c01eecdbd` |
| `00-总流程操作台.md` | `42472efe16ba9653c15cdd07bde61c1780bdc18359139487911e3df0dfab5a58` |
| `00B-自动化架构与验收口径.md` | `e1e712bad6b8a9563ea335f8257d2153ef8d69104160cd1c3b03fe43ca6e2dc5` |
| `00C-任务契约.json` | `9cba0d9fd9dcc5a78deb14b6fe98be9ee8433df19686bd897327165f3af1d926` |
| `测试用例/01-唤醒与误触发测试.md` | `37c625978448fd07ba5123576aa156e2a34c23eb8e13c444a69ea1ea5070b451` |
| 本机 `SKILL.md` | `0db7b62a2f7401b333392bc69ac6e9518808a531af57f70974bac24467ffb240` |

第 4.2 节冻结文件已逐项重算，全部与交接基线一致。`R03/01` 前后指纹相同。

## 3. 测试

```text
PYTHONDONTWRITEBYTECODE=1 python3 -B -m unittest ZL00_项目总控/自动化/test_check_multi_ai_workflow.py
Ran 55 tests in 8.125s
OK
```

覆盖：正常恢复 / 7R / 7S / 7T / 8 成功输出均带 `checkerGrantsExecutionAuthority: false` 与固定 `authorizationNote`；文本模式独立一行同义提醒；1.0 与 1.1 双层精确路径兼容；1.1 未列名路径退出 3；未来报告冒用 1.1 退出 3；目录前缀不能放行子路径；版本键串版、当前版本回列、损坏映射退出 2 且无 traceback。既有 F1–F6 与 R02 回归仍通过。

写本报告后只读检查器应退出 0，`methodVersion=MAIC-1.2`，唯一指向 7T、负责人 Codex，不得指向 8；成功输出须含路由不授权声明。保护引用与基线 HEAD 不变；无产品代码差异。`git diff --check` 通过。修改过的 Markdown 本地链接缺失数为 0。唯一 worktree。`bash ApiRelay/scripts/selfcheck.sh` 红线通过；本次未改 Swift。

R02 外部黑盒已真实执行并得到明确失败（B7-1、B7-3、B7-5），因此允许进入 7T。R03 新会话重测不在本阶段宣布通过。

## 4. 文件粒度

检查器现为 808 行，仍超过 400 行，未擅自拆。

## 5. 实现收尾四问

1. **外部资源**：只读 Git 状态/worktree；夹具用临时仓。未动 Keychain / SwiftData / CloudKit / UserDefaults。本机技能只改用户级技能文件，未写入仓库提交清单。未读 `tools/` 内容。
2. **失败路径**：检查器路由仍可能被模型误当成授权，因此增加了机器可见不授权声明；若 7T 黑盒仍越权执行或搜出项目根，本轮必须失败并转 R04。未列名旧产物、未来报告冒用旧版本、损坏兼容表均非零停止。
3. **接缝**：Git 写命令仍拒绝；版本迁移和路由不授权声明有隔离仓回归。跨项目黑盒没有本阶段替身，必须由 Codex 在真实新任务中验证。
4. **文件粒度**：检查器超过 400 行，已点名。

## 6. 方法观察

R02 的同类失败同时出现在 Codex 和 Cursor，说明缺口不在某一模型的措辞，而在“发现下一阶段”和“获得执行授权”没有分成两个可机器识别的状态。跨项目失败则说明项目根必须约束实际搜索和会话读取，而不能只约束最终选择。本轮只补这两道硬边界，未发现需要扩大范围的新方法缺陷。
