---
name: production-diagnosis
description: Diagnose unknown production failures through bounded hypotheses, sanitized evidence, falsification, and a persisted root-cause decision
compatibility: opencode-v2
---

# Production diagnosis

Use this skill only for incidents whose cause is not already known. Diagnosis is separate from implementation and delivery.

## Safety preflight

- Work from repository evidence and sanitized evidence explicitly supplied by the user.
- Never request, read, persist, or expose credentials, tokens, private keys, connection strings, secret environment files, or unnecessary personal data.
- Never connect to production or execute a production, cloud, deployment, rollback, restart, scaling, data-repair, or infrastructure mutation.
- Treat mitigation options as proposals requiring a separate operational process.
- Escalate security, data-integrity, concurrency, infrastructure, or critical incidents when safe evidence is insufficient.

## Evidence packet

Record the symptom, impact, severity, affected users, affected versions, first observation time, recent releases or configuration changes, repository evidence, sanitized logs, metrics, traces, and reproduction results. Give every observation a stable `E<n>` identifier and say where it came from. Never call an inference evidence.

## Hypothesis loop

1. Produce a small set of mutually distinguishable `H<n>` hypotheses.
2. For each hypothesis, identify supporting evidence, contradicting evidence, and one safe falsification test.
3. Prefer the least expensive local or user-provided observation that distinguishes the leading hypotheses.
4. Reject contradicted hypotheses explicitly; do not silently discard them.
5. Stop with `BLOCKED` when the next safe observation is unavailable.
6. Stop with `ESCALATED` when the risk boundary or iteration limit is reached.

The persisted maximum is one to three total hypothesis iterations. Human approval is required before starting another iteration after `DIAGNOSIS_BLOCKED`.

## Confirmation rule

Return `ROOT_CAUSE_CONFIRMED` only when exactly one hypothesis explains the observed failure, credible alternatives are contradicted or made materially less likely, the conclusion cites concrete evidence, and a regression-test obligation can be stated. Code proximity, intuition, temporal correlation, or a plausible diff is not enough by itself.

Reproduction is preferred but not mandatory. A cause may be confirmed without local reproduction when independent production evidence establishes the causal chain. If `.ai/project.json` sets `diagnostics.requireReproduction` to true, lack of a successful or partial reproduction requires `BLOCKED`.

## Persisted output

Return one object matching `.ai/diagnosis.schema.json`. The deterministic validator additionally enforces unique IDs, valid evidence references, one confirmed hypothesis, supporting root-cause evidence, a regression-test obligation, and truthful safety flags.

`BLOCKED` must list the smallest missing evidence needed to continue. `ESCALATED` must state why safe diagnosis cannot proceed. `ROOT_CAUSE_CONFIRMED` may include mitigation options, but they are proposals only.

## Implementation handoff

Only a confirmed, validated, untampered diagnostic run may become implementation work. The user must explicitly run `/ticket diagnosis:<run-id>`. The new standard run records the diagnostic source run, preserves evidence and hashes, verifies scope, creates a plan, and waits for approval. Never hand a blocked or escalated diagnosis to `/quick-fix` or directly to a developer.
