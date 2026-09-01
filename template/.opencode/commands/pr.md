---
description: Draft a detailed pull-request title and body from the canonical project template without creating anything
agent: orchestrator
---

Load `pr-description` and use `.ai/pull-request-template.md` as the required structure for the current changes.

Use the ticket, approved plan, diff, deterministic gate evidence, and review verdict. Keep every template section and write `Not applicable` with a reason where necessary. Present the complete title and body for review. Never write `.ai/pr-draft.md`, commit, push, create, merge, or approve a pull request; `/pr-create` handles the separately approved creation flow.
