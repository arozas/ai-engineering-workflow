---
description: Validate and display a persisted workflow run so work can resume safely
agent: orchestrator
---

Inspect persisted workflow run `$ARGUMENTS`.

Load `workflow-state`. Require an exact run ID. If `workflow_next` is present in the initial callable-tool catalog, call it exactly once. If it is absent or explicitly unknown, unavailable, removed, or not callable, run exactly `pwsh -NoProfile -File .ai/scripts/workflow-state.ps1 -Action Show -RunId <run-id> -Transport deterministic-script` once. Do not search, retry, substitute `Validate`, or fall back after a validation, policy, state, or execution error. Report that result without another state call. Do not edit production files or advance the run.
