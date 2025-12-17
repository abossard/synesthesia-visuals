"""
Tests for PadMapper engine.

Tests selector, toggle, and one-shot button behaviors.
"""

import pytest
from launchpad_osc_lib.button_id import ButtonId
from launchpad_osc_lib.model import (
    PadMode,
    ButtonGroupType,
    OscCommand,
    PadBehavior,
    OscEvent,
)
from launchpad_osc_lib.engine import PadMapper


class TestPadMapperConfiguration:
    """Test PadMapper configuration methods."""

    def test_add_pad(self):
        """Adding a pad stores config and initializes runtime."""
        mapper = PadMapper()
        pad_id = ButtonId(0, 0)

        behavior = PadBehavior(
            pad_id=pad_id,
            mode=PadMode.ONE_SHOT,
            idle_color=0,
            active_color=5,
            osc_action=OscCommand("/test")
        )
        mapper.add_pad(behavior)

        assert pad_id in mapper.state.pads
        assert pad_id in mapper.state.runtime
        assert mapper.state.runtime[pad_id].current_color == 0

    def test_remove_pad(self):
        """Removing a pad clears config and runtime."""
        mapper = PadMapper()
        pad_id = ButtonId(0, 0)

        mapper.add_oneshot(pad_id, "/test")
        assert pad_id in mapper.state.pads

        mapper.remove_pad(pad_id)
        assert pad_id not in mapper.state.pads
        assert pad_id not in mapper.state.runtime

    def test_clear_all_pads(self):
        """Clear all removes everything."""
        mapper = PadMapper()
        mapper.add_oneshot(ButtonId(0, 0), "/test1")
        mapper.add_oneshot(ButtonId(1, 1), "/test2")

        mapper.clear_all_pads()

        assert len(mapper.state.pads) == 0
        assert len(mapper.state.runtime) == 0


class TestAddHelpers:
    """Test quick add helper methods."""

    def test_add_selector(self):
        """add_selector creates SELECTOR pad."""
        mapper = PadMapper()
        pad_id = ButtonId(0, 0)

        mapper.add_selector(
            pad_id,
            "/scenes/Test",
            ButtonGroupType.SCENES,
            label="Test Scene",
            idle_color=17,
            active_color=21
        )

        behavior = mapper.state.pads[pad_id]
        assert behavior.mode == PadMode.SELECTOR
        assert behavior.group == ButtonGroupType.SCENES
        assert behavior.osc_action.address == "/scenes/Test"
        assert behavior.idle_color == 17
        assert behavior.active_color == 21

    def test_add_toggle(self):
        """add_toggle creates TOGGLE pad."""
        mapper = PadMapper()
        pad_id = ButtonId(1, 1)

        mapper.add_toggle(
            pad_id,
            "/controls/global/strobe",
            label="Strobe",
            on_args=[1],
            off_args=[0]
        )

        behavior = mapper.state.pads[pad_id]
        assert behavior.mode == PadMode.TOGGLE
        assert behavior.osc_on.address == "/controls/global/strobe"
        assert behavior.osc_on.args == [1]

    def test_add_oneshot(self):
        """add_oneshot creates ONE_SHOT pad."""
        mapper = PadMapper()
        pad_id = ButtonId(2, 2)

        mapper.add_oneshot(
            pad_id,
            "/playlist/random",
            label="Random"
        )

        behavior = mapper.state.pads[pad_id]
        assert behavior.mode == PadMode.ONE_SHOT
        assert behavior.osc_action.address == "/playlist/random"


class TestSelectorBehavior:
    """Test SELECTOR (radio button) behavior."""

    def test_selector_press_activates_pad(self):
        """Pressing selector activates it."""
        mapper = PadMapper()
        pad_id = ButtonId(0, 0)

        mapper.add_selector(pad_id, "/scenes/Test", ButtonGroupType.SCENES, active_color=21)
        mapper.handle_pad_press(pad_id)

        runtime = mapper.state.runtime[pad_id]
        assert runtime.is_active
        assert runtime.current_color == 21
        assert runtime.blink_enabled

    def test_selector_updates_group_tracking(self):
        """Pressing selector updates active_by_group."""
        mapper = PadMapper()
        pad_id = ButtonId(0, 0)

        mapper.add_selector(pad_id, "/scenes/Test", ButtonGroupType.SCENES)
        mapper.handle_pad_press(pad_id)

        assert mapper.state.active_by_group[ButtonGroupType.SCENES] == pad_id

    def test_selector_deactivates_previous_in_group(self):
        """Pressing new selector deactivates previous in same group."""
        mapper = PadMapper()
        pad1 = ButtonId(0, 0)
        pad2 = ButtonId(1, 0)

        mapper.add_selector(pad1, "/scenes/A", ButtonGroupType.SCENES, active_color=21)
        mapper.add_selector(pad2, "/scenes/B", ButtonGroupType.SCENES, active_color=21)

        # Press first, then second
        mapper.handle_pad_press(pad1)
        assert mapper.state.runtime[pad1].is_active

        mapper.handle_pad_press(pad2)
        assert not mapper.state.runtime[pad1].is_active
        assert mapper.state.runtime[pad2].is_active
        assert mapper.state.active_by_group[ButtonGroupType.SCENES] == pad2

    def test_different_groups_independent(self):
        """Selectors in different groups are independent."""
        mapper = PadMapper()
        scene_pad = ButtonId(0, 0)
        preset_pad = ButtonId(1, 0)

        mapper.add_selector(scene_pad, "/scenes/A", ButtonGroupType.SCENES)
        mapper.add_selector(preset_pad, "/presets/B", ButtonGroupType.PRESETS)

        mapper.handle_pad_press(scene_pad)
        mapper.handle_pad_press(preset_pad)

        # Both should be active (different groups)
        assert mapper.state.runtime[scene_pad].is_active
        assert mapper.state.runtime[preset_pad].is_active


class TestToggleBehavior:
    """Test TOGGLE (on/off) behavior."""

    def test_toggle_turns_on(self):
        """Toggle press turns on from off state."""
        mapper = PadMapper()
        pad_id = ButtonId(0, 0)

        mapper.add_toggle(pad_id, "/strobe", active_color=5)
        mapper.handle_pad_press(pad_id)

        runtime = mapper.state.runtime[pad_id]
        assert runtime.is_on
        assert runtime.current_color == 5

    def test_toggle_turns_off(self):
        """Toggle press turns off from on state."""
        mapper = PadMapper()
        pad_id = ButtonId(0, 0)

        mapper.add_toggle(pad_id, "/strobe", idle_color=0, active_color=5)

        # Press twice: on then off
        mapper.handle_pad_press(pad_id)
        assert mapper.state.runtime[pad_id].is_on

        mapper.handle_pad_press(pad_id)
        assert not mapper.state.runtime[pad_id].is_on
        assert mapper.state.runtime[pad_id].current_color == 0


class TestOneShotBehavior:
    """Test ONE_SHOT (trigger) behavior."""

    def test_oneshot_flashes(self):
        """One-shot press shows active color (flash)."""
        mapper = PadMapper()
        pad_id = ButtonId(0, 0)

        mapper.add_oneshot(pad_id, "/random", active_color=9)
        mapper.handle_pad_press(pad_id)

        runtime = mapper.state.runtime[pad_id]
        assert runtime.current_color == 9


class TestOscEventHandling:
    """Test incoming OSC event handling."""

    def test_beat_updates_state(self):
        """Beat OSC updates beat_pulse state."""
        mapper = PadMapper()

        event = OscEvent(1234.5, "/audio/beat/onbeat", [1])
        mapper.handle_osc_event(event)

        assert mapper.state.beat_pulse is True

    def test_scene_syncs_selector(self):
        """Scene OSC syncs matching selector."""
        mapper = PadMapper()
        pad_id = ButtonId(0, 0)

        mapper.add_selector(pad_id, "/scenes/Test", ButtonGroupType.SCENES, active_color=21)

        event = OscEvent(1234.5, "/scenes/Test", [])
        mapper.handle_osc_event(event)

        assert mapper.state.runtime[pad_id].is_active
        assert mapper.state.active_by_group[ButtonGroupType.SCENES] == pad_id


class TestUnmappedPads:
    """Test handling of unmapped pads."""

    def test_unmapped_pad_ignored(self):
        """Pressing unmapped pad does nothing."""
        mapper = PadMapper()

        mapper.handle_pad_press(ButtonId(5, 5))

        # State should be essentially unchanged
        assert len(mapper.state.pads) == 0


class TestStateCallback:
    """Test state change callback."""

    def test_callback_called_on_press(self):
        """State callback is called after pad press."""
        mapper = PadMapper()
        callback_called = []

        def on_change(state):
            callback_called.append(state)

        mapper.set_state_callback(on_change)
        mapper.add_oneshot(ButtonId(0, 0), "/test")
        mapper.handle_pad_press(ButtonId(0, 0))

        assert len(callback_called) == 1


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
