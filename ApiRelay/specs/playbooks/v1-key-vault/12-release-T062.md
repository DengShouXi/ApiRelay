# V1 — T062 Stage1 发布（须明确授权）

**何时用**：[`10-verify.md`](./10-verify.md) 已 **PASS**，且你准备提交 App Store **1.0.0**。  
**权威任务**：`tasks.md` **T062**（前置：Checkpoint **2b** + **T063–T066** 全绿）。  
**硬闸门**：对话里没有你写的授权句 → Agent **MUST NOT** 执行本文件任何发布步骤。

```text
10-verify PASS
  → 【本文件】T062（授权后）
  → 20-push.md（大阶段收尾核对）
  → 30 / 40（创建并切到 v2）
```

---

## 授权句（缺一不可）

请在粘贴本提示词的同一条消息里写明，例如：

> 我授权执行 T062：合并 `v1` 到 `main`，打 tag `release/1.0.0`，上传构建并提交 App Store 审核。

仅说「继续」「做完上架」**不够**。

---

## 复制给 Cursor 的整段（从下一行开始）

请**仅在用户已明确授权 T062 时**执行 Stage1 发布动作。  
未看到授权句 → 立即停止并说明缺少授权。  
不要开 V2 实现、不要改门闩/Keychain、不要重做 P13 文案（除非审核打回且用户要求）。

### 0. 再确认前置

```bash
git rev-parse --abbrev-ref HEAD
git log -1 --oneline v1
git log -1 --oneline v1.13
# MARKETING_VERSION
grep -n "MARKETING_VERSION" ApiRelay/ApiRelay.xcodeproj/project.pbxproj
```

核对：

1. `10-verify` 已 PASS（或用户书面确认等价）。  
2. `MARKETING_VERSION = 1.0.0`。  
3. T063–T066 / P13 验收清单全 ✅；ASC 元数据与截图已贴完或用户确认由他本人完成上传。  
4. T014b / 2b 仍为已完成。  
5. 本地无未提交的密钥/真实密钥截图。

### 1. T062 步骤（按仓库习惯；破坏性操作前再确认一次）

| 步 | 动作 | 说明 |
|----|------|------|
| 1 | 对齐 tip | `v1` = `v1.13` tip（或含热修后的 Stage1 tip） |
| 2 | 合并进 `main` | fast-forward 优先；冲突则停并汇报，禁止 `--force` |
| 3 | tag | 创建并推送 **`release/1.0.0`**（仅上架用 tag；禁止用 tag 当小迭代名） |
| 4 | 构建上传 | Archive → 上传 App Store Connect（可由你本人在 Xcode / Transporter 做；Agent 只协助核对） |
| 5 | 提交审核 | ASC 点提交（通常由你本人点；Agent 不得擅自点除非授权句写明） |
| 6 | 台账 | 更新 `BRANCHES.md`：注明 `release/1.0.0` 已打、T062 状态；`tasks.md` 勾选 T062 |

### 2. 禁止

- `git push --force` 到 `main` / `v1`  
- 在未授权对话中「顺手」打 tag  
- 把 `MARKETING_VERSION` 改成 2.x 或开 V2 功能  
- 用旧名分支 `v0.1.*`  

### 3. 汇报

- `main` @ `<hash>`；tag `release/1.0.0` 是否已推远程  
- ASC：已上传构建 / 已提交审核 / 待你本人点提交（三者择一写清）  
- 下一步：[`20-push.md`](./20-push.md)

---

## 本文件完成后（不要复制进 Cursor）

1. 打开 [`20-push.md`](./20-push.md) 做大阶段收尾核对。  
2. 再 [`30-create-next-branch.md`](./30-create-next-branch.md) 创建 **`v2`** tip（不要预建 `v2.1`）。  
3. 审核被拒或上架后修 bug：打开 [`../热修-save.md`](../热修-save.md)（例：`v1.13.1`），**不要**盖掉 `v1.13`，**不要**开 `release/*` 分支，**不要**假装已进 Stage2。
