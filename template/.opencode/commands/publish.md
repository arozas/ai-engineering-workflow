---
description: Push the current approved feature branch normally after explicit approval
agent: orchestrator
---

Load `workflow-state` and `delivery-safety`. Require a validated persisted run in `COMMITTED`, a completely clean working tree, a non-protected feature branch, and the exact remote URL.

Show the remote, remote URL, branch, HEAD SHA, and ref that will be created or advanced. Wait for explicit approval of that exact push. Then delegate only `.ai/scripts/publish-approved.ps1` to `delivery`.

Use a normal push only. Never force, use force-with-lease, push tags, delete refs, or push a protected/shared branch. Write the remote, ref, SHA, and result to `.ai/runtime/publish.json`, call `RecordPublish`, report the persisted result, then stop without creating a pull request.
