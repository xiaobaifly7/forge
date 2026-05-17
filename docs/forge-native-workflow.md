# Forge-native Workflow

## 目标

本流程把 flow-kit、Trellis、Forge、OMX 的可用点统一到 Forge 体系内：

- flow-kit 提供阶段方法论
- Trellis 提供 task/spec/workspace 数据模型参考
- Forge 保持最高治理、门禁、health、smoke
- OMX 作为执行 runtime

## 日常流程

```text
用户提出需求
-> New-ForgeTask.ps1 创建任务
-> Update-ForgeTaskContext.ps1 选择 implement/check 上下文
-> Set-ForgeActiveTask.ps1 绑定当前 session
-> Resolve-ForgeStage.ps1 判断阶段和 route
-> 执行实现或验证
-> Test-ForgeTaskKernel.ps1 检查任务内核
-> Add-ForgeSpecFinding.ps1 沉淀可复用经验
-> Invoke-ForgeHealth.ps1 / forge-smoke.ps1 收口
```

## 推荐命令

创建任务：

```powershell
.\scripts\New-ForgeTask.ps1 -Name "sample-task" -Title "Sample Task" -Goal "..."
```

追加上下文：

```powershell
.\scripts\Update-ForgeTaskContext.ps1 `
  -TaskPath .forge\tasks\05-07-sample-task `
  -Target implement `
  -File .forge\spec\conventions\index.md `
  -Reason "实现前读取项目约定"
```

绑定 session：

```powershell
.\scripts\Set-ForgeActiveTask.ps1 `
  -SessionId codex-current `
  -TaskPath .forge\tasks\05-07-sample-task `
  -Stage task
```

解析阶段：

```powershell
.\scripts\Resolve-ForgeStage.ps1 -SessionId codex-current -Json
```

沉淀经验：

```powershell
.\scripts\Add-ForgeSpecFinding.ps1 `
  -Category debugging `
  -Title "Empty state regression" `
  -Summary "列表组件必须覆盖 loading/empty/error 三态。" `
  -TaskPath .forge\tasks\05-07-sample-task
```

上游审计：

```powershell
.\scripts\Compare-ForgeExternalAdapterRef.ps1 -Name flow-kit -TargetRef "stage-change"
.\scripts\Compare-ForgeExternalAdapterRef.ps1 -Name flow-kit -BaseRef "<last-audited-sha>" -TargetRef HEAD -Json
.\scripts\Compare-ForgeExternalAdapterRef.ps1 -Name flow-kit -BaseRef "<last-audited-sha>" -TargetRef HEAD -RecordBaseline -Json
.\scripts\Test-ForgeExternalAdapter.ps1 -Name all -RepoPath .
```

未设置真实 `pinned_ref` 或 `last_audited_ref` 时，上游审计会返回 `BASELINE_REQUIRED`。这表示需要先人工确认一个已审计 upstream ref；没有 baseline 时不得把结果理解为安全可吸收。

`-RecordBaseline` 只在显式传入时写回 `adapters/external/<name>.yaml` 的 `last_audited_ref` 和 `last_audited`。它不会应用上游代码；遇到 `BREAKING_CHANGE` 会拒绝写回。

## 约束

- 不自动运行 `trellis init`
- 不自动同步 flow-kit/Trellis 上游
- 不把 Trellis AGPL 源码并入 Forge 核心
- 不默认把 audit check 变成阻断 gate
- 不写 `.claude` hook，除非用户明确要求
