# 多 AI 工作流自动化

本目录是长期自动化的**唯一落点**：任务契约模板、只读阶段检查器和标准库自测。不在 `tools/`、ZL02 工作包或其他目录再保留一份实现。

ZL00/04 仍是治理权威。这里的脚本只报告机械事实；与 ZL00 冲突时停止，按 [`../02-冲突裁决与变更机制.md`](../02-冲突裁决与变更机制.md) 裁决。

## 文件

| 文件 | 作用 |
| --- | --- |
| `task-contract.template.json` | 完整工作包契约模板；无注释 JSON。`checker.legacyArtifactMethodVersions` 默认为空对象：键为已废止的方法版本，值为允许保留该旧版本身份的工作包相对精确路径。不得使用前缀、通配符、空路径，也不得把当前版本回列。`checker.documentInvariants` 默认为空数组：每项登记一个工作包相对文件的字面不变量，可选启用。 |
| `check_multi_ai_workflow.py` | 只读阶段检查器 |
| `test_check_multi_ai_workflow.py` | 标准库单元测试与故障夹具 |

## 命令

在仓库根执行：

```bash
python3 ZL00_项目总控/自动化/check_multi_ai_workflow.py --work-package "<相对工作包路径>"
PYTHONDONTWRITEBYTECODE=1 python3 -B -m unittest ZL00_项目总控/自动化/test_check_multi_ai_workflow.py
```

可选 `--format json`。退出码：`0` 状态唯一；`2` 输入/JSON 无效；`3` 工作链或产物关系无效；`4` 暂存、保护路径、多写入或 Git 范围异常。非零一律停止，不自动修复。

成功输出额外包含固定声明：JSON 字段 `checkerGrantsExecutionAuthority` 恒为 `false`，`authorizationNote` 固定为“检查器只判断状态和路由，不授予下一阶段执行权限”，文本模式再输出独立一行同义提醒。`requiredUserApproval` 只说明该阶段是否还要额外批准，不表示当前对话已经获得执行授权。检查器只判断状态和路由，不授予下一阶段执行权限。

`documentInvariants` 在推导下一阶段之前执行。空数组不改变阶段推导。文件不存在、无法按 UTF-8 读取、`uniqueExactLines` 中任一行出现次数不等于 1，或命中任一 `forbiddenSubstrings` 时退出 3，只报告路径和失败规则。字段类型错误、空规则、非法路径、重复路径或同项重复规则退出 2。检查器只读，发现失败时不得修改目标文件、Git 或任务契约。

脚本只调用只读 Git 子命令，不得暂存、切换、提交或上传。
