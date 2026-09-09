# Quickstart: CloudKit 同步卫生后续

## `/speckit.implement` 怎么指到本功能

默认 `.specify/feature.json` 仍是 `specs/001-key-vault`。在 **Spec Kit 根目录**（含 `.specify/` 的 `ApiRelay/`）执行：

```bash
export SPECIFY_FEATURE_DIRECTORY=specs/001-key-vault/follow-ups/cloudkit-sync-hygiene
python3 .specify/scripts/python/check_prerequisites.py --json --require-tasks --include-tasks
```

期望 JSON 里 `FEATURE_DIR` 以 `follow-ups/cloudkit-sync-hygiene` 结尾，且 `AVAILABLE_DOCS` 含 `plan.md` 对应的 research / tasks。

完整复制段见 [`../../../playbooks/热修-CloudKit同步卫生.md`](../../../playbooks/热修-CloudKit同步卫生.md)。

## 已落地、不要重做

读 `SyncedIdentity.swift`、三个仓库的 `pruneDuplicateIdentities`、`VaultSearch` 的 `uniquingKeysWith`。本功能只补 tasks.md 里未勾项。

## 关账

`tasks.md` **T008** + 验收清单双设备项全部勾选。保存走热修-save，不改商店号除非另授权。`replicaSeed`（T006）未 Deploy 前不要勾、不要发包。
