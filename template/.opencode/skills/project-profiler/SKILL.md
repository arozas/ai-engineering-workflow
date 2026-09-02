---
name: project-profiler
description: Build a bounded, deterministic evidence profile of an existing repository before project-specific configuration is proposed
compatibility: opencode-v2
---

## Purpose

Personalize the installed workflow from repository evidence without making the installer model-dependent or treating naming conventions as proof.

## Deterministic profile

Run `workflow_profile_project` with `persist: false` during proposal. The typed tool inventories Git-visible application files while excluding workflow-owned paths, records manifest hashes, language counts, candidate module roots, architecture directory markers, tests, CI, and convention files, then returns a schema-valid structure fingerprint.

The profile is evidence, not a conclusion. A directory named `domain` supports an architectural hypothesis but does not prove Clean Architecture or DDD. Read only the bounded representative files permitted by `repo-bootstrap` to confirm or reject each hypothesis.

## Inference contract

For every proposed module, framework, architecture, convention, boundary, or command provide:

- confidence: `HIGH`, `MEDIUM`, or `LOW`
- exact evidence paths
- the observed fact
- the inference drawn from that fact
- any conflicting or missing evidence

Select existing stack and architecture skills whenever they fit. Do not generate a project skill that merely repeats a built-in skill.

## Persistence

Before approval, do not pass `OutputPath` and do not write profile or skill files. After the user explicitly approves the complete proposal, rerun the profiler with `-OutputPath .ai/project-profile.json`. The persisted fingerprint must equal the approved proposal; otherwise stop and present the structural drift.

Use `/ai-refresh` later to compare a fresh fingerprint with the persisted profile. Source-only edits that do not change paths, manifests, CI, or convention files intentionally do not force re-profiling.
