---
description: Run an independent read-only review against the ticket and approved plan
agent: orchestrator
---

Load `workflow-state`, resolve and validate the persisted run in `GATES_PASSED`, and construct the exact diff packet before delegating an independent review to `reviewer`.

Provide only the persisted requirement, approved plan, exact diff packet, affected module context, and persisted gate evidence. Require the structured output defined by `code-review`. The reviewer cannot run shell commands or edit files.

Write the returned result to `.ai/runtime/<run-id>/review.md` and call `RecordReview`. If the verdict is FAIL, summarize findings and ask before calling `BeginCorrection` unless the user already authorized the full workflow.
