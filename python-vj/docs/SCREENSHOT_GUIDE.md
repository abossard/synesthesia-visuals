# MIDI Router Screenshot Guide

This guide explains how to capture screenshots for the MIDI Router documentation.

## Prerequisites

1. **Hardware**: MIDI controller (Launchpad, MIDImix, or similar)
2. **Software**: VJ Console running with MIDI router configured
3. **Virtual MIDI**: IAC Driver enabled with "MagicBus" port

## Screenshot List

### 1. Main MIDI Router Screen (Screen 5)
**Filename**: `screenshots/midi-screen-overview.png`

**Setup**:
- Launch VJ Console: `python vj_console.py`
- Press `5` to navigate to MIDI Router screen
- Have 3-4 toggles configured with different states (some ON, some OFF)

**Capture**: Full terminal window showing all 4 panels

**What to show**:
- ✅ Toggle list with mix of ON (●) and OFF (○) states
- ✅ Status panel showing router running
- ✅ MIDI traffic log with recent messages
- ✅ Actions panel with keyboard shortcuts

---

### 2. Controller Selection Modal
**Filename**: `screenshots/controller-selection.png`

**Setup**:
- On MIDI screen (Screen 5)
- Press `c` to open controller selection modal
- Multiple MIDI controllers connected (if possible)

**Capture**: Modal overlay showing list of available controllers

**What to show**:
- ✅ List of detected controllers (Launchpad, MIDImix, etc.)
- ✅ Navigation arrows (↑↓)
- ✅ Instructions "Enter to select, Esc to cancel"

---

### 3. Learn Mode Active
**Filename**: `screenshots/learn-mode-active.png`

**Setup**:
- On MIDI screen (Screen 5)
- Press `l` to enter learn mode
- Don't press any controller button yet

**Capture**: Status panel showing "🎹 LEARN MODE ACTIVE" or similar

**What to show**:
- ✅ Learn mode indicator (yellow/highlighted)
- ✅ Status text explaining what to do next
- ✅ Existing toggle list unchanged

---

### 4. MIDI Traffic Log in Action
**Filename**: `screenshots/midi-traffic.png`

**Setup**:
- On MIDI screen (Screen 5)
- Press several pads on controller quickly
- Toggle a few buttons on and off

**Capture**: Close-up of MIDI Traffic panel

**What to show**:
- ✅ Multiple MIDI messages with timestamps
- ✅ Incoming messages (← arrow)
- ✅ Outgoing messages (→ arrow)
- ✅ Note numbers and velocities clearly visible

---

### 5. Toggle State Indicator
**Filename**: `screenshots/toggle-states.png`

**Setup**:
- On MIDI screen (Screen 5)
- Configure 4-6 toggles
- Set different states: some ON, some OFF
- Select one toggle (highlight with ▸)

**Capture**: Close-up of Toggles panel

**What to show**:
- ✅ Note numbers (e.g., 40, 41, 42)
- ✅ Toggle names (e.g., "TwisterOn", "LyricsOn")
- ✅ ON indicators (● in green/bright)
- ✅ OFF indicators (○ in dim/gray)
- ✅ Selection indicator (▸)

---

### 6. Configuration Panel
**Filename**: `screenshots/config-panel.png`

**Setup**:
- On MIDI screen (Screen 5)
- Router running with controller connected

**Capture**: Configuration panel showing details

**What to show**:
- ✅ Controller name (e.g., "Launchpad Mini MK3")
- ✅ Virtual port (e.g., "MagicBus")
- ✅ Toggle count
- ✅ Config file path

---

### 7. Full VJ Console with MIDI Screen
**Filename**: `screenshots/vj-console-midi.png`

**Setup**:
- VJ Console running
- MIDI screen active (Screen 5)
- Optional: Magic Music Visuals running in background

**Capture**: Full desktop showing VJ Console

**What to show**:
- ✅ Terminal window with VJ Console
- ✅ MIDI Router screen clearly visible
- ✅ (Optional) Magic window visible behind
- ✅ Gives context of how it fits in VJ workflow

---

## Capture Settings

### Terminal Settings
- **Font**: Monospace, 12-14pt
- **Window size**: At least 120x40 characters
- **Color scheme**: Dark background preferred (shows MIDI traffic better)
- **Transparency**: Off (for clearer screenshots)

### Screenshot Tool
- **macOS**: Cmd+Shift+4, then drag to select area
- **Linux**: `gnome-screenshot -a` or Spectacle
- **Windows**: Snipping Tool or Win+Shift+S

### File Format
- **Format**: PNG (lossless)
- **Resolution**: At least 1920x1080 for full window
- **Color depth**: 24-bit (true color)

## After Capturing

1. **Save to**: `python-vj/docs/screenshots/`
2. **Verify**: Check each image is clear and readable
3. **Update docs**: Replace `[SCREENSHOT_PLACEHOLDER]` markers in MIDI_ROUTER.md
4. **Commit**: Add screenshots to git with descriptive commit message

## Screenshot Placement in Documentation

Edit `MIDI_ROUTER.md` and replace placeholders:

```markdown
<!-- Replace this: -->
[SCREENSHOT_PLACEHOLDER: Main MIDI Router Screen]

<!-- With: -->
![MIDI Router Screen](docs/screenshots/midi-screen-overview.png)
*VJ Console Screen 5 - MIDI Router with active toggles and traffic log*
```

## Tips for Good Screenshots

✅ **Do**:
- Use a clean, focused terminal layout
- Show realistic usage (3-5 toggles, not empty)
- Capture during actual MIDI activity
- Use consistent terminal theme across all screenshots
- Include timestamps in traffic log

❌ **Don't**:
- Capture with cursor in the middle of text
- Show empty/unconfigured screens
- Include sensitive information (API keys, paths with username)
- Use tiny terminal windows (text must be readable)

## Example Flow

1. **Start fresh**: `rm -rf ~/.midi_router/` to start with clean config
2. **Launch**: `python vj_console.py`
3. **Setup**: Press `5`, press `l`, learn 3-4 toggles
4. **Activate**: Toggle some ON, leave some OFF
5. **Capture**: Take screenshots following the list above
6. **Press controller**: Generate MIDI traffic
7. **Capture traffic**: Screenshot the activity
8. **Select controller**: Press `c`, screenshot the modal

## Questions?

If you're unsure about any screenshot:
1. Check the ASCII diagrams in MIDI_ROUTER.md for reference
2. Focus on showing the actual functionality
3. When in doubt, capture more rather than less

The goal is to show users what they'll see, not to create marketing material. Authentic, clear screenshots of the actual UI are best.
