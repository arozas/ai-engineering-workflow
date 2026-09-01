---
name: explain-changes
description: Explain an implementation for human code review using the ticket, plan, diff, tests, and gate evidence
compatibility: opencode-v2
---

Explain from behavior to code:

1. What changed and why.
2. How each acceptance criterion is satisfied.
3. Main execution or data flow.
4. Important design choices and rejected alternatives.
5. Files grouped by responsibility, with a recommended review order.
6. Tests added or changed and what they prove.
7. Exact quality and review evidence.
8. Deviations from plan, known limitations, risks, and follow-up work outside scope.

Distinguish facts demonstrated by code or commands from inferences. Keep the explanation useful for a senior reviewer; do not restate the diff mechanically.
