---
name: project-context
description: Load the configured modules, project rules, and only the stack and architecture context relevant to the current task
compatibility: opencode-v2
---

## Purpose

Compose project context without flooding the session or guessing conventions.

## Workflow

1. If the current task is `/ai-bootstrap`, stop using this skill and follow `.opencode/commands/ai-bootstrap.md` instead. Project context is not trusted until bootstrap is approved and persisted.
2. Read `.ai/project.json`. If it does not exist, stop and recommend `/ai-bootstrap`; do not inspect files, ask for bootstrap input, or create project configuration from this skill.
3. Run `workflow_validate_project`. Continue only when it returns exit code zero and `PROJECT_VALID`; report invalid or missing fields and do not silently repair them.
4. Read `.ai/project-rules.md` and any `AGENTS.md` that governs the affected paths.
5. Determine affected modules from paths and ticket evidence. If ambiguous, state the ambiguity.
6. For each affected module, load exactly the skill IDs in `contextSkills`. Do not load every stack and architecture skill.
7. Extract the module path, quality commands, boundaries, applicable local rules, fast-path limits, and production-diagnosis policy when configured.
8. When `profile` is configured, compare its fingerprint with `.ai/project-profile.json`. Recommend `/ai-refresh` when validation reports drift or generated-skill inconsistency; do not regenerate context during an implementation task.

## Precedence

Explicit current user direction overrides project rules; project and module rules override architecture skills; architecture overrides stack; stack overrides core. Call out a material conflict rather than hiding it.

## Output

Return affected modules, loaded skills, governing rules, quality commands, and unresolved context gaps.
