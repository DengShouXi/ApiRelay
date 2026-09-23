# 阶段4A：Codex 波次复验报告（W5）

写入状态：未停止

- 阶段：4A
- 波次：W5 第三次整改复验
- 审计对象：`实施波次/W5/07-Grok波次整改报告.md`及其对应本地改动与测试证据
- 时间：2026-09-15
- 分支：`v1.13.9`
- HEAD：`6ec5ff7c67547637bbd55f528276422395e28c03`
- 方法版本：`MAIC-1.3`
- 审计方式：Codex 独立只读审计；使用独立 DerivedData 和结果包重跑关键子集

## 1. 交接与保护边界

- W0—W4已通过，W5/06 只剩测试证据阻塞；W5/07 为其后连续奇数整改报告。
- W5/07 已写`写入状态：已停止`，并正确引用 W5/06；分支、HEAD、方法版本与授权链匹配。
- W5 下原不存在`08-Codex波次复验报告.md`；本报告按连续偶数编号新建，未覆盖以前证据。
- 当前分支为`v1.13.9`，HEAD 仍为契约基线；暂存区为空，只有一个 worktree。
- `main`、`origin/main`和`release/1.0.0`保持契约固定对象；未切换分支、提交或上传。
- `git diff --check`通过；`tools/`未读取、修改或纳入范围。
- W5/07 的修改限于已批准 W5 文件集中的编译修正、待办消费修复和相关测试，未扩大产品范围。

## 2. W5/06 唯一阻塞复验

### 测试证据：已关闭

Grok 运行的七组 W5 目标测试结果包`/tmp/ApiRelayW5-07.xcresult`已由 Codex 直接读取：

- 总数：130
- 通过：130
- 失败：0
- 跳过：0
- 结论：Passed

Grok 的第一次运行曾暴露永久删除错口令后待办未消费的回归。修复后，`submitMasterPassword`在执行已取出的操作前先清掉`pendingPolicyOperation`、入口显示和口令页，错口令不会把旧删除待办泄漏给下一次输入。相关`testPermanentDeleteRetryRefreshesKeyAccountAndTool`已在最终结果中通过。

## 3. Codex 独立重跑

Codex 未复用 Grok 的 DerivedData，使用：

- DerivedData：`/tmp/ApiRelayCodexW5-08-DD`
- 结果包：`/tmp/ApiRelayCodexW5-08.xcresult`
- 测试类：`KeyVaultServiceTests`、`RevealGateCoordinatorTests`、`DataLifecycleTests`

结果包已直接读取：

- 总数：54
- 通过：54
- 失败：0
- 跳过：0
- 结论：Passed / `** TEST SUCCEEDED **`

该子集覆盖：组合档共享分流、显式应用密码、待办绑定与销毁、无验证/失败清旧授权、七种失效入口、永久删除错口令回归和清空全部数据顺序。

## 4. W5 最终判定

- 组合档无口令只走纯生物，显式非空密码只走组合档口令入口，无设备密码回落。
- App 锁、Vault、备份和设置四类生产界面均有与当前待办绑定的显式应用密码路由；离开场景会销毁待办。
- 明文显示与已验证复用授权分离；不验证、取用关闭、取消或失败不会新建或留下可读取的旧授权。
- 关详情、换 key、真正离前台、自动锁、会话锁、窗口销毁和开始编辑的失效已有生产状态转换和自动化回归保护。
- `bash ApiRelay/scripts/selfcheck.sh`红线通过，iOS 模拟器 Debug 构建已由 Grok 完成，W5 七组目标测试和 Codex 独立子集均全绿。
- 未发现新的范围、产品语义、保护分支、暂存区、worktree 或秘密泄漏阻塞。

W5 已达到当前波次停止点，可以进入 W6。

## 5. 非阻塞建议与未验证项

### 非阻塞建议

- 源码字符串配线断言仅作为 W5 过渡性保护；长期可在单独授权的 UI 可测性改造中替换，不在本波扩大。
- 超长文件整理不属于 W5，不应夹带到后续证据收尾。

### 未验证项

- 共享 scheme 全量测试、Mac Catalyst Debug/Release 构建。
- 真机 Face ID/Touch ID、VoiceOver、Dynamic Type、iPhone/iPad/Mac 布局、多窗和双设备同步。

上述均是 W6 的自动或人工证据，不阻塞 W5 独立通过。

## 6. 方法观察

本轮证明环境闸门解除后，应先由执行者跑完批量测试，再由审计者使用独立结果目录重跑风险最高的子集；这样可以同时避免自审和无意义地重跑全部测试。本次没有发现需要立即修改方法的新缺陷。

下一步负责人：Grok
是否需要用户批准：否
下一步：执行 `/Users/xitongzhili/Desktop/MacTransfer/08_Code/E02_ApiRelay_Github/ZL02_研发档案/第一阶段-密钥库/调整与优化/v1.13.9-身份验证四档与主密码调整/提示词/阶段4-Grok执行下一波.md`

写入状态：已停止

波次审计通过，可以进入下一波。
