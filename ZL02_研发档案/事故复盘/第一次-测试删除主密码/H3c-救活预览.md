# H3c · 救活预览

> **开工前必读**：同目录 `02-执行须知.md`。  
> **执行模型**：便宜模型即可。  
> **前置**：H3a、H3b 已执行。

---

## 这一步要达到什么（人话）

让 Xcode 画布（Preview）能直接显示 **密钥首页** 和 **设置页**，  
用假零件喂数据，**不用跑模拟器、不碰真钥匙串**。

改一行界面 → 画布刷新就能看。

---

## 改了哪些文件（已执行）

| 文件 | 动作 |
|---|---|
| `AppEnvironment.swift` | DEBUG 注入式 `init` + `makePreview()`（内存容器 + 全套 Fake） |
| `FakeKeyVault.swift` | `init(seedPreviewSample:)` 预置样例账号/密钥 |
| `FakeConsumerTools.swift` | `init(seedPreviewSample:)` 预置样例使用方 |
| `ContentView.swift` | Preview 改用 `makePreview()`（不再 `bootstrap()`） |
| `VaultHomeView.swift` | 末尾 `#Preview("Vault Home")` |
| `SettingsView.swift` | 末尾 `#Preview("Settings")` |
| 本文件 + `00-总览.md` | 进度 |

**不许**：改生产 `init(modelContainer:)` 行为；提交 git（由负责人决定）。

---

## 验证

```bash
cd ApiRelay
xcodebuild build \
  -project ApiRelay.xcodeproj \
  -scheme ApiRelay \
  -configuration Debug \
  -destination 'platform=macOS,variant=Mac Catalyst' \
  -derivedDataPath /tmp/ApiRelayAgentDD
```

通过：`BUILD SUCCEEDED`。

人工：在 Xcode 打开 `VaultHomeView.swift` / `SettingsView.swift`，打开 Canvas，选对应 Preview，应能出界面（可有样例「Preview OpenAI」等）。

---

## 做完报告格式见 `02` 第六节
