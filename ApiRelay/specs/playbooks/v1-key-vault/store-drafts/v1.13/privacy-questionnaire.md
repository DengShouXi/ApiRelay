# App 隐私问卷对齐表（T064）

> **性质**：ASC「App 隐私」问卷勾选指南 + 与产品内披露对照。  
> **不是**另起一份法律正文。法律/披露以 T059b 已落地的双语文案为准（见下方路径）。  
> **禁止**机翻另写隐私政策。

## T059b 法律 / 披露正文位置（引用）

本阶段未发现独立 `PrivacyPolicy.md` / HTML；T059b 以产品内**人工双语**披露字符串落地：

| 主题 | String Catalog key | 入口 |
|------|-------------------|------|
| iCloud 钥匙串同步明文 | `vault.sync.how.body` | 账号 / iCloud 同步说明 |
| 同步跟随本机 Apple ID | `vault.sync.icloud.status.footnote`（及同组 `vault.sync.*`） | 同上 |
| 剪贴板风险 / 通用剪贴板 | `settings.section.clipboardPrivacy.footer`、`settings.clipboardLocalOnly.rowDetail` | 设置 → 剪贴板与隐私 |
| 清除数据与购买保留 | `settings.eraseAll.message`、`settings.eraseAll.footer` | 设置 → 危险区 |
| 查看/复制一门闩 | `settings.section.password.footer` | 设置 → 密码与验证 |
| 主密码可重置（非更强保证） | `vault.masterPassword.disclosure` | 主密码设置 |

工程隐私清单（非商店法律正文）：`ApiRelay/ApiRelay/PrivacyInfo.xcprivacy`  
加密出口声明：`ApiRelay/ApiRelay/Info.plist` → `ITSAppUsesNonExemptEncryption`

## ASC 隐私问卷建议勾选（V1 实际行为）

按「我们是否收集并用于关联/跟踪」理解：本 App **无自有账号、无分析 SDK、无向开发者服务器上传密钥**。  
密钥经 **系统 iCloud 钥匙串** 在用户本人设备间同步——这是 Apple 系统能力，不是你向第三方出售数据。

| 数据类型（ASC 分类名可能随 UI 微调） | 是否收集（开发者侧） | 建议 | 对齐依据 |
|--------------------------------------|----------------------|------|----------|
| 敏感信息 / 其他敏感信息（API 密钥） | 开发者服务器：**不收集** | 一般 **不勾「我们收集」**；在隐私政策/产品说明中披露「存于钥匙串 + iCloud 钥匙串同步」 | FR-024、FR-033、`vault.sync.how.body` |
| 联系信息 / 姓名 / 邮箱 | 不收集 | 不勾 | 无账号体系 |
| 位置 | 不收集 | 不勾 | — |
| 使用数据 / 诊断（自有分析） | 不收集（无第三方分析 SDK） | 不勾；系统崩溃报告若走 Apple 标准机制，按 ASC 当前说明填写 | `PrivacyInfo` 无 tracking |
| 购买记录 | StoreKit 由 Apple 处理；本地仅权益快照 | 按 ASC 对 IAP 的现行问题如实答；勿声称自建支付账本 | FR-028、产品 ID `com.apirelay.iap.unlimited_keys` |
| 跟踪（Tracking） | 否 | `NSPrivacyTracking = false` | `PrivacyInfo.xcprivacy` |
| UserDefaults API | 访问（偏好） | 工程已声明 `CA92.1` | FR-058 |

### 必须在「隐私政策 / 产品页」说清楚、问卷里勿矛盾的句子

1. **密钥明文**：存系统钥匙串；经 **iCloud 钥匙串** 在**你本人的 Apple 设备之间**同步（系统端到端加密）。  
2. **不得**写「明文永不离开本机」。  
3. **元数据**：账号/指派等经 iCloud（CloudKit Private DB），非 ApiRelay 自建云。  
4. **剪贴板**：用户显式复制后短时存在；可关通用剪贴板；有自动清除但非绝对保证。  
5. **删除**：设置提供「清除全部数据」；不吊销 App Store 购买；开启同步时可能波及其他设备。  
6. **门闩**：应用层身份确认，可选关闭「查看/复制」验证——**不要**在问卷或商店写「系统级强制 / 无法绕过」。

## 产品内入口核对

| 检查项 | 状态（Agent） |
|--------|----------------|
| 用户可打开同步说明（含钥匙串同步） | 有：`vault.sync.*` |
| 用户可打开剪贴板与隐私设置 | 有：设置分组 |
| 用户可执行清除全部数据 | 有 |
| 独立「隐私政策」Web/Markdown 文件 | **未找到**；若 ASC 要求 Privacy Policy URL，需你托管 T059b 全文页面（本阶段不新开大功能） |

## 待你在 ASC 完成

- [ ] 按上表勾选 App 隐私问卷  
- [ ] 填入 Privacy Policy URL（托管双语正文后）  
- [ ] 确认问卷与 `vault.sync.how.body` / 清除数据文案无矛盾  

## 禁语复查

本对齐表说明性文字可提及「禁止写系统级强制」；**提交到 ASC 的答案与商店描述**不得使用「系统级强制」「无法绕过」。
