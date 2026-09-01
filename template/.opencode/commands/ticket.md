---
description: Analyze a ticket or requirement and produce a scoped implementation plan
agent: orchestrator
---

Analyze this ticket, confirmed diagnosis, or requirement: $ARGUMENTS

Load `project-context`, `workflow-state`, and `ticket-analysis`. Normalize the requirement into `.ai/runtime/requirement.md`, create one standard persisted run, and report its run ID. If `.ai/project.json` configures Azure DevOps and the argument identifies a work item, also load `azure-devops-ticket` and retrieve it read-only. Explore the affected code and load only the relevant module context skills.

When the exact argument form is `diagnosis:<run-id>`, first validate that diagnostic run through `workflow-state Validate`, require status `ROOT_CAUSE_CONFIRMED`, and validate its canonical `diagnosis.json` with `.ai/scripts/validate-diagnosis.ps1`. Build the normalized requirement from the confirmed root cause, regression-test obligation, evidence identifiers, and source hashes. Start the new standard run with `-SourceRunId <run-id>`. Do not repeat causal discovery, but verify that the proposed implementation scope still matches the confirmed evidence. Reject blocked, escalated, missing, stale, or tampered diagnoses.

Produce the structured implementation plan required by the `implementation-plan` skill and write the exact proposal to `.ai/runtime/plan.md`. Do not change code. End with unresolved decisions and wait for explicit human approval. After approval, record that exact plan with the `ApprovePlan` transition; do not rely only on conversational approval.
