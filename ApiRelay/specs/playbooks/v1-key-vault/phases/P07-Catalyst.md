# V1 · Phase 7 — Mac Catalyst（实现提示词）

把下面整段复制给 Cursor，一次只做这一阶段。

---

请**只实现 V1 Phase 7（Mac Catalyst 适配）**。不要提前做商店元数据（V1 不上架）。

## 必读

- `tasks.md` → **Phase 7**（T051–T055）
- DC-020：Mac 形态是 Catalyst，不可改成纯原生 macOS 另起炉灶

## 本阶段要点

- 默认窗口 900×700，最小 800×600
- 菜单：Settings ⌘,、New Key ⌘N（Refresh 属 V2）
- hover、右键菜单；⌘C 复制仍过门闩
- **真机/实机**验证 macOS 上 `UIPasteboard.expirationDate`；不一致则 Timer 兜底
- 无 Touch ID 的 Mac 上 `biometricOnly` 自动禁用

## 硬约束

- Checkpoint 7 通过后再进 Phase 8

汇报：剪贴板与门闩在 Mac 上的实测结论。


---

## 本阶段完成后（这段不要复制进实现对话）

Checkpoint 通过后：

1. 打开同目录小迭代上传提示词：[`P07-save.md`](./P07-save.md)  
2. 复制其中「请为」起的整段给 Cursor  
   → 写 `BRANCHES.md`（英→中），推送到小迭代分支 **`v0.1.7`**

测试只放：`ApiRelay/ApiRelayTests/V1/Phase07_Catalyst/`  
临时调试：`ApiRelay/DebugScratch/`（不上传）
