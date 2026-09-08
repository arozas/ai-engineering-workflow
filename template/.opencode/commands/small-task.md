---
description: Execute an eligible low-risk documentation, local configuration, or mechanical task through the bounded fast path
agent: quick-fix
---

Handle this small task through the fast path: $ARGUMENTS

Load `workflow-state` and `fast-path` and follow them completely. Create a persisted fast-path run. Establish clear acceptance criteria, exact paths, deterministic verification, scope estimates, and every semantic risk flag before proposing any edit. A small task may affect zero or one configured module but must remain within the same three-file and 120-line limits.

If eligible, persist the compact micro-plan and a schema-valid `.ai/runtime/<run-id>/verification.json`. Include any exact verification absent from configured gates; use an empty command array only when configured gates are sufficient. Wait for explicit approval of both artifacts, then call `ApprovePlan` with `verificationPath` before implementation. After approval, implement the smallest change, run and persist the frozen merged verification and gates, revalidate actual scope from Git, and persist a compact independent `quick-reviewer` verdict. Use no more than one correction cycle.

If the task affects production behavior beyond a mechanical local change, crosses modules, or enters any prohibited risk category, stop and return `ESCALATE STANDARD WORKFLOW` with a recommendation to run `/ticket`.
