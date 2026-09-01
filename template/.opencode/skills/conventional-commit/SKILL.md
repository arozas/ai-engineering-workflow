---
name: conventional-commit
description: Produce and validate Conventional Commit messages without AI-agent authorship or co-authorship attribution
compatibility: opencode-v2 git powershell
---

## Required format

Every workflow-created commit subject must match:

```text
<type>(optional-scope)(optional-!): <description>
```

Allowed types:

- `feat`
- `fix`
- `docs`
- `style`
- `refactor`
- `perf`
- `test`
- `build`
- `ci`
- `chore`
- `revert`

Use a lowercase, repository-relevant scope when it adds clarity. Keep the subject at 72 characters or fewer. Use the imperative mood and describe the user-visible or engineering outcome, not the agent's activity.

A body is optional. When present, separate it from the subject with a blank line and explain motivation, important behavior, and constraints. Use `BREAKING CHANGE: ...` only for an explicitly approved breaking change.

## Attribution prohibition

Never add an AI model, provider, coding tool, or agent as author or co-author. Prohibited examples include:

- `Co-authored-by: Claude ...`
- `Co-authored-by: Codex ...`
- `Generated-by: ChatGPT`
- `Generated with Copilot`
- `by Claude`
- `byclaude`

Do not add equivalent variants for Anthropic, OpenAI, Gemini, Cursor, OpenCode, or another AI agent. The Git author remains the human identity already configured in the repository.

## Deterministic validation

Validate the exact final subject and body before committing:

```text
pwsh -NoProfile -File .ai/scripts/validate-commit-message.ps1 -Message "<exact message>"
```

Create the commit only through `.ai/scripts/commit-approved.ps1`, which validates the message again and rejects protected environment files in the staged set.
