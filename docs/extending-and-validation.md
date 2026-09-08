# Extending, validating, and releasing

## Change the distribution, not generated consumers

Reusable changes belong in this repository under `template/`, `presets/`, `scripts/`, schemas, tests, and docs. A consumer repository's generated project skill is evidence for that consumer, not automatically a generic distribution skill.

Keep the repository root free of active `AGENTS.md`, `opencode.json`, `.ai/`, and `.opencode/`; those belong under `template/`. This prevents OpenCode from treating the distribution itself as an installed application workflow.

## Add a skill

Create `template/.opencode/skills/<skill-id>/SKILL.md` with frontmatter whose `name` exactly matches the directory. Define a narrow trigger and stable procedure. Avoid embedding project-specific facts in a generic skill.

When it is a stack or architecture skill, add or update the corresponding preset metadata and document its evidence requirements. Add it to an installed module only through approved bootstrap/refresh configuration.

## Add an agent

Create `template/.opencode/agents/<agent-id>.md` with valid frontmatter, a clear primary/subagent mode, bounded steps, and least privilege.

Answer before adding it:

- Does this role require different permissions or independent context?
- Can an existing agent plus a skill perform it safely?
- Is another handoff worth the token and latency cost?
- What exact input packet and output contract prevent rediscovery?
- How will corrections terminate?

Do not create a separate agent merely for a new stack; stack knowledge belongs in skills. A new agent is justified by a distinct trust boundary, such as read-only review or guarded delivery.

## Add a command

Create `template/.opencode/commands/<command>.md`, select an existing primary agent, and describe the complete route and stopping conditions. Commands should orchestrate skills and typed tools rather than repeat large procedures.

Commands that write production code must point to an approval-bearing route. Commands that mutate Git or external systems require a separate proposal and permission boundary.

## Add or change a typed tool

Custom tools live in `template/.opencode/tools/workflow.ts`. A named export becomes an OpenCode tool named `workflow_<export>`.

For each operation:

1. Define the narrowest schema: enums, regexes, maximum lengths/ranges, and repository-relative paths.
2. Pass process arguments as an array to `Bun.spawn`; never interpolate a shell command string.
3. Resolve the deterministic script inside the active worktree.
4. Bound returned output and preserve the exit code.
5. Keep validation in the underlying script as a second layer.
6. Leave the action globally denied in `opencode.json`.
7. Reopen the exact action only for agents that require it.
8. Add static and isolated tests for both allowed behavior and abuse cases.

Do not replace a typed tool with an automatically allowed `shell` resource ending in `*`.

## Add a project preset

Create `presets/projects/<id>/preset.json` and its files. The preset ID must match the directory. Reference only existing stack IDs. Ensure the preset does not contain credentials, machine-specific paths, generated build output, or an active installed runtime outside its intended project payload.

Test `-ListPresets`, `-DryRun`, generation, installation mode, and initialized Git status.

## Add stack or architecture metadata

Stack JSON files live in `presets/stacks/`; the file basename must match `id`. Architecture JSON files live in `presets/architectures/` with the same invariant.

Profiles should describe composition and generation defaults, not claim that an existing repository uses the technology. Existing repository inference remains the bootstrap agent's evidence-based responsibility.

## Change a schema

Schemas are security and compatibility contracts. When changing one:

- decide whether existing installed artifacts remain valid;
- update examples and producers/consumers together;
- keep `additionalProperties: false` on evidence/state contracts unless extensibility is intentional;
- add semantic validation when JSON Schema cannot express cross-field rules;
- test valid, invalid, tampered, stale, and boundary values;
- document the migration/update consequence.

For workflow state, optional fields can preserve the ability to read old runs, but transitions should explicitly reject legacy state when new safety evidence is required.

## Deterministic validation

Run:

```powershell
pwsh -NoProfile -File .\scripts\validate.ps1
```

It verifies:

- `VERSION` and manifest agreement;
- manifest/example/schema validity;
- required files and concise README policy;
- preset ID and reference integrity;
- agent/command frontmatter and skill names;
- sensitive-path, reviewer-exclusive tool, and direct-evidence-write permission invariants;
- absence of automatic managed-script shell allowances;
- presence and argument-vector implementation of typed tools;
- quality runner/state matrix protections;
- run-specific staging plus review, branch, commit, publish, and PR verification contracts;
- installation metadata and Local-mode safety logic;
- PR-template synchronization;
- JSON syntax and PowerShell parsing.

## Isolated tests

Run:

```powershell
pwsh -NoProfile -File .\tests\Run-Tests.ps1
```

The suite creates a temporary Git consumer, installs Local mode, and exercises:

- invisible local installation and metadata;
- deterministic profiling and project validation;
- structural drift and unsafe path/diagnostic rejection;
- passing/failing quality commands;
- root module path `.`;
- persisted quality matrices and rejection of partial evidence;
- production diagnosis and confirmed-diagnosis handoff;
- fast-path actual scope;
- control-plane and artifact tamper detection;
- reviewer-scoped structured evidence and forged-review rejection;
- persisted branch-creation evidence;
- independently validated actual commit message, changed paths, and reviewed diff;
- forged publish rejection plus real remote-ref verification;
- GitHub draft-PR metadata verification through a deterministic CLI fixture;
- reviewer isolation and typed-tool permissions;
- benchmark summarization and updater conflicts.

Expected child-process failures are assertions, not suite failures. The test script explicitly exits zero only after all assertions pass.

## OpenCode discovery smoke test

Install the current OpenCode CLI package, then run:

```powershell
opencode2 --version
pwsh -NoProfile -File .\scripts\smoke-opencode.ps1
```

The smoke test creates a temporary consumer repository, installs Local mode, starts the V2 executable on loopback without a model call, and queries the documented health, agent, command, and tool-ID endpoints. It requires `opencode2` by default because the template uses OpenCode V2 permissions. Use `-AllowLegacyOpenCodeFallback` only for local compatibility investigation; falling back to the V1 `opencode` executable is expected to reject `template/opencode.json`. Default mode may use clearly labelled static definition/export fallbacks when a beta omits discovery payloads. Pass `-RequireRuntimeDiscovery` to fail if any agent, command, or typed-tool class cannot be proven through the running OpenCode server.

Required pull-request CI remains deterministic: the `validate` job runs static distribution validation and the isolated PowerShell test suite. `.github/workflows/opencode-v2-compatibility.yml` is separate. Manual and version-tag runs install an exact pinned V2 package and require runtime discovery; the scheduled/latest-beta job is an explicitly non-blocking canary. Update the pinned package deliberately only after its strict job proves the full installed surface.

Static validation remains useful for precise policy invariants, and the isolated PowerShell suite remains useful for deterministic state behavior. Neither substitutes for loading the distribution through the real OpenCode runtime.

## Pull-request documentation

The distribution PR template and installed consumer template must remain byte-identical:

- `.github/pull_request_template.md`
- `template/.ai/pull-request-template.md`

Update both in the same change. The template documents requirement, scope, evidence, tests, gates, review, risks, delivery state, and human checks.

## Version and release checklist

For a release:

1. Select the semantic version based on compatibility and behavior.
2. Update `VERSION` and `workflow.manifest.json` together.
3. Update documentation and examples.
4. Run distribution validation.
5. Run the isolated suite.
6. Run the OpenCode discovery smoke test.
7. Run `git diff --check`.
8. Inspect the complete diff for generated files, credentials, machine paths, and accidental consumer state.
9. Test a dry-run install/update against a representative repository.
10. Prepare a Conventional Commit without AI authorship attribution.
11. Use the normal human-reviewed PR/release process.

The workflow itself does not tag, publish a release, merge, or deploy automatically.

## Compatibility references

- [OpenCode configuration](https://opencode.ai/v2/docs/config/)
- [OpenCode CLI](https://opencode.ai/v2/docs/cli/)
- [OpenCode server and troubleshooting](https://opencode.ai/v2/docs/troubleshooting/)
- [OpenCode agents](https://opencode.ai/v2/docs/agents)
- [OpenCode permissions](https://opencode.ai/v2/docs/permissions)
- [OpenCode custom tools](https://opencode.ai/docs/custom-tools)
- [OpenCode commands](https://opencode.ai/v2/docs/commands/)
- [OpenCode skills](https://opencode.ai/v2/docs/skills/)
