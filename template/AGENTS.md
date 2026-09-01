# AI Engineering Workflow

This repository uses a stack-agnostic, human-gated engineering workflow. Treat `.ai/project.json` as the machine-readable source of project modules and quality commands after bootstrap. Treat `.ai/project-rules.md` as the highest-authority project guidance.

At the start of bootstrap, ticket analysis, implementation, review, or testing, load `project-context`. It must read `.ai/project-rules.md` and the applicable module configuration before work continues. If `.ai/project.json` does not exist yet, use `/ai-bootstrap` and do not guess the project configuration.

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
4. Produce an implementation and test plan.
5. Wait for explicit human approval before modifying production code.
6. Implement only the approved scope.
7. Run the exact deterministic quality commands from `.ai/project.json`.
8. Obtain an independent read-only review.
9. Correct BLOCKER and HIGH findings, then re-run the gate and review. Stop after three review cycles.
10. Present an explanation and PR description for human review. Never commit, push, merge, or deploy automatically.

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

## Deterministic quality policy

LLM judgment never overrides command results. A gate passes only when every configured command exits successfully, in the configured order. Missing, skipped, or unexecuted required commands must be reported as NOT RUN, never PASS.

## Review policy

Review findings use `BLOCKER`, `HIGH`, `MEDIUM`, `LOW`, or `NIT` and include file, line, category, evidence, impact, and recommended fix. Any BLOCKER or HIGH finding makes the verdict FAIL. The reviewer never edits files.

## Safety boundary

Never run destructive Git operations, create commits, push, merge, rebase, deploy, mutate cloud infrastructure, or change secrets. If such an action is necessary, stop and request explicit human action.
