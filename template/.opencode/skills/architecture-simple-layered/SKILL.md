---
name: architecture-simple-layered
description: Preserve pragmatic layered API boundaries for conventional controller, DTO/model, repository, and persistence applications
compatibility: opencode-v2
---

Use this skill when repository evidence shows a conventional layered application but not Clean Architecture, hexagonal architecture, vertical slices, or event-driven design. A conventional controller/model/repository API belongs here unless stronger architectural boundaries are proven by source/build evidence.

- Keep controllers or endpoints thin: HTTP routing, validation, mapping, status codes, and delegation only.
- Keep persistence access in the established repository, DbContext, ORM, or data-access layer.
- Keep DTO/API contracts separate from persistence entities when the repository already has DTOs or mapping profiles.
- Preserve existing dependency direction; do not add layers, interfaces, mediators, or abstractions merely to imitate a stronger architecture.
- Put new behavior in the smallest existing layer that owns similar behavior.
- Keep error handling and HTTP status semantics consistent across endpoints.
- Do not introduce cross-cutting infrastructure, background processing, event contracts, or external service clients without explicit approval.
- Tests should cover controller behavior, validation/mapping, and repository/data-access behavior using the smallest safe local fixture available.

Project-specific rules and evidence always override this generic profile.
