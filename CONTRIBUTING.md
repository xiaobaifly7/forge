# Contributing to Forge

Forge 目前处于从个人本机工作流抽取为公开仓库的早期阶段。欢迎 issue、文档修正、适配器建议和小范围 PR，但在公开 API 稳定前，贡献应优先保持最小、可验证、可回滚。

## 贡献范围

- 文档修正：README、协议说明、边界说明、schema 说明。
- Windows/PowerShell 兼容性修复：脚本路径、编码、错误处理、hook 行为。
- 适配器提案：Superpowers、GSD、Task Master、gstack、GitNexus、UI review、lint 工具等外部工具的可选接入。
- 验证增强：health、smoke、manifest、docs health、adapter contract 的检查补齐。

暂不建议提交大范围重写、跨平台重构、全新运行时或强绑定外部工具的改动。Forge 的定位是 Claude Code workflow control plane 和 runtime enforcement adapter，不是替代所有 Markdown-first workflow kit。

## 开发约定

- 默认保持 Windows/PowerShell 可用。
- 不要硬编码个人路径、用户名、仓库路径或本机 Claude 配置路径。
- 外部工具必须可选：装了优先调用，没装必须有内置回退或清晰跳过。
- hook 失败策略必须明确区分 `warn`、`fail-close`、`fail-open`。
- 新增行为必须补充至少一个定向验证入口，优先接入 `forge-smoke.ps1` 或对应 health script。

## 本地验证

从仓库根目录运行：

```powershell
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\scripts\forge-smoke.ps1 -NoLog
```

基础文档检查：

```powershell
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test-ForgeDocsHealth.ps1 -ClaudeRoot . -Json
```

manifest 检查会生成 `.claude\forge-workspace-manifest.json`，提交前应清理生成的 `.claude\` 目录：

```powershell
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test-ForgeWorkspaceManifest.ps1 -RepoPath . -Json
Remove-Item -LiteralPath .\.claude -Recurse -Force
```

## PR 要求

- 说明问题、设计意图和影响范围。
- 列出已运行的验证命令和结果。
- 若跳过验证，说明原因和剩余风险。
- 不提交本机生成物、日志、session state、密钥或私有配置。
- 不把 Forge 全套方法论硬塞进其它项目；优先提交可复用的 adapter contract 或可选集成点。

## License

当前仓库还没有选定开源协议。除非 `LICENSE` 被替换为正式开源协议，否则外部贡献在合并前需要维护者明确确认授权方式。
