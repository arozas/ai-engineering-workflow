---
name: pr-description
description: Draft a traceable pull-request title and description from approved scope and verified evidence
compatibility: opencode-v2
---

Produce a concise imperative title and a description with:

- linked ticket or request
- problem and intent
- implementation summary grouped by module
- explicit non-goals
- acceptance-criteria mapping
- tests and exact gate status
- review verdict and residual findings
- compatibility, migration, rollout, configuration, and rollback notes when relevant
- risks and manual verification steps
- reviewer checklist

Never say checks passed unless the gate report proves it. Never create, push, approve, or merge the pull request.
