---
description: Assess whether the approved change is ready for commit, push, or draft PR delivery
agent: orchestrator
---

Load `workflow-state` and `delivery-safety`. If `workflow_next` is present in the initial callable-tool catalog, call it exactly once. If it is absent or explicitly unknown, unavailable, removed, or not callable, run exactly `pwsh -NoProfile -File .ai/scripts/workflow-state.ps1 -Action Show -RunId <run-id> -Transport deterministic-script` once. Do not search, retry, substitute `Validate`, or fall back after a validation, policy, state, or execution error. Require `READY_FOR_DELIVERY`, then delegate one read-only delivery inspection to `delivery` using `workflow_delivery_check`.

Combine Git state with the persisted approved plan, artifact hashes, deterministic gate evidence, independent review verdict, recorded worktree fingerprint, diff budget, and unresolved findings. Report `READY FOR DELIVERY` only when every required precondition is present and current; otherwise report `DELIVERY NOT READY` with exact blockers.

Do not create a branch, stage files, commit, push, or create a pull request.
