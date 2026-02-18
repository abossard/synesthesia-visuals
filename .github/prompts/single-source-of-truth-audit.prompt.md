---
description: Detect and remove duplicated or mirrored state ownership. Use when UI shows stale/inconsistent values, multiple subsystems store the same domain state, or modules are polled directly for presentation state.
---

# Single Source Of Truth Audit

## Overview
Keep each domain state owned by exactly one canonical store location.

## Workflow
1. List all state holders for the domain.
2. Select canonical store state as source of truth.
3. Remove mirror reads from modules/services in presentation paths.
4. Add revision or version counters for robust propagation where needed.
5. Update observers to react to canonical state only.

## Invariants
- One mutable owner per domain state.
- Derived state stays read-only and recomputable.
- View rendering uses store-backed published state.

## Regression Coverage
Add tests for:
1. Monotonic revision progression.
2. Final state consistency after rapid updates.
3. No fallback reads from non-canonical sources.
