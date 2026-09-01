---
description: Create one explicitly approved Conventional Commit from an exact staged file list
agent: orchestrator
---

Load `delivery-safety` and `conventional-commit`. Require the latest approved plan, fresh overall PASS gate evidence, a review with no BLOCKER or HIGH findings, and an unchanged diff within scope.

Propose:

- exact file paths to stage
- Conventional Commit subject and optional body
- current feature branch and HEAD
- acceptance criteria represented by the commit

The commit message must contain no AI-agent authorship, co-authorship, generation, or tool attribution. Wait for explicit approval of the exact file list and message. Then delegate one commit operation to `delivery`: stage only those file paths, inspect the cached diff, and use `.ai/scripts/commit-approved.ps1`.

Report the resulting commit SHA and final message, then stop. Do not push or create a pull request.
