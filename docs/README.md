# Documentation

This directory contains the detailed operating and design documentation for AI Engineering Workflow. The repository README intentionally remains a short entry point.

## Start here

| Document | Use it when |
| --- | --- |
| [Architecture and design](architecture.md) | You need to understand the distribution, installed control plane, agents, state machine, and trust boundaries. |
| [Installation](installation.md) | You are installing, updating, or creating a consumer project and need to choose Local or Shared mode. |
| [Workflows](workflows.md) | You are deciding between standard work, fast path, diagnosis, or guarded delivery. |
| [Project context](project-context.md) | You are bootstrapping or refreshing modules, stacks, architectures, quality commands, or Azure DevOps integration. |
| [Security](security.md) | You need the permission model, typed-tool boundary, deterministic evidence rules, or threat model. |
| [Models and efficiency](models-and-efficiency.md) | You are assigning model classes to agents or optimizing context and token usage. |
| [Extending and validation](extending-and-validation.md) | You are adding a preset, skill, agent, command, tool, schema, or release. |
| [Troubleshooting](troubleshooting.md) | Installation, bootstrap, state, gate, OpenCode, or delivery checks fail. |

## Documentation principles

- Examples use PowerShell 7 because the distribution scripts target Windows and cross-platform `pwsh`.
- Commands shown for maintainers are not automatically available to every installed agent. Agent permissions are defined separately.
- `.ai/project.json` is the consumer project's machine-readable context after approved bootstrap.
- `.ai/runs/` contains canonical evidence and `.ai/runtime/<run-id>/` contains isolated staging; neither is application delivery content.
- Project behavior is evidence-driven. Unknowns remain unknown instead of being filled with fashionable defaults.
- An LLM statement is never a substitute for schema validation, an exit code, a hash, or a persisted approval.

## Source documentation

The implementation is also documented at its source boundaries:

- `workflow.manifest.json` defines distribution paths and the release version.
- `template/AGENTS.md` defines installed repository-wide behavior.
- `template/opencode.json` defines global OpenCode permissions.
- `template/.opencode/agents/` defines role-specific boundaries.
- `template/.opencode/tools/workflow.ts` exposes typed deterministic tools.
- `template/.opencode/skills/` contains reusable operating instructions.
- `template/.ai/*.schema.json` defines persisted contracts.
- `template/.ai/scripts/` contains deterministic policy, state, gate, and delivery implementations.

## Official OpenCode documentation

- [Configuration](https://opencode.ai/docs/config/)
- [CLI](https://opencode.ai/docs/cli/)
- [Server](https://opencode.ai/docs/server/)
- [Agents](https://opencode.ai/v2/docs/agents)
- [Permissions](https://opencode.ai/v2/docs/permissions)
- [Custom tools](https://opencode.ai/docs/custom-tools)
- [Commands](https://opencode.ai/docs/commands/)
- [Skills](https://opencode.ai/docs/skills/)

The distribution targets OpenCode V2 semantics. In particular, permission rules are ordered and shell permission resources represent complete raw commands. That is why automatically allowed workflow operations are exposed as typed custom tools instead of permissive trailing-wildcard shell rules.
