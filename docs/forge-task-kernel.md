# Forge Task Kernel

## 定位

Forge Task Kernel 是 Forge-native 的任务内核。它吸收 Trellis 的 task/spec/workspace 数据模型，但不依赖 Trellis runtime、CLI、hooks 或多平台生成器。

Forge 仍是最高治理真源。

## 目录结构

```text
.forge/
  tasks/
    <date>-<task>/
      task.json
      prd.md
      info.md
      implement.jsonl
      check.jsonl
      research/
  spec/
    frontend/
    backend/
    security/
    testing/
    review/
    debugging/
    conventions/
    guides/
  workspace/
  .runtime/
    sessions/
      <thread-id>.json
```

## 文件职责

| 文件 | 作用 |
| --- | --- |
| `task.json` | 任务状态、阶段、优先级、owner、分支、PR、父子关系 |
| `prd.md` | 目标、范围、验收标准、非目标 |
| `info.md` | 技术设计、权衡、风险 |
| `implement.jsonl` | 实现前必须读取的 spec/research |
| `check.jsonl` | 验证前必须读取的 spec/research |
| `research/` | 只读调研产物 |

`implement.jsonl` 和 `check.jsonl` 只登记 spec/research 文件，不登记代码路径。代码由执行阶段按需读取。

## 阶段

Task Kernel 使用 Forge 阶段名：

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

## 验证命令

```powershell
.\scripts\Test-ForgeTaskKernel.ps1 -RepoPath .\examples\task-kernel-project
.\scripts\Test-ForgeTaskKernel.ps1 -RepoPath .\examples\task-kernel-project -Json
```

脚本只读，不修改项目。

## 创建任务

```powershell
.\scripts\New-ForgeTask.ps1 `
  -RepoPath . `
  -Name "sample-task" `
  -Title "Sample Task" `
  -Goal "Describe the expected outcome." `
  -ImplementContext ".forge\spec\conventions\index.md" `
  -CheckContext ".forge\spec\testing\index.md"
```

`New-ForgeTask.ps1` 会创建：

```text
.forge/tasks/<MM-dd-name>/
  task.json
  prd.md
  info.md
  implement.jsonl
  check.jsonl
  research/notes.md
```

上下文路径必须位于 `.forge\` 下。脚本默认不覆盖已有任务；需要覆盖时显式使用 `-Force`。

## 维护上下文

```powershell
.\scripts\Update-ForgeTaskContext.ps1 `
  -RepoPath . `
  -TaskPath .forge\tasks\<task> `
  -Target implement `
  -File .forge\spec\conventions\index.md `
  -Reason "实现前读取项目约定"
```

`-Target` 支持 `implement`、`check`、`both`、`list`。
