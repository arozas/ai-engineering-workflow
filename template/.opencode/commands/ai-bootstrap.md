---
description: Inspect an application repository and propose project context without guessing or writing before approval
agent: orchestrator
---

Perform the mandatory fast path before loading any skill:

1. Create exactly one inventory of files outside the workflow-owned paths `AGENTS.md`, `opencode.json`, `.ai/**`, and `.opencode/**`.
2. If that inventory is empty, reply with `NO PROJECT MODULES DETECTED`, explain that application source or build evidence is required, and stop in the same response. Do not load a skill, read the schema, run per-language searches, or continue exploring.
3. If application files exist, load `repo-bootstrap` and follow its preflight classification, exploration budget, and stop conditions.

If the current repository is the distributable AI Engineering Workflow source, stop with `BOOTSTRAP NOT APPLICABLE`. If application files exist but no module can be supported by source/build evidence, stop with `NO PROJECT MODULES DETECTED`. Never invent a module and never propose an invalid `.ai/project.json`.

For an applicable repository, inspect module boundaries, languages, frameworks, architectures, build systems, tests, CI/CD, and local conventions. Treat `.ai/bootstrap-input.json`, when present, as user-declared intent that must still be checked against repository evidence. Include evidence and confidence for every inference. Produce a complete proposed `.ai/project.json` that validates against `.ai/project.schema.json`, plus proposed updates to `.ai/project-rules.md`.

Do not write either file yet. End by asking the user to correct or explicitly approve the proposal. Only after explicit approval may you write the approved configuration, validate it again, and report that `/ticket` is ready.
