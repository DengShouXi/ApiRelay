# 步骤 5 · 本地 Archive + 点一遍「恢复购买」

目标：证明工程能打出上架包外形，且审核必查的「恢复购买」找得到。  
**本步不要**点 ASC 的「提交以供审核」。

> 打完 Archive 后：**下一步会上传并走 TestFlight**（步骤 6），不要直接送审。

---

## 5.1 确认版本号

终端（仓库根目录）：

```bash
grep -n "MARKETING_VERSION" ApiRelay/ApiRelay.xcodeproj/project.pbxproj
```

应看到 **`MARKETING_VERSION = 1.0.0`**（不要还是裸 `1.0`）。

- [ ] 已是 `1.0.0`  

---

## 5.2 本地 Archive

1. Xcode 顶部设备选 **Any iOS Device (arm64)**（或 Generic iOS Device）  
2. 菜单：**Product → Archive**  
3. 等 Organizer 弹出；看到这次 Archive 成功即可  
4. **本步可以先停在 Organizer**；上传构建放到步骤 6（TestFlight）再点 **Distribute App**  

若 Archive 失败：把报错原文存下来，开对话让我修（别自己乱改签名配置除非你熟）。

- [ ] Archive 成功一次  

（Mac 商店若单独要 Mac Archive：设备选 My Mac 再 Archive 一次；有失败再记。）

---

## 5.3 「恢复购买」点一遍

1. 真机或模拟器 Run App（本步用 Xcode Run 即可；正式终检在步骤 6 的 TestFlight 包上再点一次）  
2. 打开 **设置** Tab  
3. 找到分区 **Purchases / 购买** → **Restore Purchases / 恢复购买**  
4. 点一下：  
   - 沙盒未登录可能提示登录 / 无购买，**只要入口在、不崩**即可  
   - 若你有沙盒测试账号且买过，应提示已恢复  

也可用密钥列表免费额度旁的 Upgrade 打开付费墙，里面也有 Restore——但**设置里这一条是审核友好路径**，务必存在。

- [ ] 设置内「恢复购买」已点过  

---

## 5.4 工程文件再确认（可选命令）

```bash
test -f ApiRelay/ApiRelay/PrivacyInfo.xcprivacy && echo PrivacyInfo_OK
grep -n "ITSAppUsesNonExemptEncryption" ApiRelay/ApiRelay/Info.plist
grep -n "unlimited_keys" ApiRelay/ApiRelay/Business/System/EntitlementService.swift
```

- [ ] PrivacyInfo_OK  
- [ ] 出口声明键仍在  
- [ ] IAP id 仍是 `com.apirelay.iap.unlimited_keys`  

通过 → [`06-TestFlight内测.md`](./06-TestFlight内测.md)（上传 + 真机安装自测）。  
若暂时不能上传 ASC：可先勾本地 Archive，但**送审前必须补完步骤 6**。
