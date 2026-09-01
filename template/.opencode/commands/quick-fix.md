---
description: Diagnose and implement an eligible low-risk bug fix through the bounded fast path
agent: quick-fix
---

Handle this bug through the fast path: $ARGUMENTS

Load `fast-path` and follow it completely. Use bounded evidence to reproduce or prove the failure, establish the root cause, define a regression verification, and run the deterministic eligibility preflight before proposing any edit.

If eligible, present one compact micro-plan and wait for explicit approval. After approval, implement the regression test and smallest correct fix, run all required gates, revalidate actual scope, and obtain one independent `quick-reviewer` verdict. Use no more than one correction cycle.

If any eligibility condition fails or becomes uncertain, stop without expanding scope and return `ESCALATE STANDARD WORKFLOW` with a recommendation to run `/ticket`.
