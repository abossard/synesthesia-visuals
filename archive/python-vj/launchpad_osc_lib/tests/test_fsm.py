"""
Tests for FSM (Finite State Machine) logic.

These tests verify state transitions are correct and pure.
"""

import pytest
from dataclasses import replace

from launchpad_osc_lib import (
    ButtonId, PadMode, ButtonGroupType, PadBehavior, PadRuntimeState,
    OscCommand, LearnPhase, LearnState, ControllerState,
    SendOscEffect, SetLedEffect, SaveConfigEffect, LogEffect,
    handle_pad_press, handle_pad_release, handle_osc_event,
    enter_learn_mode, cancel_learn_mode,
)
from launchpad_osc_lib.model import OscEvent
from launchpad_osc_lib.fsm import finish_recording, select_pad, record_osc_event


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
    pad_id = ButtonId(0, 0)
    behavior = PadBehavior(
        pad_id=pad_id,
        mode=PadMode.SELECTOR,
        group=ButtonGroupType.SCENES,
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
    pad_id = ButtonId(1, 1)
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
    pad_id = ButtonId(2, 2)
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

    def test_unmapped_pad_returns_no_error(self, empty_state):
        """Pressing unmapped pad in idle mode has no effect."""
        new_state, effects = handle_pad_press(empty_state, ButtonId(0, 0))
        # In idle mode with no pads, pressing does nothing
        assert len(effects) == 0

    def test_selector_press_activates_pad(self, state_with_selector):
        """Selector press activates pad and sends OSC."""
        pad_id = ButtonId(0, 0)
        new_state, effects = handle_pad_press(state_with_selector, pad_id)

        # Check state updated
        runtime = new_state.pad_runtime[pad_id]
        assert runtime.is_active
        assert runtime.current_color == 21  # active_color

        # Check effects
        osc_effects = [e for e in effects if isinstance(e, SendOscEffect)]
        led_effects = [e for e in effects if isinstance(e, SetLedEffect)]

        assert len(osc_effects) == 1
        assert osc_effects[0].command.address == "/scenes/Test"
        assert len(led_effects) >= 1

    def test_toggle_press_turns_on(self, state_with_toggle):
        """Toggle press turns on from off state."""
        pad_id = ButtonId(1, 1)
        new_state, effects = handle_pad_press(state_with_toggle, pad_id)

        runtime = new_state.pad_runtime[pad_id]
        assert runtime.is_on
        assert runtime.current_color == 5  # active_color

        osc_effects = [e for e in effects if isinstance(e, SendOscEffect)]
        assert len(osc_effects) == 1
        assert osc_effects[0].command.address == "/toggle/on"

    def test_toggle_press_turns_off(self, state_with_toggle):
        """Toggle press turns off from on state."""
        pad_id = ButtonId(1, 1)

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
        pad_id = ButtonId(2, 2)
        new_state, effects = handle_pad_press(state_with_one_shot, pad_id)

        osc_effects = [e for e in effects if isinstance(e, SendOscEffect)]
        led_effects = [e for e in effects if isinstance(e, SetLedEffect)]

        assert len(osc_effects) == 1
        assert osc_effects[0].command.address == "/playlist/next"
        assert len(led_effects) >= 1


class TestSelectorGroupBehavior:
    """Test selector group (radio button) behavior."""

    def test_selector_deactivates_previous_in_group(self):
        """Pressing new selector in group deactivates previous."""
        # Create state with two selectors in same group
        pad1 = ButtonId(0, 0)
        pad2 = ButtonId(1, 0)

        behavior1 = PadBehavior(
            pad_id=pad1, mode=PadMode.SELECTOR, group=ButtonGroupType.SCENES,
            osc_action=OscCommand("/scenes/A"), active_color=21
        )
        behavior2 = PadBehavior(
            pad_id=pad2, mode=PadMode.SELECTOR, group=ButtonGroupType.SCENES,
            osc_action=OscCommand("/scenes/B"), active_color=21
        )

        state = ControllerState(
            pads={pad1: behavior1, pad2: behavior2},
            pad_runtime={
                pad1: PadRuntimeState(is_active=True, current_color=21, blink_enabled=True),
                pad2: PadRuntimeState(is_active=False, current_color=0)
            },
            active_selector_by_group={ButtonGroupType.SCENES: pad1}
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
        assert new_state.active_selector_by_group[ButtonGroupType.SCENES] == pad2


# =============================================================================
# Handle Pad Press - Learn Mode
# =============================================================================

class TestHandlePadPressLearnMode:
    """Test pad press handling in learn mode."""

    def test_pad_press_in_learn_wait_selects_pad(self, empty_state):
        """Pressing pad in WAIT_PAD selects it for learning."""
        state = replace(
            empty_state,
            learn_state=LearnState(phase=LearnPhase.WAIT_PAD)
        )
        pad_id = ButtonId(3, 4)

        new_state, effects = handle_pad_press(state, pad_id)

        assert new_state.learn_state.phase == LearnPhase.RECORD_OSC
        assert new_state.learn_state.selected_pad == pad_id

    def test_pad_press_ignored_in_record_mode(self, empty_state):
        """Pressing pad during recording uses select_pad."""
        state = replace(
            empty_state,
            learn_state=LearnState(
                phase=LearnPhase.RECORD_OSC,
                selected_pad=ButtonId(0, 0)
            )
        )

        # In record mode, another pad press should be ignored
        new_state, effects = handle_pad_press(state, ButtonId(1, 1))

        # State should be unchanged (ignores presses during recording)
        assert new_state.learn_state.selected_pad == ButtonId(0, 0)


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
        """OSC events are recorded during RECORD_OSC phase."""
        state = replace(
            empty_state,
            learn_state=LearnState(
                phase=LearnPhase.RECORD_OSC,
                selected_pad=ButtonId(0, 0)
            )
        )

        event = OscEvent(1234.5, "/scenes/Test")
        new_state, effects = record_osc_event(state, event)

        assert len(new_state.learn_state.recorded_events) == 1
        assert new_state.learn_state.recorded_events[0].address == "/scenes/Test"

    def test_non_controllable_osc_not_recorded(self, empty_state):
        """Non-controllable OSC is not recorded."""
        state = replace(
            empty_state,
            learn_state=LearnState(
                phase=LearnPhase.RECORD_OSC,
                selected_pad=ButtonId(0, 0)
            )
        )

        event = OscEvent(1234.5, "/audio/beat/onbeat", [1])
        new_state, effects = record_osc_event(state, event)

        assert len(new_state.learn_state.recorded_events) == 0


class TestActivateMatchingSelector:
    """Test automatic selector activation from OSC."""

    def test_matching_selector_activated(self):
        """Selector matching OSC address is activated via handle_osc_event."""
        pad_id = ButtonId(0, 0)
        behavior = PadBehavior(
            pad_id=pad_id, mode=PadMode.SELECTOR, group=ButtonGroupType.SCENES,
            osc_action=OscCommand("/scenes/Test"), active_color=21
        )

        state = ControllerState(
            pads={pad_id: behavior},
            pad_runtime={pad_id: PadRuntimeState()}
        )

        # Use public API - handle_osc_event will activate matching selector
        event = OscEvent(1234.5, "/scenes/Test")
        new_state, effects = handle_osc_event(state, event)

        assert new_state.pad_runtime[pad_id].is_active
        assert new_state.active_selector_by_group[ButtonGroupType.SCENES] == pad_id


# =============================================================================
# Learn Mode FSM Transitions
# =============================================================================

class TestLearnModeFSM:
    """Test learn mode state machine transitions."""

    def test_enter_learn_mode(self, empty_state):
        """Entering learn mode transitions to WAIT_PAD."""
        new_state, effects = enter_learn_mode(empty_state)

        assert new_state.learn_state.phase == LearnPhase.WAIT_PAD
        assert new_state.learn_state.selected_pad is None

        log_effects = [e for e in effects if isinstance(e, LogEffect)]
        assert len(log_effects) == 1

    def test_enter_learn_mode_from_idle(self, empty_state):
        """Enter learn mode from IDLE state."""
        assert empty_state.learn_state.phase == LearnPhase.IDLE
        new_state, effects = enter_learn_mode(empty_state)

        assert new_state.learn_state.phase == LearnPhase.WAIT_PAD

    def test_cancel_learn_mode(self, empty_state):
        """Cancelling learn mode returns to IDLE."""
        state = replace(
            empty_state,
            learn_state=LearnState(
                phase=LearnPhase.RECORD_OSC,
                selected_pad=ButtonId(0, 0)
            )
        )

        new_state, effects = cancel_learn_mode(state)

        assert new_state.learn_state.phase == LearnPhase.IDLE
        assert new_state.learn_state.selected_pad is None

    def test_finish_osc_recording(self, empty_state):
        """Finishing recording transitions to CONFIG."""
        events = [
            OscEvent(1.0, "/scenes/A", priority=1),
            OscEvent(2.0, "/scenes/B", priority=1),
            OscEvent(3.0, "/scenes/A", priority=1),  # Duplicate
        ]

        state = replace(
            empty_state,
            learn_state=LearnState(
                phase=LearnPhase.RECORD_OSC,
                selected_pad=ButtonId(0, 0),
                recorded_events=events
            )
        )

        new_state, effects = finish_recording(state)

        assert new_state.learn_state.phase == LearnPhase.CONFIG
        # Should have 2 unique controllable commands
        assert len(new_state.learn_state.candidate_commands) == 2


# =============================================================================
# Pure Function Properties
# =============================================================================

class TestPureFunctions:
    """Test that FSM functions are pure (no side effects)."""

    def test_handle_pad_press_is_pure(self, state_with_selector):
        """handle_pad_press doesn't mutate input state."""
        original_phase = state_with_selector.learn_state.phase
        original_pads = dict(state_with_selector.pads)

        handle_pad_press(state_with_selector, ButtonId(0, 0))

        assert state_with_selector.learn_state.phase == original_phase
        assert state_with_selector.pads == original_pads

    def test_handle_osc_event_is_pure(self, empty_state):
        """handle_osc_event doesn't mutate input state."""
        original_scene = empty_state.active_scene

        handle_osc_event(empty_state, OscEvent(1.0, "/scenes/Test"))

        assert empty_state.active_scene == original_scene

    def test_enter_learn_mode_is_pure(self, empty_state):
        """enter_learn_mode doesn't mutate input state."""
        original_phase = empty_state.learn_state.phase

        enter_learn_mode(empty_state)

        assert empty_state.learn_state.phase == original_phase

    def test_same_input_same_output(self, state_with_selector):
        """Same input always produces same output."""
        pad_id = ButtonId(0, 0)

        result1 = handle_pad_press(state_with_selector, pad_id)
        result2 = handle_pad_press(state_with_selector, pad_id)

        # States should be equal (ignoring timestamp in learn mode)
        assert result1[0].pads == result2[0].pads
        assert result1[0].pad_runtime == result2[0].pad_runtime
