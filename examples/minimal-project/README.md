# Forge Minimal Project

这个示例用于解释 Forge 的最小运行模型：Claude Code 仍然执行实际工作，Forge 通过 hooks 和 `.claude/forge-*` state 在关键阶段做运行时门禁。

## 文件

- `.claude/settings.json`：项目级 Claude Code hook 示例。复制到真实项目后，把 `<forge-repo>` 替换为 Forge 仓库路径，把 `<project-repo>` 替换为目标项目路径。
- `.claude/forge-session-state.blocked.json`：一个会触发 1A 写入门禁的示例 state。复制为 `.claude/forge-session-state.json` 后，普通项目写入会被拦截。

## 运行思路

1. 把 Forge 安装到真实项目：

```powershell
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File <forge-repo>\scripts\Install-ForgeLocal.ps1 -RepoPath <project-repo>
```

2. 复制示例 settings：

```powershell
Copy-Item -LiteralPath <forge-repo>\examples\minimal-project\.claude\settings.json -Destination <project-repo>\.claude\settings.json -Force
```

3. 替换 `<forge-repo>` 和 `<project-repo>` 占位符。

4. 复制 blocked state，模拟 1A 还有待回答问题：

```powershell
Copy-Item -LiteralPath <forge-repo>\examples\minimal-project\.claude\forge-session-state.blocked.json -Destination <project-repo>\.claude\forge-session-state.json -Force
```

5. 在 Claude Code 里尝试写普通项目文件。Forge pre-tool guard 应拦截，并提示先回答 1A 单问。

6. 把 `question_pending` 改为 `false` 或删除 `.claude\forge-session-state.json`，再尝试写入，门禁会放行。

## 注意

这个示例只展示门禁行为，不代表完整 Forge 项目接入。完整接入仍应运行 health 和 smoke：

```powershell
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File <forge-repo>\scripts\forge-smoke.ps1 -NoLog
```
