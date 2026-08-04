# V1 — 密钥保险库 Playbook

**分支**：`001-key-vault`（当前应已在此分支）  
**规格**：[`specs/001-key-vault/`](../../001-key-vault/)  
**任务权威**：[`tasks.md`](../../001-key-vault/tasks.md)（本 playbook 的提示词是粘贴入口，冲突以 tasks 为准）

## 一句话

给 API 密钥做一个比「记在备忘录里」安全得多的保管与分发工具。**完全不联网调用任何上游平台接口。**

## 明确不做（界面也不出入口）

用量、余额、适配器、探活、签发/作废、关系图、通知、中转。

## 8 个阶段

| Phase | 主题 | 提示词文件 | Checkpoint |
|-------|------|------------|------------|
| 1 | 工程配置 | [`phases/P01-工程配置.md`](./phases/P01-工程配置.md) | 可构建、空测试、Catalyst 可启动 |
| 2 | Data 层 | [`phases/P02-Data层.md`](./phases/P02-Data层.md) | Keychain 真机 + CloudKit Production schema（硬门槛） |
| 3 | US1 保管与取出 | [`phases/P03-保管与取出.md`](./phases/P03-保管与取出.md) | 录入→门闩→复制→限时清除 |
| 4 | US2 指派与双视角 | [`phases/P04-指派与双视角.md`](./phases/P04-指派与双视角.md) | 共享密钥不重复计数 |
| 5 | US5 付费解锁 | [`phases/P05-付费解锁.md`](./phases/P05-付费解锁.md) | 沙盒购买 / 恢复 / 降级只读 |
| 6 | US6 设置与备份 | [`phases/P06-设置与备份.md`](./phases/P06-设置与备份.md) | 设置立即生效；清除全部数据 |
| 7 | Mac Catalyst | [`phases/P07-Catalyst.md`](./phases/P07-Catalyst.md) | Mac 主流程 + 剪贴板实测 |
| 8 | 安全审查 | [`phases/P08-安全审查.md`](./phases/P08-安全审查.md) | 安全清单全绿；可合并 main |

依赖：`1 → 2 → (3 → 4) 与 5、6 可并行 → 7 → 8`。详见 tasks.md「依赖关系」。

## 版本收尾（全部 Phase 完成后按序执行）

1. [`10-verify.md`](./10-verify.md) — 检测  
2. [`20-push.md`](./20-push.md) — 上传  
3. [`30-create-next-branch.md`](./30-create-next-branch.md) — 创建 `002-usage-insights`  
4. [`40-checkout-next-branch.md`](./40-checkout-next-branch.md) — 切到 V2 分支  
