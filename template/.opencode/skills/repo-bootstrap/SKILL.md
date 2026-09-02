---
name: repo-bootstrap
description: Inspect an application repository with a bounded evidence scan and propose module, stack, architecture, and quality configuration for approval
compatibility: opencode-v2
---

## Safety contract

Bootstrap may write only durable draft proposal files under `.ai/bootstrap-proposal/` before approval. It must not modify final project context until the user explicitly approves `/ai-bootstrap-apply`. Never infer a convention merely because it is fashionable. Existing files and executable project metadata are stronger evidence than directory names.

This skill is valid only after the calling command has a schema-shaped deterministic profile. Confirm that `.opencode/skills/project-profiler/SKILL.md` and `.opencode/skills/project-skill-builder/SKILL.md` have been read. If not, read those files exactly once and continue. Do not announce that they need to be loaded without reading them.

## Mandatory empty-repository fast path

The calling command should already have inventoried files outside `AGENTS.md`, `opencode.json`, `.ai/**`, and `.opencode/**` by using `workflow_profile_project` or the documented fallback `pwsh -NoProfile -File .ai/scripts/profile-project.ps1`. If that inventory is empty, return `NO PROJECT MODULES DETECTED` immediately. Do not read more files or perform language-specific searches.

If no deterministic profile is available, stop with `BOOTSTRAP BLOCKED: PROFILE TOOL UNAVAILABLE`. Do not continue with manual directory exploration. If the fallback profile was used, include `PROFILE FALLBACK USED` in the proposal and reuse only that profile as the inventory source.

Loop guard: never restate the profile result or the need to read skills more than once. Once the required skill files are read, immediately perform the bounded evidence pass or produce the proposal.

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

For an applicable repository, produce the full proposal in durable draft files under `.ai/bootstrap-proposal/`. Do not ask whether to proceed before creating the proposal. Write:

1. `.ai/bootstrap-proposal/project-profile.json` with the exact profile used for inference.
2. `.ai/bootstrap-proposal/project.json`, conforming to `.ai/project.schema.json` and using final paths.
3. `.ai/bootstrap-proposal/project-rules.md` with proposed project-rule changes.
4. `.ai/bootstrap-proposal/generated-skills.json`, including an empty `skills` array when no custom skill is justified.
5. `.ai/bootstrap-proposal/skills/project-<module-id>/SKILL.md` for each justified generated project skill.
6. `.ai/bootstrap-proposal/evidence.md` containing detected repository shape and modules; technology and architecture per module with `HIGH`, `MEDIUM`, or `LOW` confidence and evidence; exact quality commands and the source proving each command; selected `contextSkills`; risks, unknowns, and questions; full generated-skill rationale; exploration ledger summary; deterministic structure fingerprint; and diagnostics policy.
7. `.ai/bootstrap-proposal/approval.md` explaining that users may edit the draft files, then run `/ai-bootstrap-apply` to validate and persist them.

After writing the draft files, run `workflow_bootstrap_apply` with `dryRun: true`. If validation fails, correct only files under `.ai/bootstrap-proposal/` and rerun the dry run. Do not write final `.ai/project.json`, `.ai/project-rules.md`, `.ai/generated-skills.json`, `.ai/project-profile.json`, or `.opencode/skills/project-*/SKILL.md` during `/ai-bootstrap`.

Architecture confidence must be conservative. Use `architecture-clean` only when repository evidence shows real inward dependency boundaries, use-case/application policy layers, and infrastructure depending on abstractions owned by inner layers. Use `architecture-hexagonal` only when ports and adapters are explicit. Use `architecture-vertical-slice` only when features own their request/handler/domain/test flow. Use `architecture-event-driven` only when event contracts and consumers/producers are first-class. Use `architecture-simple-layered` for conventional applications organized by controllers/endpoints, DTOs/models, services/repositories, and persistence without the stronger architecture evidence above. If no architecture pattern is supported, leave `architectures` empty and omit architecture skills.

End with a compact summary and ask the user to edit the draft files or explicitly run `/ai-bootstrap-apply`. `/ai-bootstrap-apply` reruns the profiler, stops if its fingerprint differs from the approved proposal, writes only approved final context files, runs `workflow_validate_project`, and reports `PROJECT_VALID`. A failed deterministic validation blocks bootstrap completion.

Unless the user selects stricter limits, propose the schema defaults for `fastPath`: enabled, at most three files, at most 120 added-plus-deleted lines, at most two production and two test files during diagnosis, and exactly one correction iteration. Never propose values above the schema maxima.

For `diagnostics.commands`, use only single-line commands already supported by repository evidence and safe for local inspection or reproduction. Never infer or propose production connections, secret retrieval, Git or delivery mutations, deployments, rollbacks, restarts, data repair, or infrastructure changes.
