---
description: Create one explicitly approved Conventional Commit from an exact staged file list
agent: orchestrator
---

Load `workflow-state`, `delivery-safety`, and `conventional-commit`. Require a validated persisted run in `READY_FOR_DELIVERY`, fresh overall PASS gate evidence, a review with no BLOCKER or HIGH findings, and an unchanged worktree fingerprint within scope.

Propose:

- exact file paths to stage
- Conventional Commit subject and optional body
- current feature branch and HEAD
- acceptance criteria represented by the commit

The commit message must contain no AI-agent authorship, co-authorship, generation, or tool attribution. Wait for explicit approval of the exact file list and message. Then delegate one commit operation to `delivery`: stage only those file paths, inspect the cached diff, and use `.ai/scripts/commit-approved.ps1 -RunId <run-id> -Subject <subject>` with the optional approved body.

The guarded script writes `.ai/runtime/<run-id>/commit.json`, independently validates the actual Git commit message and changed paths, and persists `RecordCommit`. Report the persisted SHA, parent, exact paths, and final message, then stop. Do not push or create a pull request.
