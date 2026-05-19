# Forge

Forge is a Claude Code + Codex workflow control plane.

Prompt packs tell agents what they should do. Forge checks what agents are actually doing through Claude Code hooks, Codex-side installed assets, routing logs, health checks, and smoke tests.

## Status

This repository is the extracted, public-friendly source layout for a local Forge installation. It currently targets Claude Code and Codex on Windows/PowerShell first.

## What Forge Provides

- A single `forge` CLI plus Claude Code slash-command assets and Codex-installed workflow assets.
- A Forge skill that explains routing, levels, risk, and workflow rules.
- Runtime hooks for write-time guardrails and session/stop audits.
- PowerShell health and smoke checks for docs, workspace manifest, M1 compliance, live route freshness, and session state.
- Optional adapter points for external workflow tools such as Superpowers, GSD, Task Master, gstack, GitNexus, UI review, and lint tools.

## Happy Path

Most daily use should fit three commands:

```powershell
forge doctor
forge workflows
forge task new -Title "Describe the task"
forge verify
```

Use them as:

1. **doctor**: check whether Forge can safely run in this repo.
2. **workflows**: show whether BMAD, Superpowers, gstack, Compound Engineering, and GSD are active, staged, vendor-only, or missing.
3. **task new**: create a tracked task artifact before agent work.
4. **verify**: produce a fast local release-readiness verdict before PR or merge.

Forge keeps deeper adapter, baseline, and smoke details behind those commands. If a check fails, the verdict should name the failing layer and the next fix command.

`forge verify` defaults to a local `Lite` health check plus minimal smoke so it stays fast and does not depend on upstream network access. Use `forge verify -Full` before final release, `forge smoke -Quick` for extended local smoke, and `forge version -FixDrift` to refresh a source-linked install when `forge_source_drift=true`.

Forge treats workflow kits as routed capabilities, not always-on prompt bulk. BMAD is the planning source, Superpowers is the execution discipline layer, gstack is a manual gate, and Compound Engineering/GSD stay manual-approval unless explicitly enabled for learnings or state handoff.

## Repository Layout

```text
commands/              Claude Code slash-command markdown files
skills/forge/          Forge skill
docs/                  Protocol, boundary, and schema documents
scripts/               PowerShell health, smoke, routing, and reset helpers
hooks/                 Claude Code hook entrypoints; Codex consumes the shared scripts/docs/skills without Claude hooks
examples/              Example project settings and manifest snapshots
```

## Install Locally

From this repository root:

```powershell
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\scripts\Install-ForgeLocal.ps1 -RepoPath "<repo>"
```

The installer copies commands, skill, docs, scripts, and hooks into the current user's `.claude` and `.codex` Forge roots, and installs project hooks under the target project's `.claude/hooks` directory when applicable. It also writes `forge.cmd` to `%USERPROFILE%\.local\bin`, so `forge doctor`, `forge task new`, and `forge verify` work once that directory is on `PATH`.

## Health Check

After installation:

```powershell
forge doctor -RepoPath "<repo>"
```

For deeper validation:

```powershell
forge verify -RepoPath "<repo>" -Full
```

## Contributing And Releases

- Contribution guide: [CONTRIBUTING.md](./CONTRIBUTING.md)
- Architecture boundaries: [docs/architecture/boundaries.md](./docs/architecture/boundaries.md)
- Release checklist: [docs/release-checklist.md](./docs/release-checklist.md)
- License: [MIT](./LICENSE)
- Minimal example: [examples/minimal-project](./examples/minimal-project)

## Relationship To Markdown-First Workflows

Forge is not a replacement for Markdown-first workflow kits such as flow-kit. It is the runtime enforcement layer that can sit beside them:

- Markdown artifacts define intent, scope, tasks, and review expectations.
- Forge hooks and checks enforce selected rules at runtime.
- Optional adapters can call external tools when installed and fall back to built-in checks when missing.

## Current Limitations

- Windows/PowerShell paths are still first-class; cross-platform packaging is not done.
- Some hooks remain Claude Code-specific by design; shared scripts/docs/skills are installed for both Claude Code and Codex.
- Public adapter contracts are not fully formalized yet.
- Existing local installations may need session state and live route coverage refreshed before all health checks pass.
