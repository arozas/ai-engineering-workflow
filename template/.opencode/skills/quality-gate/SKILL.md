---
name: quality-gate
description: Run exact configured quality commands deterministically and report factual exit-based results
compatibility: opencode-v2
---

## Source of truth

At plan approval, `workflow_state` persists the exact affected module IDs and hashes the corresponding quality-command matrix from `.ai/project.json`. Invoke `workflow_gate` once with only the approved run ID. The caller cannot select or omit modules.

The runner validates the current project configuration and persisted run, rejects a stale project or matrix, executes every frozen command with the module `path` as working directory, writes schema-valid evidence atomically to `.ai/runtime/<run-id>/gates.json`, and returns a factual exit code. Do not execute an equivalent hand-written sequence and do not create, repair, or edit `gates.json` manually.

The runner uses this fixed phase order:

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
- The worktree fingerprint before and after the gate must match. A command that changes delivery content makes the overall result FAIL.
- Runner exit `0` means PASS, `1` means FAIL, `2` means INCOMPLETE CONFIGURATION, and `3` means the runner could not produce trustworthy evidence.

## Report

Use the generated artifact for every command's module, phase, working directory, exact command, exit code, duration, status, stdout/stderr evidence, and truncation flag. Call `workflow_state` action `RecordGates` with a PASS verdict only when the artifact says overall PASS; any other artifact result is recorded as FAIL. State validation checks the run ID, exact affected-module set, phase and command matrix, schema, project hash, runner hash, command-derived verdict, worktree fingerprint, and control-plane fingerprint before accepting it. LLM opinion never overrides these results.
