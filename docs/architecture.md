# Architecture and design

## Distribution and consumer repositories

AI Engineering Workflow separates the reusable distribution from the application that consumes it.

The distribution repository contains:

- `template/`: the installed OpenCode control plane.
- `presets/projects/`: new-project templates.
- `presets/stacks/`: reusable language and framework profiles.
- `presets/architectures/`: architecture guidance.
- `scripts/`: install, update, generation, validation, and evaluation utilities.
- `tests/`: an isolated end-to-end suite.
- `workflow.manifest.json`: the versioned inventory and preset roots.

Installation copies the template into a consumer repository. OpenCode then discovers:

```text
AGENTS.md
opencode.json
.ai/
  bootstrap-proposal/ editable bootstrap draft
  project.json
  project-rules.md
  schemas and deterministic scripts
  runtime/<run-id>/ isolated staging
  runs/<run-id>/ canonical local evidence
.opencode/
  agents/
  commands/
  skills/
  tools/workflow.ts
```

The installed payload is a control plane. It coordinates and verifies application work but is not application code.

## Control plane and data plane

The control plane consists of `AGENTS.md`, `opencode.json`, `.ai/`, and `.opencode/`. Application source, tests, manifests, and project configuration outside those paths are the data plane.

Implementation agents may change only the approved application scope. They cannot edit the control plane. A workflow run hashes every protected control-plane file at creation, excluding only local runtime and run evidence. Each sensitive transition recomputes the hash. This provides a second defense if permissions are misconfigured or a change occurs outside the agent.

Legitimate control-plane updates are separate configuration work. Existing application runs must be restarted after such an update because their policy snapshot is stale.

## Agent roles

| Agent | Mode | Responsibility | Mutation boundary |
| --- | --- | --- | --- |
| `orchestrator` | Primary | Requirement analysis, planning, approvals, state, routing, and evidence packets. | Project context and local runtime staging only. |
| `developer` | Subagent | Implement an approved plan with the smallest correct diff. | Approved application paths; no control plane. |
| `tester` | Subagent | Translate acceptance criteria into tests and execute the approved gate. | Established test locations only. |
| `reviewer` | Subagent | Independent standard review. | Application read-only; exact review-recorder fallback only. |
| `diagnostician` | Subagent | Evaluate sanitized incident evidence and falsifiable hypotheses. | Read-only; no shell or subagents. |
| `quick-fix` | Primary | Bounded low-risk implementation with one review and one correction maximum. | Approved fast-path application scope. |
| `quick-reviewer` | Subagent | Compact independent review for fast-path work. | Application read-only; exact review-recorder fallback only. |
| `delivery` | Subagent | One explicitly approved branch, commit, push, or draft PR operation. | Guarded scripts and exact approved paths only. |
| `evidence-reader` | Subagent | One bounded source/test evidence pass for a precise planning question. | Read-only; eight steps, no shell or subagents. |
| `bootstrap-enricher` | Subagent | Optional semantic refinement of a deterministic bootstrap draft. | Proposal-only edits from the bounded evidence packet; eight steps. |

The orchestrator never implements production code. Review agents do not rediscover the repository through shell access; they receive exact evidence packets. This reduces both privilege and repeated context consumption.

## Skills and selective context

Skills separate stable procedure from project-specific facts. Core skills cover ticket analysis, planning, review, state, quality gates, delivery, diagnosis, Azure DevOps, stacks, and architectures.

After bootstrap, each module in `.ai/project.json` lists `contextSkills`. Agents load only the skills for affected modules. A project may therefore combine, for example, .NET Clean Architecture in one module, a simple layered API in another, and React vertical slices in another without loading every context for every task.

Generated `project-<module-id>` skills capture evidence-backed local conventions that generic stack profiles cannot know. They are declared in `.ai/generated-skills.json` and validated against the deterministic project profile.

## Persisted workflow state

Every standard, fast-path, or diagnostic request gets one local run:

```text
.ai/runs/<run-id>/
  state.json
  requirement.md
  plan.md
  verification.json
  branch.json
  gates.json
  review.json
  diagnosis.json
  commit.json
  publish.json
  pull-request.json
```

Only artifacts relevant to the route are present. `state.json` records legal status, route, task type, source diagnosis, starting branch, Git SHA, worktree and control-plane fingerprints, correction limits, diagnostic limits, the approved quality plan, timestamps, and SHA-256 hashes of canonical artifacts.

Candidate inputs are written under `.ai/runtime/<run-id>/`. The state tool accepts only the exact artifact name under the matching run ID, validates it, and copies it into the canonical run. Two active runs therefore cannot overwrite each other's request, plan, gate, review, diagnosis, or delivery evidence. Agents must never directly edit canonical run files.

## Standard state flow

```text
PLANNING
  -> PLAN_APPROVED
     -> PLAN_APPROVED + verified branch evidence (optional)
  -> IMPLEMENTING
  -> GATES_PASSED, GATE_FAILED, GATE_BLOCKED, or PLAN_INVALIDATED
  -> READY_FOR_DELIVERY or REVIEW_FAILED
  -> COMMITTED
  -> PUBLISHED
  -> DRAFT_PR_CREATED
```

Correction transitions are bounded by project policy and never exceed three. Invalid scope or evidence enters `ESCALATED`. The fast path uses the same evidence model with a maximum of one correction.

## Diagnostic state flow

```text
DIAGNOSING
  +-> ROOT_CAUSE_CONFIRMED
  +-> DIAGNOSIS_BLOCKED -> DIAGNOSING
  +-> ESCALATED
```

A blocked diagnostic run may begin another explicitly approved bounded iteration. A confirmed diagnosis does not authorize code changes; only `/ticket diagnosis:<run-id>` creates a traceable standard implementation run.

## Deterministic execution boundary

OpenCode custom tools in `.opencode/tools/workflow.ts` expose typed operations such as `workflow_state`, `workflow_next`, `workflow_gate`, `workflow_dotnet_solution_add`, `workflow_standard_review`, `workflow_quick_review`, `workflow_fast_path`, `workflow_validate_project`, and `workflow_bootstrap_apply`. Each tool validates its arguments and starts PowerShell with an argument vector rather than constructing a shell command string. Model-facing state and gate responses are compact; complete evidence remains in persisted artifacts.

New plans use a version 2 execution contract in `verification.json`. It freezes paths, dependencies, decisions, constraints, estimates, modules, and extra commands alongside the human-readable plan. Before running commands, the gate runner enforces that scope and repository hygiene. After running them, it checks that generated output did not capture the workflow control plane. The separate `GATE_FAILED`, `GATE_BLOCKED`, and `PLAN_INVALIDATED` states keep command defects, unsafe repository state, and obsolete approvals from entering the same correction loop.

The same scripts form a compatibility transport when a preview runtime does not expose a typed tool. Agents inspect only the initial tool catalog, make at most one typed call, and on a genuine availability failure may run one exact `pwsh -NoProfile -File` command. They never search, compose shell text, retry, or use fallback after a semantic failure. State records which transport performed its last transition. This design requires no MCP server and keeps the deterministic state machine identical for small and large models.

The underlying scripts remain usable by maintainers and tests, but agents receive only the tools and fallback commands required by their roles. The global policy denies all `workflow_*` actions and managed script entry points by default, after which agent definitions reopen exact actions as typed `allow` or script `ask`.

## Quality-plan binding

When a plan is approved, state persists:

- the sorted, unique affected module IDs;
- the SHA-256 of `.ai/project.json`;
- the SHA-256 of the exact module path, phase order, and command arrays.

The gate tool accepts a run ID, not module IDs. It reconstructs the quality plan and rejects stale configuration before execution. Gate recording independently compares every evidence module, path, phase, and command with the approved plan. This prevents partial runs or schema-valid fabricated evidence from advancing state.

Root-level modules with path `.` are valid. Path canonicalization accepts the repository root itself but rejects any path that escapes it.

## Independent review binding

The general state tool deliberately does not expose `RecordReview`. Only `reviewer` can call `workflow_standard_review` or its exact `ReviewerRole=reviewer` script route, and only `quick-reviewer` can use the corresponding quick route. Both remain read-only for application code. Their exclusive route accepts a structured finding and coverage payload, then the deterministic script binds the result to the run ID, workflow path, expected reviewer role, current SHA, worktree fingerprint, and canonical gate hash.

The final verdict is derived rather than trusted. Any `BLOCKER` or `HIGH` finding, or any `PARTIAL`/`MISSING` acceptance criterion, produces `FAIL`. A non-empty escalation reason produces `ESCALATE`; only complete coverage without high-severity findings produces `PASS`. The canonical `review.json` also contains recomputed severity counts, so a prose-only or internally inconsistent review cannot advance state.

## Delivery evidence binding

Delivery evidence is not trusted merely because it is schema-valid. Branch creation is bound to the run's starting branch, current SHA, clean worktree, and resulting non-protected branch before `branch.json` is accepted. Commit recording reads the actual Git commit, validates its real message as Conventional Commits, compares the evidence message and exact changed-file list, proves a single-parent transition from the reviewed SHA, and verifies that the committed diff reproduces the gate-reviewed fingerprint.

`RecordPublish` verifies the current branch, current and persisted SHA, configured upstream, and exact `git ls-remote` result before entering `PUBLISHED`. `RecordPullRequest` queries GitHub through `gh pr view` and compares the PR number, URL, base, head, head SHA, title, open state, and draft state before entering `DRAFT_PR_CREATED`.

Evidence schemas deliberately omit the remote URL from the persisted publish record because Git remote URLs can contain credentials. The verifier resolves the configured remote locally without copying it into run evidence.

## Design trade-offs

The standard route intentionally spends more tokens and time than a single autonomous coding agent. It is designed for changes where approval, traceability, independent review, and factual verification matter. The fast path exists to keep known, low-risk work proportional.

Local installation keeps consumer repositories clean but makes the workflow clone-specific. Shared installation improves team reproducibility but intentionally adds control-plane files to version control. Neither mode is universally superior; installation documents the decision explicitly.
