---
description: Inspect an application repository and propose project context without guessing or writing before approval
agent: orchestrator
---

Perform the mandatory fast path before loading any skill:

1. Run `workflow_profile_project` with `persist: false`. This is the one permitted application inventory and remains read-only.
2. If it returns `NO PROJECT MODULES DETECTED`, repeat that verdict, explain that application source or build evidence is required, and stop in the same response. Do not load a skill, run per-language searches, or continue exploring.
3. If application files exist, retain the returned profile, load `repo-bootstrap`, `project-profiler`, and `project-skill-builder`, and reuse that evidence without another inventory.

If the current repository is the distributable AI Engineering Workflow source, stop with `BOOTSTRAP NOT APPLICABLE`. If application files exist but no module can be supported by source/build evidence, stop with `NO PROJECT MODULES DETECTED`. Never invent a module and never propose an invalid `.ai/project.json`.

For an applicable repository, inspect module boundaries, languages, frameworks, architectures, build systems, tests, CI/CD, and local conventions within the bootstrap budget using the retained deterministic profile. Treat `.ai/bootstrap-input.json`, when present, as user-declared intent that must still be checked against repository evidence. Include evidence and confidence for every inference.

Reuse built-in stack and architecture skills. When verified project-specific behavior is not covered, propose minimal `project-<module-id>` skills plus a complete `.ai/generated-skills.json`. Produce a complete proposed `.ai/project.json` with the profile fingerprint, proposed `.ai/project-rules.md`, the generated-skills manifest, and the full text of every proposed project skill.

Do not write any proposed file yet. End by asking the user to correct or explicitly approve the complete proposal. Only after explicit approval may you persist `.ai/project-profile.json`, write the approved configuration and skills, validate them again, and report that `/ticket`, `/diagnose`, and `/ai-refresh` are ready.
