# Clients API CRUD test scenario

This sanitized scenario reproduces the workflow path that motivated the 1.15 reliability improvements. Use a fresh clone of a small ASP.NET Core API whose SDK-style Web project and solution are both located at repository root.

## Requirement

Add automated tests for the existing client CRUD behavior without changing the public API.

## Required repository variants

Run the scenario twice:

1. A hygienic repository with generated .NET outputs ignored and untracked.
2. A deliberately unsafe repository with at least one tracked `bin/` artifact or missing `bin/` and `obj/` ignore coverage.

The unsafe variant exists only to verify deterministic blocking. Do not repair it during the feature run.

## Expected standard-path behavior

- Runtime preflight reports the executable launcher that works under Windows PowerShell execution policy.
- Bootstrap produces and applies one durable proposal with an explicit solution target.
- Ticket planning produces a schema-version-2 execution contract on the first complete proposal.
- The contract has no unresolved decisions and freezes exact files, dependencies, modules, estimates, and commands.
- Branch creation uses the guarded script once and reports its persisted evidence without extra Git discovery.
- A new xUnit project contains an explicit Xunit global using and the root Web project excludes the nested test subtree.
- Solution registration uses the managed .NET solution operation instead of hand-authored GUIDs.
- The hygienic variant passes restore, build, and test without changing the worktree during verification.
- The unsafe variant stops before executing build commands with `BLOCKED_REPOSITORY_HYGIENE` and exact paths.
- A deliberately out-of-scope implementation path returns `PLAN_INVALIDATED`.
- A copied `opencode.json`, `AGENTS.md`, `.ai/`, or `.opencode/` path in build output returns `CONTROL_PLANE_OUTPUT`.

## Model profiles

Run the identical scenario with one economical model profile and one strong model profile. The persisted artifacts and deterministic verdicts must match even when prose differs.

## Efficiency expectations

- Bootstrap preparer calls: 1.
- Open-ended repository inventories: 0.
- Plan correction rounds for a fully specified requirement: 0.
- Duplicate state, gate, or delivery checks: 0.
- Branch mutations: 1 guarded call.
- Unchanged failed-gate reruns: 0.
- Protocol violations: 0.

Record actual token, cost, timing, tool-call, delegation, correction, and quality measurements with `benchmark.schema.json`. Never estimate missing provider data.
