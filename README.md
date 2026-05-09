# Forge

Forge is a Claude Code workflow control plane.

Prompt packs tell agents what they should do. Forge checks what agents are actually doing through Claude Code hooks, routing logs, health checks, and smoke tests.

## Status

This repository is the extracted, public-friendly source layout for a local Forge installation. It currently targets Claude Code on Windows/PowerShell first.

## What Forge Provides

- A single `/forge` router command for Claude Code.
- A Forge skill that explains routing, levels, risk, and workflow rules.
- Runtime hooks for write-time guardrails and session/stop audits.
- PowerShell health and smoke checks for docs, workspace manifest, M1 compliance, live route freshness, and session state.
- Optional adapter points for external workflow tools such as Superpowers, GSD, Task Master, gstack, GitNexus, UI review, and lint tools.

## Happy Path

Most daily use should fit three commands:

```powershell
forge doctor
forge task new -Title "Describe the task"
forge verify
```

Use them as:

1. **doctor**: check whether Forge can safely run in this repo.
2. **task new**: create a tracked task artifact before agent work.
3. **verify**: produce a release-readiness verdict before PR or merge.

Forge keeps deeper adapter, baseline, and smoke details behind those commands. If a check fails, the verdict should name the failing layer and the next fix command.

## Repository Layout

```text
commands/              Claude Code slash-command markdown files
skills/forge/          Forge skill
docs/                  Protocol, boundary, and schema documents
scripts/               PowerShell health, smoke, routing, and reset helpers
hooks/                 Claude Code hook entrypoints
examples/              Example project settings and manifest snapshots
```

## Install Locally

From this repository root:

```powershell
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\scripts\Install-ForgeLocal.ps1 -RepoPath "<repo>"
```

The installer copies commands, skill, docs, scripts, and hooks into the current user's Claude Code configuration and the target project's `.claude/hooks` directory. It also writes `forge.cmd` to `%USERPROFILE%\.local\bin`, so `forge doctor`, `forge task new`, and `forge verify` work once that directory is on `PATH`.

## Health Check

After installation:

```powershell
forge doctor -RepoPath "<repo>"
```

For deeper validation:

```powershell
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.claude\scripts\Invoke-ForgeHealth.ps1" -Mode Offline -RepoPath "<repo>"
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
- Some scripts still contain local Claude Code assumptions.
- Public adapter contracts are not fully formalized yet.
- Existing local installations may need session state and live route coverage refreshed before all health checks pass.
