---
name: quality-gate
description: Run exact configured quality commands deterministically and report factual exit-based results
compatibility: opencode-v2
---

## Source of truth

Read affected modules from `.ai/project.json`, then invoke the managed runner once with the affected module IDs:

```powershell
pwsh -NoProfile -File .ai/scripts/run-quality-gates.ps1 -ModuleId <module-id>
```

For multiple modules, pass their IDs as a comma-separated value. The runner validates project configuration, executes commands exactly as configured with the module `path` as working directory, writes schema-valid evidence atomically to `.ai/runtime/gates.json`, and returns a factual exit code. Do not execute an equivalent hand-written sequence and do not create, repair, or edit `gates.json` manually.

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

Use the generated artifact for every command's module, phase, working directory, exact command, exit code, duration, status, stdout/stderr evidence, and truncation flag. Call `workflow-state.ps1 -Action RecordGates` with a PASS verdict only when the artifact says overall PASS; any other artifact result is recorded as FAIL. State validation checks the schema, project hash, runner hash, command-derived verdict, worktree fingerprint, and control-plane fingerprint before accepting it. LLM opinion never overrides these results.
