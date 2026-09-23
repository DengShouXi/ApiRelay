# 阶段4：Grok实施报告（W6）

写入状态：未停止

- 阶段：4
- 波次：W6（总回归、人工矩阵和事实同步）
- 时间：2026-09-15
- 分支：`v1.13.9`
- HEAD：`6ec5ff7c67547637bbd55f528276422395e28c03`
- 方法版本：`MAIC-1.3`
- 工作包：`ZL02_研发档案/第一阶段-密钥库/调整与优化/v1.13.9-身份验证四档与主密码调整/`
- 输入：已用于 W0—W5 的修订版 `04-最终执行计划.md`、`05-最终检查计划.md`、`00C-任务契约.json`、`实施波次/W5/08-Codex波次复验报告.md`
- 实际授权：用户明确执行 `提示词/阶段4-Grok执行下一波.md`。W0–W5 已通过；W5/08 写明可进入下一波。`04`/`05` 文首仍留有 W5 修订「等待批准」字样；该修订已用于关闭 W5，本次按阶段4「最早未通过波次」只实施 W6，未改 `04`/`05`，未一次做完全部后续阶段。`04` 第六节「不授权进入 W6」约束的是批准 W5 修订的那一次，不是本条新的阶段4入口。

文末 `写入状态：已停止` 为交接用最终状态。

## 1. 入口核对

- 当前分支 `v1.13.9`，HEAD 仍为契约基线 `6ec5ff7c67547637bbd55f528276422395e28c03`。
- 暂存区空；单一 worktree；未提交、未上传、未换分支。
- `main` / `origin/main` = `539447ea9984608c74989da48b8770cb3fe32a6c`；`release/1.0.0` = `5c5eed3f8390f51f5a26be9737bcc11f72e7d7fd`。
- 上一写入者：W5/08 已停止且通过。本波创建前不存在 `实施波次/W6/`。
- 未读取、未修改 `tools/`。未改 Swift。未创建阶段 4B 的 `06-Grok本地实施报告.md`。
- 仓库里原有未跟踪项 `ApiRelay/ApiRelay.xcodeproj/xcshareddata/xcodecloud/manifest.json` 不在本波范围，未纳入、未删除。只读检查器因此报范围差异（退出码 4）；这不是本波新增。

## 2. 本波实际修改（均在 W6 精确清单内）

| 文件 | 做什么 |
| --- | --- |
| `ZL01_具体说明/14-项目当前状态.md` | 改为「规格已回写、本机代码已改完、正在验收；尚未提交上传」 |
| `ZL01_具体说明/04-设计与规格.md` | 去掉「App 代码尚未改」 |
| `ZL01_具体说明/10-AI对话相关记录.md` | 新增 `a09` / `v1.13.9`；13.8 的 W0/实现/行亮度移交到 13.9；未完成表两表同步 |
| `ZL02_研发档案/第一阶段-密钥库/00-阶段总览.md` | 索引本工作包 |
| `ApiRelay/specs/playbooks/BRANCHES.md` | 工作分支改为 `v1.13.9`；补本机未提交行；`v1` / `main` / tag 不动 |
| `ApiRelay/specs/playbooks/v1-key-vault/phases/P13-人工操作指南/06-TestFlight内测.md` | 区分本机新包与旧 TestFlight 包 |
| 本文件 | 本波证据 |

未写 `ZL01_具体说明/13-上传记录.md`。未预写上传成功。测试未发现必须改的 W0—W5 实现文件。

## 3. 自动证据

```text
bash ApiRelay/scripts/selfcheck.sh
```

红线全部通过。`git diff --check` 退出 0。

共享 scheme 全量测试（含 W5 七组目标）：

```text
xcodebuild test -scheme ApiRelay \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -derivedDataPath /tmp/ApiRelayAgentW6-ios-test \
  -resultBundlePath /tmp/ApiRelayW6-01.xcresult \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=YES CODE_SIGNING_REQUIRED=YES
```

- 合计：**358 tests, 0 failures**
- `** TEST SUCCEEDED **`
- 结果包：`/tmp/ApiRelayW6-01.xcresult`
- 日志：`/tmp/ApiRelayW6-01-test.log`

该次测试同时完成 **iOS 模拟器 Debug** 编译。

可用构建（独立 DerivedData，不污染仓库）：

| 配置 | DerivedData | 结果 | 日志 |
| --- | --- | --- | --- |
| iOS 模拟器 Debug | `/tmp/ApiRelayAgentW6-ios-test` | 由全量测试覆盖，通过 | `/tmp/ApiRelayW6-01-test.log` |
| iOS 模拟器 Release | `/tmp/ApiRelayAgentW6-ios-release` | `** BUILD SUCCEEDED **` | `/tmp/ApiRelayW6-01-ios-release.log` |
| Mac Catalyst Debug | `/tmp/ApiRelayAgentW6-mac-debug` | `** BUILD SUCCEEDED **` | `/tmp/ApiRelayW6-01-mac-debug.log` |
| Mac Catalyst Release | `/tmp/ApiRelayAgentW6-mac-release` | `** BUILD SUCCEEDED **` | `/tmp/ApiRelayW6-01-mac-release.log` |

Mac Catalyst 第一次带 `CODE_SIGN_IDENTITY="-"` 失败（entitlements 需要开发证书）。去掉该覆盖后 Debug / Release 均通过。iOS 模拟器仍按规则使用本地签名。

敏感材料扫描：生产代码无真实 API Key / 硬编码口令；`print` 仅 CloudKit 引导与 Diagnostics，不含明文。未知 `RevealPolicy` rawValue fail-closed 到 `.biometricOrPasscode`，不回落 `.noVerification`。`biometricOnly` 只在解码层识别，不是运行时 case。`confirmMandatory` 仍只用于设备主人 / 恢复 / 设密，普通敏感操作测试继续断言次数为 0。

本地化：本波未新增键。插值调用对不上目录字面量，不算缺键。`appLock.useAppPassword`、`settings.policy.biometryOrAppPassword`、`settings.pausedWhileNoVerification` 均在目录中。

提示词目录 16 个入口文件均在；契约 JSON 可解析。工作包内下一提示词仍是绝对路径。

## 4. 人工证据（全部标未验证）

按 `05` 第八节，缺一项即标未验证。本会话无法代替用户做真机系统弹窗和双设备 CloudKit。

1. iPhone：设备验证成功/取消；组合档取消不回落设备密码；显式应用密码入口 — **未验证**
2. iPad：同上，并检查分栏/详情关闭后的授权清除 — **未验证**
3. Mac Catalyst：Touch ID 有/无、Mac 登录密码只在设备验证档出现；快捷键和多窗不得复用详情授权 — **未验证**
4. 三端：不验证不上锁；恢复验证档后自动锁设置重新生效 — **未验证**
5. 三端：同详情查看→复制不二弹，关详情/换 key/离前台后再次验证 — **未验证**
6. 双设备：A 同步应用密码档到 B 但 B 无本机材料 — **未验证**
7. 备份与永久删除：不验证和三种验证档的确认/取消顺序 — **未验证**（自动化矩阵已绿，不能替代真机）

上述未验证项按 `04` W6 停止点 **阻塞阶段 4B 的 `06-Grok本地实施报告.md`**。本波不得用单测宣称人工矩阵通过，也不得创建 `06`。

## 5. 收尾四问

1. **外部资源：** 本波没有新碰 Keychain / SwiftData / CloudKit / UserDefaults / App Group。全量测试继续走 `KeychainStore.makeForTests()` 与内存容器。未改生产钥匙串策略。
2. **失败路径：** 本波没有改产品失败文案。用户在真机上若看不到新四档，说明装的仍是旧 TestFlight 包；P13 已写明。提交上传仍须另句授权。
3. **接缝：** 未新增 protocol。
4. **文件粒度：** `10-AI对话相关记录.md` 与 `BRANCHES.md` 远超 400 行，本波只补本机事实，不顺手拆。

## 6. 未验证 / 阻塞 `06`

- 人工矩阵 1–7：未验证，阻塞 `06`。
- VoiceOver / Dynamic Type / 三端布局手测：未验证，并入人工矩阵。
- 不因此改实现。Codex 阶段 4A 应核对自动证据是否成立，并确认不得进入 4B，直到用户完成或明确接受上述未验证项的处理方式。

## 7. 方法观察

Mac Catalyst 不能套用 iOS 模拟器的 `CODE_SIGN_IDENTITY="-"`。人工矩阵必须单独标未验证并挡住 `06`；否则会把「本机实现做完」写成「可以汇总关账」。

下一步负责人：Codex
是否需要用户批准：否
下一步：执行 `/Users/xitongzhili/Desktop/MacTransfer/08_Code/E02_ApiRelay_Github/ZL02_研发档案/第一阶段-密钥库/调整与优化/v1.13.9-身份验证四档与主密码调整/提示词/阶段4A-Codex波次审计.md`

写入状态：已停止
