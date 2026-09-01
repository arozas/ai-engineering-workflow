---
description: Assess whether the approved change is ready for branch, commit, push, or draft PR delivery
agent: orchestrator
---

Load `delivery-safety` and delegate a read-only delivery inspection to `delivery` using `.ai/scripts/delivery-check.ps1`.

Combine the Git state with the latest approved plan, deterministic quality-gate evidence, independent review verdict, diff budget, and unresolved findings. Report `READY FOR DELIVERY` only when every required precondition is present and current; otherwise report `DELIVERY NOT READY` with exact blockers.

Do not create a branch, stage files, commit, push, or create a pull request.
