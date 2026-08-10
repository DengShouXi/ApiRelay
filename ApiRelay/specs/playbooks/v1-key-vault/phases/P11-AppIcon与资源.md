# V1 · v1.11 — App Icon + SF Symbol / 资源（实现提示词）

把下面整段复制给 Cursor，一次只做这一阶段。

---

请**只实现 V1 小迭代 v1.11（App Icon + SF Symbol / Asset Catalog）**。  
补齐商店与桌面可见品牌，以及列表/设置的图标语义；**不改业务逻辑、不重做 P10 信息架构**。

## 必读

- 本文件「设计方案」（锁定稿）
- `BRANCHES.md` → `v1.11`
- 改动范围：`Assets.xcassets` + `UI/Shared`（符号表）+ 必要的 `UI/Vault` / `UI/Settings` / `PresetCatalog` 引用替换
- 商店正式截图仍属 **T065**；本阶段只出**草稿**，降低后续返工

## 大白话：这阶段交什么

| 交付物 | 说明 |
|--------|------|
| **App Icon 全尺寸** | iOS（含深色 / tinted）+ Mac Catalyst 所需 Mac 槽位，全部有图，不是空 `Contents.json` |
| **SF Symbol 语义表** | 一处定义、处处引用；Tab / 密钥动作 / 设置行 / 平台·工具默认图标语义统一 |
| **Asset Catalog 约定** | 命名、深浅色、Accent 与图标主色一致 |
| **商店截图草稿** | 按 P10 新壳截 4～6 张假数据界面，标注 draft，留给 T065 精修 |

---

## 设计方案（锁定稿）

### A. App Icon — 概念与约束

**心智**：产品是「密钥保险库」，不是聊天机器人、不是仪表盘。图标一眼要读出 **key / vault**，不是「又一个 AI 紫渐变」。

| 原则 | 做法 |
|------|------|
| **剪影优先** | 主形：一枚简化钥匙，或「钥匙 + 锁孔/保险柜门」的单层剪影。细节少到 **16×16** 仍可辨认。 |
| **禁文字** | 图标内不得出现「ApiRelay / AR / Key」等字样（小尺寸糊成斑）。 |
| **禁商标抄袭** | 不得仿 OpenAI / Anthropic 等品牌标；平台识别走应用内 SF Symbol，不进 App Icon。 |
| **色板克制** | 建议：**深石板底 + 单一亮色钥匙剪影**（或反相：浅底 + 深色剪影）。主色与 `AccentColor` 同源。避免紫靛渐变、多层光晕、拟物螺丝钉。 |
| **系统外观** | iOS 填齐 **Any / Dark / Tinted** 三槽（工程已有空槽）。Dark：底更深、剪影提亮或反相；Tinted：留给系统上色的**单色模板**（灰阶剪影，无彩底）。 |
| **Mac 可读性** | Catalyst 用 Mac idiom 槽位（16～512 @1x/@2x）。**先画 16 / 32 验收**，再放大到 1024；大图好看但小图糊 = 不合格。 |
| **圆角** | 源稿画满安全区即可；圆角由系统裁切，不要在 PNG 里自带圆角遮罩。 |

**制作流程（推荐）**

1. 矢量源稿（Figma / Sketch / Illustrator）画板 **1024×1024**，留约 4～8% 内边距。  
2. 导出 iOS：Any、Dark、Tinted 各一张 1024。  
3. 导出 Mac：从同一源缩放；对 16/32 可手调 1px 级加粗，保证钥匙齿不会消失。  
4. 丢进 `AppIcon.appiconset`，Xcode 槽位全绿。  
5. 真机主屏 + Mac Dock / Applications 文件夹各看一眼。

**非目标**：不做独立 macOS App Icon 品牌分叉；Catalyst 与 iOS **同一套图形语言**。

---

### B. SF Symbol — 统一语义表

**原则**：列表 / Tab / 设置 **只用系统 SF Symbol**（零版权纠纷、深浅色免费适配）。自定义 PNG 图标 **本期不做**，除非某语义 SF 完全不存在（则先报告再开资产）。

**落点**：新增单一映射源（建议 `UI/Shared/AppSymbols.swift` 或扩 `PresetCatalog` 的 platform/tool 符号），禁止在 View 里继续魔法字符串散落。P10 已有的合理取值可保留，但必须**收口到表里**。

#### B1. 导航与通用动作（必统一）

| 语义 | SF Symbol | 备注 |
|------|-----------|------|
| Tab · 按平台 | `square.stack.3d.up` | 保持 P10；「多层/上游」 |
| Tab · 按使用方 | `laptopcomputer` | 保持；客户端工具 |
| Tab · 回收站 | `trash` | 空态可同语义 |
| Tab · 设置 | `gearshape` | 保持 |
| 更多（⋯） | `ellipsis.circle` | 工具栏 |
| 账号 / 同步入口 | `person.crop.circle.fill` | 非独立登录体系 |
| 添加 | `plus` / 行内 `plus.circle` | 主行动点用 `plus` |
| 搜索 / 清除 | `magnifyingglass` / `xmark.circle.fill` | |
| 密钥（默认） | `key.fill` | 行头 / 空态 |
| 复制 | `doc.on.doc` | **主操作**，与查看区分 |
| 查看明文 | `eye` | 次要；勿与复制抢视觉 |
| 指派 / 关联 | `link` | |
| 失效 / 不可用 | `key.slash` 或 `exclamationmark.triangle` | 按现有状态语义，勿混用 |
| iCloud / 同步说明 | `icloud.fill` / `lock.icloud` / `arrow.triangle.2.circlepath` | 文案仍不得夸大「系统级强制」 |
| 打开系统设置 | `gearshape` | |

选中态：Tab 用系统 tint；列表行图标默认 `.secondary`，主操作（复制）可用 `.tint`。

#### B2. 上游平台默认符号（无商标）

平台 **不要** 画 Logo。用「品类隐喻」SF Symbol，自定义平台统一兜底：

| platform id | 建议 Symbol | 隐喻 |
|-------------|-------------|------|
| `openai` | `sparkles` | 通用模型 |
| `anthropic` | `bubble.left.and.bubble.right` | 对话 |
| `google` | `globe` | 搜索/云 |
| `openrouter` | `arrow.triangle.branch` | 路由 |
| `deepseek` | `waveform` | 推理/信号 |
| `alibaba-bailian` | `cloud` | 云厂商 |
| `volcengine` | `bolt.fill` | 火山/算力 |
| `siliconflow` | `cpu` | 算力聚合 |
| `custom` / 未知 | `building.2` | 上游账号兜底 |

映射进 `PresetCatalog`（或 `AppSymbols.platform(id:)`），分区头 / 选平台列表共用。

#### B3. 使用方工具（已有则收口）

沿用 `PresetCatalog.consumerTools` 的 `iconSymbol`，校验是否仍合理；**本阶段只做命名收口与缺失补齐**，不借机大换皮：

| 工具 | 现有 / 建议 |
|------|-------------|
| VS Code | `chevron.left.forwardslash.chevron.right` |
| Cursor | `cursorarrow` |
| OpenCode | `terminal` |
| Trae | `sparkles` |
| Cline | `hammer` |
| Roo Code | `bird` |
| Cherry Studio | `leaf` |
| Zed | `z.square` |
| Continue | `arrow.right.circle` |
| 用户自建 | `laptopcomputer` 或 `app` |

#### B4. 设置行

设置卡片 leading 已有彩色小方块 + SF Symbol：本阶段整理**一张设置语义表**（门闩、剪贴板、备份、权益、关于…），同一语义不得两处两名。颜色仍用系统语义（destructive / tint），不自造品牌渐变。

---

### C. Asset Catalog 命名与外观

```text
ApiRelay/Assets.xcassets/
├── AppIcon.appiconset/          # 唯一应用图标；槽位全填
├── AccentColor.colorset/        # 与图标主色同源；支持 Any/Dark 若需要
└── Contents.json
```

| 约定 | 规则 |
|------|------|
| 命名 | `AppIcon`、`AccentColor` 保持系统默认名；**本期不**新增 `IconKey` 等自定义图片集，除非 SF 不够用且已获准。 |
| 深色 | 图标靠 App Icon 的 Dark / Tinted 槽；UI 靠语义色 + SF，不靠「另一套 PNG」。 |
| 明文红线 | 截图草稿与任何预览资源 **禁止** 真实密钥；示例掩码用 `sk-••••` / `••••-demo`。 |
| 目录卫生 | 导出中间文件、`.psd` / `.fig` 源稿可放仓库外或 `DebugScratch/`；**不要**把巨型设计源塞进 `Assets.xcassets`。 |

---

### D. 商店截图草稿（预热 T065，非正式）

本阶段**顺手**出一版草稿即可，正式元数据与精修仍走 **T065**（及上架核对）。

| 项 | 要求 |
|----|------|
| 张数 | 4～6 张：① 按平台列表 ② 按使用方 ③ 回收站或空态 ④ 设置 ⑤（可选）指派 sheet / 复制门闩前界面 |
| 设备 | 优先 **iPhone 6.7"** 一档；另存 1 张 Mac Catalyst 窗口草稿可选 |
| 数据 | 假账号、假工具、掩码密钥；无真实 Keychain 内容 |
| 文案 | 不得出现「系统级强制」「无法绕过」；可用「面容 ID 确认后复制」等如实表述 |
| 存放 | 建议 `ApiRelay/specs/playbooks/v1-key-vault/store-drafts/v1.11/`（或团队约定的 marketing 草稿目录），文件名带 `-draft`；**README 一行注明：非正式，T065 替换** |
| 非目标 | 不写 App Store Connect 描述、不上传 ASC、不替代 T063/T064 |

---

## 硬约束

- 不改门闩语义、Keychain、Data、Business protocol。  
- 不重做底部 4 Tab IA（P10 冻结）。  
- 一次对话只动「图标 / 符号 / 资源 / 截图草稿」；发现顺路 UI 瑕疵只报告。  
- 商标：应用内用 SF 隐喻，不用第三方 Logo 图。  
- Catalyst：新增 API / 资源须双端可编译。

## 验收

见同目录 [`P11-验收清单.md`](./P11-验收清单.md)。

汇报：图标三外观是否齐；符号表落点路径；平台/工具默认符号是否收口；截图草稿路径与张数。

---

## 本阶段完成后（这段不要复制进实现对话）

1. 打开同目录：[`P11-save.md`](./P11-save.md)  
2. 更新 `BRANCHES.md` → commit → `git push -u origin v1.11`  
3. 商店正式截图：上架准备时执行 **T065**（可用本阶段 draft 为底稿）
