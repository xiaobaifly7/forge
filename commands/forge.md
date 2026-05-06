---
description: Forge 路由入口
---

# Forge 路由入口

本命令是 Forge 路由器，只负责把当前请求分流到合适流程，不直接承载项目接入细节。

- 项目接入/初始化：在 `/forge` 下用自然语言说明意图（如"接入当前项目"），不要再要求用户手记历史子命令。底层 fallback 见 `/forge-adopt`。
- 日常任务按 quick/fix/build/full/ship 路由；`full` 默认是 `guided-full`，`full-auto` 仅用户显式触发。
- 路由判定为 L3/L4/full/guided-full/ship 时，必须按 SKILL.md 第 10 条规则把 routing 事件落盘到 `<repo>/.claude/forge-routing.jsonl`（脚本路径见 SKILL.md）。
- 具体协议以 `$env:USERPROFILE\.claude\docs\forge-protocols.md` 为准。
