# Forge Stage Engine

## 定位

Forge Stage Engine 把外部方法论阶段和 Forge Task Kernel 阶段统一成 Forge 路由建议。它不执行任务，不写 hook，不改变现有 `.claude` session state。

## 阶段

```text
change
requirement
design
ui-design
task
dev
test
review
integration
```

## 路由映射

| Stage | Forge route |
| --- | --- |
| `change` | `scope` |
| `requirement` | `requirement` |
| `design` | `design` |
| `ui-design` | `ui-design` |
| `task` | `planning` |
| `dev` | `implementation` |
| `test` | `verification` |
| `review` | `review` |
| `integration` | `integration` |

## 来源优先级

1. 显式 `-Stage`
2. Forge Task Kernel active session
3. Forge Task Kernel task metadata
4. flow-kit stage alias

## 检测命令

```powershell
.\scripts\Resolve-ForgeStage.ps1 -Stage dev -Json
.\scripts\Set-ForgeActiveTask.ps1 -RepoPath .\examples\task-kernel-project -SessionId example -TaskPath .forge\tasks\05-07-example-task -Stage task
.\scripts\Resolve-ForgeStage.ps1 -RepoPath .\examples\task-kernel-project -SessionId example -Json
```

脚本只在显式调用 `Set-ForgeActiveTask.ps1` 时写入 `.forge/.runtime/sessions/<session-id>.json`。
