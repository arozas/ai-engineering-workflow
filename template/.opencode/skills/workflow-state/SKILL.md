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

Use the deterministic tool transport defined in `AGENTS.md`. Prefer the visible typed `workflow_state` tool; when it is absent or explicitly unavailable, invoke `.ai/scripts/workflow-state.ps1` exactly once with `pwsh -NoProfile -File` and `-Transport deterministic-script`. For `workflow_next`, the only fallback is exactly `pwsh -NoProfile -File .ai/scripts/workflow-state.ps1 -Action Show -RunId <run-id> -Transport deterministic-script`, once. Never substitute `Validate` for `workflow_next`. Do not search for a missing tool, use `powershell`, use `pwsh -Command`, compose shell expressions, or retry. Never fall back after a validation, policy, state, or execution failure.

1. Choose a unique run ID, write the normalized request to `.ai/runtime/<run-id>/requirement.md`, then `Start` with `standard` or `fast-path`.
2. Write the complete proposed plan to `.ai/runtime/<run-id>/plan.md` and a schema-valid `.ai/runtime/<run-id>/verification.json`. The manifest lists mandatory run-specific commands not already configured for the affected modules and is empty when none are needed.
3. Only after explicit user approval of both artifacts, call `ApprovePlan` with the exact plan, verification path, and every affected module ID. The script copies and hashes both artifacts and freezes the exact merged project plus run-specific quality-command matrix.
4. If an approved feature branch is needed, have `delivery` invoke `create-branch.ps1` with the run ID and exact approved name. The script persists `branch.json` through `RecordBranch` while state remains `PLAN_APPROVED`. Then call `BeginImplementation` before production or test edits.
5. Run `workflow_gate` with the run ID. It writes factual gate evidence to `.ai/runtime/<run-id>/gates.json`; then call `RecordGates` with `PASS` or `FAIL`.
6. Pass the exact persisted requirement, plan, diff packet, and gates to the independent reviewer. The reviewer must call its exclusive typed review tool or, only when unavailable, stage `.ai/runtime/<run-id>/review-input.json` and invoke the exact `record-review.ps1` fallback with its own role and `-Transport deterministic-script`. That script writes `.ai/runtime/<run-id>/review.json` and atomically records the derived verdict. Orchestrators and implementation agents must not write or record review evidence.
7. Use `BeginCorrection` before an approved correction. The script enforces the workflow-specific limit.
8. After exact paths and a Conventional Commit message are approved, have `delivery` invoke `commit-approved.ps1` with the run ID. The script writes `commit.json` and records it; state independently reads and validates the actual Git message, changed files, parent, branch, and gate-reviewed diff.
9. Record an approved push and draft PR with `RecordPublish` and `RecordPullRequest` respectively.
10. Use `Escalate` when scope, evidence, or correction limits invalidate the current route.

## Diagnostic transitions

Unknown production failures use a separate `diagnostic` path:

1. Persist the sanitized incident report and call `Start`; the initial status is `DIAGNOSING`.
2. Validate `.ai/runtime/<run-id>/diagnosis.json`, then call `RecordDiagnosis` with `PASS`, `FAIL`, or `ESCALATE`.
3. `PASS` requires a validated `ROOT_CAUSE_CONFIRMED` artifact and enters `ROOT_CAUSE_CONFIRMED`.
4. `FAIL` requires a validated `BLOCKED` artifact and enters `DIAGNOSIS_BLOCKED`.
5. After new evidence and explicit human approval, call `BeginDiagnosticIteration` before another analysis. Each recorded diagnosis consumes one of the persisted one-to-three iterations.
6. `ESCALATE` requires a validated `ESCALATED` artifact and enters `ESCALATED`.
7. Only `/ticket diagnosis:<run-id>` may start a standard implementation run from `ROOT_CAUSE_CONFIRMED`; `Start -SourceRunId` validates and records that provenance.

Diagnostic transitions never authorize edits, implementation, production access, mitigations, or delivery.

Run `Validate` before resuming or delivery. Artifact hashes, the approved module/command matrix, HEAD, the post-gate worktree fingerprint, and legal transitions are deterministic boundaries. Never edit `state.json` or canonical run artifacts directly. A state transition records evidence; it never replaces the user's required approval. Report the persisted `lastTransitionTransport` after every transition.

## Review isolation

Reviewers have no shell and no edit access. The orchestrator or quick-fix agent must construct the exact diff packet before delegation. Do not ask a reviewer to rediscover Git state.
