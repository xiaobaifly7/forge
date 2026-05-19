# Forge Schema Versions

本文件记录 Forge 本地状态 schema 的当前版本与迁移口径，避免不同状态文件版本看起来像漂移。

## 当前版本

| 文件 | schema_version | 用途 | 迁移状态 |
|---|---:|---|---|
| `<repo>/.claude/project-profile.json` | 3 | 项目画像、默认路由等级、接管模式 | 当前版本 |
| `<repo>/.claude/forge-session-state.json` | 1 | 单次 guided-full / M1 会话阶段状态 | 当前版本 |
| `<repo>/.claude/forge-routing.jsonl` | 1 | 写入阶段与 M1 任务组事件流 | 当前版本 |

## 版本边界

- `project-profile.json` 描述项目长期画像，版本演进较快。
- `forge-session-state.json` 描述短期会话状态，默认带 `expires_at`；过期后不得作为当前事实源。
- `forge-routing.jsonl` 是追加日志，不承载项目画像迁移。

## Drill 状态

演练状态必须显式标注：

```json
{
  "is_drill": true,
  "expires_at": "<iso8601>"
}
```

后续校验脚本遇到 `is_drill=true` 且已过期时，应提示清理或重新初始化，不得把演练状态当真实业务 M1。

## 运行态审计字段（2026-05-04）

`<repo>/.claude/forge-drift-audit.jsonl` 追加写入以下字段，用于区分提示与阻断：

| 字段 | 说明 |
|---|---|
| `mode` | 当前 hook 模式：`warn` 或 `fail-close` |
| `effective_severity` | 本次 issues 聚合后的最高严重度：`warn` 或 `fail-close` |
| `issue_records[]` | 每个 issue 的 `{ code, severity }` |

`Test-ForgeM1Compliance.ps1` 支持三种互斥 selector：`-TaskGroup <id>`、`-Latest`、`-AllOpenGroups`。`-AllOpenGroups` 在没有 open group 时返回 `ok=true`，并设置 `note=no_open_m1_task_groups`。

### Audit fallback log

当 `<repo>/.claude/forge-drift-audit.jsonl` 因沙箱、权限或文件锁无法追加时，`forge-session-audit.ps1` 会保留原始 audit record 并写入 fallback：

1. 优先：`$env:USERPROFILE\.claude\logs\forge-drift-audit-fallback.jsonl`
2. 兜底：`%TEMP%\forge-drift-audit-fallback.jsonl`

fallback 记录包含：`original_path`、`write_errors[]`、`record`。其中 `record` 保留原本要写入 drift audit 的 `mode`、`effective_severity`、`issues` 与 `issue_records[]`。

### Live route freshness result

`Test-ForgeLiveRouteFreshness.ps1 -Json` 输出：

| 字段 | 说明 |
|---|---|
| `max_age_hours` | live route 记录允许的最大年龄 |
| `required_modes[]` | 必须覆盖的路由：`quick`、`fix`、`build`、`full`、`ship` |
| `covered_modes[]` | 当前仍新鲜且通过的路由 |
| `mode_results[]` | 每个 mode 的最新 live 记录、execution、年龄、exit code、output hash 与问题列表 |
| `required_executions` / `covered_executions` | live route 必须覆盖并已覆盖的 execution 集合 |
| `execution_results[]` | 每个 execution 的最新 live 记录、mode、年龄、exit code、output hash 与问题列表 |
| `required_claude_version` | 可选的 Claude Code 版本约束 |

### Session reset result

`Reset-ForgeSessionState.ps1 -Json` 输出：`archive`、`actions[]`、`state_was_expired`、`lock_was_expired`、`expires_at` 与 `validation_commands[]`。脚本只归档/刷新 state 与 lock，不删除历史文件。

### Workspace manifest result

`Test-ForgeWorkspaceManifest.ps1 -Json` 输出：`manifest_path`、`checked_count`、`changed[]`、`issues[]` 与 `action`。manifest 文件为 `<repo>/.claude/forge-workspace-manifest.json`，用于 no-git workspace 的关键文件 hash drift 检查。

### Audit log rotation result

`Rotate-ForgeAuditLogs.ps1 -Json` 输出：`log_path`、`max_bytes`、`keep`、`length_before`、`length_after`、`rotated_to`、`removed[]` 与 `actions[]`。

### Forge health result

`Invoke-ForgeHealth.ps1 -Json` 输出：`mode`、`claude_version`、`checks[]`、`failed[]` 与总体 `ok`。每个 check 包含：`name`、`required`、`command`、`exit_code`、`ok`、`duration_ms`、`output`。

### Upstream and gstack patch results

`Test-ForgeUpstreams.ps1 -Json` 输出每个 upstream 的 `remote`、`branch`、`head`、`head_full`、`origin_main`、`origin_main_full`、`ahead`、`behind`、`is_current`、`dirty_count`、`dirty[]` 与可选 `fetch_error`。脚本逐个 upstream 记录 fetch 失败，不再因为单个仓库网络错误丢掉其它仓库结果。

`Test-GstackLocalPatches.ps1 -Json` 输出 `checks[]` 与 `issues[]`，覆盖 `voice-triggers`、`getHostConfig('claude')`、`skipSkills`、`LOCAL-PATCHES.md` 与 `gstack-global-discover.exe`。

`Test-ForgeWorkflowEntrypoints.ps1 -Json` 输出 `workflows[]` 与 `issues[]`。每个 workflow 包含 `name`、`status`、`policy`、`evidence[]`、`note`。标准状态包括：`active_repo_local`、`staging_active`、`marketplace_active`、`active_global_skill`、`disabled_available`、`vendor_only`、`vendor_only_manual_approval`、`optional_not_installed` 与 `missing`。

### Gstack exported patch artifacts

`Export-GstackLocalPatches.ps1 -Json` 输出：`patch_dir`、`patch_path`、`patch_bytes`、`meta_path`、`status_path` 与 `binary.sha256`。标准 artifact 为 `.local-patches/gstack-local-text.patch`、`.local-patches/gstack-local-binary.json`、`.local-patches/gstack-local-status.txt`。

### Execution router result

`Resolve-ForgeExecutionMode.ps1 -Json` 输出：`mode`、`execution`、`explicit`、`full_auto_explicit`、`downgrade_reason` 与 `reasons[]`。允许的 execution：`guided-full`、`auto`、`audit-only`、`full-auto`。用户显式 guide/auto/full-auto 必须优先于自动判断。

**full-auto 反向 gate（governance §11 升档加强 A，2026-05-17 起生效）**：
- 新增可选参数 `-PromptText <string>`，与 `-Prompt` 等价；同时传入时 `PromptText` 优先。
- 当 `execution=full-auto` 时，必须能从 prompt 文本匹配白名单关键词之一（`full-auto` / `full auto` / `端到端自动推进` / `不要分阶段停顿` / `一气呵成`），否则强制降级为 `guided-full`。
- 降级时 `full_auto_explicit=false` 且 `downgrade_reason` 取 `full_auto_missing_prompt_text`（prompt 为空）或 `full_auto_keyword_absent`（prompt 不含关键词）；通过 stderr 写入 `Write-Warning`。
- `reasons[]` 追加 `downgraded_from_full_auto:<reason>` 便于排障。
- 旧调用方（仅传 `-Prompt -Mode -Json`）行为不变。

