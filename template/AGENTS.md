# AI Engineering Workflow

This repository uses a stack-agnostic, human-gated engineering workflow. Treat `.ai/project.json` as the machine-readable source of project modules and quality commands after bootstrap. Treat `.ai/project-rules.md` as the highest-authority project guidance.

At the start of bootstrap, ticket analysis, implementation, review, or testing, load `project-context`. It must read `.ai/project-rules.md` and the applicable module configuration before work continues. If `.ai/project.json` does not exist yet, use `/ai-bootstrap` and do not guess the project configuration. Use `/ai-refresh` when the persisted repository profile reports structural drift; never regenerate project skills inside a delivery task.

## Fast path

Use `/quick-fix` for a bounded bug fix and `/small-task` for bounded documentation, local configuration, or mechanical work. Both commands must load `fast-path`, run `.ai/scripts/fast-path-check.ps1`, present one compact micro-plan, and wait for explicit approval before editing.

Fast-path work is limited to one module, three files, 120 added-plus-deleted lines, deterministic verification, no prohibited risk category, and at most one correction cycle. Quick-fix diagnosis may read at most two relevant production files and two relevant test files. Any unclear root cause, scope expansion, public contract, dependency, migration, generated code, authentication, authorization, secrets, data integrity, concurrency, CI/CD, infrastructure, deployment, cloud, or cross-module impact requires `/ticket` and the standard workflow.

The `quick-fix` agent may delegate only to the read-only `quick-reviewer`. A fast-path review receives only the requirement, approved micro-plan, exact diff, gate evidence, and classifier output. Fast-path completion never authorizes branch, commit, push, or pull-request operations.

## Instruction precedence

When instructions conflict, apply them in this order:

1. Explicit user instruction for the current task
2. `.ai/project-rules.md` and module-local `AGENTS.md`
3. Selected architecture skills
4. Selected stack skills
5. Core rules in this file and workflow skills

Do not guess missing project conventions. Report uncertainty and ask for approval when it can materially change the implementation.

## Required workflow

1. Understand the ticket or request before changing code.
2. Load `project-context` and only the stack and architecture skills selected by the affected module.
3. Explore the repository and cite evidence for the proposed impact.
4. Start a persisted workflow run and produce an implementation and test plan.
5. Wait for explicit human approval, then record `PLAN_APPROVED` before modifying production code.
6. If a feature branch is needed, create it while the tree is clean and before implementation.
7. Implement only the approved scope and record the deterministic gate evidence.
8. Obtain an independent read-only review from the supplied evidence packet; the reviewer has no shell access.
9. Record each correction cycle, then re-run the gate and review. Stop after the configured maximum of three standard-workflow review cycles. Fast-path work always stops after one correction cycle.
10. Present an explanation and PR description for human review.
11. Only when the user explicitly requests delivery, use the dedicated `delivery` agent for one approved branch, commit, normal feature-branch push, or draft PR operation at a time. Record the result in the same persisted run.

## Engineering rules

- Prefer the smallest correct change over speculative abstractions.
- Follow existing architecture, naming, error handling, and testing patterns.
- Do not change public behavior or APIs unless the approved plan requires it.
- Do not add dependencies, migrations, CI/CD changes, or infrastructure changes without explicit approval.
- Do not modify generated files or deployed migrations.
- Never weaken assertions, delete failing tests, disable checks, or suppress warnings merely to make a gate pass.
- Never introduce secrets or read or modify `.env` files. Example environment files may be read when needed.
- Keep unrelated user changes intact.
- If actual changed files exceed twice the approved estimate, or changed lines exceed three times the estimate, stop and explain the scope expansion.
- Every workflow-created commit must follow Conventional Commits and must never attribute authorship, co-authorship, or generation to Claude, Codex, ChatGPT, Copilot, OpenCode, or any other AI model, tool, or agent.

## Deterministic quality policy

LLM judgment never overrides command results. A gate passes only when every configured command exits successfully, in the configured order. Missing, skipped, or unexecuted required commands must be reported as NOT RUN, never PASS.

## Review policy

Review findings use `BLOCKER`, `HIGH`, `MEDIUM`, `LOW`, or `NIT` and include file, line, category, evidence, impact, and recommended fix. Any BLOCKER or HIGH finding makes the verdict FAIL. The reviewer never edits files or executes shell commands; it assesses only the supplied evidence packet.

## Delivery and safety boundary

All agents except `delivery` must never create branches, stage files, commit, push, or create pull requests. This includes `quick-fix` and `quick-reviewer`. The `delivery` agent may perform exactly one explicitly approved operation through the managed `.ai/scripts/` safeguards: create a local feature branch, create one Conventional Commit from exact staged files, push the current feature branch normally, or create one draft pull request.

Each operation requires current persisted PASS gate evidence, a persisted review without BLOCKER or HIGH findings, an unchanged delivery check, and a new one-time human approval. A commit must reproduce the exact reviewed gate fingerprint. Approval for one operation never authorizes the next. Never use force or force-with-lease, rewrite history, push tags, delete refs, update protected/shared branches, mark a PR ready, request reviewers, merge, release, deploy, mutate cloud infrastructure, or read/change secrets.
