---
description: Forge 路由入口
---

# Forge 路由入口

本命令是 Forge 路由器，只负责把当前请求分流到合适流程，不直接承载项目接入细节。

- 项目接入/初始化：在 `/forge` 下用自然语言说明意图（如"接入当前项目"），不要再要求用户手记历史子命令。底层 fallback 见 `/forge-adopt`。
- 日常任务按 quick/fix/build/full/ship 路由；`full` 默认是 `guided-full`，`full-auto` 仅用户显式触发。
- 路由判定为 L3/L4/full/guided-full/ship 时，必须按 SKILL.md 第 10 条规则把 routing 事件落盘到 `<repo>/.claude/forge-routing.jsonl`（脚本路径见 SKILL.md）。
- 具体协议以 `$env:USERPROFILE\.claude\docs\forge-protocols.md` 为准。
## Claude / Codex 等价入口

- Claude Code：可直接使用 `/forge` 命令入口。
- Codex：使用同名 `forge` skill 与 CLI 入口；当用户说 `/forge`、`forge`、`按流程来`、`完整走一遍`、`先规划再做`、`full/fix/build/ship` 时，按本命令同样路由。
- 两端共享同一套安装源、docs、scripts、commands、skills；用 `forge version` 确认 `forge_source_drift=false`。
- Codex 中没有 Claude 的 slash UI 时，不视为能力缺失；等价执行路径是：读取 `forge` skill -> 按 L0-L4 分流 -> 必要时调用 `forge doctor/verify/workflows` 验证。
