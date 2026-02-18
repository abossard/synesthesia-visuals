---
description: Validate Launchpad-specific flow invariants in this repository. Use when changing Launchpad UI, store actions, reducer logic, bank switching, OSC handling, or BPM/learn-mode paths to prevent state drift and bank display regressions.
---

# Launchpad Flow Regression Check

## Overview
Guard Launchpad architecture against regressions in bank/state synchronization.

## Repository Invariants
- Launchpad UI dispatches actions only.
- `LaunchpadSubState.controllerState` is canonical UI state.
- `controllerRevision` advances per controller update.
- Store receives events on main actor.

## Change Checklist
1. Confirm Launchpad views avoid direct `LaunchpadModule` calls.
2. Confirm action coverage for button press/release, learn mode, diagnostics, OSC, BPM.
3. Confirm reducer updates canonical state and bank values consistently.
4. Confirm effect handler routes through environment boundary.

## Test Checklist
1. Run `swift test --package-path swift-vj --filter Launchpad`.
2. Add/maintain stress tests for rapid bank switching and press/release bursts.
3. Assert final active bank and per-bank isolation invariants.
