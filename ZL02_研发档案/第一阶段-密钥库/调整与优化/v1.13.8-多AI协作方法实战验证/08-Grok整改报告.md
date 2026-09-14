# 08 · Grok 整改报告

写入状态：已停止

## 0. 身份与结论

- 阶段：6（Grok 修复阻塞问题）
- 时间：2026-09-11 16:15 CST
- 分支：`v1.13.8`
- 起始 / 当前 HEAD：`bb5257fd28baf7e06c9da916fe48b278e15ec384`
- 方法版本：MAIC-1.0
- 输入：`04-最终执行计划.md`、`05-最终检查计划.md`、`07-Codex独立审计报告.md`
- 授权：用户执行阶段 6 提示词；只修复 `07` 的 B1–B8；不是提交或上传授权
- 总结论：B1–B6、B8 已在本包与检查器中形成可重复回归；B7 黑盒唤醒按 `05` 保持 **未验证**，不得假装通过。

## 1. 逐条阻塞

### B1 白名单未执行

- 修复：检查器对 `git status --porcelain=v1 -z -uall` 的每一条路径执行 `allowedModify` / `allowedAdd` / `allowedPrefixes`；计划外退出 4。`knownUntracked` 仅当状态为 `??` 时放过。
- `00C` 增加工作包 `allowedPrefixes`，并把 `08` 列入 `allowedAdd`，与 `04` 2.1 已批准的本包操作台、测试用例、提示词对齐。
- 测试输入：隔离仓根目录新增 `unexpected.txt`。
- 结果：退出 4，`test_whitelist_rejects_unlisted_file`。

### B2 验收通过后闸门被绕过

- 修复：任何阶段暂存非空都退出 4。`tools/` 已暂存不再被当成未跟踪基线。HEAD 离开基线时必须 `uploadTrackingRefs`（`v1`、`origin/v1`、`origin/v1.13.8`）等于当前 HEAD，且 `protectedRefs`（`main`、`origin/main`、`release/1.0.0`）未被动、`v1.13.9` 不存在；否则退出 3。通过且 HEAD 仍为基线 → 阶段 8。
- 测试：验收后 `git add staged.txt` / `git add tools/x.txt` → 退出 4；提交使 HEAD 前进但跟踪 refs 未跟上 → 退出 3；跟踪 refs 对齐 → `nextPhase=9`。

### B3 身份与固定结论可伪造

- 修复：`strictIdentityArtifacts` 覆盖 `06`/`07`/`08`/`09`；缺分支、HEAD 或方法版本退出 3。固定结论只在文首 20 行 + 文末 15 行窗口、去掉 `**` 后作为独立行或 `总结论：`+原句匹配。`07` 使用契约 `phase5Fail`：`审计不通过，存在阻塞问题，不得进入阶段7或8。` 未改 `07` 正文。
- 未把严格身份套到冻结的 `01`–`05`。
- 测试：`06.md` 去掉身份 → 退出 3；`09.md` 只引用通过句 → 仍指向阶段 7，不进 8；`07.md` 独立失败句 → 阶段 6。

### B4 RNN 缺 02 仍可放行

- 修复：最新轮有 `03` 时必须同时有 `01` 和 `02`；三份都做严格身份检查；缺则退出 3。
- 测试：`R01` 只有 `01`+`03` 通过句 → 退出 3，`整改链不完整`。

### B5 下一提示词可以不存在

- 修复：算出路径后必须 `is_file()`；缺失则退出 2，并指出通用提示词。
- 测试：删除将返回的 `阶段5.md` → 退出 2。

### B6 单写入者 / 多 worktree

- 修复：契约 `writerStatus.files` 只扫 `06`/`08` 及 RNN `02`。契约外 worktree 退出 4；`allowedReadOnlyWorktrees` 内只读树允许。提示词 4/6/7S 要求写完声明 `写入状态：已停止`。本报告文首已声明。
- 测试：`06.md`+`08.md` 双“未停止” → 退出 4；`note.md` 引用该句 → 退出 0；额外 worktree → 4；列入只读名单 → 0。

### B7 黑盒唤醒未做

- 在 `测试用例/01` 写入不依赖本对话的 B7-1–B7-5 规程（新 Codex 任务、新 Cursor 对话、另一规则仓库）。
- 本阶段无法新建那些会话，**保持未验证**。阶段 7 因此可以继续不通过；这是预期，不是本阶段伪造通过的理由。

### B8 自测未覆盖绕过；unittest 写缓存

- 夹具从 15 项扩到 29 项，覆盖 B1–B6 隔离故障；`module.git(repo, "add", ...)` 行为级拒绝，退出 4。
- 命令改为 `PYTHONDONTWRITEBYTECODE=1 python3 -B -m unittest ZL00_项目总控/自动化/test_check_multi_ai_workflow.py`。已回写 `自动化/README.md` 与 `ZL00/04`；**未改**冻结的 `04`/`05` 计划正文。
- 本阶段不删除已有 `ZL00_项目总控/自动化/__pycache__/`，也未清理其他未跟踪内容。

未处理 `07` 非阻塞建议 2（不把 ZL00/04 抄进提示词或 ZL01）。建议 1 已并入 B6。

## 2. 实际文件

修改：`ZL00_项目总控/04-双AI协作与独立审计.md`、`ZL00_项目总控/自动化/*`、本包 `00C`、`00`、`00B`、`测试用例/01`–`02`、提示词阶段 4/6/7S。

新增：本文件 `08-Grok整改报告.md`。

未改：Swift、测试、Xcode、constitution、ROADMAP、身份验证 spec/playbook、`01`–`05`/`03`/`07` 冻结或历史产物、`tools/`。

## 3. 测试输入与结果

```text
PYTHONDONTWRITEBYTECODE=1 python3 -B -m unittest ZL00_项目总控/自动化/test_check_multi_ai_workflow.py
Ran 29 tests in 4.165s
OK
```

写本报告前，只读检查器对本包：退出 0，`nextPhase=6`，`owner=Grok`。写完后再跑一次，预期指向阶段 7、负责人 Codex。

保护现场：HEAD=`bb5257fd28baf7e06c9da916fe48b278e15ec384`；`main`=`origin/main`=`539447ea9984608c74989da48b8770cb3fe32a6c`；`release/1.0.0`=`5c5eed3f8390f51f5a26be9737bcc11f72e7d7fd`；`v1`=`origin/v1`=`origin/v1.13.8`=基线 HEAD；无 `v1.13.9`；暂存区空；无产品代码差异；`git diff --check` 通过。

`bash ApiRelay/scripts/selfcheck.sh`：红线通过。本次未改 Swift。

## 4. 文件粒度

`ZL00_项目总控/自动化/check_multi_ai_workflow.py` 约 585 行，超过 400 行。未擅自拆分，交由用户决定是否另开整理。

## 5. 实现收尾四问

1. **外部资源**：碰到 Git 仓库状态、refs、worktree 列表；检查器只读。单元测试只用临时隔离仓，不写主仓 Keychain / SwiftData / CloudKit。自测用 `-B` 避免新字节码；既有 `__pycache__/` 未删。未读 `tools/` 内容，只允许其 `??` 路径出现在 status。
2. **失败路径**：计划外文件、暂存、缺身份、缺提示词、RNN 断链、契约外 worktree 均非零停止。B7 未验证时阶段 7 应判不通过，用户可另开新会话补跑黑盒，不必退回阶段 3。
3. **接缝**：检查器对 Git 子命令有只读白名单；测试以隔离仓和直接调用 `git("add")` 为替身，不碰真实远程。
4. **文件粒度**：检查器 585 行，已在上一节点名。

## 6. 方法观察

- 问题类别：确定性阶段检查 / 故障注入不足。
- 触发条件：白名单外文件、验收后暂存、缺身份、引用结论句、RNN 缺执行报告、提示词缺失、真实多编辑器。
- 失效闸门：范围、独立验收、上传、阶段唯一性。
- 主要后果：检查器曾错误退出 0。
- 指纹：与 `07` 相同，`stage-recovery + adversarial artifact/state + scope/acceptance/upload gate + false-safe continuation`。
- 本次只修已证实阻塞并加回归；B7 仍待独立黑盒，不把本对话算作唤醒证据。

下一步负责人：Codex
是否需要用户批准：否
下一步：执行 `/Users/xitongzhili/Desktop/MacTransfer/08_Code/E02_ApiRelay_Github/ZL02_研发档案/第一阶段-密钥库/调整与优化/v1.13.8-多AI协作方法实战验证/提示词/阶段7-Codex最终验收.md`
