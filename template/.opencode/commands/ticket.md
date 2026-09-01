---
description: Analyze a ticket or requirement and produce a scoped implementation plan
agent: orchestrator
---

Analyze this ticket or requirement: $ARGUMENTS

Load `project-context` and `ticket-analysis`. If `.ai/project.json` configures Azure DevOps and the argument identifies a work item, also load `azure-devops-ticket` and retrieve it read-only. Explore the affected code and load only the relevant module context skills.

Produce the structured implementation plan required by the `implementation-plan` skill. Do not change code. End with unresolved decisions and wait for explicit human approval.
