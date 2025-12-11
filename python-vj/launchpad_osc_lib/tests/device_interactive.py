#!/usr/bin/env python3
"""
Interactive Device Test for Launchpad Mini MK3

This test requires a physical Launchpad connected and runs through
various scenarios, waiting for keypress between each phase.

Run manually: python -m launchpad_osc_lib.tests.test_device_interactive

These tests are SKIPPED by pytest unless a Launchpad is connected.
To run interactively, execute the module directly.
"""

import sys
import time
from typing import Optional

import pytest

try:
    import lpminimk3
    from lpminimk3 import Mode
    LPMINIMK3_AVAILABLE = True
except ImportError:
    LPMINIMK3_AVAILABLE = False
    lpminimk3 = None
    Mode = None

# Skip all tests in this module if lpminimk3 not available or no device connected
pytestmark = pytest.mark.skipif(
    not LPMINIMK3_AVAILABLE,
    reason="lpminimk3 not installed or no Launchpad connected"
)

if LPMINIMK3_AVAILABLE:
    from launchpad_osc_lib import (
        ButtonId, PadMode, ButtonGroupType, PadBehavior, PadRuntimeState,
        OscCommand, LearnPhase, LearnState, ControllerState, LedEffect,
        LP_RED, LP_GREEN, LP_BLUE, LP_YELLOW, LP_CYAN, LP_PURPLE, LP_PINK, LP_ORANGE, LP_WHITE,
        render_idle, render_learn_wait_pad, render_learn_record_osc, render_learn_config,
    )
    from typing import List


def wait_for_key(prompt: str = "Press Enter to continue..."):
    """Wait for user to press Enter."""
    input(f"\n⏸️  {prompt}")


def clear_all_leds(lp):
    """Turn off all LEDs."""
    for y in range(8):
        for x in range(8):
            lp.grid.led(x, y).color = 0
    # Clear scene buttons (right column)
    for y in range(8):
        try:
            lp.panel.led(f"scene_{y+1}").color = 0
        except Exception:
            pass
    # Clear top row
    for x in range(8):
        try:
            lp.panel.led(f"top_{x+1}").color = 0
        except Exception:
            pass


def apply_led_effects(lp, effects: List[LedEffect]):
    """Apply LED effects to Launchpad."""
    for effect in effects:
        btn_id = effect.pad_id
        color = effect.color
        if btn_id.is_grid():
            lp.grid.led(btn_id.x, btn_id.y).color = color
        elif btn_id.is_right_column():
            # Scene buttons
            try:
                lp.panel.led(f"scene_{btn_id.y + 1}").color = color
            except Exception:
                pass


def find_launchpad() -> Optional[lpminimk3.LaunchpadMiniMk3]:
    """Find and connect to Launchpad."""
    print("🔍 Searching for Launchpad Mini MK3...")
    
    launchpads = lpminimk3.find_launchpads()
    if not launchpads:
        return None
    
    lp = launchpads[0]
    lp.open()
    lp.mode = Mode.PROG
    return lp


def test_phase_1_all_colors(lp):
    """Phase 1: Display all colors in a gradient."""
    print("\n" + "="*60)
    print("📍 PHASE 1: Color Palette Test")
    print("="*60)
    print("Displaying color palette across the grid...")
    
    colors = [
        LP_RED, LP_ORANGE, LP_YELLOW, LP_GREEN,
        LP_CYAN, LP_BLUE, LP_PURPLE, LP_PINK,
    ]
    
    for y in range(8):
        for x in range(8):
            color_idx = (x + y) % len(colors)
            lp.grid.led(x, y).color = colors[color_idx]
    
    print("✅ Grid shows rainbow gradient")


def test_phase_2_brightness_levels(lp):
    """Phase 2: Show brightness levels for each color."""
    print("\n" + "="*60)
    print("📍 PHASE 2: Brightness Levels")
    print("="*60)
    print("Each column shows a color at 3 brightness levels (dim/normal/bright)")
    
    # Row 0-2: Red brightness, Row 3-5: Green brightness, etc.
    color_velocities = [
        (1, 5, 6),    # Red: dim, normal, bright
        (7, 9, 10),   # Orange
        (11, 13, 14), # Yellow
        (19, 21, 22), # Green
        (33, 37, 38), # Cyan
        (41, 45, 46), # Blue
        (49, 53, 54), # Purple
        (55, 57, 58), # Pink
    ]
    
    clear_all_leds(lp)
    
    for col, (dim, normal, bright) in enumerate(color_velocities):
        lp.grid.led(col, 0).color = dim
        lp.grid.led(col, 1).color = normal
        lp.grid.led(col, 2).color = bright
    
    print("Row 0: Dim | Row 1: Normal | Row 2: Bright")


def test_phase_3_idle_state(lp):
    """Phase 3: Render idle state with configured pads."""
    print("\n" + "="*60)
    print("📍 PHASE 3: Idle State Display")
    print("="*60)
    print("Showing configured pads in idle state...")
    
    # Create state with some configured pads
    pads = {}
    pad_runtime = {}
    
    # Scene selectors (row 6)
    for x in range(4):
        pad_id = ButtonId(x, 6)
        pads[pad_id] = PadBehavior(
            pad_id=pad_id,
            mode=PadMode.SELECTOR,
            group=ButtonGroupType.SCENES,
            idle_color=LP_GREEN - 2,  # Dim green
            active_color=LP_GREEN,
            osc_action=OscCommand(f"/scenes/Scene{x+1}")
        )
        pad_runtime[pad_id] = PadRuntimeState(
            is_active=(x == 0),  # First one active
            current_color=LP_GREEN if x == 0 else LP_GREEN - 2
        )
    
    # Toggle buttons (row 4)
    for x in range(3):
        pad_id = ButtonId(x, 4)
        pads[pad_id] = PadBehavior(
            pad_id=pad_id,
            mode=PadMode.TOGGLE,
            idle_color=LP_BLUE - 4,
            active_color=LP_BLUE,
            osc_on=OscCommand(f"/toggle/{x}/on"),
            osc_off=OscCommand(f"/toggle/{x}/off")
        )
        pad_runtime[pad_id] = PadRuntimeState(
            is_on=(x == 1),  # Second one ON
            current_color=LP_BLUE if x == 1 else LP_BLUE - 4
        )
    
    # One-shot buttons (row 2)
    for x in range(2):
        pad_id = ButtonId(x, 2)
        pads[pad_id] = PadBehavior(
            pad_id=pad_id,
            mode=PadMode.ONE_SHOT,
            idle_color=LP_ORANGE - 2,
            active_color=LP_ORANGE,
            osc_action=OscCommand(f"/action/{x}")
        )
        pad_runtime[pad_id] = PadRuntimeState(current_color=LP_ORANGE - 2)
    
    state = ControllerState(
        pads=pads,
        pad_runtime=pad_runtime,
        active_selector_by_group={ButtonGroupType.SCENES: ButtonId(0, 6)}
    )
    
    clear_all_leds(lp)
    led_state = render_idle(state)
    apply_led_effects(lp, led_state)
    
    print("Row 6: Scene selectors (green, first active)")
    print("Row 4: Toggles (blue, second one ON)")
    print("Row 2: One-shots (orange)")


def test_phase_4_learn_wait_pad(lp):
    """Phase 4: Learn mode - waiting for pad selection."""
    print("\n" + "="*60)
    print("📍 PHASE 4: Learn Mode - Wait for Pad")
    print("="*60)
    print("All pads should blink, indicating 'select a pad to configure'")
    
    state = ControllerState(
        learn_state=LearnState(phase=LearnPhase.WAIT_PAD),
        blink_on=True
    )
    
    clear_all_leds(lp)
    led_state = render_learn_wait_pad(state)
    apply_led_effects(lp, led_state)
    
    print("✅ Grid shows blinking yellow (press any pad to configure)")
    print("   Learn button (bottom-right scene) should be lit")


def test_phase_5_learn_record_osc(lp):
    """Phase 5: Learn mode - recording OSC."""
    print("\n" + "="*60)
    print("📍 PHASE 5: Learn Mode - Recording OSC")
    print("="*60)
    print("Selected pad blinks, waiting for OSC messages...")
    
    selected_pad = ButtonId(3, 4)
    state = ControllerState(
        learn_state=LearnState(
            phase=LearnPhase.RECORD_OSC,
            selected_pad=selected_pad
        ),
        blink_on=True
    )
    
    clear_all_leds(lp)
    led_state = render_learn_record_osc(state)
    apply_led_effects(lp, led_state)
    
    print(f"✅ Selected pad {selected_pad} should be blinking red")
    print("   Other pads dim, waiting for OSC input")


def test_phase_6_learn_config(lp):
    """Phase 6: Learn mode - configuration phase."""
    print("\n" + "="*60)
    print("📍 PHASE 6: Learn Mode - Configuration")
    print("="*60)
    print("Config UI: OSC selection, mode selection, color selection")
    
    from launchpad_osc_lib.model import LearnRegister
    
    selected_pad = ButtonId(3, 4)
    candidate_commands = [
        OscCommand("/scenes/AlienCavern"),
        OscCommand("/scenes/NeonGiza"),
        OscCommand("/presets/Cool"),
    ]
    
    state = ControllerState(
        learn_state=LearnState(
            phase=LearnPhase.CONFIG,
            selected_pad=selected_pad,
            candidate_commands=candidate_commands,
            selected_osc_index=0,
            selected_mode=PadMode.SELECTOR,
            active_register=LearnRegister.OSC_SELECT,
            selected_idle_color=LP_GREEN - 2,
            selected_active_color=LP_GREEN,
        ),
        blink_on=True
    )
    
    clear_all_leds(lp)
    led_state = render_learn_config(state)
    apply_led_effects(lp, led_state)
    
    print("✅ Config UI displayed:")
    print("   - Top row: Register tabs (OSC/Mode/Color)")
    print("   - Row 3: OSC command options (3 recorded)")
    print("   - Bottom row: Save (green), Test (blue), Cancel (red)")


def test_phase_7_button_press_feedback(lp):
    """Phase 7: Simulate button press feedback."""
    print("\n" + "="*60)
    print("📍 PHASE 7: Button Press Animation")
    print("="*60)
    print("Watch the grid flash in sequence...")
    
    clear_all_leds(lp)
    
    # Flash each row in sequence
    for y in range(8):
        for x in range(8):
            lp.grid.led(x, y).color = LP_WHITE
        time.sleep(0.1)
        for x in range(8):
            lp.grid.led(x, y).color = 0
    
    # Ripple effect from center
    print("Ripple effect from center...")
    center_x, center_y = 3.5, 3.5
    
    for radius in range(8):
        for y in range(8):
            for x in range(8):
                dist = ((x - center_x)**2 + (y - center_y)**2)**0.5
                if radius <= dist < radius + 1:
                    lp.grid.led(x, y).color = LP_CYAN
        time.sleep(0.08)
        for y in range(8):
            for x in range(8):
                lp.grid.led(x, y).color = 0
    
    print("✅ Animation complete")


def test_phase_8_beat_sync_simulation(lp):
    """Phase 8: Simulate beat-synced blinking."""
    print("\n" + "="*60)
    print("📍 PHASE 8: Beat Sync Simulation")
    print("="*60)
    print("Simulating 120 BPM beat pulse (4 beats)...")
    
    # Create some pads with blink enabled
    pads = {}
    pad_runtime = {}
    
    for x in range(4):
        pad_id = ButtonId(x, 5)
        pads[pad_id] = PadBehavior(
            pad_id=pad_id,
            mode=PadMode.SELECTOR,
            group=ButtonGroupType.SCENES,
            idle_color=LP_RED - 4,
            active_color=LP_RED,
            osc_action=OscCommand(f"/scenes/Scene{x}")
        )
        pad_runtime[pad_id] = PadRuntimeState(
            is_active=True,
            current_color=LP_RED,
            blink_enabled=True
        )
    
    clear_all_leds(lp)
    
    # 120 BPM = 0.5s per beat
    beat_duration = 0.5
    
    for beat in range(4):
        # Beat ON - bright
        for x in range(4):
            lp.grid.led(x, 5).color = LP_RED
        time.sleep(beat_duration * 0.3)
        
        # Beat OFF - dim
        for x in range(4):
            lp.grid.led(x, 5).color = LP_RED - 4
        time.sleep(beat_duration * 0.7)
    
    print("✅ Beat sync simulation complete")


def main():
    """Main test runner."""
    print("\n" + "="*60)
    print("🎹 LAUNCHPAD MINI MK3 - INTERACTIVE DEVICE TEST")
    print("="*60)
    print("This test walks through various display scenarios.")
    print("Press Enter after each phase to continue.\n")
    
    # Find and connect to Launchpad
    lp = find_launchpad()
    if not lp:
        print("❌ No Launchpad found!")
        print("   Make sure your Launchpad Mini MK3 is connected.")
        print("   On macOS, check Audio MIDI Setup for MIDI devices.")
        sys.exit(1)
    
    print(f"✅ Connected to: {lp}")
    
    try:
        # Run test phases
        phases = [
            ("Color Palette", test_phase_1_all_colors),
            ("Brightness Levels", test_phase_2_brightness_levels),
            ("Idle State", test_phase_3_idle_state),
            ("Learn: Wait for Pad", test_phase_4_learn_wait_pad),
            ("Learn: Record OSC", test_phase_5_learn_record_osc),
            ("Learn: Config UI", test_phase_6_learn_config),
            ("Button Animation", test_phase_7_button_press_feedback),
            ("Beat Sync", test_phase_8_beat_sync_simulation),
        ]
        
        for i, (name, test_fn) in enumerate(phases):
            print(f"\n[{i+1}/{len(phases)}] {name}")
            test_fn(lp)
            
            if i < len(phases) - 1:
                wait_for_key(f"Phase {i+1} complete. Press Enter for next phase...")
        
        print("\n" + "="*60)
        print("🎉 ALL TESTS COMPLETE!")
        print("="*60)
        
        wait_for_key("Press Enter to clear LEDs and exit...")
        
    finally:
        # Cleanup
        clear_all_leds(lp)
        lp.close()
        print("👋 Launchpad disconnected. Goodbye!")


if __name__ == "__main__":
    main()
