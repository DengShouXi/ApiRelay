# V3 — 中转服务 Playbook

**分支**：`003-relay-service`  
**范围权威**：[ROADMAP.md](../../ROADMAP.md) V3 节  
**Phase 为草案**；正式以启动时生成的 `tasks.md` 为准。

## 一句话

在用户自己的 Cloudflare 账号上架一层中转，让下游工具配置**永久不用因上游换钥而改**。

## 精髓（勿理解错）

中转密钥是稳定间接层：上游轮换只改 Worker 侧原始密钥，下游配置不动。次要好处才是隔离与自主用量。

## 7 个阶段（草案）

| Phase | 主题 | 提示词 |
|-------|------|--------|
| 1 | 规格 + Worker 仓库骨架 | [`phases/P01-规格与Worker骨架.md`](./phases/P01-规格与Worker骨架.md) |
| 2 | 部署引导体验 | [`phases/P02-部署引导.md`](./phases/P02-部署引导.md) |
| 3 | 原始密钥托管 + 中转密钥签发 | [`phases/P03-托管与签发.md`](./phases/P03-托管与签发.md) |
| 4 | 请求转发（含流式） | [`phases/P04-请求转发.md`](./phases/P04-请求转发.md) |
| 5 | 逐笔用量 + 原始密钥轮换 | [`phases/P05-用量与轮换.md`](./phases/P05-用量与轮换.md) |
| 6 | 可撤销共享 + 第二档买断 | [`phases/P06-共享与买断.md`](./phases/P06-共享与买断.md) |
| 7 | 隐私重写与收尾 | [`phases/P07-隐私与收尾.md`](./phases/P07-隐私与收尾.md) |

## 版本收尾

1. [`10-verify.md`](./10-verify.md)  
2. [`20-push.md`](./20-push.md)  
3. [`30-create-next-branch.md`](./30-create-next-branch.md)（产品线收官说明）  
4. [`40-checkout-next-branch.md`](./40-checkout-next-branch.md)（回到 main / 发布分支）  
