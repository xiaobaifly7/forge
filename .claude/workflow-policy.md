# Forge Workflow Policy

Forge is the authoritative governance layer for this repository.

- External systems such as flow-kit and Trellis remain optional read-only adapters.
- Do not run external init commands or let external hooks replace Forge hooks.
- Keep task/spec/workspace data under Forge-owned contracts.
- Treat adapter checks as advisory unless a policy explicitly marks them fail-close.
