"""
Tests for domain model - Immutable data structures.

These tests verify the core data structures work correctly.
"""

import pytest
from launchpad_synesthesia_control.app.domain.model import (
    PadId, PadMode, PadGroupName, PadBehavior, PadRuntimeState,
    OscCommand, OscEvent, AppMode, LearnState, ControllerState,
    Effect, SendOscEffect, SetLedEffect, SaveConfigEffect, LogEffect
)


# =============================================================================
# PadId Tests
# =============================================================================

class TestPadId:
    """Test PadId identifier class."""

    def test_grid_pad_creation(self):
        """Grid pads have x,y in range 0-7."""
        pad = PadId(3, 4)
        assert pad.x == 3
        assert pad.y == 4
        assert pad.is_grid()
        assert not pad.is_top_row()
        assert not pad.is_right_column()

    def test_top_row_pad(self):
        """Top row pads have y=-1."""
        pad = PadId(5, -1)
        assert pad.is_top_row()
        assert not pad.is_grid()
        assert not pad.is_right_column()
        assert str(pad) == "Top5"

    def test_right_column_pad(self):
        """Right column pads have x=8."""
        pad = PadId(8, 3)
        assert pad.is_right_column()
        assert not pad.is_grid()
        assert not pad.is_top_row()
        assert str(pad) == "Right3"

    def test_grid_pad_str(self):
        """Grid pads show as (x,y)."""
        pad = PadId(2, 5)
        assert str(pad) == "(2,5)"

    def test_pad_equality(self):
        """PadIds with same coords are equal."""
        pad1 = PadId(3, 4)
        pad2 = PadId(3, 4)
        assert pad1 == pad2

    def test_pad_as_dict_key(self):
        """PadIds can be used as dictionary keys."""
        pads = {PadId(0, 0): "first", PadId(1, 1): "second"}
        assert pads[PadId(0, 0)] == "first"
        assert pads[PadId(1, 1)] == "second"

    def test_pad_immutability(self):
        """PadIds are immutable (frozen dataclass)."""
        pad = PadId(0, 0)
        with pytest.raises(AttributeError):
            pad.x = 1

    @pytest.mark.parametrize("x,y,expected", [
        (0, 0, True), (7, 7, True), (0, 7, True), (7, 0, True),
        (-1, 0, False), (8, 0, False), (0, -1, False), (0, 8, False),
    ])
    def test_is_grid_bounds(self, x, y, expected):
        """Test grid boundary detection."""
        pad = PadId(x, y)
        assert pad.is_grid() == expected


# =============================================================================
# OscCommand Tests
# =============================================================================

class TestOscCommand:
    """Test OscCommand data structure."""

    def test_simple_command(self):
        """Command with no args."""
        cmd = OscCommand("/scenes/AlienCavern")
        assert cmd.address == "/scenes/AlienCavern"
        assert cmd.args == []
        assert str(cmd) == "/scenes/AlienCavern"

    def test_command_with_args(self):
        """Command with arguments."""
        cmd = OscCommand("/controls/meta/hue", [0.5])
        assert cmd.args == [0.5]
        assert str(cmd) == "/controls/meta/hue 0.5"

    def test_command_immutability(self):
        """OscCommands are immutable."""
        cmd = OscCommand("/test")
        with pytest.raises(AttributeError):
            cmd.address = "/other"

    @pytest.mark.parametrize("address,expected", [
        ("/scenes/Test", True),
        ("/presets/Cool", True),
        ("/favslots/0", True),
        ("/playlist/next", True),
        ("/controls/meta/hue", True),
        ("/controls/global/brightness", True),
        ("/audio/beat/onbeat", False),  # State-only, not controllable
        ("/random/address", False),
    ])
    def test_is_controllable(self, address, expected):
        """Test controllable address detection."""
        assert OscCommand.is_controllable(address) == expected


# =============================================================================
# OscEvent Tests
# =============================================================================

class TestOscEvent:
    """Test OscEvent data structure."""

    def test_event_creation(self):
        """Create event with timestamp."""
        event = OscEvent(1234567890.123, "/scenes/Test", [1])
        assert event.timestamp == 1234567890.123
        assert event.address == "/scenes/Test"
        assert event.args == [1]

    def test_event_to_command(self):
        """Convert event to command (drops timestamp)."""
        event = OscEvent(1234567890.123, "/scenes/Test", [1])
        cmd = event.to_command()
        assert isinstance(cmd, OscCommand)
        assert cmd.address == "/scenes/Test"
        assert cmd.args == [1]


# =============================================================================
# PadBehavior Tests
# =============================================================================

class TestPadBehavior:
    """Test PadBehavior configuration."""

    def test_selector_behavior(self):
        """Selector mode requires group and osc_action."""
        behavior = PadBehavior(
            pad_id=PadId(0, 0),
            mode=PadMode.SELECTOR,
            group=PadGroupName.SCENES,
            osc_action=OscCommand("/scenes/Test")
        )
        assert behavior.mode == PadMode.SELECTOR
        assert behavior.group == PadGroupName.SCENES

    def test_toggle_behavior(self):
        """Toggle mode requires osc_on."""
        behavior = PadBehavior(
            pad_id=PadId(0, 0),
            mode=PadMode.TOGGLE,
            osc_on=OscCommand("/toggle/on"),
            osc_off=OscCommand("/toggle/off")
        )
        assert behavior.mode == PadMode.TOGGLE
        assert behavior.osc_on.address == "/toggle/on"

    def test_one_shot_behavior(self):
        """One-shot mode requires osc_action."""
        behavior = PadBehavior(
            pad_id=PadId(0, 0),
            mode=PadMode.ONE_SHOT,
            osc_action=OscCommand("/playlist/next")
        )
        assert behavior.mode == PadMode.ONE_SHOT

    def test_selector_requires_group(self):
        """Selector mode without group raises error."""
        with pytest.raises(ValueError, match="SELECTOR mode requires group"):
            PadBehavior(
                pad_id=PadId(0, 0),
                mode=PadMode.SELECTOR,
                osc_action=OscCommand("/test")
            )

    def test_toggle_requires_osc_on(self):
        """Toggle mode without osc_on raises error."""
        with pytest.raises(ValueError, match="TOGGLE mode requires osc_on"):
            PadBehavior(
                pad_id=PadId(0, 0),
                mode=PadMode.TOGGLE
            )

    def test_one_shot_requires_osc_action(self):
        """One-shot mode without osc_action raises error."""
        with pytest.raises(ValueError, match="ONE_SHOT mode requires osc_action"):
            PadBehavior(
                pad_id=PadId(0, 0),
                mode=PadMode.ONE_SHOT
            )

    def test_color_defaults(self):
        """Default colors are off (0) and red (5)."""
        behavior = PadBehavior(
            pad_id=PadId(0, 0),
            mode=PadMode.ONE_SHOT,
            osc_action=OscCommand("/test")
        )
        assert behavior.idle_color == 0
        assert behavior.active_color == 5


# =============================================================================
# PadRuntimeState Tests
# =============================================================================

class TestPadRuntimeState:
    """Test PadRuntimeState."""

    def test_defaults(self):
        """Default runtime state is inactive."""
        runtime = PadRuntimeState()
        assert not runtime.is_active
        assert not runtime.is_on
        assert runtime.current_color == 0
        assert not runtime.blink_enabled

    def test_active_state(self):
        """Active runtime state."""
        runtime = PadRuntimeState(is_active=True, current_color=21, blink_enabled=True)
        assert runtime.is_active
        assert runtime.current_color == 21
        assert runtime.blink_enabled


# =============================================================================
# ControllerState Tests
# =============================================================================

class TestControllerState:
    """Test ControllerState (full app state)."""

    def test_default_state(self):
        """Default state is empty and normal mode."""
        state = ControllerState()
        assert state.pads == {}
        assert state.pad_runtime == {}
        assert state.app_mode == AppMode.NORMAL
        assert state.active_scene is None
        assert state.active_preset is None
        assert not state.beat_pulse

    def test_state_immutability(self):
        """ControllerState is immutable."""
        state = ControllerState()
        with pytest.raises(AttributeError):
            state.app_mode = AppMode.LEARN_WAIT_PAD


# =============================================================================
# Effect Tests
# =============================================================================

class TestEffects:
    """Test Effect classes."""

    def test_send_osc_effect(self):
        """SendOscEffect holds command."""
        cmd = OscCommand("/test")
        effect = SendOscEffect(cmd)
        assert effect.command == cmd

    def test_set_led_effect(self):
        """SetLedEffect holds pad, color, blink."""
        effect = SetLedEffect(PadId(0, 0), 21, blink=True)
        assert effect.pad_id == PadId(0, 0)
        assert effect.color == 21
        assert effect.blink

    def test_save_config_effect(self):
        """SaveConfigEffect is a marker."""
        effect = SaveConfigEffect()
        assert isinstance(effect, Effect)

    def test_log_effect(self):
        """LogEffect holds message and level."""
        effect = LogEffect("Test message", "WARNING")
        assert effect.message == "Test message"
        assert effect.level == "WARNING"


# =============================================================================
# LearnState Tests
# =============================================================================

class TestLearnState:
    """Test LearnState for learn mode."""

    def test_default_learn_state(self):
        """Default learn state is empty."""
        state = LearnState()
        assert state.selected_pad is None
        assert state.recorded_osc_events == []
        assert state.record_start_time is None
        assert state.candidate_commands == []

    def test_learn_state_with_pad(self):
        """Learn state with selected pad."""
        state = LearnState(selected_pad=PadId(3, 4))
        assert state.selected_pad == PadId(3, 4)


# =============================================================================
# AppMode Tests
# =============================================================================

class TestAppMode:
    """Test AppMode enumeration."""

    def test_all_modes_exist(self):
        """All expected modes are defined."""
        assert AppMode.NORMAL
        assert AppMode.LEARN_WAIT_PAD
        assert AppMode.LEARN_RECORD_OSC
        assert AppMode.LEARN_SELECT_MSG

    def test_modes_are_distinct(self):
        """All modes have distinct values."""
        modes = [
            AppMode.NORMAL,
            AppMode.LEARN_WAIT_PAD,
            AppMode.LEARN_RECORD_OSC,
            AppMode.LEARN_SELECT_MSG
        ]
        assert len(modes) == len(set(modes))
