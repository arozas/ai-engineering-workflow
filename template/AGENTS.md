# AI Engineering Workflow

This repository uses a stack-agnostic, human-gated engineering workflow. Treat `.ai/project.json` as the machine-readable source of project modules and quality commands after bootstrap. Treat `.ai/project-rules.md` as the highest-authority project guidance.

For `/ai-bootstrap`, do not load `project-context` first. Bootstrap has no trusted project context yet and must follow `.opencode/commands/ai-bootstrap.md`: run `workflow_bootstrap_prepare` once or its documented `prepare-bootstrap-proposal.ps1` fallback, then summarize the generated `.ai/bootstrap-proposal/` draft. Do not manually explore the repository during bootstrap. Never overwrite an existing draft unless the user explicitly runs `/ai-bootstrap --force`. `/ai-bootstrap-enhance` optionally gives a stronger model one bounded representative-file pass. `/ai-bootstrap-apply` validates and applies the approved draft.

At the start of ticket analysis, implementation, review, testing, or any non-bootstrap workflow task, load `project-context`. It must read `.ai/project-rules.md` and the applicable module configuration before work continues. If `.ai/project.json` does not exist yet, stop and tell the user to run `/ai-bootstrap`; do not guess, infer, or write project configuration from ad hoc exploration. Use `/ai-refresh` when the persisted repository profile reports structural drift; never regenerate project skills inside a delivery task.

For an existing run, call `workflow_next` once and perform one returned legal action. Do not repeat unchanged state, profile, gate, classifier, review, delegation, or search operations. Stop at the next approval, blocker, escalation, or terminal state.

## Unknown production failures

Use `/diagnose` when a production symptom is known but its cause is not. The diagnostic path is read-only, evidence-driven, persisted, and limited to three hypothesis iterations. The `diagnostician` has no edit, shell, subagent, production, secret, or delivery access. It may analyze only the exact sanitized evidence packet and repository files.

Do not use urgency to route an unknown incident through `/quick-fix`. Do not implement a speculative fix, connect to production, execute a mitigation, deploy, roll back, restart, repair data, or mutate cloud resources. A schema-valid `ROOT_CAUSE_CONFIRMED` run may become implementation work only after the user explicitly runs `/ticket diagnosis:<run-id>`.

## Fast path

Use `/quick-fix` for a bounded bug fix and `/small-task` for bounded documentation, local configuration, or mechanical work. Both commands must load `fast-path`, run the typed `workflow_fast_path` tool, present one compact micro-plan, and wait for explicit approval before editing.

Fast-path work is limited to one module, three files, 120 added-plus-deleted lines, deterministic verification, no prohibited risk category, and at most one correction cycle. Quick-fix diagnosis may read at most two relevant production files and two relevant test files. An unclear production root cause requires `/diagnose`. Scope expansion, public contract, dependency, migration, generated code, authentication, authorization, secrets, data integrity, concurrency, CI/CD, infrastructure, deployment, cloud, or cross-module impact requires `/ticket` and the standard workflow.

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
4. Start a persisted workflow run and produce an implementation and test plan, or a bounded diagnosis when `/diagnose` was selected.
5. Wait for explicit human approval, then record `PLAN_APPROVED` before modifying production code.
6. If a feature branch is needed, create it through the guarded run-aware script while the tree is clean and before implementation; require persisted branch evidence.
7. Implement only the approved scope and record the deterministic gate evidence.
8. Obtain an independent read-only review from the supplied evidence packet; the reviewer has no shell access and must record structured evidence through its exclusive typed tool.
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

LLM judgment never overrides command results. Quality gates must run through the typed `workflow_gate` tool for an approved run; agents cannot select a smaller module set and must never create or edit `.ai/runtime/<run-id>/gates.json` manually. A gate passes only when every command in the approved module matrix exits successfully, in the configured order, and the worktree remains unchanged during verification. Missing, skipped, or unexecuted required commands must be reported as NOT RUN, never PASS. `workflow_state` independently validates the run ID, exact module and command matrix, schema, project and runner hashes, derived verdict, worktree fingerprint, and control-plane fingerprint.

`AGENTS.md`, `opencode.json`, `.ai/`, and `.opencode/` form the workflow control plane. Developer and quick-fix work must not modify it. Agent permissions block direct control-plane edits, and persisted runs fingerprint the control plane so a change invalidates later gate, review, and delivery transitions. Configuration changes require a separate explicitly approved task and a new workflow run.

## Review policy

Review findings use `BLOCKER`, `HIGH`, `MEDIUM`, `LOW`, or `NIT` and include file, line, category, evidence, impact, and recommended fix. Any BLOCKER or HIGH finding, or incomplete acceptance-criteria coverage, makes the verdict FAIL. The reviewer never edits files or executes shell commands; it assesses only the supplied evidence packet and records through `workflow_standard_review` or `workflow_quick_review`. Orchestrator and implementation roles must not author or record review evidence.

## Delivery and safety boundary

All agents except `delivery` must never create branches, stage files, commit, push, or create pull requests. This includes `quick-fix` and `quick-reviewer`. The `delivery` agent may perform exactly one explicitly approved operation through the managed `.ai/scripts/` safeguards: create a local feature branch, create one Conventional Commit from exact staged files, push the current feature branch normally, or create one draft pull request.

Every operation requires a new one-time human approval. Branch creation occurs before implementation and instead requires `PLAN_APPROVED`, the recorded base branch/SHA, and a clean tree. Commit, push, and draft-PR operations require current persisted PASS gate evidence, a persisted review without BLOCKER or HIGH findings, and an unchanged delivery check. Branch and commit scripts must receive the selected run ID and own their evidence/state recording. A commit must reproduce the exact reviewed gate fingerprint, and state must independently validate its actual Git message and changed paths. Approval for one operation never authorizes the next. Never use force or force-with-lease, rewrite history, push tags, delete refs, update protected/shared branches, mark a PR ready, request reviewers, merge, release, deploy, mutate cloud infrastructure, or read/change secrets.
