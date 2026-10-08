# 多 AI 工作流自动化

本目录是长期自动化的**唯一落点**：任务契约模板、只读阶段检查器和标准库自测。不在 `tools/`、ZL02 工作包或其他目录再保留一份实现。

ZL00/04 仍是治理权威。这里的脚本只报告机械事实；与 ZL00 冲突时停止，按 [`../02-冲突裁决与变更机制.md`](../02-冲突裁决与变更机制.md) 裁决。

## 文件

| 文件 | 作用 |
| --- | --- |
| `task-contract.template.json` | 可选的**阶段式**工作包契约模板，不是所有新任务的必填文件；无注释 JSON。新包用 `MAIC-1.4.0`，`worktreeIsolation: scoped`，`uploadTrackingRefs` 初始为空，须填入本次获准推进的分支及远端引用，绝不默认 `v1`。`PROTECTED_REF_TO_REPLACE` 必须换成本任务实际保护引用，空路径和角色也必须填实；禁止直接复制模板运行检查器。`authorizationRecord` 只记录用户指令来源和范围，自填内容不产生授权。旧版契约与报告保留原身份。`checker.legacyArtifactMethodVersions` 仅精确列出旧产物路径，不用通配；`documentInvariants` 可选。 |
| `check_multi_ai_workflow.py` | 只读阶段检查器 |
| `test_check_multi_ai_workflow.py` | 标准库单元测试与故障夹具 |
| `check_governance_consistency.py` | 只读检查当前治理入口的方法版本、契约默认引用、废止的强制上传语句及单 AI／对话归档路由；不扫描历史档案 |
| `test_check_governance_consistency.py` | 对版本、旧上传硬规则和单 AI／对话归档漂移做故障注入；不改真实仓库 |

## 命令

在仓库根执行：

```bash
python3 ZL00_项目总控/自动化/check_multi_ai_workflow.py --work-package "<相对工作包路径>"
PYTHONDONTWRITEBYTECODE=1 python3 -B -m unittest ZL00_项目总控/自动化/test_check_multi_ai_workflow.py
PYTHONDONTWRITEBYTECODE=1 python3 -B ZL00_项目总控/自动化/check_governance_consistency.py
PYTHONDONTWRITEBYTECODE=1 python3 -B -m unittest ZL00_项目总控/自动化/test_check_governance_consistency.py
```

可选 `--format json`。退出码：`0` 状态唯一；`2` 输入/JSON 无效；`3` 工作链或产物关系无效；`4` 暂存、保护路径、多写入或 Git 范围异常。非零一律停止，不自动修复。

成功输出额外包含固定声明：JSON 字段 `checkerGrantsExecutionAuthority` 恒为 `false`，`authorizationNote` 固定为“检查器只判断状态和路由，不授予下一阶段执行权限”，文本模式再输出独立一行同义提醒。`requiredUserApproval` 只说明该阶段是否还要额外批准，不表示当前对话已经获得执行授权。检查器只判断状态和路由，不授予下一阶段执行权限。

`documentInvariants` 在推导下一阶段之前执行。空数组不改变阶段推导。文件不存在、无法按 UTF-8 读取、`uniqueExactLines` 中任一行出现次数不等于 1，或命中任一 `forbiddenSubstrings` 时退出 3，只报告路径和失败规则。字段类型错误、空规则、非法路径、重复路径或同项重复规则退出 2。检查器只读，发现失败时不得修改目标文件、Git 或任务契约。旧版 `MAIC-1.3.1` 契约可只读诊断，但下一次写入前须迁移并复验；检查器不把旧阶段路由当成新方法授权。

新契约 `repository.worktreeIsolation: scoped` 时，当前实施树和明确列为依赖的只读树受严格检查；其他未关联工作树只报告，不因它们脏或未登记退出 4。旧契约缺该字段时沿用 `strict`，其冻结快照语义不变。任何模式下当前树的暂存、越界差异和写入冲突仍阻断。不能通过清理用户文件求通过。

新版 `schemaVersion: 1.1` 契约若登记上传 refs，必须在 `authorizationRecord` 写入非空用户指令来源、`push` 操作及与 `uploadTrackingRefs` 精确一致的 `targetRefs`，并至少跟踪 `origin/` 引用。脚本只验字段自洽和本地追踪引用，不能证明来源确由用户给出，也不能代替阶段 9 的远端实时 SHA 复核；人工仍须核对用户原话和远端现场。

同一实施树内经独立审计的外部治理差异可列入 `repository.frozenExternalFiles`，每项为精确 `path`、两字符 Git `status`、普通文件 `kind`、整数 `mode` 和内容 `sha256`，同时填写 `frozenExternalReview` 指向清单内已停止且含独立通过结论的审计报告。冻结只排除完全一致的外部差异，不授予修改权；任何新路径、内容、文件类型、权限或 Git 状态变化仍失败。方法升版时，旧阶段产物须通过精确 legacy 映射保留原身份。

脚本只调用只读 Git 子命令，不得暂存、切换、提交或上传。
