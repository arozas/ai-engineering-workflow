---
description: Implement the latest explicitly approved plan through the developer agent
agent: orchestrator
---

Implement only an exact plan recorded as `PLAN_APPROVED` in persisted workflow state.

Load `workflow-state`. Resolve exactly one approved run or require the user to name its run ID. If `workflow_next` is present in the initial callable-tool catalog, call it exactly once. If it is absent or explicitly unknown, unavailable, removed, or not callable, run exactly `pwsh -NoProfile -File .ai/scripts/workflow-state.ps1 -Action Show -RunId <run-id> -Transport deterministic-script` once. Do not search, retry, substitute `Validate`, or fall back after a validation, policy, state, or execution error. Require `PLAN_APPROVED`, then call `BeginImplementation`; if no persisted approved plan exists, stop and ask the user to run `/ticket` or approve its proposal. Delegate the persisted requirement, hashed plan, hashed verification manifest, constraints, expected diff budget, selected module context, and frozen merged quality commands to `developer`.

After implementation, run `workflow_gate` once with the approved run ID. The tool loads the frozen affected-module and command matrix from state; the agent must not supply module IDs. Record its unedited `.ai/runtime/<run-id>/gates.json` through `workflow_state` action `RecordGates`. A repeated unchanged gate returns the current validated evidence and must not start another execution. A prose summary or manually authored JSON is not gate evidence. Do not silently expand scope and do not begin reviewer/developer correction loops unless the user requested the full workflow.
