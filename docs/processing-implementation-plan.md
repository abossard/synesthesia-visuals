# Processing VJ System Implementation Plan

Iterative plan to build the complete VJ system from [processing-syphon-idea-board.md](processing-syphon-idea-board.md).

---

## Phase 1: Core Infrastructure

### 1.1 Project Setup
- [x] Create `processing-vj/src/` directory structure
- [x] Set up main sketch file `VJSystem.pde`
- [x] Configure `size(1920, 1080, P3D)` for Full HD Syphon output
- [x] Add library imports: Syphon, The MidiBus

### 1.2 MIDI Module (`midi/`)
- [x] Create `MidiIO.pde` — thin wrapper around MidiBus
  - `void onNote(int channel, int pitch, int velocity)`
  - `void sendLED(int note, int velocity)`
- [x] Create `LaunchpadGrid.pde` — note↔cell math
  - `PVector noteToCell(int note)` → (col, row) or null
  - `int cellToNote(int col, int row)`
  - `boolean isValidPad(int note)`
  - `boolean isSceneButton(int note)`
  - LED color constants: `LP_OFF`, `LP_RED`, `LP_GREEN`, `LP_BLUE`, etc.
- [x] Implement graceful fallback when no Launchpad connected
- [x] Add `LaunchpadHUD.pde` — LED state buffer + batch send

### 1.3 State Machine Module (`fsm/`) ✅
- [x] Create `LevelFSM.pde` — table-driven FSM
  - `State current`
  - `void trigger(Event e)`
  - `boolean isExit()`, `isWin()`, `isLose()`
- [x] Define `State` enum: `IDLE, PLAYING, WIN, LOSE, PAUSED, EXIT`
- [x] Define `Event` enum: `START, PAD_HIT, PAD_MISS, GOAL_REACHED, TIME_UP, LIVES_EMPTY, PAUSE, RESUME, RESTART, ADVANCE, FORCE_EXIT`
- [x] Add `loadDefaults()` for common rules; levels add their own win/lose conditions

### 1.4 Level Interface (`levels/`) ✅
- [x] Create `Level.pde` interface:
  ```java
  interface Level {
    void init(SharedContext ctx);
    void update(float dt, Inputs inputs);
    void draw(PGraphics g);
    void handlePad(int col, int row, int velocity);
    LevelFSM getFSM();
    String getName();
    void dispose();
  }
  ```
- [x] Create `EmptyLevel.pde` — minimal implementation for testing

### 1.5 Shared Context (`core/`) ✅
- [x] Create `SharedContext.pde`:
  - `PGraphics framebuffer`
  - `SyphonServer syphon`
  - `AudioEnvelope audioEnv` (for visual reactivity, not FSM)
  - `SketchConfig config`
- [x] Create `Inputs.pde` DTO:
  - `float dt`
  - `float bassLevel`, `midLevel`, `highLevel` (visual modulation only)
  - `ArrayList<PadEvent> padEvents`
- [x] Create `AudioEnvelope.pde` — manual/auto audio levels with smoothing
- [x] Create `SketchConfig.pde` — level order, buffer sizes, timing

### 1.6 Level Manager (`core/`) ✅
- [x] Create `LevelManager.pde`:
  - `ArrayList<Level> levels`
  - `int activeIndex`
  - `Level queued`
  - `void queueNext(int id)`
  - `void update(float dt, Inputs inputs)`
  - `void draw(PGraphics g)`
- [x] Implement level swap with instant cut (transitions later)
- [x] Wire Launchpad top row (71–78) to level selection

### 1.7 Main Sketch Wiring ✅
- [x] Initialize all modules in `setup()`
- [x] Collect inputs each frame in `draw()`
- [x] Call `levelManager.update()` and `levelManager.draw()`
- [x] Send framebuffer via `syphon.sendImage()`
- [x] Route `noteOn()`/`noteOff()` to `LaunchpadGrid` → `LevelManager`
- [x] Keyboard fallbacks: 1-8=levels, arrows=next/prev, space=beat, R=reset, S=start, P=pause

---

## Phase 2: Graphics Utilities

### 2.1 Buffer Management (`graphics/`)
- [ ] Create `LazyBuffer.pde` — allocate-once PGraphics wrapper
- [ ] Create `HistoryBuffer.pde` — circular buffer of frames for trails/smear
- [ ] Create `FeedbackBuffer.pde` — ping-pong FBO pattern

### 2.2 Common Shaders
- [ ] Create `shaders/fade.glsl` — multiply by fade factor
- [ ] Create `shaders/additive.glsl` — additive blend
- [ ] Create `shaders/crossfade.glsl` — mix two textures
- [ ] Add shader loading helper in `SharedContext`

### 2.3 Color Utilities
- [ ] Create `Palette.pde` — predefined VJ palettes
- [ ] Add `lerpPalette(float t)` for smooth color ramps
- [ ] Add `cyclePalette(int index)` for tap-to-cycle control

---

## Phase 3: Audio Integration

### 3.1 Audio Envelope (`audio/`)
- [ ] Create `AudioEnvelope.pde` stub (manual control first)
- [ ] Add `bassLevel`, `midLevel`, `highLevel` (0–1 floats)
- [ ] Add `onBeat` flag for transient detection
- [ ] Wire to Launchpad pads for manual testing (row 1 = bass/mid/high sliders)

### 3.2 Audio Input (Optional)
- [ ] Integrate Minim or Sound library for real audio
- [ ] FFT → band levels
- [ ] Beat detection → `onBeat` trigger

---

## Phase 4: Transitions

### 4.1 Transition System
- [ ] Create `Transition.pde` interface:
  ```java
  interface Transition {
    void start(PGraphics from, PGraphics to);
    void update(float progress);
    void draw(PGraphics g);
    boolean isComplete();
  }
  ```
- [ ] Implement `CrossfadeTransition.pde`
- [ ] Implement `RadialWipeTransition.pde`
- [ ] Add `TransitionManager.pde` in `LevelManager`

### 4.2 Transition Triggers
- [ ] Scene button arms transition
- [ ] Auto-advance after X bars triggers transition
- [ ] Audio peak can trigger snap transition

---

## Phase 5: Empty Level Stubs (All 14)

Create minimal placeholder for each level with correct pad bindings:

### 5.1 Particle Levels
- [ ] `GravityWellsLevel.pde` — placeholder with FSM
- [ ] `JellyBlobsLevel.pde` — placeholder with FSM
- [ ] `AgentTrailsLevel.pde` — placeholder with FSM

### 5.2 Surface/Texture Levels
- [ ] `ReactionDiffusionLevel.pde` — placeholder with FSM
- [ ] `RecursiveCityLevel.pde` — placeholder with FSM
- [ ] `LiquidFloorLevel.pde` — placeholder with FSM
- [ ] `CellularAutomataLevel.pde` — placeholder with FSM

### 5.3 Shader/Effect Levels
- [ ] `PortalRaymarchLevel.pde` — placeholder with FSM
- [ ] `RopeSimLevel.pde` — placeholder with FSM
- [ ] `LogoWindTunnelLevel.pde` — placeholder with FSM

### 5.4 Composite Levels
- [ ] `SwarmCamerasLevel.pde` — placeholder with FSM
- [ ] `TimeSmearLevel.pde` — placeholder with FSM
- [ ] `MirrorRoomsLevel.pde` — placeholder with FSM
- [ ] `TextEngineLevel.pde` — placeholder with FSM

### 5.5 Register All Levels
- [ ] Add all 14 levels to `LevelManager`
- [ ] Map top row pads to first 8 levels
- [ ] Map scene buttons to level banks (1–8, 9–14)

---

## Phase 6: Implement Levels (One by One)

### 6.1 Level: Gravity Wells in a Particle Galaxy
- [ ] Create `Particle` class (pos, vel, color, life)
- [ ] Create `Well` class (pos, mass, active)
- [ ] Implement N-body attraction with softening
- [ ] Add trail rendering via `HistoryBuffer`
- [ ] Wire pads: middle rows → spawn/move wells
- [ ] Wire row 5 → gravity/drag/trail cycle
- [ ] Add audio reactivity: bass → pull, highs → sparks
- [ ] Test FSM: Idle → Sculpt → Peak → Cooldown

### 6.2 Level: Jelly Blobs and Goo Physics
- [ ] Create `SoftBody` class (mass-spring mesh)
- [ ] Implement Verlet integration
- [ ] Add volume preservation constraint
- [ ] Render with metaball shader or hull
- [ ] Wire pads: col 0–1 → spawn, col 7 → glitch
- [ ] Wire row 5 → stiffness, row 4 → damping
- [ ] Add audio reactivity: envelope → wobble
- [ ] Test FSM: Idle → Play → MergeSplit → Peak → Settle

### 6.3 Level: Crowd of Agents Drawing Light Trails
- [ ] Create `Agent` class (pos, vel, behavior mode)
- [ ] Implement steering behaviors (seek, flee, flock)
- [ ] Add trail rendering with fading buffer
- [ ] Wire pads: row 7 → behavior, row 6 → trail style
- [ ] Wire row 5 → speed/jitter/cohesion
- [ ] Add audio reactivity: bass → cohesion, highs → jitter
- [ ] Test FSM: Idle → Flock → Orbit → Peak → Scatter

### 6.4 Level: Reaction–Diffusion Skin on 3D Shapes
- [ ] Implement Gray–Scott RD on PGraphics (ping-pong)
- [ ] Create 3D mesh (sphere, torus) with UV mapping
- [ ] Apply RD texture to mesh
- [ ] Wire pads: row 5 → mesh, row 6 → lighting/palette
- [ ] Wire row 4 → feed/kill, row 3 → diffusion
- [ ] Add audio reactivity: kicks → palette shift
- [ ] Test FSM: Idle → Grow → Morph → Peak → Fade

### 6.5 Level: Recursive City / Escher Camera Ride
- [ ] Create modular city block geometry
- [ ] Implement recursive instancing with transforms
- [ ] Add camera path (spline or procedural)
- [ ] Wire pads: row 7 → layout, row 6 → mirror/fog
- [ ] Wire row 5 → speed/FOV/depth
- [ ] Add audio reactivity: kick → shake, fills → zoom
- [ ] Test FSM: Idle → Cruise → Spiral → Peak → Glide

### 6.6 Level: Non-Newtonian Liquid Floor
- [ ] Create heightfield grid
- [ ] Implement spring-mass simulation
- [ ] Add non-Newtonian stiffening on impulse
- [ ] Render with normal-mapped lighting
- [ ] Wire pads: bottom row → slams, row 6 → wireframe
- [ ] Wire row 5 → viscosity/elasticity/damping
- [ ] Add audio reactivity: bass → stiffness + impulse
- [ ] Test FSM: Idle → Ripples → Stiff → Flow

### 6.7 Level: Cellular Automata Zoo
- [ ] Implement Game of Life on GPU (shader ping-pong)
- [ ] Add rule variants: Brian's Brain, Day & Night, 1D
- [ ] Add zoom and palette controls
- [ ] Wire pads: row 7 → rules, row 6 → seed, row 5 → zoom
- [ ] Wire row 4 → birth/survival thresholds
- [ ] Add audio reactivity: impulse → seed, highs → noise
- [ ] Test FSM: Idle → Seed → Evolve → ZoomDrift → Peak

### 6.8 Level: Portal / Wormhole Raymarcher
- [ ] Create tunnel SDF shader
- [ ] Add polar UV distortion
- [ ] Implement forward motion + bend
- [ ] Wire pads: row 7 → palette, row 6 → bend
- [ ] Wire row 5 → twist/noise
- [ ] Add audio reactivity: kick → burst, snare → wobble
- [ ] Test FSM: Idle → Drift → Bend → Peak → Cool

### 6.9 Level: String Theory Rope Simulation
- [ ] Create Verlet rope with distance constraints
- [ ] Spawn multiple ropes with different anchors
- [ ] Add glow/ribbon rendering
- [ ] Wire pads: col 0–2 → spawn, col 7 → trail
- [ ] Wire row 5 → gravity, row 4 → wind
- [ ] Add audio reactivity: kick → impulse, highs → tremor
- [ ] Test FSM: Idle → Spawn → Sway → Peak → Tangle → Relax

### 6.10 Level: Logo as Physical Object in Wind Tunnel
- [ ] Load logo as alpha mask
- [ ] Create Perlin + vortex flow field
- [ ] Collide particles against logo mask
- [ ] Add trails with motion blur
- [ ] Wire pads: row 7 → logo, row 6 → porous/noise
- [ ] Wire row 5 → speed/turbulence/particles
- [ ] Add audio reactivity: bass → wind + turbulence
- [ ] Test FSM: Idle → Stream → Vortex → Peak → Wake

### 6.11 Level: Swarm of Intelligent Cameras
- [ ] Render scene to multiple small buffers
- [ ] Implement camera path modes (orbit, track, random)
- [ ] Composite into tiled layout
- [ ] Wire pads: bottom row → count, row 6 → paths
- [ ] Wire row 5 → zoom/jitter, row 4 → speed
- [ ] Add audio reactivity: shake + time offset
- [ ] Test FSM: Idle → TileSet → Pathing → Peak → Collage

### 6.12 Level: Time Smear / History Trails
- [ ] Implement circular frame buffer
- [ ] Create sampling shader with time offsets
- [ ] Add freeze/melt toggle
- [ ] Wire pads: row 7 → freeze/hue, row 6 → offsets
- [ ] Wire row 5 → length/pattern
- [ ] Add audio reactivity: hits → offset, highs → chroma
- [ ] Test FSM: Idle → Record → Smear → Peak → Melt

### 6.13 Level: Split-Reality Mirror Rooms
- [ ] Run sim with multiple parameter sets
- [ ] Render to layered FBOs
- [ ] Composite with mirror transforms
- [ ] Wire pads: row 7 → slice assign, row 6 → mirror/warp
- [ ] Wire row 5 → divergence
- [ ] Add audio reactivity: kicks → slice swap
- [ ] Test FSM: Idle → Assign → Diverge → Peak → Blend

### 6.14 Level: Recursive Text / Glyph Engines
- [ ] Convert text to point clouds (Geomerative or `textToPoints`)
- [ ] Implement cohesion toward target layout
- [ ] Add dissolve/reform animations
- [ ] Wire pads: row 7 → text preset, row 6 → dissolve
- [ ] Wire row 5 → cohesion/chaos/trail
- [ ] Add audio reactivity: bass → scatter, quiet → reform
- [ ] Test FSM: Idle → Phrase → Dissolve → Scatter → Reform

---

## Phase 7: Polish & Performance

### 7.1 Performance Optimization
- [ ] Profile each level at 1080p60
- [ ] Add resolution scaling for heavy levels
- [ ] Implement frame budget monitoring
- [ ] Add LOD for particle counts

### 7.2 LED Feedback
- [ ] Show active level (green) on top row
- [ ] Show queued level (amber)
- [ ] Show FSM state via row colors
- [ ] Pulse red during transitions

### 7.3 Auto-Rotate System
- [ ] Add tap tempo on bottom row
- [ ] Implement bars-per-level timer
- [ ] Add favorites list management
- [ ] Scene button 89 → rotate speed toggle

### 7.4 Config & Presets
- [ ] Export `SketchConfig` to JSON
- [ ] Load level order from config
- [ ] Save/load pad bindings
- [ ] Hot-reload config without restart

---

## Phase 8: Testing & Export

### 8.1 Headless Testing
- [ ] Create `HeadlessHarness.pde` with `PSurfaceNone`
- [ ] Add FSM transition tests
- [ ] Add pad binding contract tests
- [ ] Run via `processing-java` CLI

### 8.2 Integration Testing
- [ ] Test full level rotation
- [ ] Test Launchpad connection/disconnection
- [ ] Test Syphon output in Magic/Synesthesia
- [ ] Test audio reactivity end-to-end

### 8.3 Standalone Export
- [ ] Export as macOS app (Intel for Syphon)
- [ ] Bundle config files
- [ ] Create launch script
- [ ] Document keyboard fallbacks

---

## Milestone Summary

| Milestone | Deliverable |
|-----------|-------------|
| Phase 1 complete | Launchpad-controlled level switcher with empty levels |
| Phase 2 complete | Buffer/shader utilities ready |
| Phase 3 complete | Audio envelope working (manual or real) |
| Phase 4 complete | Smooth transitions between levels |
| Phase 5 complete | All 14 level stubs with FSMs |
| Phase 6 complete | All 14 levels fully implemented |
| Phase 7 complete | 60fps, LED feedback, auto-rotate |
| Phase 8 complete | Tested, exported, performance-ready |

---

## Next Steps

1. Start with **Phase 1.1–1.7** to get the skeleton running
2. Pick **one level from Phase 6** to implement alongside infrastructure
3. Iterate: add features as needed while building levels
4. Test frequently with real Launchpad + Syphon output
