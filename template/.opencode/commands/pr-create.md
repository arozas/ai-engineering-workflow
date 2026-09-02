---
description: Create one explicitly approved draft pull request from the published feature branch
agent: orchestrator
---

Load `workflow-state`, `delivery-safety`, and `pr-description`. Require a validated persisted run in `PUBLISHED`, a clean working tree, a feature branch with upstream, and no existing open pull request for the branch.

Use `.ai/pull-request-template.md` as the required structure. Produce the complete title and body, keeping every section; write `Not applicable` with a reason when a section does not apply. Do not claim checks passed without exact evidence. Do not include automatic reviewers, assignees, labels, comments, issue-closing keywords, merge, or auto-merge.

Show the exact base, head, title, and body and wait for explicit approval. After approval, write the approved body to `.ai/runtime/<run-id>/pr-draft.md` and delegate only `.ai/scripts/create-draft-pr.ps1 -BodyFile .ai/runtime/<run-id>/pr-draft.md` to `delivery`.

Write schema-valid evidence, including the run ID, PR number and URL, base, head, head SHA, title, draft/open state, and UTC timestamp, to `.ai/runtime/<run-id>/pull-request.json`. Call `RecordPullRequest`; it must independently query GitHub and confirm every recorded field before state can advance. Report the persisted result, and stop. Do not mark it ready or merge it.
