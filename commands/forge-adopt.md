---
description: Forge 项目接入（底层 fallback）
---

# Forge Adopt（底层 fallback）

> **首选自然语言入口**：直接用 `/forge 接入当前项目` 或 `/forge 完整接入当前项目`，由 forge SKILL 自动判断重量并调度下面三步。本命令仅作为底层 fallback 暴露原子脚本，需要手动逐步控制时使用。

用于把 Forge 接入一个项目工作区。最小顺序：

```powershell
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.claude\scripts\forge-project-precheck.ps1" -RepoPath "<repo>"
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.claude\scripts\init-project-profile.ps1" -RepoPath "<repo>"
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.claude\scripts\install-bmad-local.ps1" -RepoPath "<repo>"
```

接入后运行：

```powershell
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File "C:\Users\Administrator\.claude\scripts\Invoke-ForgeHealth.ps1" -Mode Quick -RepoPath "<repo>"
```
