# 05 · SpecKit 与工具准则

> 回答：**「Spec Kit / 宪法 / `.specify` 在哪？和 `.cursor/rules` 什么关系？」**
>
> 上一页：[`04-设计与规格.md`](./04-设计与规格.md)  
> Cursor 九条 → [`06-AI铁律清单.md`](./06-AI铁律清单.md)
>
> **本页只指路。** 不复制宪法与模板正文。

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

<h2 id="toc">目录</h2>

- [§1 · 两套闸门](#two-guardrails)
- [§2 · 目录地图](#directory-map)
- [§3 · 权威表](#authority-map)
- [§4 · 维护](#maintenance)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

<h2 id="two-guardrails">§1 · 两套闸门</h2>

| 套 | 路径 | 谁在读 | 管什么 |
|---|---|---|---|
| Cursor 规则 | [`.cursor/rules/*.mdc`](../.cursor/rules/) | Cursor（多数每次加载） | 改代码纪律 |
| Spec Kit | `.specify/` + `.github/` + 宪法 | 写规格 / speckit 命令 | 规格流程与产品原则 |

本项目只装了 **Copilot** 集成。日常 Cursor 写代码吃 `.cursor/rules`；写规格、改宪法吃本页这套。  
**两套并存，不要删。** 见 [`03-路径红线.md`](./03-路径红线.md)。

[↑ 返回目录](#toc)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

<h2 id="directory-map">§2 · 目录地图</h2>

```text
ApiRelay/
├── .specify/                 配置与模板（勿搬）
│   ├── memory/constitution.md
│   ├── templates/
│   └── integration.json      当前：copilot
├── .github/agents|prompts|skills/
└── specs/                    产出（见 04）
```

`spec-kit-0.15.2/` 不入库，日常不用进。

[↑ 返回目录](#toc)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

<h2 id="authority-map">§3 · 权威表</h2>

| 想查什么 | 打开 |
|---|---|
| 产品与工程铁律 | [`constitution.md`](../ApiRelay/.specify/memory/constitution.md) |
| 写规格模板 | [`templates/`](../ApiRelay/.specify/templates/) |
| 阶段 / 需求正文 | [`04-设计与规格.md`](./04-设计与规格.md) |
| 分支上传 / 开发顺序 | [`07-开发流程.md`](./07-开发流程.md)、[`08-分支与流程.md`](./08-分支与流程.md) |
| Spec Kit 命令实体 | [`../ApiRelay/.github/agents/`](../ApiRelay/.github/agents/) |
| Cursor 纪律 | [`06-AI铁律清单.md`](./06-AI铁律清单.md) |

常见：`speckit.specify` / `plan` / `tasks` / `implement` / `constitution` …（以 agents 目录文件名为准）。  
`.cursor/commands/` 尚不存在（H1 计划要建）。

[↑ 返回目录](#toc)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

<h2 id="maintenance">§4 · 维护</h2>

- 新增模板 / 命令 → 更新本节。  
- 改宪法：先说明决策，再改 `constitution.md` 的 Sync Impact，不要只改 `.mdc` 摘要。

[↑ 返回目录](#toc)
