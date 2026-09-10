# Reliability, preflight, and execution contracts

This document explains the safeguards that prevent an approved plan from turning into an ambiguous or repository-polluting implementation. These checks are deterministic: an agent cannot waive them by claiming that a result is acceptable.

## Why the execution contract exists

Early workflow versions stored only extra verification commands. That was enough to freeze a quality matrix, but it did not fully constrain new files, dependency choices, or solution edits. A small model could therefore approve one plan and later improvise a different test-project shape.

New standard runs use schema version 2 of `.ai/runtime/<run-id>/verification.json`. The file is both a verification manifest and the machine-readable execution contract approved with `plan.md`.

```json
{
  "schemaVersion": 2,
  "runId": "ticket-client-crud-tests",
  "affectedModules": ["app"],
  "expectedChanges": [
    { "path": "BackNet.sln", "action": "modify", "reason": "Register the approved test project" },
    { "path": "ClientsApiTest.csproj", "action": "modify", "reason": "Exclude nested test sources from the root web project" },
    { "path": "ClientsApiTest.Tests/ClientsApiTest.Tests.csproj", "action": "create", "reason": "Define the approved test project" },
    { "path": "ClientsApiTest.Tests/Usings.cs", "action": "create", "reason": "Provide the xUnit global using" },
    { "path": "ClientsApiTest.Tests/Controllers/ClientControllerTests.cs", "action": "create", "reason": "Cover existing controller behavior" }
  ],
  "dependencies": [
    {
      "name": "Microsoft.NET.Test.Sdk",
      "version": "17.11.1",
      "source": "approved-plan",
      "reason": "Run the approved .NET test project"
    }
  ],
  "decisions": [
    "Use xUnit and Moq for isolated controller tests.",
    "Add the test project to BackNet.sln through the managed helper."
  ],
  "unresolvedDecisions": [],
  "constraints": [
    "Do not change the public HTTP API.",
    "Do not modify production behavior."
  ],
  "estimatedChanges": {
    "files": 5,
    "lines": 400
  },
  "commands": [
    {
      "moduleId": "app",
      "phase": "test",
      "command": "dotnet test BackNet.sln --no-build",
      "reason": "Exercise the new test project through the solution"
    }
  ]
}
```

The dependency versions above are an example, not workflow defaults. The planner must select and justify exact versions before approval. `unresolvedDecisions` must be empty. Every affected module and intended delivery path must be explicit. Duplicate paths and control-plane paths are rejected.

Schema version 1 remains valid only for existing persisted runs created by earlier workflow versions. New or revised plans should use version 2; compatibility does not authorize silently downgrading a new contract.

## Plan scope enforcement

Before a quality command runs, the gate runner compares the current Git worktree with `expectedChanges` from the frozen version 2 contract.

- An unexpected changed path produces `PLAN_INVALIDATED`.
- An expected path that is still absent is recorded as missing evidence. The runner uses the complete scope result when deriving the verdict.
- A plan cannot include `AGENTS.md`, `opencode.json`, `.ai/`, or `.opencode/`; those paths belong to the workflow control plane.

`PLAN_INVALIDATED` is not a test failure. No correction loop should try to repair it under the old approval. Return to planning, revise both artifacts, obtain explicit approval, and freeze a new matrix.

## Repository-hygiene preflight

The gate runner checks common generated-output paths before executing restore, build, lint, typecheck, test, or end-to-end commands.

| Stack | Generated paths checked |
| --- | --- |
| .NET | `bin/`, `obj/` |
| Node.js or TypeScript | `node_modules/` |
| Python | `__pycache__/`, `.pytest_cache/` |
| Java or Kotlin | `target/`, `build/` |

The gate returns `BLOCKED_REPOSITORY_HYGIENE` when a generated path is already tracked or is not ignored by repository policy. Every module command is recorded as `NOT_RUN`; a blocked preflight is never reported as a failed build or a passing gate.

The workflow does not untrack files, edit `.gitignore`, or change project files automatically. Those are repository-policy changes and require a separate reviewed task. After the repository is clean, start or re-approve a run whose base evidence reflects the corrected state.

## Control-plane output detection

Some SDK-style application projects copy repository-root content into generated output. If `AGENTS.md`, `opencode.json`, `.ai/`, or `.opencode/` appears under a generated directory after commands run, the result is `CONTROL_PLANE_OUTPUT`, even when every command exited zero.

This prevents workflow prompts, local evidence, schemas, or agent definitions from becoming build or publish artifacts. The safe remediation is project-specific: explicitly exclude the affected paths in the application project, then review that project-file change normally. The gate runner reports the exact detected output paths and never edits the project on its own.

## .NET xUnit test-project recipe

When an approved task adds a new xUnit project, load the built-in `stack-dotnet` reference `references/xunit-test-project.md`. The execution contract must freeze:

- the exact project and solution paths;
- exact package names and versions;
- `<Using Include="Xunit" />` or explicit `using Xunit;` evidence;
- any root-project exclusion needed to prevent the application project from compiling nested test sources;
- the exact solution-targeted restore, build, and test commands.

For an SDK-style web project at repository root, a nested test project may be globbed by the application project. The approved plan should normally add a narrow `DefaultItemExcludes` entry for that test directory. This is a production project-file change and must appear in `expectedChanges`; the workflow never injects it implicitly.

Add the test project to an existing solution with the typed `workflow_dotnet_solution_add` tool. When that tool is absent from the initial catalog, use the exact audited fallback once:

```powershell
pwsh -NoProfile -File .ai/scripts/add-dotnet-project.ps1 `
  -RunId <run-id> `
  -Solution BackNet.sln `
  -Project ClientsApiTest.Tests/ClientsApiTest.Tests.csproj
```

The helper requires an `IMPLEMENTING` run with a version 2 contract, verifies that both paths were approved, is idempotent, and delegates solution-file formatting and project identifiers to `dotnet sln add`. Do not hand-edit solution GUIDs.

## Runtime launcher selection on Windows

PowerShell resolves `.ps1` before `.cmd` in some installations. A restricted execution policy can therefore reject a bare `opencode2` command even though `opencode2.cmd` works.

`/workflow-doctor` now reports:

- `selectedOpenCode`: the callable `.cmd` or `.bat` launcher used for the check;
- `selectedVersion`: the detected OpenCode V2 version;
- `resolvedOpenCode`: what a bare `opencode2` resolves to;
- `recommendedCommand`: the launcher to use from the current terminal;
- duplicate installations, execution-policy warnings, and the next step.

The doctor is read-only. It does not change `PATH`, execution policy, aliases, or installed packages.

## Delivery branch behavior

Branch creation is one guarded delivery operation. The orchestrator performs the state and delivery prechecks once, asks for approval of one exact name, and delegates only that operation. The delivery agent does not repeat raw Git discovery and does not load commit or pull-request skills for branch creation.

`.ai/scripts/create-branch.ps1` captures Git chatter and returns one compact JSON result containing the branch, SHA, canonical `branch.json` path and hash, persisted status, and transition transport. It stops without staging, committing, pushing, or opening a pull request.

## Interpreting blocked states

| Persisted status | Meaning | Required next action |
| --- | --- | --- |
| `GATE_FAILED` | An approved command ran and exited nonzero. | Approve a bounded correction, then rerun the full frozen matrix. |
| `GATE_BLOCKED` | Commands did not run because repository hygiene or output safety blocked them. | Correct repository policy in a separate approved task; do not enter a normal code-correction loop. |
| `PLAN_INVALIDATED` | Actual paths no longer match the approved execution contract. | Return to planning and explicitly approve the revised scope. |

These statuses preserve the distinction between defective code, an unsafe repository state, and an obsolete plan. That distinction is essential for smaller models: each outcome has one legal next step instead of inviting repeated exploration or speculative fixes.

## Evaluation scenario

The sanitized Clients API scenario in `evaluations/scenarios/clients-api-crud-tests.md` exercises both a hygienic repository and an unsafe root-project layout. Run it with economical and frontier model profiles. Record duplicate calls, protocol violations, step-budget exhaustion, tokens, elapsed time, acceptance results, and whether the deterministic blockers were interpreted correctly.
