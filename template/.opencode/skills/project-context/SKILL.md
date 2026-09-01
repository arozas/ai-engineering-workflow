---
name: project-context
description: Load the configured modules, project rules, and only the stack and architecture context relevant to the current task
compatibility: opencode-v2
---

## Purpose

Compose project context without flooding the session or guessing conventions.

## Workflow

1. Read `.ai/project.json`. If it does not exist, stop and recommend `/ai-bootstrap`.
2. Validate its shape against `.ai/project.schema.json`. Report invalid or missing fields; do not silently repair them.
3. Read `.ai/project-rules.md` and any `AGENTS.md` that governs the affected paths.
4. Determine affected modules from paths and ticket evidence. If ambiguous, state the ambiguity.
5. For each affected module, load exactly the skill IDs in `contextSkills`. Do not load every stack and architecture skill.
6. Extract the module path, quality commands, boundaries, applicable local rules, and fast-path limits when configured.

## Precedence

Explicit current user direction overrides project rules; project and module rules override architecture skills; architecture overrides stack; stack overrides core. Call out a material conflict rather than hiding it.

## Output

Return affected modules, loaded skills, governing rules, quality commands, and unresolved context gaps.
