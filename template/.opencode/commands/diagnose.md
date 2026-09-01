---
description: Diagnose an unknown production failure through bounded, read-only evidence analysis
agent: orchestrator
---

Diagnose this production incident without changing code or production: $ARGUMENTS

Load `project-context`, `workflow-state`, and `production-diagnosis`, then load only the context skills for modules plausibly related to the symptom. Normalize the user-supplied incident report into `.ai/runtime/requirement.md`. Redact secrets and personal data before persistence; if safe sanitization is uncertain, ask the user for a sanitized excerpt instead of reading or storing the source.

Create one persisted run with path `diagnostic` and task type `ProductionBug`. Record the run ID. Gather bounded evidence from the repository and from sanitized logs, metrics, traces, deployment facts, affected versions, timestamps, and reproduction results supplied by the user. Never connect to production. Run only explicitly configured `diagnostics.commands` against the local repository, and only after the normal shell approval. Those commands may inspect or reproduce locally; they must not mutate production, cloud resources, deployed data, secrets, or delivery state.

Construct an exact evidence packet and delegate it to the read-only `diagnostician`. Write its returned JSON object to `.ai/runtime/diagnosis.json`, validate it with `.ai/scripts/validate-diagnosis.ps1`, then call `RecordDiagnosis` with `PASS` for `ROOT_CAUSE_CONFIRMED`, `FAIL` for `BLOCKED`, or `ESCALATE` for `ESCALATED`.

For `DIAGNOSIS_BLOCKED`, report the missing evidence and stop. Continue only after the user supplies or approves new evidence; call `BeginDiagnosticIteration` before the next bounded analysis. Never exceed `diagnostics.maxHypothesisIterations` or three total iterations. If the limit is reached, escalate.

For `ROOT_CAUSE_CONFIRMED`, report the causal chain, evidence IDs, confidence, regression-test obligation, and proposal-only mitigations. Do not implement. End by reporting that `/ticket diagnosis:<run-id>` is ready. Urgency never authorizes `/quick-fix`, a speculative implementation, production mutation, secret access, rollback, restart, deployment, or cloud action.
