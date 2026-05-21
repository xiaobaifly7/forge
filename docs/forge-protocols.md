# Forge 协议详细参考

本文是 `/forge` SKILL.md 的展开层。SKILL.md 只保留路由骨架；规划/执行/验收/沉淀的具体链路放这里，按需读取。项目接入命令统一使用 `/forge 接入当前项目`。

## BMAD 参考源

### 优先级

1. 仓库根目录已存在本地 `_bmad/`，优先使用仓库自己的 BMAD 产物
2. 否则回退到全局 staging：`$env:USERPROFILE\.claude\vendors\bmad-method-staging`

### 缺失本地 BMAD 时

`full` 或 `build` 路径若仓库根目录没有 `_bmad/`，先引导本地 BMAD 再进入协议：

```powershell
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.claude\scripts\install-bmad-local.ps1" -RepoPath "<repo>"
```

或自然语言入口：`/forge 完整接入当前项目`

### Playground / lite tier 豁免

当 `project-profile.json` 中 `tier=playground/lite` 或类似实验性 tier 时，`build` 路径**不强制要求** `_bmad/`。理由：playground 项目以快速验证为主，BMAD 规划开销超过收益。判断顺序：

1. 读 `project-profile.json` 的 `tier` 字段
2. tier ∈ {`playground`, `playground/lite`, `experimental`, `prototype`} → 跳过 `_bmad/` 检查，直接走 build
3. 其他 tier 仍按 L14 要求装 `_bmad/`

如果 playground 项目升档到 `production` 或 `core` tier，需先补装 `_bmad/` 再做 L3+ 任务。

### 重点参考的官方工作流

- `bmad-brainstorming/workflow.md`
- `bmad-domain-research/workflow.md`
- `bmad-technical-research/workflow.md`
- `bmad-create-architecture/workflow.md`
- `bmad-create-epics-and-stories/workflow.md`
- `bmad-create-story/workflow.md`
- `bmad-quick-dev/workflow.md`
- `bmad-review-adversarial-general/workflow.md`
- `bmad-review-edge-case-hunter/workflow.md`

均位于 `vendors\bmad-method-staging\.claude\skills\` 下。Forge 引用，不复制。

## 协议硬规则：BMAD 优先与 L4 继承

### BMAD 是 L3/L4/full 的规划骨架

- BMAD 负责 requirements、architecture、stories、acceptance。
- Superpowers `brainstorming` 只能在 BMAD requirements 阶段作为辅助工具使用。
- 禁止把 Superpowers `brainstorming` 作为 L3/L4/full 的完整规划替代品。
- 阶段命名不得只写 `brainstorming/research`，应写 `BMAD requirements（可辅以 brainstorming/research）`。

### L4 milestone 继承

- 已确认的 L4 milestone / phase / story 创建父治理级别。
- 该父级下的所有子任务默认 `level=L4`，除非用户明确确认脱离父 milestone。
- 子任务范围较小时，使用 `execution_scope=light`，不得降级到 L3/L2。
- 路由日志和人工输出都应保留继承证据：`inherited_from=<milestone_id|phase_id|story_id>`。

### L4 parent inheritance routing 调用

ParentLevel=L4 routing 必须保留 `-Level L4` 与 `-ProjectLevel L4`，并提供 `-InheritedFrom` 与 `-ExecutionScope light|normal|heavy`：

```powershell
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.claude\scripts\write-forge-routing.ps1" -RepoPath "<repo>" -Level L4 -ProjectLevel L4 -ParentLevel L4 -InheritedFrom "<parent-ref>" -ExecutionScope light -Mode full -Execution guided-full -PipelinePhase M1 -BatchProtocol build
```

## 协议固定主链

### `full`

适用：新能力、跨模块、高风险、高不确定性。

进入前要求：本地 `_bmad/` 存在；不存在先通过 `/forge 完整接入当前项目` 只读审计并在用户确认后安装，且必须有用户明确写入授权。

主链：

1. **BMAD 深规划**（默认逐步执行）
   - 阶段 1A：BMAD requirements（可辅以 brainstorming / research）
     - 单题单确认：每次只问 1 个问题，用户回答后再问下一题。
     - 禁止抢跑：1A 未确认完成前，不得讨论技术栈、数据库、部署、实现细节或进入 1B。
     - 产物门禁：完成前必须写入 `<repo>/.claude/forge/artifacts/<yyyyMMdd-HHmmss>-1A-brainstorm.md`。
   - 阶段 1B：architecture
   - 阶段 1C：epics and stories / story
   - 每完成一子阶段先停下汇报"当前位置 / 本阶段产物 / 下一阶段意图"，等用户确认
   - 每次阶段转换必须输出 `[PIPELINE] 阶段 <N或1A> 完成 → 进入/等待 <下一步>`
2. **Superpowers 执行**
   - writing-plans
   - 规划全部确认后才进入执行；执行层按 `best-path first` 选执行形态
   - test-driven-development（行为变更时）
   - verification-before-completion
3. **gstack 把关**：review / QA / design-review / canary / benchmark / 交付前 gate
4. **Compound + GSD**：沉淀 learnings、review patterns、reusable context；更新仓库状态

### guided-full 状态与产物门禁

`guided-full` 必须用本地状态文件把阶段边界变成可回读事实：

```json
{
  "mode": "full",
  "execution": "guided-full",
  "phase": "1A",
  "question_pending": true,
  "artifact_path": "",
  "updated_at": "<iso8601>",
  "last_pipeline_marker": "[PIPELINE] 阶段 1A 进行中 → 等待用户回答"
}
```

状态文件位置：`<repo>/.claude/forge-session-state.json`。

初始化命令：`pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.claude\scripts\Initialize-ForgeGuidedFullState.ps1" -RepoPath "<repo>" -Phase 1A -QuestionPending`。

1A 完成条件全部满足后才能进入 1B：

1. `phase == "1A"`；
2. `question_pending == false`；
3. `artifact_path` 非空、文件存在，且 artifact 文件必须非空；
4. 候选回复包含 `[PIPELINE] 阶段 1A 完成`；
5. `user_confirmed_next_phase == true`，且用户明确确认进入 1B。

本地校验脚本：

```powershell
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.claude\scripts\Test-ForgeGuidedFullGate.ps1" -RepoPath "<repo>" -CandidateText "<assistant draft>"
```

校验失败时，继续停留在当前阶段；不得用自然语言绕过。

### `full-auto`

仅在用户显式 `full-auto` / `端到端自动推进` / `不要分阶段停顿` 时启用。

行为：同 `full` 主链，但不在阶段间等待确认。

### `build`

适用：需求明确、边界清晰、既有架构内开发。

进入前要求：若需要正式 story / architecture / epics 支撑，优先存在本地 `_bmad/`。

主链：

1. BMAD 轻规划：create story 或 quick-dev 收敛范围
2. Superpowers：plan → 按 `best-path first` 选执行形态 → verify
3. gstack 定向验收：focused review / qa
4. GSD 更新当前状态

### `fix`

适用：bug、回归、测试失败、环境故障、行为异常。

主链：

1. BMAD 最小问题框定：症状 / 影响面 / 回归边界
2. Superpowers：systematic-debugging → verification-before-completion；可并行时把只读核对/日志复核拆给 sidecar
3. gstack 回归把关：changed-path review / qa（按风险触发）
4. GSD 更新修复结论与剩余风险

### `ship`

适用：上线前、交付前、merge-ready、handoff。

主链：

1. BMAD 验收口径确认：done criteria / release notes inputs / rollback concerns
2. Superpowers 收尾：docs / tests / versioning / artifacts
3. gstack 最终 gate：review / qa / ship checks
4. Compound + GSD 封版沉淀

## 工作流边界与去重

边界真源：`$env:USERPROFILE\.claude\docs\forge-workflow-boundary.md`。

本文不重复定义职责矩阵、去重硬规则、项目适配分层或自然语言入口；需要判断边界时读取边界真源。

## 边界真源引用

Compound Engineering 白名单、CE 插件启用前提、项目适配分层、职责矩阵、去重硬规则和自然语言原则都只在：

```text
$env:USERPROFILE\.claude\docs\forge-workflow-boundary.md
```

本文只补充执行规则：项目画像与用户目标冲突时，以用户当前目标优先；必须说明降级或升档原因。

## Step 0-4 详细流程

### Step 0：初始化

1. 找出当前 repo root
2. 读取 `<repo>/.claude/project-profile.json`
3. 缺失则提示 `/forge 接入当前项目 init`；只有获得写入授权时才运行 `init-project-profile.ps1` 生成初稿
4. 回读 `<repo>/.claude/workflow-policy.md`
5. 归纳当前任务信号：新功能 / 修 bug / 收尾交付 / 调研规划 / 重构；改动范围；是否涉及全局/共享/持久化/依赖/认证；是否临近发布

### Step 1：选路顺序

1. **用户 override**：显式 `full/build/fix/ship` 直接采用
2. **硬触发器**（命中任一直接 `full`）：全局配置变更 / 共享契约 / 持久化 schema / 依赖升级 / 认证支付安全 / 多服务跨边界 / 并发队列定时
3. **任务意图**：bug→`fix`、release→`ship`、清晰需求→`build`、模糊调研→`full`
4. **画像只升档不降档**：`risk_level=high` / `default_min_mode=full` / `shared_surface=true` / `has_public_contracts=true` / `test_maturity=low` / `has_release_pipeline=true` 且接近交付
5. **默认保守**：仍无法判定走 `full`

### Step 2：协议执行

按上文协议主链。

### Step 3：协议内升级规则

- 协议选定后不再自由切换
- 仅允许升级（`build/fix/ship → full`），禁止降级（`full → build/fix/ship`）
- 升级仅在出现新增高风险信号时触发

### Step 4：第一次进入新仓库

1. 提示 `/forge 接入当前项目 init`，或在已有写入授权时运行 `init-project-profile.ps1`
2. 读取生成的 `project-profile.json` 与 `workflow-policy.md`
3. 一句话总结项目画像
4. 给出本次任务的协议判断

## 路由日志

进入 `L3/L4`、`full/guided-full`、`ship` 或 M1 实施期时追加到 `<repo>/.claude/forge-routing.jsonl`。L0/L1 直通和普通 L2 build/fix 不强制写 routing log；若本轮目标是审计/演练，可以显式写 `reason=drill`。

```powershell
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.claude\scripts\write-forge-routing.ps1" -RepoPath "<repo>" -Level L3 -Mode full -Execution guided-full -AdoptionMode local_routing -Risk high -Cost medium -WriteScope cross_module -Reason shared_contract,security_auth
```

字段：

```json
{
  "time": "<iso8601>",
  "level": "L3",
  "mode": "full",
  "execution": "guided-full",
  "adoption_mode": "local_routing",
  "risk": "high",
  "cost": "medium",
  "write_scope": "cross_module",
  "reason": ["shared_contract", "security_auth"],
  "profile": ".claude/project-profile.json",
  "policy": ".claude/workflow-policy.md",
  "bmad_local": true,
  "gstack_enabled": false,
  "prompt_sha256": "<hash-only-no-raw-prompt>"
}
```

`level` 与 `adoption_mode` 必填。禁止写入完整 prompt、密钥、token、验证码、业务敏感数据。

## M1 实施期合规门禁

M1 仅在 `L4` 或用户显式选择 `full/guided-full` 且规划已确认后启用。L0-L2 的日常只读、小修、普通 build/fix 不强制 M1，也不要求写 M1 routing log。

M1 是 full/guided-full 在规划确认后的实施期。M1 的目标不是继续讨论方案，而是把每组执行任务变成可审计事件链。

### M1 任务组开始模板

每组任务开始前必须输出：

```text
[FORGE] phase=M1 group=<M1.n> mode=<build|fix|full> reason=<reason>
[FORGE] write_scope=<none|single_file|module|cross_module|global> verify=<typecheck|test|build|manual|none> commit_required=<true|false>
[PIPELINE] 阶段 M1.<n> 开始 → 执行
```

同时必须追加 routing event：

```powershell
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.claude\scripts\write-forge-routing.ps1" -RepoPath "<repo>" -Level L3 -Mode full -Execution guided-full -AdoptionMode local_routing -PipelinePhase M1 -TaskGroup M1.1 -GroupStatus started -WriteScope module -VerificationRef "<planned>" -Reason implementation_group
```

### M1 任务组完成模板

每组任务结束时必须输出：

```text
[PIPELINE] 阶段 M1.<n> 完成 → 进入 <M1.n+1|M1.review|done>
```

并再次追加 routing event，`GroupStatus=completed`，同时填入：

- `TodoRef`：todo/task 追踪引用；没有 todo 时必须填 `skip:<reason>`。
- `VerificationRef`：实际运行的验证命令/结果；无法验证时必须填 `skip:<reason>`。
- `ArtifactRef`：本组产物、PRD、spec、日志或文件路径；无产物时填 `skip:<reason>`。
- `CommitSha`：commit hash；未提交时必须填 `skip:<reason>`。
- `LearningsRef`：沉淀层记录；无沉淀时必须填 `skip:<reason>`。
- `NextPhase`：下一阶段。

### M1 高风险工程纪律

如果任务组涉及 auth、jwt、init-data、signature、contract、permission、money path、database migration 或 security boundary，则该组为高风险实施组。

高风险实施组完成事件必须额外提供：

- `HighRisk`：命中的高风险标签，例如 `auth,jwt,signature`。
- `TodoRef`：必须是 `TodoWrite:<id>`，不得用 forge-routing 代替。
- `TddRef`：必须记录先测后写的证据；若偏离，必须写 `deviation:<reason>`，且不能静默跳过。
- `TestRef`：必须有 unit/integration 测试结果；不能只用 typecheck。
- `VerificationRef`：可包含 typecheck，但高风险组不能只有 `typecheck:pass`。

示例：

```powershell
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.claude\scripts\write-forge-routing.ps1" -RepoPath "<repo>" -Level L4 -Mode full -Execution guided-full -PipelinePhase M1 -TaskGroup W1-B -GroupStatus completed -HighRisk "auth,jwt,signature" -TodoRef "TodoWrite:W1-B" -TddRef "red-green:auth-jwt-init-data" -TestRef "unit:pass:14" -VerificationRef "typecheck:pass;unit:pass" -CommitSha "<sha>" -LearningsRef ".claude/compound-learnings.md" -NextPhase W2
```


- 高风险任务不得用 `typecheck:pass` 或 manual-only 作为唯一验证；`TestRef` 必须包含 `unit` 或 `integration` 证据，且 `TddRef` 必须明确记录红绿循环/偏离原因。

### M1 完成条件

M1 组任务不得仅凭“文件已写”宣称完成。至少满足：

1. 有 `[FORGE] phase=M1 group=<id>` 开始头；
2. 有 `[PIPELINE] 阶段 M1.<id> 完成`；
3. 有 started 与 completed 两条 `forge-routing.jsonl`；
4. 有 todo/ref 或显式 skip reason；
5. 有 verification/ref 或显式 skip reason；
6. 有 commit sha 或显式 skip reason；
7. 有 learnings/captures/ref 或显式 skip reason。

本地校验脚本：

```powershell
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.claude\scripts\Test-ForgeM1Compliance.ps1" -RepoPath "<repo>" -TaskGroup "M1.1" -CandidateText "<assistant draft>"
```

## Compound 与 GSD 落盘

进入写入阶段后，仓库允许本地状态时收尾使用：

- `<repo>/.claude/compound-learnings.md`
- `<repo>/.claude/gsd-state.json`

辅助脚本：

```powershell
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.claude\scripts\update-forge-state.ps1" -RepoPath "<repo>" -Mode fix -CurrentFocus "<focus>" -OpenRisks "<risk>" -NextActions "<next>" -Learning "<learning>"
```

audit-only 任务只建议这些文件，不自动创建。

## gstack 启用策略

`gstack` 是 review / QA / ship / canary / benchmark gate，不是默认执行层。

- 日常只读、小修、小范围 fix：默认不启用
- UI / 浏览器态 / 交互验收：启用
- `ship`：作为最终 review / QA / ship gate
- `full`：在 review / QA / canary / benchmark / 交付前 gate 阶段启用
- 当前禁用但任务需要时，先提示 `/gstack-toggle enable` 并说明需重启 Claude Code

## 自然语言入口执行

自然语言原则的真源在 `forge-workflow-boundary.md`。本节只记录底层脚本映射。

| 用户自然语言 | 意图 | 底层 |
|---|---|---|
| "看一下这个项目适合不适合 Forge" / "先别改，评估一下" | adopt audit | `forge single-entry adopt-natural.ps1 -Action audit` |
| "帮我接入 Forge，按最适合方式来" | single-entry adopt | 使用 `/forge 接入当前项目`，先 audit，再按推荐初始化 |
| "帮我把这个项目配置好 Forge" / "全部搞定" | adopt write | 备份+评估，执行推荐动作并回读 |
| "这是长期/复杂/高风险项目，完整接入" | full adopt | 使用 `/forge 完整接入当前项目`，先审计，确认后完整接入 |
| "这是临时/小项目，别搞重" | lite adopt | audit 或 init，不安装 BMAD |

底层脚本：

```powershell
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.claude\scripts\forge single-entry adopt-natural.ps1" -RepoPath "<repo>" -Action audit
```

写入授权条件之一：用户明确说"执行 / 帮我搞定 / 配置好 / 全部完成"；用户明确选择初始化方式；当前任务已有写入授权。无授权只能 audit。

执行后回读验证：`project-profile.json`、`workflow-policy.md`、`_bmad/`、`.claude/skills/bmad-*`、`.claude/bmad-version.lock`、`forge_tier` 与推荐动作是否符合证据。

### M1 自动化门禁补充（2026-05-04）

- `PreToolUse` 写入门禁：当 `<repo>/.claude/forge-session-state.json` 显示 `execution=guided-full` 且 `phase=M1` 时，写普通项目文件前必须已经存在 M1 `started` routing event；写 `.claude/forge/*`、`forge-session-state.json`、`forge-session.lock.json`、`forge-routing.jsonl`、`forge-drift-audit.jsonl` 允许通过。
- 高风险 / L4 M1 写入门禁：若 M1 started event 命中 `L4`、`high_risk`、`auth/security/release/shared/contract/schema/persistence` 等信号，写普通项目文件前必须已经有 `TodoRef=TodoWrite:<id>`、非 skip 的 `TddRef`、且 `TestRef` 包含 `unit` 或 `integration`。
- Stop 审计分级：`forge-session-audit.ps1 -Mode warn` 只写 drift log 与 additionalContext；`-Mode fail-close` 对 M1 未完成、高风险缺 TodoWrite/TDD/TestRef、L4 downgrade 证据缺失、state/lock mismatch 等问题返回非零退出码。
- Stop 审计日志 fallback：若 `<repo>/.claude/forge-drift-audit.jsonl` 因沙箱、权限或文件锁无法追加，audit 会重试并写 `forge-drift-audit-fallback.jsonl`；优先路径是 `$env:USERPROFILE\.claude\logs\forge-drift-audit-fallback.jsonl`，最后兜底 `%TEMP%`。
- 当前 playground 的 `.claude/settings.json` Stop hook 使用 `-Mode fail-close`；SessionStart 保持 warn 语义，避免启动时误阻断。

### M1 合规检查快捷入口

```powershell
# 检查指定任务组
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.claude\scripts\Test-ForgeM1Compliance.ps1" -RepoPath "<repo>" -TaskGroup "M1.1" -CandidateText "<assistant draft>" -Json

# 检查最近一个 M1 任务组
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.claude\scripts\Test-ForgeM1Compliance.ps1" -RepoPath "<repo>" -Latest -Json

# 检查所有 started 但未 completed 的 M1 任务组；没有 open group 时返回 ok=true，并带 note=no_open_m1_task_groups
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.claude\scripts\Test-ForgeM1Compliance.ps1" -RepoPath "<repo>" -AllOpenGroups -Json
```

### Forge smoke live route

`forge-smoke.ps1` 默认执行离线路由、drift、M1、高风险、L4 downgrade、adapter contract、docs health 回归。需要额外探测 Claude Code 真实路由时可加 `-LiveClaudeRoute`：

```powershell
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.claude\scripts\forge-smoke.ps1" -LiveClaudeRoute
```

live route 只在能从 Claude 输出解析出 `[forge] mode=...` 与 `[forge] execution=...` 时计入 pass/fail；若 Claude 命令异常、超时或输出没有可解析 route，则计入 skipped，不得把 skipped 当作 live 验收通过。

当前 live route eval 覆盖 `quick/fix/build/full/ship`，并要求 execution 覆盖 `audit-only/auto/guided-full`；不默认覆盖 `full-auto`，避免把“端到端自动推进”语义误放进常规验收。

注意：`-LiveClaudeRoute` 和 `-IncludeLiveClaudeRoute` 会真实调用 Claude Code，耗时更长且会产生成本。默认 smoke 不运行 live route；只有在改路由规则、hook 接线、发布前验收或手动要求时才运行。

### Forge smoke settings gate

`forge-smoke.ps1` 会检查项目级 `.claude/settings.json` 的关键接线，并输出：

- `settings_gate_total`：当前固定为 2，分别检查 Stop hook 与 PreToolUse hook。
- `settings_gate_passed`：通过的接线断言数量。
- `settings_gate_failed`：失败的接线断言数量；大于 0 时 smoke 返回非零退出码。

当前要求：

1. Stop hook 命令必须包含 `forge-session-audit.ps1`、`-Event Stop`、`-Mode fail-close`。
2. PreToolUse hook 命令必须包含 `forge-pretool-guard.ps1`。
### 运行态维护脚本

- `Test-ForgeLiveRouteFreshness.ps1`：读取 `$env:USERPROFILE\.claude\logs\forge-smoke.jsonl`，确认最近 live route 覆盖 `quick/fix/build/full/ship` 与 `audit-only/auto/guided-full` execution、全部 `passed=true`、未超过 `-MaxAgeHours`，并可用 `-RequiredClaudeVersion` 绑定当前 Claude Code 版本。
- `Reset-ForgeSessionState.ps1`：安全归档并刷新 `<repo>/.claude/forge-session-state.json` 与 `forge-session.lock.json`；默认只在 state/lock 缺失或过期时动作，`-Force` 可强制刷新，归档目录位于 `<repo>/.claude/backups/forge-session-reset-*`。

### 长期运维脚本

- `Rotate-ForgeAuditLogs.ps1`：轮转 `forge-drift-audit-fallback.jsonl`，默认超过 5MB 归档并保留最近 10 份。
- `Test-ForgeWorkspaceManifest.ps1`：在 no-git workspace 中用 SHA256 manifest 保护关键 Forge 文件；`-Update` 创建或刷新 `<repo>/.claude/forge-workspace-manifest.json`，默认模式检查 hash drift。
- gstack vendor 的本地适配必须记录在 `LOCAL-PATCHES.md`，包括 `voice-triggers` frontmatter、`scripts/skill-check.ts` 的 Claude host skip 逻辑和 `bin/gstack-global-discover.exe`。

### 一键健康检查与 upstream 校验

- `Invoke-ForgeHealth.ps1`：聚合 docs health、session state、live freshness、workspace manifest、audit rotation、upstreams、gstack patches、M1 latest 与 offline/live smoke；支持 `-Mode Offline|Live|Full` 和 `-Json`。
- `Test-ForgeUpstreams.ps1`：检查 BMAD、Compound Engineering、GSD-2、gstack 的 remote、HEAD、origin/main、ahead/behind 与 dirty state；可加 `-Fetch` 联网刷新。
- `Test-GstackLocalPatches.ps1`：自动校验 gstack 本地 patch 是否还存在，包括 `voice-triggers`、`getHostConfig('claude')` / `skipSkills`、`LOCAL-PATCHES.md` 和 `gstack-global-discover.exe`。
- `Export-GstackLocalPatches.ps1`：将 gstack 本地 dirty patch 导出为 `.local-patches/gstack-local-text.patch`，并记录 `gstack-global-discover.exe` 的 SHA256 元数据；这是 upstream 更新后恢复/核对本地适配的标准 artifact。
- 日常入口收敛：除非正在做单项排错，默认只跑 `Invoke-ForgeHealth.ps1 -Mode Offline`；重大升级或 hook/route 变更后再跑 `-Mode Full`。

### Guide / Auto execution 判定

Forge 先判定 `mode=quick|build|fix|full|ship|full-auto`，再用 `Resolve-ForgeExecutionMode.ps1` 判定 execution。

铁律：用户显式指定永远优先。

- 显式 guide/guided/指导模式/带我一步步/每步确认/等我确认 → `execution=guided-full`
- 显式 auto/自动模式/自动执行/直接做完/不用问我/无需确认 → `execution=auto`
- 显式 full-auto/端到端自动推进/不要分阶段停顿 → `execution=full-auto`

未显式时自动判断：

- `quick` → `audit-only`
- 清晰 `build` / `fix` / `ship` → `auto`
- `full`、高风险、跨模块、共享契约、认证安全、数据库/schema/依赖升级、方案不清或需要用户选择 → `guided-full`

执行前输出必须包含：

```text
[FORGE] execution=<guided-full|auto|audit-only|full-auto> explicit=<true|false> reason=<reason>
```

## Forge unified route 输出

`forge route` 是统一控制面入口。它一次性输出：

- `level`：L0-L4
- `mode`：quick/build/fix/full/ship/full-auto
- `execution`：audit-only/auto/guided-full/full-auto
- `frameworks`：BMAD、Superpowers、CE、GSD、gstack 是否参与
- `ce_commands`：按需启用的 CE 白名单能力
- `reasons`：触发依据

示例：

```powershell
forge route -Title "准备发布这个版本，做 release handoff 和复盘沉淀" -Subcommand ship -Json
forge upstreams -Full -Json
```

边界：

- BMAD 只在 L3/L4/full 做规划主骨架。
- Superpowers 负责执行纪律，不替代 BMAD 规划。
- CE 只按需启用专项白名单能力：debug、review、PR feedback、browser test、compound learning。
- GSD 只在 L4/ship/handoff 负责状态交接和 next actions。
- gstack 只做 review/QA/ship gate，不做主规划。


## Review 分工与 Codex 插件

Forge review 阶段默认把 Claude Code 内的代码审计交给 OpenAI Codex 插件：

- 默认 diff/code review：Claude Code 中运行 `/codex:review`。
- 高风险专项审查：认证、安全、数据库 schema、迁移、共享契约、跨模块等场景追加 CE `ce-code-review`。
- ship/release gate：发布、交付、final/QA/canary/benchmark 场景追加 `gstack gate`。
- 机器门禁：所有 review plan 最后都跑 `forge verify -RepoPath <repo> -Full`。

CLI 入口：

```powershell
forge review -RepoPath <repo> -Title "Task prompt" -Subcommand <quick|build|fix|full|ship|full-auto> -Json
```

`forge review` 只生成可审计计划，不替代 Claude Code 插件交互；真正审查在 Claude Code 会话里执行 `/codex:review`。

## Framework upstream 自动更新

`forge update-frameworks` 默认只审计，不改文件：

```powershell
forge update-frameworks -Json
```

明确 `-Apply` 才执行 `git pull --ff-only`：

```powershell
forge update-frameworks -Apply -Json
```

安全门禁：

- 缺 upstream：停止。
- dirty：停止。
- ahead：停止。
- 非 fast-forward：停止。
- gstack 检测到本地 patch 标记：停止并要求人工 review。
- Apply 后自动跑 workflows / doctor / verify -Full。
