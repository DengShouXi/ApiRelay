# V1 — 每个小 Phase 保存并上传（tag）提示词

先 [`05-annotate-branch.md`](./05-annotate-branch.md)，再贴本段。

---

请把刚完成的 **Phase N** 保存为检查点并上传。

## 正确做法

1. 确认在工作分支 **`v0.1`**（没有就：`git checkout -b v0.1` 从当前 HEAD）。  
2. `git status` / `diff` / `log`；禁止提交密钥、`build/`、明文。  
3. 经我确认后 commit（留在 `v0.1`）。  
4. 打 **tag**（不是新分支）：`git tag -a v0.1.N -m "Phase N checkpoint"`  
5. `git push -u origin v0.1` 且 `git push origin v0.1.N`  
6. 报告：分支、tag、commit hash。

## 不要做

- 不要新建名为 `v0.1.N` 的**分支**（第三层用 tag）  
- 不要预先创建 `v0.2` / `v0.3` / `v0.4`  
- 不要 force push  
- 不要删已有 tag（除非我要求）  

人继续留在 `v0.1` 做下一 Phase。
