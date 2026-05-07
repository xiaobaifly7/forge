# Forge Repo Adapter Contract

This repo-local contract records the boundary between Forge core and optional external adapters.

- Forge remains the authoritative governance layer.
- flow-kit is absorbed only as stage methodology.
- Trellis is absorbed only as task/spec/workspace data-model guidance.
- External adapters are read-only translation layers by default.
- No external `init`, global hook takeover, telemetry, or AGPL source copy is allowed without explicit approval.

The live, general adapter contract is documented in `docs/adapter-contract.md`.
