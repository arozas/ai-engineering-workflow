---
description: Assess whether the approved change is ready for branch, commit, push, or draft PR delivery
agent: orchestrator
---

Load `workflow-state` and `delivery-safety`. Require a validated persisted run in `READY_FOR_DELIVERY`, then delegate a read-only delivery inspection to `delivery` using `workflow_delivery_check`.

Combine Git state with the persisted approved plan, artifact hashes, deterministic gate evidence, independent review verdict, recorded worktree fingerprint, diff budget, and unresolved findings. Report `READY FOR DELIVERY` only when every required precondition is present and current; otherwise report `DELIVERY NOT READY` with exact blockers.

Do not create a branch, stage files, commit, push, or create a pull request.
