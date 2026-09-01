---
name: stack-react
description: Apply repository-aligned React guidance for state, effects, accessibility, rendering, and component tests
compatibility: opencode-v2 react
---

Load this together with `stack-node` when the affected module uses React. Confirm React version, router, state/data libraries, styling, component library, testing tools, and rendering model from repository evidence.

- Keep components focused and place state at the narrowest existing ownership boundary.
- Derive values during render when possible; use effects only for synchronization with external systems.
- Make effect dependencies correct; do not silence hook lint rules to hide stale closures.
- Preserve controlled/uncontrolled behavior and stable keys.
- Handle loading, empty, error, success, and permission states where relevant.
- Maintain keyboard access, semantics, focus behavior, labels, and visible feedback.
- Avoid speculative memoization and new global state.
- Test user-visible behavior rather than implementation details, following existing tools and patterns.
- Preserve server/client component or SSR/hydration boundaries when present.

Project conventions and the selected architecture skill override generic preferences.
