---
name: stack-python
description: Apply evidence-based Python guidance using the repository's actual environment, typing, linting, framework, and test setup
compatibility: opencode-v2 python
---

## Evidence first

Read `pyproject.toml`, lockfiles, requirements files, runtime markers, package layout, type checker, linter, formatter, framework, and tests. Do not assume Poetry, uv, pip, pytest, Ruff, mypy, Django, FastAPI, or an async model unless configured.

## Guidance

- Preserve supported Python versions and packaging layout.
- Add precise type hints consistent with the configured checker; avoid blanket ignores.
- Keep sync/async boundaries explicit and never block the event loop with synchronous I/O.
- Use context managers for resources and preserve transaction lifetimes.
- Avoid mutable default arguments, broad `except Exception` handling, and import-time side effects.
- Validate external data at existing boundaries and avoid leaking secrets through logs or exceptions.
- Follow established fixtures, parametrization, async test, and mocking patterns.

Execute only quality commands configured for the module in `.ai/project.json`.
