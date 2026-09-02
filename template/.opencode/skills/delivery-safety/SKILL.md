---
name: delivery-safety
description: Guard local branch creation, exact-file commits, normal feature-branch pushes, and draft PR creation with one-time human approvals
compatibility: opencode-v2 git github-cli powershell
---

## Preconditions

Before proposing a commit, push, or draft PR mutation, require:

1. An explicitly approved implementation plan.
2. Actual changes within the approved scope and diff budget.
3. Fresh deterministic quality-gate evidence with overall PASS.
4. An independent review verdict with no BLOCKER or HIGH findings.
5. A delivery check captured from the typed `workflow_delivery_check` tool.
6. No protected environment files, secrets, unrelated files, or unapproved generated artifacts.

If any precondition is missing, report `DELIVERY NOT READY` and do not mutate Git or GitHub state.

Branch creation is a preparation step, not post-implementation delivery. It requires a persisted `PLAN_APPROVED` run, the recorded base SHA, and a completely clean working tree. Create the feature branch before `BeginImplementation`; it does not require gates or review because no implementation exists yet.

## Approval contract

For each operation, show the complete proposal and ask for explicit approval. The approval is valid only while the reported HEAD, branch, and file state remain unchanged. Re-run the delivery check immediately before execution. Use permission approval once, never a saved blanket approval.

One approval authorizes exactly one of:

- Create one named local branch.
- Stage an exact file list and create one local commit.
- Push the current feature branch normally to one named remote.
- Create one draft pull request with an exact base, head, title, and body.

Never infer approval for the next stage.

## Mutation boundaries

- Use only the managed scripts under `.ai/scripts/` for branch creation, commit, push, and draft PR creation.
- Direct commit, push, PR creation, merge, rebase, reset, clean, tag mutation, release, deployment, secret mutation, and cloud mutation remain denied.
- Never operate on `main`, `master`, `develop`, `development`, `trunk`, or `release` as a delivery source branch.
- Never use force, force-with-lease, tag push, ref deletion, `--amend`, or author overrides.
- Never create a ready-for-review PR, merge, enable auto-merge, request reviewers, assign people, apply labels, or add comments without a separate future policy.

## Required reports

Before execution, report exact inputs and expected impact. After execution, report the resulting branch, commit SHA, remote ref, or draft PR URL. On failure, report partial local or remote state without attempting a more permissive fallback.
