---
name: project-skill-builder
description: Compose built-in skills with minimal evidence-backed project skills for repository-specific modules and conventions
compatibility: opencode-v2
---

## Generation policy

Generate a project skill only when verified repository behavior is not already covered by selected stack and architecture skills. Prefer one skill per real module boundary. IDs must use `project-<module-id>` and live at `.opencode/skills/<id>/SKILL.md`.

Every generated skill must begin with valid OpenCode skill frontmatter and contain these sections in order:

1. `## Scope`
2. `## Evidence`
3. `## Rules`
4. `## Quality and testing`
5. `## Unknowns`

Rules must be imperative, project-specific, and traceable to evidence. Do not copy generic language guidance, invent architectural intent, embed secrets, include credentials, or turn LOW-confidence hypotheses into mandatory rules. Put unresolved LOW-confidence observations under `Unknowns` instead.

## Composition

Keep built-in stack and architecture skill IDs in the module's `contextSkills`, followed by its generated project skill. Include an architecture skill only when the evidence supports it. For a conventional controller/model/repository application without stronger dependency-boundary evidence, use `architecture-simple-layered` or no architecture skill; do not use `architecture-clean` as a default. The project skill should contain only the delta: module ownership, dependency boundaries, file placement, local conventions, error behavior, generated-file restrictions, and test commands supported by this repository.

## Manifest

Describe every generated skill in `.ai/generated-skills.json`, which must validate against `.ai/generated-skills.schema.json`. Each entry records its module, exact path, confidence, reason, composed built-in skills, and evidence claims. The manifest fingerprint must match `.ai/project-profile.json` and the `profile.repositoryFingerprint` in `.ai/project.json`.

When no custom skill is justified, write a valid manifest with an empty `skills` array and use only built-in skills. Never generate content merely to make the manifest non-empty.

## Approval boundary

Before approval, write the complete contents of every proposed project skill and the generated-skills manifest together with proposed project configuration and rules under `.ai/bootstrap-proposal/`. The generated-skills manifest must still use final paths such as `.opencode/skills/project-<module-id>/SKILL.md`; the draft skill body lives under `.ai/bootstrap-proposal/skills/project-<module-id>/SKILL.md` until approval. Do not ask for permission to create this durable proposal; approval is required only before applying it. After explicit approval, `/ai-bootstrap-apply` writes exactly the approved proposal, persists the deterministic profile, and runs `workflow_validate_project`. Any validation or fingerprint mismatch blocks completion.
