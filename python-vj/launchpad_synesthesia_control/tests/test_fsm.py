"""
Tests for FSM (Finite State Machine) logic.

These tests verify state transitions are correct and pure.
"""

import pytest
from dataclasses import replace

from launchpad_synesthesia_control.app.domain.model import (
    PadId, PadMode, PadGroupName, PadBehavior, PadRuntimeState,
    OscCommand, OscEvent, AppMode, LearnState, ControllerState,
    SendOscEffect, SetLedEffect, SaveConfigEffect, LogEffect
)
from launchpad_synesthesia_control.app.domain.fsm import (
    handle_pad_press, handle_osc_event,
    enter_learn_mode, cancel_learn_mode, finish_osc_recording,
    select_learn_command,
    _handle_selector_press, _handle_toggle_press, _handle_one_shot_press,
    _activate_matching_selector
)


# =============================================================================
# Fixtures
# =============================================================================

@pytest.fixture
def empty_state():
    """Fresh controller state with no pads configured."""
    return ControllerState()


@pytest.fixture
def state_with_selector():
    """State with a selector pad configured."""
    pad_id = PadId(0, 0)
    behavior = PadBehavior(
        pad_id=pad_id,
        mode=PadMode.SELECTOR,
        group=PadGroupName.SCENES,
        idle_color=0,
        active_color=21,
        label="Test Scene",
        osc_action=OscCommand("/scenes/Test")
    )
    runtime = PadRuntimeState(is_active=False, current_color=0)

    return ControllerState(
        pads={pad_id: behavior},
        pad_runtime={pad_id: runtime}
    )


@pytest.fixture
def state_with_toggle():
    """State with a toggle pad configured."""
    pad_id = PadId(1, 1)
    behavior = PadBehavior(
        pad_id=pad_id,
        mode=PadMode.TOGGLE,
        idle_color=0,
        active_color=5,
        label="Test Toggle",
        osc_on=OscCommand("/toggle/on"),
        osc_off=OscCommand("/toggle/off")
    )
    runtime = PadRuntimeState(is_active=False, is_on=False, current_color=0)

    return ControllerState(
        pads={pad_id: behavior},
        pad_runtime={pad_id: runtime}
    )


@pytest.fixture
def state_with_one_shot():
    """State with a one-shot pad configured."""
    pad_id = PadId(2, 2)
    behavior = PadBehavior(
        pad_id=pad_id,
        mode=PadMode.ONE_SHOT,
        idle_color=0,
        active_color=9,
        label="Next",
        osc_action=OscCommand("/playlist/next")
    )
    runtime = PadRuntimeState(is_active=False, current_color=0)

    return ControllerState(
        pads={pad_id: behavior},
        pad_runtime={pad_id: runtime}
    )


# =============================================================================
# Handle Pad Press - Normal Mode
# =============================================================================

class TestHandlePadPressNormal:
    """Test pad press handling in normal mode."""

    def test_unmapped_pad_returns_warning(self, empty_state):
        """Pressing unmapped pad logs warning."""
        new_state, effects = handle_pad_press(empty_state, PadId(0, 0))

        assert new_state == empty_state  # State unchanged
        assert len(effects) == 1
        assert isinstance(effects[0], LogEffect)
        assert effects[0].level == "WARNING"
        assert "not mapped" in effects[0].message

    def test_selector_press_activates_pad(self, state_with_selector):
        """Selector press activates pad and sends OSC."""
        pad_id = PadId(0, 0)
        new_state, effects = handle_pad_press(state_with_selector, pad_id)

        # Check state updated
        runtime = new_state.pad_runtime[pad_id]
        assert runtime.is_active
        assert runtime.current_color == 21  # active_color
        assert runtime.blink_enabled

        # Check effects
        osc_effects = [e for e in effects if isinstance(e, SendOscEffect)]
        led_effects = [e for e in effects if isinstance(e, SetLedEffect)]

        assert len(osc_effects) == 1
        assert osc_effects[0].command.address == "/scenes/Test"
        assert len(led_effects) == 1
        assert led_effects[0].color == 21

    def test_toggle_press_turns_on(self, state_with_toggle):
        """Toggle press turns on from off state."""
        pad_id = PadId(1, 1)
        new_state, effects = handle_pad_press(state_with_toggle, pad_id)

        runtime = new_state.pad_runtime[pad_id]
        assert runtime.is_on
        assert runtime.current_color == 5  # active_color

        osc_effects = [e for e in effects if isinstance(e, SendOscEffect)]
        assert len(osc_effects) == 1
        assert osc_effects[0].command.address == "/toggle/on"

    def test_toggle_press_turns_off(self, state_with_toggle):
        """Toggle press turns off from on state."""
        pad_id = PadId(1, 1)

        # First turn on
        state, _ = handle_pad_press(state_with_toggle, pad_id)
        # Then turn off
        new_state, effects = handle_pad_press(state, pad_id)

        runtime = new_state.pad_runtime[pad_id]
        assert not runtime.is_on
        assert runtime.current_color == 0  # idle_color

        osc_effects = [e for e in effects if isinstance(e, SendOscEffect)]
        assert len(osc_effects) == 1
        assert osc_effects[0].command.address == "/toggle/off"

    def test_one_shot_sends_osc_and_flashes(self, state_with_one_shot):
        """One-shot press sends OSC and flashes LED."""
        pad_id = PadId(2, 2)
        new_state, effects = handle_pad_press(state_with_one_shot, pad_id)

        osc_effects = [e for e in effects if isinstance(e, SendOscEffect)]
        led_effects = [e for e in effects if isinstance(e, SetLedEffect)]

        assert len(osc_effects) == 1
        assert osc_effects[0].command.address == "/playlist/next"
        assert len(led_effects) == 1
        assert led_effects[0].color == 9  # active_color flash


class TestSelectorGroupBehavior:
    """Test selector group (radio button) behavior."""

    def test_selector_deactivates_previous_in_group(self):
        """Pressing new selector in group deactivates previous."""
        # Create state with two selectors in same group
        pad1 = PadId(0, 0)
        pad2 = PadId(1, 0)

        behavior1 = PadBehavior(
            pad_id=pad1, mode=PadMode.SELECTOR, group=PadGroupName.SCENES,
            osc_action=OscCommand("/scenes/A"), active_color=21
        )
        behavior2 = PadBehavior(
            pad_id=pad2, mode=PadMode.SELECTOR, group=PadGroupName.SCENES,
            osc_action=OscCommand("/scenes/B"), active_color=21
        )

        state = ControllerState(
            pads={pad1: behavior1, pad2: behavior2},
            pad_runtime={
                pad1: PadRuntimeState(is_active=True, current_color=21, blink_enabled=True),
                pad2: PadRuntimeState(is_active=False, current_color=0)
            },
            active_selector_by_group={PadGroupName.SCENES: pad1}
        )

        # Press pad2
        new_state, effects = handle_pad_press(state, pad2)

        # pad1 should be deactivated
        assert not new_state.pad_runtime[pad1].is_active
        assert new_state.pad_runtime[pad1].current_color == 0

        # pad2 should be activated
        assert new_state.pad_runtime[pad2].is_active
        assert new_state.pad_runtime[pad2].current_color == 21

        # Active selector updated
        assert new_state.active_selector_by_group[PadGroupName.SCENES] == pad2


# =============================================================================
# Handle Pad Press - Learn Mode
# =============================================================================

class TestHandlePadPressLearnMode:
    """Test pad press handling in learn mode."""

    def test_pad_press_in_learn_wait_selects_pad(self, empty_state):
        """Pressing pad in LEARN_WAIT_PAD selects it for learning."""
        state = replace(empty_state, app_mode=AppMode.LEARN_WAIT_PAD)
        pad_id = PadId(3, 4)

        new_state, effects = handle_pad_press(state, pad_id)

        assert new_state.app_mode == AppMode.LEARN_RECORD_OSC
        assert new_state.learn_state.selected_pad == pad_id
        assert new_state.learn_state.record_start_time is not None

        # Should have LED effect to show recording
        led_effects = [e for e in effects if isinstance(e, SetLedEffect)]
        assert len(led_effects) == 1
        assert led_effects[0].blink  # Blinking during recording

    def test_pad_press_ignored_in_record_mode(self, empty_state):
        """Pressing pad during recording is ignored."""
        state = replace(
            empty_state,
            app_mode=AppMode.LEARN_RECORD_OSC,
            learn_state=LearnState(selected_pad=PadId(0, 0))
        )

        new_state, effects = handle_pad_press(state, PadId(1, 1))

        assert new_state == state  # No change
        assert effects == []


# =============================================================================
# OSC Event Handling
# =============================================================================

class TestHandleOscEvent:
    """Test OSC event handling."""

    def test_beat_pulse_updates_state(self, empty_state):
        """Beat pulse OSC updates state."""
        event = OscEvent(1234.5, "/audio/beat/onbeat", [1])
        new_state, effects = handle_osc_event(empty_state, event)

        assert new_state.beat_pulse is True

    def test_beat_pulse_off(self, empty_state):
        """Beat pulse off updates state."""
        state = replace(empty_state, beat_pulse=True)
        event = OscEvent(1234.5, "/audio/beat/onbeat", [0])
        new_state, effects = handle_osc_event(state, event)

        assert new_state.beat_pulse is False

    def test_scene_updates_active_scene(self, empty_state):
        """Scene OSC updates active scene."""
        event = OscEvent(1234.5, "/scenes/AlienCavern")
        new_state, effects = handle_osc_event(empty_state, event)

        assert new_state.active_scene == "AlienCavern"

    def test_preset_updates_active_preset(self, empty_state):
        """Preset OSC updates active preset."""
        event = OscEvent(1234.5, "/presets/CoolPreset")
        new_state, effects = handle_osc_event(empty_state, event)

        assert new_state.active_preset == "CoolPreset"

    def test_osc_recorded_during_learn_mode(self, empty_state):
        """OSC events are recorded during LEARN_RECORD_OSC mode."""
        state = replace(
            empty_state,
            app_mode=AppMode.LEARN_RECORD_OSC,
            learn_state=LearnState(selected_pad=PadId(0, 0))
        )

        event = OscEvent(1234.5, "/scenes/Test")
        new_state, effects = handle_osc_event(state, event)

        assert len(new_state.learn_state.recorded_osc_events) == 1
        assert new_state.learn_state.recorded_osc_events[0].address == "/scenes/Test"

    def test_non_controllable_osc_not_recorded(self, empty_state):
        """Non-controllable OSC is not recorded."""
        state = replace(
            empty_state,
            app_mode=AppMode.LEARN_RECORD_OSC,
            learn_state=LearnState(selected_pad=PadId(0, 0))
        )

        event = OscEvent(1234.5, "/audio/beat/onbeat", [1])
        new_state, effects = handle_osc_event(state, event)

        assert len(new_state.learn_state.recorded_osc_events) == 0

    def test_first_controllable_osc_starts_timer(self, empty_state):
        """First controllable OSC message starts recording timer."""
        state = replace(
            empty_state,
            app_mode=AppMode.LEARN_RECORD_OSC,
            learn_state=LearnState(selected_pad=PadId(0, 0), record_start_time=None)
        )

        event = OscEvent(1234.5, "/scenes/Test")
        new_state, effects = handle_osc_event(state, event)

        assert new_state.learn_state.record_start_time == 1234.5


class TestActivateMatchingSelector:
    """Test automatic selector activation from OSC."""

    def test_matching_selector_activated(self):
        """Selector matching OSC address is activated."""
        pad_id = PadId(0, 0)
        behavior = PadBehavior(
            pad_id=pad_id, mode=PadMode.SELECTOR, group=PadGroupName.SCENES,
            osc_action=OscCommand("/scenes/Test"), active_color=21
        )

        state = ControllerState(
            pads={pad_id: behavior},
            pad_runtime={pad_id: PadRuntimeState()}
        )

        cmd = OscCommand("/scenes/Test")
        new_state, effects = _activate_matching_selector(state, cmd, PadGroupName.SCENES)

        assert new_state.pad_runtime[pad_id].is_active
        assert new_state.active_selector_by_group[PadGroupName.SCENES] == pad_id


# =============================================================================
# Learn Mode FSM Transitions
# =============================================================================

class TestLearnModeFSM:
    """Test learn mode state machine transitions."""

    def test_enter_learn_mode(self, empty_state):
        """Entering learn mode transitions to LEARN_WAIT_PAD."""
        new_state, effects = enter_learn_mode(empty_state)

        assert new_state.app_mode == AppMode.LEARN_WAIT_PAD
        assert new_state.learn_state.selected_pad is None

        log_effects = [e for e in effects if isinstance(e, LogEffect)]
        assert len(log_effects) == 1

    def test_enter_learn_mode_when_already_in_learn(self, empty_state):
        """Cannot enter learn mode when already in learn mode."""
        state = replace(empty_state, app_mode=AppMode.LEARN_WAIT_PAD)
        new_state, effects = enter_learn_mode(state)

        assert new_state == state  # No change
        log_effects = [e for e in effects if isinstance(e, LogEffect)]
        assert log_effects[0].level == "WARNING"

    def test_cancel_learn_mode(self, empty_state):
        """Cancelling learn mode returns to NORMAL."""
        state = replace(
            empty_state,
            app_mode=AppMode.LEARN_RECORD_OSC,
            learn_state=LearnState(selected_pad=PadId(0, 0))
        )

        new_state, effects = cancel_learn_mode(state)

        assert new_state.app_mode == AppMode.NORMAL
        assert new_state.learn_state.selected_pad is None

    def test_cancel_normal_mode_no_effect(self, empty_state):
        """Cancelling when already in normal mode has no effect."""
        new_state, effects = cancel_learn_mode(empty_state)

        assert new_state == empty_state
        assert effects == []

    def test_finish_osc_recording(self, empty_state):
        """Finishing recording transitions to LEARN_SELECT_MSG."""
        events = [
            OscEvent(1.0, "/scenes/A"),
            OscEvent(2.0, "/scenes/B"),
            OscEvent(3.0, "/scenes/A"),  # Duplicate
            OscEvent(4.0, "/audio/beat", [1])  # Not controllable
        ]

        state = replace(
            empty_state,
            app_mode=AppMode.LEARN_RECORD_OSC,
            learn_state=LearnState(
                selected_pad=PadId(0, 0),
                recorded_osc_events=events
            )
        )

        new_state, effects = finish_osc_recording(state)

        assert new_state.app_mode == AppMode.LEARN_SELECT_MSG
        # Should have 2 unique controllable commands
        assert len(new_state.learn_state.candidate_commands) == 2

    def test_select_learn_command(self, empty_state):
        """Selecting command completes learn mode."""
        candidates = [
            OscCommand("/scenes/Test"),
            OscCommand("/presets/Cool")
        ]

        state = replace(
            empty_state,
            app_mode=AppMode.LEARN_SELECT_MSG,
            learn_state=LearnState(
                selected_pad=PadId(0, 0),
                candidate_commands=candidates
            )
        )

        new_state, effects = select_learn_command(
            state,
            command_index=0,
            pad_mode=PadMode.SELECTOR,
            group=PadGroupName.SCENES,
            idle_color=0,
            active_color=21,
            label="My Scene"
        )

        assert new_state.app_mode == AppMode.NORMAL
        assert PadId(0, 0) in new_state.pads
        assert new_state.pads[PadId(0, 0)].osc_action.address == "/scenes/Test"

        # Should save config
        save_effects = [e for e in effects if isinstance(e, SaveConfigEffect)]
        assert len(save_effects) == 1

    def test_select_invalid_command_index(self, empty_state):
        """Selecting invalid index returns error."""
        state = replace(
            empty_state,
            app_mode=AppMode.LEARN_SELECT_MSG,
            learn_state=LearnState(
                selected_pad=PadId(0, 0),
                candidate_commands=[OscCommand("/test")]
            )
        )

        new_state, effects = select_learn_command(
            state, command_index=99, pad_mode=PadMode.ONE_SHOT,
            group=None, idle_color=0, active_color=5
        )

        assert new_state == state  # No change
        log_effects = [e for e in effects if isinstance(e, LogEffect)]
        assert log_effects[0].level == "ERROR"


# =============================================================================
# Pure Function Properties
# =============================================================================

class TestPureFunctions:
    """Test that FSM functions are pure (no side effects)."""

    def test_handle_pad_press_is_pure(self, state_with_selector):
        """handle_pad_press doesn't mutate input state."""
        original_mode = state_with_selector.app_mode
        original_pads = dict(state_with_selector.pads)

        handle_pad_press(state_with_selector, PadId(0, 0))

        assert state_with_selector.app_mode == original_mode
        assert state_with_selector.pads == original_pads

    def test_handle_osc_event_is_pure(self, empty_state):
        """handle_osc_event doesn't mutate input state."""
        original_scene = empty_state.active_scene

        handle_osc_event(empty_state, OscEvent(1.0, "/scenes/Test"))

        assert empty_state.active_scene == original_scene

    def test_enter_learn_mode_is_pure(self, empty_state):
        """enter_learn_mode doesn't mutate input state."""
        original_mode = empty_state.app_mode

        enter_learn_mode(empty_state)

        assert empty_state.app_mode == original_mode

    def test_same_input_same_output(self, state_with_selector):
        """Same input always produces same output."""
        pad_id = PadId(0, 0)

        result1 = handle_pad_press(state_with_selector, pad_id)
        result2 = handle_pad_press(state_with_selector, pad_id)

        # States should be equal (ignoring timestamp in learn mode)
        assert result1[0].pads == result2[0].pads
        assert result1[0].pad_runtime == result2[0].pad_runtime
