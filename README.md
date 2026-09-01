# AI Engineering Workflow

A reusable, stack-agnostic engineering workflow for OpenCode V2. Use this repository as a versioned distribution: install the workflow into an existing application repository, or create a new project from a preset and install the workflow automatically.

The workflow turns tickets, specifications, and written requirements into evidence-based implementation plans, enforces explicit human approval before production changes, delegates implementation and testing to specialized agents, runs deterministic quality gates, performs an independent read-only review, and prepares human-facing explanations and pull-request descriptions.

> [!IMPORTANT]
> This repository is the **distribution source**, not an application repository. Do not run `/ai-bootstrap` here. The consumer payload lives under [`template/`](template/) and becomes active only after it is installed into another repository.

## Table of contents

- [Goals](#goals)
- [Core principles](#core-principles)
- [How the workflow fits together](#how-the-workflow-fits-together)
- [Repository layout](#repository-layout)
- [Requirements](#requirements)
- [Quick start](#quick-start)
- [Distribution commands](#distribution-commands)
- [Installed project layout](#installed-project-layout)
- [Bootstrap](#bootstrap)
- [Working with tickets and specifications](#working-with-tickets-and-specifications)
- [Agents](#agents)
- [Skills](#skills)
- [Project configuration](#project-configuration)
- [Deterministic quality gates](#deterministic-quality-gates)
- [Gated delivery workflow](#gated-delivery-workflow)
- [Pull-request template](#pull-request-template)
- [Azure DevOps integration](#azure-devops-integration)
- [Safety model](#safety-model)
- [Extending the distribution](#extending-the-distribution)
- [Validation and release checklist](#validation-and-release-checklist)
- [Troubleshooting](#troubleshooting)
- [Current limitations](#current-limitations)
- [OpenCode V2 compatibility](#opencode-v2-compatibility)

## Goals

This project is designed to provide a repeatable engineering process across repositories without forcing every project into the same stack or architecture.

It provides:

- A distributable OpenCode V2 configuration for existing repositories.
- Extensible project generators for new repositories.
- Evidence-based detection of modules, languages, frameworks, architecture, tests, build systems, CI/CD, and repository conventions.
- Ticket and specification analysis with testable acceptance criteria.
- A mandatory human approval point before production code changes.
- Specialized orchestrator, developer, reviewer, tester, and delivery agents.
- Stack and architecture guidance loaded only when relevant.
- Deterministic, exit-code-based quality gates.
- Read-only Azure DevOps work-item retrieval.
- Safe installation and hash-aware updates.
- Guarded feature-branch creation, Conventional Commits, normal feature-branch pushes, and draft PR creation with one-time human approvals.

This project does **not** attempt to replace project-specific conventions, CI/CD, code ownership, or human engineering judgment.

## Core principles

### Evidence before inference

Repository files, build manifests, test projects, lockfiles, CI/CD definitions, and existing instructions are treated as stronger evidence than directory names or common industry patterns. Missing evidence remains an explicit unknown.

### Human approval before implementation

Bootstrap and ticket analysis are read-only. The orchestrator must present a complete proposal or implementation plan and wait for explicit approval before configuration or production code is changed.

### Project context is selective

The workflow does not load every stack and architecture skill into every session. `.ai/project.json` maps each module to the exact `contextSkills` that apply to it.

### Quality results are factual

A command passes only when it runs and exits with code zero. Missing, skipped, denied, interrupted, or failed commands are never reported as passing.

### Review is independent and read-only

The reviewer can inspect the ticket, approved plan, diff, Git history, and gate evidence, but cannot edit files or run arbitrary shell commands.

### Delivery remains human-controlled

The workflow never performs a delivery mutation automatically. A dedicated `delivery` agent can create one local feature branch, Conventional Commit, normal feature-branch push, or draft pull request only after the exact operation is proposed, repository state is revalidated, and the user gives a new one-time approval. Merge, history rewriting, release, deployment, secret handling, and cloud mutations remain manual and denied.

## How the workflow fits together

```text
AI Engineering Workflow distribution
        |
        | install.ps1 or new-project.ps1
        v
Application repository with OpenCode payload
        |
        | /ai-bootstrap
        v
Evidence-backed .ai/project.json + project rules
        |
        | /ticket <ticket, spec, or requirement>
        v
Scoped implementation plan
        |
        | explicit human approval
        v
Developer -> deterministic gates -> tester -> read-only reviewer
        |
        v
Explanation + detailed PR draft
        |
        | separate approval for each operation
        v
Feature branch -> Conventional Commit -> normal push -> draft PR
        |
        v
Manual review, merge, release, and deployment
```

The distribution and consumer roles are intentionally separated:

- The **distribution repository** versions templates, scripts, schemas, and presets.
- A **consumer repository** receives the contents of `template/` at its root.
- `.ai/workflow-installation.json` records the installed version and hashes needed for later updates.
- `.ai/project.json` is generated only after bootstrap has inspected the real consumer repository and the user has approved the proposal.

## Repository layout

```text
ai-engineering-workflow/
├── README.md
├── VERSION
├── workflow.manifest.json
├── workflow.manifest.schema.json
├── .github/
│   └── pull_request_template.md
│
├── scripts/
│   ├── Workflow.Common.ps1
│   ├── install.ps1
│   ├── new-project.ps1
│   ├── update.ps1
│   └── validate.ps1
│
├── presets/
│   ├── projects/
│   │   ├── empty/
│   │   ├── node-basic/
│   │   ├── python-basic/
│   │   ├── dotnet-webapi/
│   │   └── react-vite/
│   ├── stacks/
│   │   ├── dotnet.json
│   │   ├── java.json
│   │   ├── node.json
│   │   ├── python.json
│   │   └── react.json
│   └── architectures/
│       ├── clean.json
│       ├── event-driven.json
│       ├── hexagonal.json
│       └── vertical-slice.json
│
└── template/
    ├── AGENTS.md
    ├── opencode.json
    ├── .ai/
    │   ├── .gitignore
    │   ├── pull-request-template.md
    │   ├── project.example.json
    │   ├── project.schema.json
    │   ├── project-rules.md
    │   ├── bootstrap-input.schema.json
    │   ├── workflow-installation.schema.json
    │   └── scripts/
    │       ├── delivery-check.ps1
    │       ├── create-branch.ps1
    │       ├── validate-commit-message.ps1
    │       ├── commit-approved.ps1
    │       ├── publish-approved.ps1
    │       └── create-draft-pr.ps1
    └── .opencode/
        ├── agents/
        ├── commands/
        └── skills/
```

`workflow.manifest.json` is the machine-readable distribution manifest. `VERSION` and the manifest version must contain the same semantic version.

## Requirements

### Required for distribution management

- Windows with PowerShell 7 or later.
- Read and write access to the target repository.
- The target must be outside the workflow distribution directory.

The distribution management scripts and guarded consumer delivery scripts are PowerShell-only. The remaining OpenCode payload is Markdown and JSON.

### Required for workflow execution

- OpenCode V2, invoked by this distribution as `opencode2`.
- A configured OpenCode provider and model.
- The language runtimes, SDKs, package managers, and build tools used by the target project.

No model is pinned by the base template. Agents inherit the model selected in the OpenCode session unless the consumer project adds an explicit override.

### Optional tools

- Git, when `new-project.ps1 -InitializeGit` is used.
- GitHub CLI, when the approved workflow creates a draft pull request.
- .NET SDK, for the `dotnet-webapi` preset.
- Node.js and npm, for the `react-vite` preset and for working with Node projects.
- Python, for working with the `python-basic` preset.
- Azure CLI plus the Azure DevOps extension, when Azure DevOps work-item retrieval is configured.

## Quick start

Clone or download this repository, then run its scripts from the distribution root.

```powershell
git clone https://github.com/arozas/ai-engineering-workflow.git
cd .\ai-engineering-workflow
```

### Install into an existing repository

Run a conflict preflight first:

```powershell
.\scripts\install.ps1 `
  -TargetPath "C:\Repositories\existing-application" `
  -DryRun
```

If the dry run reports no conflicts, install the payload:

```powershell
.\scripts\install.ps1 `
  -TargetPath "C:\Repositories\existing-application"
```

The target directory must already exist. Existing application files that do not overlap workflow paths are left untouched.

### Create a new repository

Inspect the available presets first:

```powershell
.\scripts\new-project.ps1 -ListPresets
```

Preview a new project without creating it:

```powershell
.\scripts\new-project.ps1 `
  -Name "orders-api" `
  -ParentPath "C:\Repositories" `
  -Preset "dotnet-webapi" `
  -Architecture "vertical-slice" `
  -DryRun
```

Create the project and initialize a `main` Git branch:

```powershell
.\scripts\new-project.ps1 `
  -Name "orders-api" `
  -ParentPath "C:\Repositories" `
  -Preset "dotnet-webapi" `
  -Architecture "vertical-slice" `
  -InitializeGit
```

### Bootstrap the consumer repository

After installation or project creation:

```powershell
cd "C:\Repositories\orders-api"
opencode2
```

Inside OpenCode:

```text
/ai-bootstrap
```

Review the proposed `.ai/project.json` and `.ai/project-rules.md`. Correct any assumptions or explicitly approve the proposal. Bootstrap writes those files only after approval.

## Distribution commands

### `install.ps1`

Installs every file under `template/` into an existing target repository.

| Parameter | Required | Description |
| --- | --- | --- |
| `-TargetPath` | Yes | Existing consumer repository directory. It must be outside the distribution repository. |
| `-DryRun` | No | Performs path and conflict validation without copying files. |

Safety behavior:

- Enumerates the complete template before copying.
- Checks every destination path for conflicts.
- Treats an existing `.ai/workflow-installation.json` as a conflict.
- Aborts before copying when any conflict exists.
- Never overwrites an existing target file.
- Writes `.ai/workflow-installation.json` with the workflow version and SHA-256 hash of each managed template file after a successful copy.

The conflict preflight protects existing files, but the copy is not a filesystem transaction. An unexpected I/O failure during copying can leave a partial installation; inspect the reported target and remove only the files that were copied before retrying.

### `new-project.ps1`

Creates a new directory, applies a project preset, installs the workflow, records bootstrap intent, and optionally initializes Git.

| Parameter | Required | Description |
| --- | --- | --- |
| `-Name` | Yes, except with `-ListPresets` | New directory and project name. Must start with a letter or number and may contain letters, numbers, `.`, `_`, and `-`. |
| `-ParentPath` | Yes, except with `-ListPresets` | Existing parent directory in which the project is created. |
| `-Preset` | No | Project preset ID. Defaults to `empty`. |
| `-Architecture` | No | Architecture preset ID recorded as bootstrap intent. |
| `-InitializeGit` | No | Runs `git init -b main` after project and workflow creation. |
| `-DryRun` | No | Validates the target and preset and prints external commands without creating the project. |
| `-ListPresets` | No | Lists project, stack, and architecture presets, then exits. |

The target directory must not already exist and cannot be inside the distribution repository.

If a preset generator or required executable fails after the target directory is created, the script deliberately leaves the partial project in place and reports its path. Inspect it before retrying or removing it.

#### Project presets

| Preset | Stacks | Network | Behavior |
| --- | --- | --- | --- |
| `empty` | None | No | Creates only the workflow payload. It has no application module to bootstrap. |
| `node-basic` | Node | No | Creates a dependency-free ES module with native Node tests. |
| `python-basic` | Python | No | Creates a minimal package with standard-library `unittest` tests. |
| `dotnet-webapi` | .NET | No | Runs the installed SDK's `dotnet new webapi` template with `--no-restore`. |
| `react-vite` | Node, React | Yes | Runs the official Vite React TypeScript generator through npm. |

`empty` is useful when the application will be added later. `/ai-bootstrap` correctly returns `NO PROJECT MODULES DETECTED` until source or build evidence exists.

#### Architecture presets

| Preset | Context skill | Intent |
| --- | --- | --- |
| `clean` | `architecture-clean` | Clean Architecture dependency direction and use-case boundaries. |
| `hexagonal` | `architecture-hexagonal` | Ports-and-adapters boundaries. |
| `vertical-slice` | `architecture-vertical-slice` | Feature-oriented vertical slices. |
| `event-driven` | `architecture-event-driven` | Event contracts, delivery semantics, idempotency, ordering, and evolution. |

The selected architecture is recorded as user intent in `.ai/bootstrap-input.json`. Bootstrap must still verify it against repository evidence; a preset selection is not proof that the generated application already follows that architecture.

### `update.ps1`

Updates a previously managed installation using `.ai/workflow-installation.json` as the baseline.

```powershell
.\scripts\update.ps1 `
  -TargetPath "C:\Repositories\existing-application" `
  -DryRun

.\scripts\update.ps1 `
  -TargetPath "C:\Repositories\existing-application"
```

| Target state | Result |
| --- | --- |
| Managed file is unchanged and template changed | File is updated. |
| Managed file already matches the new template | File is kept. |
| Managed file is missing | Entire update aborts before copying. |
| Managed file was locally modified | Entire update aborts before copying. |
| New template path does not exist in the target | File is added. |
| New template path exists with identical content | File is accepted and added to managed metadata. |
| New template path exists with different content | Entire update aborts before copying. |
| Previously managed path was retired from the template | Path is reported and left untouched. |

The updater never automatically deletes retired files. Resolve reported conflicts deliberately; do not replace customized project rules blindly.

Installations created before `.ai/workflow-installation.json` was introduced cannot be updated automatically. They must be migrated or reinstalled after reviewing conflicts.

### `validate.ps1`

Validates the distribution itself:

```powershell
.\scripts\validate.ps1
```

It checks:

- `VERSION` and manifest version consistency.
- Absence of active project configuration at the distribution root.
- Required template files.
- JSON parsing for every JSON document.
- PowerShell parsing for every management script.
- Skill directory and frontmatter name consistency.
- Agent and command frontmatter presence.
- Project preset IDs and directory names.
- Stack preset uniqueness and references from project presets.
- Architecture preset IDs and filenames.
- Final counts for template files, agents, commands, skills, and presets.

Run validation before committing or releasing distribution changes.

## Installed project layout

An installed consumer repository receives this payload at its root:

```text
consumer-repository/
├── AGENTS.md
├── opencode.json
├── .ai/
│   ├── .gitignore                         # ignores the local PR draft
│   ├── pull-request-template.md           # canonical consumer PR structure
│   ├── scripts/                           # guarded delivery operations
│   ├── project-rules.md
│   ├── project.example.json
│   ├── project.schema.json
│   ├── bootstrap-input.schema.json
│   ├── workflow-installation.schema.json
│   ├── workflow-installation.json       # generated by installation
│   ├── bootstrap-input.json              # generated for new projects
│   ├── pr-draft.md                        # ignored; written after PR approval
│   └── project.json                      # generated after approved bootstrap
└── .opencode/
    ├── agents/
    ├── commands/
    └── skills/
```

For an existing repository installed with `install.ps1`, `.ai/bootstrap-input.json` is normally absent. Bootstrap derives its proposal entirely from repository evidence and user corrections.

### Important files

- `AGENTS.md`: persistent workflow policy loaded by OpenCode V2.
- `opencode.json`: default agent and permission policy.
- `.ai/project.json`: approved modules, context skills, integrations, and deterministic quality commands.
- `.ai/project-rules.md`: approved repository-specific architecture and engineering rules.
- `.ai/workflow-installation.json`: distribution version and managed-file hashes used by updates.
- `.ai/bootstrap-input.json`: project-generator intent; it is not authoritative evidence.
- `.ai/pull-request-template.md`: detailed structure required by `/pr` and `/pr-create`.
- `.ai/pr-draft.md`: ignored local copy of the exact approved PR body.
- `.ai/scripts/`: guarded, deterministic wrappers for delivery checks and approved Git/GitHub mutations.
- `.opencode/agents/`: specialized agent definitions.
- `.opencode/commands/`: slash-command prompt templates.
- `.opencode/skills/`: reusable, on-demand workflow, stack, and architecture instructions.

## Bootstrap

`/ai-bootstrap` converts repository evidence into an explicit project model.

### Read-only preflight

Before loading the bootstrap skill, the command creates one inventory excluding workflow-owned paths:

- `AGENTS.md`
- `opencode.json`
- `.ai/**`
- `.opencode/**`

It then applies these stop conditions:

- `BOOTSTRAP NOT APPLICABLE`: the current repository is this distribution source rather than an application repository.
- `NO PROJECT MODULES DETECTED`: no application module can be supported by source or build evidence.

The empty-repository path stops immediately instead of repeatedly scanning an empty project.

### Bounded evidence scan

For an applicable repository, `repo-bootstrap`:

1. Reuses the initial inventory instead of repeating it.
2. Reads at most 20 relevant manifests, workspace files, CI/CD definitions, and instruction files.
3. Reads at most three representative source files and three representative test files per candidate module.
4. Caps representative files at 18 overall.
5. Never intentionally reads the same file twice or repeats an equivalent repository search.
6. Produces a proposal or stops when evidence is insufficient.

### Proposal

The proposal includes:

- Repository shape and module boundaries.
- Languages, frameworks, and architectures per module.
- `HIGH`, `MEDIUM`, or `LOW` confidence with evidence for every inference.
- Exact quality commands and the files that prove them.
- Selected stack and architecture skills.
- Risks, unknowns, and questions.
- A complete `.ai/project.json` conforming to `.ai/project.schema.json`.
- Proposed `.ai/project-rules.md` updates.
- A summary of the exploration ledger.

No configuration is written during the proposal. After explicit approval, bootstrap writes only the approved `.ai/project.json` and `.ai/project-rules.md`, validates them again, and reports that `/ticket` is ready.

## Working with tickets and specifications

After approved bootstrap, use `/ticket` with any of the following:

- A natural-language requirement.
- Acceptance criteria copied from a ticket.
- A path to a specification in the repository.
- An Azure DevOps work-item ID when the integration is configured.

Examples:

```text
/ticket Add optimistic concurrency checks when updating an order
```

```text
/ticket Implement the requirements in docs/specifications/order-cancellation.md
```

```text
/ticket 18427
```

### Recommended lifecycle

1. Run `/ticket <requirement>`.
2. Review the interpreted acceptance criteria, scope, affected modules, risks, quality commands, and expected diff budget.
3. Answer unresolved questions and explicitly approve the final plan.
4. Run `/implement`.
5. Run `/test` when acceptance scenarios or additional test work are needed.
6. Run `/review` for the independent read-only review.
7. If BLOCKER or HIGH findings exist, approve a correction cycle and repeat gates and review. The configured maximum is three cycles.
8. Run `/explain` for a human-oriented implementation walkthrough.
9. Run `/pr` to draft the title and complete canonical PR template.
10. Run `/delivery-check` and resolve every readiness blocker.
11. Optionally run `/branch`, `/commit`, `/publish`, and `/pr-create` in order. Review and explicitly approve each exact operation separately.
12. Review the draft PR and perform readiness changes, reviewer assignment, merge, release, and deployment manually.

### Slash commands

| Command | Purpose | Writes production code? |
| --- | --- | --- |
| `/ai-bootstrap` | Inspect the repository and propose project configuration. Writes approved `.ai` configuration only after consent. | No |
| `/ticket` | Analyze a ticket, specification, or requirement and produce an approvable plan. | No |
| `/implement` | Delegate the latest explicitly approved plan to the developer. | Yes, within approved scope |
| `/test` | Derive acceptance scenarios, add tests only in recognized test paths, and run quality gates. | Tests only |
| `/review` | Delegate an independent review against ticket, plan, diff, and gate evidence. | No |
| `/explain` | Explain behavior, design choices, risks, deviations, and review order. | No |
| `/pr` | Draft a title and detailed body using `.ai/pull-request-template.md`. | No |
| `/delivery-check` | Combine Git state, gates, review, scope, and diff evidence into a delivery-readiness verdict. | No |
| `/branch` | Propose and create one approved local feature branch. | Git metadata only |
| `/commit` | Stage exact approved paths and create one validated Conventional Commit. | Git index and local history |
| `/publish` | Push the current feature branch normally to an explicitly approved remote. | Remote feature branch |
| `/pr-create` | Create one explicitly approved draft PR from the published branch. | Draft PR only |

Commands are intentionally composable. `/implement` does not silently start repeated developer/reviewer correction cycles unless the user has authorized the full workflow. Delivery approval never carries forward: approving a commit does not approve a push, and approving a push does not approve PR creation.

## Agents

| Agent | Mode | Responsibility | Important boundary |
| --- | --- | --- | --- |
| `orchestrator` | Primary | Loads project context, analyzes requirements, plans work, enforces approval, and coordinates other agents. | Cannot implement production code directly. During bootstrap it may edit only approved `.ai/project.json` and `.ai/project-rules.md`. |
| `developer` | Subagent | Implements the explicitly approved plan using the smallest correct diff and project conventions. | Stops with `PLAN INVALIDATED` when evidence contradicts the plan; cannot launch subagents. |
| `reviewer` | Subagent | Reviews correctness, security, architecture, regressions, tests, and scope independently. | Read-only; arbitrary shell and all file edits are denied. Only safe Git inspection commands are allowed. |
| `tester` | Subagent | Converts acceptance criteria into scenarios and adds the smallest valuable tests. | May edit recognized test paths only; never production code. Returns `TESTABILITY ISSUE` when production changes are required. |
| `delivery` | Subagent | Revalidates delivery state and performs one approved branch, commit, push, or draft PR operation through managed scripts. | Cannot edit files or use arbitrary shell; merge, force, protected branches, tags, releases, deployments, and secret/cloud mutations remain denied. |

The orchestrator can delegate only to `developer`, `reviewer`, `tester`, `delivery`, and OpenCode's read-only `explore` agent.

## Skills

Skills are discovered from `.opencode/skills/` and loaded on demand.

### Core workflow skills

- `repo-bootstrap`: bounded repository inspection and project-configuration proposal.
- `project-context`: validates `.ai/project.json`, reads project rules, resolves affected modules, and loads only their context skills.
- `ticket-analysis`: converts requirements into traceable, testable acceptance criteria.
- `implementation-plan`: produces the required human-approvable plan.
- `quality-gate`: runs exact configured commands and reports exit-based results.
- `code-review`: defines structured independent review and severity rules.
- `explain-changes`: prepares a human code-review walkthrough.
- `pr-description`: drafts a traceable pull-request description.
- `conventional-commit`: defines allowed commit types, format, and the AI-attribution prohibition.
- `delivery-safety`: defines readiness evidence, one-operation approvals, and mutation boundaries.
- `azure-devops-ticket`: retrieves and normalizes Azure DevOps work items read-only.

### Stack skills

- `stack-dotnet`
- `stack-java`
- `stack-node`
- `stack-python`
- `stack-react`

Stack skills defer to repository evidence and project-specific rules. They do not impose a package manager, framework version, formatting tool, or testing framework that the repository does not already establish.

### Architecture skills

- `architecture-clean`
- `architecture-hexagonal`
- `architecture-vertical-slice`
- `architecture-event-driven`

Architecture skills preserve boundaries and evolution rules for the selected module. Project and module rules take precedence when they conflict with general architecture guidance.

## Project configuration

`.ai/project.json` is the machine-readable source of truth after bootstrap. It must validate against `.ai/project.schema.json`.

A simplified example:

```json
{
  "$schema": "./project.schema.json",
  "version": 1,
  "name": "orders-platform",
  "review": {
    "maxIterations": 3,
    "diffBudget": {
      "filesMultiplier": 2,
      "linesMultiplier": 3
    }
  },
  "modules": [
    {
      "id": "orders-api",
      "path": "src/orders-api",
      "languages": ["csharp"],
      "frameworks": ["aspnetcore"],
      "architectures": ["vertical-slice"],
      "contextSkills": [
        "stack-dotnet",
        "architecture-vertical-slice"
      ],
      "quality": {
        "restore": ["dotnet restore"],
        "build": ["dotnet build --no-restore"],
        "lint": ["dotnet format --verify-no-changes"],
        "typecheck": [],
        "test": ["dotnet test --no-build"],
        "e2e": []
      }
    }
  ],
  "integrations": {
    "workItems": {
      "provider": "azure-devops",
      "organization": "https://dev.azure.com/ORGANIZATION",
      "project": "PROJECT"
    }
  }
}
```

See [`template/.ai/project.example.json`](template/.ai/project.example.json) for a multi-module example.

### Module fields

| Field | Meaning |
| --- | --- |
| `id` | Stable lowercase kebab-case module identifier. |
| `path` | Working directory relative to the repository root. |
| `languages` | Languages supported by repository evidence. |
| `frameworks` | Frameworks supported by manifests or source evidence. |
| `architectures` | Confirmed or explicitly approved architecture identifiers. |
| `contextSkills` | Exact stack and architecture skills loaded for this module. |
| `quality` | Ordered command arrays for every deterministic gate phase. |

Every quality phase is required in the JSON shape, even when its command array is empty.

### Review policy

`review.maxIterations` accepts values from 1 through 3. A BLOCKER or HIGH finding makes the review verdict fail and requires correction plus a complete gate rerun before another review.

The optional diff budget compares actual implementation scope with the approved estimate:

- `filesMultiplier` defaults to 2.
- `linesMultiplier` defaults to 3.

The developer stops and reports scope expansion when actual changed files exceed the configured file multiple or changed lines exceed the configured line multiple.

## Deterministic quality gates

For each affected module, commands run with the module's `path` as the working directory and in this fixed order:

1. `restore`
2. `build`
3. `lint`
4. `typecheck`
5. `test`
6. `e2e`

Within each phase, array order is preserved.

### Status rules

- Exit code `0`: `PASS`.
- Nonzero exit code: `FAIL`.
- Timeout, missing executable, denied permission, or interrupted execution: `FAIL`.
- Command not attempted: `NOT RUN`.
- Empty phase: `NOT CONFIGURED`, not `PASS`.
- A module without configured commands: `INCOMPLETE CONFIGURATION`.
- Overall `PASS` requires every configured command for every affected module to pass.

The gate stops a module after its first failure unless the user explicitly requests a full diagnostic run. Remaining commands are reported as `NOT RUN`.

The agent may diagnose a failure, but it must not silently change commands, append flags, skip required checks, weaken assertions, delete failing tests, or suppress warnings merely to produce a passing result.

## Gated delivery workflow

Delivery is opt-in and separated from implementation. The `delivery` agent is the only agent that can request the narrow permissions needed for branch creation, staging, commit, push, or draft PR creation. It operates through managed scripts and stops after one approved mutation.

### Readiness check

Run:

```text
/delivery-check
```

The check combines:

- current branch and HEAD SHA
- configured remote and upstream
- staged, unstaged, and untracked paths
- latest approved implementation plan
- actual diff and diff-budget status
- deterministic gate evidence
- independent review verdict and unresolved findings

It reports `READY FOR DELIVERY` only when every required input is current. A missing plan, stale gate result, BLOCKER/HIGH finding, changed SHA, unrelated file, protected environment file, or scope mismatch produces `DELIVERY NOT READY`.

### Create a feature branch

```text
/branch
```

The command proposes one branch name and waits for approval. The managed script requires a clean working tree, validates the ref name, refuses an existing branch, and blocks shared/protected names including `main`, `master`, `develop`, `development`, `trunk`, and `release`.

Branch approval does not authorize a commit.

### Create a Conventional Commit

```text
/commit
```

The command presents the exact file paths, subject, optional body, branch, HEAD, and acceptance-criteria mapping before asking for approval.

Every workflow commit uses:

```text
<type>(optional-scope)(optional-!): <description>
```

Allowed types are `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`, and `revert`. Subjects are limited to 72 characters.

The workflow never adds AI authorship or co-authorship. It rejects messages containing attribution such as `Co-authored-by: Claude`, `Generated-by: ChatGPT`, `by Claude`, `byclaude`, or equivalent attribution to Anthropic, OpenAI, Codex, Copilot, Gemini, Cursor, OpenCode, or another AI agent.

Commit safeguards:

- Stage only explicitly approved file paths with `git add -- <paths>`.
- Never use `git add -A`, `git add .`, a directory path, `git commit -a`, or `--amend`.
- Inspect the cached diff after staging.
- Reject staged `.env` and `.env.*` files other than `.env.example`.
- Validate the exact message before and after commit creation.
- Preserve the human Git identity already configured in the repository.
- Stop after reporting the commit SHA; do not push automatically.

### Publish a feature branch

```text
/publish
```

Before approval, the command displays the remote name and URL, branch, HEAD SHA, and exact remote ref. The managed publisher requires a completely clean working tree and performs only a normal push of the current feature branch.

It never uses force, force-with-lease, tags, ref deletion, or a protected/shared branch. If the normal push is rejected because the remote changed, the workflow stops and reports the conflict instead of retrying with a more permissive command.

Push approval does not authorize PR creation.

### Create a draft pull request

First draft the complete content:

```text
/pr
```

Then create it only after reviewing the exact base, head, title, and body:

```text
/pr-create
```

After approval, the orchestrator writes the approved body to the ignored `.ai/pr-draft.md`. The managed script requires a clean working tree, a published feature branch with an upstream, and no existing open PR for that branch. It calls GitHub CLI with explicit base and head and always creates a draft.

The creation flow does not request reviewers, assign users, apply labels, add comments, include issue-closing keywords without approval, mark the PR ready, enable auto-merge, or merge it.

### Operations that remain manual

- Marking a draft ready for review.
- Requesting reviewers or assigning people.
- Applying labels, milestones, or project items.
- Adding comments or approvals.
- Merge and auto-merge.
- Rebase, reset, amend, force push, tag, and ref deletion.
- Releases and deployments.
- Database execution, secrets, and cloud mutations.

## Pull-request template

The distribution maintains two identical copies of the detailed template:

- [`.github/pull_request_template.md`](.github/pull_request_template.md) is used by GitHub for contributions to this distribution repository.
- [`template/.ai/pull-request-template.md`](template/.ai/pull-request-template.md) is installed into consumer repositories and is required by `/pr` and `/pr-create`.

The distribution validator fails when the two copies differ.

The template contains:

- summary, related work, problem, and solution
- included scope and explicit non-goals
- change classification
- acceptance-criteria traceability
- module and file impact
- design, data flow, alternatives, and dependencies
- API, compatibility, data, and migration impact
- security, privacy, reliability, performance, and observability
- exact deterministic gate evidence
- test scenarios and manual verification
- independent review results
- deployment, rollout, and rollback considerations
- risks and known limitations
- visual evidence and reviewer guidance
- final scope, quality, security, operations, and delivery checklists

Every section must remain present. Use `Not applicable` with a reason instead of deleting a section, and never represent a command or review as successful without evidence.

## Azure DevOps integration

Azure DevOps support is optional and read-only.

### Prerequisites

1. Install Azure CLI.
2. Install the Azure DevOps extension:

   ```powershell
   az extension add --name azure-devops
   ```

3. Authenticate using your normal Azure CLI process.
4. Configure `integrations.workItems` in the approved `.ai/project.json`.

```json
{
  "integrations": {
    "workItems": {
      "provider": "azure-devops",
      "organization": "https://dev.azure.com/ORGANIZATION",
      "project": "PROJECT"
    }
  }
}
```

Then pass a work-item ID:

```text
/ticket 18427
```

The skill retrieves the work item, description, acceptance criteria, comments, relations, parent and child links, related items, hyperlinks, and related pull requests when available. It preserves identifiers and source links and reports permission or retrieval gaps.

The integration never requests or stores credentials and never adds comments, updates fields, changes assignments, creates branches, or modifies the work item.

## Safety model

### Global boundaries

The installed `opencode.json`:

- Allows normal repository reads and edits for agents that are permitted to edit.
- Denies reading or editing `.env` and `.env.*` files.
- Allows reading `.env.example` and asks before editing it.
- Denies access outside the repository.
- Allows skills.
- Requires approval for shell commands by default.
- Allows narrowly scoped, read-only Git and GitHub PR inspection.
- Denies direct staging, branch mutation, commit, push, PR mutation, merge, rebase, reset, clean, tag, release, secret, variable, and workflow-dispatch commands.
- Denies direct invocation of managed mutation scripts for every agent except `delivery`.
- Denies common infrastructure mutations such as Terraform apply/destroy, Kubernetes apply/delete, and Azure deployments.

Agent-specific permissions further restrict the orchestrator, reviewer, tester, and delivery agent. The delivery agent's later, narrow `ask` rules override only the exact managed operations and still require a permission decision.

### Human gates

Explicit approval is required before:

- Writing bootstrap configuration.
- Modifying production code.
- Adding dependencies.
- Changing public contracts.
- Editing migrations, CI/CD, or infrastructure beyond approved scope.
- Starting correction loops when the full workflow was not already authorized.
- Creating one local feature branch.
- Staging an exact file list and creating one Conventional Commit.
- Pushing one feature branch normally.
- Creating one draft pull request with exact approved content.

Each delivery approval is single-purpose and state-bound. Commit, push, and draft PR creation can be requested through the gated delivery workflow, but are never automatic. Merge, ready-for-review transitions, releases, deployments, secrets, and cloud mutations remain manual operations outside this workflow.

### Scope control

Plans must identify affected modules and files, non-goals, test scenarios, risks, exact quality commands, and an expected file/line budget. If repository evidence later invalidates the plan, the developer must stop with `PLAN INVALIDATED` rather than inventing a new design.

## Extending the distribution

### Add a project preset

Create:

```text
presets/projects/<preset-id>/
├── preset.json
└── files/                  # optional
```

Minimal `preset.json`:

```json
{
  "id": "service-basic",
  "description": "Create a basic service",
  "stacks": ["node"],
  "networkRequired": false,
  "commands": []
}
```

Static files under `files/` are copied before generator commands run. Both paths and UTF-8 text content support these tokens:

| Token | Value |
| --- | --- |
| `{{name}}` | Original project name. |
| `{{packageName}}` | Lowercase package name. Unsupported characters become `-`. |
| `{{pythonPackage}}` | Package name with `-` and `.` converted to `_`. |
| `{{target}}` | Absolute target directory. |
| `{{parent}}` | Absolute parent directory. |

Generator commands use structured data:

```json
{
  "executable": "dotnet",
  "arguments": [
    "new",
    "webapi",
    "--name",
    "{{name}}",
    "--output",
    "{{target}}",
    "--no-restore"
  ],
  "workingDirectory": "{{parent}}"
}
```

An optional `environment` object can define process environment values for that command. Preset files and commands are trusted distribution code; review them as carefully as scripts.

### Add a stack profile

Create `presets/stacks/<id>.json`:

```json
{
  "id": "go",
  "contextSkills": ["stack-go"],
  "description": "Go applications and modules"
}
```

Then add the referenced skill under `template/.opencode/skills/stack-go/SKILL.md` and reference the stack ID from applicable project presets.

### Add an architecture profile

Create `presets/architectures/<id>.json`:

```json
{
  "id": "modular-monolith",
  "contextSkills": ["architecture-modular-monolith"],
  "description": "Explicit module boundaries within one deployment"
}
```

Add the matching skill under `template/.opencode/skills/`.

### Add a skill

Create `template/.opencode/skills/<skill-id>/SKILL.md` with YAML frontmatter:

```markdown
---
name: skill-id
description: Explain exactly when this skill is relevant
compatibility: opencode-v2
---

## Workflow

Detailed, bounded instructions go here.
```

The frontmatter `name` must match the directory name.

### Add an agent or command

- Add agents under `template/.opencode/agents/<agent-id>.md`.
- Add commands under `template/.opencode/commands/<command-id>.md`.
- Include YAML frontmatter with at least a useful description.
- Keep permissions narrowly aligned with the agent's responsibility.
- Do not pin a model unless the distribution intentionally adopts that model as a compatibility requirement.

### Change the consumer payload

Any file under `template/` becomes a managed file in new installations. Existing installations receive it through `update.ps1` only when the hash safety rules allow the update.

When changing the payload or distribution behavior:

1. Update `VERSION` using semantic versioning.
2. Update `workflow.manifest.json` to the same version.
3. Update schemas when a contract changes.
4. Update this README.
5. Run `scripts/validate.ps1`.
6. Test a fresh install, a fresh project, a clean update, and a locally modified update conflict.

## Validation and release checklist

Before releasing a change:

- [ ] `VERSION` and `workflow.manifest.json` match.
- [ ] The distribution root contains no `AGENTS.md`, `opencode.json`, `.ai/`, or `.opencode/`.
- [ ] `scripts/validate.ps1` passes.
- [ ] `install.ps1 -DryRun` reports conflicts without writing.
- [ ] A fresh installation creates valid installation metadata.
- [ ] `new-project.ps1 -ListPresets` lists every supported preset.
- [ ] At least one offline preset is created and its tests pass.
- [ ] `update.ps1 -DryRun` succeeds for an unchanged installation.
- [ ] An update aborts when a managed file was locally modified.
- [ ] OpenCode discovers `orchestrator`, `developer`, `reviewer`, `tester`, and `delivery` in a consumer repository.
- [ ] The reviewer remains effectively read-only.
- [ ] Non-delivery agents cannot invoke managed mutation scripts.
- [ ] The commit-message validator accepts valid Conventional Commits and rejects non-conventional or AI-attributed messages.
- [ ] Branch creation rejects protected/shared names and a dirty working tree.
- [ ] Publishing uses a normal feature-branch push and has no force fallback.
- [ ] Draft PR creation requires explicit base/head, an upstream branch, and the canonical template.
- [ ] The repository and consumer pull-request templates have identical hashes.
- [ ] The distribution root is not detected as a consumer configuration.
- [ ] No secrets, generated credentials, or local `.env` files are included.

## Troubleshooting

### `opencode2` is not recognized

Open a new terminal after installation and check command discovery:

```powershell
Get-Command opencode2
opencode2 --version
```

If the command is still unavailable, review the current [OpenCode installation documentation](https://opencode.ai/docs/).

### Installation reports conflicts

This is expected when the target already has workflow paths such as `AGENTS.md`, `opencode.json`, `.ai/`, or `.opencode/`.

The installer does not merge or overwrite them. Review each conflict and decide whether to:

- Keep the target's existing file and merge the workflow manually.
- Rename or relocate the existing file after confirming project behavior.
- Use a clean target.

Run `-DryRun` again before installing.

### Update reports `locally modified`

The target file no longer matches the hash recorded at installation. Preserve the local intent, compare it with the new template, and merge deliberately. The updater will not choose a version for you.

### Update metadata is missing

The target was not installed by the current version of `install.ps1`, or `.ai/workflow-installation.json` was removed. Automatic update is unavailable. Perform a reviewed migration or a clean reinstall instead of inventing baseline hashes.

### `BOOTSTRAP NOT APPLICABLE`

You launched `/ai-bootstrap` in the workflow distribution repository. Install or create a consumer project, change to that directory, start OpenCode there, and run the command again.

### `NO PROJECT MODULES DETECTED`

Bootstrap found no source/build evidence that can support a valid module. Add or generate the application first. This is expected for the `empty` preset before application files exist.

### Preset executable is missing

Install the SDK or runtime required by the chosen preset and ensure it is available in the current terminal. The partial target directory is kept so that you can inspect what was created before the failure.

### PowerShell blocks script execution

Inspect your organization's execution policy before changing it:

```powershell
Get-ExecutionPolicy -List
```

Use an approved policy or a process-scoped invocation consistent with your security requirements. Do not weaken machine-wide policy without understanding the impact.

### Azure DevOps retrieval fails

Verify:

- Azure CLI is installed.
- The Azure DevOps extension is installed.
- Your current CLI session is authenticated.
- The organization URL and project name in `.ai/project.json` are correct.
- Your identity has read access to the requested work item and its comments.

The workflow reports retrieval gaps and does not fall back to a write-capable operation.

## Current limitations

- Distribution management scripts currently require PowerShell 7+.
- The project generators are intentionally minimal starting points, not production application templates.
- The `empty` preset cannot bootstrap until application evidence exists.
- Azure DevOps is the only built-in work-item provider.
- Built-in stack skills currently cover .NET, Java, Node.js, Python, and React.
- Built-in architecture skills currently cover Clean Architecture, Hexagonal Architecture, Vertical Slice, and Event-Driven systems.
- The gated delivery workflow can create draft PRs on GitHub; other hosting providers are not built in.
- GitHub CLI is required for draft PR creation.
- The workflow does not mark PRs ready, request reviewers, apply labels, merge, release, or deploy.
- The workflow does not configure CI/CD or deployment automatically.
- File installation and updates perform full conflict preflight, but are not transactional against unexpected filesystem failures.
- OpenCode V2 is evolving; validate the distribution again after upgrading the CLI.

## OpenCode V2 compatibility

The template follows the current OpenCode V2 project conventions:

- Persistent project instructions in `AGENTS.md`.
- Project agents in `.opencode/agents/`.
- Project commands in `.opencode/commands/`.
- On-demand skills in `.opencode/skills/`.
- Ordered V2 permissions in `opencode.json`.

Current OpenCode V2 accepts an `instructions` field in `opencode.json` but does not yet resolve those files into active instruction sources. The template therefore relies on `AGENTS.md` to require `project-context`, and `project-context` explicitly reads `.ai/project-rules.md` before project work.

Relevant documentation:

- [OpenCode V2 instructions](https://opencode.ai/v2/docs/instructions/)
- [OpenCode V2 agents](https://opencode.ai/v2/docs/agents/)
- [OpenCode V2 commands](https://opencode.ai/v2/docs/commands/)
- [OpenCode skills](https://opencode.ai/docs/skills)
- [OpenCode V2 configuration](https://opencode.ai/v2/docs/config/)

Because OpenCode V2 is still evolving, keep the workflow versioned, run deterministic distribution validation, and smoke-test a consumer repository before adopting a new CLI release.
