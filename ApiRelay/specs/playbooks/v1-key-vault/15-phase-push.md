# V1 — 每个小 Phase 保存并上传（tag）提示词

先 [`05-annotate-branch.md`](./05-annotate-branch.md)，再贴本段。

---

请把刚完成的 **Phase N** 保存为检查点并上传。

对照：`Phase 1 → tag v0.1.1`，`Phase 2 → v0.1.2`，…，`Phase 8 → v0.1.8`。  
（若我是从某个 `phases/P0N-*.md` 过来的，用该文件写明的 tag 名。）

## 正确做法

1. 确认在工作分支 **`v0.1`**（没有就从当前 HEAD：`git checkout -b v0.1`）。  
2. `git status` / `diff` / `log`；禁止提交密钥、`build/`、明文。  
3. 经我确认后 **commit**（人仍留在 `v0.1`，不要为检查点新建分支）。  
4. 打 **annotated tag**（第三层是 tag，不是分支）：  
   `git tag -a v0.1.N -m "Phase N checkpoint"`  
5. 上传：`git push -u origin v0.1`，再 `git push origin refs/tags/v0.1.N`  
6. 报告：分支名、tag 名、commit hash。

## 不要做

- 不要新建名为 `v0.1.N` 的分支  
- 不要预先创建 `v0.2` / `v0.3` / `v0.4`  
- 不要 force push；不要擅自删 tag  

人继续留在 `v0.1` 做下一 Phase。
