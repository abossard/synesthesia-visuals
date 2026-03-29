# SwiftVJ Automation Editor Plan

This document verifies the current automation feature in `SwiftVJApp`, clarifies what QLC+ can and cannot provide for timeline capture, and proposes a no-code implementation plan for an easier automation editor.

No app code is changed by this document.

---

## Goal

Add an easy-to-use automation editor to `SwiftVJApp` that can:

- record a live performance as automation against song position
- let the operator edit that automation visually against the song timeline
- replay the automation reliably when the same song plays again
- recover the correct state even if playback starts in the middle of the song

The last requirement is the critical one. It is what separates a usable per-song automation system from a simple trigger recorder.

---

## Verified Current State

### What already exists

The current app already has a real automation subsystem:

- an Automation tab exists in the main app shell
- a timeline view exists for selecting songs, adding cues, and adding value-lane points
- the store has a dedicated `AutomationSubState`
- outgoing OSC can already be auto-recorded into per-song automation cues
- replay runs from playback position via `playbackTick`
- reducer and E2E tests already cover parts of recording and replay

Primary code references:

- [ContentView.swift](/Users/abossard/Desktop/projects/synesthesia-visuals/swift-vj/Sources/SwiftVJApp/ContentView.swift):126
- [AutomationTimelineView.swift](/Users/abossard/Desktop/projects/synesthesia-visuals/swift-vj/Sources/SwiftVJApp/AutomationTimelineView.swift):72
- [AppState.swift](/Users/abossard/Desktop/projects/synesthesia-visuals/swift-vj/Sources/SwiftVJCore/Store/AppState.swift):1274
- [Actions.swift](/Users/abossard/Desktop/projects/synesthesia-visuals/swift-vj/Sources/SwiftVJCore/Store/Actions.swift):652
- [Reducer.swift](/Users/abossard/Desktop/projects/synesthesia-visuals/swift-vj/Sources/SwiftVJCore/Store/Reducer.swift):1353
- [SwiftVJApp.swift](/Users/abossard/Desktop/projects/synesthesia-visuals/swift-vj/Sources/SwiftVJApp/SwiftVJApp.swift):910
- [AutomationReducerTests.swift](/Users/abossard/Desktop/projects/synesthesia-visuals/swift-vj/Tests/BehaviorTests/ReducerTests/AutomationReducerTests.swift):43
- [AutomationE2ETests.swift](/Users/abossard/Desktop/projects/synesthesia-visuals/swift-vj/Tests/E2ETests/AutomationE2ETests.swift):39

### What is already verified in code

The current feature already supports:

- manual cue entry by playhead time
- per-song persistence of automation timelines
- auto-record of outgoing OSC filtered by configured address prefixes
- sampling-rate and minimum-delta guards during auto-record
- replay of one-shot cues when playback crosses a cue boundary
- replay of LedFx brightness value lanes by interpolation

Evidence:

- `recordOSC` persists OSC cues only when automation is enabled, auto-record is enabled, and the address matches configured prefixes
- `playbackTick` replays cues and value lanes during playback
- tests explicitly verify prefix filtering, rate limiting, delta filtering, one-shot cue firing, and brightness interpolation

### What is missing today

The current implementation is functional but not yet an easy live editor.

Main UX limitations:

- the editor is form-based, not timeline-first
- cue editing is add/delete oriented, with no direct drag or trim workflow
- only one graph lane type exists today: `ledfxVirtualBrightness`
- recorded OSC is stored as generic cues, but not grouped into editable lanes by address/target
- there is no dedicated capture review workflow after a live take
- automation OSC targets are currently limited to `synesthesia`, `magic`, and `vdj`

Main replay limitation:

- one-shot cues are still edge-triggered between `previous` and `current` playback position
- value lanes are sampled at absolute position, but one-shot state is not reconstructed from absolute position
- this means "start playback in the middle and immediately rebuild the correct look" is not fully solved

The key evidence is here:

- [Reducer.swift](/Users/abossard/Desktop/projects/synesthesia-visuals/swift-vj/Sources/SwiftVJCore/Store/Reducer.swift):1562

`playbackTick` currently:

- remembers the previous playback position
- fires cues only when `cue.timeSec > previous && cue.timeSec <= position`
- samples value lanes at the current position

That is good for forward playback, but it is not yet a full state reconstruction engine.

### Architecture finding

Current architecture is UDF-compliant enough to extend safely:

- views dispatch store actions
- reducers own timeline state transitions
- external sends happen through `EffectEnvironment.sendOSC`
- outgoing OSC auto-recording is bridged back into the store from app wiring, not directly from the reducer

That is a good base. The next step is not a rewrite. It is a targeted expansion of the automation domain.

---

## QLC+ Capability Verification

### Can QLC+ receive OSC and use it to trigger scenes or effects?

Yes.

QLC+ OSC input can be attached to an OSC input profile and then mapped to Virtual Console widgets. Those widgets can in turn trigger Buttons, Sliders, Blackout, Cue Lists, and the functions attached to them.

Practically, that means OSC can drive:

- scenes
- chasers
- collections
- EFX through owning widgets
- slider/submaster values

### Can QLC+ output scene changes directly?

Not as semantic scene-change events by default.

QLC+ native OSC output is a DMX-style control bus. The official OSC docs describe output paths like:

- `/3/dmx/11`

and float values for the channel state.

So QLC+ native OSC output is good for:

- control-bus channels
- learned parameters in Magic
- external values that behave like faders, toggles, or bus levels

It is not a built-in "announce scene name whenever a VC button is pressed" feature.

### Can QLC+ output non-DMX related changes?

Yes, but not only through native OSC output.

Verified options:

1. Native OSC output
   - emits DMX-style bus values
   - useful when the external app learns fixed OSC addresses
2. Script functions
   - can `startfunction`, `stopfunction`, `blackout:on|off`
   - can execute `systemcommand:` with absolute paths and arguments
   - useful for HTTP, helper CLIs, and custom OSC senders
3. Loopback plugin
   - can control QLC+ widgets from scenes and other functions internally
   - useful inside QLC+, but not a direct external semantic event bridge

### Practical implication for this feature

If you want SwiftVJApp to record meaningful QLC+ scene changes, you should not rely on raw native OSC output alone.

Better options:

1. Make each important QLC+ button or collection also emit a stable helper OSC message.
2. Or make each important QLC+ button also call a helper script via `systemcommand:` that sends a semantic OSC event.
3. Or drive QLC+ from SwiftVJApp instead of trying to infer QLC+ state afterward.

The third option is architecturally cleaner if SwiftVJApp is meant to be the timeline brain.

Current app-side implication:

- if SwiftVJApp should drive QLC+ directly, `qlc` must be added as a first-class automation target
- if SwiftVJApp should only record QLC+ performance intent, helper OSC or script-triggered semantic events are enough

---

## Product Direction

The automation editor should become a timeline tool, not just a cue form.

### Desired operator workflow

1. Start the song in VirtualDJ.
2. Arm recording in SwiftVJApp.
3. Perform live:
   - Launchpad / QLC+ scene triggers
   - Magic macro changes
   - LedFx scene or brightness changes
4. Stop recording.
5. Review captured events in a timeline aligned to song position.
6. Clean up:
   - delete noise
   - rename lanes
   - quantize or trim selected events
   - convert repetitive stepped OSC to smoother value lanes where useful
7. Save the automation to the song.
8. Later, when the song plays again, SwiftVJApp reconstructs the current state from the current song position.

### Core UX principle

The editor should present two automation kinds differently:

1. Stateful automation
   - "what should be true at this position"
   - examples: active look, Magic mode, brightness, blackout state
2. Momentary automation
   - "fire once when crossing this point"
   - examples: white hit, strobe hit, flash

Without this distinction, mid-song recovery stays unreliable.

---

## Proposed Architecture Plan

This plan keeps the existing UDF/store/effect boundaries intact.

### View Layer

Build a proper editor shell around the existing automation feature.

Planned UI pieces:

- transport header
  - current song
  - current playhead
  - recording arm
  - follow-playhead toggle
- capture review panel
  - recently recorded addresses
  - source filter
  - noise suppression actions
- timeline canvas
  - horizontal time ruler
  - vertical lanes
  - draggable cues
  - draggable value points
  - selection and multi-select
- inspector panel
  - target
  - OSC address
  - args
  - cue kind: stateful or momentary
  - source tag
- lane manager
  - group by target + address
  - convert repeated OSC values into value lanes
  - hide muted lanes

Important constraint:

- views stay action-only
- drag/edit gestures update local transient UI state as needed
- commits go through `AppAction.automation(...)`

### Store Layer

Extend the automation domain rather than bypassing it.

Proposed model changes:

1. Add cue semantics
   - `state`
   - `momentary`
2. Generalize value lanes beyond LedFx brightness
   - target type should support arbitrary OSC value lanes, not only brightness
3. Add grouping metadata
   - lane key by target + OSC address + argument index
4. Add editor substate
   - selected cue ids
   - selected lane ids
   - zoom scale
   - visible time range
   - capture filters
5. Add capture session metadata
   - recording started at
   - source labels
   - recorded message count

Critical replay change:

- replay must compute state from absolute song position, not only from edge crossing

That means:

- for each stateful lane or cue family, compute the latest value or command at `<= currentPosition`
- emit only if the desired state differs from the last emitted state
- keep momentary cues edge-triggered

This is the part that makes mid-song start safe.

### Effect Boundary Layer

All output remains behind effect environment abstractions.

Needed boundary extensions:

1. Add a QLC+ output target only if SwiftVJApp should drive QLC+ directly.
2. Otherwise keep QLC+ external and record only semantic helper OSC emitted by QLC+.
3. If we add QLC+ as a target:
   - extend `AutomationOSCTarget`
   - extend `EffectEnvironment.sendOSC`
   - extend `OSCHub` send routing

No reducer should:

- talk to QLC+ directly
- talk to Magic directly
- call shell scripts
- call HTTP

### App Wiring Layer

App wiring already has the right pattern for OSC auto-record:

- `oscHub.outgoingMessageHandler`
- bridged back to store on `@MainActor`

Keep that pattern.

Planned wiring additions:

- capture semantic helper OSC from QLC+ if present
- optionally add a QLC+ target send route
- tag recorded events by source such as:
  - `qlc-scene`
  - `magic-macro`
  - `ledfx-auto`
  - `manual`

### Test Layer

Required coverage before implementation is considered complete:

1. Reducer tests
   - stateful cue replay from absolute position
   - start playback in the middle
   - seek backward then forward
   - lane grouping and conversion
2. Store or app wiring tests
   - QLC helper OSC recording
   - no self-recording loops
   - target routing for QLC if added
3. UI tests
   - recording arm and capture review
   - drag cue to new time
   - edit cue inspector fields
4. Stress tests
   - rapid position updates
   - dense automation timelines
   - repeated seek bursts

---

## Recommended Implementation Phases

### Phase 1: Replay semantics first

Before improving UI, fix the underlying meaning of automation.

Deliverables:

- stateful vs momentary cue model
- absolute-position state reconstruction
- tests for mid-song start and seek behavior

Reason:

- without this, a prettier editor still produces unreliable show playback

### Phase 2: Capture model cleanup

Improve how live recording is stored.

Deliverables:

- source tagging
- lane grouping by target/address
- conversion rules from repeated OSC samples to value lanes
- better capture filtering

### Phase 3: Editor UX overhaul

Replace the form-first experience with a timeline-first editor.

Deliverables:

- zoomable timeline
- draggable cues and points
- inspector
- capture review panel
- lane visibility and grouping

### Phase 4: QLC+ semantic bridge

Only after the editor itself is solid.

Two viable paths:

1. Preferred for minimal coupling
   - QLC+ emits helper OSC or script-based semantic messages
   - SwiftVJApp records those semantic messages
2. Preferred for tighter integration
   - add `qlc` as a first-class automation OSC target
   - SwiftVJApp becomes the timeline master and drives QLC+ widgets/control bus directly

### Phase 5: Polish

Deliverables:

- snapping and quantization
- duplicate and move tools
- batch rename lanes
- mute/solo lanes
- import/export timeline JSON

---

## Recommendation

For this rig, the cleanest architecture is:

- VirtualDJ provides song identity and playback position
- SwiftVJApp owns the timecoded automation timeline
- QLC+ remains the lighting/output hub
- QLC+ scene intent is exposed either through a helper OSC layer or by letting SwiftVJApp drive QLC+ directly

Do not make the editor depend on inferred QLC+ DMX output if you want a reliable semantic timeline.

Use either:

- semantic helper OSC from QLC+, or
- direct SwiftVJApp control of QLC+

---

## Open Decisions

These should be decided before implementation starts:

1. Should SwiftVJApp become a first-class OSC sender to QLC+?
2. Should QLC+ emit helper OSC scene names, or should it only expose a control bus?
3. Which recorded signals are stateful vs momentary by default?
4. Should Magic parameters be edited as raw OSC lanes or as named macros?
5. Do we want timeline automation to drive only external apps, or also internal SwiftVJ rendering state?

---

## Sources

Official QLC+ and VirtualDJ references used for this plan:

- [QLC+ Input Profiles (v4)](https://docs.qlcplus.org/v4/input-output/input-profiles) · [v5](https://docs.qlcplus.org/v5/input-output/input-profiles)
- [QLC+ OSC plugin (v4)](https://docs.qlcplus.org/v4/plugins/osc) · [v5](https://docs.qlcplus.org/v5/plugins/osc)
- [QLC+ Button widget (v4)](https://docs.qlcplus.org/v4/virtual-console/button) · [v5](https://docs.qlcplus.org/v5/virtual-console/button)
- [QLC+ Script Editor (v4)](https://docs.qlcplus.org/v4/function-manager/script-editor) · [v5](https://docs.qlcplus.org/v5/function-manager/script-editor)
- [QLC+ Loopback plugin](https://docs.qlcplus.org/v4/plugins/loopback)
- [VirtualDJ OS2L Show Per Track](https://www.virtualdj.com/wiki/OS2L_ShowPerTrack.html)
- [VirtualDJ QLC+ with OS2L](https://www.virtualdj.com/wiki/QLC%20with%20OS2L.html)
