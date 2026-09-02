---
name: code-review
description: Review a diff independently against its ticket, approved plan, project rules, and deterministic gate evidence
compatibility: opencode-v2
---

## Inputs

Require the ticket or request, approved plan, current diff, applicable project/module context, and latest gate report. Mark missing inputs explicitly.

## Review dimensions

Check correctness, acceptance-criteria coverage, regressions, security and authorization, input validation, error handling, concurrency, transactions and data integrity, architecture boundaries, API compatibility, performance, operability, missing or misleading tests, unnecessary complexity, and scope expansion.

Ignore pure stylistic preferences already enforced by tooling unless they create a real maintenance or correctness risk.

## Finding format

For each actionable finding report:

- Severity: BLOCKER, HIGH, MEDIUM, LOW, or NIT
- File and tight line reference
- Category
- Problem
- Evidence
- Impact
- Recommended fix

Do not calculate or merely print a verdict. Submit the complete structured review through the exclusive typed review tool assigned to the active reviewer role. That tool derives FAIL from any BLOCKER, HIGH, PARTIAL, or MISSING acceptance criterion, derives ESCALATE only from an explicit escalation reason, and otherwise derives PASS. Include acceptance-criteria coverage, gate status, and residual risks. Do not edit files or author the persisted review artifact directly.
