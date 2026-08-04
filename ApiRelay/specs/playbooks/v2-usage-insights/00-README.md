# V2 — 用量看板与关系图 Playbook

**分支**：`002-usage-insights`（必须从已合并 V1 的 `main` 切出）  
**规格位置**：`specs/002-usage-insights/`（启动时创建增量文档）  
**范围权威**：[ROADMAP.md](../../ROADMAP.md) V2 节  
**说明**：下列 Phase 为按 ROADMAP 预拆的**草案**。正式开发前请生成 `tasks.md`，冲突以 tasks 为准。

## 一句话

让用户知道每一把密钥、每一个工具花了多少钱；并支持探活、关系图、加密传递。

## 依赖

V1 数据模型与保管能力；CloudKit 预留健康度字段已在 V1 部署。

## 8 个阶段（草案）

| Phase | 主题 | 提示词 |
|-------|------|--------|
| 1 | 规格与网络骨架 | [`phases/P01-规格与网络骨架.md`](./phases/P01-规格与网络骨架.md) |
| 2 | 管理凭证 + 四平台适配器 | [`phases/P02-管理凭证与适配器.md`](./phases/P02-管理凭证与适配器.md) |
| 3 | 用量/余额刷新与诚实呈现 | [`phases/P03-用量与余额.md`](./phases/P03-用量与余额.md) |
| 4 | 密钥可用性检测（US10） | [`phases/P04-密钥探活.md`](./phases/P04-密钥探活.md) |
| 5 | App 内签发与作废（US3） | [`phases/P05-签发与作废.md`](./phases/P05-签发与作废.md) |
| 6 | 关系图（US8） | [`phases/P06-关系图.md`](./phases/P06-关系图.md) |
| 7 | 加密传递 + 通知（US9） | [`phases/P07-加密传递与通知.md`](./phases/P07-加密传递与通知.md) |
| 8 | 上架材料与收尾 | [`phases/P08-上架与收尾.md`](./phases/P08-上架与收尾.md) |

## 版本收尾

1. [`10-verify.md`](./10-verify.md)  
2. [`20-push.md`](./20-push.md)  
3. [`30-create-next-branch.md`](./30-create-next-branch.md) → `003-relay-service`  
4. [`40-checkout-next-branch.md`](./40-checkout-next-branch.md)  
