# Launchpad Configuration Specification

This document defines the complete Launchpad Mini Mk3 configuration for SwiftVJ.

## Physical Layout

```text
         ┌─────────────────────────────────────────────────────────────┐
         │  [Top0] [Top1] [Top2] [Top3] [Top4] [Top5] [Top6] [Top7]    │  ← TOP ROW: BANKS (fixed, CC 91-98)
         ├─────────────────────────────────────────────────────────────┤
         │  [0,7] [1,7] [2,7] [3,7] [4,7] [5,7] [6,7] [7,7]  │ Scene 7 │
         │  [0,6] [1,6] [2,6] [3,6] [4,6] [5,6] [6,6] [7,6]  │ Scene 6 │
8x8 Grid │  [0,5] [1,5] [2,5] [3,5] [4,5] [5,5] [6,5] [7,5]  │ Scene 5 │
         │  [0,4] [1,4] [2,4] [3,4] [4,4] [5,4] [6,4] [7,4]  │ Scene 4 │
         │  [0,3] [1,3] [2,3] [3,3] [4,3] [5,3] [6,3] [7,3]  │ Scene 3 │
         │  [0,2] [1,2] [2,2] [3,2] [4,2] [5,2] [6,2] [7,2]  │ Scene 2 │
         │  [0,1] [1,1] [2,1] [3,1] [4,1] [5,1] [6,1] [7,1]  │ Scene 1 │
         │  [0,0] [1,0] [2,0] [3,0] [4,0] [5,0] [6,0] [7,0]  │ Scene 0 │  ← RECORD (fixed)
         └─────────────────────────────────────────────────────────────┘
```

**MIDI Notes (Programmer Mode):**
- Top row: CC 91-98 (not note messages)
- 8x8 Grid: Note = (row+1)*10 + (col+1), e.g., [0,0]=11, [7,7]=88
- Scene buttons: Note = (row+1)*10 + 9, e.g., Scene0=19, Scene7=89

---

## Fixed Elements (Cannot Be Changed Per-Bank)

### Top Row: Bank Selection (CC 91-98)

| Button | CC  | Bank | Color (Idle) | Color (Active) | Description |
|--------|-----|------|--------------|----------------|-------------|
| Top 0  | 91  | 0    | ?            | ?              | _TBD_       |
| Top 1  | 92  | 1    | ?            | ?              | _TBD_       |
| Top 2  | 93  | 2    | ?            | ?              | _TBD_       |
| Top 3  | 94  | 3    | ?            | ?              | _TBD_       |
| Top 4  | 95  | 4    | ?            | ?              | _TBD_       |
| Top 5  | 96  | 5    | ?            | ?              | _TBD_       |
| Top 6  | 97  | 6    | ?            | ?              | _TBD_       |
| Top 7  | 98  | 7    | ?            | ?              | _TBD_       |

### Record Button: Scene 0 (Note 19)

| Button   | Note | Function | Color (Idle) | Color (Recording) | OSC Address |
|----------|------|----------|--------------|-------------------|-------------|
| Scene 0  | 19   | Record   | Red (5)      | Red pulsing       | `/learn/...`|

### Shift Button: Scene 1 (Note 29)

| Button   | Note | Function | Color (Idle) | Color (Held) | Behavior |
|----------|------|----------|--------------|--------------|----------|
| Scene 1  | 29   | Shift    | Grey (1)     | White (3)    | Hold + press programmed pad = reset that pad |

---

## Bank Definitions

Each bank controls a different aspect of the VJ system. The full 8x8 grid (y=0..7, x=0..7) is available for bank-specific mappings.

### Bank 0: Playlist

**Purpose:** Playlist selection and playback management

**Grid Layout:**

| Row | Pad 0 | Pad 1 | Pad 2 | Pad 3 | Pad 4 | Pad 5 | Pad 6 | Pad 7 |
|-----|-------|-------|-------|-------|-------|-------|-------|-------|
| 7   | Playlist 1 | Playlist 2 | Playlist 3 | Playlist 4 | Playlist 5 | Playlist 6 | Playlist 7 | Playlist 8 |
| 6   | ▶/⏹ Play | _(empty)_ | ⏮ Prev | _(empty)_ | ⏭ Next | _(empty)_ | _(empty)_ | 🔄 Auto |
| 5   | _TBD_ | | | | | | | |
| 4   | _TBD_ | | | | | | | |
| 3   | _TBD_ | | | | | | | |
| 2   | _TBD_ | | | | | | | |
| 1   | _TBD_ | | | | | | | |
| 0   | _TBD_ | | | | | | | |

**Row 7: Playlist Selection (selector group)**

| Pad | Mode | OSC Address | Args | Color (Idle) | Color (Active) |
|-----|------|-------------|------|--------------|----------------|
| 0,7 | selector | `/playlist/select` | `{playlistName}` | Blue dim | Blue |
| 1,7 | selector | `/playlist/select` | `{playlistName}` | Blue dim | Blue |
| 2,7 | selector | `/playlist/select` | `{playlistName}` | Blue dim | Blue |
| 3,7 | selector | `/playlist/select` | `{playlistName}` | Blue dim | Blue |
| 4,7 | selector | `/playlist/select` | `{playlistName}` | Blue dim | Blue |
| 5,7 | selector | `/playlist/select` | `{playlistName}` | Blue dim | Blue |
| 6,7 | selector | `/playlist/select` | `{playlistName}` | Blue dim | Blue |
| 7,7 | selector | `/playlist/select` | `{playlistName}` | Blue dim | Blue |

> **Config:** User must provide playlist names array in config. Names map to pad positions 0-7.

**Row 6: Playback Controls**

| Pad | Mode | Function | OSC Address | Args | Color (Off) | Color (On) |
|-----|------|----------|-------------|------|-------------|------------|
| 0,6 | toggle | Play/Stop | `/playlist/play` | `{0\|1}` | Green dim | Green |
| 1,6 | - | _(empty)_ | - | - | Off | - |
| 2,6 | oneShot | Previous | `/playlist/previous` | - | Yellow | Yellow flash |
| 3,6 | - | _(empty)_ | - | - | Off | - |
| 4,6 | oneShot | Next | `/playlist/next` | - | Yellow | Yellow flash |
| 5,6 | - | _(empty)_ | - | - | Off | - |
| 6,6 | toggle | Shuffle | `/playlist/shuffle` | `{0\|1}` | Purple dim | Purple |
| 7,6 | toggle | Auto-advance | `/playlist/auto` | `{0\|1}` | Orange dim | Orange |

**Scene Buttons (2-7):**

| Scene | Function | Color | OSC Address |
|-------|----------|-------|-------------|
| 7     | _TBD_    |       |             |
| 6     | _TBD_    |       |             |
| 5     | _TBD_    |       |             |
| 4     | _TBD_    |       |             |
| 3     | _TBD_    |       |             |
| 2     | _TBD_    |       |             |
| 1     | Shift    | Grey  | (fixed)     |
| 0     | Record   | Red   | (fixed)     |

---

### Bank 1: _[Name]_

**Purpose:** _Describe what this bank controls_

**Grid Layout (y=0..6):**

| Row | Description |
|-----|-------------|
| 6   | _TBD_       |
| 5   | _TBD_       |
| 4   | _TBD_       |
| 3   | _TBD_       |
| 2   | _TBD_       |
| 1   | _TBD_       |
| 0   | _TBD_       |

**Scene Buttons (1-7):**

| Scene | Function | Color | OSC Address |
|-------|----------|-------|-------------|
| 7     | _(bank)_ | -     | -           |
| 6     | _TBD_    |       |             |
| 5     | _TBD_    |       |             |
| 4     | _TBD_    |       |             |
| 3     | _TBD_    |       |             |
| 2     | _TBD_    |       |             |
| 1     | _TBD_    |       |             |
| 0     | Record   | Red   | (fixed)     |

---

### Bank 2: _[Name]_

**Purpose:** _Describe what this bank controls_

**Grid Layout (y=0..6):**

| Row | Description |
|-----|-------------|
| 6   | _TBD_       |
| 5   | _TBD_       |
| 4   | _TBD_       |
| 3   | _TBD_       |
| 2   | _TBD_       |
| 1   | _TBD_       |
| 0   | _TBD_       |

**Scene Buttons (1-7):**

| Scene | Function | Color | OSC Address |
|-------|----------|-------|-------------|
| 7     | _(bank)_ | -     | -           |
| 6     | _TBD_    |       |             |
| 5     | _TBD_    |       |             |
| 4     | _TBD_    |       |             |
| 3     | _TBD_    |       |             |
| 2     | _TBD_    |       |             |
| 1     | _TBD_    |       |             |
| 0     | Record   | Red   | (fixed)     |

---

### Bank 3: _[Name]_

**Purpose:** _Describe what this bank controls_

**Grid Layout (y=0..6):**

| Row | Description |
|-----|-------------|
| 6   | _TBD_       |
| 5   | _TBD_       |
| 4   | _TBD_       |
| 3   | _TBD_       |
| 2   | _TBD_       |
| 1   | _TBD_       |
| 0   | _TBD_       |

**Scene Buttons (1-7):**

| Scene | Function | Color | OSC Address |
|-------|----------|-------|-------------|
| 7     | _(bank)_ | -     | -           |
| 6     | _TBD_    |       |             |
| 5     | _TBD_    |       |             |
| 4     | _TBD_    |       |             |
| 3     | _TBD_    |       |             |
| 2     | _TBD_    |       |             |
| 1     | _TBD_    |       |             |
| 0     | Record   | Red   | (fixed)     |

---

### Bank 4: _[Name]_

**Purpose:** _Describe what this bank controls_

**Grid Layout (y=0..6):**

| Row | Description |
|-----|-------------|
| 6   | _TBD_       |
| 5   | _TBD_       |
| 4   | _TBD_       |
| 3   | _TBD_       |
| 2   | _TBD_       |
| 1   | _TBD_       |
| 0   | _TBD_       |

**Scene Buttons (1-7):**

| Scene | Function | Color | OSC Address |
|-------|----------|-------|-------------|
| 7     | _(bank)_ | -     | -           |
| 6     | _TBD_    |       |             |
| 5     | _TBD_    |       |             |
| 4     | _TBD_    |       |             |
| 3     | _TBD_    |       |             |
| 2     | _TBD_    |       |             |
| 1     | _TBD_    |       |             |
| 0     | Record   | Red   | (fixed)     |

---

### Bank 5: _[Name]_

**Purpose:** _Describe what this bank controls_

**Grid Layout (y=0..6):**

| Row | Description |
|-----|-------------|
| 6   | _TBD_       |
| 5   | _TBD_       |
| 4   | _TBD_       |
| 3   | _TBD_       |
| 2   | _TBD_       |
| 1   | _TBD_       |
| 0   | _TBD_       |

**Scene Buttons (1-7):**

| Scene | Function | Color | OSC Address |
|-------|----------|-------|-------------|
| 7     | _(bank)_ | -     | -           |
| 6     | _TBD_    |       |             |
| 5     | _TBD_    |       |             |
| 4     | _TBD_    |       |             |
| 3     | _TBD_    |       |             |
| 2     | _TBD_    |       |             |
| 1     | _TBD_    |       |             |
| 0     | Record   | Red   | (fixed)     |

---

### Bank 6: _[Name]_

**Purpose:** _Describe what this bank controls_

**Grid Layout (y=0..6):**

| Row | Description |
|-----|-------------|
| 6   | _TBD_       |
| 5   | _TBD_       |
| 4   | _TBD_       |
| 3   | _TBD_       |
| 2   | _TBD_       |
| 1   | _TBD_       |
| 0   | _TBD_       |

**Scene Buttons (1-7):**

| Scene | Function | Color | OSC Address |
|-------|----------|-------|-------------|
| 7     | _(bank)_ | -     | -           |
| 6     | _TBD_    |       |             |
| 5     | _TBD_    |       |             |
| 4     | _TBD_    |       |             |
| 3     | _TBD_    |       |             |
| 2     | _TBD_    |       |             |
| 1     | _TBD_    |       |             |
| 0     | Record   | Red   | (fixed)     |

---

### Bank 7: _[Name]_

**Purpose:** _Describe what this bank controls_

**Grid Layout (y=0..6):**

| Row | Description |
|-----|-------------|
| 6   | _TBD_       |
| 5   | _TBD_       |
| 4   | _TBD_       |
| 3   | _TBD_       |
| 2   | _TBD_       |
| 1   | _TBD_       |
| 0   | _TBD_       |

**Scene Buttons (1-7):**

| Scene | Function | Color | OSC Address |
|-------|----------|-------|-------------|
| 7     | _(bank)_ | -     | -           |
| 6     | _TBD_    |       |             |
| 5     | _TBD_    |       |             |
| 4     | _TBD_    |       |             |
| 3     | _TBD_    |       |             |
| 2     | _TBD_    |       |             |
| 1     | _TBD_    |       |             |
| 0     | Record   | Red   | (fixed)     |

---

## Global Buttons (Same Across All Banks)

These buttons behave identically regardless of which bank is active.

| Location | Function | Color (Idle) | Color (Active) | OSC Address |
|----------|----------|--------------|----------------|-------------|
| Scene 0  | Record   | ?            | Red            | `/learn/...`|
| _TBD_    | _TBD_    |              |                |             |

---

## Color Palette Reference

| Name       | Value | Hex     | Use Case |
|------------|-------|---------|----------|
| Off        | 0     | -       | Inactive |
| White      | 3     | #FFFFFF | Neutral  |
| Red        | 5     | #FF0000 | Record/Stop |
| Orange     | 9     | #FF8000 | Warning  |
| Yellow     | 13    | #FFFF00 | Highlight |
| Green      | 21    | #00FF00 | Active/Go |
| Cyan       | 37    | #00FFFF | Info     |
| Blue       | 45    | #0000FF | Selected |
| Purple     | 53    | #8000FF | Special  |
| Pink       | 57    | #FF00FF | Accent   |
| Magenta    | 61    | #FF0080 | Accent   |

---

## Pad Behavior Types

| Mode      | Description                                      |
|-----------|--------------------------------------------------|
| `selector`  | Radio button - one active in group             |
| `toggle`    | On/Off switch - sends oscOn/oscOff             |
| `oneShot`   | Momentary - sends on press only                |
| `momentary` | Held - sends on press, different on release    |

---

## Config Structure Requirements

Based on this spec, the config needs:

```swift
// MARK: - Fixed Layout Definition

/// Bank 0 has fixed pads that cannot be reprogrammed
struct Bank0Layout {
    /// Playlist names for row 7 (user configurable list, not pad behavior)
    var playlistNames: [String]  // Up to 8 names
    
    /// Fixed pads in Bank 0 (hardcoded, not saved to config)
    static let fixedPads: Set<ButtonId> = [
        // Row 7: Playlist selection (0,7) to (7,7)
        ButtonId(x: 0, y: 7), ButtonId(x: 1, y: 7), ButtonId(x: 2, y: 7), ButtonId(x: 3, y: 7),
        ButtonId(x: 4, y: 7), ButtonId(x: 5, y: 7), ButtonId(x: 6, y: 7), ButtonId(x: 7, y: 7),
        // Row 6: Playback controls
        ButtonId(x: 0, y: 6),  // Play/Stop
        ButtonId(x: 2, y: 6),  // Previous
        ButtonId(x: 4, y: 6),  // Next
        ButtonId(x: 6, y: 6),  // Shuffle
        ButtonId(x: 7, y: 6),  // Auto
    ]
    
    /// Check if a pad is fixed (cannot be reprogrammed)
    static func isFixed(_ padId: ButtonId, bank: Int) -> Bool {
        if bank == 0 {
            return fixedPads.contains(padId)
        }
        return false
    }
}

/// Global fixed elements (same across all banks)
struct GlobalLayout {
    /// Scene 0 = Record button (Note 19)
    static let recordButton = ButtonId(x: 8, y: 0)  // Scene column
    
    /// Scene 1 = Shift button (Note 29)
    static let shiftButton = ButtonId(x: 8, y: 1)   // Scene column
    
    /// Top row = Bank selection (CC 91-98)
    static let bankButtons: [Int] = [91, 92, 93, 94, 95, 96, 97, 98]
}

struct LaunchpadConfig {
    // Fixed elements (not per-bank)
    let bankRow: [BankButton]           // Top row (CC 91-98)
    let recordButton: RecordButton      // Scene 0
    let shiftButton: ShiftButton        // Scene 1
    
    // Bank 0 specific config
    var bank0: Bank0Layout
    
    // Per-bank configurations (banks 1-7 are fully programmable)
    let banks: [Int: BankConfig]        // 0-7
}

struct BankConfig {
    let name: String
    let purpose: String
    let gridPads: [ButtonId: PadBehavior]    // Full 8x8 grid
    let sceneButtons: [Int: SceneButton]      // Scene 2-7 (0=Record, 1=Shift are fixed)
}
```

### Bank 0 Fixed OSC Commands

| Pad | OSC Address | Args | Notes |
|-----|-------------|------|-------|
| Row 7 (0-7) | `/playlist/select` | `{playlistName}` | Name from config array |
| 0,6 | `/playlist/play` | `{0\|1}` | Toggle |
| 2,6 | `/playlist/previous` | - | One-shot |
| 4,6 | `/playlist/next` | - | One-shot |
| 6,6 | `/playlist/shuffle` | `{0\|1}` | Toggle |
| 7,6 | `/playlist/auto` | `{0\|1}` | Toggle |

---

## Notes

- _Add implementation notes here_
- _Add OSC address conventions here_
- _Add color coding conventions here_
