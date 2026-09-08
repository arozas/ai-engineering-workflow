---
description: Check PowerShell and OpenCode runtime selection without modifying the project
agent: orchestrator
---

Run exactly `pwsh -NoProfile -File .ai/scripts/check-workflow-runtime.ps1` once and summarize only its JSON result. Do not search for tools, change PATH, install or upgrade software, restart services, or edit files. Report the selected `opencode2` path and version, every duplicate installation, warnings, and the next step.
