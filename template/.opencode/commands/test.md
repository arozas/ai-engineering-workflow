---
description: Derive acceptance scenarios, add tests in test locations, and run deterministic gates
agent: orchestrator
---

Require an exact run ID, call `workflow_next` once, and continue only when testing is a legal action for the current persisted state. Delegate testing of the approved behavior to `tester`.

Provide the ticket, acceptance criteria, approved plan, implementation diff, and affected module context. Require scenario coverage before test edits. The tester may edit only established test files and must return `TESTABILITY ISSUE` instead of changing production code.

Then invoke `workflow_gate` once with the approved run ID and report the generated PASS, FAIL, or NOT RUN status for every command in the frozen affected-module matrix. Reuse its current evidence when the tool reports an unchanged cached gate. Never choose a smaller module set or write or repair gate evidence manually.
