#!/usr/bin/env python
"""
Interactive Hardware Tests for Launchpad Mini MK3

Run specific tests by number or 'all' for full suite.
Usage: python interactive_hw_tests.py [test_number]

LPMINIMK3 COORDINATE SYSTEM:
- panel.y=0 is the TOP ROW (control buttons: up, down, left, right, session, drums, keys, user)
- panel.y=1-8 is the 8x8 GRID (y=1 is bottom row, y=8 is top row)
- panel.x=8 is the SCENE LAUNCH column (right edge)

OUR COORDINATE SYSTEM (after y-1 fix):
- y=-1 is the TOP ROW (control buttons)
- y=0-7 is the 8x8 GRID (matches LED addressing)
- x=8 is the SCENE LAUNCH column
"""
import sys
import lpminimk3

# Color constants
OFF = 0
RED = 5
GREEN = 21
BLUE = 45
YELLOW = 13
CYAN = 37
MAGENTA = 53
WHITE = 3
ORANGE = 9
PINK = 57

# Top row button names (x=0-7 at y=-1)
TOP_ROW_BUTTONS = ["Up", "Down", "Left", "Right", "Session", "Drums", "Keys", "User"]


def get_launchpad():
    """Connect to Launchpad in programmer mode."""
    lps = lpminimk3.find_launchpads()
    if not lps:
        print("❌ No Launchpad found!")
        sys.exit(1)
    lp = lps[0]
    lp.open()
    
    # Verify and set programmer mode
    lp.mode = lpminimk3.Mode.PROG
    print("✅ Launchpad connected in PROGRAMMER mode")
    print(f"   Panel dimensions: {lp.panel.width}x{lp.panel.height}")
    print(f"   Grid dimensions: {lp.grid.width}x{lp.grid.height}")
    print()
    
    lp.grid.reset()
    lp.panel.reset()
    return lp


def wait_for_press(lp, count=1):
    """Wait for N button presses, return list of (x, y, raw_y) tuples."""
    results = []
    while len(results) < count:
        event = lp.panel.buttons().poll_for_event()
        if event and event.type == lpminimk3.ButtonEvent.PRESS and event.button:
            raw_x, raw_y = event.button.x, event.button.y
            fixed_y = raw_y - 1  # Apply y-1 fix
            results.append((raw_x, fixed_y, raw_y))
    return results


def wait_for_any_press(lp):
    """Wait for any button press, return (x, y) in LED coordinates."""
    result = wait_for_press(lp, 1)[0]
    return (result[0], result[1])  # Return only x, fixed_y


# =============================================================================
# TEST 1: LED Color Palette
# =============================================================================
def test_1_colors(lp):
    """Display color palette across the grid."""
    print("\n" + "=" * 50)
    print("TEST 1: LED Color Palette")
    print("=" * 50)
    print()
    print("Displaying colors 0-63 on the grid...")
    print("Each row is 8 consecutive colors.")
    print()
    
    for row in range(8):
        for col in range(8):
            color = row * 8 + col
            lp.grid.led(col, row).color = color
    
    print("Color map:")
    print("  Row 0 (bottom): colors 0-7")
    print("  Row 1: colors 8-15")
    print("  ...")
    print("  Row 7 (top): colors 56-63")
    print()
    print("Press any pad to continue...")
    wait_for_any_press(lp)
    
    # Second page: colors 64-127
    print("\nDisplaying colors 64-127...")
    for row in range(8):
        for col in range(8):
            color = 64 + row * 8 + col
            lp.grid.led(col, row).color = color
    
    print("Press any pad to finish...")
    wait_for_any_press(lp)
    lp.grid.reset()
    print("✅ Color test complete!")


# =============================================================================
# TEST 2: Button Feedback
# =============================================================================
def test_2_button_feedback(lp):
    """Press buttons and see immediate LED feedback."""
    print("\n" + "=" * 50)
    print("TEST 2: Button Feedback")
    print("=" * 50)
    print()
    print("Press any pad - it will light up!")
    print("Press 10 different pads to complete the test.")
    print("(Same pad twice counts as one)")
    print()
    
    pressed_pads = set()
    colors = [RED, GREEN, BLUE, YELLOW, CYAN, MAGENTA, ORANGE, PINK, WHITE, 45]
    
    while len(pressed_pads) < 10:
        event = lp.panel.buttons().poll_for_event()
        if event and event.button:
            x, y = event.button.x, event.button.y - 1
            
            if event.type == lpminimk3.ButtonEvent.PRESS:
                if (x, y) not in pressed_pads and 0 <= x <= 7 and 0 <= y <= 7:
                    pressed_pads.add((x, y))
                    color = colors[len(pressed_pads) - 1]
                    lp.grid.led(x, y).color = color
                    print(f"  Pad ({x},{y}) pressed - color {color} ({len(pressed_pads)}/10)")
    
    print()
    print("✅ Button feedback test complete!")
    print("Press any pad to clear and continue...")
    wait_for_any_press(lp)
    lp.grid.reset()


# =============================================================================
# TEST 3: Flash/Blink Mode
# =============================================================================
def test_3_flash_mode(lp):
    """Test flashing LEDs."""
    print("\n" + "=" * 50)
    print("TEST 3: Flash Mode")
    print("=" * 50)
    print()
    print("Lighting alternating pads with flash mode...")
    print()
    
    for row in range(8):
        for col in range(8):
            if (row + col) % 2 == 0:
                lp.grid.led(col, row, mode='flash').color = RED
            else:
                lp.grid.led(col, row, mode='static').color = BLUE
    
    print("Red pads should be flashing, blue pads static.")
    print("Press any pad to continue...")
    wait_for_any_press(lp)
    lp.grid.reset()
    print("✅ Flash mode test complete!")


# =============================================================================
# TEST 4: Top Row Detection (Control Buttons)
# =============================================================================
def test_4_top_row(lp):
    """Test top row button detection - all 8 control buttons."""
    print("\n" + "=" * 50)
    print("TEST 4: Top Row Detection (Control Buttons)")
    print("=" * 50)
    print()
    print("TOP ROW BUTTONS (above the grid):")
    print("  x=0: Up       x=4: Session")
    print("  x=1: Down     x=5: Drums")
    print("  x=2: Left     x=6: Keys")
    print("  x=3: Right    x=7: User")
    print()
    print("In lpminimk3, top row is y=0 (raw)")
    print("With our y-1 fix, top row becomes y=-1")
    print()
    
    # Light the top row buttons for visual feedback
    print("Lighting top row buttons...")
    for col in range(8):
        try:
            lp.panel.led(col, 0).color = [RED, ORANGE, YELLOW, GREEN, CYAN, BLUE, MAGENTA, WHITE][col]
        except Exception as e:
            print(f"  ⚠️ Could not light top row button {col}: {e}")
    
    # Also light grid row 7 as reference
    for col in range(8):
        lp.grid.led(col, 7).color = 1  # Dim for comparison
    print("Grid row 7 (y=7) lit dim as reference.")
    print()
    
    print("Press ALL 8 top row buttons to verify detection.")
    print("(The row ABOVE the grid, where Up/Down/Left/Right and Session/Drums/Keys/User are)")
    print()
    
    detected = {}
    while len(detected) < 8:
        event = lp.panel.buttons().poll_for_event()
        if not event or event.type != lpminimk3.ButtonEvent.PRESS or not event.button:
            continue
        
        raw_x, raw_y = event.button.x, event.button.y
        fixed_y = raw_y - 1
        
        if raw_x in detected:
            continue
        
        if fixed_y == -1:  # Top row
            button_name = TOP_ROW_BUTTONS[raw_x] if raw_x < 8 else f"x={raw_x}"
            detected[raw_x] = button_name
            print(f"  ✅ raw=({raw_x},{raw_y}) → fixed=({raw_x},{fixed_y}) = TOP ROW: {button_name}")
            print(f"     [{len(detected)}/8 detected]")
        elif fixed_y >= 0 and fixed_y <= 7 and raw_x <= 7:
            print(f"  ℹ️  raw=({raw_x},{raw_y}) → fixed=({raw_x},{fixed_y}) = GRID (not top row)")
        elif raw_x == 8:
            print(f"  ℹ️  raw=({raw_x},{raw_y}) → fixed=({raw_x},{fixed_y}) = SCENE LAUNCH (not top row)")
    
    print()
    print("All 8 top row buttons detected!")
    print("Button mapping verified:")
    for x in range(8):
        print(f"  x={x}: {detected.get(x, 'NOT DETECTED')}")
    
    lp.grid.reset()
    lp.panel.reset()
    print()
    print("✅ Top row detection complete!")


# =============================================================================
# TEST 5: Scene Buttons (Right Column)
# =============================================================================
def test_5_scene_buttons(lp):
    """Test right column scene button detection."""
    print("\n" + "=" * 50)
    print("TEST 5: Scene Buttons (Right Column)")
    print("=" * 50)
    print()
    print("Scene launch buttons are on the RIGHT EDGE (x=8)")
    print("They report as Note messages, not CC like top row.")
    print()
    
    # Light rightmost grid column for reference
    for row in range(8):
        lp.grid.led(7, row).color = ORANGE
    print("Rightmost grid column (x=7) is lit orange for reference.")
    print()
    print("Press 4 scene launch buttons (the column to the RIGHT of the orange)...")
    print()
    
    detected = []
    while len(detected) < 4:
        event = lp.panel.buttons().poll_for_event()
        if not event or event.type != lpminimk3.ButtonEvent.PRESS or not event.button:
            continue
        
        raw_x, raw_y = event.button.x, event.button.y
        fixed_y = raw_y - 1
        
        if raw_x == 8:
            detected.append(fixed_y)
            print(f"  ✅ raw=({raw_x},{raw_y}) → fixed=({raw_x},{fixed_y})")
            print(f"     SCENE LAUNCH button (row {fixed_y})")
        elif fixed_y == -1:
            print(f"  ℹ️  raw=({raw_x},{raw_y}) → TOP ROW (not scene launch)")
        else:
            print(f"  ℹ️  raw=({raw_x},{raw_y}) → GRID (not scene launch)")
    
    lp.grid.reset()
    print()
    print("✅ Scene button detection complete!")


# =============================================================================
# TEST 6: Simulated Learn Mode (No OSC)
# =============================================================================
def test_6_learn_mode_simulation(lp):
    """Simulate learn mode workflow without OSC."""
    print("\n" + "=" * 50)
    print("TEST 6: Learn Mode Simulation (No OSC)")
    print("=" * 50)
    print()
    print("This simulates the learn mode workflow:")
    print("  1. Enter learn mode (scene button)")
    print("  2. Select a pad to configure")
    print("  3. Simulate OSC recording")
    print("  4. Exit learn mode")
    print()
    
    # State
    learn_mode = False
    selected_pad = None
    configured_pads = {}
    
    # Light scene buttons as mode switches
    # We'll use grid pads for now since scene buttons are harder to light
    # Use bottom row as "control row" for demo
    lp.grid.led(0, 0).color = GREEN   # "Enter Learn"
    lp.grid.led(1, 0).color = RED     # "Exit Learn"
    lp.grid.led(2, 0).color = BLUE    # "Simulate OSC"
    
    print("Control pads (bottom row):")
    print("  (0,0) GREEN = Enter Learn Mode")
    print("  (1,0) RED   = Exit Learn Mode / Cancel")
    print("  (2,0) BLUE  = Simulate OSC Recording")
    print()
    print("Press GREEN to start...")
    print()
    
    while True:
        event = lp.panel.buttons().poll_for_event()
        if not event or event.type != lpminimk3.ButtonEvent.PRESS or not event.button:
            continue
        
        x, y = event.button.x, event.button.y - 1
        
        # Check control buttons
        if y == 0:
            if x == 0:  # Enter learn mode
                if not learn_mode:
                    learn_mode = True
                    selected_pad = None
                    print("📚 LEARN MODE ACTIVE")
                    print("   Press any grid pad to select it for configuration...")
                    # Flash all unconfigured pads
                    for row in range(1, 8):
                        for col in range(8):
                            if (col, row) not in configured_pads:
                                lp.grid.led(col, row, mode='flash').color = YELLOW
                            
            elif x == 1:  # Exit learn mode
                if learn_mode:
                    learn_mode = False
                    selected_pad = None
                    print("🚪 EXITED LEARN MODE")
                    # Restore configured pads
                    lp.grid.reset()
                    lp.grid.led(0, 0).color = GREEN
                    lp.grid.led(1, 0).color = RED
                    lp.grid.led(2, 0).color = BLUE
                    for (px, py), color in configured_pads.items():
                        lp.grid.led(px, py).color = color
                else:
                    print("👋 Test complete!")
                    break
                    
            elif x == 2:  # Simulate OSC
                if learn_mode and selected_pad:
                    # "Record" this pad
                    configured_pads[selected_pad] = MAGENTA
                    print(f"   ✅ Recorded OSC for pad {selected_pad}")
                    print("   Pad configured! Select another or exit learn mode.")
                    lp.grid.led(selected_pad[0], selected_pad[1]).color = MAGENTA
                    selected_pad = None
                elif learn_mode:
                    print("   ⚠️ No pad selected! Press a grid pad first.")
                    
        # Check grid pads (not control row)
        elif y >= 1 and y <= 7 and 0 <= x <= 7:
            if learn_mode:
                if selected_pad:
                    # Deselect previous
                    if selected_pad not in configured_pads:
                        lp.grid.led(selected_pad[0], selected_pad[1], mode='flash').color = YELLOW
                
                selected_pad = (x, y)
                print(f"   🎯 Selected pad ({x},{y}) - press BLUE to simulate OSC")
                lp.grid.led(x, y).color = WHITE  # Highlight selected
            else:
                # Normal mode - show feedback
                if (x, y) in configured_pads:
                    print(f"Pad ({x},{y}) is configured!")
                else:
                    print(f"Pad ({x},{y}) pressed (not in learn mode)")
    
    lp.grid.reset()
    print()
    print("✅ Learn mode simulation complete!")
    print(f"   Configured {len(configured_pads)} pads")


# =============================================================================
# TEST 7: Bank Switching (Using Actual Top Row)
# =============================================================================
def test_7_bank_switching(lp):
    """Bank switching using all 8 top row control buttons (y=-1)."""
    print("\n" + "=" * 50)
    print("TEST 7: Bank Switching (Top Row - 8 Banks)")
    print("=" * 50)
    print()
    
    banks = [
        {"name": "Bank A (Up)", "color": RED, "button": "Up"},
        {"name": "Bank B (Down)", "color": GREEN, "button": "Down"},
        {"name": "Bank C (Left)", "color": BLUE, "button": "Left"},
        {"name": "Bank D (Right)", "color": YELLOW, "button": "Right"},
        {"name": "Bank E (Session)", "color": CYAN, "button": "Session"},
        {"name": "Bank F (Drums)", "color": MAGENTA, "button": "Drums"},
        {"name": "Bank G (Keys)", "color": ORANGE, "button": "Keys"},
        {"name": "Bank H (User)", "color": WHITE, "button": "User"},
    ]
    
    active_bank = 0
    
    # Light top row bank buttons (panel.led at y=0 for lpminimk3)
    def light_top_row_banks():
        for i, bank in enumerate(banks):
            try:
                color = bank["color"] if i == active_bank else 1  # Active vs dim
                lp.panel.led(i, 0).color = color
            except Exception as e:
                print(f"  ⚠️ Could not light top button {i}: {e}")
    
    light_top_row_banks()
    
    # Fill bank content on the 8x8 grid - unique pattern for each bank
    def show_bank_content(bank_idx):
        for row in range(8):
            for col in range(8):
                if bank_idx == 0:  # Checkerboard
                    color = RED if (col + row) % 2 == 0 else OFF
                elif bank_idx == 1:  # X pattern
                    color = GREEN if col == row or col == 7 - row else OFF
                elif bank_idx == 2:  # Left half
                    color = BLUE if col < 4 else OFF
                elif bank_idx == 3:  # Bottom half
                    color = YELLOW if row < 4 else OFF
                elif bank_idx == 4:  # Border
                    color = CYAN if row == 0 or row == 7 or col == 0 or col == 7 else OFF
                elif bank_idx == 5:  # Center square
                    color = MAGENTA if 2 <= col <= 5 and 2 <= row <= 5 else OFF
                elif bank_idx == 6:  # Vertical stripes
                    color = ORANGE if col % 2 == 0 else OFF
                else:  # Horizontal stripes
                    color = WHITE if row % 2 == 0 else OFF
                lp.grid.led(col, row).color = color
    
    show_bank_content(active_bank)
    
    print(f"Active: {banks[active_bank]['name']}")
    print()
    print("Use ALL 8 TOP ROW buttons to switch banks:")
    print("  Up (x=0)      = Bank A (red checkerboard)")
    print("  Down (x=1)    = Bank B (green X)")
    print("  Left (x=2)    = Bank C (blue left half)")
    print("  Right (x=3)   = Bank D (yellow bottom half)")
    print("  Session (x=4) = Bank E (cyan border)")
    print("  Drums (x=5)   = Bank F (magenta center)")
    print("  Keys (x=6)    = Bank G (orange stripes)")
    print("  User (x=7)    = Bank H (white stripes)")
    print()
    print("Press any SCENE LAUNCH button (right column) to exit.")
    print()
    
    while True:
        event = lp.panel.buttons().poll_for_event()
        if not event or event.type != lpminimk3.ButtonEvent.PRESS or not event.button:
            continue
        
        raw_x, raw_y = event.button.x, event.button.y
        fixed_y = raw_y - 1  # Apply y-1 fix
        
        # Scene button (right column) = exit
        if raw_x == 8:
            print("👋 Exiting bank test")
            break
        
        # Top row button (y=-1 after fix, y=0 raw) = bank switch
        if fixed_y == -1 and raw_x < 8:
            active_bank = raw_x
            light_top_row_banks()
            print(f"✅ Switched to {banks[active_bank]['name']} (pressed {TOP_ROW_BUTTONS[raw_x]})")
            show_bank_content(active_bank)
        elif fixed_y >= 0:
            print(f"  ℹ️ Grid pad ({raw_x},{fixed_y}) pressed")
    
    lp.grid.reset()
    lp.panel.reset()
    print()
    print("✅ Bank switching test complete!")


# =============================================================================
# TEST 8: Full Programming Workflow Simulation
# =============================================================================
def test_8_full_programming(lp):
    """
    Full programming workflow simulation with:
    - OSC message selection (simulated)
    - Pad mode selection (SELECTOR, TOGGLE, ONE_SHOT)
    - Color selection with brightness levels
    - Blink/flash mode testing
    - Bank-aware configuration
    """
    import time
    
    print("\n" + "=" * 50)
    print("TEST 8: Full Programming Workflow")
    print("=" * 50)
    print()
    
    # Simulated OSC messages (what would come from Synesthesia)
    SIMULATED_OSC = [
        "/scenes/AlienCavern",
        "/scenes/NeonGiza",
        "/scenes/FluidNoise",
        "/presets/Warm",
        "/presets/Cool",
        "/presets/Intense",
        "/global/strobe",
        "/global/mirror",
        "/meta/color/hue",
        "/playlist/random",
    ]
    
    # Pad modes
    PAD_MODES = ["SELECTOR", "TOGGLE", "ONE_SHOT", "PUSH"]
    
    # Color options (base colors with brightness)
    COLORS = {
        "red": (1, 5, 6),       # dim, normal, bright
        "orange": (7, 9, 10),
        "yellow": (11, 13, 14),
        "green": (19, 21, 22),
        "cyan": (33, 37, 38),
        "blue": (41, 45, 46),
        "purple": (49, 53, 54),
        "pink": (55, 57, 58),
    }
    COLOR_NAMES = list(COLORS.keys())
    
    # State
    state = {
        "phase": "IDLE",  # IDLE, SELECT_PAD, SELECT_OSC, SELECT_MODE, SELECT_COLOR, TEST_PAD
        "selected_pad": None,
        "configured_pads": {},  # {(x,y): {osc, mode, idle_color, active_color, blink}}
        "current_bank": 0,
        "osc_page": 0,
        "selected_osc": None,
        "selected_mode": None,
        "idle_color": 21,  # green
        "active_color": 5,  # red
        "blink_enabled": False,
    }
    
    def show_help():
        """Show current phase instructions."""
        print()
        print("-" * 40)
        if state["phase"] == "IDLE":
            print("IDLE MODE - Press Scene button to enter Learn Mode")
            print("  Scene 0 (bottom right) = Enter Learn Mode")
            print("  Scene 7 (top right) = Exit Test")
        elif state["phase"] == "SELECT_PAD":
            print("SELECT PAD - Press any grid pad to configure")
            print("  Scene 0 = Cancel / Back to IDLE")
        elif state["phase"] == "SELECT_OSC":
            print(f"SELECT OSC - Page {state['osc_page']+1} (O pattern shown)")
            print("  Bottom row (row 0): OSC options")
            print("  Scene 0 = Back | Scene 1 = Next Page")
        elif state["phase"] == "SELECT_MODE":
            print("SELECT MODE - Choose pad behavior (M pattern shown)")
            print("  Bottom row (row 0): SELECTOR | TOGGLE | ONE_SHOT | PUSH")
            print("  Scene 0 = Back")
        elif state["phase"] == "SELECT_COLOR":
            print("SELECT COLOR - Choose colors (colorful C shown)")
            print("  Row 1: Idle color options")
            print("  Row 2: Active color options")
            print("  Row 0: [0]=Toggle Blink [7]=Confirm")
            print("  Scene 0 = Back")
        elif state["phase"] == "TEST_PAD":
            print("TEST PAD - Test the configured pad")
            print("  Press the configured pad to see it work")
            print("  Scene 0 = Back | Scene 1 = Save & Done")
        print("-" * 40)
    
    def refresh_display():
        """Update LEDs based on current state."""
        lp.grid.reset()
        
        # Show configured pads in current bank
        for (x, y), config in state["configured_pads"].items():
            if config.get("bank", 0) == state["current_bank"]:
                color = config.get("idle_color", 21)
                lp.grid.led(x, y).color = color
        
        # Phase-specific display
        if state["phase"] == "IDLE":
            # Show "READY" pattern
            for col in range(8):
                lp.grid.led(col, 3).color = GREEN
                lp.grid.led(col, 4).color = GREEN
            # Light scene button 0 for "Enter Learn"
            try:
                lp.panel.led(8, 1).color = GREEN  # Scene 0 (raw y=1)
                lp.panel.led(8, 8).color = RED    # Scene 7 (raw y=8)
            except Exception:
                pass
                
        elif state["phase"] == "SELECT_PAD":
            # Flash all unconfigured pads
            for row in range(8):
                for col in range(8):
                    if (col, row) not in state["configured_pads"]:
                        lp.grid.led(col, row, mode='flash').color = YELLOW
            # Highlight configured pads
            for (x, y), config in state["configured_pads"].items():
                lp.grid.led(x, y).color = config.get("idle_color", 21)
                
        elif state["phase"] == "SELECT_OSC":
            # Draw "O" pattern on top right (cols 4-7, rows 4-7)
            o_pattern = [
                "  OO  ",
                " O  O ",
                "O    O",
                "O    O",
                "O    O",
                " O  O ",
                "  OO  ",
            ]
            for row_idx, row_str in enumerate(o_pattern):
                for col_idx, char in enumerate(row_str):
                    if char == 'O':
                        lp.grid.led(col_idx + 2, 7 - row_idx).color = CYAN
            
            # Show OSC options on bottom rows (8 per page)
            start = state["osc_page"] * 8
            for i in range(8):
                idx = start + i
                if idx < len(SIMULATED_OSC):
                    lp.grid.led(i, 0).color = YELLOW  # Selection row at bottom
            # Navigation
            try:
                lp.panel.led(8, 1).color = RED    # Back
                lp.panel.led(8, 2).color = YELLOW  # Next page
            except Exception:
                pass
                
        elif state["phase"] == "SELECT_MODE":
            # Draw "M" pattern on top (cols 1-6, rows 3-7)
            m_pattern = [
                "M    M",
                "MM  MM",
                "M MM M",
                "M    M",
                "M    M",
                "M    M",
            ]
            for row_idx, row_str in enumerate(m_pattern):
                for col_idx, char in enumerate(row_str):
                    if char == 'M':
                        lp.grid.led(col_idx + 1, 7 - row_idx).color = MAGENTA
            
            # Mode buttons on row 0 (bottom)
            mode_colors = [BLUE, GREEN, ORANGE, CYAN]
            for i, color in enumerate(mode_colors):
                lp.grid.led(i, 0).color = color
            # Labels on row 1
            lp.grid.led(0, 1).color = 1  # SELECTOR
            lp.grid.led(1, 1).color = 1  # TOGGLE
            lp.grid.led(2, 1).color = 1  # ONE_SHOT
            lp.grid.led(3, 1).color = 1  # PUSH
            
        elif state["phase"] == "SELECT_COLOR":
            # Draw colorful "C" pattern on top right
            c_colors = [RED, ORANGE, YELLOW, GREEN, CYAN, BLUE, MAGENTA]
            c_pattern = [
                (4, 7), (5, 7), (6, 7),  # Top of C
                (3, 6),                   # Left upper
                (3, 5),                   # Left middle
                (3, 4),                   # Left lower
                (4, 3), (5, 3), (6, 3),  # Bottom of C
            ]
            for i, (cx, cy) in enumerate(c_pattern):
                lp.grid.led(cx, cy).color = c_colors[i % len(c_colors)]
            
            # Idle colors (row 1) - bottom area
            for i, name in enumerate(COLOR_NAMES):
                if i < 8:
                    lp.grid.led(i, 1).color = COLORS[name][1]  # Normal brightness
            # Active colors (row 2)
            for i, name in enumerate(COLOR_NAMES):
                if i < 8:
                    lp.grid.led(i, 2).color = COLORS[name][2]  # Bright
            
            # Blink toggle and confirm (row 0)
            blink_color = WHITE if state["blink_enabled"] else 1
            lp.grid.led(0, 0, mode='flash' if state["blink_enabled"] else 'static').color = blink_color
            # Confirm button
            lp.grid.led(7, 0).color = GREEN
            
        elif state["phase"] == "TEST_PAD":
            # Show the configured pad
            if state["selected_pad"]:
                x, y = state["selected_pad"]
                mode = 'flash' if state["blink_enabled"] else 'static'
                lp.grid.led(x, y, mode=mode).color = state["idle_color"]
            # Instructions
            lp.grid.led(0, 0).color = RED   # Back
            lp.grid.led(7, 0).color = GREEN  # Save
    
    def transition_to(new_phase):
        """Transition to a new phase."""
        old_phase = state["phase"]
        state["phase"] = new_phase
        print(f"\n→ {old_phase} → {new_phase}")
        refresh_display()
        show_help()
    
    # Initial display
    refresh_display()
    show_help()
    print()
    print("Starting full programming simulation...")
    print("Configured pads will be saved to memory (not persisted).")
    print()
    
    running = True
    while running:
        event = lp.panel.buttons().poll_for_event()
        if not event or event.type != lpminimk3.ButtonEvent.PRESS or not event.button:
            continue
        
        raw_x, raw_y = event.button.x, event.button.y
        x, y = raw_x, raw_y - 1  # Apply y-1 fix
        
        # Scene buttons (x=8)
        if raw_x == 8:
            scene_idx = y  # 0-7 after fix
            
            if state["phase"] == "IDLE":
                if scene_idx == 0:
                    transition_to("SELECT_PAD")
                elif scene_idx == 7:
                    print("\n👋 Exiting test")
                    running = False
                    
            elif state["phase"] == "SELECT_PAD":
                if scene_idx == 0:
                    transition_to("IDLE")
                    
            elif state["phase"] == "SELECT_OSC":
                if scene_idx == 0:
                    transition_to("SELECT_PAD")
                elif scene_idx == 1:
                    # Next page
                    max_pages = (len(SIMULATED_OSC) + 7) // 8
                    state["osc_page"] = (state["osc_page"] + 1) % max_pages
                    print(f"  OSC Page {state['osc_page']+1}/{max_pages}")
                    refresh_display()
                    
            elif state["phase"] == "SELECT_MODE":
                if scene_idx == 0:
                    transition_to("SELECT_OSC")
                    
            elif state["phase"] == "SELECT_COLOR":
                if scene_idx == 0:
                    transition_to("SELECT_MODE")
                    
            elif state["phase"] == "TEST_PAD":
                if scene_idx == 0:
                    transition_to("SELECT_COLOR")
                elif scene_idx == 1:
                    # Save configuration
                    if state["selected_pad"]:
                        px, py = state["selected_pad"]
                        state["configured_pads"][(px, py)] = {
                            "osc": state["selected_osc"],
                            "mode": state["selected_mode"],
                            "idle_color": state["idle_color"],
                            "active_color": state["active_color"],
                            "blink": state["blink_enabled"],
                            "bank": state["current_bank"],
                        }
                        print(f"\n✅ SAVED pad ({px},{py}):")
                        print(f"   OSC: {state['selected_osc']}")
                        print(f"   Mode: {state['selected_mode']}")
                        print(f"   Colors: idle={state['idle_color']}, active={state['active_color']}")
                        print(f"   Blink: {state['blink_enabled']}")
                    transition_to("IDLE")
            continue
        
        # Top row buttons (y=-1) - Bank switching
        if y == -1 and x < 8:
            state["current_bank"] = x
            print(f"\n🏦 Switched to Bank {x} ({TOP_ROW_BUTTONS[x]})")
            refresh_display()
            continue
        
        # Grid buttons (x=0-7, y=0-7)
        if 0 <= x <= 7 and 0 <= y <= 7:
            
            if state["phase"] == "SELECT_PAD":
                state["selected_pad"] = (x, y)
                state["osc_page"] = 0
                print(f"\n🎯 Selected pad ({x},{y})")
                transition_to("SELECT_OSC")
                
            elif state["phase"] == "SELECT_OSC":
                if y == 0:  # OSC selection row at BOTTOM
                    idx = state["osc_page"] * 8 + x
                    if idx < len(SIMULATED_OSC):
                        state["selected_osc"] = SIMULATED_OSC[idx]
                        print(f"\n📨 Selected OSC: {state['selected_osc']}")
                        transition_to("SELECT_MODE")
                        
            elif state["phase"] == "SELECT_MODE":
                if y == 0 and x < 4:  # Mode buttons at BOTTOM
                    state["selected_mode"] = PAD_MODES[x]
                    print(f"\n⚙️ Selected mode: {state['selected_mode']}")
                    transition_to("SELECT_COLOR")
                    
            elif state["phase"] == "SELECT_COLOR":
                if y == 1 and x < len(COLOR_NAMES):
                    # Idle color (row 1)
                    state["idle_color"] = COLORS[COLOR_NAMES[x]][1]
                    print(f"  Idle color: {COLOR_NAMES[x]}")
                    refresh_display()
                elif y == 2 and x < len(COLOR_NAMES):
                    # Active color (row 2)
                    state["active_color"] = COLORS[COLOR_NAMES[x]][2]  # Bright
                    print(f"  Active color: {COLOR_NAMES[x]}")
                    refresh_display()
                elif y == 0:
                    if x == 0:
                        # Toggle blink
                        state["blink_enabled"] = not state["blink_enabled"]
                        print(f"  Blink: {'ON' if state['blink_enabled'] else 'OFF'}")
                        refresh_display()
                    elif x == 7:
                        # Confirm - go to test
                        transition_to("TEST_PAD")
                        
            elif state["phase"] == "TEST_PAD":
                if (x, y) == state["selected_pad"]:
                    # Test the pad!
                    print(f"\n🔔 PAD PRESSED! Would send: {state['selected_osc']}")
                    # Flash active color
                    lp.grid.led(x, y).color = state["active_color"]
                    time.sleep(0.3)
                    mode = 'flash' if state["blink_enabled"] else 'static'
                    lp.grid.led(x, y, mode=mode).color = state["idle_color"]
                elif y == 0:
                    if x == 0:
                        transition_to("SELECT_COLOR")
                    elif x == 7:
                        # Save (handled above in scene button section)
                        pass
    
    # Summary
    lp.grid.reset()
    lp.panel.reset()
    print()
    print("=" * 40)
    print("PROGRAMMING SESSION SUMMARY")
    print("=" * 40)
    print(f"Configured {len(state['configured_pads'])} pads:")
    for (px, py), config in state["configured_pads"].items():
        print(f"  ({px},{py}): {config['osc']} [{config['mode']}]")
    print()
    print("✅ Full programming test complete!")


# =============================================================================
# MAIN
# =============================================================================
def run_all_tests():
    """Run all interactive tests."""
    lp = get_launchpad()
    
    try:
        test_1_colors(lp)
        test_2_button_feedback(lp)
        test_3_flash_mode(lp)
        test_4_top_row(lp)
        test_5_scene_buttons(lp)
        test_6_learn_mode_simulation(lp)
        test_7_bank_switching(lp)
        test_8_full_programming(lp)
        
        print("\n" + "=" * 50)
        print("ALL TESTS COMPLETE!")
        print("=" * 50)
    finally:
        lp.grid.reset()
        lp.close()


def main():
    tests = {
        "1": ("LED Color Palette", test_1_colors),
        "2": ("Button Feedback", test_2_button_feedback),
        "3": ("Flash Mode", test_3_flash_mode),
        "4": ("Top Row Detection", test_4_top_row),
        "5": ("Scene Buttons", test_5_scene_buttons),
        "6": ("Learn Mode Simulation", test_6_learn_mode_simulation),
        "7": ("Bank Switching", test_7_bank_switching),
        "8": ("Full Programming Workflow", test_8_full_programming),
    }
    
    if len(sys.argv) > 1:
        choice = sys.argv[1]
    else:
        print("\n" + "=" * 50)
        print("INTERACTIVE HARDWARE TESTS")
        print("=" * 50)
        print()
        for num, (name, _) in tests.items():
            print(f"  {num}. {name}")
        print()
        print("  all - Run all tests")
        print("  q   - Quit")
        print()
        choice = input("Select test: ").strip().lower()
    
    if choice == "q":
        return
    
    lp = get_launchpad()
    
    try:
        if choice == "all":
            for num in sorted(tests.keys()):
                tests[num][1](lp)
        elif choice in tests:
            tests[choice][1](lp)
        else:
            print(f"Unknown test: {choice}")
    finally:
        lp.grid.reset()
        lp.close()


if __name__ == "__main__":
    main()
