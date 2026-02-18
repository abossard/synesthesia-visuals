---
description: Enforce effect-environment boundaries for side effects. Use when introducing new side-effect domains or refactoring existing modules so reducers stay pure and concrete implementations are isolated to app-layer wiring.
---

# Effect Boundary Enforcer

## Overview
Force all external work behind effect environment abstractions.

## Required Sequence For New Side-Effect Domains
1. Add or extend domain actions.
2. Handle action in reducer without direct IO.
3. Add protocol/closure surface in effect environment.
4. Implement concrete adapter in app layer.
5. Wire environment dependency during app setup.
6. Add tests for action-to-effect behavior.

## Enforcement Checks
- No reducer reaches into app modules directly.
- No view executes side effects directly.
- Effects call environment abstractions only.
- App layer owns concrete type construction and lifecycle.

## Output Contract
Provide:
1. Missing boundary points.
2. Exact files to patch.
3. Minimal migration diff strategy.
