---
description: 启用/禁用 gstack skill 家族（按需 toggle，减少 system prompt 注入）
argument-hint: [status|enable|disable]
---

# gstack Toggle

通过重命名 `~/.claude/skills/gstack/` 目录来控制 gstack skill 家族是否被 Claude Code 扫描注入。

- `enable`：`.gstack-disabled` → `gstack`
- `disable`：`gstack` → `.gstack-disabled`（以 `.` 开头的目录会被忽略）
- `status`：查看当前状态（默认）

任何改动都需要**重启 Claude Code** 才能生效（skill 列表在启动时扫描）。

## 用法

- `/gstack-toggle` 或 `/gstack-toggle status`：查看状态
- `/gstack-toggle disable`：关闭 gstack
- `/gstack-toggle enable`：重新启用

## 执行

根据参数 `{action}`（默认 `status`）调用：

```bash
pwsh.exe -NoProfile -ExecutionPolicy Bypass -Command "& (Join-Path $env:USERPROFILE '.claude\scripts\toggle-gstack.ps1') -Action '{action}'"
```

执行后把脚本输出原样返回给用户，并提醒若发生状态变更需要重启 Claude Code。

## 推荐策略

`gstack` 默认作为验收 gate 按需启用：UI/浏览器态、`ship`、`full` 的最终验收阶段建议启用；日常只读、小修、小范围 fix 不建议长期常驻，以减少 skill 注入和上下文噪音。
