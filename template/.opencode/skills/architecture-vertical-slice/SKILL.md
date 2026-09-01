---
name: architecture-vertical-slice
description: Preserve feature-oriented vertical slices while controlling coupling and shared abstractions
compatibility: opencode-v2
---

Confirm that the repository groups behavior by feature/use case rather than merely using feature-like folder names.

- Keep request handling, validation, mapping, and tests close to the feature when established.
- A slice owns its behavior and should not reach into another slice's internals.
- Prefer explicit cross-slice contracts or existing shared services over hidden coupling.
- Extract shared abstractions only after demonstrated reuse; avoid premature common layers.
- Keep handlers focused on one use case and transaction boundary.
- Preserve external API, event, and data ownership contracts.
- Test each slice through its observable behavior, adding lower-level tests only where they add diagnostic value.

Follow the project's actual mediator, routing, state, and persistence patterns; none are mandatory to vertical-slice architecture.
