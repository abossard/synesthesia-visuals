---
description: Replace lock-centric concurrency with actor or single-owner queue boundaries. Use when debugging race conditions, queue assertion crashes, or inconsistent state caused by cross-thread mutations.
---

# Actor Isolation Check

## Overview
Apply ownership boundaries so mutable state has one concurrency owner.

## Workflow
1. Inventory shared mutable state and lock usage.
2. Choose one owner boundary per mutable domain (actor preferred).
3. Route all cross-boundary access through async API.
4. Remove lock-based flow patches where ownership is sufficient.
5. Add stress tests for concurrent event bursts.

## Preferred Patterns
- Actor-wrapped gateway for module calls.
- Single queue ownership only when actor migration is not feasible.
- Main-actor hopping before UI/store mutations.

## Anti-Patterns
- New lock layers around architectural coupling.
- Mixed ownership (actor plus ad-hoc direct mutations).
- Cross-thread mutable access without a boundary API.
