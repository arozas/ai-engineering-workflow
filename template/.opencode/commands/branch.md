---
description: Propose and create one local feature branch after explicit approval
agent: orchestrator
---

Load `workflow-state` and `delivery-safety`. Resolve a persisted run in `PLAN_APPROVED`, validate its base SHA, then call `workflow_delivery_check` once for current branch, HEAD, remote, and clean-working-tree evidence. Do not attempt equivalent raw Git shell commands before or after this typed check. Propose one valid, descriptive branch name. Branch creation must occur before `BeginImplementation`.

Wait for explicit approval of that exact branch name. After approval, delegate only the approved branch creation to `delivery` through `.ai/scripts/create-branch.ps1 -RunId <run-id> -Name <approved-name>`. The guarded script must write `.ai/runtime/<run-id>/branch.json` and persist `RecordBranch`. Verify the resulting branch, SHA, and canonical branch artifact, report them, and stop. Do not stage, commit, push, or create a pull request.
