---
description: Implement the latest explicitly approved plan through the developer agent
agent: orchestrator
---

Implement only an exact plan recorded as `PLAN_APPROVED` in persisted workflow state.

Load `workflow-state`. Resolve exactly one approved run or require the user to name its run ID. Validate the run and call `BeginImplementation`; if no persisted approved plan exists, stop and ask the user to run `/ticket` or approve its proposal. Delegate the persisted requirement, hashed plan, constraints, expected diff budget, selected module context, and quality commands to `developer`.

After implementation, require exact `quality-gate` results and record their evidence with `RecordGates`. Do not silently expand scope and do not begin reviewer/developer correction loops unless the user requested the full workflow.
