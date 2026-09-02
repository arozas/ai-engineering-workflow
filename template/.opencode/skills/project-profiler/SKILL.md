---
name: project-profiler
description: Build a bounded, deterministic evidence profile of an existing repository before project-specific configuration is proposed
compatibility: opencode-v2
---

## Purpose

Personalize the installed workflow from repository evidence without making the installer model-dependent or treating naming conventions as proof.

## Deterministic profile

Run `workflow_profile_project` with `persist: false` during proposal. The typed tool inventories Git-visible application files while excluding workflow-owned paths, records manifest hashes, language counts, candidate module roots, architecture directory markers, tests, CI, and convention files, then returns a schema-valid structure fingerprint.

If OpenCode reports the typed tool as unavailable, unknown, removed, renamed, or not callable, do not start manual exploration. Use the controlled read-only fallback exactly once: `pwsh -NoProfile -File .ai/scripts/profile-project.ps1`. Report `PROFILE FALLBACK USED` and reuse only that profile as the inventory source. If the fallback cannot run or does not return a schema-shaped profile, stop with `BOOTSTRAP BLOCKED: PROFILE TOOL UNAVAILABLE`.

The profile is evidence, not a conclusion. A directory named `domain` supports an architectural hypothesis but does not prove Clean Architecture or DDD. Read only the bounded representative files permitted by `repo-bootstrap` to confirm or reject each hypothesis.

## Inference contract

For every proposed module, framework, architecture, convention, boundary, or command provide:

- confidence: `HIGH`, `MEDIUM`, or `LOW`
- exact evidence paths
- the observed fact
- the inference drawn from that fact
- any conflicting or missing evidence

Select existing stack and architecture skills whenever they fit. Do not generate a project skill that merely repeats a built-in skill. Prefer no architecture skill or `architecture-simple-layered` over falsely applying Clean Architecture, hexagonal architecture, event-driven architecture, or vertical slices.

## Persistence

Before final approval, write the profile only to `.ai/bootstrap-proposal/project-profile.json` as part of the durable draft proposal. Do not write `.ai/project-profile.json` during `/ai-bootstrap`. `/ai-bootstrap-apply` reruns the profiler and persists `.ai/project-profile.json` only when the fresh fingerprint equals the approved proposal; otherwise it stops and reports structural drift.

Use `/ai-refresh` later to compare a fresh fingerprint with the persisted profile. Source-only edits that do not change paths, manifests, CI, or convention files intentionally do not force re-profiling.
