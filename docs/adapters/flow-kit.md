# Forge flow-kit adapter

## 定位

flow-kit 只作为阶段方法论来源接入 Forge。它定义任务应该经历哪些阶段，Forge 负责运行时路由、证据检查、health 和 smoke。

不把 flow-kit 作为 Forge 依赖，也不让 flow-kit 接管 hook。

## 吸收层

Forge 只吸收这些稳定抽象：

- `GO.md` 作为 flow-kit 入口说明
- `prompts/*` 作为阶段提示词
- `templates/*` 作为阶段制品模板
- 阶段顺序：change、requirement、design、ui-design、task、dev、test、review、integration

## 阶段映射

| flow-kit 阶段 | Forge 路由 |
| --- | --- |
| `0-change` | scope / intent |
| `1-requirement` | requirement |
| `2-design` | design |
| `2a-ui-design` | ui-design |
| `3-task` | planning |
| `4-dev` | implementation |
| `5-test` | verification |
| `6-review` | review |
| `7-integration` | integration |

## 更新策略

上游更新不等于必须集成。只在以下内容变化时更新 adapter：

- 阶段名称变化
- 阶段顺序变化
- `GO.md` 路由语义变化
- `prompts/*` 或 `templates/*` 结构变化

文档示例、README 文案、内部说明变化默认记为 `NO_IMPACT`。

## 检测命令

```powershell
.\scripts\Test-ForgeFlowKitAdapter.ps1 -RepoPath .\examples\flow-kit-project -Json
.\scripts\Test-ForgeExternalAdapter.ps1 -Name flow-kit -RepoPath .\examples\flow-kit-project -Json
```

检测脚本只读，不修改项目。

## 上游对比

```powershell
.\scripts\Compare-ForgeExternalAdapterRef.ps1 -Name flow-kit -TargetRef "stage-change"
```

输出分类：

- `NO_IMPACT`
- `MAPPING_UPDATE_REQUIRED`
- `BREAKING_CHANGE`
