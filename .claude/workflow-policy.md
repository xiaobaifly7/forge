# Forge Workflow Policy

Forge is the authoritative governance layer for this repository.

- External systems such as flow-kit and Trellis remain optional read-only adapters.
- Do not run external init commands or let external hooks replace Forge hooks.
- Keep task/spec/workspace data under Forge-owned contracts.
- Treat adapter checks as advisory unless a policy explicitly marks them fail-close.
- BMAD is the L3/L4/full planning source, with repo-local `_bmad/` preferred and global staging as fallback.
- Superpowers is the execution discipline layer for build/fix/debug/verification.
- gstack is a manual gate for review, QA, ship, canary, and benchmark checks.
- Compound Engineering and GSD are manual-approval workflows for reusable learnings, state handoff, risks, and next actions; they are not default execution layers.
