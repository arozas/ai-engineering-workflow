# AI Engineering Workflow

A reusable, stack-agnostic engineering workflow for OpenCode V2. Use this repository as a versioned distribution: install the workflow into an existing application repository, or create a new project from a preset and install the workflow automatically.

The workflow turns tickets, specifications, written requirements, and unknown production incidents into evidence-based plans or diagnoses. It enforces explicit human approval before production changes, delegates implementation and testing to specialized agents, runs deterministic quality gates, performs independent read-only review, and prepares human-facing explanations and pull-request descriptions.

> [!IMPORTANT]
> This repository is the **distribution source**, not an application repository. Do not run `/ai-bootstrap` here. The consumer payload lives under [`template/`](template/) and becomes active only after it is installed into another repository.

## Table of contents

- [Goals](#goals)
- [Core principles](#core-principles)
- [How the workflow fits together](#how-the-workflow-fits-together)
- [Repository layout](#repository-layout)
- [Requirements](#requirements)
- [Quick start](#quick-start)
- [Installation modes](#installation-modes)
- [Distribution commands](#distribution-commands)
- [Installed project layout](#installed-project-layout)
- [Bootstrap](#bootstrap)
- [Working with tickets and specifications](#working-with-tickets-and-specifications)
- [Production diagnosis for unknown incidents](#production-diagnosis-for-unknown-incidents)
- [Persisted workflow state](#persisted-workflow-state)
- [Fast path for small changes](#fast-path-for-small-changes)
- [Agents](#agents)
- [Model selection](#model-selection)
- [Skills](#skills)
- [Project configuration](#project-configuration)
- [Deterministic quality gates](#deterministic-quality-gates)
- [Control-plane protection](#control-plane-protection)
- [Gated delivery workflow](#gated-delivery-workflow)
- [Pull-request template](#pull-request-template)
- [Azure DevOps integration](#azure-devops-integration)
- [Safety model](#safety-model)
- [Extending the distribution](#extending-the-distribution)
- [Validation and release checklist](#validation-and-release-checklist)
- [Measuring token efficiency and quality](#measuring-token-efficiency-and-quality)
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
- Bounded, read-only production diagnosis with persisted evidence, falsifiable hypotheses, and a confirmed-root-cause gate.
- A mandatory human approval point before production code changes.
- Specialized orchestrator, diagnostician, developer, reviewer, tester, delivery, quick-fix, and quick-reviewer agents.
- A deterministic, bounded fast path for low-risk bug fixes and small tasks.
- Local, hash-verified run state that survives session changes and compaction.
- Stack and architecture guidance loaded only when relevant.
- Deterministic, exit-code-based quality gates executed by a managed runner with schema-valid evidence.
- Read-only Azure DevOps work-item retrieval.
- Safe installation and hash-aware updates.
- Local-first installation that keeps the OpenCode runtime out of consumer commits and pull requests.
- Guarded feature-branch creation, Conventional Commits, normal feature-branch pushes, and draft PR creation with one-time human approvals.

This project does **not** attempt to replace project-specific conventions, CI/CD, code ownership, or human engineering judgment.

## Core principles

### Evidence before inference

Repository files, build manifests, test projects, lockfiles, CI/CD definitions, and existing instructions are treated as stronger evidence than directory names or common industry patterns. Missing evidence remains an explicit unknown.

For production incidents, plausible code is not proof. Every causal claim must cite sanitized evidence, distinguish credible alternatives, and define what would falsify it. Insufficient evidence produces `DIAGNOSIS_BLOCKED`, not a speculative fix.

### Human approval before implementation

Bootstrap and ticket analysis are read-only. The orchestrator must present a complete proposal or implementation plan and wait for explicit approval before configuration or production code is changed.

### Approved state is persisted

Conversation history is not the source of truth for execution. Requirements, approved plans, gate evidence, review evidence, correction counts, Git SHAs, and worktree fingerprints are stored under ignored `.ai/runs/` records and verified before each transition.

### Project context is selective

The workflow does not load every stack and architecture skill into every session. `.ai/project.json` maps each module to the exact `contextSkills` that apply to it.

### Workflow effort is proportional to risk

Small, well-understood changes can use a bounded fast path with less context, one implementation agent, one read-only review, and at most one correction. Ambiguous, broad, cross-module, security-sensitive, contract-changing, migration, infrastructure, concurrency, data-integrity, dependency, or generated-code work must use the standard workflow.

An unknown production cause uses `/diagnose`, regardless of urgency or apparent diff size. Only a confirmed diagnostic run can seed a standard implementation ticket.

### Quality results are factual

A command passes only when the managed runner executes it and receives exit code zero. Missing, skipped, denied, interrupted, timed-out, or failed commands are never reported as passing. An agent-authored verdict is not evidence.

### Review is independent and read-only

The reviewer can inspect the ticket, approved plan, diff, Git history, and gate evidence, but cannot edit files or run arbitrary shell commands.

### Delivery remains human-controlled

The workflow never performs a delivery mutation automatically. A dedicated `delivery` agent can create one local feature branch, Conventional Commit, normal feature-branch push, or draft pull request only after the exact operation is proposed, repository state is revalidated, and the user gives a new one-time approval. Merge, history rewriting, release, deployment, secret handling, and cloud mutations remain manual and denied.

### Consumer repositories stay clean by default

The default `Local` installation writes the workflow files into the consumer working tree so OpenCode can discover them, then excludes workflow-owned paths and the reserved generated-skill namespace through that clone's `.git/info/exclude`. The consumer's tracked `.gitignore`, commits, branches, and pull requests are not changed. Teams that intentionally want to version the workflow and generated project context can opt into `Shared` mode.

## How the workflow fits together

```text
AI Engineering Workflow distribution
        |
        | install.ps1 or new-project.ps1
        v
Application repository with OpenCode payload
        |
        | /ai-bootstrap once
        v
Deterministic profile + project model + composed skills
        |
        +-------------------------------+
        |                               |
        | /quick-fix or /small-task     | /ticket <ticket, spec, or requirement>
        v                               v
Bounded classifier + micro-plan    Scoped implementation plan
        |                               |
        | explicit approval             | explicit approval
        v                               v
Persisted approved run state       Persisted approved run state
        |                               |
        | optional feature branch       | optional feature branch
        v                               v
Quick fix -> gates -> quick review  Developer -> gates -> tester -> reviewer
        |                               |
        | eligible final diff           | standard correction policy
        +---------------+---------------+
        v
Explanation + detailed PR draft
        |
        | separate approval for each operation
        v
Verified diff -> Conventional Commit -> normal push -> draft PR
        |
        v
Manual review, merge, release, and deployment
```

The distribution and consumer roles are intentionally separated:

- The **distribution repository** versions templates, scripts, schemas, and presets.
- A **consumer repository** receives the contents of `template/` at its root.
- Local installations keep those files available on disk but invisible to normal Git status and staging in that clone.
- `.ai/workflow-installation.json` records the installed version, installation mode, local exclusion paths, and hashes needed for later updates.
- `.ai/project.json` is generated only after bootstrap has inspected the real consumer repository and the user has approved the proposal.
- `.ai/project-profile.json` records deterministic structural evidence and a refresh fingerprint without sending repository content to the installer.
- Built-in stack and architecture skills are composed with minimal `project-<module>` skills only when repository-specific rules justify them.
- `.ai/runs/<run-id>/state.json` provides a resumable state machine whose canonical artifacts are hash verified and remain local.
- `/diagnose` creates a separate read-only diagnostic run. A validated `ROOT_CAUSE_CONFIRMED` result can enter the normal planning path only through an explicit `/ticket diagnosis:<run-id>` handoff.

## Repository layout

```text
ai-engineering-workflow/
├── README.md
├── VERSION
├── workflow.manifest.json
├── workflow.manifest.schema.json
├── .github/
│   ├── pull_request_template.md
│   └── workflows/validate.yml
│
├── scripts/
│   ├── Workflow.Common.ps1
│   ├── install.ps1
│   ├── new-project.ps1
│   ├── update.ps1
│   ├── summarize-evaluations.ps1
│   └── validate.ps1
├── tests/
│   └── Run-Tests.ps1
├── evaluations/
│   ├── README.md
│   └── benchmark.schema.json
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
    │   ├── project-profile.schema.json
    │   ├── generated-skills.schema.json
    │   ├── project-rules.md
    │   ├── bootstrap-input.schema.json
    │   ├── workflow-installation.schema.json
    │   ├── workflow-run.schema.json
    │   └── scripts/
    │       ├── fast-path-check.ps1
    │       ├── profile-project.ps1
    │       ├── validate-project.ps1
    │       ├── workflow-state.ps1
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
- Git for the default `Local` mode. Existing targets must be initialized repositories, and the target must be the repository root.

The distribution management scripts and guarded consumer delivery scripts are PowerShell-only. The remaining OpenCode payload is Markdown and JSON.

### Required for workflow execution

- OpenCode V2, invoked by this distribution as `opencode2`.
- A configured OpenCode provider and model.
- The language runtimes, SDKs, package managers, and build tools used by the target project.

No model is pinned by the base template. Agents inherit the model selected in the OpenCode session unless the consumer project adds an explicit override.

### Optional tools

- Git is optional only when explicitly using `Shared` mode without `-InitializeGit`.
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

`Local` is the default mode. The target directory must already exist, be an initialized Git repository, and be its repository root. Existing application files that do not overlap workflow paths are left untouched. The installer does not create a branch, stage files, commit, push, or edit the repository's tracked `.gitignore`.

To intentionally make all workflow files visible to Git:

```powershell
.\scripts\install.ps1 `
  -TargetPath "C:\Repositories\existing-application" `
  -Mode Shared
```

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

Create the project with a local-only workflow installation:

```powershell
.\scripts\new-project.ps1 `
  -Name "orders-api" `
  -ParentPath "C:\Repositories" `
  -Preset "dotnet-webapi" `
  -Architecture "vertical-slice"
```

Because `Local` is the default, `new-project.ps1` initializes a `main` Git repository when the preset did not already create one. Use `-Mode Shared` when the workflow should remain Git-visible; add `-InitializeGit` only if the shared project should also be initialized as a repository.

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

## Installation modes

### Local mode: default

Local mode is intended for individual developers and for consumer repositories that should not carry the workflow implementation in their history.

```powershell
.\scripts\install.ps1 `
  -TargetPath "C:\Repositories\existing-application" `
  -Mode Local
```

The installer:

- Requires the target to be the root of an initialized Git repository.
- Rejects a local installation when any path that needs to be excluded is already tracked. Git cannot hide tracked files with ignore rules.
- Performs the normal destination conflict preflight before copying.
- Adds one clearly delimited block to the clone-local `.git/info/exclude` file.
- Lists exact workflow and generated file paths instead of ignoring entire `.ai` or `.opencode` directories. Unrelated consumer files cannot be hidden accidentally.
- Preserves every line outside the managed exclude block.
- Records the local paths in `.ai/workflow-installation.json` so later updates can maintain the block.
- Verifies that installed workflow files are ignored and that a pure local installation did not change the Git-visible working-tree status.

`.git/info/exclude` belongs only to the current clone. It is not committed, pushed, or copied when another developer clones the application repository. Each clone that needs the workflow must run the installer independently.

### Shared mode: explicit opt-in

Shared mode installs the same payload but does not add local Git exclusions:

```powershell
.\scripts\install.ps1 `
  -TargetPath "C:\Repositories\existing-application" `
  -Mode Shared
```

The files remain visible to `git status` and may be committed deliberately. The installer still never stages or commits them. Shared mode can also be used for a non-Git target.

### Hybrid project-context sharing

Use this option when the workflow runtime should remain local but the approved module model and repository rules should be reviewable by the team:

```powershell
.\scripts\install.ps1 `
  -TargetPath "C:\Repositories\existing-application" `
  -Mode Local `
  -ShareProjectContext
```

All runtime files remain clone-local except:

- `.ai/project-rules.md`, installed initially and updated by approved bootstrap.
- `.ai/project.json`, generated only after approved bootstrap.

Those two paths remain Git-visible. The installer does not stage or commit them. `-ShareProjectContext` is invalid with `Shared` mode because all workflow paths are already visible there.

### Changing mode safely

`update.ps1` preserves the installed mode unless an explicit mode is supplied. It can also migrate an installation:

```powershell
# Make a previously shared, untracked installation local.
.\scripts\update.ps1 `
  -TargetPath "C:\Repositories\existing-application" `
  -Mode Local

# Make a local installation visible to Git.
.\scripts\update.ps1 `
  -TargetPath "C:\Repositories\existing-application" `
  -Mode Shared
```

Shared-to-local migration is refused if any locally excluded path is already tracked. Local-to-shared migration removes only the delimited workflow block from `.git/info/exclude`; all unrelated exclude rules remain intact.

## Distribution commands

### `install.ps1`

Installs every file under `template/` into an existing target repository.

| Parameter | Required | Description |
| --- | --- | --- |
| `-TargetPath` | Yes | Existing consumer repository directory. It must be outside the distribution repository. |
| `-Mode` | No | `Local` by default, or explicit `Shared`. Local mode requires the target to be its Git repository root. |
| `-ShareProjectContext` | No | With Local mode, leaves `.ai/project-rules.md` and generated `.ai/project.json` Git-visible. |
| `-DryRun` | No | Performs path and conflict validation without copying files. |

Safety behavior:

- Enumerates the complete template before copying.
- Checks every destination path for conflicts.
- Treats an existing `.ai/workflow-installation.json` as a conflict.
- Aborts before copying when any conflict exists.
- Never overwrites an existing target file.
- Never creates a branch, stages files, commits, pushes, or edits the tracked `.gitignore`.
- In Local mode, rejects tracked local paths before copying and manages only its delimited `.git/info/exclude` block.
- Writes `.ai/workflow-installation.json` with the workflow version, mode, local excluded paths, and SHA-256 hash of each managed template file after a successful copy.

The conflict preflight protects existing files, but the copy is not a filesystem transaction. An unexpected I/O failure during copying can leave a partial installation; inspect the reported target and remove only the files that were copied before retrying.

### `new-project.ps1`

Creates a new directory, applies a project preset, installs the workflow, records bootstrap intent, and initializes Git when Local mode or `-InitializeGit` requires it.

| Parameter | Required | Description |
| --- | --- | --- |
| `-Name` | Yes, except with `-ListPresets` | New directory and project name. Must start with a letter or number and may contain letters, numbers, `.`, `_`, and `-`. |
| `-ParentPath` | Yes, except with `-ListPresets` | Existing parent directory in which the project is created. |
| `-Preset` | No | Project preset ID. Defaults to `empty`. |
| `-Architecture` | No | Architecture preset ID recorded as bootstrap intent. |
| `-Mode` | No | Workflow installation mode. Defaults to `Local`. |
| `-ShareProjectContext` | No | Keeps only approved project context Git-visible in Local mode. |
| `-InitializeGit` | No | Initializes a `main` Git repository in Shared mode. Local mode initializes Git automatically. |
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
| Managed file was locally modified | Entire update aborts before copying, except mutable `.ai/project-rules.md`, which is preserved. |
| New template path does not exist in the target | File is added. |
| New template path exists with identical content | File is accepted and added to managed metadata. |
| New template path exists with different content | Entire update aborts before copying. |
| Previously managed path was retired from the template | Path is reported and left untouched. |

The updater never automatically deletes retired files. In Local mode, their recorded paths remain locally excluded so a retired workflow file is not exposed accidentally by a later update. Customized `.ai/project-rules.md` is treated as user-owned project context and is preserved.

`update.ps1` accepts `-Mode` and `-ShareProjectContext` using the same semantics as installation. Without those parameters, it preserves the mode recorded in schema-version-2 metadata. Schema-version-1 installations are interpreted as `Shared`, matching the behavior of workflow releases before 1.2.0.

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
│   ├── .gitignore                         # ignores runtime, run state, and PR draft
│   ├── pull-request-template.md           # canonical consumer PR structure
│   ├── scripts/                           # guarded delivery operations
│   ├── project-rules.md
│   ├── project.example.json
│   ├── project.schema.json
│   ├── project-profile.schema.json       # deterministic repository evidence contract
│   ├── generated-skills.schema.json      # project-skill audit contract
│   ├── bootstrap-input.schema.json
│   ├── workflow-installation.schema.json
│   ├── workflow-run.schema.json           # persisted run-state contract
│   ├── quality-gates.schema.json           # deterministic command-evidence contract
│   ├── diagnosis.schema.json              # production-diagnosis evidence contract
│   ├── workflow-installation.json       # generated by installation
│   ├── bootstrap-input.json              # generated for new projects
│   ├── project-profile.json              # generated after approved profiling
│   ├── generated-skills.json             # generated-skill evidence and composition
│   ├── pr-draft.md                        # ignored; written after PR approval
│   ├── runtime/                           # ignored transition inputs
│   ├── runs/<run-id>/                     # ignored canonical evidence and state
│   └── project.json                       # generated after approved bootstrap
└── .opencode/
    ├── agents/
    ├── commands/
    └── skills/
        └── project-<module>/SKILL.md      # optional approved project-specific delta
```

The physical layout is identical in Local and Shared modes. The difference is Git visibility: Local mode records exact paths in `.git/info/exclude`, while Shared mode leaves them visible. No workflow file is committed automatically in either mode.

For an existing repository installed with `install.ps1`, `.ai/bootstrap-input.json` is normally absent. Bootstrap derives its proposal entirely from repository evidence and user corrections.

### Important files

- `AGENTS.md`: persistent workflow policy loaded by OpenCode V2.
- `opencode.json`: default agent and permission policy.
- `.ai/project.json`: approved modules, context skills, integrations, and deterministic quality commands.
- `.ai/project-profile.json`: deterministic manifests, languages, module candidates, structural markers, tests, CI, conventions, and repository fingerprint.
- `.ai/generated-skills.json`: generated-skill ownership, confidence, composition, evidence, and matching profile fingerprint.
- `.ai/project-rules.md`: approved repository-specific architecture and engineering rules.
- `.ai/workflow-installation.json`: distribution version, installation mode, exact local exclusion paths, and managed-file hashes used by updates.
- `.ai/bootstrap-input.json`: project-generator intent; it is not authoritative evidence.
- `.ai/pull-request-template.md`: detailed structure required by `/pr` and `/pr-create`.
- `.ai/pr-draft.md`: ignored local copy of the exact approved PR body.
- `.ai/runtime/`: ignored temporary inputs written before deterministic state transitions.
- `.ai/runs/<run-id>/`: canonical requirement, approved plan, gate, review, delivery evidence, hashes, SHAs, and status.
- `.ai/diagnosis.schema.json`: portable contract for sanitized evidence, hypotheses, reproduction, root cause, regression test, and safety assertions.
- `.ai/scripts/validate-project.ps1`: deterministic JSON Schema, module-path, context-skill, and command validation.
- `.ai/scripts/profile-project.ps1`: bounded Git-aware repository profiling with no application writes unless an approved output path is supplied.
- `.ai/scripts/workflow-state.ps1`: legal run transitions, artifact hashing, HEAD checks, correction limits, and worktree fingerprints.
- `.ai/scripts/run-quality-gates.ps1`: exact configured command execution, timeout handling, output capture, exit-derived verdicts, and atomic gate evidence.
- `.ai/scripts/validate-diagnosis.ps1`: deterministic schema and semantic validation for evidence IDs, root-cause confirmation, blocked evidence, reproduction policy, and safety assertions.
- `.ai/scripts/`: deterministic classifiers plus guarded delivery checks and approved Git/GitHub mutations.
- `.opencode/agents/`: specialized agent definitions.
- `.opencode/commands/`: slash-command prompt templates.
- `.opencode/skills/`: reusable, on-demand workflow, stack, and architecture instructions.

## Bootstrap

`/ai-bootstrap` converts repository evidence into an explicit project model and a minimal composition of reusable and project-specific skills. Installation remains deterministic and model-independent; personalization begins only when the user runs this command.

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

1. Reuses the deterministic profile and Git-visible inventory created by the command preflight.
2. Records manifest hashes, detected languages, module candidates, architecture markers, tests, CI/CD, conventions, and a structure fingerprint.
3. Reads at most 20 relevant manifests, workspace files, CI/CD definitions, and instruction files.
4. Reads at most three representative source files and three representative test files per candidate module.
5. Caps representative files at 18 overall.
6. Never intentionally reads the same file twice or repeats evidence already supplied by the profiler.
7. Produces a proposal or stops when evidence is insufficient.

### Proposal

The proposal includes:

- Repository shape and module boundaries.
- Languages, frameworks, and architectures per module.
- `HIGH`, `MEDIUM`, or `LOW` confidence with evidence for every inference.
- Exact quality commands and the files that prove them.
- Selected stack and architecture skills.
- The deterministic structure fingerprint and any evidence conflicts.
- A complete `.ai/generated-skills.json`, even when no custom skill is required.
- Full text for each proposed `project-<module-id>` skill.
- Risks, unknowns, and questions.
- A complete `.ai/project.json` conforming to `.ai/project.schema.json`.
- Proposed `.ai/project-rules.md` updates.
- A summary of the exploration ledger.

No configuration or skill is written during the proposal. After explicit approval, bootstrap reruns the profiler, refuses structural drift, persists `.ai/project-profile.json`, and writes only the approved `.ai/project.json`, `.ai/project-rules.md`, `.ai/generated-skills.json`, and project skills. It reports that `/ticket`, `/diagnose`, and `/ai-refresh` are ready only after `.ai/scripts/validate-project.ps1` returns `PROJECT_VALID`.

### Generated project skills

The builder first reuses built-in stack and architecture skills. A generated skill is justified only for verified repository-specific behavior such as module ownership, dependency direction, local file placement, error conventions, protected generated files, or exact testing rules.

Generated skills use the ID `project-<module-id>` and contain mandatory `Scope`, `Evidence`, `Rules`, `Quality and testing`, and `Unknowns` sections. LOW-confidence hypotheses stay under `Unknowns`; they cannot silently become mandatory rules. The generated-skills manifest records every claim, evidence path, confidence, and composed built-in skill.

In `Local` mode, approved profile files and `project-*` skills remain clone-local. In `Shared` mode they remain Git-visible, but the workflow still never stages or commits them automatically.

### Refreshing personalization

Run `/ai-refresh` after module boundaries, manifests, languages, architecture markers, CI/CD, or convention files change. It compares a fresh deterministic fingerprint with the approved profile. Matching fingerprints return `PROJECT PROFILE CURRENT` without model-driven regeneration. Drift produces a bounded proposal and requires explicit approval before updating or retiring any generated skill.

Ordinary source-content changes and additional files in an already recognized structure do not force refresh. Implementation commands never regenerate project context implicitly.

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

## Production diagnosis for unknown incidents

Use `/diagnose` when a production symptom is known but its cause is not. This is not the fast path and it does not implement a fix. It creates a separate, read-only run that turns sanitized incident evidence into bounded hypotheses and one of three auditable outcomes.

```text
/diagnose Checkout requests started returning stale totals after release 2026.09.01; the cause is unknown
```

The orchestrator loads `production-diagnosis`, persists a sanitized incident requirement, and starts a `diagnostic` run in `DIAGNOSING`. It may inspect repository evidence and may run only the local commands explicitly listed in `diagnostics.commands`, subject to the normal shell approval. The workflow never connects to production itself. Logs, metrics, traces, deployment facts, timestamps, and affected versions must be supplied by the user in a sanitized form.

The orchestrator gives the `diagnostician` an exact evidence packet. That agent cannot edit files, execute shell commands, delegate work, access external directories, read secrets, or perform delivery operations. It assigns stable `E<n>` evidence IDs and `H<n>` hypothesis IDs, records supporting and contradicting evidence, and defines a safe falsification test for each hypothesis.

### Diagnostic outcomes

| Persisted status | Meaning | Next action |
| --- | --- | --- |
| `DIAGNOSIS_BLOCKED` | Current evidence cannot distinguish credible causes. The artifact names the smallest missing evidence needed. | Supply or approve new sanitized evidence, then explicitly start another bounded iteration. |
| `ROOT_CAUSE_CONFIRMED` | Exactly one hypothesis is supported by concrete evidence, credible alternatives are addressed, and a regression-test obligation is defined. | Run `/ticket diagnosis:<run-id>` to create a separate standard implementation run. |
| `ESCALATED` | Safe analysis cannot continue because of risk, inaccessible evidence, or the iteration limit. | Use the relevant human incident, security, data, or infrastructure process. |

Each `RecordDiagnosis` call consumes one configured hypothesis iteration. A blocked run can return to `DIAGNOSING` only through `BeginDiagnosticIteration`, after the user provides or approves new evidence. The project policy allows one to three total iterations; three is the hard schema ceiling.

Reproduction is preferred, not automatically mandatory. Independent logs, traces, metrics, or deployment evidence can establish a causal chain when local reproduction is impossible. Set `diagnostics.requireReproduction` to `true` when repository policy requires `REPRODUCED` or `PARTIAL` before confirmation. The deterministic validator enforces that choice.

### Confirmation and handoff

`.ai/scripts/validate-diagnosis.ps1` rejects duplicate IDs, dangling evidence references, multiple confirmed hypotheses, a root cause without supporting evidence, a confirmation without a regression test, a blocked result without missing evidence, and any artifact claiming that production was mutated or secrets were accessed. `workflow-state.ps1` validates and hashes the artifact again before advancing the run.

After confirmation, use the exact source run ID:

```text
/ticket diagnosis:diagnose-stale-totals
```

The new standard run records `sourceRunId`, revalidates the canonical diagnosis and hashes, preserves the causal statement and regression-test obligation, verifies the proposed code scope, and creates an implementation plan. It does not repeat causal discovery and still waits for explicit plan approval before code changes.

Mitigation options in a diagnosis are proposals only. `/diagnose` never authorizes a speculative code change, rollback, restart, deployment, data repair, infrastructure action, secret access, or cloud mutation. Urgency does not weaken this boundary.

## Persisted workflow state

Ticket, diagnostic, and fast-path commands create an ignored local run under `.ai/runs/<run-id>/`. This is the execution source of truth; the conversation remains the human interface but is not the only record of approval.

```text
.ai/runs/ticket-18427/
├── state.json
├── requirement.md
├── plan.md
├── gates.json
├── review.md
├── commit.json
├── publish.json
└── pull-request.json
```

`state.json` records the workflow path, legal status, base/current Git SHA, post-gate worktree fingerprint, correction allowance, timestamps, and SHA-256 for every canonical artifact. Agents write candidate inputs under `.ai/runtime/`; `.ai/scripts/workflow-state.ps1` copies, hashes, validates, and advances them. Canonical run files and `state.json` must never be edited directly.

Legal standard transitions are:

```text
PLANNING -> PLAN_APPROVED -> IMPLEMENTING
    -> GATES_PASSED -> READY_FOR_DELIVERY
    -> COMMITTED -> PUBLISHED -> DRAFT_PR_CREATED
```

Gate or review failure can enter one approved correction and return to `IMPLEMENTING` until the configured limit is reached. Any invalidated route enters `ESCALATED`. The fast path allows exactly one correction; the standard path uses `review.maxIterations`, capped at three.

Legal diagnostic transitions are:

```text
DIAGNOSING -> DIAGNOSIS_BLOCKED -> DIAGNOSING
           -> ROOT_CAUSE_CONFIRMED
           -> ESCALATED
```

`ROOT_CAUSE_CONFIRMED` is terminal for the diagnostic run. An explicit `/ticket diagnosis:<run-id>` starts a separate `PLANNING` run whose `sourceRunId` preserves the relationship.

Resume or audit a run with:

```text
/run-status ticket-18427
```

Every transition first validates the run schema and every canonical artifact hash. Gate and review transitions also require an unchanged HEAD. Review requires the actual worktree fingerprint to match the one recorded after gates. A temporary Git index produces the same canonical binary diff for tracked, deleted, and newly added files without modifying the real index. After commit, the state script reconstructs that representation and refuses the commit unless it matches the exact gate-reviewed fingerprint.

### Recommended lifecycle

1. Run `/ticket <requirement>`.
2. Review the interpreted acceptance criteria, scope, affected modules, risks, quality commands, and expected diff budget.
3. Answer unresolved questions and explicitly approve the final plan.
4. Optionally run `/branch` while the tree is clean and the persisted run is `PLAN_APPROVED`.
5. Run `/implement`.
6. Run `/test` when acceptance scenarios or additional test work are needed.
7. Run `/review` for the independent shell-free review.
8. If BLOCKER or HIGH findings exist, approve a correction cycle and repeat gates and review. The persisted maximum is enforced.
9. Run `/explain` for a human-oriented implementation walkthrough.
10. Run `/pr` to draft the title and complete canonical PR template.
11. Run `/delivery-check` and resolve every readiness blocker.
12. Optionally run `/commit`, `/publish`, and `/pr-create` in order. Review and explicitly approve each exact operation separately.
13. Review the draft PR and perform readiness changes, reviewer assignment, merge, release, and deployment manually.

### Slash commands

| Command | Purpose | Writes production code? |
| --- | --- | --- |
| `/ai-bootstrap` | Inspect the repository and propose project configuration. Writes approved `.ai` configuration only after consent. | No |
| `/ai-refresh` | Compare current structural evidence with the approved profile and propose project-context or generated-skill updates. | No application code |
| `/ticket` | Analyze a ticket, specification, or requirement and produce an approvable plan. | No |
| `/diagnose` | Diagnose an unknown production failure from sanitized evidence, without code or production mutations. | No |
| `/quick-fix` | Classify and implement a well-understood, low-risk bug fix through the bounded fast path. | Yes, after micro-plan approval |
| `/small-task` | Classify and implement a narrow documentation, test, or local configuration change through the bounded fast path. | Yes, after micro-plan approval |
| `/run-status` | Validate and display a persisted run, hashes, corrections, and next legal action. | No |
| `/implement` | Delegate an exact persisted plan in `PLAN_APPROVED` to the developer. | Yes, within approved scope |
| `/test` | Derive acceptance scenarios, add tests only in recognized test paths, and run quality gates. | Tests only |
| `/review` | Build an exact evidence packet and delegate a shell-free independent review. | No |
| `/explain` | Explain behavior, design choices, risks, deviations, and review order. | No |
| `/pr` | Draft a title and detailed body using `.ai/pull-request-template.md`. | No |
| `/delivery-check` | Combine Git state, gates, review, scope, and diff evidence into a delivery-readiness verdict. | No |
| `/branch` | Create one approved feature branch after plan approval and before implementation. | Git metadata only |
| `/commit` | Stage exact approved paths and create one validated Conventional Commit. | Git index and local history |
| `/publish` | Push the current feature branch normally to an explicitly approved remote. | Remote feature branch |
| `/pr-create` | Create one explicitly approved draft PR from the published branch. | Draft PR only |

Commands are intentionally composable. `/implement` does not silently start repeated developer/reviewer correction cycles unless the user has authorized the full workflow. Delivery approval never carries forward: approving a commit does not approve a push, and approving a push does not approve PR creation.

## Fast path for small changes

The fast path reduces coordination and context overhead for changes whose risk and scope are already understood. It is not a weaker quality mode: it keeps explicit approval, deterministic configured gates, a final scope recheck, and an independent read-only review. It saves tokens by loading fewer files, avoiding the full planning handoff chain, and limiting corrections; actual provider token usage still depends on the selected models, prompts, and repository content.

Use `/quick-fix <problem>` for a reproducible bug with a known root cause. Use `/small-task <request>` for a narrow documentation, test-only, or local configuration task. Both commands run through the `quick-fix` primary agent and the `fast-path` skill.

### Default eligibility policy

A task is eligible only when all of these statements are true:

- Acceptance criteria are clear and verification is available.
- At most one configured project module is affected.
- The estimate is no more than three changed files and 120 changed lines.
- Diagnosis needs no more than two production files and two test files.
- A quick fix has a known root cause; a small task may have no production module.
- The task does not change a public contract or add a dependency.
- It does not involve migrations, security-sensitive behavior, infrastructure, data integrity, concurrency, cross-module coordination, or generated code.
- At most one correction cycle is needed.

The repository can adopt stricter numeric limits through `fastPath` in `.ai/project.json`, but it cannot raise the schema ceilings. The evaluator is `.ai/scripts/fast-path-check.ps1`. Estimate mode evaluates bounded declared evidence. Actual mode reads project limits, derives changed files and added-plus-deleted lines from Git, maps paths to configured modules, includes untracked text files, rejects unmeasurable binary changes, and conservatively recognizes dependency, migration, CI/infrastructure, generated, security, and public-contract paths. Exit code `0` and `FAST_PATH_ELIGIBLE` permit the fast path; exit code `3` and `ESCALATE_STANDARD` require the standard workflow.

Example estimate:

```powershell
pwsh -NoProfile -File .ai/scripts/fast-path-check.ps1 `
  -TaskType QuickFix `
  -Phase Estimate `
  -ModuleCount 1 `
  -FileCount 2 `
  -LineCount 35 `
  -AcceptanceClear `
  -RootCauseKnown `
  -VerificationAvailable
```

### Fast-path lifecycle

1. The quick-fix agent loads project context and only the files allowed by the diagnosis budget.
2. The classifier evaluates the estimate and risk flags.
3. The agent presents a compact micro-plan, verification commands, and file/line estimate.
4. The user explicitly approves implementation.
5. The agent implements the smallest correct change and runs configured deterministic gates.
6. The classifier rechecks the actual diff.
7. The quick reviewer independently reviews the requirement, micro-plan, diff, gate evidence, and classifier evidence.
8. One correction is allowed. Any second correction, BLOCKER/HIGH finding after correction, or loss of eligibility ends the fast path and returns a standard-workflow handoff summary.

Fast-path approval authorizes only its micro-plan. It does not approve branch creation, commit, push, PR creation, merge, release, or deployment. The same separate delivery approvals and Conventional Commit requirements apply.

The quick reviewer has neither edit nor shell permissions. The quick-fix agent constructs the exact diff packet after gates and passes only persisted requirement, plan, classifier, diff, and gate evidence.

### Automatic escalation

Do not force a task to remain small. Use `/ticket` and the standard lifecycle when the classifier rejects the estimate, evidence invalidates the root cause, the actual diff exceeds a limit, an excluded risk appears, a configured quality gate fails for a reason that expands scope, or the quick review cannot be resolved in one correction. Existing evidence should be summarized for the standard orchestrator so work is not rediscovered unnecessarily.

## Agents

| Agent | Mode | Responsibility | Important boundary |
| --- | --- | --- | --- |
| `orchestrator` | Primary | Loads project context, analyzes requirements, plans work, enforces approval, and coordinates other agents. | Cannot implement production code directly. During bootstrap or refresh it may write only the explicitly approved profile, project configuration, rules, generated-skills manifest, and `project-*` skills. |
| `diagnostician` | Subagent | Tests bounded causal hypotheses against an exact sanitized evidence packet and returns a schema-valid diagnosis. | No edits, no shell, no subagents, no production access, no secrets, and no implementation or mitigation authority. |
| `quick-fix` | Primary | Classifies, plans, implements, verifies, and closes bounded low-risk changes with minimal context. | Must reclassify the actual diff, permits one correction only, and delegates solely to `quick-reviewer`. |
| `quick-reviewer` | Subagent | Performs a focused independent review of a supplied fast-path diff packet. | No edits, no shell, eight-step budget, and no subagents. |
| `developer` | Subagent | Implements the explicitly approved plan using the smallest correct diff and project conventions. | Stops with `PLAN INVALIDATED` when evidence contradicts the plan; cannot launch subagents. |
| `reviewer` | Subagent | Reviews correctness, security, architecture, regressions, tests, and scope independently from a supplied evidence packet. | No edits, no shell, and no subagents. It cannot rediscover or mutate repository state. |
| `tester` | Subagent | Converts acceptance criteria into scenarios and adds the smallest valuable tests. | May edit recognized test paths only; never production code. Returns `TESTABILITY ISSUE` when production changes are required. |
| `delivery` | Subagent | Revalidates delivery state and performs one approved branch, commit, push, or draft PR operation through managed scripts. | Cannot edit files or use arbitrary shell; merge, force, protected branches, tags, releases, deployments, and secret/cloud mutations remain denied. |

The standard orchestrator can delegate only to `diagnostician`, `developer`, `reviewer`, `tester`, `delivery`, and OpenCode's read-only `explore` agent. Fast-path commands select the `quick-fix` primary agent directly, avoiding an orchestrator handoff; that agent can delegate only to `quick-reviewer`.

Profiling does not introduce another agent. The orchestrator composes the deterministic `project-profiler` and `project-skill-builder` skills during the one-time, human-approved bootstrap. This avoids a permanent extra handoff and token cost; a dedicated read-only profiling agent can be added later if measured monorepo context pressure justifies it.

## Model selection

The base distribution deliberately does not pin a provider or model. This keeps the workflow portable across OpenCode providers, authentication methods, budgets, and future model releases. When an agent has no explicit `model` field, the primary agent uses the globally or session-selected model, and a subagent inherits the model of the primary agent that invoked it.

OpenCode supports a model override in each agent definition. Model identifiers use the exact `provider-id/model-id` format documented by OpenCode; display names, marketing names, and aliases must not be guessed.

### Discover available model IDs

Configure each required provider in OpenCode:

```text
/connect
```

Then inspect the models actually available to the current OpenCode installation and authenticated providers:

```text
/models
```

Copy the exact identifier shown by OpenCode. Availability varies by provider, account, region, subscription, and OpenCode version. The workflow documentation therefore recommends model capabilities rather than hard-coding product names that may become unavailable or obsolete.

Official references:

- [OpenCode agents: agent-specific model overrides and inheritance](https://opencode.ai/docs/agents/)
- [OpenCode models: provider configuration, model selection, IDs, and variants](https://opencode.ai/docs/models/)
- [OpenCode providers: authentication and provider setup](https://opencode.ai/docs/providers/)
- [OpenCode configuration reference](https://opencode.ai/docs/config/)

### Recommended model classes by agent

| Agent | Recommended model class | Why this class is appropriate |
| --- | --- | --- |
| `orchestrator` | Frontier reasoning and tool-use model | The orchestrator interprets incomplete requirements, resolves repository evidence, produces bounded plans, coordinates specialized agents, and decides when human approval is required. Strong reasoning and reliable tool use matter more than low per-call cost. |
| `diagnostician` | Strong analytical and causal-reasoning model | The diagnostician must separate observations from inference, compare competing explanations, design falsification tests, and resist premature confirmation. Analytical discipline matters more than code generation or tool use because the role is shell-free and read-only. |
| `developer` | Frontier coding model | The developer must understand an approved plan, navigate an existing codebase, preserve architecture and conventions, implement the smallest correct change, and diagnose quality-gate failures. Strong code generation and repository-scale context handling reduce rework. |
| `quick-fix` | Fast, strong, cost-efficient coding model | This role handles only preclassified, single-module changes with a small context and diff budget. It still needs reliable diagnosis and editing, but a low-latency coding model usually provides a better cost/quality balance than the standard orchestrator/developer pair. |
| `quick-reviewer` | Cost-efficient analytical model | The quick reviewer receives a compact evidence packet and a small diff. It needs disciplined defect detection and severity calibration, but not broad repository exploration or code generation. |
| `reviewer` | Strong analytical and reasoning model | The reviewer must independently detect correctness, security, architecture, regression, and test-coverage problems without editing code. Analytical precision and calibrated severity are more important than generation speed. |
| `tester` | Fast, cost-efficient coding model | Test work is usually narrower and more repetitive: translate acceptance criteria into scenarios, add focused tests in known locations, and report deterministic results. A reliable smaller model can often do this efficiently, provided it follows constraints and handles the target stack well. |
| `delivery` | Deterministic, low-variance, cost-efficient tool-use model | Delivery operations are intentionally narrow and protected by deterministic scripts. The model should follow exact instructions, preserve arguments and file lists, and stop after one approved operation; creative implementation ability is unnecessary. |

These are defaults for role design, not guarantees. Increase model capability when the repository, language, security profile, or ticket complexity demands it. A model assigned to any agent must support the tool-calling behavior required by that agent.

### Configure a model in an agent definition

Agent models are configured in YAML frontmatter. The following values are placeholders; replace them with exact IDs copied from `/models`.

For the orchestrator:

```yaml
---
description: Plans and coordinates the human-gated engineering workflow without implementing production code directly
mode: primary
model: provider-id/frontier-reasoning-model-id
color: "#4f8cff"
steps: 30
permissions:
  # Existing orchestrator permissions remain here.
---
```

For the developer:

```yaml
---
description: Implements only an approved plan and reports any evidence that invalidates it
mode: subagent
model: provider-id/frontier-coding-model-id
color: "#36b37e"
steps: 40
permissions:
  # Existing developer permissions remain here.
---
```

Use the same `model` field in `diagnostician.md`, `quick-fix.md`, `quick-reviewer.md`, `reviewer.md`, `tester.md`, or `delivery.md` when those agents need explicit overrides. Model selection does not change permissions, step limits, approval requirements, read-only boundaries, classifier limits, diagnostic confirmation rules, or delivery safeguards.

### Distribution default versus consumer customization

Choose the configuration location deliberately:

- Edit `template/.opencode/agents/<agent-id>.md` in this distribution when the model policy should become the versioned default for future consumer installations. Treat that choice as a compatibility decision, update the distribution version, document the provider requirement, and validate a fresh consumer.
- Edit `.opencode/agents/<agent-id>.md` inside an installed consumer when the assignment applies only to that repository or clone. The change takes effect for that consumer, but it modifies a hash-managed workflow file.

The updater intentionally reports a conflict when an installed agent definition no longer matches its recorded hash. It never overwrites a consumer-specific model assignment. Before updating such an installation, compare the new distribution agent with the customized file and reapply the desired `model` field during a reviewed manual merge.

For the least maintenance and widest portability, leave the base distribution unpinned and add explicit model overrides only where the role, repository, or organization has a stable provider requirement.

## Skills

Skills are discovered from `.opencode/skills/` and loaded on demand.

### Core workflow skills

- `repo-bootstrap`: bounded repository inspection and project-configuration proposal.
- `project-profiler`: deterministic structural evidence, module candidates, and refresh fingerprint.
- `project-skill-builder`: minimal evidence-backed composition of built-in and project-specific skills.
- `project-context`: validates `.ai/project.json`, reads project rules, resolves affected modules, and loads only their context skills.
- `ticket-analysis`: converts requirements into traceable, testable acceptance criteria.
- `production-diagnosis`: defines sanitized evidence, bounded hypotheses, falsification, confirmation, blocked outcomes, and implementation handoff.
- `implementation-plan`: produces the required human-approvable plan.
- `workflow-state`: persists approved artifacts and enforces legal resumable transitions across sessions.
- `fast-path`: classifies low-risk work, enforces minimal context and diff budgets, and defines the one-correction escalation policy.
- `quality-gate`: invokes the managed runner and records schema-valid, exit-derived command evidence.
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

`.ai/project.json` is the machine-readable source of truth after bootstrap. It must validate against `.ai/project.schema.json`; `.ai/scripts/validate-project.ps1` performs that JSON Schema check plus repository-relative module-path, directory, context-skill, duplicate-ID, and multiline-command checks. Profiled projects additionally validate the persisted profile and generated-skills schemas, all evidence paths, skill frontmatter and required sections, module ownership, fingerprint consistency, and current structural drift.

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
  "fastPath": {
    "enabled": true,
    "maximumFiles": 3,
    "maximumLines": 120,
    "maximumProductionFilesForDiagnosis": 2,
    "maximumTestFilesForDiagnosis": 2,
    "maximumCorrectionIterations": 1
  },
  "diagnostics": {
    "maxHypothesisIterations": 3,
    "requireReproduction": false,
    "commands": []
  },
  "profile": {
    "repositoryFingerprint": "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
    "analyzedAtUtc": "2026-09-01T18:00:00Z",
    "source": ".ai/project-profile.json",
    "generatedSkillsManifest": ".ai/generated-skills.json"
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
        "architecture-vertical-slice",
        "project-orders-api"
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
| `path` | Existing working directory relative to the repository root; absolute and escaping paths are rejected. |
| `languages` | Languages supported by repository evidence. |
| `frameworks` | Frameworks supported by manifests or source evidence. |
| `architectures` | Confirmed or explicitly approved architecture identifiers. |
| `contextSkills` | Exact stack and architecture skills loaded for this module. |
| `quality` | Ordered command arrays for every deterministic gate phase. |

The optional top-level `profile` block binds project configuration to the approved deterministic profile and generated-skills manifest. Existing configurations without profiling remain schema-compatible; rerun `/ai-bootstrap` deliberately to add personalization, then use `/ai-refresh` for later structural changes.

Every quality phase is required in the JSON shape, even when its command array is empty.

Run the validator manually after a reviewed project-configuration change:

```powershell
pwsh -NoProfile -File .ai/scripts/validate-project.ps1
```

### Review policy

`review.maxIterations` accepts values from 1 through 3. A BLOCKER or HIGH finding makes the review verdict fail and requires correction plus a complete gate rerun before another review.

The optional diff budget compares actual implementation scope with the approved estimate:

- `filesMultiplier` defaults to 2.
- `linesMultiplier` defaults to 3.

The developer stops and reports scope expansion when actual changed files exceed the configured file multiple or changed lines exceed the configured line multiple.

### Fast-path policy

`fastPath` is optional. When omitted, the fast-path skill uses the schema defaults shown above. Set `enabled` to `false` when a repository requires the standard workflow for every change.

| Field | Allowed value | Meaning |
| --- | --- | --- |
| `enabled` | Boolean | Enables or disables fast-path classification for the repository. |
| `maximumFiles` | 1 through 3 | Maximum total files in both the estimate and final diff. |
| `maximumLines` | 1 through 120 | Maximum added plus deleted lines in both the estimate and final diff. |
| `maximumProductionFilesForDiagnosis` | 1 through 2 | Maximum production files read during bounded diagnosis. |
| `maximumTestFilesForDiagnosis` | 1 through 2 | Maximum test files read during bounded diagnosis. |
| `maximumCorrectionIterations` | Exactly 1 | The single correction allowed before standard-workflow escalation. |

These numeric settings only tighten scope. Risk exclusions are fixed by the fast-path skill and classifier and cannot be enabled through project configuration.

### Production-diagnosis policy

`diagnostics` is optional. It controls the separate read-only workflow for incidents with an unknown cause; it does not loosen agent permissions or allow production access.

| Field | Allowed value | Meaning |
| --- | --- | --- |
| `maxHypothesisIterations` | 1 through 3 | Maximum number of persisted diagnostic conclusions, including blocked outcomes and the final result. |
| `requireReproduction` | Boolean | When true, confirmation requires reproduction status `REPRODUCED` or `PARTIAL`; otherwise independent causal evidence may be sufficient. |
| `commands` | Array of single-line commands | Optional local inspection or reproduction commands. Every execution still uses normal shell approval and must remain local and non-mutating. |

Do not place production connection commands, secret retrieval, delivery operations, Git mutations, deployment tools, rollback commands, restarts, data repair, or infrastructure mutations in `diagnostics.commands`. Project validation rejects multiline commands and known Git, GitHub, Kubernetes, Terraform, and Azure deployment mutations. This static check is defense in depth, not proof that an arbitrary command is safe; the orchestrator must still explain the exact command and obtain approval.

## Deterministic quality gates

Quality gates are executable policy, not a reporting convention. Agents invoke the managed script instead of running a hand-written command sequence or composing a verdict:

```powershell
pwsh -NoProfile -File .ai/scripts/run-quality-gates.ps1 -ModuleId api
```

Use a comma-separated value for multiple affected modules. Omitting `-ModuleId` runs every configured module. The runner validates `.ai/project.json`, writes one artifact atomically to `.ai/runtime/gates.json`, validates that artifact against `.ai/quality-gates.schema.json`, and exits with:

| Exit code | Meaning |
| --- | --- |
| `0` | Every configured command for every selected module passed. |
| `1` | A command failed, timed out, was interrupted, or the worktree changed during verification. |
| `2` | At least one selected module has no configured quality command. |
| `3` | Trustworthy evidence could not be produced because configuration, schema, repository, or runner execution failed. |

For each selected module, commands run with the module's `path` as the working directory and in this fixed order:

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
- A stable worktree fingerprint is required from the beginning through the end of the runner execution.

The gate stops a module after its first failure unless the user explicitly requests a full diagnostic run. Remaining commands are reported as `NOT RUN`.

Each command record contains the exact command, module, phase, working directory, exit code, duration, timeout flag, status, bounded stdout and stderr, and an output-truncation flag. Output is capped to prevent unbounded run artifacts, but the exit code always remains authoritative.

The agent may diagnose a failure, but it must not silently change commands, append flags, skip required checks, weaken assertions, delete failing tests, suppress warnings, or edit `.ai/runtime/gates.json` merely to produce a passing result.

`workflow-state.ps1 -Action RecordGates` does not trust the supplied `-Verdict`. Before advancing state, it independently validates:

- the gate JSON Schema;
- the current `.ai/project.json` hash;
- the current runner hash;
- configured command counts and command-derived module verdicts;
- the overall verdict derived from module evidence;
- worktree stability during the gate;
- the current worktree fingerprint; and
- the workflow control-plane fingerprint captured when the run started.

Malformed, fabricated, stale, manually edited, or mismatched evidence is rejected. Before review, accepted evidence is copied and hashed into the active run. Subsequent review and delivery transitions continue verifying HEAD, the exact worktree, and the protected control plane.

## Control-plane protection

The installed workflow treats these paths as its control plane:

- `AGENTS.md`
- `opencode.json`
- `.ai/**`, excluding transient `.ai/runtime/**` and canonical `.ai/runs/**` from the fingerprint payload
- `.opencode/**`

The `developer` agent has explicit edit denials for all control-plane paths. The `quick-fix` agent can stage ordinary requirement, plan, and review inputs under `.ai/runtime/`, but cannot edit `gates.json`, canonical runs, project policy, scripts, schemas, agents, commands, or skills. Shell rules deny commands that name protected paths and reopen only the exact managed classifiers, state transition, and quality-runner commands required by each role.

Permissions prevent normal direct edits; persisted fingerprints provide deterministic detection. At run creation, `workflow-state.ps1` hashes every protected control-plane file. Plan approval, implementation, gate recording, review, correction, and commit transitions stop if that hash changes. A legitimate workflow configuration change therefore requires a separately approved configuration task and a new run; it cannot be smuggled into an application implementation.

## Gated delivery workflow

Delivery is opt-in and separated from implementation. The `delivery` agent is the only agent that can request the narrow permissions needed for branch creation, staging, commit, push, or draft PR creation. It operates through managed scripts and stops after one approved mutation. A branch is created after plan approval and before implementation; commit, push, and PR creation use the persisted run after it reaches `READY_FOR_DELIVERY`.

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
- persisted run status, artifact hashes, base/current SHA, and worktree fingerprint

It reports `READY FOR DELIVERY` only when every required input is current. A missing plan, stale gate result, BLOCKER/HIGH finding, changed SHA, unrelated file, protected environment file, or scope mismatch produces `DELIVERY NOT READY`.

### Create a feature branch

```text
/branch
```

The command proposes one branch name and waits for approval. It requires one validated `PLAN_APPROVED` run and a clean working tree. The managed script validates the ref name, refuses an existing branch, and blocks shared/protected names including `main`, `master`, `develop`, `development`, `trunk`, and `release`.

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
- Record the resulting commit only when its patch exactly matches the gate-reviewed worktree fingerprint.
- Stop after reporting the commit SHA; do not push automatically.

### Publish a feature branch

```text
/publish
```

Before approval, the command displays the remote name and URL, branch, HEAD SHA, and exact remote ref. The managed publisher requires a completely clean working tree and performs only a normal push of the current feature branch.

It never uses force, force-with-lease, tags, ref deletion, or a protected/shared branch. If the normal push is rejected because the remote changed, the workflow stops and reports the conflict instead of retrying with a more permissive command.

Push approval does not authorize PR creation.

The approved push result is persisted before draft-PR creation can continue.

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

The draft PR URL, base, head, and title are persisted as the terminal workflow record. A draft PR remains manually reviewed and manually merged.

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
- Denies reading or editing `.env` and `.env.*` files, plus common credential and private-key file patterns.
- Allows reading `.env.example` and asks before editing it.
- Denies access outside the repository.
- Allows skills.
- Requires approval for shell commands by default.
- Requires approval for Git diff, log, and show commands because their output can be redirected by the underlying Git CLI.
- Denies direct staging, branch mutation, commit, push, PR mutation, merge, rebase, reset, clean, tag, release, secret, variable, and workflow-dispatch commands.
- Denies direct invocation of managed mutation scripts for every agent except `delivery`.
- Denies common infrastructure mutations such as Terraform apply/destroy, Kubernetes apply/delete, and Azure deployments.

Agent-specific permissions further restrict the orchestrator, diagnostician, developer, quick-fix, reviewer, tester, and delivery agent. Developer and quick-fix deny control-plane edits; quick-fix also denies direct gate-evidence writes. The diagnostician and both review agents deny every shell command and receive an immutable evidence packet rather than rediscovering or mutating the repository. The diagnostician additionally denies every edit and subagent action. The delivery agent's later, narrow `ask` rules override only the exact managed operations and still require a permission decision.

### Human gates

Explicit approval is required before:

- Writing bootstrap configuration.
- Starting another diagnostic iteration after `DIAGNOSIS_BLOCKED` with newly supplied evidence.
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

`/ai-bootstrap` and installation/update tooling validate `.ai/project.json` against its JSON schema before accepting it. The validator also rejects duplicate module identifiers, missing referenced skills, multiline quality commands, absolute module paths, and paths that escape the repository. Profiled configurations additionally require matching profile and generated-skill fingerprints, valid evidence paths, correct module ownership, and structurally current repository evidence.

Production diagnoses have an additional deterministic boundary. The schema and validator require sanitized evidence records, internally consistent references, exactly one supported root cause for confirmation, a regression-test obligation, explicit missing evidence for blocked results, and false safety flags for production mutation and secret access. Canonical diagnosis artifacts are copied, hashed, and revalidated on every state transition and implementation handoff.

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
- When pinning a model, use an exact `provider-id/model-id` obtained from OpenCode `/models`, document the provider dependency, and validate the agent in a fresh consumer repository.

### Change the consumer payload

Any file under `template/` becomes a managed file in new installations. Existing installations receive it through `update.ps1` only when the hash safety rules allow the update.

When changing the payload or distribution behavior:

1. Update `VERSION` using semantic versioning.
2. Update `workflow.manifest.json` to the same version.
3. Update schemas when a contract changes.
4. Update this README.
5. Run `scripts/validate.ps1`.
6. Test fresh Local, Shared, and hybrid installs; a fresh project; mode migration; a clean update; and a locally modified update conflict.

## Validation and release checklist

Before releasing a change:

- [ ] `VERSION` and `workflow.manifest.json` match.
- [ ] The distribution root contains no `AGENTS.md`, `opencode.json`, `.ai/`, or `.opencode/`.
- [ ] `scripts/validate.ps1` passes.
- [ ] `install.ps1 -DryRun` reports conflicts without writing.
- [ ] A fresh Local installation leaves the pre-existing Git-visible status unchanged.
- [ ] Approved project profiles, generated-skills manifests, and `project-*` skills remain Git-invisible in Local mode.
- [ ] Local installation preserves unrelated `.git/info/exclude` content and ignores only exact workflow-owned paths.
- [ ] Local installation rejects paths that are already tracked.
- [ ] A Shared installation leaves workflow files Git-visible.
- [ ] A hybrid installation exposes only `.ai/project-rules.md` and generated `.ai/project.json` from the workflow payload.
- [ ] A fresh installation creates schema-version-2 metadata with the correct mode and exclusion paths.
- [ ] `new-project.ps1 -ListPresets` lists every supported preset.
- [ ] At least one offline preset is created and its tests pass.
- [ ] `update.ps1 -DryRun` succeeds for an unchanged installation.
- [ ] Local-to-Shared and untracked Shared-to-Local migrations preserve unrelated Git exclude rules.
- [ ] An update aborts when a managed file was locally modified.
- [ ] OpenCode discovers `orchestrator`, `developer`, `reviewer`, `tester`, and `delivery` in a consumer repository.
- [ ] OpenCode discovers `diagnostician`, `/diagnose`, and `production-diagnosis`.
- [ ] OpenCode discovers `quick-fix`, `quick-reviewer`, `/quick-fix`, and `/small-task` in a consumer repository.
- [ ] OpenCode discovers `/ai-refresh`, `project-profiler`, and `project-skill-builder`.
- [ ] Deterministic profiling emits a schema-valid stable fingerprint and excludes workflow-owned paths.
- [ ] Generated skills require matching module ownership, evidence, frontmatter, mandatory sections, and profile fingerprint.
- [ ] Structural marker drift blocks project validation until an approved `/ai-refresh`.
- [ ] The managed quality-gate runner derives command and overall verdicts from actual exit codes and emits schema-valid evidence.
- [ ] `RecordGates` rejects fabricated, stale, manually edited, runner-mismatched, project-mismatched, and worktree-mismatched evidence.
- [ ] Developer and quick-fix deny control-plane edits, and a changed control-plane fingerprint invalidates the active run.
- [ ] The reviewer remains effectively read-only.
- [ ] The reviewer and quick reviewer deny shell access and receive only the evidence packet.
- [ ] The diagnostician denies edit, shell, and subagent access and receives only sanitized evidence.
- [ ] Diagnostic state persists blocked, confirmed, and escalated outcomes; enforces the one-to-three iteration ceiling; and rejects unsupported confirmation.
- [ ] Only a validated `ROOT_CAUSE_CONFIRMED` run can seed a standard run with `sourceRunId`.
- [ ] The quick reviewer remains read-only and the quick-fix agent cannot delegate to standard implementation agents.
- [ ] The fast-path classifier accepts a compliant estimate and actual diff, and returns exit code 3 for every excluded risk and exceeded limit.
- [ ] Actual fast-path scope is derived from the Git diff and untracked files, not agent-supplied counts.
- [ ] Fast-path work escalates after one correction or whenever the final diff loses eligibility.
- [ ] Non-delivery agents cannot invoke managed mutation scripts.
- [ ] The commit-message validator accepts valid Conventional Commits and rejects non-conventional or AI-attributed messages.
- [ ] Branch creation rejects protected/shared names and a dirty working tree.
- [ ] Publishing uses a normal feature-branch push and has no force fallback.
- [ ] Draft PR creation requires explicit base/head, an upstream branch, and the canonical template.
- [ ] The repository and consumer pull-request templates have identical hashes.
- [ ] `tests/Run-Tests.ps1` passes, including state transitions, schema rejection, Local-install invisibility, fast-path derivation, commit-fingerprint verification, and updater conflict detection.
- [ ] The CI workflow runs the distribution validation and test suite on a clean Windows runner.
- [ ] The distribution root is not detected as a consumer configuration.
- [ ] No secrets, generated credentials, or local `.env` files are included.

## Measuring token efficiency and quality

The workflow is designed to reduce avoidable context and handoff cost, not to promise a fixed provider bill. It does that by selecting only relevant project/stack/architecture skills, using a bounded fast path for low-risk work, giving reviewers a narrow evidence packet, and limiting correction cycles. Use the evaluation contract to measure whether those controls work for your own models and repositories.

Record one completed task per JSON document that validates against [`evaluations/benchmark.schema.json`](evaluations/benchmark.schema.json). Include the actual workflow path, provider-reported or manually captured input/output tokens, cost if available, elapsed time, correction count, pass/fail result, and escaped defect count. Do not invent measurements or compare tasks with materially different scope as if they were equivalent.

Summarize a directory of recorded benchmarks with:

```powershell
pwsh -NoProfile -File scripts/summarize-evaluations.ps1 -Path .\evaluations\results
```

The report groups manual, standard, and fast-path runs, totals usage and outcomes, and calculates fast-path savings only when both fast-path and standard observations exist. [`evaluations/README.md`](evaluations/README.md) defines the field meanings and a safe collection procedure.

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

### Local installation requires a Git repository

Local mode stores its ignore rules in the clone's `.git/info/exclude`, so the target must be an initialized repository and must be the repository root. Initialize the application repository first, target its root, or explicitly use `-Mode Shared` when local Git exclusion is not wanted.

### Local installation reports tracked paths

Git ignore rules cannot hide files that are already tracked. The installer and updater therefore refuse Local mode when a locally excluded path is present in the index. Keep `Shared` mode, or deliberately remove the relevant path from version control using your normal repository-review process before retrying. The workflow never untracks it automatically.

### Workflow files appear after cloning the application elsewhere

This is expected for Local mode: `.git/info/exclude` is clone-specific and is not transferred by Git. Install the workflow separately in each clone that needs OpenCode support.

### Switch between Local and Shared mode

Use `update.ps1 -Mode Local` or `update.ps1 -Mode Shared`. The updater modifies only the block delimited by `# BEGIN ai-engineering-workflow` and `# END ai-engineering-workflow`; malformed or duplicate blocks cause a safe failure instead of an overwrite.

### Update reports `locally modified`

The target file no longer matches the hash recorded at installation. Preserve the local intent, compare it with the new template, and merge deliberately. The updater will not choose a version for you.

### Update metadata is missing

The target was not installed by the current version of `install.ps1`, or `.ai/workflow-installation.json` was removed. Automatic update is unavailable. Perform a reviewed migration or a clean reinstall instead of inventing baseline hashes.

### `BOOTSTRAP NOT APPLICABLE`

You launched `/ai-bootstrap` in the workflow distribution repository. Install or create a consumer project, change to that directory, start OpenCode there, and run the command again.

### `NO PROJECT MODULES DETECTED`

Bootstrap found no source/build evidence that can support a valid module. Add or generate the application first. This is expected for the `empty` preset before application files exist.

### `PROJECT_INVALID` or `PROJECT_VALID` is not produced

Run the deterministic validator directly from the consumer repository:

```powershell
pwsh -NoProfile -File .ai/scripts/validate-project.ps1
```

Correct the reported schema, module-path, skill, or quality-command problem. Do not edit a canonical run to bypass the validator.

### Repository structure has drifted from the approved profile

Run `/ai-refresh`. Review the changed manifests, language set, module candidates, architecture markers, CI/CD, or convention evidence and explicitly approve any project-context or generated-skill update. Do not copy the new fingerprint into `.ai/project.json` manually; the approved refresh must update the profile, manifest, configuration, and affected skills as one validated proposal.

### A workflow-state transition or fingerprint check fails

Use `/run-status <run-id>` to identify the current legal state and validate artifact hashes. A changed `HEAD`, changed post-gate diff, changed control-plane fingerprint, or a commit whose patch differs from the reviewed gate fingerprint is an intentional stop. Restore an unauthorized control-plane change; for an approved configuration change, start a new run. For application changes, create a new plan or return through an explicitly approved correction cycle.

### `DIAGNOSIS_BLOCKED`

The current sanitized evidence cannot distinguish the remaining hypotheses. Read `missingEvidence` in the canonical diagnosis artifact and provide only the smallest requested log, metric, trace, deployment fact, timestamp, or reproduction result. Do not edit the run artifact. After explicit approval, the orchestrator uses `BeginDiagnosticIteration` and records a new validated conclusion. If the configured limit is exhausted, escalate rather than guessing.

### A diagnosis cannot be handed to `/ticket`

Run `/run-status <diagnostic-run-id>` and require `ROOT_CAUSE_CONFIRMED`. The handoff rejects blocked, escalated, missing, schema-invalid, hash-mismatched, or tampered diagnoses. Use the exact syntax `/ticket diagnosis:<run-id>`; do not copy a root-cause sentence into a new ticket and discard its evidence provenance.

### `ESCALATE_STANDARD`

The deterministic fast-path classifier found an exceeded limit, missing prerequisite, or excluded risk. This is a routing verdict, not a failed implementation. Preserve the requirement, evidence, proposed files, and verification commands, then continue with `/ticket` and the standard workflow.

### Fast path was invalidated after implementation

The final diff no longer matches the approved fast-path estimate or a new risk appeared. Do not hide files, split a coherent change artificially, or weaken verification to satisfy the classifier. Stop fast-path work and provide the actual diff, gate results, review findings, and escalation reason to the standard orchestrator.

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
- Production diagnosis analyzes repository evidence and sanitized evidence supplied by the user; it does not connect to observability platforms or production systems automatically.
- Diagnostic confirmation reduces speculation but does not replace incident command, security response, compliance, data-recovery, or production-operations procedures.
- File installation and updates perform full conflict preflight, but are not transactional against unexpected filesystem failures.
- Local installations are intentionally clone-specific. A new clone must install the workflow again.
- Local mode depends on `.git/info/exclude`; it cannot hide workflow paths that are already tracked.
- Actual fast-path scope is derived from Git changes and untracked files; task-level semantic risks can still require agent judgment and conservative escalation.
- Repository profiling is deterministic, but framework, architecture, and convention interpretation still uses model judgment and requires explicit human approval.
- Evaluation collection is intentionally manual and provider-neutral; the workflow cannot automatically retrieve token or cost telemetry from every OpenCode provider.
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

- [OpenCode rules and instructions](https://opencode.ai/docs/rules/)
- [OpenCode agents](https://opencode.ai/docs/agents/)
- [OpenCode models](https://opencode.ai/docs/models/)
- [OpenCode providers](https://opencode.ai/docs/providers/)
- [OpenCode commands](https://opencode.ai/docs/commands/)
- [OpenCode skills](https://opencode.ai/docs/skills/)
- [OpenCode configuration](https://opencode.ai/docs/config/)

Because OpenCode V2 is still evolving, keep the workflow versioned, run deterministic distribution validation, and smoke-test a consumer repository before adopting a new CLI release.
