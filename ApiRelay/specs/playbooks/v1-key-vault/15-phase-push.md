# V1 — 小 Phase 保存与上传（索引）

**不要用本文件代替 Phase 专用提示词。** 每个小阶段请打开对应的完整文件（备注格式、分支、tag 都已写死）：

| Phase | 提示词 | 分支 | tag |
|-------|--------|------|-----|
| 1 | [`phases/P01-save.md`](./phases/P01-save.md) | `v0.1` | `v0.1.1` |
| 2 | [`phases/P02-save.md`](./phases/P02-save.md) | `v0.1` | `v0.1.2` |
| 3 | [`phases/P03-save.md`](./phases/P03-save.md) | `v0.1` | `v0.1.3` |
| 4 | [`phases/P04-save.md`](./phases/P04-save.md) | `v0.1` | `v0.1.4` |
| 5 | [`phases/P05-save.md`](./phases/P05-save.md) | `v0.1` | `v0.1.5` |
| 6 | [`phases/P06-save.md`](./phases/P06-save.md) | `v0.1` | `v0.1.6` |
| 7 | [`phases/P07-save.md`](./phases/P07-save.md) | `v0.1` | `v0.1.7` |
| 8 | [`phases/P08-save.md`](./phases/P08-save.md) | `v0.1` | `v0.1.8` |

统一规则（各 `P0N-save.md` 已写明，此处仅摘要）：

1. 人留在分支 **`v0.1`** 上 commit  
2. 第三层是 **tag `v0.1.N`**，禁止新建同名分支  
3. `BRANCHES.md` 必须先 English、后简体中文  
4. `git push origin v0.1` + `git push origin refs/tags/v0.1.N`  
5. 禁止 force push；禁止预建 `v0.2`/`v0.3`/`v0.4`
