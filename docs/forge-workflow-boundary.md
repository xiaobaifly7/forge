# Forge Workflow Boundary

本文件定义 Forge 融合 BMAD / Superpowers / gstack / Compound Engineering / GSD 的职责边界，避免重复规划、重复 review、重复总结。

## 核心原则

## 反漂移硬边界

- BMAD 是 L3/L4/full 的规划主骨架；Superpowers `brainstorming` 只是 BMAD requirements 阶段的辅助工具。
- Superpowers 不得替代 BMAD 产出 requirements、architecture、stories、acceptance。
- 已确认 L4 milestone 下的子任务继承 L4；不得因局部写集较小降级。
- 需要降低成本时，用 `execution_scope=light`，不要改 `level=L4`。


Forge 是唯一入口和路由器；其他工作流只在 Forge 指定阶段发挥自己的最强项。

```text
Forge 决策
BMAD 规划
Superpowers 执行
gstack 验收
Compound Engineering 沉淀与专项工具
GSD 续航
Memory 跨会话背景
```

## 职责矩阵

| 能力 | Forge | BMAD | Superpowers | gstack | Compound Engineering | GSD |
|---|---|---|---|---|---|---|
| 路由 | 主责 | 禁止 | 禁止 | 禁止 | 禁止 | 禁止 |
| 风险/写集判定 | 主责 | 辅助 | 辅助 | 辅助 | 禁止 | 禁止 |
| 需求/架构/story | 调用 | 主责 | 消费产物 | 禁止 | 禁止替代 | 记录状态 |
| 执行计划 | 选择入口 | 提供约束 | 主责 | 禁止 | 不默认替代 | 记录 next actions |
| 实现/debug | 调用 | 禁止 | 主责 | 禁止 | 仅用户点名 ce-debug | 记录状态 |
| review/验收 | 调用 | 可给验收标准 | 基础验证 | 主责 gate | 仅专项 ce-code-review | 记录风险 |
| 沉淀 | 调用 | 可提供背景 | 可提供结论 | 可提供 gate 结论 | 主责 ce-compound | 主责 next actions |
| 长期记忆 | 可写摘要 | 禁止 | 禁止 | 禁止 | 可整理 | 交给 Memory |

## 去重硬规则

1. BMAD 已经输出 architecture / story / acceptance criteria 后，Superpowers 只转换为执行 checklist，不重新规划需求。
2. Superpowers 已经完成 verification-before-completion 后，gstack 只做 gate，不做完整重复 review。
3. Compound Engineering 只提炼 reusable learning，不复述完整过程。
4. GSD 只写 current_focus / open_risks / next_actions，不写长总结。
5. 若上一层已有等价产物，下一层必须引用它，不得重写一份。
6. 只有用户明确点名 `/ce-*`、`/lfg` 或 Forge 到达对应阶段时，才调用 Compound Engineering。
7. `bmad-workflows` 插件不默认启用；Forge 使用全局 staging 或 repo-local `_bmad` 作为规划源。

## Compound Engineering 白名单

前提：compound-engineering 插件/skills 必须当前可用。若只存在于 cache、marketplace 或未被 Claude Code 启用，Forge 跳过 CE 阶段并说明原因。

默认允许 Forge 调用：

- `/ce-compound`
- `/ce-compound-refresh`
- `/ce-sessions`
- `/ce-pr-description`
- `/ce-resolve-pr-feedback`
- `/ce-test-browser`
- `/ce-code-review`（只在高风险或用户点名时）

默认不允许 CE 接管主流程：

- `/ce-brainstorm`
- `/ce-plan`
- `/ce-work`
- `/lfg`

除非用户明确说“用 CE 全流程 / 用 /lfg / 用 ce-plan”。

## 项目适配分层

不是每个项目都适合同等强度 Forge。

| 项目类型 | 推荐 Forge 强度 | 说明 |
|---|---|---|
| 临时 playground / 草稿 | audit-only / lite | 不自动初始化，不安装 BMAD |
| 单文件脚本 / 小工具 | lite | 只用 fix/build，少用 full |
| 普通 app / CLI | standard | `/forge 接入当前项目 init` 即可，按风险升 full |
| 多包 monorepo / SDK / 服务端 | full-capable | 建议 `/forge 完整接入当前项目`，保留 evidence |
| 安全/支付/认证/数据库项目 | full-by-default | 高风险默认 full + gate |
| 文档/Obsidian/知识库 | audit + compound | 不需要完整 BMAD，实现改动少用 full |

## 输出上限

- BMAD：允许完整规划，但必须产出可消费 artifact。
- Superpowers：只输出执行 checklist / test checklist。
- gstack：只输出阻断问题和非阻断建议。
- Compound Engineering：最多 3-5 条 reusable learning。
- GSD：只输出 current_focus / open_risks / next_actions。

## GitNexus impact gate 与 Forge 路由

GitNexus 已在部分项目的 `CLAUDE.md` 中声明"修改任何 symbol 前必须先 `gitnexus_impact`"。它与 Forge 的 L0-L4 路由不冲突，但需要明确串联顺序，避免重复或互相绕过。

### 调用顺序

```text
Forge 路由（L0-L4 判定）
  -> GitNexus impact 分析（L1+ 任何会改 symbol 的写动作前）
  -> 把 impact 结果纳入 [FORGE] risk 字段
  -> 进入对应协议（quick/build/fix/full/ship）
```

### 边界规则

1. **L0 任务（只读分析）不需要 impact**：纯解读、画像、状态查询不触发 GitNexus impact gate。
2. **L1+ 写动作必须先跑 impact**：单文件改也算，因为符号血缘可能跨文件。
3. **impact 结果纳入 risk 字段**：`gitnexus_impact` 返回 HIGH/CRITICAL 时，Forge 的 `risk` 字段必须升到 `high`，并按规则只升档不降档（拿不准升 L3）。
4. **GitNexus 不替代 Forge 路由**：impact 只回答"改 X 会影响什么"，不决定"用什么协议"，更不决定"是否应该改"。
5. **GitNexus 不替代 BMAD 规划**：L3/L4 的 requirements/architecture/stories 仍由 BMAD 主责，GitNexus 提供 impact 证据作为 architecture 决策输入。
6. **重命名走 `gitnexus_rename`**：跨调用图的重命名不能用 find-and-replace，但仍受 Forge 协议约束（属于 L2+ 写动作）。
7. **commit 前跑 `gitnexus_detect_changes`**：与 Forge ship 协议的 verify 步骤合并，不重复执行。
8. **索引过期时 GitNexus 自检**：若 GitNexus 工具警告 stale，先 `npx gitnexus analyze`，不要在过期索引上做决策。

### 输出要求

L1+ 任务的 `[FORGE]` 路由输出可在 `risk` 字段后追加 `impact=<low|medium|high|critical>`，便于追溯：

```text
[FORGE] level=L2 mode=build reason=feature_in_existing_module
[FORGE] next=plan -> implement -> verify
[FORGE] risk=medium cost=low write_scope=module impact=low
```

未接入 GitNexus 的项目无需此字段。

## 自然语言优先

Forge 默认不要求用户记斜杠命令。

- 自然语言是主入口。
- 斜杠命令是备用快捷方式。
- PowerShell 脚本是底层实现。

常见自然语言映射：

| 用户说法 | 处理方式 |
|---|---|
| 看一下适不适合接入 Forge | 只读 adopt audit |
| 帮我接入 Forge，按最适合方式来 | `/forge 接入当前项目`，先审计，再按推荐初始化 |
| 这是长期复杂项目，完整接入 | `/forge 完整接入当前项目` |
| 临时项目，别搞重 | `/forge 接入当前项目 audit` 或 `/forge 接入当前项目 init` |

底层脚本映射和执行前后验证见 `C:\Users\Administrator\.claude\docs\forge-protocols.md` 的 “自然语言入口执行”。





