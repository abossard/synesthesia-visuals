#!/usr/bin/env python
"""
Interactive Hardware Tests for Launchpad Mini MK3

Run specific tests by number or 'all' for full suite.
Usage: python interactive_hw_tests.py [test_number]
"""
import sys
import time
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

def get_launchpad():
    """Connect to Launchpad in programmer mode."""
    lps = lpminimk3.find_launchpads()
    if not lps:
        print("❌ No Launchpad found!")
        sys.exit(1)
    lp = lps[0]
    lp.open()
    lp.mode = lpminimk3.Mode.PROG
    lp.grid.reset()
    return lp

def wait_for_press(lp, count=1):
    """Wait for N button presses, return list of (x, y) tuples (LED coordinates)."""
    results = []
    while len(results) < count:
        event = lp.panel.buttons().poll_for_event()
        if event and event.type == lpminimk3.ButtonEvent.PRESS and event.button:
            x, y = event.button.x, event.button.y - 1  # Apply y-1 fix
            results.append((x, y))
    return results

def wait_for_any_press(lp):
    """Wait for any button press, return (x, y) in LED coordinates."""
    return wait_for_press(lp, 1)[0]


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
# TEST 4: Top Row Detection
# =============================================================================
def test_4_top_row(lp):
    """Test top row button detection."""
    print("\n" + "=" * 50)
    print("TEST 4: Top Row Detection")
    print("=" * 50)
    print()
    
    # Light the top row (control buttons)
    # In lpminimk3, top row is accessed differently
    print("Note: Top row (control buttons) may have different coordinates.")
    print("Press the 8 buttons at the very top of the Launchpad.")
    print("We'll detect what coordinates they report.")
    print()
    
    # Light the grid top row as reference
    for col in range(8):
        lp.grid.led(col, 7).color = CYAN
    print("Top grid row (y=7) is lit cyan for reference.")
    print()
    print("Press 4 top control buttons to see their coordinates...")
    print()
    
    for i in range(4):
        event = None
        while not event or event.type != lpminimk3.ButtonEvent.PRESS:
            event = lp.panel.buttons().poll_for_event()
        
        x, y = event.button.x, event.button.y
        fixed_y = y - 1
        print(f"  Press #{i+1}: raw=({x},{y}) -> fixed=({x},{fixed_y})")
        
        # If it's a top row button (y=-1 after fix), it's outside grid
        if fixed_y == -1:
            print(f"    → This is a TOP ROW control button (x={x})")
        elif fixed_y >= 0 and fixed_y <= 7:
            print(f"    → This is a GRID button")
    
    lp.grid.reset()
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
    
    # Light rightmost grid column for reference
    for row in range(8):
        lp.grid.led(7, row).color = ORANGE
    print("Rightmost grid column (x=7) is lit orange for reference.")
    print()
    print("Press the 4 scene launch buttons (right edge, outside the grid)...")
    print()
    
    for i in range(4):
        event = None
        while not event or event.type != lpminimk3.ButtonEvent.PRESS:
            event = lp.panel.buttons().poll_for_event()
        
        x, y = event.button.x, event.button.y
        fixed_y = y - 1
        print(f"  Press #{i+1}: raw=({x},{y}) -> fixed=({x},{fixed_y})")
        
        if x == 8:
            print(f"    → This is a SCENE LAUNCH button (row {fixed_y})")
        elif x <= 7:
            print(f"    → This is a GRID button")
    
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
                    print(f"   Pad configured! Select another or exit learn mode.")
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
# TEST 7: Bank Switching Simulation
# =============================================================================
def test_7_bank_switching(lp):
    """Simulate bank switching using actual top row control buttons."""
    print("\n" + "=" * 50)
    print("TEST 7: Bank Switching (Top Row)")
    print("=" * 50)
    print()
    
    banks = [
        {"name": "Bank A", "color": RED},
        {"name": "Bank B", "color": GREEN},
        {"name": "Bank C", "color": BLUE},
        {"name": "Bank D", "color": YELLOW},
    ]
    
    active_bank = 0
    
    # Light top row bank buttons (y=-1 in our coordinate system)
    # Top row LEDs use panel.led() not grid.led()
    def light_top_row_banks():
        for i, bank in enumerate(banks):
            # Top row uses different LED access - try via panel
            try:
                if i == active_bank:
                    lp.panel.led(i, 0).color = bank["color"]
                else:
                    lp.panel.led(i, 0).color = 1  # Dim
            except:
                pass  # Some top row LEDs might not be controllable
    
    light_top_row_banks()
    
    # Fill bank content on the 8x8 grid
    def show_bank_content(bank_idx):
        for row in range(8):
            for col in range(8):
                if bank_idx == 0:
                    color = RED if (col + row) % 2 == 0 else OFF
                elif bank_idx == 1:
                    color = GREEN if col == row or col == 7 - row else OFF
                elif bank_idx == 2:
                    color = BLUE if col < 4 else OFF
                else:
                    color = YELLOW if row < 4 else OFF
                lp.grid.led(col, row).color = color
    
    show_bank_content(active_bank)
    
    print(f"Active: {banks[active_bank]['name']}")
    print()
    print("Press TOP ROW buttons (above the grid, y=-1) to switch banks.")
    print("  Button 0-3 = Banks A-D")
    print("Press any SCENE button (right column, x=8) to exit.")
    print()
    
    while True:
        event = lp.panel.buttons().poll_for_event()
        if not event or event.type != lpminimk3.ButtonEvent.PRESS or not event.button:
            continue
        
        x, y = event.button.x, event.button.y - 1  # Apply y-1 fix
        
        # Scene button (right column) = exit
        if x == 8:
            print("👋 Exiting bank test")
            break
        
        # Top row button (y=-1) = bank switch
        if y == -1 and x < 4:
            old_bank = active_bank
            active_bank = x
            
            # Update top row bank button LEDs
            light_top_row_banks()
            
            print(f"Switched to {banks[active_bank]['name']}")
            show_bank_content(active_bank)
    
    lp.grid.reset()
    print()
    print("✅ Bank switching test complete!")


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
