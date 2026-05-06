# Forge Release Checklist

这个 checklist 用于把本机 Forge 仓库发布到 GitHub 或打 tag 前做最小门禁。目标是避免把个人路径、生成物、失效 hook 或未授权协议带到公开仓库。

## 1. 仓库卫生

- `rtk git status --short` 只包含本次计划发布的改动。
- 仓库内没有 `.claude/`、日志、session state、临时 smoke 输出。
- 扫描不到个人硬编码路径，例如 `C:\Users\<name>`、本机 playground 路径、私有仓库路径。
- `.gitignore` 已覆盖本地 Claude 生成物、日志、临时文件。

## 2. 协议与公开边界

- `README.md` 说明 Forge 的定位：Claude Code workflow control plane / runtime enforcement adapter。
- `docs/adapter-contract.md` 说明外部工具如何被可选调用。
- `docs/forge-workflow-boundary.md` 说明 Forge 不替代 Markdown-first workflow kits。
- `LICENSE` 已确认，当前为 MIT License。

## 3. 验证命令

PowerShell 解析：

```powershell
$files = Get-ChildItem -Recurse -Include *.ps1,*.psm1 -File
foreach ($f in $files) {
  $tokens = $null
  $errors = $null
  [System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$tokens, [ref]$errors) | Out-Null
  if ($errors.Count) { throw "$($f.FullName): $($errors[0].Message)" }
}
```

文档健康检查：

```powershell
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test-ForgeDocsHealth.ps1 -ClaudeRoot . -Json
```

workspace manifest：

```powershell
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test-ForgeWorkspaceManifest.ps1 -RepoPath . -Json
Remove-Item -LiteralPath .\.claude -Recurse -Force
```

smoke：

```powershell
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\scripts\forge-smoke.ps1 -NoLog
```

Git 检查：

```powershell
rtk git diff --check
rtk git status --short
```

## 4. GitHub 发布

- 创建 GitHub 空仓库，不要先生成 README/LICENSE，避免和本地历史冲突。
- 添加 remote：`rtk git remote add origin <repo-url>`。
- 首次推送：`rtk git push -u origin main`。
- 若要打 tag：`rtk git tag v0.1.0`，再 `rtk git push origin v0.1.0`。
- 发布说明列出：支持平台、安装方式、验证命令、已知限制、license 状态。

## 5. 发布后检查

- GitHub 页面没有识别到私有路径或密钥。
- README 的安装命令可从干净 clone 运行。
- Issues 模板或 README 已说明：跨平台支持、外部工具适配、Claude Code 版本兼容性仍在收敛。
