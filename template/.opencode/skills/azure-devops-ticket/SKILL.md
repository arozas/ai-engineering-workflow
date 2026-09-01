---
name: azure-devops-ticket
description: Retrieve an Azure DevOps work item, comments, and relations read-only and normalize them for technical analysis
compatibility: opencode-v2 azure-cli azure-devops-extension
---

## Preconditions

Read `integrations.workItems` from `.ai/project.json`. Require provider `azure-devops`, an organization URL, and project name. Never request, print, store, or modify credentials. Use the user's existing Azure CLI authentication and read-only operations only.

## Retrieve

For work item `<id>`, retrieve the full item and relations as JSON:

```text
az boards work-item show --id <id> --expand all --org <organization> --output json
```

Retrieve discussion through the Work Item Tracking comments resource using `az devops invoke` with area `wit`, resource `workItemComments`, route parameters for project and work item ID, organization, GET, JSON output, and API version `7.1-preview.4`. Follow continuation tokens until complete. If the CLI resource is unavailable, report the exact failure and the documented read-only REST endpoint; do not fall back to a write-capable operation.

Do not add comments, update fields, change assignments, create branches, or mutate the work item.

## Normalize

Return:

- ID, type, title, state, tags, area, iteration, and assigned identity
- description and acceptance criteria with HTML normalized to readable text
- comments in chronological order with author and timestamp
- parent, children, related items, hyperlinks, and related pull requests when present
- conflicting or superseded requirements
- retrieval gaps and permission errors

Preserve identifiers and source links so every interpretation remains traceable.
