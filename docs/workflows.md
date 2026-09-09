# Operating workflows

## Choosing the route

Use the smallest route that is valid for the risk and uncertainty.

| Situation | Route |
| --- | --- |
| New feature, broad bug, cross-module work, dependency, public contract, migration, security, concurrency, data integrity, CI/CD, or infrastructure | `/ticket` standard workflow |
| Known-cause bug in one module, no more than three files and 120 changed lines, deterministic regression verification, no prohibited risk | `/quick-fix` |
| Bounded documentation, local configuration, or mechanical change with the same limits | `/small-task` |
| Production symptom with unknown cause | `/diagnose` |
| Already confirmed diagnostic run | `/ticket diagnosis:<run-id>` |

Urgency never changes the route. An unknown one-line production bug is still a diagnosis problem. A large generated change is not a fast-path task even when its conceptual edit is simple.

## Standard workflow

### Analyze

Run `/ticket <ticket, specification, or requirement>`. The orchestrator normalizes the input into a persisted requirement, loads project context for affected modules, and delegates at most one precise repository question to the eight-step read-only `evidence-reader`. That agent performs no shell commands, reads at most six production and four test files, and cannot recursively delegate. The orchestrator then proposes:

- observable acceptance criteria;
- evidence and confidence;
- affected module IDs, files, and expected diff budget;
- explicit non-goals;
- implementation steps and design decisions;
- success, boundary, failure, authorization, and regression scenarios;
- exact configured quality commands;
- exact task-specific verification commands that are required but not yet configured;
- risks and unresolved questions.

No production code changes during planning.

### Approve

Correct the proposal or explicitly approve it. Planning always writes `.ai/runtime/<run-id>/verification.json`; its command list is empty when configured gates are sufficient. Approval persists the exact plan, verification manifest, and affected module IDs. State validates and hashes the manifest, hashes the current `.ai/project.json`, and freezes the complete merged phase/command matrix for those modules. A mandatory command mentioned only in prose is not approval-ready.

Changing module selection later requires a new approved plan. Conversation history alone is not approval.

### Implement and test

Run `/implement` or request the full workflow. The orchestrator validates the run and sends the canonical requirement, plan, constraints, diff budget, and selected module context to the developer.

The developer stops with `PLAN INVALIDATED` if repository evidence contradicts the plan. It cannot add dependencies, change public contracts, alter migrations or CI/CD, or expand a refactor without approval. It does not use general shell commands for discovery, Git inspection, runtime checks, or ad hoc verification, and it never composes multiple commands; persisted evidence and the deterministic gate runner own those operations.

The tester may add focused tests only in established test locations. If testing requires a production design change, it reports `TESTABILITY ISSUE`.

### Gate

`workflow_gate` receives the run ID. It obtains the module list and approved verification manifest from state, verifies project, manifest, and merged-matrix hashes, and executes phases in this fixed order:

1. `restore`
2. `build`
3. `lint`
4. `typecheck`
5. `test`
6. `e2e`

Configured commands run first and approved task-specific commands follow in manifest order within the same phase. An empty phase is `NOT CONFIGURED`. The first failure normally stops that module and later commands become `NOT RUN`. A module with no commands is incomplete, not passing. For .NET modules, bootstrap-generated commands explicitly name the unique solution or project so adding another `.csproj` cannot turn a previously valid gate into `MSB1011`; approved run-specific commands must preserve that target.

The runner writes `.ai/runtime/<run-id>/gates.json`. If the run, project, runner, matrix, and worktree fingerprints are unchanged, a repeated gate request returns the existing validated artifact instead of executing commands again. `force: true` is reserved for an explicit intentional rerun. State accepts only that run-specific path and independently validates the run ID, module identities and paths, phases and commands, hashes, exit-derived status, and worktree stability before accepting it. Other active runs keep separate staging directories.

### Review

The orchestrator constructs an exact packet from the requirement, plan, diff, and gates. The reviewer receives it without application edit or general shell access and reports structured findings plus acceptance-criteria coverage through its exclusive typed tool or exact role-bound recorder fallback. The recorder creates `review.json`, binds it to the current SHA, reviewed worktree, and canonical gate hash, derives the verdict, and records the transition atomically. The orchestrator cannot call `RecordReview` through its general state tool or author the canonical verdict.

A `BLOCKER` or `HIGH` finding requires an approved correction, a full gate rerun, and another review. Project policy limits correction cycles to one through three. Exhausting the limit requires human intervention.

### Prepare delivery

`READY_FOR_DELIVERY` means the exact current diff has passing deterministic gates and review without high-severity findings. It does not authorize commit, push, merge, or deployment.

## Fast path

`/quick-fix` and `/small-task` use the `quick-fix` primary agent to reduce repeated context. Hard ceilings are:

- one affected module for a quick fix; zero or one for a small task;
- no more than three files and 120 added plus deleted lines;
- clear acceptance criteria and deterministic verification;
- no public contract, dependency, migration, generated code, CI/CD, infrastructure, deployment, security, secret, data-integrity, concurrency, or cross-module impact;
- no more than one correction cycle.

Project configuration may lower these limits but cannot raise them.

Before editing, the agent runs `workflow_fast_path` in `Estimate` mode and presents a compact micro-plan plus a run-specific verification manifest with exact paths, line estimate, verification, risk flags, evidence, and non-goals. One explicit approval authorizes only those exact artifacts.

After implementation, it runs the frozen merged quality matrix and `workflow_fast_path` in `Actual` mode. Actual mode derives files, line counts, module mapping, untracked files, binary uncertainty, and conservative path risks from Git. Expansion returns `FAST PATH INVALIDATED`.

The quick reviewer receives only the requirement, approved micro-plan, exact diff, gate results, and classifier output. It records through the separate `workflow_quick_review` capability; the standard reviewer uses `workflow_standard_review`. A failed second review after the single correction allowance escalates to `/ticket`.

## Production diagnosis

Run `/diagnose <sanitized incident description>`. Diagnosis is read-only and separates causal discovery from implementation. Only repository-evidenced local commands configured in `.ai/project.json` are allowed. It never connects to production, retrieves secrets, deploys, rolls back, restarts services, repairs data, or mutates infrastructure.

The diagnostic artifact contains impact, sanitized evidence IDs, competing falsifiable hypotheses, reproduction status, a confirmed evidence-backed root cause or explicit missing evidence, a regression-test obligation, bounded mitigation options, and safety assertions.

Outcomes:

- `ROOT_CAUSE_CONFIRMED`: exactly one supported hypothesis and regression test.
- `BLOCKED`: insufficient evidence and an exact missing-evidence list.
- `ESCALATED`: safe local diagnosis cannot continue.

Iterations are persisted and capped at three. A confirmed diagnosis starts implementation only through `/ticket diagnosis:<run-id>`; the new standard run records and validates that source.

## Guarded delivery

Delivery is split into single operations:

1. `/delivery-check` evaluates readiness without mutation.
2. `/branch` obtains readiness through the typed delivery check and proposes one local feature branch without attempting raw Git shell probes.
3. `/commit` proposes exact staged paths and a Conventional Commit.
4. `/publish` proposes a normal feature-branch push.
5. `/pr-create` proposes a draft PR with explicit base and head.

Each operation requires a fresh proposal, revalidation, and approval. Approval does not carry forward. The delivery agent stops after one operation and records evidence under `.ai/runtime/<run-id>/`. The branch script accepts the run ID and persists the previous branch, created branch, and SHA. The commit script accepts the run ID and owns both evidence generation and state recording.

Commits stage exact paths only; broad staging, amend, and AI authorship trailers are forbidden. State independently reads the actual commit message and changed paths, validates Conventional Commits, and compares them with `commit.json`; a fabricated evidence message cannot legitimize a nonconforming commit. Publishing never force-pushes, pushes tags, deletes refs, or publishes a protected/shared branch. State independently verifies the published remote ref and SHA. PR creation does not add reviewers, labels, assignees, comments, merge, or auto-merge; state independently queries GitHub and requires the exact open draft PR metadata before recording success.

Merge, rebase, reset, release, deployment, secret mutation, and cloud mutation remain outside the workflow.

## Resuming work

Use `/run-status <run-id>`. It validates artifact hashes and shows status, route, source diagnosis, Git state, quality plan, correction usage, and next legal action. Internally `workflow_next` returns a compact state summary. When the typed tool is absent, the only compatible lookup is `pwsh -NoProfile -File .ai/scripts/workflow-state.ps1 -Action Show -RunId <run-id> -Transport deterministic-script`, once; `Validate` is not a substitute. An agent must perform one returned action and stop at the next approval, blocker, escalation, or terminal boundary. Repeating an unchanged state, gate, classifier, review, delegation, or search is a protocol violation. If multiple nonterminal runs exist, commands require an exact ID and never guess.
