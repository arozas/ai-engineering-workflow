---
name: ticket-analysis
description: Turn a work item or natural-language request into testable acceptance criteria, scope, evidence, risks, and open questions
compatibility: opencode-v2
---

## Workflow

1. Preserve the original ticket wording and source.
2. Separate stated requirements from inferred implications.
3. Normalize acceptance criteria into observable outcomes without changing intent.
4. Identify actors, permissions, inputs, outputs, data changes, failures, compatibility needs, and non-functional constraints.
5. Explore repository evidence that connects each criterion to current behavior.
6. Mark contradictions, missing decisions, and assumptions that could materially change implementation.
7. Define explicit in-scope and out-of-scope boundaries.

## Output

- Objective
- Source and ticket identity
- Interpreted acceptance criteria, each linked to original evidence
- Current behavior and repository evidence
- Scope and non-goals
- Risks and dependencies
- Questions requiring human decision
- Candidate test scenarios

Do not design or implement beyond what the evidence supports.
