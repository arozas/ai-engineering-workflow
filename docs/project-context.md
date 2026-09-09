# Project context and personalization

## Why bootstrap exists

The distributed agents are stack- and architecture-agnostic. An existing repository supplies the facts: module boundaries, languages, frameworks, architecture signals, build systems, tests, CI/CD, and local conventions. `/ai-bootstrap` converts those facts into explicit configuration after human review.

Installation remains deterministic and model-independent. Personalization is a separate, visible, approval-gated phase.

## Deterministic profile

`workflow_profile_project` inventories Git-visible application content while excluding workflow paths. It records:

- relevant files and language counts;
- build, workspace, dependency, lock, and test manifests;
- candidate module roots;
- architecture directory markers;
- CI/CD and convention files;
- manifest hashes and a structural fingerprint.

During proposal the final profile is not written. `/ai-bootstrap` delegates draft creation to the deterministic `workflow_bootstrap_prepare` tool, backed by `.ai/scripts/prepare-bootstrap-proposal.ps1`. The preparer profiles the repository, applies conservative inference rules, writes `.ai/bootstrap-proposal/`, and validates the draft as a dry run.

The preparer is idempotent. When an existing valid draft has the same structural fingerprint it returns `BOOTSTRAP_PROPOSAL_CURRENT` and does not rewrite user edits. Structural drift returns `BOOTSTRAP_PROPOSAL_STALE`. Only an explicit `/ai-bootstrap --force` replaces the draft.

If OpenCode does not expose `workflow_bootstrap_prepare`, bootstrap may use exactly one controlled fallback: `pwsh -NoProfile -File .ai/scripts/prepare-bootstrap-proposal.ps1`. The fallback owns profiling and draft generation. It is not permission to browse the repository manually.

Empty repositories stop with `NO PROJECT MODULES DETECTED`. The distribution repository stops with `BOOTSTRAP NOT APPLICABLE`. Bootstrap never invents a module to satisfy the schema.

## Proposal contract

Before approval, bootstrap writes a durable draft proposal under `.ai/bootstrap-proposal/` instead of using the conversation as the only working buffer:

```text
.ai/bootstrap-proposal/
├── project-profile.json
├── project.json
├── project-rules.md
├── generated-skills.json
├── evidence-packet.json
├── evidence.md
├── approval.md
└── skills/
    └── project-<module-id>/
        └── SKILL.md
```

The draft `project.json` uses final installed paths such as `.ai/project-profile.json`, `.ai/generated-skills.json`, and `.opencode/skills/project-<module-id>/SKILL.md`. Deterministic inference is deliberately conservative:

1. Languages are derived independently for each module from all Git-visible files in that module.
2. Test commands require actual test files or a test project identified from project content, never from an application filename containing `Test`.
3. `dotnet format` requires an established repository or CI command; `.editorconfig` alone is insufficient.
4. .NET quality commands target the module's single solution explicitly. When no solution exists, one project file may be targeted; multiple solutions or multiple projects without a unique solution remain unconfigured for human review. This prevents `MSB1011` after a test project is added beside an application project.
5. Node package-manager commands follow lockfiles and declared package scripts.
6. Unsupported stacks remain explicit and do not create dangling generated-skill references.
7. Timestamps are emitted and checked as RFC 3339 independently of machine culture.

`evidence.md` records the structural profile, module inference, declared bootstrap intent, risks, and review instructions. `evidence-packet.json` lists at most three representative production and three representative test files per module. It is the complete exploration boundary for optional enrichment.

Run `/ai-bootstrap-enhance` only when a stronger model should refine project-specific rules from representative source. The `bootstrap-enricher` reads each listed file at most once, cannot use shell, search, web, or subagents, cannot change deterministic modules, quality commands, or fingerprints, and may perform only one correction after dry-run validation. Large models retain room for useful semantic refinement without making the default small-model path open-ended.

Arrays remain empty when evidence does not establish a command or technology. Confidence communicates evidence strength; it does not turn a weak inference into a rule.

After writing the draft, bootstrap runs a dry validation through `workflow_bootstrap_apply`. The chat response stays compact: fingerprint, modules, selected skills, files written, risks, and validation status.

After approval, `/ai-bootstrap-apply` persists the profile again. Structural drift blocks the write. It then writes only approved project context and requires `PROJECT_VALID`.

## `.ai/project.json`

The file is the installed machine-readable source of truth. Its top-level sections are version/name, `fastPath`, `review`, `diagnostics`, `profile`, `modules`, and optional `integrations`.

Each module defines:

```json
{
  "id": "api",
  "path": "src/api",
  "languages": ["csharp"],
  "frameworks": ["aspnetcore"],
  "architectures": ["vertical-slice"],
  "contextSkills": [
    "stack-dotnet",
    "architecture-vertical-slice",
    "project-api"
  ],
  "quality": {
    "restore": ["dotnet restore Api.sln"],
    "build": ["dotnet build Api.sln --no-restore"],
    "lint": ["dotnet format Api.sln --verify-no-changes"],
    "typecheck": [],
    "test": ["dotnet test Api.sln --no-build"],
    "e2e": []
  }
}
```

Module paths are repository-relative and may be `.` for a root application. Absolute and escaping paths are rejected. IDs are stable kebab-case values used in approvals and evidence.

Quality commands must be single-line commands proven by repository evidence such as package scripts, solutions, build files, or CI. Bootstrap does not infer a conventional command merely because a language is present. Task-specific .NET commands added later in `verification.json` should reuse the configured explicit solution or project target; a bare `dotnet test` in a directory that can contain multiple project files is not approval-ready.

## Project rules

`.ai/project-rules.md` holds human-readable local conventions:

- dependency direction and ownership;
- public API/compatibility expectations;
- naming and directory conventions;
- test placement and fixture rules;
- generated-code and migration boundaries;
- documentation obligations;
- repository-specific restrictions.

Rules cite repository evidence or explicit user intent. They should not duplicate generic stack guidance or record guesses as mandatory behavior.

## Generated project skills

Generic skills answer how a stack or architecture is normally handled. Generated project skills describe what this repository demonstrably does.

Every generated skill includes stable frontmatter, module scope, evidence/confidence, concrete rules, quality/testing guidance, and unknowns. `.ai/generated-skills.json` maps it to its module, path, composition, reason, evidence, and approved fingerprint.

Validation rejects missing files, wrong names, dangling module IDs, stale fingerprints, invalid evidence paths, and structural drift.

## Stack and architecture composition

Built-in stack profiles are `stack-dotnet`, `stack-java`, `stack-node`, `stack-python`, and `stack-react`. Architecture skills are `architecture-clean`, `architecture-event-driven`, `architecture-hexagonal`, `architecture-vertical-slice`, and `architecture-simple-layered`.

They load only for affected configured modules. Architecture labels require evidence such as dependency direction, ports/adapters, slices, or handlers/events. Directory names alone normally justify only low confidence. Use `architecture-simple-layered` for conventional controller/model/repository applications when stronger architecture evidence is missing.

## Refreshing context

Run `/ai-refresh` after structural changes: a new module/workspace, framework migration, new architecture boundary, replaced build/test tooling, changed CI commands, or moved manifests/source roots.

Refresh compares one read-only profile with the persisted one. If unchanged it stops. On structural drift it uses the deterministic forced preparer to replace only the draft proposal, after which the same optional enrichment and explicit apply steps are available. Ordinary source growth inside known structure does not require regeneration.

## Azure DevOps work items

Configure the optional read-only integration:

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

When `/ticket` receives a work-item identifier, the orchestrator retrieves it read-only and normalizes title, description, acceptance criteria, links, and relevant history. Credentials are not stored in project context; authentication is established externally through supported Azure tooling.

The integration does not update work items, add comments, change states, or create PRs.

## Safe diagnostics configuration

`diagnostics.commands` may contain only repository-evidenced, single-line local inspection or reproduction commands. It must never contain production connections, secret retrieval, Git/delivery mutations, deployments, rollbacks, restarts, data repair, or infrastructure commands.

Default policy allows up to three hypothesis iterations and does not require reproduction. Repositories may require reproduction or lower the iteration count.
