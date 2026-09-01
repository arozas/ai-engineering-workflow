---
name: stack-node
description: Apply evidence-based Node.js, JavaScript, and TypeScript guidance using the repository's actual package manager and tooling
compatibility: opencode-v2 node
---

## Evidence first

Read `package.json`, workspace configuration, lockfiles, runtime/version files, TypeScript configuration, module type, scripts, lint/format config, and tests. The lockfile and existing scripts determine the package manager and commands; never mix npm, pnpm, yarn, or bun without evidence.

## Guidance

- Preserve ESM/CommonJS boundaries and package export contracts.
- Keep TypeScript strictness and avoid `any`, unsafe casts, or suppression comments unless already justified.
- Await promises, handle rejections, preserve cancellation/abort behavior, and avoid blocking the event loop.
- Validate untrusted external input at the established boundary.
- Avoid import-time side effects and accidental circular dependencies.
- Respect workspace boundaries and do not add dependencies without approval.
- Use the project's existing test environment, fake timers, and module-mocking conventions.

Run only commands configured in `.ai/project.json` and from the configured module path.
