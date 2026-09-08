---
description: Inspect an application repository and propose project context without guessing or writing before approval
agent: orchestrator
---

Run the deterministic bootstrap preparer instead of performing manual repository exploration.

1. If `workflow_bootstrap_prepare` is present in the initial callable-tool catalog, run it once. Set `force: true` only when `$ARGUMENTS` is exactly `--force`; otherwise omit it.
2. If the typed tool is absent or explicitly reports unknown/unavailable/not callable, do not search or retry it. Run the exact fallback command `pwsh -NoProfile -File .ai/scripts/prepare-bootstrap-proposal.ps1` once; append `-Force` only for the exact `--force` argument. Do not fall back after any other tool error.
3. If the selected transport fails before returning JSON, stop with `BOOTSTRAP BLOCKED: PROFILE TOOL UNAVAILABLE` and report that error.
4. If the result is `BOOTSTRAP NOT APPLICABLE` or `NO PROJECT MODULES DETECTED`, repeat that verdict and stop.
5. If the result is `BOOTSTRAP_PROPOSAL_READY` or `BOOTSTRAP_PROPOSAL_CURRENT`, summarize only the returned JSON: proposal root, fingerprint, modules, files, risks, and next step.
6. If the result is `BOOTSTRAP_PROPOSAL_STALE` or `BOOTSTRAP_PROPOSAL_INVALID`, preserve the draft, explain the exact issue, and stop. Never retry automatically or add `--force` yourself.

Do not read source files, list directories, run extra shell commands, load `project-context`, read stack/architecture skills, or regenerate the proposal manually. The preparer owns profiling, conservative inference, durable draft creation, and dry-run validation.

The proposal is written under `.ai/bootstrap-proposal/` and may be edited by the user:

- `.ai/bootstrap-proposal/project-profile.json`
- `.ai/bootstrap-proposal/project.json`
- `.ai/bootstrap-proposal/project-rules.md`
- `.ai/bootstrap-proposal/generated-skills.json`
- `.ai/bootstrap-proposal/evidence.md`
- `.ai/bootstrap-proposal/approval.md`
- `.ai/bootstrap-proposal/evidence-packet.json`
- `.ai/bootstrap-proposal/skills/project-<module-id>/SKILL.md` when a generated project skill is justified

Do not write final `.ai/project.json`, `.ai/project-rules.md`, `.ai/generated-skills.json`, `.ai/project-profile.json`, or `.opencode/skills/project-*/SKILL.md` during `/ai-bootstrap`. Final context is applied only by `/ai-bootstrap-apply` after explicit approval.

For optional source-informed refinement with a stronger model, run `/ai-bootstrap-enhance` after the deterministic proposal is valid.
