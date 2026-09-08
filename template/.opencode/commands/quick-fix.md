---
description: Diagnose and implement an eligible low-risk bug fix through the bounded fast path
agent: quick-fix
---

Handle this bug through the fast path: $ARGUMENTS

Load `workflow-state` and `fast-path` and follow them completely. Create a persisted fast-path run, use bounded evidence to reproduce or prove the failure, establish the root cause, define a regression verification, and run the deterministic eligibility estimate before proposing any edit.

If eligible, persist the compact micro-plan and a schema-valid `.ai/runtime/<run-id>/verification.json`. Include the regression command when it is not already configured; use an empty command array only when configured gates fully verify the micro-plan. Wait for explicit approval of both artifacts, then call `ApprovePlan` with `verificationPath` before implementation. After approval, implement the regression test and smallest correct fix, run and persist the frozen merged gates, revalidate actual scope from Git, and persist one independent `quick-reviewer` verdict. Use no more than one correction cycle.

If any eligibility condition fails or becomes uncertain, stop without expanding scope and return `ESCALATE STANDARD WORKFLOW` with a recommendation to run `/ticket`.
