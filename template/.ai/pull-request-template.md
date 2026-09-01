# Pull Request

<!--
Complete every section. Use "Not applicable" with a short reason instead of
deleting sections. Report only evidence that was actually observed. Do not
claim that tests, checks, reviews, deployments, or migrations succeeded unless
their results are available.
-->

## Summary

<!--
Describe the outcome in plain language. Focus on what changes for users,
operators, maintainers, or downstream systems.
-->

## Related work

- Work item or ticket:
- Specification:
- Approved implementation plan:
- Related pull requests:

<!--
Do not add issue-closing keywords such as "Fixes" or "Closes" unless automatic
closure was explicitly approved.
-->

## Problem and current behavior

<!--
Explain the problem, why it matters, and the evidence for the previous
behavior. Include relevant constraints or failure modes.
-->

## Solution

<!--
Explain the implemented approach and why it fits the repository's existing
architecture and conventions.
-->

## Scope

### Included

-

### Explicitly not included

-

## Change classification

- [ ] Feature
- [ ] Bug fix
- [ ] Refactor with no intended behavior change
- [ ] Performance improvement
- [ ] Tests
- [ ] Documentation
- [ ] Build or dependency change
- [ ] CI/CD change
- [ ] Configuration change
- [ ] Database or migration change
- [ ] Infrastructure or deployment change
- [ ] Breaking change

## Acceptance criteria

| Criterion | Implementation evidence | Verification evidence | Status |
| --- | --- | --- | --- |
|  |  |  | PASS / FAIL / NOT RUN |

## Module and file impact

| Module or component | Key files | Reason for change | Public behavior affected? |
| --- | --- | --- | --- |
|  |  |  | Yes / No |

## Technical details

### Design and data flow

<!--
Describe relevant control flow, data flow, dependency direction, state
transitions, error handling, concurrency, and important design decisions.
-->

### Alternatives considered

| Alternative | Why it was not selected |
| --- | --- |
|  |  |

### Dependencies

- Added:
- Updated:
- Removed:
- Approval or justification:

## API and compatibility

- Public API changes:
- Contract or schema changes:
- Backward compatibility:
- Client or consumer impact:
- Deprecations:

## Data and migrations

- Data model changes:
- Migration required:
- Migration order:
- Backfill required:
- Rollback or recovery considerations:

## Security and privacy

- Authentication impact:
- Authorization impact:
- Input validation:
- Sensitive data or privacy impact:
- Secret handling:
- Threats considered:

## Reliability, performance, and observability

- Failure and retry behavior:
- Idempotency or concurrency considerations:
- Performance impact:
- Logging changes:
- Metrics or tracing:
- Alerts or dashboards:

## Verification

### Deterministic quality gates

| Module | Phase | Exact command | Exit code | Status |
| --- | --- | --- | --- | --- |
|  | restore / build / lint / typecheck / test / e2e |  |  | PASS / FAIL / NOT RUN / NOT CONFIGURED |

Overall gate verdict:

### Tests added or changed

| Test level | Scenario | Location | Result |
| --- | --- | --- | --- |
| Unit / integration / component / e2e |  |  |  |

### Manual verification

1.

### Evidence not run

<!--
List checks that were not run, why they were not run, and the resulting risk.
-->

-

## Independent review

- Review verdict:
- BLOCKER findings:
- HIGH findings:
- Remaining MEDIUM, LOW, or NIT findings:
- Correction cycles completed:

## Deployment and operations

- Deployment required:
- Target environments:
- Feature flag or configuration:
- Rollout sequence:
- Rollback procedure:
- Operational runbook changes:
- Post-deployment verification:

## Risks and known limitations

| Risk or limitation | Likelihood | Impact | Mitigation or follow-up |
| --- | --- | --- | --- |
|  | Low / Medium / High | Low / Medium / High |  |

## Visual evidence

<!--
Add screenshots, recordings, logs, request/response examples, or diagrams when
they materially help reviewers. Remove sensitive information first.
-->

Not applicable.

## Reviewer guide

### Recommended review order

1.

### Areas requiring extra attention

-

### Suggested local verification

~~~text
# Add exact commands only when they are known.
~~~

## Final checklist

### Scope and correctness

- [ ] The change matches the explicitly approved plan.
- [ ] Acceptance criteria are mapped to implementation and verification evidence.
- [ ] Unrelated changes are excluded.
- [ ] The actual diff remains within the approved scope and budget.
- [ ] Public behavior and compatibility impacts are documented.

### Quality and review

- [ ] Configured quality gates have factual statuses.
- [ ] Failed, skipped, or missing checks are not represented as passing.
- [ ] New or changed behavior has appropriate tests.
- [ ] Independent review has no unresolved BLOCKER or HIGH findings.
- [ ] Residual risks and limitations are documented.

### Security and operations

- [ ] No secrets, credentials, tokens, or protected environment files are included.
- [ ] Authentication, authorization, validation, and privacy impacts were reviewed.
- [ ] Data, migration, deployment, and rollback requirements are documented.
- [ ] Logs, screenshots, and examples contain no sensitive information.

### Delivery

- [ ] The source branch is a non-protected feature branch.
- [ ] Commits follow Conventional Commits.
- [ ] Commit messages contain no AI-agent authorship or co-authorship attribution.
- [ ] The PR is created as a draft.
- [ ] Reviewers, assignees, labels, comments, merge, and auto-merge remain manual.

