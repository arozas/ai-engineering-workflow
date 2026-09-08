---
description: Validate and display a persisted workflow run so work can resume safely
agent: orchestrator
---

Inspect persisted workflow run `$ARGUMENTS`.

Load `workflow-state`. Require an exact run ID and call `workflow_next` once; it validates the persisted run while returning compact status and legal next actions. Report that result without another state call. Do not edit production files or advance the run.
