---
name: architecture-hexagonal
description: Preserve ports-and-adapters boundaries and keep domain behavior independent from external technologies
compatibility: opencode-v2
---

Identify the repository's actual domain, application ports, driving adapters, and driven adapters from dependencies and representative code.

- Domain/application code defines capabilities; adapters translate external protocols and technologies.
- Ports express behavior needed by use cases and live on the side that owns the abstraction.
- Keep framework annotations, persistence schemas, HTTP details, messaging clients, and vendor types out of the domain when existing boundaries do so.
- Adapter mapping, errors, retries, timeouts, and idempotency remain explicit.
- Do not create a port for trivial code or add an adapter layer without a real substitution or boundary need.
- Test domain behavior directly, ports with contract tests when valuable, and adapters with focused integration tests.

Use existing vocabulary and layout; project rules override generic hexagonal terminology.
