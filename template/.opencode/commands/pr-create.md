---
description: Create one explicitly approved draft pull request from the published feature branch
agent: orchestrator
---

Load `delivery-safety` and `pr-description`. Require a clean working tree, a published feature branch with upstream, fresh gate/review evidence, and no existing open pull request for the branch.

Use `.ai/pull-request-template.md` as the required structure. Produce the complete title and body, keeping every section; write `Not applicable` with a reason when a section does not apply. Do not claim checks passed without exact evidence. Do not include automatic reviewers, assignees, labels, comments, issue-closing keywords, merge, or auto-merge.

Show the exact base, head, title, and body and wait for explicit approval. After approval, write the approved body to `.ai/pr-draft.md` and delegate only `.ai/scripts/create-draft-pr.ps1` to `delivery`.

Report the draft PR URL and stop. Do not mark it ready or merge it.
