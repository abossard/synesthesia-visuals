---
description: Enforce main-actor dispatch for store sends and UI-bound state updates. Use when callbacks originate on background queues (timers, OSC, MIDI, async streams) and actions must be safely routed into the store.
---

# MainActor Send Guard

## Overview
Guarantee `store.send(...)` and UI state updates occur on `@MainActor`.

## Workflow
1. Find callback entry points from non-main contexts.
2. Wrap action sends in `Task { @MainActor in ... }` or main-actor helper sinks.
3. Keep queue ownership consistent for transport clients/adapters.
4. Verify no direct store mutation from background callbacks.

## Checks
- Timer callbacks
- Network subscriptions
- OSC/MIDI event handlers
- Detached task callbacks

## Verification
1. Build and run targeted tests.
2. Reproduce previous race/assertion path if available.
3. Confirm absence of queue-assertion crashes.
