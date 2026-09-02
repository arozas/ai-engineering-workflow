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
  project.json
  project-rules.md
  schemas and deterministic scripts
  runtime/ and runs/ local evidence
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
| `reviewer` | Subagent | Independent standard review. | Read-only; no shell. |
| `diagnostician` | Subagent | Evaluate sanitized incident evidence and falsifiable hypotheses. | Read-only; no shell or subagents. |
| `quick-fix` | Primary | Bounded low-risk implementation with one review and one correction maximum. | Approved fast-path application scope. |
| `quick-reviewer` | Subagent | Compact independent review for fast-path work. | Read-only; no shell. |
| `delivery` | Subagent | One explicitly approved branch, commit, push, or draft PR operation. | Guarded scripts and exact approved paths only. |

The orchestrator never implements production code. Review agents do not rediscover the repository through shell access; they receive exact evidence packets. This reduces both privilege and repeated context consumption.

## Skills and selective context

Skills separate stable procedure from project-specific facts. Core skills cover ticket analysis, planning, review, state, quality gates, delivery, diagnosis, Azure DevOps, stacks, and architectures.

After bootstrap, each module in `.ai/project.json` lists `contextSkills`. Agents load only the skills for affected modules. A project may therefore combine, for example, .NET clean architecture in one module and React vertical slices in another without loading both contexts for every task.

Generated `project-<module-id>` skills capture evidence-backed local conventions that generic stack profiles cannot know. They are declared in `.ai/generated-skills.json` and validated against the deterministic project profile.

## Persisted workflow state

Every standard, fast-path, or diagnostic request gets one local run:

```text
.ai/runs/<run-id>/
  state.json
  requirement.md
  plan.md
  gates.json
  review.md
  diagnosis.json
  commit.json
  publish.json
  pull-request.json
```

Only artifacts relevant to the route are present. `state.json` records legal status, route, task type, source diagnosis, Git SHA, worktree and control-plane fingerprints, correction limits, diagnostic limits, the approved quality plan, timestamps, and SHA-256 hashes of canonical artifacts.

Candidate inputs are written under `.ai/runtime/`. The state tool validates and copies them into the run. Agents must never directly edit canonical run files.

## Standard state flow

```text
PLANNING
  -> PLAN_APPROVED
  -> IMPLEMENTING
  -> GATES_PASSED or GATE_FAILED
  -> READY_FOR_DELIVERY or REVIEW_FAILED
  -> COMMITTED
  -> PUBLISHED
  -> PULL_REQUEST_OPEN
```

Correction transitions are bounded by project policy and never exceed three. Invalid scope or evidence enters `ESCALATED`. The fast path uses the same evidence model with a maximum of one correction.

## Diagnostic state flow

```text
DIAGNOSING
  -> ROOT_CAUSE_CONFIRMED
  -> DIAGNOSIS_BLOCKED
  -> ESCALATED
```

A blocked diagnostic run may begin another explicitly approved bounded iteration. A confirmed diagnosis does not authorize code changes; only `/ticket diagnosis:<run-id>` creates a traceable standard implementation run.

## Deterministic execution boundary

OpenCode custom tools in `.opencode/tools/workflow.ts` expose typed operations such as `workflow_state`, `workflow_gate`, `workflow_fast_path`, and `workflow_validate_project`. Each tool validates its arguments and starts PowerShell with an argument vector rather than constructing a shell command string.

The underlying scripts remain usable by maintainers and tests, but agents receive only the tools required by their roles. The global policy denies all `workflow_*` actions by default, after which agent definitions reopen exact actions.

## Quality-plan binding

When a plan is approved, state persists:

- the sorted, unique affected module IDs;
- the SHA-256 of `.ai/project.json`;
- the SHA-256 of the exact module path, phase order, and command arrays.

The gate tool accepts a run ID, not module IDs. It reconstructs the quality plan and rejects stale configuration before execution. Gate recording independently compares every evidence module, path, phase, and command with the approved plan. This prevents partial runs or schema-valid fabricated evidence from advancing state.

Root-level modules with path `.` are valid. Path canonicalization accepts the repository root itself but rejects any path that escapes it.

## Design trade-offs

The standard route intentionally spends more tokens and time than a single autonomous coding agent. It is designed for changes where approval, traceability, independent review, and factual verification matter. The fast path exists to keep known, low-risk work proportional.

Local installation keeps consumer repositories clean but makes the workflow clone-specific. Shared installation improves team reproducibility but intentionally adds control-plane files to version control. Neither mode is universally superior; installation documents the decision explicitly.
