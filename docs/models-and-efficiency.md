# Model roles and token efficiency

## Configure models per agent

OpenCode agent definitions live under `template/.opencode/agents/` in the distribution and `.opencode/agents/` after installation. Set the agent frontmatter `model` to a provider/model identifier available in your OpenCode configuration:

```yaml
---
description: Plans and coordinates the workflow
mode: primary
model: provider/model-id
---
```

Keep provider credentials outside the repository and follow the [OpenCode agent](https://opencode.ai/v2/docs/agents) and [model/provider](https://opencode.ai/docs/models/) documentation. Model availability and identifiers vary by provider and account.

Changing a model is a control-plane change. In a consumer repository, make it through an explicitly reviewed workflow configuration update. Active runs will detect the changed agent file and must be restarted.

## Recommended model classes

Choose capabilities by role rather than hard-coding product names in the distribution.

| Agent | Recommended model class | Why |
| --- | --- | --- |
| `orchestrator` | Frontier reasoning model | It must integrate requirements, repository evidence, risks, module boundaries, state, and multiple handoffs without silently changing scope. |
| `developer` | Strong implementation model | It needs reliable code generation, local convention adherence, and disciplined execution of an approved plan. |
| `reviewer` | Strong analysis model | Independent defect detection, contract reasoning, and evidence-to-finding traceability matter more than editing speed. |
| `tester` | Fast, economical coding model | Test scaffolding and scenario translation are bounded, while deterministic gates provide the final factual result. Use a stronger model for complex test architecture. |
| `diagnostician` | Frontier analysis model | Competing hypotheses, falsification, uncertainty, and production-risk reasoning require high analytical quality. |
| `quick-fix` | Balanced implementation model | It must be capable enough for a small fix but efficient enough to preserve the fast path's value. |
| `quick-reviewer` | Fast analytical model | It receives a compact evidence packet and performs a narrow independent review. |
| `delivery` | Deterministic, economical instruction-following model | Operations are tightly scripted; exact compliance is more valuable than creative reasoning. |

Use stronger classes when domain complexity demands them. For example, cryptography, concurrency, or subtle compiler behavior may justify a frontier reviewer/tester even when the role normally uses an economical model.

## Is the workflow token-efficient?

The standard workflow optimizes for reliability per approved change, not minimum tokens per prompt. It intentionally pays for planning, specialized context, independent review, and correction when risk justifies them. Compared with repeatedly iterating in a general editor chat, it can still reduce waste because approvals and evidence are persisted, agents receive bounded packets, and failed stages have explicit stop conditions.

It becomes inefficient when every typo or obvious one-file change is routed through the full orchestrator/developer/tester/reviewer chain. The fast path addresses that case.

## Efficiency mechanisms

### Route by risk

- Use `/quick-fix` only for known-cause, one-module bugs within hard limits.
- Use `/small-task` for bounded docs/config/mechanical work.
- Use `/diagnose` when the cause is unknown instead of paying developers to implement speculative fixes.
- Use `/ticket` for everything that affects contracts, dependencies, multiple modules, security, data, concurrency, migrations, generated code, or infrastructure.

### Load context selectively

`.ai/project.json` maps modules to skills. Agents load only the affected module's stack, architecture, and project skills. Avoid passing full repository inventories, unrelated files, unused skills, or complete conversation history.

### Persist decisions

Requirements, plans, hashes, gates, reviews, and run status live under `.ai/runs/`. A resumed session reads the canonical evidence instead of reconstructing decisions from a long conversation.

### Bound exploration

Bootstrap, fast-path diagnosis, production diagnosis, correction cycles, and review packets all have explicit budgets. Repeating equivalent searches is a stop signal, not a reason for more browsing.

### Use deterministic computation

Profiling, schema validation, scope counts, Git fingerprints, command execution, verdict derivation, and delivery checks are scripts/tools. Spending model tokens to estimate these facts would be both more expensive and less reliable.

### Stop invalid work early

`PLAN INVALIDATED`, `FAST PATH INVALIDATED`, `DIAGNOSIS_BLOCKED`, stale quality matrices, and correction limits stop unproductive loops. The workflow never keeps iterating simply because another agent could try again.

## Measuring instead of guessing

`evaluations/benchmark.schema.json` defines comparable runs with workflow path, model profile, input/output tokens, cost, duration, corrections, result, and escaped defects. Record the same representative scenario under standard and fast-path routes, then summarize:

```powershell
pwsh -NoProfile -File .\scripts\summarize-evaluations.ps1 `
  -InputPath .\evaluations\your-benchmark.json `
  -OutputPath .\evaluations\your-summary.md
```

Evaluate at least:

- total input and output tokens;
- cost and elapsed time;
- correction cycles;
- gate/review success;
- escaped defects or human-discovered misses;
- frequency of inappropriate fast-path escalation or acceptance.

The cheapest run is not efficient if it ships defects. The most thorough run is not efficient if a deterministic one-file task consumes four large-model handoffs.

## Practical defaults

Start with a high-capability orchestrator and diagnostician, a strong developer/reviewer, a faster tester/quick-reviewer, a balanced quick-fix model, and an economical delivery model. Keep temperature/reasoning settings conservative for state and delivery roles. Benchmark your own ticket mix before optimizing further.

Do not use model choice to weaken permissions or deterministic checks. A more capable model is not a security boundary, and a cheaper model should not be asked to compensate for missing project context.
