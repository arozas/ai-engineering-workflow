---
description: Inspect an application repository and propose project context without guessing or writing before approval
agent: orchestrator
---

Perform the mandatory profiling path before reading any skill:

1. Run `workflow_profile_project` with `persist: false`. This is the preferred read-only application inventory.
2. If the tool is unavailable, unknown, removed, renamed, or not callable, do not browse manually. Run exactly one fallback inventory through shell: `pwsh -NoProfile -File .ai/scripts/profile-project.ps1`. This fallback is read-only and must be reported as `PROFILE FALLBACK USED`.
3. If both the typed tool and fallback script are unavailable, denied, or fail before returning a schema-shaped profile, stop with `BOOTSTRAP BLOCKED: PROFILE TOOL UNAVAILABLE`. Explain that OpenCode custom-tool discovery or the installed profile script must be fixed. Do not read a skill, run per-language searches, or continue exploring.
4. If the profile returns `NO PROJECT MODULES DETECTED`, repeat that verdict, explain that application source or build evidence is required, and stop in the same response. Do not read a skill, run per-language searches, or continue exploring.
5. If application files exist, retain the returned profile and immediately read these three files exactly once: `.opencode/skills/repo-bootstrap/SKILL.md`, `.opencode/skills/project-profiler/SKILL.md`, and `.opencode/skills/project-skill-builder/SKILL.md`. Reading these files is the skill-loading mechanism. Do not merely say that you need to load them, do not repeat the profile summary, and do not wait for another user message before reading them.

Loop guard: after a schema-shaped profile exists, the only valid next actions are reading the three required `SKILL.md` files, performing the bounded evidence reads allowed by those files, or presenting the complete proposal. If you notice yourself restating that the profile succeeded or that skills need to be loaded, stop that narration and perform the concrete file reads or produce the proposal.

If the current repository is the distributable AI Engineering Workflow source, stop with `BOOTSTRAP NOT APPLICABLE`. If application files exist but no module can be supported by source/build evidence, stop with `NO PROJECT MODULES DETECTED`. Never invent a module and never propose an invalid `.ai/project.json`.

For an applicable repository, inspect module boundaries, languages, frameworks, architectures, build systems, tests, CI/CD, and local conventions within the bootstrap budget using the retained deterministic profile and the three required skill files. Treat `.ai/bootstrap-input.json`, when present, as user-declared intent that must still be checked against repository evidence. Include evidence and confidence for every inference.

Reuse built-in stack and architecture skills only when evidence fits. Do not infer Clean Architecture, hexagonal architecture, event-driven architecture, or vertical slices from generic controller/model/repository folders alone. For simple APIs with controllers, DTOs/models, persistence, and repositories but no enforced inward dependency layers or use-case boundaries, prefer `architecture-simple-layered`. When verified project-specific behavior is not covered, propose minimal `project-<module-id>` skills plus a complete generated-skills manifest.

Write the complete proposal to durable draft files under `.ai/bootstrap-proposal/`. This is the only pre-approval write allowed by bootstrap and it must not modify the final project configuration. Create or overwrite only these proposal paths:

- `.ai/bootstrap-proposal/project-profile.json`
- `.ai/bootstrap-proposal/project.json`
- `.ai/bootstrap-proposal/project-rules.md`
- `.ai/bootstrap-proposal/generated-skills.json`
- `.ai/bootstrap-proposal/evidence.md`
- `.ai/bootstrap-proposal/approval.md`
- `.ai/bootstrap-proposal/skills/project-<module-id>/SKILL.md` when a generated project skill is justified

The proposal's `project.json` must reference final paths (`.ai/project-profile.json`, `.ai/generated-skills.json`, and `.opencode/skills/project-<module-id>/SKILL.md`), not draft paths. The draft `project-profile.json` must contain the exact schema-shaped profile used for the proposal. The draft `evidence.md` must contain the detailed evidence, confidence, risks, unknowns, exploration ledger, and rationale that would otherwise make the chat response too large. The draft `approval.md` must explain how to edit the draft and how to apply it with `/ai-bootstrap-apply`.

After writing the draft proposal, run `workflow_bootstrap_apply` with `dryRun: true`. If the dry run fails, report the validation errors and fix the draft files only within `.ai/bootstrap-proposal/`. Do not modify final configuration files.

Do not ask permission to create the proposal and do not stop with an intermediate "should I proceed" question. End with a compact summary: profile fingerprint, detected modules, selected stack/architecture skills, proposal file list, important risks, dry-run verdict, and a request to edit the files or explicitly approve `/ai-bootstrap-apply`. Only `/ai-bootstrap-apply` may persist `.ai/project-profile.json`, write the approved final configuration and skills, validate them again, and report that `/ticket`, `/diagnose`, and `/ai-refresh` are ready.
