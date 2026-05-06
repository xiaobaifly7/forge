# Forge Adapter Contract

Forge adapters are optional integrations. They strengthen Forge when available, but Forge must keep a built-in fallback path when they are missing.

## Adapter Metadata

Each adapter should document:

- `name`: Stable adapter name.
- `detect`: Command or file probe used to detect availability.
- `stage`: Workflow stage where the adapter runs.
- `mode`: `advisory`, `blocking`, `fail-open`, or `fail-close`.
- `inputs`: Files, logs, prompts, or metadata read by the adapter.
- `outputs`: Minimal JSON or text contract returned by the adapter.
- `fallback`: Built-in Forge behavior when the adapter is missing.

## Output Shape

Preferred JSON shape:

```json
{
  "ok": true,
  "adapter": "example",
  "mode": "advisory",
  "summary": "short human-readable result",
  "issues": []
}
```

Blocking adapters should return `ok=false` with actionable `issues`.

## Initial Adapter Categories

- `workflow`: Superpowers, GSD, Task Master, gstack.
- `code-intel`: GitNexus or equivalent impact analysis.
- `quality`: brooks-lint or equivalent code quality review.
- `ui`: frontend-design, ui-ux-pro-max, impeccable, or equivalent UI review/lint.
- `runtime`: Claude Code hooks, pre-write guards, stop/session audits.

## Rule

Do not make optional adapters hard dependencies. If detection fails, Forge should report the missing adapter and continue through the documented fallback path unless the current policy explicitly requires fail-close behavior.
