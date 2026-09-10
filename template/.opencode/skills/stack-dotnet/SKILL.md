---
name: stack-dotnet
description: Apply evidence-based .NET and ASP.NET Core implementation and review guidance without overriding project conventions
compatibility: opencode-v2 dotnet
---

## Evidence first

Read `global.json`, solution/project files, central package management, nullable and analyzer settings, target frameworks, test projects, and existing code patterns. Do not assume ASP.NET Core, EF Core, MediatR, xUnit, or a particular SDK unless present.

## Guidance

- Respect nullable reference types and analyzer severity.
- Use asynchronous APIs for I/O and propagate `CancellationToken` along established request boundaries.
- Avoid `async void`, sync-over-async, broad exception swallowing, and hidden global state.
- Preserve dependency injection lifetimes and existing configuration/option patterns.
- Keep transport contracts, domain models, and persistence entities separated when the project already does so.
- For EF Core, consider query shape, tracking, transactions, concurrency, migrations, and generated SQL; do not rewrite deployed migrations.
- Keep public API and serialization behavior compatible unless change is approved.
- Follow the repository's test framework and naming conventions.

When an approved plan creates a new xUnit project, read and follow `references/xunit-test-project.md`. This recipe prevents root SDK projects from compiling nested test sources, requires an explicit xUnit global using, and keeps package versions and solution targets frozen in the execution contract.

Use only quality commands established in `.ai/project.json`; do not invent `dotnet format`, warning flags, or test options.
