# 阶段 1 · 执行与检查计划

方法版本：MAIC-1.3  
阶段：1  
时间：2026-09-24  
分支：`v1.13.10`  
HEAD：`25fe006896a816475e269e155530c1464cc19304`

## 执行顺序

1. 回写启动决定、范围与不可逆标识基线。
2. 零改动基线自检和全量测试。
3. 新建 `ApiRelayUITests`、独立 UI harness、固定 fixture 与 accessibility identifiers。
4. 先拆纯顶层类型，再拆 UI 子视图，最后处理 service/controller；一次一个可回滚变更单元。
5. 只对审计确认的重复状态做 ownership 迁移：设置 committed snapshot/draft、互斥 pending action、Vault 派生/回收站、生命周期 reducer、session writer capability。
6. 每单元跑定向测试；末尾跑全量测试、三端构建、XCUITest、敏感基线与范围检查。
7. 停止写入，交由独立角色审计；不得自行提交上传。

## 检查计划

- 对照 `release-sequence.md`、现行 spec、冻结记录和实际 diff。
- 反搜第二状态权威、双 timer、生产 secret、任意 UI fixture 输入与新增持久字段。
- 核对原工作树没有被写入。
- 区分自动证据与系统/真机边界，不扩大测试结论。

方法观察：未发现需要迭代的方法问题。
