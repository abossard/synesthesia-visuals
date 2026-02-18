---
description: Audit and enforce strict unidirectional data flow and state ownership in Swift/SwiftUI repositories. Use when refactoring architecture, fixing inconsistent UI state, removing view-to-module coupling, or reviewing event flow from UI to reducers and effects.
---

# UDF Architecture Audit

## Overview
Apply a repository-wide audit for strict flow: `Event -> Action -> Reducer -> State -> View`.

## Run This Workflow
1. Map current flow from user event to state mutation.
2. Identify direct calls from views to modules/services and replace them with action dispatch.
3. Identify state reads that bypass store-backed state and route them through a single source of truth.
4. Ensure side effects are triggered from effects, not views or reducers.
5. Add regression tests for the migrated flow.

## Enforced Rules
- Keep views action-only.
- Keep reducers pure and synchronous.
- Keep side effects in effect handlers.
- Keep state ownership centralized in the store.

## Output Contract
Return:
1. Findings list with severity and file references.
2. Concrete patch plan grouped by layer (`View`, `Store`, `Effects`, `App Wiring`, `Tests`).
3. Validation commands and their outcomes.
