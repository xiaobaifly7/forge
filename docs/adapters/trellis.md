# Forge Trellis adapter

## 定位

Trellis 只作为任务知识外壳参考接入 Forge。它提供 spec、task、workspace、session runtime 的数据模型；Forge 仍是最高治理和门禁真源。

不直接运行 `trellis init` 接管现有 `.claude`、`.codex`、hook 或多平台配置。

## 吸收层

Forge 只吸收这些稳定抽象：

- spec library：项目规范库
- task directory：PRD、技术设计、实现上下文、验证上下文
- workspace journal：开发者 handoff 和决策记录
- session-scoped active task：每个 AI session 独立绑定任务

## 推荐 Forge-native 结构

```text
.forge/tasks/<date>-<task>/
  task.json
  prd.md
  info.md
  implement.jsonl
  check.jsonl
  research/
```

```text
.forge/spec/
  frontend/
  backend/
  security/
  testing/
  review/
  debugging/
  conventions/
  guides/
```

## 更新策略

上游更新不等于必须集成。只在以下内容变化时更新 adapter：

- `task.json` schema 变化
- `prd.md` 或 `info.md` 约定变化
- `implement.jsonl` 或 `check.jsonl` 语义变化
- `.runtime/sessions` 机制变化
- `spec/tasks/workspace` 目录模型变化

CLI、hook、多平台生成器变化默认不吸收，除非用户明确批准。

## 许可证边界

Trellis 为 AGPL-3.0。Forge 侧只吸收数据模型和 adapter 检测思想，不把 Trellis 源码并入 Forge 核心。

## 检测命令

```powershell
.\scripts\Test-ForgeTrellisAdapter.ps1 -RepoPath .\examples\trellis-project -Json
.\scripts\Test-ForgeExternalAdapter.ps1 -Name trellis -RepoPath .\examples\trellis-project -Json
```

检测脚本只读，不修改项目。

## 上游对比

```powershell
.\scripts\Compare-ForgeExternalAdapterRef.ps1 -Name trellis -TargetRef "task-json-schema"
```

输出分类：

- `NO_IMPACT`
- `MAPPING_UPDATE_REQUIRED`
- `BREAKING_CHANGE`
