---
name: stack-java
description: Apply evidence-based Java and JVM guidance using the repository's actual build, framework, language level, and tests
compatibility: opencode-v2 java
---

## Evidence first

Read Maven or Gradle configuration, wrapper files, toolchains, Java version, module descriptors, framework plugins, dependency management, static analysis, and test setup. Use the checked-in wrapper when present. Never mix Maven and Gradle commands without module evidence.

## Guidance

- Preserve package/module boundaries and visibility.
- Use nullability, optional values, records, streams, and language features consistently with the existing codebase and Java level.
- Keep exceptions meaningful; do not catch broadly or discard causes.
- Preserve thread safety, transaction scope, persistence fetch behavior, and framework lifecycle rules.
- Avoid reflection, global mutable state, and new dependencies without approval.
- Maintain serialization and public API compatibility.
- Follow the project's JUnit/TestNG, mocking, fixture, and integration-test conventions.

Run only the module commands configured in `.ai/project.json`.
