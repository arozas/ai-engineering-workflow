---
description: Implement the latest explicitly approved plan through the developer agent
agent: orchestrator
---

Implement only the latest plan that the user explicitly approved in this session.

If no approved plan is present, stop and ask the user to run `/ticket` or approve a plan. Otherwise delegate the complete ticket, approved plan, constraints, expected diff budget, selected module context, and required quality commands to `developer`.

After implementation, require exact `quality-gate` results. Do not silently expand scope and do not begin reviewer/developer correction loops unless the user requested the full workflow.
