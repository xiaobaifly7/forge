# Forge Architecture Boundaries

Forge is a local engineering governance layer.

It connects task artifacts, routing rules, hooks, adapter checks, health checks, smoke tests, and release gates into one auditable workflow. It should not become a general agent runtime or a replacement for every tool around it.

## Responsibility

Forge owns:

- workflow routing and risk level selection;
- repo-local task, spec, and finding artifacts;
- runtime guardrails through Claude Code hooks;
- health, smoke, and release-readiness checks;
- adapter contracts for external methodology or intelligence tools;
- evidence collection before PR, release, or merge.

Forge does not own:

- model execution;
- long-running agent orchestration;
- source-code intelligence indexing;
- product requirements methodology;
- full CI/CD deployment;
- global user shell or editor configuration.

## Boundary Matrix

| System | Forge relationship | Boundary |
|---|---|---|
| Codex | Codex can operate on Forge repos and follow Forge gates. | Forge does not replace Codex sessions, memory, tools, or approval policy. |
| Claude Code | Forge installs Claude commands, skills, and hooks. | Forge should keep repo-local `.claude` contract files inert unless explicitly installed. |
| OMX | OMX can provide runtime/team workflow above Forge. | Forge is not the durable runtime; it exposes checks and artifacts OMX can call. |
| GitNexus | Forge consumes impact and detect-change evidence. | GitNexus owns graph/index intelligence; Forge only gates and records its result. |
| flow-kit | Forge can adapt Markdown-first workflow artifacts. | flow-kit remains a methodology/source of intent; Forge enforces selected runtime checks. |
| Trellis | Forge can adapt task/spec workspace concepts. | Trellis remains an external task system; Forge should not hard-fork its model. |
| CI | CI runs Forge readiness commands. | Forge does not replace CI providers or deployment policy. |

## Default Integration Rule

Prefer adapter and evidence over ownership.

```text
External tool produces intent or intelligence
  -> Forge validates contract
  -> Forge records evidence
  -> Forge gates ship/release
```

If a feature requires Forge to duplicate another tool's core responsibility, keep it out of Forge unless there is a clear repo-local enforcement need.

## Growth Guardrails

- Add a public command only when it shortens the happy path.
- Add an adapter only when it can fail closed with a clear warning.
- Add a gate only when it has a direct fix hint.
- Keep advanced checks behind `health`, `smoke`, or `readiness`.
- Do not add a new workflow DSL unless existing artifacts cannot express the requirement.

## Product Sentence

Forge is the local control plane that turns agent workflow intent into checked, auditable engineering gates.
