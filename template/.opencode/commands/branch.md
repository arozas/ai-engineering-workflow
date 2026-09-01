---
description: Propose and create one local feature branch after explicit approval
agent: orchestrator
---

Load `delivery-safety`. Propose one valid, descriptive branch name and show the current branch, HEAD, and clean working-tree evidence.

Wait for explicit approval of that exact branch name. After approval, delegate only the approved branch creation to `delivery` through `.ai/scripts/create-branch.ps1`. Verify the resulting branch and SHA, report them, and stop. Do not stage, commit, push, or create a pull request.
