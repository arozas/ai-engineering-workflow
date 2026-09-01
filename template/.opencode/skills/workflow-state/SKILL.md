---
name: workflow-state
description: Persist approved plans, gate evidence, review evidence, hashes, and workflow transitions so work can resume safely across sessions
compatibility: opencode-v2
---

# Persisted workflow state

Every `/ticket`, `/diagnose`, `/quick-fix`, and `/small-task` execution must use one local run under `.ai/runs/<run-id>/`. Run artifacts are ignored by Git and are not delivery content.

## Run selection

Use a lowercase run ID of 3-64 characters, for example `ticket-18427` or `quick-order-null-guard`. If a command continues work without an explicit run ID, inspect `.ai/runs/*/state.json` and continue only when exactly one compatible nonterminal run exists. Otherwise ask the user to select a run; never guess between multiple plans.

## Required transitions

Use only `.ai/scripts/workflow-state.ps1`:

1. Write the normalized request to `.ai/runtime/requirement.md`, then `Start` with `standard` or `fast-path`.
2. Write the complete proposed plan to `.ai/runtime/plan.md`.
3. Only after explicit user approval, call `ApprovePlan` with that exact file. The script copies and hashes it.
4. Call `BeginImplementation` before production or test edits.
5. Write factual gate evidence to `.ai/runtime/gates.json`, then call `RecordGates` with `PASS` or `FAIL`.
6. Pass the exact persisted requirement, plan, diff packet, and gates to the read-only reviewer. Write its returned result to `.ai/runtime/review.md`, then call `RecordReview`.
7. Use `BeginCorrection` before an approved correction. The script enforces the workflow-specific limit.
8. After an approved commit, write its evidence to `.ai/runtime/commit.json` and call `RecordCommit`; the script proves that the commit is the exact gate-reviewed diff.
9. Record an approved push and draft PR with `RecordPublish` and `RecordPullRequest` respectively.
10. Use `Escalate` when scope, evidence, or correction limits invalidate the current route.

## Diagnostic transitions

Unknown production failures use a separate `diagnostic` path:

1. Persist the sanitized incident report and call `Start`; the initial status is `DIAGNOSING`.
2. Validate `.ai/runtime/diagnosis.json`, then call `RecordDiagnosis` with `PASS`, `FAIL`, or `ESCALATE`.
3. `PASS` requires a validated `ROOT_CAUSE_CONFIRMED` artifact and enters `ROOT_CAUSE_CONFIRMED`.
4. `FAIL` requires a validated `BLOCKED` artifact and enters `DIAGNOSIS_BLOCKED`.
5. After new evidence and explicit human approval, call `BeginDiagnosticIteration` before another analysis. Each recorded diagnosis consumes one of the persisted one-to-three iterations.
6. `ESCALATE` requires a validated `ESCALATED` artifact and enters `ESCALATED`.
7. Only `/ticket diagnosis:<run-id>` may start a standard implementation run from `ROOT_CAUSE_CONFIRMED`; `Start -SourceRunId` validates and records that provenance.

Diagnostic transitions never authorize edits, implementation, production access, mitigations, or delivery.

Run `Validate` before resuming or delivery. Artifact hashes, HEAD, the post-gate worktree fingerprint, and legal transitions are deterministic boundaries. Never edit `state.json` or canonical run artifacts directly. A state transition records evidence; it never replaces the user's required approval.

## Review isolation

Reviewers have no shell and no edit access. The orchestrator or quick-fix agent must construct the exact diff packet before delegation. Do not ask a reviewer to rediscover Git state.
