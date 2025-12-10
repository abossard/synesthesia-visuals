# Launchpad Standalone - Architecture Documentation

## Table of Contents
1. [Overview](#overview)
2. [Current Architecture](#current-architecture)
3. [Component Diagram](#component-diagram)
4. [State Machine](#state-machine)
5. [Data Flow](#data-flow)
6. [File Structure](#file-structure)
7. [Future Requirements](#future-requirements)

## Overview

Launchpad Standalone is a device-driven learn mode application that allows configuring Launchpad Mini MK3 pads to control OSC-enabled applications (like Synesthesia) without requiring any computer screen interaction.

**Key Design Principles:**
- **Functional Core, Imperative Shell**: Pure functions handle state transitions, imperative shell handles I/O
- **Immutable State**: All state is immutable; transitions create new state objects
- **Effect-Based I/O**: State transitions return effects that are executed by the app shell
- **No TUI Dependency**: Everything is controlled through Launchpad LEDs and pads

## Current Architecture

### Component Diagram

```mermaid
graph TB
    subgraph "Imperative Shell"
        App[StandaloneApp<br/>app.py]
    end
    
    subgraph "Hardware I/O"
        LP[LaunchpadDevice<br/>launchpad.py]
        OSC[OscClient<br/>osc.py]
    end
    
    subgraph "Functional Core"
        FSM[State Machine<br/>fsm.py]
        Display[LED Renderer<br/>display.py]
        Model[Domain Models<br/>model.py]
    end
    
    subgraph "Support Modules"
        Config[Config Persistence<br/>config.py]
        OscCat[OSC Categorization<br/>osc_categories.py]
    end
    
    App -->|MIDI Events| LP
    App -->|OSC Events| OSC
    App -->|State Transitions| FSM
    App -->|Render LEDs| Display
    App -->|Save/Load| Config
    
    FSM -->|Uses| Model
    FSM -->|Categorizes| OscCat
    Display -->|Uses| Model
    OSC -->|Enriches Events| OscCat
    
    LP -.->|Callbacks| App
    OSC -.->|Callbacks| App
    
    style App fill:#e1f5ff
    style FSM fill:#fff4e1
    style Display fill:#fff4e1
    style Model fill:#fff4e1
```

### Effect System

```mermaid
graph LR
    subgraph "State Transition"
        OldState[Old State] -->|Event| FSM[FSM Function]
        FSM -->|Returns| NewState[New State]
        FSM -->|Returns| Effects[Effect List]
    end
    
    subgraph "Effect Types"
        Effects --> LED[LedEffect]
        Effects --> OSCT[SendOscEffect]
        Effects --> Save[SaveConfigEffect]
        Effects --> Log[LogEffect]
    end
    
    subgraph "Execution"
        LED -->|Execute| Launchpad[Set LED Color]
        OSCT -->|Execute| OscSend[Send OSC Message]
        Save -->|Execute| SaveYAML[Write YAML File]
        Log -->|Execute| Logger[Console Log]
    end
    
    style FSM fill:#fff4e1
    style NewState fill:#e1ffe1
    style Effects fill:#ffe1e1
```

## State Machine

### Learn Mode State Machine

```mermaid
stateDiagram-v2
    [*] --> IDLE: App Start
    
    IDLE --> WAIT_PAD: Press Learn Button
    WAIT_PAD --> IDLE: Press Learn Button (cancel)
    WAIT_PAD --> RECORD_OSC: Select Grid Pad
    
    RECORD_OSC --> CONFIG: High Priority Event Received
    RECORD_OSC --> CONFIG: Timeout (5s)
    RECORD_OSC --> IDLE: No Events Recorded
    
    CONFIG --> IDLE: Press Save
    CONFIG --> IDLE: Press Cancel
    CONFIG --> IDLE: Press Learn Button
    
    note right of IDLE
        Normal operation
        - Configured pads active
        - Learn button = green
    end note
    
    note right of WAIT_PAD
        - All pads blink red
        - Waiting for selection
        - Learn button = orange
    end note
    
    note right of RECORD_OSC
        - Selected pad blinks orange
        - Recording OSC events
        - Scene buttons show count
    end note
    
    note right of CONFIG
        - Register selection (top row)
        - Content area (varies)
        - Action buttons (bottom)
    end note
```

### Config Phase Sub-States

```mermaid
stateDiagram-v2
    [*] --> OSC_SELECT: Enter Config
    
    OSC_SELECT --> MODE_SELECT: Press Mode Register
    OSC_SELECT --> COLOR_SELECT: Press Color Register
    
    MODE_SELECT --> OSC_SELECT: Press OSC Register
    MODE_SELECT --> COLOR_SELECT: Press Color Register
    
    COLOR_SELECT --> OSC_SELECT: Press OSC Register
    COLOR_SELECT --> MODE_SELECT: Press Mode Register
    
    OSC_SELECT --> [*]: Save/Cancel/Learn
    MODE_SELECT --> [*]: Save/Cancel/Learn
    COLOR_SELECT --> [*]: Save/Cancel/Learn
    
    note right of OSC_SELECT
        Row 3: Command options
        Top row: Pagination
        Auto-detects mode
    end note
    
    note right of MODE_SELECT
        Row 3: 4 mode buttons
        - Toggle
        - Push
        - One-shot
        - Selector
    end note
    
    note right of COLOR_SELECT
        Left 4x4: Idle colors
        Right 4x4: Active colors
        Row 6: Preview
    end note
```

## Data Flow

### Pad Press Flow

```mermaid
sequenceDiagram
    participant User
    participant Launchpad
    participant App
    participant FSM
    participant Display
    participant OSC
    
    User->>Launchpad: Press Pad
    Launchpad->>App: Callback(pad_id, velocity)
    App->>FSM: handle_pad_press(state, pad_id)
    
    alt Normal Mode & Configured Pad
        FSM->>FSM: Get pad config
        FSM->>FSM: Determine OSC command
        FSM-->>App: (new_state, [SendOscEffect])
        App->>OSC: send(command)
    else Learn Mode - Select Pad
        FSM-->>App: (new_state, [LogEffect])
    else Config Mode - Action Button
        FSM->>FSM: Execute config action
        FSM-->>App: (new_state, effects)
        App->>App: Execute effects
    end
    
    App->>Display: render_state(new_state)
    Display-->>App: [LedEffect list]
    App->>Launchpad: set_led() for each effect
    Launchpad->>User: Visual feedback
```

### OSC Recording Flow

```mermaid
sequenceDiagram
    participant User
    participant Synesthesia
    participant OSC
    participant App
    participant FSM
    participant OscCat
    
    User->>Synesthesia: Trigger control (e.g., select scene)
    Synesthesia->>OSC: Send OSC message
    OSC->>OscCat: enrich_event(address, args)
    OscCat-->>OSC: OscEvent(with priority)
    OSC->>App: Callback(event)
    
    alt Phase = RECORD_OSC
        App->>FSM: record_osc_event(state, event)
        FSM->>OscCat: is_controllable(address)?
        
        alt Controllable
            FSM->>FSM: Add to recorded_events
            FSM->>OscCat: should_stop_recording(event)?
            
            alt High Priority (Scene/Preset/Control)
                FSM->>FSM: finish_recording()
                FSM->>FSM: Sort by priority
                FSM->>FSM: Dedupe addresses
                FSM->>OscCat: categorize_osc() for mode
                FSM-->>App: (CONFIG state, effects)
            else Low Priority
                FSM-->>App: (RECORD_OSC state, effects)
                Note over App: Wait for timeout
            end
        else Not Controllable (e.g., /audio/)
            FSM-->>App: (unchanged state, [])
        end
    else Other Phase
        App->>App: Ignore event
    end
```

### Config Save Flow

```mermaid
sequenceDiagram
    participant User
    participant Launchpad
    participant App
    participant FSM
    participant Config
    participant FileSystem
    
    User->>Launchpad: Press Green Save Pad
    Launchpad->>App: Callback(SAVE_PAD)
    App->>FSM: handle_pad_press(state, SAVE_PAD)
    FSM->>FSM: Create PadConfig
    FSM->>FSM: Update ControllerConfig
    FSM-->>App: (IDLE state, [SaveConfigEffect, LogEffect])
    
    App->>App: Execute SaveConfigEffect
    App->>Config: save_config(controller_config)
    Config->>Config: Convert to YAML data
    Config->>FileSystem: Write ~/.config/launchpad_standalone/config.yaml
    
    App->>App: Execute LogEffect
    App->>App: Log "Saved config..."
    
    App->>App: Render IDLE state
    App->>Launchpad: Update all LEDs
```

## File Structure

```
launchpad_standalone/
├── __init__.py           # Package metadata
├── __main__.py           # Entry point (calls app.main)
├── README.md             # User documentation
├── ARCHITECTURE.md       # This file
│
├── model.py              # Domain models (immutable)
│   ├── PadId             # Pad coordinate (x, y)
│   ├── PadMode           # SELECTOR, TOGGLE, ONE_SHOT, PUSH
│   ├── LearnPhase        # IDLE, WAIT_PAD, RECORD_OSC, CONFIG
│   ├── LearnRegister     # OSC_SELECT, MODE_SELECT, COLOR_SELECT
│   ├── OscCommand        # (address, args)
│   ├── OscEvent          # (timestamp, address, args, priority)
│   ├── LearnState        # Learn mode state
│   ├── PadConfig         # Saved pad configuration
│   ├── ControllerConfig  # Complete saved config
│   ├── PadRuntimeState   # Runtime state per pad
│   ├── AppState          # Complete application state
│   └── Effects           # LedEffect, SendOscEffect, SaveConfigEffect, LogEffect
│
├── app.py                # Main application (imperative shell)
│   └── StandaloneApp     # Orchestrates I/O and effects
│       ├── start()       # Connect devices, load config
│       ├── stop()        # Cleanup
│       ├── _on_pad_press()
│       ├── _on_pad_release()
│       ├── _on_osc_event()
│       ├── _render_leds()
│       └── _execute_effects()
│
├── fsm.py                # State machine (pure functions)
│   ├── enter_learn_mode()
│   ├── exit_learn_mode()
│   ├── select_pad()
│   ├── record_osc_event()
│   ├── finish_recording()
│   ├── handle_config_pad_press()
│   ├── save_config()
│   ├── test_config()
│   ├── handle_pad_press()      # Main dispatcher
│   ├── handle_pad_release()
│   └── toggle_blink()
│
├── display.py            # LED rendering (pure functions)
│   ├── render_idle()           # Normal operation
│   ├── render_learn_wait_pad() # Blinking red pads
│   ├── render_learn_record_osc() # Selected pad blinks
│   ├── render_learn_config()   # Config UI
│   └── render_state()          # Main dispatcher
│
├── launchpad.py          # Launchpad MIDI driver
│   └── LaunchpadDevice
│       ├── connect()          # Auto-detect & connect
│       ├── set_callbacks()
│       ├── start_listening()  # Async MIDI input
│       ├── set_led()
│       └── stop()
│
├── osc.py                # OSC client (bidirectional)
│   └── OscClient
│       ├── connect()          # Start server & client
│       ├── add_callback()
│       ├── send()
│       └── stop()
│
├── osc_categories.py     # OSC address categorization
│   ├── categorize_osc()       # (priority, mode, group)
│   ├── is_controllable()
│   ├── should_stop_recording()
│   └── enrich_event()         # Add priority to event
│
└── config.py             # YAML persistence
    ├── save_config()
    └── load_config()
```

## Future Requirements

### 1. Bank Switching with Top Row Pads

**Requirement:** Use the top row (y=7) pads for switching between different banks of pad configurations, allowing more than 64 pad mappings.

#### Design

```mermaid
stateDiagram-v2
    [*] --> Bank0: Default
    
    Bank0 --> Bank1: Press Top Row Pad 0
    Bank0 --> Bank2: Press Top Row Pad 1
    Bank0 --> Bank3: Press Top Row Pad 2
    
    Bank1 --> Bank0: Press Top Row Pad 0
    Bank1 --> Bank2: Press Top Row Pad 1
    
    Bank2 --> Bank0: Press Top Row Pad 0
    Bank2 --> Bank1: Press Top Row Pad 1
    
    note right of Bank0
        Shows pads for bank 0
        Top row pad 0 = bright
        Other bank pads = dim
    end note
```

**Implementation Plan:**

1. **Model Changes:**
   - Add `current_bank: int` to `AppState`
   - Change `ControllerConfig.pads` to `Dict[int, Dict[str, PadConfig]]` (bank → pad map)
   - Add bank indicator to top row in IDLE phase

2. **Display Changes:**
   - `render_idle()`: Show active bank indicator (top row pads 0-7)
   - Active bank = bright color, inactive banks = dim color
   - Only show pads from current bank

3. **FSM Changes:**
   - In `handle_normal_press()`: Check if pad is in top row (y=7)
   - If top row: Switch bank instead of sending OSC
   - Update state with new bank number
   - Re-render to show new bank's pads

4. **Config Changes:**
   - Save/load bank structure in YAML
   - Each pad config includes bank number

**Constraints:**
- Top row (y=7) in IDLE mode is reserved for bank switching
- Config mode still uses top row for register selection (no conflict)
- Maximum 8 banks (0-7)

---

### 2. Enhanced Pad Edit Mode

**Requirement:** When pressing record/learn on an already assigned pad, enter a special edit mode that:
- Shows the current OSC message as a blue pad (first yellow register position)
- Keeps it selected by default
- Allows editing the mode (second yellow register)
- Allows editing colors (third yellow register)
- Has a blue preview button in the bottom row that blinks between blue and chosen color
- Accept/reject with green/red buttons

#### Current vs. Enhanced Flow

```mermaid
graph TB
    subgraph "Current Behavior"
        C1[Press Learn] --> C2[Wait for Pad]
        C2 --> C3[Select Pad]
        C3 --> C4[Record OSC]
        C4 --> C5[Config Phase]
    end
    
    subgraph "Enhanced Behavior - Editing Existing Pad"
        E1[Press Learn] --> E2[Wait for Pad]
        E2 --> E3[Select CONFIGURED Pad]
        E3 --> E4[Skip Recording]
        E4 --> E5[Config with Current OSC]
        E5 -.->|Blue pad in OSC register| E6[Current OSC Selected]
        E5 -.->|Can change| E7[Mode/Color Registers]
    end
    
    style E3 fill:#ffe1e1
    style E6 fill:#e1f5ff
```

#### Edit Mode State Machine

```mermaid
stateDiagram-v2
    IDLE --> WAIT_PAD: Press Learn
    WAIT_PAD --> RECORD_OSC: Select Unconfigured Pad
    WAIT_PAD --> CONFIG_EDIT: Select Configured Pad
    
    RECORD_OSC --> CONFIG_NEW: Finish Recording
    
    CONFIG_NEW --> IDLE: Save/Cancel
    CONFIG_EDIT --> IDLE: Save/Cancel
    
    note right of CONFIG_EDIT
        Edit mode:
        - Load existing PadConfig
        - Show current OSC as blue
        - Blink test button
        - Can change mode/colors
    end note
    
    note right of CONFIG_NEW
        New mode:
        - Record OSC first
        - Show all recorded as cyan
        - Same edit capabilities
    end note
```

**Implementation Plan:**

1. **Model Changes:**
   - Add `is_edit_mode: bool` to `LearnState`
   - Add `original_config: Optional[PadConfig]` to `LearnState`

2. **FSM Changes (`fsm.py`):**
   ```python
   def select_pad(state: AppState, pad_id: PadId):
       # Check if pad already configured
       existing_config = state.config.get_pad(pad_id) if state.config else None
       
       if existing_config:
           # Edit mode - skip recording
           new_learn = replace(
               state.learn,
               phase=LearnPhase.CONFIG,
               selected_pad=pad_id,
               is_edit_mode=True,
               original_config=existing_config,
               candidate_commands=[existing_config.osc_command],
               selected_osc_index=0,
               selected_mode=existing_config.mode,
               selected_idle_color=existing_config.idle_color,
               selected_active_color=existing_config.active_color,
               active_register=LearnRegister.MODE_SELECT  # Start at mode
           )
           return replace(state, learn=new_learn), [LogEffect("Edit mode")]
       else:
           # Normal flow - record OSC
           return record_mode_flow(state, pad_id)
   ```

3. **Display Changes (`display.py`):**
   ```python
   def _render_osc_select(learn: LearnState) -> List[LedEffect]:
       effects = []
       
       if learn.is_edit_mode:
           # Show single blue pad at position 0 with current OSC
           effects.append(LedEffect(pad_id=PadId(0, 3), color=LP_BLUE))
           # Indicate edit mode with different register color
           # (implementation detail)
       else:
           # Normal mode - show all recorded as cyan
           # ... existing logic ...
       
       return effects
   ```

4. **Test Button Blinking:**
   - Add test button to blink state tracking
   - Blink between `LP_BLUE` and `selected_active_color`
   - Update in `_blink_loop()` when in CONFIG phase

---

### 3. Test Button Blinking Enhancement

**Requirement:** Make the blue preview button (TEST_PAD) blink between blue and the chosen active color.

**Implementation Plan:**

1. **Model Changes:**
   - No changes needed; use existing `blink_on` in `AppState`

2. **Display Changes:**
   ```python
   def render_learn_config(state: AppState) -> List[LedEffect]:
       # ... existing code ...
       
       # Test button blinks between blue and selected active color
       if state.blink_on:
           test_color = state.learn.selected_active_color
       else:
           test_color = LP_BLUE
       
       effects.append(LedEffect(pad_id=TEST_PAD, color=test_color))
       
       # ... rest of code ...
   ```

3. **App Changes (`app.py`):**
   ```python
   async def _blink_loop(self):
       while self._running:
           await asyncio.sleep(0.2)
           
           phase = self.state.learn.phase
           # Add CONFIG to blinking phases
           if phase in (LearnPhase.WAIT_PAD, LearnPhase.RECORD_OSC, LearnPhase.CONFIG):
               self.state = toggle_blink(self.state)
               self._render_leds()
   ```

---

### 4. Learn Mode Cancellation

**Requirement:** Pressing the learn button when already in learn mode will cancel the learn mode.

**Current Behavior:** Learn button exits learn mode only from IDLE.

**Enhanced Behavior:**
```mermaid
stateDiagram-v2
    IDLE --> WAIT_PAD: Press Learn
    WAIT_PAD --> IDLE: Press Learn (cancel)
    RECORD_OSC --> IDLE: Press Learn (cancel)
    CONFIG --> IDLE: Press Learn (cancel)
    
    note right of IDLE
        Learn button = toggle
        - Not in learn: Enter
        - In learn: Exit/Cancel
    end note
```

**Implementation:**

Already implemented in `fsm.py`:
```python
def handle_pad_press(state: AppState, pad_id: PadId):
    if pad_id == LEARN_BUTTON:
        if phase == LearnPhase.IDLE:
            return enter_learn_mode(state)
        else:
            return exit_learn_mode(state)  # ✓ Already handles all phases
```

**Status:** ✅ Already implemented!

---

### 5. Bank Switching During Learn Mode

**Requirement:** After pressing learn, the user can still switch the bank to another one.

**Use Case:** User wants to configure a pad in Bank 2, so they:
1. Press learn (enter WAIT_PAD)
2. Press top row pad 2 (switch to Bank 2)
3. Select a pad in Bank 2
4. Configure it

**Implementation Plan:**

1. **FSM Changes:**
   ```python
   def handle_pad_press(state: AppState, pad_id: PadId):
       phase = state.learn.phase
       
       # Learn button handling (unchanged)
       if pad_id == LEARN_BUTTON:
           # ...
       
       # Bank switching (NEW - works in all phases)
       if pad_id.y == 7 and 0 <= pad_id.x <= 7 and phase == LearnPhase.WAIT_PAD:
           # In WAIT_PAD, top row switches banks
           new_state = replace(state, current_bank=pad_id.x)
           return new_state, [LogEffect(f"Switched to bank {pad_id.x}")]
       
       # Phase-specific handling
       if phase == LearnPhase.IDLE:
           return handle_normal_press(state, pad_id)
       # ...
   ```

2. **Display Changes:**
   ```python
   def render_learn_wait_pad(state: AppState) -> List[LedEffect]:
       effects = []
       blink_color = LP_RED if state.blink_on else LP_RED_DIM
       
       # Grid pads blink
       for y in range(8):
           for x in range(8):
               effects.append(LedEffect(pad_id=PadId(x, y), color=blink_color))
       
       # Top row shows bank selection (NEW)
       for x in range(8):
           color = LP_GREEN if x == state.current_bank else LP_GREEN_DIM
           effects.append(LedEffect(pad_id=PadId(x, 7), color=color))
       
       # Learn button & cancel (unchanged)
       effects.append(LedEffect(pad_id=LEARN_BUTTON, color=LP_ORANGE))
       effects.append(LedEffect(pad_id=PadId(8, 7), color=LP_RED))
       
       return effects
   ```

---

## Implementation Summary

### Phase 1: Core Enhancements (High Priority)
1. ✅ **Learn mode cancellation** - Already works
2. **Test button blinking** - Simple display change
3. **Enhanced pad edit mode** - Moderate complexity

### Phase 2: Bank System (Medium Priority)
4. **Bank switching** - Model + FSM + Display changes
5. **Bank switching in learn mode** - Extends #4

### Estimated Complexity
| Feature | Model | FSM | Display | App | Config | Total |
|---------|-------|-----|---------|-----|--------|-------|
| Test blink | - | - | ⭐ | ⭐ | - | ⭐ |
| Edit mode | ⭐ | ⭐⭐ | ⭐⭐ | - | - | ⭐⭐⭐ |
| Bank switching | ⭐⭐ | ⭐⭐ | ⭐⭐ | - | ⭐⭐ | ⭐⭐⭐⭐ |
| Bank in learn | - | ⭐ | ⭐ | - | - | ⭐ |

Legend: ⭐ = Low effort, ⭐⭐ = Medium, ⭐⭐⭐ = High

---

## Testing Strategy

### Manual Testing Checklist

**Current Features:**
- [ ] Enter learn mode (bottom-right scene button)
- [ ] Select pad (grid pad blinks orange)
- [ ] Record OSC (trigger Synesthesia control)
  - [ ] Scene selection (stops immediately)
  - [ ] Preset selection (stops immediately)
  - [ ] Control toggle (stops immediately)
  - [ ] Timeout after 5 seconds
- [ ] Config phase navigation
  - [ ] OSC register (select command)
  - [ ] Mode register (4 modes)
  - [ ] Color register (idle + active)
- [ ] Test button (sends OSC)
- [ ] Save button (green, persists config)
- [ ] Cancel button (red, exits without saving)
- [ ] Normal operation (configured pads work)

**Future Features:**
- [ ] Bank switching (top row in IDLE)
- [ ] Bank switching in learn mode (top row in WAIT_PAD)
- [ ] Edit mode (select configured pad)
- [ ] Test button blinking (blue ↔ active color)
- [ ] Learn button cancellation (all phases)

### Unit Testing Approach

The functional core (FSM, Display) is highly testable:

```python
def test_enter_learn_mode():
    state = AppState()
    new_state, effects = enter_learn_mode(state)
    
    assert new_state.learn.phase == LearnPhase.WAIT_PAD
    assert len(effects) == 1
    assert isinstance(effects[0], LogEffect)

def test_bank_switching():
    state = AppState(current_bank=0)
    new_state, effects = handle_pad_press(state, PadId(2, 7))
    
    assert new_state.current_bank == 2
    assert "bank 2" in effects[0].message.lower()
```

---

## Glossary

**App State:** Complete application state including learn mode state, config, runtime state

**Bank:** A set of 64 pad configurations (one bank = full 8x8 grid)

**Blink:** LED animation that alternates between two colors every 200ms

**Effect:** Side effect returned by FSM (LED, OSC, Save, Log)

**FSM:** Finite State Machine - pure functions handling state transitions

**Imperative Shell:** The outer layer (app.py) that handles I/O and effects

**Learn Mode:** Configuration mode where user can map pads to OSC commands

**LearnPhase:** Current step in learn mode (IDLE, WAIT_PAD, RECORD_OSC, CONFIG)

**LearnRegister:** Section of config phase (OSC_SELECT, MODE_SELECT, COLOR_SELECT)

**OSC:** Open Sound Control - network protocol for multimedia communication

**Pad Config:** Saved configuration for a single pad (mode, OSC, colors)

**PadMode:** How a pad behaves (TOGGLE, PUSH, ONE_SHOT, SELECTOR)

**Priority:** OSC event priority (1=scene, 2=preset, 3=control, 99=noise)

**Programmer Mode:** Launchpad MIDI mode enabling full pad control

**Pure Function:** Function with no side effects, same input = same output

**Register:** Configuration section in learn mode config phase

**Scene Button:** Right column buttons (x=8, y=0-7)

**Selector Mode:** Radio button behavior - only one active in group

