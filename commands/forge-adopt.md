---
description: Forge 项目接入（底层 fallback）
---

# Forge Adopt（底层 fallback）

> **首选自然语言入口**：直接用 `/forge 接入当前项目` 或 `/forge 完整接入当前项目`，由 forge SKILL 自动判断重量并调度下面三步。本命令仅作为底层 fallback 暴露原子脚本，需要手动逐步控制时使用。

用于把 Forge 接入一个项目工作区。优先使用 CLI，CLI 会复用当前 source-linked 安装并同步 Claude/Codex 用户根：

```powershell
forge install -RepoPath "<repo>"
forge doctor -RepoPath "<repo>"
```

只有 CLI 不在 PATH 或需要逐步调试时，才直接调用底层脚本：

```powershell
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.claude\scripts\forge-project-precheck.ps1" -RepoPath "<repo>"
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.claude\scripts\init-project-profile.ps1" -RepoPath "<repo>"
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.claude\scripts\install-bmad-local.ps1" -RepoPath "<repo>"
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.claude\scripts\Invoke-ForgeHealth.ps1" -Mode Quick -RepoPath "<repo>"
```
