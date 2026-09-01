---
description: Run an independent read-only review against the ticket and approved plan
agent: orchestrator
---

Delegate an independent review of the current changes to `reviewer`.

Provide the original ticket or requirement, the explicitly approved plan, the current diff, affected module context, and the latest deterministic quality-gate evidence. Require the structured output defined by `code-review`.

Do not allow the reviewer to edit. If the verdict is FAIL, summarize the findings and ask before starting a correction cycle unless the user already authorized the full workflow.
