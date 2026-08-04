# V3 · Phase 1 — 规格与 Worker 骨架（实现提示词）

---

请启动 V3：增量规格 + Cloudflare Worker 技术栈约定，**不要**先做完整转发。

## 要点

- 创建 `specs/003-relay-service/` 增量文档
- 明确：客户端仍遵守「Apple 原生优先」；Worker 侧单独约定（TS/JS）
- 仓库内 Worker 目录骨架、本地 `wrangler` 开发方式、密钥存储方案选型记录
- 双存储一致性问题先写进 research（Keychain ↔ Worker）
- 第二档 IAP 产品 ID 已预留：`com.apirelay.iap.relay`

汇报：目录结构与技术决策摘要。


---

## 本阶段完成后（这段不要复制进实现对话）

实现 Checkpoint 通过后：

1. 打开**同目录**完整上传提示词：[`P01-save.md`](./P01-save.md)  
2. 把该文件里「请为」起的整段复制给 Cursor（会写 `BRANCHES.md` 英+中备注，在分支 `v0.3` 上 commit，打 tag **`v0.3.1`** 并 push）

不要把上传步骤粘进本次实现对话。
