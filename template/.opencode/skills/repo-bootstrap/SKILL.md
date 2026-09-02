---
name: repo-bootstrap
description: Inspect an application repository with a bounded evidence scan and propose module, stack, architecture, and quality configuration for approval
compatibility: opencode-v2
---

## Safety contract

Bootstrap is read-only until the user explicitly approves the complete proposal. Never infer a convention merely because it is fashionable. Existing files and executable project metadata are stronger evidence than directory names.

Load `project-profiler` and `project-skill-builder`. The installer remains deterministic and model-independent; repository personalization belongs to this approved bootstrap phase.

## Mandatory empty-repository fast path

The calling command should already have inventoried files outside `AGENTS.md`, `opencode.json`, `.ai/**`, and `.opencode/**`. If that inventory is empty, return `NO PROJECT MODULES DETECTED` immediately. Do not read more files or perform language-specific searches.

## Preflight classification

The repository is the distributable AI Engineering Workflow source when it contains `workflow.manifest.json`, `template/`, `presets/`, and `scripts/`, and has no independent application/service module supported by a build manifest and source evidence.

If this classification matches, stop immediately with `BOOTSTRAP NOT APPLICABLE`. Explain that `/ai-bootstrap` must run in an installed target repository. Do not propose `.ai/project.json`.

If no application module is supported after the inventory and manifest pass, stop with `NO PROJECT MODULES DETECTED`. The schema requires at least one real module; never invent one to satisfy it.

## Exploration budget

Use a bounded, non-repeating scan:

1. Reuse the caller's deterministic profile and repository inventory; do not run the profiler or create another equivalent inventory before approval.
2. Perform one manifest/configuration pass, reading at most 20 relevant manifests, workspace files, CI/CD files, and existing instruction files.
3. For each candidate module, read at most three representative source files and three representative test files, capped at 18 representative files overall.
4. Never read the same file twice and never repeat an equivalent glob, search, or directory listing.
5. Keep an exploration ledger of paths inspected and evidence still missing.
6. After these passes, produce the proposal or stop. Absence of evidence is a stop signal, not a reason for another search round.

## Inspect

Within the budget, look for repository/workspace markers, languages, frameworks, dependency direction, exact quality commands, tests, migrations, CI/CD, infrastructure, module boundaries, and nested instructions.

Reuse the profile returned by the calling command: inventory, manifest hashes, module candidates, language counts, structural markers, tests, CI, conventions, and structure fingerprint. Do not repeat equivalent searches already answered by the profile. The only second profiler execution is the approved persistence step, which also detects drift between proposal and write.

Common evidence includes `*.sln`, `*.csproj`, `global.json`, `package.json`, lockfiles, `pnpm-workspace.yaml`, `pom.xml`, `build.gradle*`, `pyproject.toml`, `requirements*.txt`, `go.mod`, `Cargo.toml`, `Dockerfile*`, and pipeline files. This list is guidance, not a closed list.

When `.ai/bootstrap-input.json` exists, read it once. Treat requested stacks and architectures as explicit user intent, not as proof that the generated code follows them. Report any mismatch.

## Propose

For an applicable repository, present:

1. Detected repository shape and modules.
2. Technology and architecture per module with `HIGH`, `MEDIUM`, or `LOW` confidence and evidence.
3. Exact quality commands and the source proving each command. Leave an array empty when no command is established.
4. Selected `contextSkills` per module.
5. Risks, unknowns, and questions.
6. A complete `.ai/project.json` conforming to `.ai/project.schema.json`.
7. Proposed project-rule changes.
8. A complete `.ai/generated-skills.json`, including an empty `skills` array when no custom skill is justified.
9. Full proposed contents of each minimal `project-<module-id>` skill, with evidence and confidence.
10. Exploration ledger summary and deterministic structure fingerprint.
11. A `diagnostics` policy. Default to three hypothesis iterations, no mandatory reproduction, and no commands unless repository evidence establishes safe local inspection or reproduction commands.

Wait for explicit approval. On approval, rerun `workflow_profile_project` with `persist: true`; stop if its fingerprint differs from the approved proposal. Then write only the approved `.ai/project.json`, `.ai/project-rules.md`, `.ai/generated-skills.json`, and approved project skill files. Run `workflow_validate_project` and report `PROJECT_VALID` before summarizing corrections made by the user. A failed deterministic validation blocks bootstrap completion.

Unless the user selects stricter limits, propose the schema defaults for `fastPath`: enabled, at most three files, at most 120 added-plus-deleted lines, at most two production and two test files during diagnosis, and exactly one correction iteration. Never propose values above the schema maxima.

For `diagnostics.commands`, use only single-line commands already supported by repository evidence and safe for local inspection or reproduction. Never infer or propose production connections, secret retrieval, Git or delivery mutations, deployments, rollbacks, restarts, data repair, or infrastructure changes.
