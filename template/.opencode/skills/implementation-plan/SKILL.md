---
name: implementation-plan
description: Produce a human-approvable implementation plan grounded in ticket criteria and repository evidence
compatibility: opencode-v2
---

## Required plan

1. Ticket or request and objective.
2. Acceptance criteria, each mapped to current evidence and an intended verification.
3. Affected modules, components, files, APIs, data, and dependencies.
4. Proposed implementation steps in dependency order.
5. Test plan by unit, integration, component, and e2e level as applicable.
6. Exact configured quality commands plus every mandatory task-specific command absent from project configuration.
7. Security, compatibility, concurrency, data, rollout, and operational risks.
8. Non-goals and unchanged behavior.
9. Expected changed files and approximate changed lines.
10. Alternatives considered and why the proposed option fits existing conventions.
11. Questions and assumptions.

Every expected file must have a reason. Plans must be specific enough that the developer does not need to invent architecture. Materialize the task-specific commands in `.ai/runtime/<run-id>/verification.json` using `.ai/task-verification.schema.json`; an empty command array is required when configured gates are sufficient. Every manifest command must appear in the plan and every mandatory plan command absent from `.ai/project.json` must appear in the manifest. For .NET, reuse the configured explicit `.sln`, `.slnx`, or project target in task-specific commands; never propose a bare `dotnet restore`, `dotnet build`, or `dotnet test` when the module can contain multiple build files. End with `WAITING FOR APPROVAL`; no production edit is allowed before explicit approval of both artifacts.
