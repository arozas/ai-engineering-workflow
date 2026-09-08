---
description: Detect structural repository drift and prepare a deterministic replacement context proposal
agent: orchestrator
---

Require existing `.ai/project.json` and `.ai/project-profile.json`. Do not load bootstrap skills or perform manual repository exploration.

Run `workflow_profile_project` once with `persist: false` and compare its structure fingerprint with `.ai/project-profile.json`. If they match, report `PROJECT PROFILE CURRENT` and stop.

If they differ, run `workflow_bootstrap_prepare` once with `force: true`. This may replace only the draft under `.ai/bootstrap-proposal/`; it must not change active project context. Summarize the returned fingerprint, modules, files, risks, and structural drift, then stop at review.

Use `/ai-bootstrap-enhance` for one optional bounded source-informed pass and `/ai-bootstrap-apply` after explicit approval. Never change application code, dependencies, Git state, or delivery state, and never retry an unchanged profile or proposal.
