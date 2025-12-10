"""
Tests for blink module - Beat-synced LED blinking logic.

These tests verify blink phase calculations work correctly.
"""

import pytest
from launchpad_osc_lib import (
    compute_blink_phase,
    should_led_be_lit,
    compute_all_led_states,
    get_dimmed_color,
    ButtonId, PadMode, PadGroupName, PadBehavior, PadRuntimeState, ControllerState,
    OscCommand
)


# =============================================================================
# compute_blink_phase Tests
# =============================================================================

class TestComputeBlinkPhase:
    """Test blink phase computation."""

    def test_beat_pulse_on_returns_full_intensity(self):
        """When beat is on, phase is 1.0."""
        phase = compute_blink_phase(beat_pulse=True, beat_phase=0.0)
        assert phase == 1.0

    def test_beat_pulse_off_returns_dim_intensity(self):
        """When beat is off, phase is dimmed."""
        phase = compute_blink_phase(beat_pulse=False, beat_phase=0.0)
        assert phase == 0.3

    def test_beat_phase_ignored_currently(self):
        """Beat phase parameter is available for future smooth transitions."""
        # Current implementation uses pulse-based blinking
        phase1 = compute_blink_phase(beat_pulse=True, beat_phase=0.0)
        phase2 = compute_blink_phase(beat_pulse=True, beat_phase=0.5)
        phase3 = compute_blink_phase(beat_pulse=True, beat_phase=1.0)

        # All should be same when pulse is on
        assert phase1 == phase2 == phase3 == 1.0


# =============================================================================
# should_led_be_lit Tests
# =============================================================================

class TestShouldLedBeLit:
    """Test LED lit determination."""

    def test_non_blinking_led_always_lit(self):
        """LEDs with blink disabled are always lit."""
        runtime = PadRuntimeState(blink_enabled=False)

        # Should be lit regardless of phase
        assert should_led_be_lit(runtime, 0.0) is True
        assert should_led_be_lit(runtime, 0.3) is True
        assert should_led_be_lit(runtime, 0.5) is True
        assert should_led_be_lit(runtime, 1.0) is True

    def test_blinking_led_lit_when_phase_high(self):
        """Blinking LEDs are lit when phase > 0.5."""
        runtime = PadRuntimeState(blink_enabled=True)

        assert should_led_be_lit(runtime, 0.6) is True
        assert should_led_be_lit(runtime, 0.8) is True
        assert should_led_be_lit(runtime, 1.0) is True

    def test_blinking_led_dimmed_when_phase_low(self):
        """Blinking LEDs are dimmed when phase <= 0.5."""
        runtime = PadRuntimeState(blink_enabled=True)

        assert should_led_be_lit(runtime, 0.0) is False
        assert should_led_be_lit(runtime, 0.3) is False
        assert should_led_be_lit(runtime, 0.5) is False

    def test_threshold_boundary(self):
        """Test exact threshold behavior."""
        runtime = PadRuntimeState(blink_enabled=True)

        assert should_led_be_lit(runtime, 0.5) is False
        assert should_led_be_lit(runtime, 0.50001) is True


# =============================================================================
# compute_all_led_states Tests
# =============================================================================

class TestComputeAllLedStates:
    """Test computing LED states for all pads."""

    @pytest.fixture
    def state_with_pads(self):
        """State with multiple pad configurations."""
        pad1 = ButtonId(0, 0)  # Blinking
        pad2 = ButtonId(1, 0)  # Not blinking

        behavior1 = PadBehavior(
            pad_id=pad1, mode=PadMode.SELECTOR, group=PadGroupName.SCENES,
            osc_action=OscCommand("/scenes/A"), idle_color=0, active_color=21
        )
        behavior2 = PadBehavior(
            pad_id=pad2, mode=PadMode.ONE_SHOT,
            osc_action=OscCommand("/test"), idle_color=0, active_color=5
        )

        return ControllerState(
            pads={pad1: behavior1, pad2: behavior2},
            pad_runtime={
                pad1: PadRuntimeState(is_active=True, current_color=21, blink_enabled=True),
                pad2: PadRuntimeState(is_active=False, current_color=5, blink_enabled=False)
            }
        )

    def test_returns_dict_of_led_states(self, state_with_pads):
        """Returns dictionary mapping pad to (color, is_lit)."""
        led_states = compute_all_led_states(state_with_pads, blink_phase=1.0)

        assert isinstance(led_states, dict)
        assert ButtonId(0, 0) in led_states
        assert ButtonId(1, 0) in led_states

    def test_blinking_pad_lit_at_high_phase(self, state_with_pads):
        """Blinking pad is lit when phase is high."""
        led_states = compute_all_led_states(state_with_pads, blink_phase=1.0)

        color, is_lit = led_states[ButtonId(0, 0)]
        assert is_lit is True
        assert color == 21

    def test_blinking_pad_dimmed_at_low_phase(self, state_with_pads):
        """Blinking pad is dimmed when phase is low."""
        led_states = compute_all_led_states(state_with_pads, blink_phase=0.3)

        color, is_lit = led_states[ButtonId(0, 0)]
        assert is_lit is False
        assert color == 21  # Color unchanged, dimming applied separately

    def test_non_blinking_pad_always_lit(self, state_with_pads):
        """Non-blinking pad is always lit regardless of phase."""
        for phase in [0.0, 0.3, 0.5, 1.0]:
            led_states = compute_all_led_states(state_with_pads, blink_phase=phase)
            color, is_lit = led_states[ButtonId(1, 0)]
            assert is_lit is True


# =============================================================================
# get_dimmed_color Tests
# =============================================================================

class TestGetDimmedColor:
    """Test color dimming for blink-off state."""

    def test_off_stays_off(self):
        """Color 0 (off) stays off when dimmed."""
        assert get_dimmed_color(0) == 0

    def test_color_is_reduced(self):
        """Colors are reduced by approximately 70%."""
        # Green (21) -> dimmed
        dimmed = get_dimmed_color(21)
        assert dimmed == 7  # 21 // 3

    def test_bright_colors_dim_significantly(self):
        """Bright colors are significantly dimmed."""
        original = 60
        dimmed = get_dimmed_color(original)
        assert dimmed == 20  # 60 // 3
        assert dimmed < original

    def test_low_colors_stay_visible(self):
        """Low colors don't dim to invisible."""
        for color in [1, 2, 3]:
            dimmed = get_dimmed_color(color)
            assert dimmed >= 1  # At least minimally visible

    def test_max_dimmed_color(self):
        """Dimmed color doesn't exceed 127."""
        # This shouldn't happen with normal colors, but test edge case
        dimmed = get_dimmed_color(127)
        assert dimmed <= 127

    @pytest.mark.parametrize("color,expected", [
        (0, 0),     # Off stays off
        (3, 1),     # White -> very dim
        (5, 1),     # Red -> dim red
        (21, 7),    # Green -> dim green
        (45, 15),   # Blue -> dim blue
    ])
    def test_specific_color_dimming(self, color, expected):
        """Test specific color dimming values."""
        assert get_dimmed_color(color) == expected


# =============================================================================
# Integration Tests
# =============================================================================

class TestBlinkIntegration:
    """Integration tests for blink system."""

    def test_beat_sync_workflow(self):
        """Test typical beat sync workflow."""
        # Setup: Active selector pad with blinking
        pad_id = ButtonId(0, 0)
        behavior = PadBehavior(
            pad_id=pad_id, mode=PadMode.SELECTOR, group=PadGroupName.SCENES,
            osc_action=OscCommand("/scenes/Test"), active_color=21
        )
        state = ControllerState(
            pads={pad_id: behavior},
            pad_runtime={
                pad_id: PadRuntimeState(
                    is_active=True, current_color=21, blink_enabled=True
                )
            }
        )

        # Simulate beat ON
        phase_on = compute_blink_phase(beat_pulse=True, beat_phase=0.0)
        led_states_on = compute_all_led_states(state, phase_on)
        color, is_lit = led_states_on[pad_id]
        assert is_lit is True  # Full brightness on beat

        # Simulate beat OFF
        phase_off = compute_blink_phase(beat_pulse=False, beat_phase=0.0)
        led_states_off = compute_all_led_states(state, phase_off)
        color, is_lit = led_states_off[pad_id]
        assert is_lit is False  # Dimmed off beat
