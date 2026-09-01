---
name: architecture-event-driven
description: Preserve event contracts, delivery semantics, idempotency, ordering, observability, and safe evolution
compatibility: opencode-v2
---

Establish whether events are domain events, integration events, commands, or notifications and identify broker, producers, consumers, schemas, and delivery guarantees from evidence.

- Treat published event schemas and topic/routing names as compatibility contracts.
- Make at-least-once delivery safe with idempotent consumers or explicit deduplication.
- Preserve ordering and concurrency assumptions; do not imply global ordering without proof.
- Keep transaction boundaries explicit; use the existing outbox/inbox strategy when present.
- Define retry, backoff, dead-letter, poison-message, and replay behavior consistently with operations.
- Propagate correlation/causation identifiers and avoid logging sensitive payloads.
- Version events compatibly and tolerate expected old/new producer overlap.
- Test serialization contracts, duplicate delivery, retries, failures, and replay-sensitive behavior.

Do not introduce events or asynchronous delivery merely to decouple code; require an approved architectural reason.
