# H3a · 服务改认接口

> **开工前必读**：同目录 `02-执行须知.md`。  
> **执行模型**：**贵模型**（跨文件；协议缺方法要现场补）。  
> **前置**：H1、H2 已执行。

---

## 这一步要达到什么（人话）

现在很多服务写死了「必须是某某真零件」。  
改成「只要符合插座标准（protocol）就行」。  
这样下一步（H3b）才能插假零件；本步**还不造假零件**。

App 界面看起来应该几乎没变化。

## 改哪些文件

1. 先扩协议（缺口补齐）  
2. 再改 7 个服务 + `AppEnvironment` 的类型声明  
3. 更新 `StubEntitlements`（若协议新增了它必须实现的方法）  
4. 更新同目录 `00-总览.md` 进度  

**不许**：改 UI 业务逻辑、改宪法/specs（除本步骤不要求）、提交 git、开 H3b。

---

## 第 1 步 · 补协议缺口

### `RevealGateServing.swift`

增加：

```swift
/// 选用主密码门闩前确认本机已设密。
func ensureMasterPasswordConfigured() async throws
```

并把已有 `availableBiometry()` 标成 `nonisolated`（与实现一致，方便 UI 无 await 调用）：

```swift
nonisolated func availableBiometry() -> BiometryKind
```

### `KeyVaultServing.swift`

增加：

```swift
func purgeAllRecordsForErase() async throws
func preflightRestoreQuota(keyIds: [UUID], accountIds: [UUID]) async throws
func restoreDeletedAfterAuthentication(keyIds: [UUID], accountIds: [UUID]) async -> TrashBatchOutcome
func permanentlyDeleteDeletedAfterAuthentication(keyIds: [UUID], accountIds: [UUID]) async -> TrashBatchOutcome
```

### `ConsumerToolServing`（在 `ConsumerToolService.swift` 顶部 protocol）

增加：

```swift
func restoreToolsAfterAuthentication(ids: [UUID]) async -> TrashBatchOutcome
func permanentlyDeleteToolsAfterAuthentication(ids: [UUID]) async -> TrashBatchOutcome
func purgeAllRecordsForErase() async throws
```

### `PreferencesServing`

增加：

```swift
func purgeAllRecordsForErase() async throws
```

### `EntitlementServing`

增加：

```swift
func startListening()
func purgeLocalSnapshotForErase() async throws
```

### `StubEntitlements`

为新增的 `startListening` / `purgeLocalSnapshotForErase` 提供空实现（或合理 no-op）。

---

## 第 2 步 · 服务与组装根改类型

| 文件 | 改法 |
|---|---|
| `KeyVaultService` | `keychain: KeychainStoring`；`gate: RevealGateServing` |
| `ConsumerToolService` | `gate: RevealGateServing` |
| `RecentlyDeletedBatchService` | `vault: KeyVaultServing`；`consumerTools: ConsumerToolServing`；`gate: RevealGateServing` |
| `DataLifecycleService` | `gate`/`keychain`/`vault`/`consumerTools`/`preferences`/`entitlements` 全部改对应 Serving / Storing |
| `SecureBackupService` | `gate: RevealGateServing`；`keychain: KeychainStoring` |
| `MasterPasswordService` | `keychain: KeychainStoring`（`KeychainStore.masterPasswordAccount` 静态常量可保留） |
| `BackupPassphraseService` | `keychain: KeychainStoring` |
| `AppEnvironment` | 对外属性改为 `any XxxServing` / `any KeychainStoring` / `any ClipboardServing`；**组装处仍 `XxxService(...)` 真实现** |
| `VaultHomeViewModel` | `vault` / `environmentVault` 改为 `any KeyVaultServing`（否则接不上已改类型的 `environment.vault`） |

`AppPrivacyController` 已是 protocol，**不要改**。

---

## 第 3 步 · 验证

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

```bash
xcodebuild test \
  -project ApiRelay.xcodeproj \
  -scheme ApiRelay \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath /tmp/ApiRelayAgentDD \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_ALLOWED=YES \
  CODE_SIGNING_REQUIRED=YES
```

通过：`TEST SUCCEEDED`。

```bash
bash ApiRelay/scripts/selfcheck.sh ; echo EXIT:$?
```

通过：退出码 0。

---

## 第 4 步 · 更新 `00-总览.md`

勾选 `H3a` 已完成；文件清单标 H3a 已执行。  
**MUST NOT** commit。

按 `02` 第六节报告。
