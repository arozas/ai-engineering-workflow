---
name: architecture-clean
description: Preserve Clean Architecture dependency direction, use-case boundaries, and separation of policy from infrastructure
compatibility: opencode-v2
---

Confirm actual layers and project references before applying this guidance; names such as Domain, Application, Infrastructure, and API are evidence, not proof.

- Dependencies point inward toward policy; inner layers do not reference delivery, persistence, or framework details.
- Business rules remain independent of transport and storage models.
- Application use cases coordinate behavior and expose explicit input/output boundaries.
- Infrastructure implements ports owned by inner layers when that pattern already exists.
- Map between API contracts, domain models, and persistence models at established boundaries.
- Keep controllers, endpoints, consumers, and CLI handlers thin.
- Do not add interfaces, repositories, mediators, or layers merely to imitate a diagram.
- Tests should target business policy at inner layers and adapters at integration boundaries.

Project-specific dependency rules always override this generic profile.
