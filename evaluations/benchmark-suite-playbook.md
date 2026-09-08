# Benchmark suite playbook

Use this playbook to create the first real evidence set for token efficiency and quality. Do not commit proprietary prompts, source excerpts, customer data, incident details, provider invoices, or internal defect information to this repository. Store measured result files outside the distribution repository unless they are fully sanitized.

## Goal

Measure whether the workflow reduces repeated agent iteration without lowering delivery quality.

The comparison is valid only when every workflow path uses:

- the same repository state;
- the same requirement or defect report;
- the same acceptance tests;
- the same provider account and pricing date;
- the same model profile category;
- the same human review standard.

## Scenario set

Start with ten scenarios:

| ID pattern | Category | Count | Required characteristics |
| --- | --- | ---: | --- |
| `bugfix-01` to `bugfix-05` | `bugfix` | 5 | Known expected behavior, reproducible locally, low-to-medium scope, objective pass/fail verification. |
| `feature-01` to `feature-05` | `feature` | 5 | Clear acceptance criteria, one or two modules, no production mutation, no secret access, objective pass/fail verification. |

Optionally add `small-task-*` scenarios after the first run when documentation, local configuration, or mechanical updates are common in the target project.

Do not include high-risk production incidents in the first efficiency benchmark. Measure those separately with diagnosis-specific outcomes such as confirmed root cause, missing evidence, escalation, and time to safe handoff.

## Workflow paths

Run every scenario through:

1. `manual`: the current human/agent process used before this workflow.
2. `standard`: `/ticket` -> approval -> `/implement` -> `/test` -> `/review`.
3. `fast-path`: only when the scenario passes `/quick-fix` or `/small-task` eligibility.

If a scenario is not fast-path eligible, record only `manual` and `standard`; do not force eligibility.

## Measurements

For every run, record actual values only:

- input tokens;
- output tokens;
- total cost in USD at execution time;
- elapsed duration in seconds;
- correction cycles;
- final result: `PASS` or `FAIL`;
- escaped defects after the workflow declared completion;
- exact model profile used.
- total tool calls and subagent delegations;
- duplicate tool calls and protocol violations;
- whether any agent reached its configured step limit.

Use provider or OpenCode usage exports whenever available. If a value cannot be measured, leave the run out of the benchmark instead of estimating it.

Run at least one suite with the intended economical model profile and one with the intended strong-model profile. Keep scenarios and acceptance tests identical. The purpose is not to require equal prose or implementation style; it is to prove that both profiles terminate, obey gates, and meet acceptance criteria while exposing their real token and tool-call cost.

## Quality rules

A run is `PASS` only when:

- all acceptance criteria are satisfied;
- required tests/checks pass;
- no high-severity review finding remains unresolved;
- the final diff is limited to the scenario scope.

A run is `FAIL` when it ships an incorrect behavior, misses a required criterion, bypasses verification, introduces a regression, or needs unplanned human repair after completion.

## Result file

Create a private result file that validates against `benchmark.schema.json`, then summarize it:

```powershell
pwsh -NoProfile -File .\scripts\summarize-evaluations.ps1 `
  -InputPath "C:\Measurements\workflow-benchmark.json" `
  -OutputPath "C:\Measurements\workflow-benchmark-summary.md"
```

Interpret token savings only beside success rate and escaped defects. A cheaper path that lowers acceptance quality is not an improvement.
