# AI Engineering Workflow

A reusable, stack-agnostic engineering workflow for OpenCode V2. This repository is a versioned distribution that can be installed locally into an existing application repository or used to create a new project from a preset.

It converts tickets, specifications, written requirements, and unknown production incidents into evidence-based plans or diagnoses. Human approval gates implementation and every delivery mutation; deterministic tools validate project context, workflow state, quality commands, and evidence.

> [!IMPORTANT]
> This is the distribution repository, not an application repository. Run `/ai-bootstrap` only inside a consumer repository after installation.

## What it provides

- Repository profiling and an approval-gated, project-specific `.ai/project.json`.
- Selective stack, architecture, and generated project skills per module.
- Standard, fast-path, and production-diagnosis workflows.
- Persisted, hash-verified run state under local `.ai/runs/` records, with isolated staging under `.ai/runtime/<run-id>/`.
- An orchestrator plus specialized developer, tester, reviewer, diagnostician, quick-fix, delivery, bounded evidence-reader, and optional bootstrap-enricher agents.
- Deterministic quality gates bound to the exact modules, configured commands, and hashed run-specific verification approved with the plan.
- Reviewer-scoped structured evidence whose verdict is derived from findings and acceptance-criteria coverage.
- Read-only Azure DevOps work-item integration.
- Local-first installation that avoids workflow files in consumer commits by default.
- Guarded branch, Conventional Commit, push, and draft-PR operations with separate human approvals and independently verified evidence.

The workflow does not replace repository conventions, CI/CD, code ownership, or human judgment. Merge, history rewriting, release, deployment, secret handling, and cloud mutations remain manual and denied.

## Requirements

- Git.
- PowerShell 7 (`pwsh`).
- OpenCode V2 for running the installed agents and commands.
- The language runtimes and build tools required by the consumer project.
- Optional: GitHub CLI for guarded draft-PR operations and Azure CLI for Azure DevOps work-item retrieval.

## Install into an existing repository

Preview first:

```powershell
pwsh -NoProfile -File .\scripts\install.ps1 `
  -TargetPath "C:\path\to\application" `
  -Mode Local `
  -DryRun
```

Install locally:

```powershell
pwsh -NoProfile -File .\scripts\install.ps1 `
  -TargetPath "C:\path\to\application" `
  -Mode Local
```

`Local` is the recommended default. It installs the files into the working tree for OpenCode discovery and writes a managed block to the clone-local `.git/info/exclude`; it does not modify the tracked `.gitignore`. Use `Shared` only when the team intentionally wants to version the workflow in the consumer repository.

Then start OpenCode inside the consumer repository:

```powershell
cd "C:\path\to\application"
opencode2
```

Run:

```text
/workflow-doctor
/ai-bootstrap
```

The doctor reports PowerShell and duplicate OpenCode installations without changing the machine. Bootstrap then profiles the project deterministically, writes an editable draft plus a bounded evidence packet under `.ai/bootstrap-proposal/`, and keeps the chat response compact. A second call preserves a current draft; use `/ai-bootstrap --force` only when you explicitly intend to replace it. Review or edit the draft, optionally run `/ai-bootstrap-enhance` with a stronger model for one bounded source-informed pass, then run:

```text
/ai-bootstrap-apply
```

The apply step validates the draft, checks for repository drift, transactionally writes the approved project context, and requires `PROJECT_VALID`. A post-write validation failure restores every previous managed destination.

## Create a new project

List available presets:

```powershell
pwsh -NoProfile -File .\scripts\new-project.ps1 -ListPresets
```

Create and initialize a repository:

```powershell
pwsh -NoProfile -File .\scripts\new-project.ps1 `
  -Name "orders-service" `
  -ParentPath "C:\path\to\repos" `
  -Preset dotnet-webapi `
  -Architecture vertical-slice `
  -Mode Local `
  -InitializeGit
```

Project presets currently include `empty`, `dotnet-webapi`, `node-basic`, `python-basic`, and `react-vite`. Stack profiles and architecture presets are composable rather than embedded in agent prompts.

## Main commands

| Command | Purpose |
| --- | --- |
| `/workflow-doctor` | Report PowerShell and OpenCode runtime selection or duplicates without modifying the machine. |
| `/ai-bootstrap` | Profile an existing repository and write an editable context proposal under `.ai/bootstrap-proposal/`. |
| `/ai-bootstrap-enhance` | Optionally enrich the current draft from its bounded evidence packet without re-inventorying the repository. |
| `/ai-bootstrap-apply` | Validate and apply the approved bootstrap proposal. |
| `/ai-refresh` | Propose context updates after structural repository changes. |
| `/ticket` | Normalize a ticket/specification and propose a standard implementation plan. |
| `/implement` | Implement exactly one persisted, approved plan. |
| `/test` | Add focused tests and run the approved quality matrix. |
| `/review` | Perform independent read-only review. |
| `/quick-fix` | Handle an eligible, known-cause, low-risk bug through the bounded fast path. |
| `/small-task` | Handle eligible documentation, local configuration, or mechanical work. |
| `/diagnose` | Investigate an unknown production cause without modifying code or production. |
| `/run-status` | Validate and show one persisted run. |
| `/explain` | Produce a human-readable explanation of approved changes. |
| `/pr` | Draft PR content from the evidence. |
| `/delivery-check` | Evaluate readiness without mutating Git or GitHub. |
| `/branch`, `/commit`, `/publish`, `/pr-create` | Propose one guarded delivery mutation and require fresh approval. |

## Workflow at a glance

```text
requirement
   |
   +-- unknown production cause --> /diagnose --> confirmed evidence --> /ticket
   |
   +-- bounded low-risk work ------> /quick-fix or /small-task
   |
   +-- standard work --------------> /ticket
                                         |
                         proposed plan + verification manifest
                                         |
                                  human approval
                                         |
                               implementation + tests
                                         |
                       frozen merged deterministic quality matrix
                                         |
                               independent read-only review
                                         |
                                  ready for delivery
                                         |
                         separately approved delivery operations
```

The affected module IDs and `.ai/runtime/<run-id>/verification.json` are persisted when the plan is approved. The manifest is required even when empty and captures mandatory task-specific commands that do not yet exist in project configuration. `workflow_next` returns a compact status and legal next actions for resumed runs. The quality runner accepts only a run ID, reuses unchanged current evidence, reconstructs the configured-plus-run-specific matrix, and rejects stale configuration, altered manifests, omitted modules or commands, mismatched evidence, or worktree/control-plane drift.

## Documentation

Detailed guidance lives under [`docs/`](docs/README.md):

- [Architecture and design](docs/architecture.md)
- [Installation, updates, and new projects](docs/installation.md)
- [Standard, fast-path, diagnosis, and delivery workflows](docs/workflows.md)
- [Project profiling, configuration, stacks, architectures, and Azure DevOps](docs/project-context.md)
- [Permissions, typed tools, quality evidence, and threat model](docs/security.md)
- [Model roles, routing, context budgets, and token efficiency](docs/models-and-efficiency.md)
- [Extending the distribution, validation, testing, and release](docs/extending-and-validation.md)
- [Troubleshooting](docs/troubleshooting.md)

## Validate the distribution

```powershell
pwsh -NoProfile -File .\scripts\validate.ps1
pwsh -NoProfile -File .\tests\Run-Tests.ps1
pwsh -NoProfile -File .\scripts\smoke-opencode.ps1
```

The first two commands require Git and PowerShell 7 and form the required CI gate. The smoke test additionally requires the OpenCode V2 CLI package (`@opencode-ai/cli@beta`) and the V2 executable (`opencode2`) because this template uses OpenCode V2 permissions. It starts a local model-free server and prefers runtime agent, command, and typed-tool discovery. Some V2 preview builds return empty discovery payloads or omit the tool endpoint; the default local smoke names a static fallback instead of presenting it as runtime discovery. `-RequireRuntimeDiscovery` rejects every fallback. Installed workflows remain usable when typed tools are unavailable through role-scoped, approval-gated deterministic script fallbacks; no MCP server is required. Run `/workflow-doctor` to detect PowerShell or duplicate-OpenCode runtime problems. A separate compatibility workflow runs strict mode against an exact pinned package for manual/tag checks and probes the latest beta in a non-blocking scheduled canary. The isolated suite proves both state transports plus run-level staging, reviewer, branch, commit, remote publish, and draft-PR evidence binding.

## OpenCode references

- [Configuration](https://opencode.ai/v2/docs/config/)
- [CLI](https://opencode.ai/v2/docs/cli/)
- [Server and troubleshooting](https://opencode.ai/v2/docs/troubleshooting/)
- [Agents](https://opencode.ai/v2/docs/agents)
- [Permissions](https://opencode.ai/v2/docs/permissions)
- [Custom tools](https://opencode.ai/docs/custom-tools)
- [Commands](https://opencode.ai/v2/docs/commands/)
- [Skills](https://opencode.ai/v2/docs/skills/)

## License

Released under the [MIT License](LICENSE).
