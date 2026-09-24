# 阶段 3 · 最终实施计划

方法版本：MAIC-1.3  
阶段：3  
时间：2026-09-24  
分支：`v1.13.10`  
HEAD：`25fe006896a816475e269e155530c1464cc19304`

用户已在审阅“v1.13.10 只做结构治理与自动测试”的建议后明确授权实现、测试并在同范围内修复直至成功。本计划因此允许进入阶段 4；不把授权扩大到提交上传或下一产品阶段。

## 波次

- W1：characterization + UI-test target/harness/fixture/IDs；确保 UI harness 不关闭真实生命周期观察。
- W2：物理拆分低风险顶层类型和 SwiftUI 子视图；类型名、modifier 顺序、导航和文案不变。
- W3：物理拆分 service/controller；保持同一 actor、façade、await/WAL/commit 顺序。
- W4：一次一个 ownership：设置 committed snapshot/draft、互斥 pending action、Vault 派生/回收站、生命周期 reducer、session writer capability。经检查已单一的 gate/coordinator/clipboard 只补证明，不重写。
- W5：全量回归、三端构建、XCUITest、敏感基线、范围和文档一致性。

任一波出现产品语义变化、敏感标识漂移或无法证明等价，停止该波并回到本计划裁决，不顺手扩大。

方法观察：未发现需要迭代的方法问题。
