# AI Agent Rules (Repository-Wide)

This file defines mandatory architecture and workflow rules for all AI coding agents working in this repository.

## Scope
- Applies to the whole repository unless a deeper `AGENTS.md` overrides a subset for its subtree.
- When in doubt, prefer these rules over ad-hoc patterns.

## Core Architecture Rules

### 1) Single Source Of Truth
- Application state must be owned by the Store (`SwiftVJCore.Store` state tree).
- Views and app-layer adapters must read derived state from Store-backed published properties.
- Do not poll module internals from views or other presentation code.

### 2) Strict Unidirectional Data Flow
- Flow must remain: `User/System Event -> AppAction -> Reducer -> State -> View`.
- Views must only dispatch actions (`appState.send(...)`), never call domain modules directly.
- Side effects must execute via Effects, not inline in views.

### 3) Reducers Stay Pure
- Reducers mutate state synchronously and deterministically.
- Reducers do not call network, file, MIDI, OSC, timers, sleeps, or hardware APIs directly.
- Any external work must be returned as `Effect`.

### 4) Effects + Environment Boundaries
- Effects must depend on protocols/closures exposed in `EffectEnvironment`.
- App layer owns concrete implementations and wiring.
- New side-effect domains require:
  - action(s),
  - reducer handling,
  - environment protocol/callback,
  - concrete app-layer implementation.

### 5) Actor Isolation Instead Of Locks
- Prefer actor boundaries for mutable side-effectful services.
- Avoid introducing new locks for app-domain flow control when actor isolation is feasible.
- Cross-thread module access must go through a single serialized boundary (actor or owned queue).

### 6) Store/Main-Actor Safety
- Store sends must occur on `@MainActor`.
- If callbacks originate off-main (MIDI/OSC/background queues), hop to main before `store.send(...)`.
- Keep queue ownership consistent for transport adapters (avoid mixed-queue send patterns).

### 7) Launchpad Domain Rules (Reference Pattern)
- `LaunchpadSubState.controllerState` is the source of truth for Launchpad UI state.
- `LaunchpadSubState.controllerRevision` must advance on each controller update to support robust change propagation.
- UI diagnostics and pad interactions dispatch Launchpad actions; they do not call `LaunchpadModule` directly.

## Simplification Rules
- Prefer one explicit data path over duplicated mirrors/snapshots.
- Remove dead/parallel code paths after migration to UDF.
- Keep module APIs focused on domain behavior; presentation-only behavior stays in view/view-model.

## Testing Requirements
- Every architecture/concurrency change must include tests.
- Add stress tests for rapid event sequences in interactive domains (e.g., bank switching, press/release bursts).
- Validate invariants, not just happy paths:
  - final state consistency,
  - bank isolation,
  - monotonic revision/update behavior.

## Implementation Checklist (For Any New Feature)
1. Add/extend action(s).
2. Update reducer state transitions (pure only).
3. Implement side effects via `Effect` + `EffectEnvironment`.
4. Keep views action-only.
5. Add focused tests + at least one stress/regression test for the changed flow.

## Anti-Patterns (Do Not Introduce)
- View -> Module direct calls for business logic.
- Reducer -> direct IO/hardware/network calls.
- Multiple mutable state owners for the same domain.
- Lock-based patching of flow bugs that should be solved by ownership/isolation boundaries.

## Preferred Skills For Compliance
- Use `udf-architecture-audit` for architecture reviews and refactors that touch event/state flow.
- Use `reducer-purity-guard` when changing reducers or action handling.
- Use `effect-boundary-enforcer` when adding or migrating side effects.
- Use `actor-isolation-check` when touching concurrency, locks, or queue ownership.
- Use `mainactor-send-guard` when wiring callbacks that dispatch store actions.
- Use `single-source-of-truth-audit` when state appears duplicated or stale.
- Use `launchpad-flow-regression-check` for Launchpad UI/store/module changes.
- Use `stress-test-generator` when adding coverage for high-rate event paths.
