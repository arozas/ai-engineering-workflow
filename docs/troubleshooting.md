# Troubleshooting

## `opencode2` is not recognized

The OpenCode V2 CLI is missing from the current terminal's `PATH`, or the terminal predates installation. Follow the current [official V2 installation documentation](https://opencode.ai/v2/docs) for your platform, close and reopen PowerShell, then verify:

```powershell
opencode2 --version
```

This workflow uses OpenCode V2 configuration and permissions, so the command is `opencode2`. Installing this repository does not install the OpenCode CLI.

After installation, run `/workflow-doctor` from OpenCode or invoke the same read-only check directly:

```powershell
pwsh -NoProfile -File .ai/scripts/check-workflow-runtime.ps1
```

`RUNTIME_WARNING` commonly means multiple global installations or shims are visible. Use the reported `selectedOpenCode`, installation directories, versions, and callable flags to correct `PATH`; then restart PowerShell and OpenCode. The doctor never changes the machine.

## Installation reports conflicts

The installer refuses to overwrite existing managed destinations. Run with `-DryRun`, inspect each conflict, and decide whether it is an existing project instruction, an older managed installation, or unrelated content.

- For an existing managed installation, use `scripts/update.ps1`.
- For project-owned instructions, merge them deliberately into supported project rules or retain them and do not install blindly.
- Do not remove files simply to bypass the safety check.

## Local mode says a path is tracked

`.git/info/exclude` cannot hide tracked files. The repository already versions one or more workflow paths. Use Shared mode, or deliberately untrack/migrate those paths through the repository's normal review process. The installer will not mutate the index for you.

## Local installation appears in Git status

Check that installation completed, the target is the same Git worktree, and the managed block exists in that worktree's `.git/info/exclude`. Nested repositories and worktrees can have different Git directories.

Run the installer dry run again. Do not add broad tracked `.gitignore` entries as an automatic workaround; that changes repository policy for every clone.

## `/ai-bootstrap` keeps exploring

Current bootstrap has strict scan budgets and should stop after one profile plus bounded evidence reads. Confirm the installed workflow version is current and `/ai-bootstrap` is running in the consumer application, not the distribution repository.

If OpenCode says `Unknown tool 'workflow_bootstrap_prepare'`, current bootstrap should run the controlled fallback `pwsh -NoProfile -File .ai/scripts/prepare-bootstrap-proposal.ps1`. If it starts broad manual exploration instead, update the installed workflow from this distribution before retrying.

If `/ai-bootstrap` loads `project-context`, asks for a generic bootstrap input confirmation, explores source files by itself, or writes final `.ai/project.json` immediately after a short `yes`, the installed control plane is stale or inconsistent. Current bootstrap must call `workflow_bootstrap_prepare` or its fallback and write only draft files under `.ai/bootstrap-proposal/` before approval.

If a second `/ai-bootstrap` appears ready to regenerate an unchanged proposal, stop it and update the installed workflow. Current behavior returns `BOOTSTRAP_PROPOSAL_CURRENT` and preserves edits. `BOOTSTRAP_PROPOSAL_STALE` requires a deliberate choice; use `/ai-bootstrap --force` only to replace the draft. Use `/ai-bootstrap-enhance` for one optional bounded semantic pass instead of asking the bootstrap command to explore repeatedly.

## An agent repeats tools or appears stuck in a loop

Use `/run-status <run-id>` once. Current agents call `workflow_next` once, take one legal action, and stop at approvals or terminal states. Repeating an unchanged state, gate, classifier, review, delegation, or search is a protocol violation. Do not keep prompting the same model to continue indefinitely: preserve the run ID and artifacts, then retry the role with a stronger model if needed.

For bootstrap, inspect `.ai/bootstrap-proposal/approval.md` and `evidence.md`; for gates, inspect `.ai/runtime/<run-id>/gates.json`. The full evidence is persisted even though model-facing tool output is intentionally compact. Record duplicate calls, violations, and step-limit exhaustion in the benchmark rather than increasing every agent's step budget.

If `/ai-bootstrap` repeats that the profile succeeded and that it must load `repo-bootstrap`, `project-profiler`, and `project-skill-builder`, the runtime/model is treating skill loading as narration instead of an action. Current bootstrap defines concrete file reads for those skills: `.opencode/skills/repo-bootstrap/SKILL.md`, `.opencode/skills/project-profiler/SKILL.md`, and `.opencode/skills/project-skill-builder/SKILL.md`. Update the installed workflow before retrying.

If the proposal is too large for the chat or a provider returns HTTP 413, review `.ai/bootstrap-proposal/evidence.md` and edit the draft files directly. Do not rerun the whole bootstrap just to correct a proposal field. Run `/ai-bootstrap-apply` after the draft files are corrected.

An empty repository returns `NO PROJECT MODULES DETECTED`. The distribution returns `BOOTSTRAP NOT APPLICABLE`. Missing evidence should produce explicit unknowns, not repeated searches.

## Bootstrap proposes incorrect technology or architecture

Do not approve it. Correct the claim and request evidence. A manifest is stronger evidence than a folder name; architecture requires dependency/behavior evidence. Ask that unsupported fields remain empty or low confidence. A conventional controller/model/repository application should normally use `architecture-simple-layered`, not `architecture-clean`, unless inward dependency boundaries and use-case/application layers are proven.

Bootstrap writes only after explicit approval of the complete JSON, rules, generated manifest, and generated skills.

## `PROJECT_VALID` fails

Review the deterministic error. Common causes are:

- project JSON does not match the schema;
- duplicate/invalid module IDs;
- absolute, missing, or escaping module paths;
- missing context skills;
- multiline/unsafe commands;
- stale profile fingerprint;
- generated-skill manifest mismatch;
- missing evidence paths or skill sections;
- structural repository drift requiring `/ai-refresh`.

Do not edit the validator to make an invalid configuration pass.

## A root-level project gate fails with a path error

Current versions support a module path of `.`. Confirm both `.ai/project.json` and the installed runner are current, then start a new run. Older runners incorrectly treated the repository root as an escape attempt.

## Quality gates say the plan is stale

`.ai/project.json` or its selected command matrix changed after plan approval. This is intentional. Revalidate project context, create or return to planning, present the new commands/module list, and obtain explicit approval. Do not edit state hashes or gate evidence.

## Quality gate cannot find the run

The gate tool requires a persisted run in `IMPLEMENTING` status with an approved quality plan. Use `/run-status <run-id>`. If the run predates quality-plan binding, create a new run and approve its affected modules.

## Gate evidence is rejected

Only `.ai/runtime/<run-id>/gates.json` written by `workflow_gate` for the same run is accepted. Rejection may indicate:

- wrong run ID;
- omitted or reordered module;
- changed phase or command;
- project/runner/matrix hash mismatch;
- manually authored or repaired JSON;
- worktree changes during/after gates;
- control-plane changes;
- verdict not matching command-derived status.

An artifact at `.ai/runtime/gates.json` or under another run ID is rejected even when its content is otherwise valid. Use the exact run ID throughout the command and do not move evidence between runtime directories.

Rerun the complete gate after resolving the underlying drift. Never repair evidence manually.

## Gate returns incomplete configuration

An affected module has no configured commands. Add evidence-backed commands through `/ai-refresh` and approve the configuration, or acknowledge that the module cannot yet produce a trustworthy PASS. Empty phases are acceptable; an entirely empty module matrix is not.

## State transition or fingerprint fails

Use `/run-status <run-id>`. Typical causes are current HEAD changed, worktree changed after gates, a canonical artifact was edited, or control-plane files changed.

Restore the exact reviewed state if appropriate, or begin a new run. Do not edit `.ai/runs/<id>/state.json` or canonical artifacts.

## Fast path escalates a small change

Size is only one condition. Dependencies, contracts, security, data integrity, concurrency, migrations, generated code, CI/CD, infrastructure, multiple modules, unknown root cause, missing verification, binary/unmeasurable files, or actual-scope expansion require `/ticket` or `/diagnose`.

Do not loosen schema ceilings to force eligibility. Project settings may only be stricter.

## Diagnosis is blocked

`DIAGNOSIS_BLOCKED` means evidence cannot distinguish credible hypotheses. Read `missingEvidence`, sanitize and supply exactly that evidence, then explicitly approve another bounded iteration if available. Do not implement the most plausible hypothesis as a production fix.

## Delivery check fails

Confirm:

- run status is `READY_FOR_DELIVERY`;
- deterministic gates and review belong to the exact current diff;
- current branch is named and not protected/default;
- Git status matches the proposed operation;
- remote and base/head are explicit;
- required CLI authentication exists;
- no workflow/control-plane drift occurred.

Each delivery operation needs fresh approval. Approval for commit is not approval for push or PR creation.

## Branch evidence is rejected

The guarded branch script requires the run to be `PLAN_APPROVED`, the current branch to equal the run's recorded `baseBranch`, HEAD to equal the run SHA, and the worktree to be clean. It then writes `.ai/runtime/<run-id>/branch.json` and records it while remaining in `PLAN_APPROVED`.

If the branch was created but evidence recording failed, do not create another branch blindly. Inspect the reported branch, restore a clean matching state, and either reconcile the exact run or start a new run. Directly editing `branch.json` or `state.json` is not a supported recovery path.

## Review evidence is rejected

Only the reviewer-specific typed tool should create `review.json`. Rejection means the reviewer role or route was wrong, the gate/canonical artifact changed, the SHA or worktree no longer matches, severity counts are inconsistent, or acceptance coverage requires `FAIL`. Rerun the gate if the diff changed and delegate a fresh evidence packet; do not ask the orchestrator to record `RecordReview` directly.

## Publish or PR evidence is rejected

`RecordPublish` requires schema-valid `.ai/runtime/<run-id>/publish.json`, then independently checks the named branch, current/persisted SHA, upstream, and exact remote ref with Git. Confirm the normal push completed, the branch still has the expected upstream, and no commit was added afterward.

`RecordPullRequest` requires schema-valid `.ai/runtime/<run-id>/pull-request.json`, then queries GitHub CLI. Confirm `gh auth status`, the PR number, base/head branches, head SHA, title, open state, and draft state. A ready-for-review, closed, retitled, or advanced PR no longer matches the approved evidence and is deliberately rejected.

## Commit message is rejected

Use a Conventional Commits subject, for example:

```text
fix(gates): bind evidence to the approved module matrix
```

Keep the subject concise and imperative. Remove `Co-authored-by`, `Generated-by`, `by Claude`, `byclaude`, or any model/tool attribution. State reads the final message from Git and compares it with `commit.json`, so editing only the evidence cannot bypass the rule. It also compares the exact changed-file list and parent SHA. The delivery workflow never amends a pushed commit; history rewriting remains manual.

## Update refuses a locally changed file

The updater compares the current file with its installed hash and stops to protect customization. Review the distribution diff and decide whether to:

- keep the customization and port the upstream change manually;
- move project-specific content into `.ai/project-rules.md` or a generated project skill;
- deliberately accept the new managed file in a separately reviewed update.

Do not overwrite blindly; an agent permission or schema customization may be security-relevant.

## GitHub Actions says tests passed but the job exits 1

The suite includes child processes that intentionally return nonzero for negative assertions. The top-level test script must explicitly exit zero after all assertions. Use the current `tests/Run-Tests.ps1`; older versions could leak the last expected child exit code to the job.

The workflow uses the current Node 24-based checkout action. If a runtime deprecation warning reappears, update to an official compatible action release; do not suppress it by forcing an insecure runtime.

## OpenCode smoke discovery fails

Run `opencode2 --version`, then execute `scripts/smoke-opencode.ps1` locally. The test does not call a model; it verifies local server health and prefers runtime agent, command, and typed-tool discovery. Current V2 preview builds may return empty agent/command payloads or omit typed-tool discovery; default mode verifies installed Markdown definitions and TypeScript exports statically and names each fallback. Use `-RequireRuntimeDiscovery` when selecting a pinned compatible release: it rejects all static fallbacks. The script is V2-only by default and safely launches Windows `.cmd` shims from paths containing spaces. If `opencode2` is missing from `PATH`, install the current V2 CLI or fix the terminal environment before retrying. Other failures usually mean the installed OpenCode version cannot parse `opencode.json` or the current preview changed its headless API behavior.

Use `-AllowLegacyOpenCodeFallback` only for local compatibility investigation. The fallback may select the V1 `opencode` executable and is expected to reject this workflow's V2 permissions.

## A `workflow_*` typed tool is unavailable

This is a supported transport condition in V2 preview builds. The agent must inspect only the initial callable-tool catalog. When the named tool is absent—or one call explicitly says unknown, unavailable, removed, or not callable—it uses the role-approved deterministic script once. It must not search for tools or retry.

The fallback is safe only when the command starts exactly with `pwsh -NoProfile -File .ai/scripts/` and names the documented script. State transitions also include `-Transport deterministic-script`. The permission prompt is expected because script fallbacks are `ask`, not `allow`.

Do not approve commands containing `powershell`, `pwsh -Command`, `;`, `&&`, `|`, redirection, substitutions, or an unrelated script. If the typed tool returned a schema, validation, policy, stale-state, or transition error, the agent must stop; script fallback must never be used to bypass that result.

After a successful state transition, inspect the reported `lastTransitionTransport`. Both `typed-tool` and `deterministic-script` run the same validator and persist the same canonical evidence. No MCP server is required.

## Collecting useful support evidence

Share only sanitized information:

- workflow version from `VERSION` or installation metadata;
- exact failing command/tool name and exit code;
- deterministic error text;
- relevant schema-valid configuration with secrets removed;
- `/run-status` summary without sensitive ticket content;
- operating system, PowerShell, Git, and OpenCode versions.

Never share environment files, tokens, keys, credential files, production payloads, or unsanitized incident evidence.
