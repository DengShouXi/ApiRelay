# 步骤 6 · TestFlight 内测（推荐：先测再送审）

目标：用**真机安装包**自己摸一遍，再决定要不要提交 App Store 审核。  
**本步仍不要**点 ASC 的「提交以供审核」——那是以后的 T062。

> **要不要先 TestFlight？**  
> **要。** 首发尤其建议。上传到 ASC 的构建可以先给 TestFlight，测完同一构建再送审，不浪费工。  
> 只做本地 Archive、不上传，也能勾 P13 的「能打包」；但**正式送审前**仍强烈建议完成本步。

---

## 6.0 你现在处在哪一步

```text
截图 / 文案 / 隐私问卷（步骤 2～4）
  → 本地 Archive + 恢复购买（步骤 5）
  → 【本步】上传构建 → TestFlight 安装 → 真机自测
  → 步骤 7：勾验收清单 → P13-save（仍不上架）
  → 以后：10-verify → 授权后才 T062 提交审核
```

---

## 6.1 前置（缺一补一）

- [ ] 步骤 5：本地 **Archive 已成功**（Organizer 里看得到这次包）  
- [ ] `MARKETING_VERSION = 1.0.0`  
- [ ] ASC 里已有 App 记录（`ApiRelay`，Bundle ID 与工程一致）  
- [ ] 真机至少一台（iPhone；有余力再测 iPad / Mac）  
- [ ] 手机已装苹果 **TestFlight** App（App Store 搜 “TestFlight”）

协议：ASC → **协议、税务和银行业务** 若有红点未同意，先点完，否则上传/TestFlight 会卡。

---

## 6.2 把 Archive 上传到 App Store Connect

1. Xcode → **Window → Organizer**（或 Archive 结束后的窗口）  
2. 选刚打的那条 **iOS** Archive → **Distribute App**  
3. 选 **App Store Connect** → Next  
4. 选 **Upload**（不要选 Export 到硬盘就算完）  
5. 选项保持默认即可（通常勾 Automatically manage signing）→ Next → Upload  
6. 等到 Xcode 提示上传成功  

然后去浏览器 [App Store Connect](https://appstoreconnect.apple.com) → 你的 App → **TestFlight** 标签：  
构建会出现「正在处理」；一般 **10～30 分钟**（偶发更久）。状态变成可测试即可。

若上传报错（签名 / 权限 / 协议）：把**完整英文报错**存下来开对话修，不要乱改 Bundle ID。

- [ ] 构建已上传  
- [ ] ASC → TestFlight 里该构建处理完成（可测）

（若要上 Mac 商店：另用 **My Mac** Archive 再上传一次；iOS 包测通即可先内测手机。）

---

## 6.3 开内部测试（Internal Testing）

1. ASC → App → **TestFlight**  
2. 左侧 **内部测试**（Internal Testing）→ 用默认组或新建一组（如 `Internal`）  
3. **添加构建** → 选刚处理好的 `1.0.0 (build N)`  
4. **第一次**用某构建时，ASC 可能要填「测试信息 / 加密合规」：  
   - 按你们出口声明口径回答（工程里 `ITSAppUsesNonExemptEncryption` 已为豁免类 `false` 时，按 ASC 问题选「不使用非豁免加密」一类选项；拿不准就对照 `Info.plist` / 开对话问）  
5. **添加测试员**：把自己的 Apple ID（与真机登录的同一账号）加成内部测试员  
   - 内部测试员须是该 App 的 **App Store Connect 用户**（用户与访问里已有角色即可）  
6. 保存后：测试员邮箱会收到邀请；或真机打开 TestFlight → 兑邀请

- [ ] 内部测试组已挂上该构建  
- [ ] 自己已是测试员  

> **外部测试**（External Testing）要额外 Beta App Review，首发可先不做；内部测通再考虑。

---

## 6.4 真机安装

1. 真机用**同一 Apple ID** 打开 **TestFlight**  
2. 接受邀请 → 找到 **ApiRelay** → **安装**  
3. 桌面打开的应是 TestFlight 装的包（不是 Xcode Run 的 Debug 包）

- [ ] 真机已从 TestFlight 安装并打开  

---

## 6.5 自测清单（假数据，禁止贴真实密钥）

至少做完下面这些再考虑送审：

| # | 测什么 | 期望 |
|---|--------|------|
| 1 | 冷启动进密钥列表 | 不崩；默认**不**弹「打开 App 要验证」（`appLock` 默认关） |
| 2 | 新增假账号 + 假密钥 | 列表出现；明文为掩码 |
| 3 | 复制密钥 | **13.8 出厂默认是设备验证**，应先过系统设备主人再复制。若用户改成「不验证」则直接复制。现行未改代码的包仍可能是旧默认「不验证」 |
| 4 | 按使用方指派 | 双视角能看到指派 |
| 5 | 设置 → **恢复购买** | 入口在；点一下不崩（沙盒无购买也 OK） |
| 6 | 设置 → 验证方式 | 查看与复制仍共用一道门闩；13.8 另有「取用验证」行。四档名称见 `身份验证方案.md`，不要再按「仅生物识别」测新包 |
| 7 | （可选）第二台已登录同一 iCloud 的设备 | 元数据/钥匙串同步符合预期；2b 已 Deploy Production |

出问题：记「哪一步 + 系统版本 + 截图/原文」→ 开对话修 → **重新 Archive 上传新 build** → TestFlight 再测。  
不要带着已知崩溃去点「提交审核」。

- [ ] 上表 1～6 已在 TestFlight 包上跑过  

---

## 6.6 本步明确不要做的事

| 不要 | 原因 |
|------|------|
| ASC 点「提交以供审核」 | 那是 T062，须另授权 |
| 打 git tag `release/1.0.0` / 合并 `main` | 同上 |
| 用真实 API Key 做演示 | 明文红线 + 截图/录屏风险 |
| 以为 TestFlight 通过 = 已上架 | TestFlight 只是内测分发 |

---

## 6.7 测完怎么走

- 自测 OK → [`07-做完后去哪.md`](./07-做完后去哪.md)（勾清单 → P13-save；**仍不送审**）  
- 以后要上架：`10-verify` PASS 后，另开对话写清授权句 → [`../../12-release-T062.md`](../../12-release-T062.md)  
  送审时可选用**本次 TestFlight 已验证的同一构建**（或修复后的新构建）。
