# V1 — Stage1 总验收（P13 之后）

**何时用**：[`phases/P13-save.md`](./phases/P13-save.md) 已把 **`v1.13`** 推上远程，且 [`P13-验收清单.md`](./phases/P13-验收清单.md) 材料块全 ✅。  
**本文件做什么**：核对 Stage1 是否达到「可申请上架」状态。  
**本文件不做什么**：不合并 `main`、不打 `release/1.0.0`、不点 ASC「提交审核」——那些在 [`12-release-T062.md`](./12-release-T062.md)，且**必须你明确授权**。

```text
P13 材料齐 + save
  → 【本文件】10-verify
  →（授权）12-release-T062
  → 20-push → 30 → 40（进 V2 playbook）
```

---

## 复制给 Cursor 的整段（从下一行开始）

请验收 **Stage1 / 大阶段 `v1`**（工作在 tip **`v1`**，应对齐 **`v1.13`**）。  
不要开始 V2 实现，不要执行 T062，除非用户在本对话里写出明确授权句。

### 0. 前置命令

```bash
git rev-parse --abbrev-ref HEAD          # 期望：v1 或 v1.13
git log -1 --oneline v1
git log -1 --oneline v1.13
# tip 应对齐（或 v1 已 fast-forward 到 v1.13）

python3 ApiRelay/.specify/scripts/python/check_prerequisites.py --json --require-tasks --include-tasks
```

### 1. 分支与台账

| # | 检查 | 期望 |
|---|------|------|
| 1.1 | 小迭代 `v1.1`…`v1.13`（含热修 `v1.11.1` 若存在） | 远程存在；`BRANCHES.md` 各有英+中备注 |
| 1.2 | tip `v1` | 与 `v1.13` tip 一致或已前进对齐，**未回退** |
| 1.3 | `00-README.md` | 当前状态写明 P13 已关 / 下一步为本 verify 或 T062 |

### 2. tasks 收口

| # | 检查 | 期望 |
|---|------|------|
| 2.1 | T056–T061 | 已勾（P08） |
| 2.2 | T014b / Checkpoint **2b** | 已勾（`v1.9`）；Production schema 未回退 |
| 2.3 | T063–T066 | 已勾，或验收清单全 ✅ 且草稿在 `store-drafts/v1.13/` |
| 2.4 | T062 | **仍为未勾**（本 verify 阶段正确） |
| 2.5 | Phase 8 执行序 | 材料在 T062 之前；无「先打 tag 再补材料」的痕迹 |

### 3. 材料与工程闸门（对照 P13 清单）

| # | 检查 | 期望 |
|---|------|------|
| 3.1 | `MARKETING_VERSION` | **`1.0.0`**（不是裸 `1.0`） |
| 3.2 | `PrivacyInfo.xcprivacy` + 加密出口声明 | 仍在工程内（FR-045 / FR-058） |
| 3.3 | IAP id | `com.apirelay.iap.unlimited_keys`；恢复购买可达（FR-028） |
| 3.4 | 商店草稿 | 无真实密钥；无「系统级强制」「无法绕过」；无中转/用量看板/探活承诺（SC-010） |
| 3.5 | 隐私对齐 | T064 表与 T059b 法律文本无矛盾（FR-024 / FR-033 / FR-044） |

### 4. 安全与体验抽检（不必重做全量 P08，但下列不过则 FAIL）

| # | 检查 | 期望 |
|---|------|------|
| 4.1 | 明文红线 | 列表/日志/SwiftData 无明文；门闩仍为查看+复制单一设置项 |
| 4.2 | quickstart §7 | 安全清单无新增红灯 |
| 4.3 | quickstart §1.1b（FR-025 / SC-001） | 「新增并指定使用方」关键确认 ≤3 步（可抽测 1～2 次） |
| 4.4 | 本地化 | 未覆盖语言回退**英语**（FR-042）；无商店材料伪装成界面开发语言 |

### 5. 汇报格式

- 总判定：PASS / FAIL（逐条列出缺口）  
- 明确写出：**T062 未执行**  
- PASS 时下一步：请用户打开 [`12-release-T062.md`](./12-release-T062.md) 并**另句授权**  
- FAIL 时：回到 P13 或对应 Phase 修补，**不要**进入 release  

---

## 本文件完成后（不要复制进 Cursor）

| 结果 | 你做什么 |
|------|----------|
| PASS | 新对话粘贴 [`12-release-T062.md`](./12-release-T062.md)，并写明「授权执行 T062」 |
| FAIL | 修缺口 → 必要时再跑本文件 |
| 暂缓上架 | 可停在 `v1` tip；**不要**为「好看」强行开 `v2` 实现线 |
