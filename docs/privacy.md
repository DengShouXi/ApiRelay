# ApiRelay Privacy Policy / 隐私政策

**Last updated / 更新日期:** 2026-08-11  
**Developer / 开发者:** Deng Shouxi (邓守系)  
**Support / 支持:** https://github.com/DengShouXi/ApiRelay/issues

This page is the privacy policy for the ApiRelay app on the App Store.  
本页为 ApiRelay 在 App Store 上的隐私政策（人工双语，非机翻）。

---

## English

### What ApiRelay is

ApiRelay is a private vault for API keys you use with AI platforms and developer tools. It does **not** create an ApiRelay account and does **not** route your API calls through our servers.

### Data we (the developer) collect

We **do not collect** personal data from the app onto developer-operated servers. There is no analytics SDK and no advertising identifier collection by us.

### Where your keys and related data live

- **Key secrets** are stored in the system **Keychain**. When you enable it, secrets sync between **your own Apple devices** through **iCloud Keychain** (end-to-end encrypted by Apple’s system)—not uploaded to an ApiRelay server.
- **Account / assignment metadata** syncs through **iCloud** (CloudKit) under the Apple Account signed into that device. The app cannot sign you in or switch Apple ID; sync follows the system account.
- Turn on iCloud Keychain on every device that should see the same key secrets.
- Do **not** assume “secrets never leave this device” if iCloud Keychain sync is enabled.

### Clipboard

When you explicitly copy a secret, it is placed on the system clipboard for a limited time you configure. You may disable Universal Clipboard so copied secrets stay off other nearby devices. Automatic clearing is best-effort and is not an absolute guarantee if the app is terminated by the system.

### Identity confirmation (Face ID / passcode / master password)

Reveal and copy share **one** optional verification policy you control in Settings. This is an **app-layer** gate (not a claim of system-enforced Keychain ACL that “cannot be bypassed”). A master password is optional, stored only on that device as verification material, and can be reset after device authentication—it is not stronger than your device passcode.

### Purchases

Optional one-time In-App Purchase (`com.apirelay.iap.unlimited_keys`) is processed by Apple. We do not receive your card number. Restore Purchases is available in Settings. Erasing app data does not revoke App Store purchases.

### Erase all data

Settings provides “Erase All Data,” which permanently removes keys, accounts, preferences, and Keychain secrets for this app on the device. If sync is enabled, corresponding synced data on other devices may also be cleared. This skips the recycle bin.

### Contact

Questions: https://github.com/DengShouXi/ApiRelay/issues

---

## 简体中文

### 产品是什么

ApiRelay 是面向开发者的 API 密钥保险库，帮你在自己的 Apple 设备上保管、整理并取用密钥。本产品 **没有** ApiRelay 账号，也 **不会** 把你的 API 调用发到我们的服务器。

### 开发者是否收集数据

我们 **不会** 把本 App 中的个人数据收集到开发者自有服务器。无分析 SDK，我们也不采集广告标识符。

### 密钥与相关数据存在哪里

- **密钥明文** 保存在系统 **钥匙串**。若你开启相关能力，明文经 **「iCloud 钥匙串」** 在你本人的 Apple 设备之间同步（系统端到端加密）——**不会**上传到 ApiRelay 自有服务器。
- **账号 / 指派等元数据** 经 **iCloud**（CloudKit）同步，跟随该设备系统里已登录的苹果账号。本 App 不能登录或切换 Apple ID。
- 每台要共用同一密钥明文的设备都需开启 iCloud 钥匙串。
- 若已开启 iCloud 钥匙串同步，**不要**理解为「明文永不离开本机」。

### 剪贴板

仅在你显式复制后，明文会进入系统剪贴板，并可按你设定的时长自动清除。可关闭「通用剪贴板」，避免同步到附近其他设备。自动清除为尽力而为：若应用已被系统终止，不能保证绝对清除。

### 身份确认（面容 ID / 设备密码 / 主密码）

查看明文与复制共用 **同一** 套可在设置中选择的验证方式（含「不验证」）。这是 **应用层** 门闩，产品 **不会** 宣称「系统级强制」「无法绕过」。主密码可选，校验材料仅存本机，可经设备验证后重置，强度不高于设备密码。

### 购买

可选的一次买断内购（`com.apirelay.iap.unlimited_keys`）由 Apple 处理支付，我们拿不到银行卡号。设置中提供「恢复购买」。清除 App 数据 **不会** 吊销 App Store 已购权益。

### 清除全部数据

设置提供「清除全部数据」，将永久清除本机密钥、账号、偏好与本 App 相关钥匙串明文，并跳过回收站。若已开启同步，其他设备上的对应同步数据也可能被清除。

### 联系

问题反馈：https://github.com/DengShouXi/ApiRelay/issues
