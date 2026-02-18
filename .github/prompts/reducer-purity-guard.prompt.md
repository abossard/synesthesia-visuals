---
description: Enforce pure reducers in state-management codebases. Use when editing reducers, adding actions, or reviewing architectural regressions to ensure reducers mutate state deterministically and never perform IO, timer, hardware, network, or filesystem work directly.
---

# Reducer Purity Guard

## Overview
Prevent hidden side effects in reducers and keep state transitions deterministic.

## Audit Steps
1. Scan reducer files for direct IO patterns.
2. Move non-pure work into effects.
3. Keep reducer output limited to `state mutation + Effect return`.
4. Verify action naming describes events, not imperative commands.

## Forbidden In Reducers
- Network calls
- File system reads/writes
- Hardware or MIDI/OSC calls
- Timers, sleeps, background queues
- Direct module/service invocation with side effects

## Migration Pattern
1. Keep state mutation in reducer.
2. Return `.run` or domain effect helper.
3. Route dependencies through environment protocols/callbacks.

## Verification
- Run focused reducer tests.
- Add at least one regression test for the migrated action path.
