# Workflow evaluations

This directory defines the evidence contract for measuring whether the workflow actually reduces cost without lowering quality.

Use [`benchmark-suite-playbook.md`](benchmark-suite-playbook.md) to define the first real suite. Do not invent measurements; record only provider or OpenCode usage observed during comparable runs.

Use the same repository state, requirement, provider account, model assignments, and acceptance tests for each compared path. A useful initial suite contains five bounded bug fixes and five medium features. Run each scenario through `manual`, `standard`, and, only when eligible, `fast-path`.

Record actual provider or OpenCode usage; never estimate or invent token counts. Store benchmark result files outside this repository when they contain proprietary prompts, source excerpts, account prices, or internal defect information. The schema contains no secrets and can be copied wherever the measurements are kept.

Each run records:

- input and output tokens
- actual cost in USD at execution time
- elapsed duration
- correction cycles
- final acceptance result
- defects found after the workflow declared completion
- the exact model profile used
- tool calls and subagent delegations
- duplicate tool calls and protocol violations
- whether an agent exhausted its configured step budget

Validate and summarize a result file:

```powershell
pwsh -NoProfile -File .\scripts\summarize-evaluations.ps1 `
  -InputPath "C:\Measurements\workflow-benchmark.json" `
  -OutputPath "C:\Measurements\workflow-benchmark-summary.md"
```

The summary reports cost, quality, and loop indicators by workflow path. A duplicate call means the same tool and materially unchanged arguments were issued without relevant state or repository change. A protocol violation includes repeated searches, repeated unchanged state/gate/classifier/review calls, recursive evidence delegation, or continuing past a required approval/stop boundary. Token savings are meaningful only when the compared paths use equivalent scenarios and model profiles; interpret mixed profiles separately.
