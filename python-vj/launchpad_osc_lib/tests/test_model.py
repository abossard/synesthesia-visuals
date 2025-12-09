"""
Tests for domain models.

Tests PadMode, ButtonGroupType, OscCommand, PadBehavior, PadRuntimeState.
"""

import pytest
from launchpad_osc_lib.launchpad import PadId
from launchpad_osc_lib.model import (
    PadMode,
    ButtonGroupType,
    OscCommand,
    PadBehavior,
    PadRuntimeState,
)


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


class TestPadBehavior:
    """Test PadBehavior configuration."""

    def test_selector_behavior(self):
        """Selector mode requires group and osc_action."""
        behavior = PadBehavior(
            pad_id=PadId(0, 0),
            mode=PadMode.SELECTOR,
            group=ButtonGroupType.SCENES,
            osc_action=OscCommand("/scenes/Test")
        )
        assert behavior.mode == PadMode.SELECTOR
        assert behavior.group == ButtonGroupType.SCENES

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


class TestButtonGroupType:
    """Test ButtonGroupType enum."""

    def test_all_groups_exist(self):
        """All expected groups are defined."""
        assert ButtonGroupType.SCENES
        assert ButtonGroupType.PRESETS
        assert ButtonGroupType.COLORS
        assert ButtonGroupType.CUSTOM

    def test_groups_are_strings(self):
        """Groups have string values."""
        assert ButtonGroupType.SCENES.value == "scenes"
        assert ButtonGroupType.PRESETS.value == "presets"


class TestPadMode:
    """Test PadMode enum."""

    def test_all_modes_exist(self):
        """All expected modes are defined."""
        assert PadMode.SELECTOR
        assert PadMode.TOGGLE
        assert PadMode.ONE_SHOT

    def test_modes_are_distinct(self):
        """All modes have distinct values."""
        modes = [PadMode.SELECTOR, PadMode.TOGGLE, PadMode.ONE_SHOT]
        assert len(modes) == len(set(modes))


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
