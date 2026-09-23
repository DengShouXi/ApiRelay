# V1 · Phase 7 — Mac Catalyst（实现提示词）

把下面整段复制给 Cursor，一次只做这一阶段。

---

请**只实现 V1 Phase 7（Mac Catalyst 适配，T051–T055）**。商店元数据/隐私问卷/截图留给 Phase 8 的 T063–T066（Stage1→1.0.0）；本阶段不要做。

## 必读

- `tasks.md` → **Phase 7**（T051–T055）
- DC-020：Mac 形态是 Catalyst，不可改成纯原生 macOS 另起炉灶

## 本阶段要点

- 默认窗口 900×700，最小 800×600
- 菜单：Settings ⌘,、New Key ⌘N（Refresh 属 V2）
- hover、右键菜单；⌘C 复制仍过门闩
- **真机/实机**验证 macOS 上 `UIPasteboard.expirationDate`；不一致则 Timer 兜底
- 无 Touch ID 的 Mac 上旧 `biometricOnly` 档自动禁用——**已被 13.9 覆盖**：该档不再是用户可选项，迁到设备验证；无生物识别时设备验证仍可用设备或 Mac 登录密码。**已被 U1 覆盖：** 列表标题固定「生物验证或设备密码」，不随有无触控 ID 改名。**已被 U2 覆盖：** 界面称「应用密码」；设置首页该行仅在已 persist 为应用密码或组合档时显示。现行见 [`身份验证方案.md`](../../身份验证方案.md)

## 硬约束

- Checkpoint 7 通过后再进 Phase 8

汇报：剪贴板与门闩在 Mac 上的实测结论。


---

## 本阶段完成后（这段不要复制进实现对话）

Checkpoint 通过后：

1. 打开同目录小迭代上传提示词：[`P07-save.md`](./P07-save.md)  
2. 复制其中「请为」起的整段给 Cursor  
   → 写 `BRANCHES.md`（英→中），推送到小迭代分支 **`v1.7`**

测试只放：`ApiRelay/ApiRelayTests/V1/Phase07_Catalyst/`  
临时调试：`ApiRelay/DebugScratch/`（不上传）
