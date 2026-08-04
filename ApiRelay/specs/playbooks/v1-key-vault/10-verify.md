# V1 — 检测 / 验收提示词

V1 八个 Phase 全部完成后，把下面整段复制给 Cursor。

---

请对 **V1（`001-key-vault`）** 做版本级验收，**不要开始写 V2 代码**。

## 依据

- `ApiRelay/specs/001-key-vault/tasks.md`：所有 Phase Checkpoint + 任务是否均已 `[X]`
- `ApiRelay/specs/001-key-vault/quickstart.md`：跳过标注为 V2 的条目
- `ApiRelay/specs/ROADMAP.md` V1 验收标准
- 宪法与 `.cursor/rules/key-security.mdc`

## 请你执行

1. 列出 `tasks.md` 中仍为 `[ ]` 的任务（若有，标为阻塞）。
2. 跑 `xcodebuild test`（在正确 scheme/destination 下），报告失败用例。
3. 按安全红线做静态排查：明文是否进入 `@Published` / 日志 / SwiftData 模型字段。
4. 确认无 `kSecAttrAccessControl`；界面无 V2/V3 入口。
5. 对照 ROADMAP V1「验收标准」写一份 **Pass / Fail** 结论表。

## 输出

- 总评：能否合并 main / 打 tag
- 阻塞项清单（若有）
- 下一步：若通过，请我打开 `20-push.md`
