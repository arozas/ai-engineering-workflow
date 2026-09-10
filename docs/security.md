# Security and trust model

## Objectives

The workflow prevents an agent from converting a plausible narrative into unauthorized application or delivery state through defense in depth:

- least-privilege permissions;
- explicit human approvals;
- typed tools when available, with role-scoped deterministic script fallbacks;
- persisted state and artifact hashes;
- control-plane and worktree fingerprints;
- an exact approved quality matrix, including hashed run-specific verification;
- independent read-only review with reviewer-exclusive evidence capabilities;
- separately approved delivery operations;
- run-isolated staging and independently verified remote delivery evidence;
- default denial of secrets, external directories, destructive Git, deployments, and cloud mutation.

## Permission model

`opencode.json` defines the baseline. Sensitive environment, key, package-credential, and credential/secret JSON patterns are denied. External directories are denied. Shell commands are generally `ask`; limited read-only Git/GitHub observations are allowed while destructive and publishing operations are denied.

All `workflow_*` actions and managed script entry points are globally denied. Agent files reopen only required typed tools and exact script fallbacks. Fallback shell rules are `ask`, never automatic `allow`, and each role keeps a default `shell: deny`. Developer/tester may run only the gate script fallback, quick-fix only state/gate/classifier fallbacks, and reviewers only their role-bound recorder. Reviewer fallback staging is limited to `.ai/runtime/<run-id>/review-input.json`; application files remain read-only. The diagnostician receives no shell or custom workflow tools.

OpenCode V2 permission rules are ordered and the last match wins. Review them in order. See [OpenCode permissions](https://opencode.ai/v2/docs/permissions).

## Two deterministic transports

A V2 shell resource is a complete raw command. An automatically allowed rule ending in `*` can also match an appended shell suffix. That creates a command-composition boundary that is difficult to secure.

The preferred transport is `.opencode/tools/workflow.ts`, which:

1. Defines bounded input schemas.
2. Resolves scripts inside the active repository/worktree.
3. Starts `pwsh` using `Bun.spawn` with an argument vector.
4. Never constructs an interpolated shell command.
5. Returns structured exit code, stdout, and stderr.

This prevents an argument from becoming `;`, `&&`, a pipeline, or an appended command at the permission boundary. Scripts still validate values as an independent layer. See [OpenCode custom tools](https://opencode.ai/docs/custom-tools).

Some OpenCode V2 preview builds do not expose repository custom tools to the active model even when their definitions are valid. The workflow therefore supports a smaller compatibility transport: if a named typed tool is absent from the initial callable catalog or explicitly reports unavailable, the agent may invoke one exact script with `pwsh -NoProfile -File`. It must not search for tools, use `pwsh -Command`, compose shell expressions, retry, or fall back after a validation/policy failure. The role permission asks the user before that exact command runs.

Both transports execute the same scripts and validations. State transitions persist `lastTransitionTransport` as `typed-tool` or `deterministic-script`; the fallback does not create a weaker state machine. No MCP server, extra long-lived process, or additional tool schema is required.

## Control-plane protection

At run creation, state hashes `AGENTS.md`, `opencode.json`, `.ai/` except runtime/runs, and `.opencode/`. Sensitive transitions recompute the fingerprint. A mismatch stops the run, so implementation cannot weaken permissions, schemas, scripts, or instructions and use the weakened policy in the same run.

Application agents also have direct edit denials for these paths. The fingerprint detects changes by another process or incorrectly authorized command.

## Approved quality matrix

At `ApprovePlan`, state requires `.ai/runtime/<run-id>/verification.json`. For schema version 2 it validates the run ID, exact affected modules and paths, dependency versions and reasons, settled decisions, empty unresolved-decision list, constraints, estimates, phases, commands, duplicate protection, control-plane exclusion, and delivery/mutation denylist. It then copies the contract into canonical run storage. It builds the canonical matrix of module ID, normalized path, six ordered phases, configured commands, and approved task-specific commands. It persists the project SHA-256, verification SHA-256, matrix SHA-256, and module IDs. Schema version 1 remains accepted for already persisted legacy runs.

The runner accepts only `RunId`. It requires `IMPLEMENTING`, reconstructs the matrix, rejects stale state, accepts `.` as the repository root, and rejects escaping paths.

Gate evidence requires run/project/verification/runner/matrix identity plus fingerprints and results. Recording compares exact module count/order, IDs, paths, phase count/order/names, command count/order/text, derived statuses, hashes, worktree/control-plane stability, repository hygiene, approved-path scope, and control-plane output. Evidence omitting a module, omitting a run-specific command, substituting a harmless command, or claiming a blocked preflight passed is rejected even if schema-valid.

All candidate artifacts use `.ai/runtime/<run-id>/<artifact>`. State rejects a correct filename supplied from another run or from the shared runtime root. This prevents concurrent sessions from replacing one another's pending evidence.

## Reviewer independence

Review independence is enforced by capability and evidence, not only by prompt wording. `workflow_state` does not expose `RecordReview`, and orchestrator/implementation roles are denied direct review-artifact edits. The two reviewer roles have different exclusive typed tools and exact role-bound script fallbacks that stamp the expected role and workflow path.

The recorder recomputes severity counts and the verdict from structured findings, acceptance-criteria coverage, and escalation reason. State then validates the schema and independently binds the artifact to the current run, SHA, worktree fingerprint, and canonical gate hash. A reviewer cannot declare `PASS` while reporting a `BLOCKER`, `HIGH`, or uncovered acceptance criterion, and another role cannot complete the review through the normal state capability.

## Quality command risks

Configured commands are executable repository policy. Bootstrap cites their source and the user approves them. Run-specific commands are executable per-task policy and require explicit approval with the plan. Typed gates prevent agent selection changes; they cannot make a malicious approved command safe.

Review command changes like CI scripts. Never configure deployment, production access, secret retrieval, remote mutation, history rewrite, or data repair. A command that changes delivery content fails worktree stability even when it exits zero.

## Secrets and incident evidence

The workflow denies common secret paths and never requests secret access. Sanitize incident evidence before it enters prompts or `.ai/runtime/<run-id>/`. Do not paste tokens, connection strings, private keys, production payloads, or personal data into tickets, runs, or PR drafts.

Diagnostic artifacts assert that no secrets were accessed and no production mutation occurred. Validation rejects unsafe claims.

## Delivery safety

Delivery begins with shell denied. Read-only observations are reopened, while mutation scripts remain `ask` and require exact approval.

Rules include:

- no default-branch or detached-HEAD mutation;
- no force push, tags, ref deletion, or history rewrite;
- no broad staging;
- Conventional Commits only;
- no AI authorship attribution;
- draft PR with explicit base/head only;
- no reviewers, labels, assignees, comments, merge, or auto-merge;
- no release, deployment, secret, workflow-dispatch, or cloud mutation.

Gate/review evidence is tied to the exact worktree diff. Later changes invalidate readiness. Branch recording proves the new branch was created from the run's named starting branch at the persisted SHA with a clean worktree. Commit recording validates the message returned by Git, rejects forbidden/non-Conventional attribution, compares the real changed paths, and proves the committed diff is the reviewed diff. Publish recording uses `git ls-remote` to prove the configured upstream ref points to the persisted commit. Draft-PR recording uses `gh pr view` to prove the number, URL, base, head, head SHA, title, open state, and draft state. Agent-authored delivery JSON alone cannot advance state.

## Installation trust

Local exclusion is not access control. Files still exist and can be changed; hashes and fingerprints detect drift. Shared mode makes control-plane changes visible to review but increases repository surface. Teams should add ownership/branch policy where appropriate.

## Outside scope

The workflow does not secure a compromised host, malicious runtime/dependency, tampered OpenCode binary, administrator process, or unsafe project command approved by the user. Use OS isolation, dependency security, CI protections, branch rules, ownership, and secret management alongside it.

Security, authorization, authentication, data integrity, concurrency, migrations, public contracts, infrastructure, dependencies, and generated code are never fast-path eligible.
