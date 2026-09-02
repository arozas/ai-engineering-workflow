# Troubleshooting

## `opencode` is not recognized

The OpenCode CLI is missing from the current terminal's `PATH`, or the terminal predates installation. Follow the current [official installation documentation](https://opencode.ai/docs/) for your platform, close and reopen PowerShell, then verify:

```powershell
opencode --version
```

The command is `opencode`, not `opencode2`. Installing this repository does not install the OpenCode CLI.

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

An empty repository returns `NO PROJECT MODULES DETECTED`. The distribution returns `BOOTSTRAP NOT APPLICABLE`. Missing evidence should produce explicit unknowns, not repeated searches.

## Bootstrap proposes incorrect technology or architecture

Do not approve it. Correct the claim and request evidence. A manifest is stronger evidence than a folder name; architecture requires dependency/behavior evidence. Ask that unsupported fields remain empty or low confidence.

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

## Publish or PR evidence is rejected

`RecordPublish` requires schema-valid `.ai/runtime/<run-id>/publish.json`, then independently checks the named branch, current/persisted SHA, upstream, and exact remote ref with Git. Confirm the normal push completed, the branch still has the expected upstream, and no commit was added afterward.

`RecordPullRequest` requires schema-valid `.ai/runtime/<run-id>/pull-request.json`, then queries GitHub CLI. Confirm `gh auth status`, the PR number, base/head branches, head SHA, title, open state, and draft state. A ready-for-review, closed, retitled, or advanced PR no longer matches the approved evidence and is deliberately rejected.

## Commit message is rejected

Use a Conventional Commits subject, for example:

```text
fix(gates): bind evidence to the approved module matrix
```

Keep the subject concise and imperative. Remove `Co-authored-by`, `Generated-by`, `by Claude`, `byclaude`, or any model/tool attribution. The delivery workflow never amends a pushed commit; history rewriting remains manual.

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

Run `opencode --version`, then execute `scripts/smoke-opencode.ps1` locally. The test does not call a model; it verifies the local server health and discovery endpoints. Failure usually means the installed OpenCode version cannot parse `opencode.json`, one Markdown definition has invalid frontmatter, or `.opencode/tools/workflow.ts` cannot load. Inspect the reported missing names or temporary server error, fix the distribution source, and rerun all validation layers.

## Collecting useful support evidence

Share only sanitized information:

- workflow version from `VERSION` or installation metadata;
- exact failing command/tool name and exit code;
- deterministic error text;
- relevant schema-valid configuration with secrets removed;
- `/run-status` summary without sensitive ticket content;
- operating system, PowerShell, Git, and OpenCode versions.

Never share environment files, tokens, keys, credential files, production payloads, or unsanitized incident evidence.
