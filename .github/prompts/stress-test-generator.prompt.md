---
description: Generate deterministic stress and regression tests for stateful interactive flows. Use when event bursts, concurrency, or rapid mode/bank switching can cause inconsistent state, race conditions, or hidden architectural regressions.
---

# Stress Test Generator

## Overview
Create high-signal stress tests that validate invariants under rapid event sequences.

## Workflow
1. Identify the critical state invariants.
2. Build deterministic high-volume event loops.
3. Assert final-state correctness and isolation rules.
4. Cover both reducer-level and FSM/domain-level behavior when applicable.

## Test Design Rules
- Keep randomness out unless seeded and reproducible.
- Use enough iterations to expose ordering bugs.
- Assert invariant-focused outcomes, not only no-crash behavior.
- Keep runtime short for CI.

## Recommended Assertions
- Final active mode/bank correctness.
- Per-group/per-bank isolation.
- Monotonic revision/version counters.
- Idempotence where repeated events should stabilize.

## Delivery
Include:
1. New test file path(s).
2. Why each invariant matters.
3. Commands used to run targeted tests.
