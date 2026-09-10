---
description: Analyze a ticket or requirement and produce a scoped implementation plan
agent: orchestrator
---

Analyze this ticket, confirmed diagnosis, or requirement: $ARGUMENTS

Load `project-context`, `workflow-state`, `ticket-analysis`, and `implementation-plan`. Choose a unique run ID, normalize the requirement into `.ai/runtime/<run-id>/requirement.md`, create one standard persisted run, and report its run ID. If `.ai/project.json` configures Azure DevOps and the argument identifies a work item, also load `azure-devops-ticket` and retrieve it read-only. Load only the relevant module context skills and delegate at most one bounded, precise code question to `evidence-reader`; never perform an open-ended repository inventory.

When the exact argument form is `diagnosis:<run-id>`, first validate that diagnostic run through `workflow_state` action `Validate`, require status `ROOT_CAUSE_CONFIRMED`, and validate its canonical `diagnosis.json` with `workflow_validate_diagnosis`. Build the normalized requirement from the confirmed root cause, regression-test obligation, evidence identifiers, and source hashes. Start the new standard run with `sourceRunId` set to the diagnostic run. Do not repeat causal discovery, but verify that the proposed implementation scope still matches the confirmed evidence. Reject blocked, escalated, missing, stale, or tampered diagnoses.

Produce the structured implementation plan required by the `implementation-plan` skill and write the exact proposal to `.ai/runtime/<run-id>/plan.md`. The plan must name every affected module ID. Write `.ai/runtime/<run-id>/verification.json` as a schema-version-2 execution contract. It must contain the exact affected modules, expected file actions, dependency versions and evidence sources, closed decisions, an empty `unresolvedDecisions` array, constraints, estimated files/lines, and every mandatory task-specific command that is not already configured in `.ai/project.json`; use an empty `commands` array when no additional command is required. Validate it against `.ai/task-verification.schema.json`. Alternatives such as "A or B", optional files, missing dependency versions, unresolved material choices, or mandatory verification described only in prose must block approval.

Do not change code. End with unresolved decisions and wait for explicit human approval of both files. After approval, call `workflow_state` action `ApprovePlan` with the exact plan, `verificationPath`, and affected module IDs; this copies and hashes the manifest and freezes the merged configured plus run-specific quality matrix. Do not rely only on conversational approval.
