---
name: fast-path
description: Classify and execute bounded quick fixes and small tasks with strict escalation, context, scope, gate, and review limits
compatibility: opencode-v2
---

# Fast path

Use this skill only for `/quick-fix` and `/small-task`. It reduces model context and handoffs without weakening repository safety. Fast path eligibility is a claim that must be supported by repository evidence and confirmed by the deterministic `.ai/scripts/fast-path-check.ps1` policy evaluator.

## Non-negotiable limits

A fast-path task must:

- affect at most one configured module; a quick fix must affect exactly one
- change no more than three files and no more than 120 total added plus deleted lines
- have clear, observable acceptance criteria
- have a deterministic verification command or regression test
- avoid public APIs and external contracts
- avoid new or replaced dependencies
- avoid migrations, generated code, CI/CD, infrastructure, deployments, and cloud changes
- avoid authentication, authorization, secrets, data-integrity-sensitive behavior, and concurrency-sensitive behavior
- avoid cross-module behavior
- use no more than one correction cycle

Use stricter `fastPath` thresholds from `.ai/project.json` when configured. Project settings may reduce the three-file, 120-line, and two-plus-two diagnosis budgets but may never increase them. Pass configured `maximumFiles` and `maximumLines` to the deterministic evaluator.

Size alone never makes work low risk. Any security, data integrity, concurrency, migration, infrastructure, or public-contract impact requires escalation even when the diff is one line.

## Context budget

Load `project-context` and only the affected module's configured context skills. During diagnosis, read at most two directly relevant production files and two directly relevant test files. Read additional files only when necessary to prove that the task is ineligible, then stop and escalate. Do not perform general repository exploration.

Pass the quick reviewer only:

- the original requirement
- the approved micro-plan
- the exact diff
- the configured gate results
- the fast-path classifier output

Do not send unrelated source files, full repository inventories, conversational history, or unused skills.

## Eligibility preflight

Before proposing an edit:

1. Identify the single affected module or establish that a non-code small task affects no module.
2. For a quick fix, reproduce or otherwise prove the failure and establish the root cause from bounded evidence.
3. Define observable acceptance criteria and exact deterministic verification.
4. Estimate exact files and added-plus-deleted lines.
5. Evaluate every risk flag explicitly.
6. Run `.ai/scripts/fast-path-check.ps1` with `-Phase Estimate`, configured maximums, and truthful arguments derived from the evidence.
7. If it returns `ESCALATE_STANDARD` or cannot run, stop without editing and direct the user to `/ticket`.

The policy evaluator is deterministic for its inputs; evidence is required so an agent cannot make the task eligible merely by omitting a known risk.

## Micro-plan and approval

Present one compact micro-plan containing:

- task type: quick fix or small task
- evidence and root cause, when applicable
- acceptance criteria
- exact proposed paths
- estimated line count
- verification command or regression test
- every risk flag and its evidence
- classifier verdict
- explicit non-goals

Wait for one explicit approval before editing. Approval applies only to the exact micro-plan and does not authorize scope expansion or delivery operations.

## Execution

Implement the smallest correct diff. For a quick fix, add or update the smallest valuable regression test whenever an established test location exists. A small task may change documentation, local configuration, or mechanical code only within its approved paths.

Run the exact configured quality gates for the affected module. For a module-free documentation task, run the exact deterministic validation identified in the micro-plan. Missing, skipped, denied, interrupted, or failing verification is never PASS.

After implementation:

1. Count actual changed files and actual added-plus-deleted lines for the approved scope.
2. Re-evaluate all risk flags against the real diff.
3. Run `.ai/scripts/fast-path-check.ps1` with `-Phase Actual`.
4. If actual scope is ineligible, stop with `FAST PATH INVALIDATED`; do not continue modifying code.
5. Delegate a compact independent review to `quick-reviewer`.

## Correction and completion

Only `BLOCKER` or `HIGH` findings may trigger an automatic correction. Perform at most one correction cycle, then rerun the complete gate and quick review. If the gate or review still fails, or the correction changes the design or approved scope, stop and require `/ticket`.

Report:

- classifier results for estimate and actual scope
- changed files and acceptance-criteria mapping
- exact gate outcomes
- quick-review verdict and findings
- whether the single correction allowance was used
- residual risks and recommended workflow escalation, if any

Do not automatically run `/explain`, `/pr`, branch creation, commit, push, or PR creation.
