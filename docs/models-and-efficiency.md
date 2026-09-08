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

Keep provider credentials outside the repository and follow the [OpenCode agent](https://opencode.ai/v2/docs/agents) and [model/provider](https://opencode.ai/v2/docs/models/) documentation. Model availability and identifiers vary by provider and account.

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
| `evidence-reader` | Fast analytical model | It answers one precise code question under an eight-step and ten-file budget. |
| `bootstrap-enricher` | Strong analysis model, optional | It extracts project-specific semantics from a small representative packet; skip it when the deterministic baseline is sufficient. |

Use stronger classes when domain complexity demands them. For example, cryptography, concurrency, or subtle compiler behavior may justify a frontier reviewer/tester even when the role normally uses an economical model.

## Is the workflow token-efficient?

The standard workflow optimizes for reliability per approved change, not minimum tokens per prompt. It intentionally pays for planning, specialized context, independent review, and correction when risk justifies them. Compared with repeatedly iterating in a general editor chat, it can still reduce waste because approvals and evidence are persisted, agents receive bounded packets, and failed stages have explicit stop conditions.

It becomes inefficient when every typo or obvious one-file change is routed through the full orchestrator/developer/tester/reviewer chain. The fast path addresses that case.

## Small and large model compatibility

The default route is designed to remain usable by small instruction-following models without reducing what a larger model can reason about:

- deterministic scripts own profiling, quality execution, state transitions, fingerprints, and verdict derivation;
- every agent has a hard `steps` ceiling, and specialized evidence agents use eight steps;
- agent-specific skill allowlists prevent OpenCode from advertising the full skill catalog on every turn;
- `workflow_next` returns only compact state, budgets, artifacts, and legal next actions;
- gate responses contain the verdict and failures while full command evidence remains on disk;
- repeated bootstrap preserves a current draft, and repeated unchanged gates reuse validated evidence;
- prompts define repeated unchanged inspection, delegation, classification, gate, or review calls as protocol violations.
- missing typed tools use one exact deterministic script fallback without tool search or retries;
- the compatibility path requires no MCP server, so it adds no MCP tool schemas or long-lived server context to each model turn.

For bootstrap, `/ai-bootstrap` is the economical deterministic baseline. `/ai-bootstrap-enhance` is an optional second stage for a stronger model. It reads only the generated evidence packet and representative files, so a larger model can extract semantic local conventions without reopening an unlimited repository search. The large model is not artificially restricted to the small model's reasoning quality; both share the same safety and iteration boundaries.

These controls prevent unbounded behavior; they cannot guarantee that every small model follows every instruction or produces the same plan quality as a frontier model. If a model reaches its step limit, repeats a tool call, invents missing evidence, or fails a structured handoff, treat that as an evaluation failure and switch the affected role to a stronger model. Do not increase all step budgets first. Large models follow the same transport policy but retain the full evidence packet and reasoning budget; the fallback does not reduce their analytical capability.

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

Bootstrap, ticket evidence reading, fast-path diagnosis, production diagnosis, correction cycles, and review packets all have explicit budgets. The `evidence-reader` accepts one precise question, reads at most six production and four test files, and stops. Repeating equivalent searches is a protocol violation, not a reason for more browsing.

### Use deterministic computation

Profiling, schema validation, scope counts, Git fingerprints, command execution, verdict derivation, and delivery checks are scripts/tools. Spending model tokens to estimate these facts would be both more expensive and less reliable.

### Stop invalid work early

`PLAN INVALIDATED`, `FAST PATH INVALIDATED`, `DIAGNOSIS_BLOCKED`, stale quality matrices, and correction limits stop unproductive loops. The workflow never keeps iterating simply because another agent could try again.

## Measuring instead of guessing

`evaluations/benchmark.schema.json` defines comparable runs with workflow path, model profile, input/output tokens, cost, duration, corrections, result, and escaped defects. It also accepts operational loop indicators: tool calls, duplicate tool calls, subagent delegations, protocol violations, and whether the step limit was reached. The summarizer separates model profiles and calculates savings only from matching scenario IDs present in both paths. Record the same representative scenario under standard and fast-path routes, then summarize:

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
- duplicate tool calls and protocol violations;
- step-limit exhaustion and unnecessary delegation count.

The cheapest run is not efficient if it ships defects. The most thorough run is not efficient if a deterministic one-file task consumes four large-model handoffs.

## Practical defaults

Start with a high-capability orchestrator and diagnostician, a strong developer/reviewer, a faster tester/quick-reviewer/evidence-reader, a balanced quick-fix model, and an economical delivery model. Use the deterministic bootstrap baseline with small models; assign a stronger model to `bootstrap-enricher` only when semantic project rules justify the extra cost. Keep temperature/reasoning settings conservative for state and delivery roles. Benchmark your own ticket mix before optimizing further.

Do not use model choice to weaken permissions or deterministic checks. A more capable model is not a security boundary, and a cheaper model should not be asked to compensate for missing project context.
