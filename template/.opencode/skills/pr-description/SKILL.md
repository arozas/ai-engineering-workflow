---
name: pr-description
description: Draft a traceable pull-request title and description from approved scope and verified evidence
compatibility: opencode-v2
---

Read `.ai/pull-request-template.md` and preserve its complete section order. Produce a concise imperative title and a detailed body with:

- linked ticket or request
- selected workflow path, estimate and actual classifier evidence, correction count, and any escalation
- problem and intent
- implementation summary grouped by module
- explicit non-goals
- acceptance-criteria mapping
- tests and exact gate status
- review verdict and residual findings
- persisted run ID, state, base/current SHA, and evidence hashes
- compatibility, migration, rollout, configuration, and rollback notes when relevant
- risks and manual verification steps
- reviewer checklist

Write `Not applicable` with a concise reason instead of omitting a section. Never say checks passed unless the gate report proves it. Do not include issue-closing keywords, reviewers, assignees, labels, comments, or rollout claims unless the user explicitly approved them. Never create, push, mark ready, approve, or merge the pull request.

For fast-path work, report both classifier runs and confirm that the final diff remained within the configured file, line, module, risk, and correction limits. If it did not, describe the handoff to the standard workflow instead of presenting the work as fast-path complete.
