---
description: Derive acceptance scenarios, add tests in test locations, and run deterministic gates
agent: orchestrator
---

Delegate testing of the approved behavior to `tester`.

Provide the ticket, acceptance criteria, approved plan, implementation diff, and affected module context. Require scenario coverage before test edits. The tester may edit only established test files and must return `TESTABILITY ISSUE` instead of changing production code.

Then invoke `.ai/scripts/run-quality-gates.ps1` for every affected module and report the generated PASS, FAIL, or NOT RUN status for each configured command. Never write or repair gate evidence manually.
