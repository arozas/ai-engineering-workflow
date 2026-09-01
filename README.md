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
- Specialized orchestrator, developer, reviewer, and tester agents.
- Stack and architecture guidance loaded only when relevant.
- Deterministic, exit-code-based quality gates.
- Read-only Azure DevOps work-item retrieval.
- Safe installation and hash-aware updates.
- PR preparation without automatic Git or remote mutations.

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

The workflow never commits, pushes, merges, rebases, deploys, mutates cloud infrastructure, or changes secrets automatically.

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
Explanation and PR description for human delivery
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
    │   ├── project.example.json
    │   ├── project.schema.json
    │   ├── project-rules.md
    │   ├── bootstrap-input.schema.json
    │   └── workflow-installation.schema.json
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

The current management scripts are PowerShell-only. The installed OpenCode payload itself is plain Markdown and JSON.

### Required for workflow execution

- OpenCode V2, invoked by this distribution as `opencode2`.
- A configured OpenCode provider and model.
- The language runtimes, SDKs, package managers, and build tools used by the target project.

No model is pinned by the base template. Agents inherit the model selected in the OpenCode session unless the consumer project adds an explicit override.

### Optional tools

- Git, when `new-project.ps1 -InitializeGit` is used.
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
│   ├── project-rules.md
│   ├── project.example.json
│   ├── project.schema.json
│   ├── bootstrap-input.schema.json
│   ├── workflow-installation.schema.json
│   ├── workflow-installation.json       # generated by installation
│   ├── bootstrap-input.json              # generated for new projects
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
9. Run `/pr` to draft a title, description, risks, evidence, and checklist.
10. Review and perform commit, push, PR creation, merge, and deployment manually.

### Slash commands

| Command | Purpose | Writes production code? |
| --- | --- | --- |
| `/ai-bootstrap` | Inspect the repository and propose project configuration. Writes approved `.ai` configuration only after consent. | No |
| `/ticket` | Analyze a ticket, specification, or requirement and produce an approvable plan. | No |
| `/implement` | Delegate the latest explicitly approved plan to the developer. | Yes, within approved scope |
| `/test` | Derive acceptance scenarios, add tests only in recognized test paths, and run quality gates. | Tests only |
| `/review` | Delegate an independent review against ticket, plan, diff, and gate evidence. | No |
| `/explain` | Explain behavior, design choices, risks, deviations, and review order. | No |
| `/pr` | Draft a pull-request title and description. | No |

Commands are intentionally composable. `/implement` does not silently start repeated developer/reviewer correction cycles unless the user has authorized the full workflow.

## Agents

| Agent | Mode | Responsibility | Important boundary |
| --- | --- | --- | --- |
| `orchestrator` | Primary | Loads project context, analyzes requirements, plans work, enforces approval, and coordinates other agents. | Cannot implement production code directly. During bootstrap it may edit only approved `.ai/project.json` and `.ai/project-rules.md`. |
| `developer` | Subagent | Implements the explicitly approved plan using the smallest correct diff and project conventions. | Stops with `PLAN INVALIDATED` when evidence contradicts the plan; cannot launch subagents. |
| `reviewer` | Subagent | Reviews correctness, security, architecture, regressions, tests, and scope independently. | Read-only; arbitrary shell and all file edits are denied. Only safe Git inspection commands are allowed. |
| `tester` | Subagent | Converts acceptance criteria into scenarios and adds the smallest valuable tests. | May edit recognized test paths only; never production code. Returns `TESTABILITY ISSUE` when production changes are required. |

The orchestrator can delegate only to `developer`, `reviewer`, `tester`, and OpenCode's read-only `explore` agent.

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
- Allows safe Git inspection such as `git status`, `git diff`, `git log`, and `git show`.
- Denies `git commit`, `git push`, `git merge`, `git rebase`, `git reset`, and `git clean`.
- Denies common infrastructure mutations such as Terraform apply/destroy, Kubernetes apply/delete, and Azure deployments.

Agent-specific permissions further restrict the orchestrator, reviewer, and tester.

### Human gates

Explicit approval is required before:

- Writing bootstrap configuration.
- Modifying production code.
- Adding dependencies.
- Changing public contracts.
- Editing migrations, CI/CD, or infrastructure beyond approved scope.
- Starting correction loops when the full workflow was not already authorized.

Commit, push, PR creation, merge, deployment, secrets, and cloud mutations remain manual operations outside this workflow.

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
- [ ] OpenCode discovers `orchestrator`, `developer`, `reviewer`, and `tester` in a consumer repository.
- [ ] The reviewer remains effectively read-only.
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
- The workflow prepares PR content but does not create a PR.
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
