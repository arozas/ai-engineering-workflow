---
description: Optionally enrich a valid deterministic bootstrap proposal from a bounded representative-file packet
agent: orchestrator
---

Enhance the current bootstrap draft without open-ended exploration.

1. Run `workflow_bootstrap_prepare` once without force, using its exact deterministic script fallback only under the transport policy. Continue only for `BOOTSTRAP_PROPOSAL_READY` or `BOOTSTRAP_PROPOSAL_CURRENT`.
2. Delegate exactly once to `bootstrap-enricher`. Supply only `.ai/bootstrap-proposal/evidence-packet.json` and the proposal root.
3. After it returns, run `workflow_bootstrap_apply` once with `dryRun: true`, using `pwsh -NoProfile -File .ai/scripts/apply-bootstrap-proposal.ps1 -DryRun` only when the typed tool is absent or explicitly unavailable.
4. Report the changed proposal files, evidence used, validation verdict, and `/ai-bootstrap-apply` as the next step; then stop.

Do not inspect source files yourself, repeat a delegation, apply final context, or continue after one correction failure. This optional route is intended for a stronger model; the deterministic `/ai-bootstrap` proposal remains sufficient when enrichment is skipped.
