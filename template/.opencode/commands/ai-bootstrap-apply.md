---
description: Validate and apply an explicitly approved durable bootstrap proposal
agent: orchestrator
---

Apply the durable bootstrap proposal only after the user explicitly requests this command.

Do not re-run `/ai-bootstrap`, regenerate the proposal, reinterpret repository architecture, or edit proposal files. The approved source of truth is the current `.ai/bootstrap-proposal/` directory.

Run `workflow_bootstrap_apply` with `dryRun: true` first and report any validation errors without modifying files. If the dry run returns `BOOTSTRAP_PROPOSAL_VALID`, ask for one final explicit approval to apply the listed files unless the user's current message already explicitly says to apply the proposal.

After explicit approval, run `workflow_bootstrap_apply` with `dryRun: false`. Report `PROJECT_VALID`, applied files, modules, and any residual manual follow-up. Do not run Git commit, push, PR, deployment, cloud, or secret operations.
