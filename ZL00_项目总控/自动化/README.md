# 治理检查工具

本目录是长期自动化的**唯一落点**：多 AI 契约、单/多 AI 共用的方法阶段记录模板、只读检查器和标准库自测。不在 `tools/`、ZL02 工作包或其他目录再保留一份实现。

[`ZL00/04`](../04-双AI协作与独立审计.md) 与 [`ZL00/06`](../06-方法迭代闭环.md) 是相应治理权威。这里的脚本只报告机械事实；与 ZL00 冲突时停止，按 [`../02-冲突裁决与变更机制.md`](../02-冲突裁决与变更机制.md) 裁决。

## 文件

| 文件 | 作用 |
| --- | --- |
| `task-contract.template.json` | 仅供**实际多 AI 工作包**实例化的契约模板；无注释 JSON。角色、文件名、批准的跟踪 refs 都要按任务填写，不沿用示例。`checker.legacyArtifactMethodVersions` 仅精确列出允许保留旧版本身份的历史产物；`checker.documentInvariants` 可选登记字面文档不变量。 |
| `check_multi_ai_workflow.py` | 只读阶段检查器 |
| `test_check_multi_ai_workflow.py` | 标准库单元测试与故障夹具 |
| `check_governance_routes.py` | 只读核对现行单/多 AI 路由、方法版本与上传硬规则是否漂移；不扫描或改写历史报告 |
| `method-stage-record.template.json` | 标准/高风险新任务逐阶段记录的空模板；按已批准计划填写阶段名，轻量任务不强制使用 |
| `check_method_iteration.py` | 只读核对逐阶段记录、问题指纹索引、已解决问题的回归证据和未关阻塞项 |
| `test_check_method_iteration.py` | 上一检查器的标准库单元测试与失败夹具 |

## 命令

在仓库根执行：

```bash
python3 ZL00_项目总控/自动化/check_multi_ai_workflow.py --work-package "<相对工作包路径>"
PYTHONDONTWRITEBYTECODE=1 python3 -B -m unittest ZL00_项目总控/自动化/test_check_multi_ai_workflow.py
python3 -B ZL00_项目总控/自动化/check_governance_routes.py
python3 -B ZL00_项目总控/自动化/check_method_iteration.py --record "<工作包内的相对记录路径>" --require-stage "<本阶段名>"
python3 -B ZL00_项目总控/自动化/check_method_iteration.py --record "<工作包内的相对记录路径>" --final
PYTHONDONTWRITEBYTECODE=1 python3 -B -m unittest ZL00_项目总控/自动化/test_check_method_iteration.py
```

方法阶段记录只用于按新版方法建立的标准/高风险任务。实例化模板时先填写 `taskId`、`riskLevel`（`standard`/`high`）和 `expectedStages`（获批计划的全部实质阶段）；每完成一阶段才向 `checks` 加一条：`stage`、`verdict`（`clear`/`issue`）、具体 `evidence`、`issueIds`。有真实问题时再向 `issues` 加 `id`（`MI-YYYYMMDD-NN`）、`category`（`method`/`product`/`external`/`execution`）、`fingerprint`、`impact`（`blocking`/`nonblocking`）、`status`（`open`/`deferred`/`resolved`）、`evidence` 和 `action`。方法问题另填 `regressionCase` 与 `regressionResult`（`pending`/`pass`），并把 ID、指纹、本记录路径登记在 [`ZL02/方法问题索引.json`](../../ZL02_研发档案/方法问题索引.json)；相同指纹沿用同一 ID。索引不复制结论。实例见本次 [`方法阶段记录.json`](../../ZL02_研发档案/第一阶段-密钥库/调整与优化/方法体系单AI适配/方法阶段记录.json)。

`checks` 必须按 `expectedStages` 的顺序逐项追加，不能跳过前一步预填后一步。`check_method_iteration.py` 退出码：`0` 结构与请求的阶段闸门通过（不等于产品验收、独立审计或上传授权）；`2` JSON、字段或路径无效；`3` 阶段缺失、顺序跳步、应关联而未关联的问题、假称回归通过或阻塞方法问题未关。阶段中途用 `--require-stage`，最终用 `--final`；输出的待验证数量要回原记录看分类，外部服务待验证不能被脚本转成真实验收通过。历史工作包不倒填新版记录。

方法问题还须写 `indexStatus`：通常为 `linked`，索引必须指向本记录。若用户批准的封闭文件清单不含索引，只能把**非阻塞**方法问题标为 `deferred`、`indexStatus: pending_scope`，另填 `indexReason` 和具体后续动作；检查器显示待办，不把它算作问题已解决，也不为此阻断无关产品任务。阻塞方法问题不能用此例外绕过。若连阶段记录也不在批准范围内，按 [`06`](../06-方法迭代闭环.md) 在允许的报告或最终答复说明，不能为凑检查结果越界建文件或声称方法闭环已通过。

可选 `--format json`。退出码：`0` 状态唯一；`2` 输入/JSON 无效；`3` 工作链或产物关系无效；`4` 暂存、保护路径、多写入或 Git 范围异常。非零一律停止，不自动修复。

成功输出额外包含固定声明：JSON 字段 `checkerGrantsExecutionAuthority` 恒为 `false`，`authorizationNote` 固定为“检查器只判断状态和路由，不授予下一阶段执行权限”，文本模式再输出独立一行同义提醒。`requiredUserApproval` 只说明该阶段是否还要额外批准，不表示当前对话已经获得执行授权。检查器只判断状态和路由，不授予下一阶段执行权限。

`documentInvariants` 在推导下一阶段之前执行。空数组不改变阶段推导。文件不存在、无法按 UTF-8 读取、`uniqueExactLines` 中任一行出现次数不等于 1，或命中任一 `forbiddenSubstrings` 时退出 3，只报告路径和失败规则。字段类型错误、空规则、非法路径、重复路径或同项重复规则退出 2。检查器只读，发现失败时不得修改目标文件、Git 或任务契约。

其他未登记 worktree 仅报告路径，不因其已有无关差异退出 4，也不读取其文件或授予写入权。若本任务**明确依赖**某只读 worktree，才列入 `repository.allowedReadOnlyWorktrees` 并要求洁净；已有脏树确需作为冻结输入时，登记 `readOnlyWorktreeSnapshots` 的规范绝对 `path`、`branch`、完整 `head` 和 `fingerprint`。快照覆盖 Git 可见状态与文件类型、权限、内容，不覆盖 Git 忽略文件；任何漂移仍退出 4。不能通过清理用户文件求通过。

新契约模板不预填 `v1` 或其他上传跟踪引用。工作包必须按实际授权填写 `uploadTrackingRefs`；HEAD 离开基线而该数组为空时，检查器退出 3，不能把“有提交”冒充“已核对授权远端”。
`sourceKind`、`riskLevel`、目标、实施 worktree、基线和保护 refs 也必须按任务实例化；模板不再默认禁止整个 App/测试目录、不再默认忽略 `tools/` 或预设某个发布 tag。单 AI 任务不使用这份多 AI 契约。
检查器只读本地 Git 引用；即使本地 `origin/*` 相等，也不能替代阶段 9 对实时远端 SHA 的独立读取。网络故障时阶段 9 结果保持未复核。

既有 `MAIC-1.3.1` 等历史工作包保持其原分支与方法快照，不批量改写历史契约或报告。确需在新基线续办时，先制定精确迁移记录和产物版本映射，再由新方法检查器接管；不能仅把契约版本字符串改新来绕过身份检查。

同一实施树内经独立审计的外部治理差异可列入 `repository.frozenExternalFiles`，每项为精确 `path`、两字符 Git `status`、普通文件 `kind`、整数 `mode` 和内容 `sha256`，同时填写 `frozenExternalReview` 指向清单内已停止且含独立通过结论的审计报告。冻结只排除完全一致的外部差异，不授予修改权；任何新路径、内容、文件类型、权限或 Git 状态变化仍失败。方法升版时，旧阶段产物须通过精确 legacy 映射保留原身份。

脚本只调用只读 Git 子命令，不得暂存、切换、提交或上传。
