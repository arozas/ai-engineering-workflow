---
name: quality-gate
description: Run exact configured quality commands deterministically and report factual exit-based results
compatibility: opencode-v2
---

## Source of truth

Read affected modules from `.ai/project.json`. For each module, run commands exactly as configured, with the module `path` as working directory, in this fixed phase order:

1. `restore`
2. `build`
3. `lint`
4. `typecheck`
5. `test`
6. `e2e`

Within each phase, preserve array order. An empty phase is `NOT CONFIGURED`, not PASS. Never substitute, repair, append flags to, or skip a configured command. Ask for shell approval when policy requires it.

## Deterministic result

- Exit code zero: PASS for that command.
- Nonzero exit code, timeout, missing executable, permission denial, or interrupted execution: FAIL.
- Not attempted: NOT RUN.
- Stop the module on the first FAIL unless the user explicitly requests a full diagnostic run; remaining commands are NOT RUN.
- Overall PASS requires every configured command for every affected module to PASS.
- A module with no configured commands cannot receive overall PASS; report INCOMPLETE CONFIGURATION.

## Report

For every command include module, phase, working directory, exact command, exit code, duration when available, status, and concise failure evidence. End with module summaries and one overall verdict. LLM opinion never overrides these results.
