---
name: forge
description: |
  项目感知固定工作流入口。用于中高风险、跨模块、持久化/数据库/Redis/schema、私钥/签名/Fernet/认证/安全、钱包/交易广播、依赖升级、新能力接入等任务，或当用户说"按流程来""完整走一遍""先规划再做""不要直接开工""forge/full/fix/ship"时触发。读取仓库画像和当前任务信号，先按 L0-L4 分流，再映射到 quick/build/fix/full/ship/full-auto；用户显式指定永远优先。
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Glob
  - Grep
  - Agent
  - AskUserQuestion
---

# /forge — 项目感知固定工作流入口

## 定位

`forge` 是薄路由器，只做四件事：

1. 识别 repo root 与本地画像
2. 读取 `<repo>/.claude/project-profile.json` 与 `workflow-policy.md`（缺失则先只读审计；有写入授权时才生成）
3. 按用户要求 + 项目画像 + 任务信号判定 `L0-L4`
4. 映射到 `quick/build/fix/full/ship/full-auto` 最小充分协议

不规划、不执行、不验收、不替用户临场发明流程。协议内部链路固定，不自由调度。

协议内部遵循 **best-path first**：写集清晰、可并行、收益明显时用 subagent；强耦合或单线思考时用单代理；交付前把关交给 gstack。subagent 是手段之一，不是默认主路线。

## 任务等级与协议映射

## 协议硬规则：BMAD 优先与 L4 继承

### BMAD 优先

L3/L4/full 的规划主骨架必须是 BMAD。Superpowers `brainstorming` 只能作为 BMAD requirements 阶段里的辅助收敛工具，不得替代 BMAD requirements、architecture、stories、acceptance。

正确层级：

```text
Forge 路由
  -> BMAD planning: requirements -> architecture -> stories -> acceptance
  -> Superpowers execution: writing-plans -> TDD/debug -> verification
  -> gstack gate / GSD / compound 按需收尾
```

### L4 继承

如果当前任务属于已确认的 L4 milestone / phase / story，子任务默认继承 L4，不得因为局部写集较小而降级到 L3/L2。可降低 `execution_scope`，不可降低 `level`。

L4 子任务路由必须追加：

```text
[FORGE] inherited_from=<milestone_id|phase_id|story_id|none> execution_scope=<light|normal|heavy>
```


| 等级 | 判断标准 | 协议 |
|---|---|---|
| L0 | 只读解释、查配置、状态确认、方案评价，不写文件 | `quick/audit-only` |
| L1 | 单文件小改、文案/配置小修、无行为或低风险行为变化 | `quick/direct` |
| L2 | 多文件但边界清晰、既有架构内开发、普通 bug/fix | `build` 或 `fix` |
| L3 | 架构调整、跨模块、共享契约、数据库、认证、安全、依赖升级、全局配置 | `full`（默认 guided-full） |
| L4 | 多阶段长期项目、自治执行、需要状态连续性和阶段复盘 | `full + stateful`（GSD-2/compound） |

`full-auto` 仅用户显式触发，自动路由不得选用。

## 模块职责边界

职责矩阵、CE 白名单、项目适配分层、输出上限与自然语言原则的真源在：

```text
C:\Users\Administrator\.claude\docs\forge-workflow-boundary.md
```

本 SKILL 只保留路由骨架，不重复定义边界规则。

## 项目接管模式

每个项目必须明确 `project-profile.json` 的 `forge_adoption.mode`：

| mode | 含义 |
|---|---|
| `disabled` | 不接入 Forge |
| `audit_only` | 只读审计，不写状态、不安装、不接管 |
| `local_routing` | 只做 L0-L4 路由，不强制完整链 |
| `full` | 允许完整 BMAD / Superpowers / gstack / GSD / compound 链 |

profile 缺失或字段空缺时，按目录证据推断；推断不确定时默认 `local_routing`。

## 本地状态

- 仓库入口：`<repo>/CLAUDE.md`
- 机器可读真源：`<repo>/.claude/project-profile.json`（含 `forge_adoption.mode`）
- 人类可读摘要：`<repo>/.claude/workflow-policy.md`

缺失则先做只读审计并提示可通过 `/forge 接入当前项目` 初始化；只有获得写入授权时才执行：

```powershell
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File "C:\Users\Administrator\.claude\scripts\init-project-profile.ps1" -RepoPath "<repo>"
```

## 路由铁律

1. 用户显式指定 `quick/build/fix/full/ship/full-auto` 或 `L0-L4` 时直接采用
2. `full-auto` 仅在显式说"端到端自动推进 / 不要分阶段停顿"时启用
3. 自动判断只决定入口协议，不改写协议内部
4. 拿不准只升档不降档
5. 命中硬触发器（共享契约、持久化 schema、依赖升级、认证支付安全、并发队列）直接 `L3/full`；长期自治升 `L4/full+stateful`
6. 显式 `full` 不得自动降为 `build`
7. execution 由 `Resolve-ForgeExecutionMode.ps1` 判定：用户显式 guide/guided/一步步/每步确认时必须 `guided-full`；显式 auto/自动做完/不用问我时必须 `auto`；显式 `full-auto` 时必须 `full-auto`。
8. 未显式时自动判断：高风险、跨模块、方案不清、full/L3-L4 默认 `guided-full`；清晰 build/fix/ship 默认 `auto`；quick 默认 `audit-only`。
9. 进入协议前必须输出三行路由结论（见下），并补充 `execution=<guided-full|auto|audit-only|full-auto>`。
10. **路由日志硬规则**：判定为 `L3/L4`、`full/guided-full/full-auto` 或 `ship` 时，输出三行路由结论后必须立即调用 `write-forge-routing.ps1` 落盘到 `<repo>/.claude/forge-routing.jsonl`。L0/L1 直通和普通 L2 build/fix 豁免，但项目接管演练/调试需显式写 `reason=drill`。漏写视为路由未完成，等同于跳过协议。详见 `forge-protocols.md` 的 “M1 实施期合规门禁” 与 routing log 字段表。

```powershell
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File "C:\Users\Administrator\.claude\scripts\write-forge-routing.ps1" -RepoPath "<repo>" -Level <L3|L4> -Mode <full|ship|...> -Execution <guided-full|auto|full-auto> -Risk <low|medium|high> -Cost <low|medium|high> -WriteScope <module|cross_module|global> -Reason <comma-separated triggers>
```

## 输出要求

每次进入协议至少输出：

```text
[FORGE] level=<L0|L1|L2|L3|L4> mode=<mode> reason=<comma-separated triggers>
[FORGE] next=<first protocol step>
[FORGE] risk=<low|medium|high> cost=<low|medium|high> write_scope=<none|single_file|module|cross_module|global>
```

`mode=full` 且未显式 `full-auto` 时追加：

```text
[FORGE] execution=guided-full
[FORGE] wait_for_confirmation=true
[PIPELINE] 阶段 1A 开始 → BMAD requirements（可辅以 brainstorming/research）
```

## guided-full 防漂移门禁

`execution=guided-full` 是逐阶段、单题确认、可回读状态的协议，不是普通提示词。进入 `full` 后必须遵守：

1. **1A 单题单确认**：阶段 1A 每次只允许向用户提出 1 个问题；同一回复不得合并多个需求、技术、部署或验收问题。
2. **禁止抢跑**：阶段 1A 未收到用户明确确认前，不得进入 1B architecture，不得讨论技术栈选型、数据库、部署方案或实现细节；除非用户主动要求。
3. **阶段标记必填**：每个阶段/子阶段结束必须输出 `[PIPELINE] 阶段 <N或1A> 完成 → 进入/等待 <下一步>`；缺失则视为协议未完成。
4. **状态文件必填**：guided-full 写入阶段必须维护 `<repo>/.claude/forge-session-state.json`，至少包含 `schema_version`、`mode`、`execution`、`phase`、`question_pending`、`user_confirmed_next_phase`、`artifact_path`、`session_id`、`created_at`、`updated_at`、`expires_at`。
5. **1A 产物门禁**：宣布 `阶段 1A 完成` 前，必须先落盘 `<repo>/.claude/forge/artifacts/<yyyyMMdd-HHmmss>-1A-brainstorm.md`，并把路径写入 `artifact_path`。
6. **无产物不完成**：如果 `artifact_path` 为空、文件不存在或文件为空，只能输出 `[PIPELINE] 阶段 1A 进行中 → 等待产物落盘`，不得进入 1B。
7. **确认门禁**：进入 1B 前必须先把 `user_confirmed_next_phase` 置为 `true`；否则不得输出进入 1B/架构阶段。
8. **本地校验优先**：如有疑问，先运行 `Test-ForgeGuidedFullGate.ps1` 校验状态与候选回复，再继续。

只读审计追加：

```text
[FORGE] execution=audit-only
[FORGE] write=false
```

## M1 实施期合规要求

M1 是 `L4` 或用户显式 `full/guided-full` 的实施期门禁；L0-L2 的日常只读、小修、普通 build/fix 不强制 M1，也不要求写 M1 routing log。

详细事件字段、模板、高风险纪律与校验命令只在 `forge-protocols.md` 的 “M1 实施期合规门禁” 中定义。本 SKILL 不复制字段清单，避免漂移。

## 写集口径

- `none`：只读审计
- `single_file`：单文件小改
- `module`：单模块多文件
- `cross_module`：跨模块/共享契约
- `global`：全局配置/系统级行为

## 详细参考

协议主链、BMAD 引用、路由日志格式、M1 细则、Compound/GSD 落盘、gstack 启用策略、Step 0-4 详细流程，全部在：

```text
C:\Users\Administrator\.claude\docs\forge-protocols.md
```

`/forge` 触发时按需读取该文档，不在本 SKILL 中重复。

边界真源：`C:\Users\Administrator\.claude\docs\forge-workflow-boundary.md`

项目接入也使用单一入口：`/forge 接入当前项目`。不要再要求用户手记历史接入子命令；`/forge-adopt` 命令文件保留作为底层入口，但用户面建议统一通过 `/forge` 自然语言触发。





