# H3b · 配假零件

> **开工前必读**：同目录 `02-执行须知.md`。  
> **执行模型**：便宜模型即可（照协议抄假实现；编不过再对签名）。  
> **前置**：H3a 已执行（服务认接口）。

---

## 这一步要达到什么（人话）

给每个常用 `XxxServing` / `KeychainStoring` 插座配一个 **DEBUG 专用假零件**。  
假零件只做：内存存取 + `FakeJournal` 记调用。  
**不碰** LA、Keychain、StoreKit、CloudKit、SwiftData。

本步**不接**到 `AppEnvironment` / Preview（那是 H3c）。  
本步**不造** `FakeKeyHealth`。

---

## 改哪些文件

全部在 `ApiRelay/ApiRelay/DebugSupport/Fakes/`（同步文件夹，**不必**改 `pbxproj`）：

| # | 文件 | 认的协议 |
|---|---|---|
| 1 | `FakeKeychain.swift` | `KeychainStoring` |
| 2 | `FakeRevealGate.swift` | `RevealGateServing` |
| 3 | `FakeClipboard.swift` | `ClipboardServing` |
| 4 | `FakeKeyVault.swift` | `KeyVaultServing` |
| 5 | `FakeConsumerTools.swift` | `ConsumerToolServing` |
| 6 | `FakeRecentlyDeletedBatch.swift` | `RecentlyDeletedBatchServing` |
| 7 | `FakeEntitlements.swift` | `EntitlementServing` |
| 8 | `FakePreferences.swift` | `PreferencesServing` |
| 9 | `FakeMasterPassword.swift` | `MasterPasswordServing` |
| 10 | `FakeBackupPassphrase.swift` | `BackupPassphraseServing` |
| 11 | `FakeSecureBackup.swift` | `SecureBackupServing` |
| 12 | `FakeDataLifecycle.swift` | `DataLifecycleServing` |
| 13 | `FakeCloudSync.swift` | `CloudSyncServing` |

另外：

| 文件 | 动作 |
|---|---|
| 同目录 `00-总览.md` | 勾选 H3b 已完成 |
| 本文件 `H3b-配假零件.md` | 执行提示词（本文件） |

已有、**勿改业务语义**：`FakeSupport.swift`（`FakeJournal` + DTO 样例助手）。

---

## 不许碰的文件

- 任何 `Business/**` 真服务实现
- `AppEnvironment.swift`（组装仍用真零件）
- `pbxproj` / specs / 宪法
- **不许** `git commit`

---

## 实现约定（照抄）

1. 每个文件整文件包在 `#if DEBUG` … `#endif`。
2. `actor FakeXxx: XxxServing`（或 `KeychainStoring`）。
3. `var journal = FakeJournal()`；每个方法开头 `try journal.record("methodName")` 或 `recordNonThrowing`。
4. Keychain 读 miss → `throw ApiRelayError.keychainFailure(errSecItemNotFound)`（`import Security`）。
5. `availableBiometry` 必须是 `nonisolated`。
6. `PreferencesServing.persist` 是 `nonisolated`：假实现用可跨隔离的 Store 箱同步合 patch，再 `Task` 记 journal。
7. `SecureBackupServing.inspectProtection` 是同步 `throws`。
8. `EntitlementServing` 含 `startListening` / `purgeLocalSnapshotForErase` / DEBUG `debugOverride`。

---

## 验证

工作目录 `ApiRelay/`：

```bash
rm -rf /tmp/ApiRelayAgentDD
xcodebuild build \
  -project ApiRelay.xcodeproj \
  -scheme ApiRelay \
  -configuration Debug \
  -destination 'platform=macOS,variant=Mac Catalyst' \
  -derivedDataPath /tmp/ApiRelayAgentDD
```

通过：`BUILD SUCCEEDED`。

（本步不强制跑 test / selfcheck；编过即可。）

---

## 第 4 步 · 更新 `00-总览.md`

勾选 `H3b` 已完成；文件清单标 H3b 已执行。  
**MUST NOT** commit。

按 `02` 第六节报告。

---

## 执行记录（2026-09-04）

- 新建上表 13 个假零件；协议签名与 H3a 后现状对齐。
- Mac Catalyst Debug：`BUILD SUCCEEDED`。
- 协议缺口：无（H3a 已补齐本步需要的方法）。
- 未造 `FakeKeyHealth`；未改生产服务；未 commit。
