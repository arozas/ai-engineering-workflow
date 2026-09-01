---
description: Validate and display a persisted workflow run so work can resume safely
agent: orchestrator
---

Inspect persisted workflow run `$ARGUMENTS`.

Load `workflow-state`. Require an exact run ID, execute `.ai/scripts/workflow-state.ps1 -Action Validate -RunId <id>`, then execute `Show`. Report status, workflow path, source run when present, base/current SHA, correction or diagnostic-iteration use, artifact hashes, and the next legal action. Do not edit production files or advance the run.
