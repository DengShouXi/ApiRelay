# ApiRelay 分版本实现 Playbook

**台账**：[BRANCHES.md](./BRANCHES.md) · **产品范围**：[ROADMAP.md](../ROADMAP.md)

## 分支命名（按你的规则：三层都是分支）

```text
v0.1          大阶段工作线
└── v0.1.1    小阶段 1 上传目标
└── v0.1.2    小阶段 2 …
```

## 每个小 Phase 两份提示词

| 文件 | 用途 |
|------|------|
| `P0N-某某.md` | 只实现 |
| `P0N-save.md` | 只保存：英→中备注 + 推到小阶段分支 `v0.Y.N` |

## 测试隔离

| 路径 | 是否上传 |
|------|----------|
| `ApiRelay/ApiRelay/` 正式代码 | 是 |
| `ApiRelay/ApiRelayTests/V*/Phase*/` 按阶段测试 | 是（跟对应小阶段一起） |
| `ApiRelay/DebugScratch/` | **否**（gitignore） |
| `ApiRelay/build/` | **否** |

详见 `ApiRelay/ApiRelayTests/README.md`。
