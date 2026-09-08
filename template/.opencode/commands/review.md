---
description: Run an independent read-only review against the ticket and approved plan
agent: orchestrator
---

Load `workflow-state`, resolve the exact run, call `workflow_next` once, require `GATES_PASSED`, and construct the exact diff packet before delegating one independent review to `reviewer`.

Provide only the persisted requirement, approved plan, exact diff packet, affected module context, and persisted gate evidence. Require the structured output defined by `code-review`. The reviewer cannot run shell commands or edit files.

Require the reviewer to call its exclusive `workflow_standard_review` tool. The tool writes `.ai/runtime/<run-id>/review.json`, validates and binds it to the exact gates/worktree, and atomically calls `RecordReview`. The orchestrator must not write review evidence or supply the verdict. If persisted state is `REVIEW_FAILED`, summarize findings and ask before calling `BeginCorrection` unless the user already authorized the full workflow.
