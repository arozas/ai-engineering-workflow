---
description: Propose and create one local feature branch after explicit approval
agent: orchestrator
---

Load `workflow-state` and `delivery-safety`. Resolve a persisted run in `PLAN_APPROVED`, validate its base SHA, and propose one valid, descriptive branch name. Show the current branch, HEAD, run ID, and clean working-tree evidence. Branch creation must occur before `BeginImplementation`.

Wait for explicit approval of that exact branch name. After approval, delegate only the approved branch creation to `delivery` through `.ai/scripts/create-branch.ps1`. Verify the resulting branch and SHA, report them, and stop. Do not stage, commit, push, or create a pull request.
