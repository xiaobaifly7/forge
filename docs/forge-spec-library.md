# Forge Spec Library

## 定位

Forge Spec Library 是项目内可审查、可版本化的规范库。它用于沉淀长期约定、重复 bug 的预防规则、review 规则和调试经验。

它不是聊天记忆的替代品，而是把高价值经验提升为项目契约。

## 推荐分类

```text
.forge/spec/
  frontend/
  backend/
  security/
  testing/
  review/
  debugging/
  conventions/
  guides/
```

## 写入规则

适合提升为 spec：

- 同类 bug 重复出现
- review 多次重复同一意见
- 架构决策会影响后续任务
- 测试策略需要固定
- 安全边界必须长期保留

不适合提升为 spec：

- 一次性过程日志
- 临时命令输出
- 与项目无关的个人偏好
- 未验证的猜测

## 与 Task Kernel 的关系

Task 的 `implement.jsonl` 和 `check.jsonl` 应引用相关 spec：

```jsonl
{"file":".forge/spec/testing/index.md","reason":"验证前读取测试要求。"}
{"file":".forge/spec/review/index.md","reason":"review 前读取审查规则。"}
```

这样 agent 可以按任务加载必要规范，而不是把所有规则塞进系统提示词。

## 追加经验

```powershell
.\scripts\Add-ForgeSpecFinding.ps1 `
  -RepoPath . `
  -Category debugging `
  -Title "Empty state regression" `
  -Summary "列表组件必须覆盖 loading/empty/error 三态。" `
  -TaskPath .forge\tasks\<task>
```

新增 finding 会写入对应分类目录，并追加到分类 `index.md`。
