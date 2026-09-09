---
description: Derive acceptance scenarios, add tests in test locations, and run deterministic gates
agent: orchestrator
---

Require an exact run ID. If `workflow_next` is present in the initial callable-tool catalog, call it exactly once. If it is absent or explicitly unknown, unavailable, removed, or not callable, run exactly `pwsh -NoProfile -File .ai/scripts/workflow-state.ps1 -Action Show -RunId <run-id> -Transport deterministic-script` once. Do not search, retry, substitute `Validate`, or fall back after a validation, policy, state, or execution error. Continue only when testing is a legal action for the current persisted state. Delegate testing of the approved behavior to `tester`.

Provide the ticket, acceptance criteria, approved plan, implementation diff, and affected module context. Require scenario coverage before test edits. The tester may edit only established test files and must return `TESTABILITY ISSUE` instead of changing production code.

Then invoke `workflow_gate` once with the approved run ID and report the generated PASS, FAIL, or NOT RUN status for every command in the frozen affected-module matrix. Reuse its current evidence when the tool reports an unchanged cached gate. Never choose a smaller module set or write or repair gate evidence manually.
