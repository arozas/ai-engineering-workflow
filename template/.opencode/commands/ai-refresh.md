---
description: Detect structural repository drift and propose approved updates to project context and generated skills
agent: orchestrator
---

Load `project-profiler`, `project-skill-builder`, and `repo-bootstrap`. Require an existing valid `.ai/project.json` and `.ai/project-profile.json`.

Run `workflow_profile_project` with `persist: false` and compare its structure fingerprint and evidence with the persisted profile. If they match, report `PROJECT PROFILE CURRENT` and stop. If they differ, perform only the bounded scan needed to explain added, removed, or changed structural evidence.

Propose exact updates to `.ai/project.json`, `.ai/project-rules.md`, `.ai/generated-skills.json`, and affected `project-*` skills. Show evidence, confidence, removed assumptions, and complete proposed file contents. Do not write before explicit approval.

After approval, persist the fresh profile with `workflow_profile_project`, write exactly the approved updates, remove a retired generated skill only when the user explicitly approved that exact path, run `workflow_validate_project`, and report `PROJECT_VALID`. Never change application code, dependencies, Git state, or delivery state.
