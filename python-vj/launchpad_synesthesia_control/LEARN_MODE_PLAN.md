# Learn Mode Configuration Workflow - Design Plan v2

## Philosophy: Row-First Configuration

**Key Insight:** Users think in rows/areas, not individual pads!

Instead of configuring 64 pads one-by-one:
1. **Define row purpose** first (e.g., "Row 0-4 = Scenes")
2. **Bulk configure** the row with smart defaults
3. **Fine-tune** individual pads if needed

This reduces configuration from 64 steps to ~8 rows + tweaks!

---

## Revised User Journey Flow

```
NORMAL MODE
    ↓ [Press L]
SETUP_WIZARD (Welcome & choose config method)
    ↓ [Choose Quick Setup OR Advanced]
    
Quick Setup Path:
    ↓
DEFINE_LAYOUT (Define what each row does)
    ↓
BULK_CONFIGURE (Auto-configure rows with OSC learning)
    ↓
NORMAL MODE (Ready to use!)

Advanced Path:
    ↓
LEARN_WAIT_PAD (Select individual pad)
    ↓
LEARN_RECORD_OSC (Record OSC for that pad)
    ↓
CONFIGURE_PAD (Configure that specific pad)
    ↓
NORMAL MODE
```

---

---

## Detailed Step-by-Step Plan (Quick Setup - Recommended)

### Step 0: Welcome Screen
**Trigger:** User presses `L` key from NORMAL mode
**UI Display:**
```
╔═══════════════════════════════════════════════════════════╗
║                                                           ║
║              🎹 LAUNCHPAD CONFIGURATION WIZARD 🎹          ║
║                                                           ║
║  Welcome! Let's set up your Launchpad for Synesthesia.   ║
║                                                           ║
║  This wizard will guide you step-by-step to create a     ║
║  layout that works perfectly for your VJ style.          ║
║                                                           ║
║  ┌─────────────────────────────────────────────────────┐ ║
║  │                                                     │ ║
║  │  Choose your setup method:                         │ ║
║  │                                                     │ ║
║  │  ► [1] QUICK SETUP (Recommended - 5 minutes)       │ ║
║  │      • Configure rows/areas at once                │ ║
║  │      • Perfect for scene/preset layouts            │ ║
║  │      • Smart defaults & OSC learning               │ ║
║  │                                                     │ ║
║  │    [2] ADVANCED (One pad at a time)                │ ║
║  │      • Full control over each pad                  │ ║
║  │      • Best for custom/complex setups              │ ║
║  │      • Takes longer but very flexible              │ ║
║  │                                                     │ ║
║  │    [3] LOAD TEMPLATE                               │ ║
║  │      • Start from pre-made layout                  │ ║
║  │      • Edit template to fit your needs             │ ║
║  │                                                     │ ║
║  └─────────────────────────────────────────────────────┘ ║
║                                                           ║
║  Controls:                                                ║
║  • 1/2/3 - Select method                                  ║
║  • ↑/↓ - Navigate                                         ║
║  • Enter - Confirm                                        ║
║  • ESC - Cancel and return                                ║
║                                                           ║
╚═══════════════════════════════════════════════════════════╝
```

**Friendly Tips:**
- Most users should choose **Quick Setup**
- You can always reconfigure individual pads later
- Templates available: "Scenes+Presets", "DJ Effects", "Color Control"

**Actions:**
- 1 → Quick Setup (recommended path)
- 2 → Advanced mode (original one-by-one flow)
- 3 → Show template browser
- ESC → Cancel

---

### Step 1: Define Your Layout (Quick Setup)
**Trigger:** User selects Quick Setup
**UI Display:**
```
╔═══════════════════════════════════════════════════════════╗
║                   STEP 1 of 4: DEFINE LAYOUT              ║
╠═══════════════════════════════════════════════════════════╣
║                                                           ║
║  Let's organize your Launchpad by rows!                  ║
║                                                           ║
║  Think about what you want to control:                   ║
║  • Rows 0-4 (40 pads) → Scene selection?                 ║
║  • Row 5 (8 pads) → Presets for current scene?           ║
║  • Row 6-7 (16 pads) → Effect toggles? Color controls?   ║
║                                                           ║
║  ┌─ Launchpad Grid (8 columns × 8 rows) ───────────────┐ ║
║  │                                                      │ ║
║  │  [T] [T] [T] [T] [T] [T] [T] [T]  ← Top row         │ ║
║  │                                                      │ ║
║  │  [0] [0] [0] [0] [0] [0] [0] [0]  ← Row 0: UNDEFINED│ ║
║  │  [1] [1] [1] [1] [1] [1] [1] [1]  ← Row 1: UNDEFINED│ ║
║  │  [2] [2] [2] [2] [2] [2] [2] [2]  ← Row 2: UNDEFINED│ ║
║  │  [3] [3] [3] [3] [3] [3] [3] [3]  ← Row 3: UNDEFINED│ ║
║  │► [4] [4] [4] [4] [4] [4] [4] [4]  ← Row 4: UNDEFINED│ ║
║  │  [5] [5] [5] [5] [5] [5] [5] [5]  ← Row 5: UNDEFINED│ ║
║  │  [6] [6] [6] [6] [6] [6] [6] [6]  ← Row 6: UNDEFINED│ ║
║  │  [7] [7] [7] [7] [7] [7] [7] [7]  ← Row 7: UNDEFINED│ ║
║  │                                                      │ ║
║  └──────────────────────────────────────────────────────┘ ║
║                                                           ║
║  Select Row 4 type:                                       ║
║  ┌─────────────────────────────────────────────────────┐ ║
║  │ 1. SCENE SELECTOR (8 scenes, one active at a time) │ ║
║  │ 2. PRESET SELECTOR (8 presets/variations)          │ ║
║  │ 3. TOGGLE SWITCHES (8 on/off controls)             │ ║
║  │ 4. ONE-SHOT TRIGGERS (8 momentary buttons)         │ ║
║  │ 5. COLOR CONTROLS (hue/saturation selectors)       │ ║
║  │ 6. MIXED/CUSTOM (each button different - advanced) │ ║
║  │ 7. SKIP THIS ROW (leave empty for now)             │ ║
║  └─────────────────────────────────────────────────────┘ ║
║                                                           ║
║  Controls:                                                ║
║  • ↑/↓ - Select different row                             ║
║  • 1-6 - Choose row type                                  ║
║  • Enter - Confirm and move to next row                   ║
║  • ESC - Go back                                          ║
║                                                           ║
╚═══════════════════════════════════════════════════════════╝
```

**Smart Features:**
- Visual grid shows which rows are configured
- Colors indicate row type (scenes=green, presets=blue, toggles=yellow)
- Can skip rows and come back later
- Suggest common layouts: "5 rows scenes, 1 row presets, 2 rows effects"

**What Happens:**
User goes through each row (0-7) and assigns a type. This creates a "layout template" that will be filled with actual OSC commands in the next step.

**Row Types Explained:**

1. **SCENE SELECTOR** - Radio button group
   - Only one scene active at a time in this row
   - Active pad blinks with beat
   - All pads work together as a group
   
2. **PRESET SELECTOR** - Radio button group
   - Only one preset active at a time
   - Similar to scenes but for variations
   
3. **TOGGLE SWITCHES** - Independent on/off
   - Each button is independent
   - Can have multiple ON at same time
   - Press once: ON, press again: OFF
   
4. **ONE-SHOT TRIGGERS** - Momentary actions
   - Each button sends command when pressed
   - No "active" state - just fires action
   - Good for "Next", "Prev", "Random", etc.
   
5. **COLOR CONTROLS** - Hue/saturation selector
   - Radio group for color selection
   - Maps to Synesthesia meta controls
   
6. **MIXED/CUSTOM** - Each button configured separately
   - Button 1 might be a toggle
   - Button 2 might be one-shot
   - Button 3 might be a selector
   - Most flexible but requires individual configuration
   
7. **SKIP** - Leave empty for now

**Example Result:**
```
Rows 0-4: Scene Selector (40 pads total, grouped)
Row 5: Preset Selector (8 pads, grouped)
Row 6: Toggle Switches (8 pads, independent)
Row 7: Mixed/Custom (8 pads, each configured separately)
```

---

### Step 2: Learn OSC Commands for Each Row
**Trigger:** Layout defined
**UI Display (for Scene Selector row):**
```
╔═══════════════════════════════════════════════════════════╗
║            STEP 2 of 4: LEARN SCENES (Rows 0-4)           ║
╠═══════════════════════════════════════════════════════════╣
║                                                           ║
║  Great! You chose Rows 0-4 for Scene Selection.          ║
║  That's 40 pads (5 rows × 8 pads).                        ║
║                                                           ║
║  Now let's capture your scenes from Synesthesia:         ║
║                                                           ║
║  📝 INSTRUCTIONS:                                         ║
║  ┌─────────────────────────────────────────────────────┐ ║
║  │ 1. Go to Synesthesia                                │ ║
║  │ 2. Click through your scenes (as many as you want) │ ║
║  │ 3. I'll record each scene you activate             │ ║
║  │ 4. Press SPACE when done (or wait 30 seconds)      │ ║
║  └─────────────────────────────────────────────────────┘ ║
║                                                           ║
║  🎬 RECORDING SCENES...  [████████░░] 16s remaining       ║
║                                                           ║
║  Captured so far:                                         ║
║  ✓  1. Alien Cavern          (/scenes/AlienCavern)       ║
║  ✓  2. Neon City             (/scenes/NeonCity)          ║
║  ✓  3. Desert Sunset         (/scenes/DesertSunset)      ║
║  ✓  4. Deep Ocean            (/scenes/DeepOcean)         ║
║  ✓  5. Purple Rain           (/scenes/PurpleRain)        ║
║  ✓  6. Digital Glitch        (/scenes/DigitalGlitch)     ║
║  🔵 7. Waiting for more...                                ║
║                                                           ║
║  💡 TIP: You can capture up to 40 scenes for this area.  ║
║       If you have fewer, that's totally fine!            ║
║                                                           ║
║  Controls:                                                ║
║  • Keep clicking scenes in Synesthesia                    ║
║  • SPACE - Finish early (I have all my scenes)            ║
║  • ESC - Cancel and go back                               ║
║                                                           ║
╚═══════════════════════════════════════════════════════════╝
```

**Friendly Features:**
- **Auto-detection:** System captures scene names from OSC
- **Deduplication:** If you click same scene twice, only count once
- **Visual feedback:** Checkmark when each scene captured
- **Progress bar:** Shows time remaining
- **Friendly language:** "I'll record..." instead of "System will..."

**What Happens:**
- Records all `/scenes/*` OSC messages for 30 seconds (or until SPACE)
- Automatically extracts scene names from addresses
- Creates list of unique scenes
- Auto-assigns to grid starting from row 0, left to right

**Example Auto-Layout:**
```
Row 0: [Alien] [Neon] [Desert] [Deep] [Purple] [Glitch] [ ] [ ]
Row 1: [ ] [ ] [ ] [ ] [ ] [ ] [ ] [ ]  (if you had 8+ scenes)
...
```

---

### Step 2b: Arrange Scenes on Grid (Optional)
**UI Display:**
```
╔═══════════════════════════════════════════════════════════╗
║         STEP 2b: ARRANGE YOUR SCENES (OPTIONAL)           ║
╠═══════════════════════════════════════════════════════════╣
║                                                           ║
║  I've arranged your 6 scenes in order:                    ║
║                                                           ║
║  ┌─ Scene Rows (0-4) ──────────────────────────────────┐ ║
║  │                                                      │ ║
║  │  [Alien] [Neon] [Desert] [Deep] [Purple] [Glitch]  │ ║
║  │  [Empty] [Empty] ... (34 empty pads)                │ ║
║  │                                                      │ ║
║  └──────────────────────────────────────────────────────┘ ║
║                                                           ║
║  Want to rearrange?                                       ║
║  ┌─────────────────────────────────────────────────────┐ ║
║  │ ► [1] Keep this arrangement (looks good!)          │ ║
║  │   [2] Let me drag & drop to rearrange              │ ║
║  │   [3] Fill rows top-to-bottom instead              │ ║
║  └─────────────────────────────────────────────────────┘ ║
║                                                           ║
║  💡 TIP: Most people keep the automatic arrangement.     ║
║       You can always edit individual pads later!         ║
║                                                           ║
║  Controls:                                                ║
║  • 1/2/3 - Choose option                                  ║
║  • Enter - Continue with current layout                   ║
║  • ESC - Go back to re-record scenes                      ║
║                                                           ║
╚═══════════════════════════════════════════════════════════╝
```

---

### Step 3: Repeat for Other Row Types

For **Preset Selector** (Row 5):
```
╔═══════════════════════════════════════════════════════════╗
║         STEP 2 of 4: LEARN PRESETS (Row 5)                ║
╠═══════════════════════════════════════════════════════════╣
║                                                           ║
║  Now let's set up Row 5 for Preset Selection.            ║
║  These are like "variations" of your current scene.       ║
║                                                           ║
║  📝 INSTRUCTIONS:                                         ║
║  ┌─────────────────────────────────────────────────────┐ ║
║  │ 1. Select a scene in Synesthesia                    │ ║
║  │ 2. Switch between presets/variations               │ ║
║  │ 3. I'll capture up to 8 presets                     │ ║
║  │ 4. Press SPACE when done                            │ ║
║  └─────────────────────────────────────────────────────┘ ║
║                                                           ║
║  🎬 RECORDING PRESETS...  [██████░░░░] 12s remaining      ║
║                                                           ║
║  Captured:                                                ║
║  ✓  1. Preset 1              (/presets/Preset1)          ║
║  ✓  2. Preset 2              (/presets/Preset2)          ║
║  ✓  3. Calm                  (/favslots/3)               ║
║  🔵 4. Waiting...                                         ║
║                                                           ║
║  Controls:                                                ║
║  • SPACE - Finish (have all presets)                      ║
║  • ESC - Skip this row for now                            ║
║                                                           ║
╚═══════════════════════════════════════════════════════════╝
```

For **Toggle Switches** (Row 6):
```
╔═══════════════════════════════════════════════════════════╗
║         STEP 2 of 4: LEARN TOGGLES (Row 6)                ║
╠═══════════════════════════════════════════════════════════╣
║                                                           ║
║  Row 6 will be Toggle Switches (ON/OFF controls).        ║
║                                                           ║
║  📝 INSTRUCTIONS:                                         ║
║  ┌─────────────────────────────────────────────────────┐ ║
║  │ 1. Turn ON an effect in Synesthesia                 │ ║
║  │ 2. I'll capture the ON command                      │ ║
║  │ 3. Turn it OFF                                      │ ║
║  │ 4. I'll capture the OFF command                     │ ║
║  │ 5. Repeat for other effects (up to 8)              │ ║
║  └─────────────────────────────────────────────────────┘ ║
║                                                           ║
║  🎬 RECORDING TOGGLE #1...                                ║
║                                                           ║
║  ✓  ON command:  /effects/strobe 1.0                     ║
║  🔵 Waiting for OFF... (toggle it off in Synesthesia)    ║
║                                                           ║
║  💡 TIP: For each toggle:                                ║
║      • Turn it ON → I capture                            ║
║      • Turn it OFF → I capture                           ║
║      • Then we move to next toggle                       ║
║                                                           ║
║  Controls:                                                ║
║  • SPACE - This toggle is done, next one                  ║
║  • ESC - Skip rest of row                                 ║
║                                                           ║
╚═══════════════════════════════════════════════════════════╝
```

For **Mixed/Custom** (Row 7 - Each Button Different):
```
╔═══════════════════════════════════════════════════════════╗
║    STEP 2 of 4: CONFIGURE MIXED ROW (Row 7)               ║
╠═══════════════════════════════════════════════════════════╣
║                                                           ║
║  Row 7 is MIXED/CUSTOM - each button configured          ║
║  individually. Let's go button-by-button!                 ║
║                                                           ║
║  ┌─ Row 7 ─────────────────────────────────────────────┐ ║
║  │ [✓] [✓] [✓] [→] [ ] [ ] [ ] [ ]                     │ ║
║  │  1   2   3   4   5   6   7   8                      │ ║
║  └──────────────────────────────────────────────────────┘ ║
║                                                           ║
║  Configuring Button 4 (Row 7, Column 3):                  ║
║                                                           ║
║  What should this button do?                              ║
║  ┌─────────────────────────────────────────────────────┐ ║
║  │ ► 1. TOGGLE - On/Off switch                        │ ║
║  │   2. ONE-SHOT - Single action when pressed          │ ║
║  │   3. SELECTOR - Part of a custom group              │ ║
║  │   4. SKIP - Leave this button empty                 │ ║
║  └─────────────────────────────────────────────────────┘ ║
║                                                           ║
║  💡 Already configured in this row:                      ║
║     • Button 1: Toggle (Strobe ON/OFF)                   ║
║     • Button 2: One-Shot (Playlist Next)                 ║
║     • Button 3: One-Shot (Random Scene)                  ║
║                                                           ║
║  Controls:                                                ║
║  • 1/2/3/4 - Choose button type                           ║
║  • Enter - Confirm and learn OSC for this button          ║
║  • ESC - Skip rest of buttons                             ║
║                                                           ║
╚═══════════════════════════════════════════════════════════╝
```

**After selecting type for mixed button:**
```
╔═══════════════════════════════════════════════════════════╗
║    LEARN OSC FOR BUTTON 4 (Toggle)                        ║
╠═══════════════════════════════════════════════════════════╣
║                                                           ║
║  Button 4 will be a TOGGLE switch.                        ║
║                                                           ║
║  📝 INSTRUCTIONS:                                         ║
║  ┌─────────────────────────────────────────────────────┐ ║
║  │ 1. Turn ON the control in Synesthesia              │ ║
║  │ 2. I'll record the ON command                       │ ║
║  │ 3. Turn it OFF                                      │ ║
║  │ 4. I'll record the OFF command                      │ ║
║  └─────────────────────────────────────────────────────┘ ║
║                                                           ║
║  🎬 RECORDING...                                          ║
║                                                           ║
║  ✓  ON:  /effects/blur 1.0                               ║
║  ✓  OFF: /effects/blur 0.0                               ║
║                                                           ║
║  Label (optional): Blur Effect__                          ║
║                                                           ║
║  Colors:                                                  ║
║  OFF: ○ [Red]    ON: ● [Green]                           ║
║                                                           ║
║  [ENTER] Save & continue to Button 5                      ║
║  [ESC] Skip rest of row                                   ║
║                                                           ║
╚═══════════════════════════════════════════════════════════╝
```

**Key Differences for Mixed/Custom Rows:**
- Each button configured one-by-one
- Can choose different types for different buttons
- More flexible but takes longer
- Great for rows with miscellaneous controls
- Example uses:
  - Button 1: Strobe toggle
  - Button 2: Next playlist item (one-shot)
  - Button 3: Previous playlist item (one-shot)
  - Button 4: Blur toggle
  - Button 5: Flash toggle
  - Button 6: Random scene (one-shot)
  - Button 7: BPM tap (one-shot)
  - Button 8: Empty (unused)

---

### Step 4: Choose Colors & Review
**UI Display:**
```
╔═══════════════════════════════════════════════════════════╗
║              STEP 3 of 4: CHOOSE COLORS                   ║
╠═══════════════════════════════════════════════════════════╣
║                                                           ║
║  Almost done! Let's pick colors for your pads.            ║
║                                                           ║
║  SCENES (Rows 0-4):                                       ║
║  ┌─────────────────────────────────────────────────────┐ ║
║  │ Inactive: ○ [Dim White]    (when scene not active) │ ║
║  │ Active:   ● [Green]        (current scene - blinks)│ ║
║  └─────────────────────────────────────────────────────┘ ║
║                                                           ║
║  PRESETS (Row 5):                                         ║
║  ┌─────────────────────────────────────────────────────┐ ║
║  │ Inactive: ○ [Blue]         (not selected)          │ ║
║  │ Active:   ● [Cyan]         (current preset)        │ ║
║  └─────────────────────────────────────────────────────┘ ║
║                                                           ║
║  TOGGLES (Row 6):                                         ║
║  ┌─────────────────────────────────────────────────────┐ ║
║  │ OFF: ○ [Red]               (effect disabled)       │ ║
║  │ ON:  ● [Green]             (effect active)         │ ║
║  └─────────────────────────────────────────────────────┘ ║
║                                                           ║
║  💡 TIP: These are smart defaults that work great!       ║
║       Press Enter to accept, or Tab to customize.        ║
║                                                           ║
║  Controls:                                                ║
║  • Enter - Accept these colors (recommended)              ║
║  • Tab - Customize colors for each row type               ║
║  • ESC - Go back                                          ║
║                                                           ║
╚═══════════════════════════════════════════════════════════╝
```

---

### Step 5: Final Review & Save
**UI Display:**
```
╔═══════════════════════════════════════════════════════════╗
║          STEP 4 of 4: REVIEW & SAVE                       ║
╠═══════════════════════════════════════════════════════════╣
║                                                           ║
║  🎉 Your Launchpad is ready! Here's what we set up:      ║
║                                                           ║
║  ┌─ Layout Summary ───────────────────────────────────┐  ║
║  │                                                     │  ║
║  │  📁 SCENES (Rows 0-4): 6 scenes configured         │  ║
║  │     Alien Cavern, Neon City, Desert Sunset...      │  ║
║  │     Colors: ○ White → ● Green (blinks on beat)     │  ║
║  │                                                     │  ║
║  │  🎛️  PRESETS (Row 5): 3 presets configured         │  ║
║  │     Preset 1, Preset 2, Calm                       │  ║
║  │     Colors: ○ Blue → ● Cyan                        │  ║
║  │                                                     │  ║
║  │  🔘 TOGGLES (Row 6): 2 toggles configured          │  ║
║  │     Strobe, Flash                                  │  ║
║  │     Colors: ○ Red (OFF) → ● Green (ON)             │  ║
║  │                                                     │  ║
║  │  Total: 11 pads configured, 53 empty (ready for   │  ║
║  │         custom mapping later)                      │  ║
║  │                                                     │  ║
║  └─────────────────────────────────────────────────────┘  ║
║                                                           ║
║  This configuration will be saved to:                     ║
║  ~/.config/launchpad-synesthesia/config.yaml              ║
║                                                           ║
║  ┌─────────────────────────────────────────────────────┐ ║
║  │ ► [ENTER] Save & Start Using! 🚀                   │ ║
║  │   [E] Edit - Go back and change something          │ ║
║  │   [ESC] Cancel - Don't save                        │ ║
║  └─────────────────────────────────────────────────────┘ ║
║                                                           ║
║  💡 After saving, your Launchpad LEDs will light up      ║
║     to match your configuration. Try pressing pads!      ║
║                                                           ║
╚═══════════════════════════════════════════════════════════╝
```

**After Saving:**
```
╔═══════════════════════════════════════════════════════════╗
║                                                           ║
║          ✅ CONFIGURATION SAVED SUCCESSFULLY! ✅           ║
║                                                           ║
║  Your Launchpad is now ready to control Synesthesia!     ║
║                                                           ║
║  🎹 Try it out:                                           ║
║  • Press scene pads - they'll switch scenes              ║
║  • Active scene blinks with the music beat               ║
║  • Toggle switches turn effects on/off                   ║
║  • All changes sync with Synesthesia via OSC             ║
║                                                           ║
║  📝 What's next?                                          ║
║  • Press L anytime to configure more pads                ║
║  • Edit config file for advanced tweaks                  ║
║  • Check logs if something doesn't work                  ║
║                                                           ║
║           [Press any key to start performing]            ║
║                                                           ║
╚═══════════════════════════════════════════════════════════╝
```

---
**Trigger:** User presses `L` key
**State:** NORMAL → LEARN_WAIT_PAD
**UI Display:**
```
╔═══ LEARN MODE ═══════════╗
║ Status: Select a pad      ║
║ [yellow]Click any pad on   ║
║ Launchpad or TUI grid[/]  ║
║                           ║
║ Instructions:             ║
║ • Click pad (TUI or HW)   ║
║ • ESC to cancel           ║
╚═══════════════════════════╝
```
**Actions Available:**
- Click any pad in TUI grid → Step 2
- Press any pad on hardware → Step 2
- Press ESC → Cancel, return to NORMAL

---

### Step 2: Pad Selected - Wait for First OSC Message
**Trigger:** Pad clicked/pressed
**State:** LEARN_WAIT_PAD → LEARN_RECORD_OSC (timer not started yet)
**UI Display:**
```
╔═══ LEARN MODE ═══════════╗
║ Selected: Pad (2,3)       ║
║ [yellow]Waiting for OSC...[/] ║
║                           ║
║ Instructions:             ║
║ 1. Go to Synesthesia      ║
║ 2. Trigger an action:     ║
║    - Click a scene        ║
║    - Adjust a control     ║
║    - Select a preset      ║
║                           ║
║ Recording starts when     ║
║ first message received    ║
║                           ║
║ ESC to cancel             ║
╚═══════════════════════════╝
```
**Actions Available:**
- User triggers action in Synesthesia → Step 3
- Press ESC → Cancel, return to NORMAL

---

### Step 3: Recording OSC Messages (5 seconds)
**Trigger:** First controllable OSC message received
**State:** LEARN_RECORD_OSC (timer started)
**UI Display:**
```
╔═══ LEARN MODE ═══════════╗
║ Recording: Pad (2,3)      ║
║ [cyan]Time: 3.2s remaining[/]║
║                           ║
║ [green]Captured: 5 messages[/]║
║ • /scenes/AlienCavern     ║
║ • /controls/meta/hue      ║
║ • /presets/Preset1        ║
║ ...                       ║
║                           ║
║ Keep triggering actions   ║
║ or wait for timer...      ║
║                           ║
║ SPACE to finish early     ║
║ ESC to cancel             ║
╚═══════════════════════════╝
```
**What Happens:**
- System records all **controllable** OSC messages for 5 seconds
- Filters out: `/audio/*`, `/time/*`, `/audio/bpm/*`
- Shows live count of captured messages
- Auto-advances when timer expires

**Actions Available:**
- Wait 5 seconds → Auto-advance to Step 4
- Press SPACE → Finish early, advance to Step 4
- Press ESC → Cancel, return to NORMAL

---

### Step 4: Select OSC Command (If Multiple Captured)
**Trigger:** Timer expires or user presses SPACE
**State:** LEARN_RECORD_OSC → LEARN_SELECT_MSG
**UI Display:**

#### 4a. If Only ONE Command Captured:
```
╔═══ CONFIGURE PAD ════════╗
║ Pad: (2,3)                ║
║ Command: /scenes/Alien... ║
║                           ║
║ Auto-selected single cmd  ║
║ → Proceed to Step 5       ║
╚═══════════════════════════╝
```
Skip to Step 5 automatically.

#### 4b. If MULTIPLE Commands Captured:
```
╔═══ SELECT COMMAND ═══════════════════════╗
║ Choose which OSC command to bind:        ║
║                                          ║
║ ► 1. /scenes/AlienCavern                ║
║   2. /presets/Preset1                   ║
║   3. /controls/meta/hue 0.5             ║
║   4. /playlist/next                     ║
║   5. /favslots/1                        ║
║                                          ║
║ Controls:                                ║
║ • ↑/↓ arrows - Navigate list             ║
║ • 1-9 keys - Direct selection            ║
║ • Enter - Confirm selection              ║
║ • ESC - Cancel                           ║
╚══════════════════════════════════════════╝
```

**Actions Available:**
- ↑/↓ arrows → Navigate list (visual `►` marker moves)
- 1-9 keys → Direct selection (if 9 or fewer commands)
- Enter → Confirm selection, advance to Step 5
- ESC → Cancel, return to NORMAL

**Smart Defaults:**
- Pre-select first command in list
- Group similar commands (e.g., all `/scenes/*` together)
- Show truncated addresses if too long

---

### Step 5: Choose Pad Mode (Selector/Toggle/One-Shot)
**Trigger:** Command selected or single command auto-selected
**UI Display:**
```
╔═══ CONFIGURE PAD ════════════════════════╗
║ Pad: (2,3)                               ║
║ Command: /scenes/AlienCavern             ║
║━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━║
║                                          ║
║ Choose Pad Mode:                         ║
║                                          ║
║ ► [SELECTOR] Radio button in group      ║
║     - One active at a time in group      ║
║     - Blinks on beat when active         ║
║     - Best for: Scenes, Presets          ║
║                                          ║
║   [TOGGLE] On/Off switch                 ║
║     - Press once: ON, press again: OFF   ║
║     - Best for: Effects, Strobes         ║
║                                          ║
║   [ONE-SHOT] Momentary trigger           ║
║     - Sends command on press only        ║
║     - Best for: Bang triggers, Next/Prev ║
║                                          ║
║ Controls:                                ║
║ • Tab/↑/↓ - Navigate options             ║
║ • S/T/O keys - Direct selection          ║
║ • Enter - Confirm                        ║
║ • ESC - Cancel                           ║
╚══════════════════════════════════════════╝
```

**Smart Defaults Based on OSC Address:**
- `/scenes/*` → SELECTOR (group: scenes)
- `/presets/*` or `/favslots/*` → SELECTOR (group: presets)
- `/controls/meta/hue` → SELECTOR (group: colors)
- `/playlist/next|prev` → ONE_SHOT
- Unknown → SELECTOR (group: custom)

**Actions Available:**
- Tab/↑/↓ → Navigate between three options
- S key → Select SELECTOR
- T key → Select TOGGLE
- O key → Select ONE_SHOT
- Enter → Confirm selection
  - If SELECTOR → Advance to Step 6 (Group selection)
  - If TOGGLE → Advance to Step 7 (Toggle OFF command)
  - If ONE_SHOT → Skip to Step 8 (Color selection)
- ESC → Cancel, return to NORMAL

---

### Step 6: Select Group (Only for SELECTOR mode)
**Trigger:** SELECTOR mode chosen
**UI Display:**
```
╔═══ CONFIGURE PAD ════════════════════════╗
║ Pad: (2,3)                               ║
║ Command: /scenes/AlienCavern             ║
║ Mode: SELECTOR                           ║
║━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━║
║                                          ║
║ Choose Group (only one active per group):║
║                                          ║
║ ► [scenes] Scene selection               ║
║     - For switching between scenes       ║
║                                          ║
║   [presets] Preset selection             ║
║     - For sub-presets within a scene     ║
║                                          ║
║   [colors] Color/hue controls            ║
║     - For meta color adjustments         ║
║                                          ║
║   [custom] Custom group                  ║
║     - For other radio button groups      ║
║     - You'll name it in next step        ║
║                                          ║
║ Controls:                                ║
║ • Tab/↑/↓ - Navigate options             ║
║ • 1-4 keys - Direct selection            ║
║ • Enter - Confirm                        ║
║ • ESC - Cancel                           ║
╚══════════════════════════════════════════╝
```

**Smart Defaults:**
- Pre-select based on OSC address pattern
- If "custom" selected, show input field for custom group name

**Actions Available:**
- Tab/↑/↓ → Navigate between four options
- 1-4 keys → Direct selection
- Enter → Confirm selection
  - If "custom" → Show text input for group name
  - Otherwise → Advance to Step 8
- ESC → Cancel, return to NORMAL

---

### Step 7: Configure Toggle OFF Command (Only for TOGGLE mode)
**Trigger:** TOGGLE mode chosen
**UI Display:**
```
╔═══ CONFIGURE PAD ════════════════════════╗
║ Pad: (2,3)                               ║
║ ON Command: /effects/strobe 1.0          ║
║ Mode: TOGGLE                             ║
║━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━║
║                                          ║
║ Configure OFF command:                   ║
║                                          ║
║ ► [AUTO] Auto-generate OFF command       ║
║     OFF: /effects/strobe 0.0             ║
║     (Changes last arg to 0)              ║
║                                          ║
║   [SAME] Send same command when OFF      ║
║     (Some toggles use same address)      ║
║                                          ║
║   [NONE] No OFF command                  ║
║     (Fire-and-forget toggle)             ║
║                                          ║
║   [CUSTOM] Manually specify...           ║
║     (Advanced: type OSC address)         ║
║                                          ║
║ Controls:                                ║
║ • Tab/↑/↓ - Navigate options             ║
║ • Enter - Confirm                        ║
║ • ESC - Cancel                           ║
╚══════════════════════════════════════════╝
```

**Smart Defaults:**
- If last arg is float/int → AUTO (set to 0)
- Otherwise → SAME

**Actions Available:**
- Tab/↑/↓ → Navigate options
- Enter → Confirm selection, advance to Step 8
- ESC → Cancel, return to NORMAL

---

### Step 8: Select Colors (Idle and Active)
**Trigger:** Mode/group configured
**UI Display:**
```
╔═══ CONFIGURE PAD ════════════════════════╗
║ Pad: (2,3)                               ║
║ Command: /scenes/AlienCavern             ║
║ Mode: SELECTOR (group: scenes)           ║
║━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━║
║                                          ║
║ Choose LED Colors:                       ║
║                                          ║
║ IDLE Color (when not active):            ║
║ ► [Red] [Orange] [Yellow] [Green]       ║
║   [Cyan] [Blue] [Purple] [White]        ║
║                                          ║
║ ACTIVE Color (when active/on):           ║
║   [Red] [Orange] [Yellow] ► [Green]     ║
║   [Cyan] [Blue] [Purple] [White]        ║
║                                          ║
║ Preview: ○ Idle  ● Active                ║
║                                          ║
║ Controls:                                ║
║ • Tab - Switch Idle/Active               ║
║ • 1-8 keys - Direct color                ║
║ • ↑/↓/←/→ - Navigate palette             ║
║ • Enter - Confirm both colors            ║
║ • ESC - Cancel                           ║
╚══════════════════════════════════════════╝
```

**Color Palette:**
1. Red (LP color 5) - High energy, warnings
2. Orange (LP color 9) - Medium energy
3. Yellow (LP color 13) - Attention, caution
4. Green (LP color 21) - Active, success, go
5. Cyan (LP color 37) - Cool, calm
6. Blue (LP color 45) - Passive, info
7. Purple (LP color 53) - Special, creative
8. White (LP color 3) - Neutral, all-purpose

**Smart Defaults:**
- SELECTOR: Idle=dim white, Active=green (blinks)
- TOGGLE: Idle=red, Active=green
- ONE_SHOT: Idle=blue, Active=white

**Actions Available:**
- Tab → Switch between Idle and Active color selection
- 1-8 keys → Direct color selection
- Arrow keys → Navigate 2D color grid
- Enter → Confirm both colors, advance to Step 9
- ESC → Cancel, return to NORMAL

---

### Step 9: Enter Label (Optional)
**Trigger:** Colors selected
**UI Display:**
```
╔═══ CONFIGURE PAD ════════════════════════╗
║ Pad: (2,3)                               ║
║ Command: /scenes/AlienCavern             ║
║ Mode: SELECTOR (group: scenes)           ║
║ Colors: ○ White  ● Green                 ║
║━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━║
║                                          ║
║ Label (optional):                        ║
║                                          ║
║ ┌────────────────────────────────────┐  ║
║ │ Alien Cavern_                      │  ║
║ └────────────────────────────────────┘  ║
║                                          ║
║ This name helps identify the pad.        ║
║ Leave blank for auto-label.              ║
║                                          ║
║ Auto-label: "Alien Cavern"               ║
║ (from OSC address)                       ║
║                                          ║
║ Controls:                                ║
║ • Type - Enter custom label              ║
║ • Backspace - Delete                     ║
║ • Enter - Confirm & Save                 ║
║ • ESC - Cancel                           ║
╚══════════════════════════════════════════╝
```

**Smart Auto-Labels:**
- `/scenes/AlienCavern` → "Alien Cavern"
- `/presets/Preset1` → "Preset 1"
- `/controls/meta/hue` → "Hue"
- `/playlist/next` → "Next"

**Actions Available:**
- Type text → Enter custom label
- Backspace/Delete → Edit label
- Enter → Confirm and advance to Step 10
- ESC → Cancel, return to NORMAL

---

### Step 10: Confirmation & Save
**Trigger:** Label entered (or skipped)
**UI Display:**
```
╔═══ CONFIRM CONFIGURATION ════════════════╗
║                                          ║
║ Review your configuration:               ║
║                                          ║
║ Pad: (2,3)                               ║
║ Label: "Alien Cavern"                    ║
║ Mode: SELECTOR                           ║
║ Group: scenes                            ║
║ Command: /scenes/AlienCavern             ║
║ Colors: ○ White → ● Green (blinks)       ║
║                                          ║
║━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━║
║                                          ║
║ This will update your config file:       ║
║ ~/.config/launchpad-synesthesia/         ║
║        config.yaml                       ║
║                                          ║
║ [Enter] Save Configuration               ║
║ [ESC] Cancel (discard changes)           ║
║                                          ║
╚══════════════════════════════════════════╝
```

**Actions Available:**
- Enter → Save to YAML, update LED, return to NORMAL
- ESC → Cancel without saving, return to NORMAL

**What Happens on Save:**
1. Create `PadBehavior` object
2. Update `ControllerState.pads[pad_id]`
3. Emit `SaveConfigEffect` → Write to YAML atomically
4. Emit `SetLedEffect` → Update hardware LED immediately
5. Emit `LogEffect` → "Configured pad (2,3) as Alien Cavern"
6. Return to NORMAL mode
7. Show success notification in TUI

---

## Special Cases & Edge Handling

### No OSC Messages Captured
If timer expires with zero controllable messages:
```
╔═══ LEARN MODE ═══════════╗
║ [red]No OSC messages      ║
║ captured![/]              ║
║                           ║
║ Possible causes:          ║
║ • Synesthesia not sending ║
║ • Wrong OSC port          ║
║ • No actions triggered    ║
║                           ║
║ [Enter] Try again         ║
║ [ESC] Cancel              ║
╚═══════════════════════════╝
```
- Enter → Return to Step 2 (wait for OSC)
- ESC → Return to NORMAL

### OSC Connection Lost During Recording
```
╔═══ LEARN MODE ═══════════╗
║ [red]OSC disconnected[/]  ║
║                           ║
║ Saved 3 messages so far   ║
║                           ║
║ [Enter] Continue with     ║
║         captured msgs     ║
║ [ESC] Cancel              ║
╚═══════════════════════════╝
```

### Reconfigure Existing Pad
If pad already configured:
```
╔═══ PAD ALREADY CONFIGURED ═══════════════╗
║                                          ║
║ Pad (2,3) is already configured:         ║
║ Label: "Old Scene"                       ║
║ Mode: SELECTOR (group: scenes)           ║
║ Command: /scenes/OldScene                ║
║                                          ║
║ [Enter] Reconfigure (overwrite)          ║
║ [ESC] Keep existing (cancel)             ║
║                                          ║
╚══════════════════════════════════════════╝
```

---

## Keyboard Shortcuts Summary

| Key | Action | Context |
|-----|--------|---------|
| L | Enter Learn Mode | NORMAL mode |
| ESC | Cancel/Go back | Any Learn step |
| Enter | Confirm/Next step | Any Learn step |
| ↑/↓ | Navigate lists | Command/mode selection |
| ←/→ | Navigate options | Color palette |
| Tab | Cycle options/fields | Most steps |
| Space | Finish recording early | Recording step |
| 1-9 | Direct selection | Lists/options with <10 items |
| S/T/O | Select mode | Mode selection (Selector/Toggle/OneShot) |
| Backspace | Delete text | Label input |

---

## Implementation Checklist

### Phase 1: FSM Functions (Pure Logic)
- [x] `enter_learn_mode()` - NORMAL → LEARN_WAIT_PAD
- [x] `select_pad_for_learn()` - LEARN_WAIT_PAD → LEARN_RECORD_OSC
- [x] `start_osc_recording()` - Start timer on first controllable message
- [ ] `finish_recording()` - LEARN_RECORD_OSC → LEARN_SELECT_MSG
- [ ] `complete_learn_mode()` - Save config and return to NORMAL
- [ ] `cancel_learn_mode()` - Discard and return to NORMAL at any step

### Phase 2: UI Screens
- [x] `LearnModePanel` - Status display in main TUI
- [ ] `CommandSelectionScreen` - Step 4 (modal overlay)
- [ ] `ModeSelectionScreen` - Step 5 (modal overlay)
- [ ] `GroupSelectionScreen` - Step 6 (modal overlay)
- [ ] `ToggleConfigScreen` - Step 7 (modal overlay)
- [ ] `ColorSelectionScreen` - Step 8 (modal overlay)
- [ ] `LabelInputScreen` - Step 9 (modal overlay)
- [ ] `ConfirmationScreen` - Step 10 (modal overlay)

### Phase 3: Integration
- [ ] Wire up screen transitions in main TUI
- [ ] Handle keyboard events in each screen
- [ ] Pass data between screens
- [ ] Update LearnModePanel with current step
- [ ] Test with/without hardware

### Phase 4: Polish
- [ ] Smart defaults for all steps
- [ ] Visual preview of colors
- [ ] Help text/hints on each screen
- [ ] Validation and error messages
- [ ] Success notification
- [ ] Unit tests for FSM functions

---

## Alternative: Wizard-Style Single Screen

Instead of multiple modal screens, use a **single wizard screen** that morphs through steps:

```
╔═══ CONFIGURE PAD: Step 3 of 6 ═══════════╗
║                                          ║
║ [✓] Pad selected: (2,3)                  ║
║ [✓] Command: /scenes/AlienCavern         ║
║ [→] Choose Mode:                         ║
║ [ ] Choose Group                         ║
║ [ ] Choose Colors                        ║
║ [ ] Enter Label                          ║
║                                          ║
║ ► [SELECTOR] Radio button in group      ║
║   [TOGGLE] On/Off switch                 ║
║   [ONE-SHOT] Momentary trigger           ║
║                                          ║
║ [Tab] Next  [Shift+Tab] Previous         ║
║ [Enter] Confirm  [ESC] Cancel            ║
╚══════════════════════════════════════════╝
```

**Benefits:**
- Single screen = less code
- Visual progress indicator
- Can go back/forward between steps
- All state in one place

**Tradeoffs:**
- More complex state management within one screen
- Less modularity

---

## Recommendation

**Start with Wizard-Style Single Screen** for MVP:
1. Simpler to implement
2. Easier to test
3. Can refactor to multi-screen later if needed
4. Better UX (see progress, navigate back)

Then enhance with:
- Smart defaults everywhere
- Visual previews
- Comprehensive validation
- Good error messages

This plan provides a solid foundation for implementation!
