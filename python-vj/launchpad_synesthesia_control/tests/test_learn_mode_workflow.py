"""
High-level tests for Learn Mode workflow.

Tests the complete learn mode flow from entering to saving configuration,
including FSM state transitions, modal interactions, and edge cases.
"""

import pytest
from unittest.mock import Mock, AsyncMock, patch
from dataclasses import replace

from launchpad_synesthesia_control.app.domain.model import (
    ControllerState, PadId, AppMode, LearnState, OscEvent, OscCommand,
    PadMode, PadGroupName, PadBehavior
)
from launchpad_synesthesia_control.app.domain.fsm import (
    enter_learn_mode, cancel_learn_mode, handle_pad_press,
    handle_osc_event, finish_osc_recording, select_learn_command
)


class TestLearnModeBasicFlow:
    """Test the basic learn mode state transitions."""

    def test_enter_learn_mode_transitions_to_wait_pad(self):
        """Pressing L should transition NORMAL → LEARN_WAIT_PAD."""
        state = ControllerState()
        assert state.app_mode == AppMode.NORMAL

        new_state, effects = enter_learn_mode(state)

        assert new_state.app_mode == AppMode.LEARN_WAIT_PAD
        assert len(effects) == 1
        assert "Learn mode" in effects[0].message

    def test_cancel_learn_mode_returns_to_normal(self):
        """ESC during learn mode should return to NORMAL."""
        state = ControllerState()
        state = replace(state, app_mode=AppMode.LEARN_WAIT_PAD)

        new_state, effects = cancel_learn_mode(state)

        assert new_state.app_mode == AppMode.NORMAL
        assert any("cancelled" in e.message.lower() for e in effects)

    def test_pad_press_in_learn_mode_selects_pad(self):
        """Clicking a pad in LEARN_WAIT_PAD should select it."""
        state = ControllerState()
        state = replace(state, app_mode=AppMode.LEARN_WAIT_PAD)
        pad_id = PadId(2, 3)

        new_state, effects = handle_pad_press(state, pad_id)

        assert new_state.app_mode == AppMode.LEARN_RECORD_OSC
        assert new_state.learn_state.selected_pad == pad_id

    def test_osc_recording_captures_controllable_messages(self):
        """OSC messages should be recorded during LEARN_RECORD_OSC."""
        pad_id = PadId(2, 3)
        state = ControllerState()
        state = replace(
            state,
            app_mode=AppMode.LEARN_RECORD_OSC,
            learn_state=LearnState(selected_pad=pad_id)
        )

        # Send a controllable OSC message
        event = OscEvent(
            timestamp=0.0,
            address="/scenes/AlienCavern",
            args=[]
        )

        new_state, effects = handle_osc_event(state, event)

        assert len(new_state.learn_state.recorded_osc_events) == 1
        assert new_state.learn_state.recorded_osc_events[0].address == "/scenes/AlienCavern"

    def test_finish_recording_creates_candidate_commands(self):
        """After 5s, recorded OSC should become candidate commands."""
        pad_id = PadId(2, 3)
        events = [
            OscEvent(0.0, "/scenes/Scene1", []),
            OscEvent(1.0, "/scenes/Scene2", []),
            OscEvent(2.0, "/presets/Preset1", []),
        ]
        state = ControllerState()
        state = replace(
            state,
            app_mode=AppMode.LEARN_RECORD_OSC,
            learn_state=LearnState(
                selected_pad=pad_id,
                recorded_osc_events=events
            )
        )

        new_state, effects = finish_osc_recording(state)

        assert new_state.app_mode == AppMode.LEARN_SELECT_MSG
        assert len(new_state.learn_state.candidate_commands) == 3
        assert new_state.learn_state.candidate_commands[0].address == "/scenes/Scene1"


class TestLearnModeEdgeCases:
    """Test edge cases and error handling."""

    def test_no_osc_messages_captured(self):
        """If no OSC messages are captured, should handle gracefully."""
        state = ControllerState()
        state = replace(
            state,
            app_mode=AppMode.LEARN_RECORD_OSC,
            learn_state=LearnState(
                selected_pad=PadId(0, 0),
                recorded_osc_events=[]
            )
        )

        new_state, effects = finish_osc_recording(state)

        # Should transition but have no candidates
        assert new_state.app_mode == AppMode.LEARN_SELECT_MSG
        assert len(new_state.learn_state.candidate_commands) == 0

    def test_pad_already_configured_can_be_overwritten(self):
        """Selecting a configured pad should work (overwrite warning given by UI)."""
        pad_id = PadId(2, 3)
        existing_behavior = PadBehavior(
            pad_id=pad_id,
            mode=PadMode.SELECTOR,
            group=PadGroupName.SCENES,
            idle_color=3,
            active_color=21,
            label="Old Scene",
            osc_action=OscCommand("/scenes/OldScene", [])
        )
        state = ControllerState()
        state = replace(
            state,
            pads={pad_id: existing_behavior},
            app_mode=AppMode.LEARN_WAIT_PAD
        )

        # Should still allow selection
        new_state, effects = handle_pad_press(state, pad_id)

        assert new_state.app_mode == AppMode.LEARN_RECORD_OSC
        assert new_state.learn_state.selected_pad == pad_id

    def test_non_controllable_osc_filtered_out(self):
        """Non-controllable OSC messages (like /audio/beat) should be filtered."""
        state = ControllerState()
        state = replace(
            state,
            app_mode=AppMode.LEARN_RECORD_OSC,
            learn_state=LearnState(selected_pad=PadId(0, 0))
        )

        # Send non-controllable messages
        beat_event = OscEvent(0.0, "/audio/beat/onbeat", [1])
        bpm_event = OscEvent(0.5, "/audio/bpm", [120])
        scene_event = OscEvent(1.0, "/scenes/Test", [])

        state, _ = handle_osc_event(state, beat_event)
        state, _ = handle_osc_event(state, bpm_event)
        state, _ = handle_osc_event(state, scene_event)

        # Only the scene event should be recorded
        new_state, _ = finish_osc_recording(state)
        assert len(new_state.learn_state.candidate_commands) == 1
        assert new_state.learn_state.candidate_commands[0].address == "/scenes/Test"


class TestLearnModeCompleteWorkflow:
    """Test complete end-to-end workflows."""

    def test_complete_selector_pad_configuration(self):
        """Test full workflow for configuring a SELECTOR pad."""
        # Step 1: Enter learn mode
        state = ControllerState()
        state, _ = enter_learn_mode(state)
        assert state.app_mode == AppMode.LEARN_WAIT_PAD

        # Step 2: Select pad
        pad_id = PadId(2, 3)
        state, _ = handle_pad_press(state, pad_id)
        assert state.app_mode == AppMode.LEARN_RECORD_OSC

        # Step 3: Record OSC
        event = OscEvent(0.0, "/scenes/AlienCavern", [])
        state, _ = handle_osc_event(state, event)

        # Step 4: Finish recording
        state, _ = finish_osc_recording(state)
        assert state.app_mode == AppMode.LEARN_SELECT_MSG
        assert len(state.learn_state.candidate_commands) == 1

        # Step 5: Select command and configure
        state, effects = select_learn_command(
            state,
            command_index=0,
            pad_mode=PadMode.SELECTOR,
            group=PadGroupName.SCENES,
            idle_color=3,
            active_color=21,
            label="Alien Cavern"
        )

        # Verify final state
        assert state.app_mode == AppMode.NORMAL
        assert pad_id in state.pads
        behavior = state.pads[pad_id]
        assert behavior.mode == PadMode.SELECTOR
        assert behavior.group == PadGroupName.SCENES
        assert behavior.label == "Alien Cavern"
        assert behavior.osc_action.address == "/scenes/AlienCavern"

        # Verify effects include save
        assert any(e.__class__.__name__ == "SaveConfigEffect" for e in effects)

    def test_complete_toggle_pad_configuration(self):
        """Test full workflow for configuring a TOGGLE pad."""
        state = ControllerState()
        state, _ = enter_learn_mode(state)

        pad_id = PadId(0, 7)
        state, _ = handle_pad_press(state, pad_id)

        # Record ON command (use controllable address)
        event = OscEvent(0.0, "/controls/meta/strobe", [1.0])
        state, _ = handle_osc_event(state, event)

        state, _ = finish_osc_recording(state)

        # Configure as toggle
        state, effects = select_learn_command(
            state,
            command_index=0,
            pad_mode=PadMode.TOGGLE,
            group=None,
            idle_color=5,  # Red for OFF
            active_color=21,  # Green for ON
            label="Strobe"
        )

        assert state.app_mode == AppMode.NORMAL
        assert pad_id in state.pads
        behavior = state.pads[pad_id]
        assert behavior.mode == PadMode.TOGGLE
        assert behavior.osc_on.address == "/controls/meta/strobe"

    def test_complete_oneshot_pad_configuration(self):
        """Test full workflow for configuring a ONE_SHOT pad."""
        state = ControllerState()
        state, _ = enter_learn_mode(state)

        pad_id = PadId(1, 7)
        state, _ = handle_pad_press(state, pad_id)

        event = OscEvent(0.0, "/playlist/next", [])
        state, _ = handle_osc_event(state, event)

        state, _ = finish_osc_recording(state)

        state, effects = select_learn_command(
            state,
            command_index=0,
            pad_mode=PadMode.ONE_SHOT,
            group=None,
            idle_color=45,
            active_color=3,
            label="Next"
        )

        assert state.app_mode == AppMode.NORMAL
        behavior = state.pads[pad_id]
        assert behavior.mode == PadMode.ONE_SHOT
        assert behavior.osc_action.address == "/playlist/next"

    def test_cancel_during_recording(self):
        """Test canceling learn mode during OSC recording."""
        state = ControllerState()
        state, _ = enter_learn_mode(state)
        pad_id = PadId(0, 0)
        state, _ = handle_pad_press(state, pad_id)

        # In recording mode
        assert state.app_mode == AppMode.LEARN_RECORD_OSC

        # User cancels
        state, _ = cancel_learn_mode(state)

        assert state.app_mode == AppMode.NORMAL
        assert state.learn_state.selected_pad is None

    def test_multiple_commands_selection(self):
        """Test selecting one command when multiple are captured."""
        state = ControllerState()
        state, _ = enter_learn_mode(state)

        pad_id = PadId(4, 4)
        state, _ = handle_pad_press(state, pad_id)

        # Capture multiple commands
        events = [
            OscEvent(0.0, "/scenes/Scene1", []),
            OscEvent(1.0, "/scenes/Scene2", []),
            OscEvent(2.0, "/presets/Preset1", []),
        ]
        for event in events:
            state, _ = handle_osc_event(state, event)

        state, _ = finish_osc_recording(state)

        # User selects the second command (Scene2)
        state, _ = select_learn_command(
            state,
            command_index=1,
            pad_mode=PadMode.SELECTOR,
            group=PadGroupName.SCENES,
            idle_color=3,
            active_color=21,
            label="Scene 2"
        )

        behavior = state.pads[pad_id]
        assert behavior.osc_action.address == "/scenes/Scene2"


class TestLearnModeValidation:
    """Test validation and error conditions."""

    def test_invalid_command_index(self):
        """Selecting an out-of-range command index should fail gracefully."""
        state = ControllerState()
        state = replace(
            state,
            app_mode=AppMode.LEARN_SELECT_MSG,
            learn_state=LearnState(
                selected_pad=PadId(0, 0),
                candidate_commands=[OscCommand("/test", [])]
            )
        )

        state, effects = select_learn_command(
            state,
            command_index=99,  # Out of range
            pad_mode=PadMode.SELECTOR,
            group=PadGroupName.SCENES,
            idle_color=3,
            active_color=21,
            label="Test"
        )

        # Should fail and log error
        assert any("Invalid command index" in e.message for e in effects if hasattr(e, "message"))
        assert state.app_mode == AppMode.LEARN_SELECT_MSG  # Didn't change

    def test_selector_mode_requires_group(self):
        """SELECTOR mode without a group should fail."""
        state = ControllerState()
        state = replace(
            state,
            app_mode=AppMode.LEARN_SELECT_MSG,
            learn_state=LearnState(
                selected_pad=PadId(0, 0),
                candidate_commands=[OscCommand("/scenes/Test", [])]
            )
        )

        state, effects = select_learn_command(
            state,
            command_index=0,
            pad_mode=PadMode.SELECTOR,
            group=None,  # Missing group!
            idle_color=3,
            active_color=21,
            label="Test"
        )

        # Should fail validation
        assert any("requires group" in e.message.lower() for e in effects if hasattr(e, "message"))

    def test_deduplication_of_osc_messages(self):
        """Duplicate OSC messages should be deduplicated."""
        state = ControllerState()
        state = replace(
            state,
            app_mode=AppMode.LEARN_RECORD_OSC,
            learn_state=LearnState(selected_pad=PadId(0, 0))
        )

        # Send same command multiple times
        for _ in range(5):
            event = OscEvent(0.0, "/scenes/Same", [])
            state, _ = handle_osc_event(state, event)

        state, _ = finish_osc_recording(state)

        # Should only have one candidate
        assert len(state.learn_state.candidate_commands) == 1


class TestLearnModeTimerIntegration:
    """Test timer-related functionality (requires mocking time)."""

    def test_timer_starts_on_first_controllable_message(self):
        """Timer should start when first controllable OSC is received."""
        state = ControllerState()
        state = replace(
            state,
            app_mode=AppMode.LEARN_RECORD_OSC,
            learn_state=LearnState(
                selected_pad=PadId(0, 0),
                record_start_time=None  # Timer not started
            )
        )

        # Send non-controllable first
        beat_event = OscEvent(0.0, "/audio/beat/onbeat", [1])
        state, _ = handle_osc_event(state, beat_event)
        assert state.learn_state.record_start_time is None

        # Send controllable - timer should start
        scene_event = OscEvent(1.0, "/scenes/Test", [])
        state, effects = handle_osc_event(state, scene_event)

        assert state.learn_state.record_start_time == 1.0
        assert any("First controllable message" in e.message for e in effects if hasattr(e, "message"))


class TestMultiplePadLearning:
    """Test learning multiple pads sequentially."""

    def test_can_learn_second_pad_after_completing_first(self):
        """
        Bug regression test: After learning one pad successfully,
        should be able to learn another pad without issues.
        """
        state = ControllerState()
        
        # --- FIRST PAD ---
        # Step 1: Enter learn mode
        state, _ = enter_learn_mode(state)
        assert state.app_mode == AppMode.LEARN_WAIT_PAD
        
        # Step 2: Select first pad
        pad1 = PadId(0, 0)
        state, _ = handle_pad_press(state, pad1)
        assert state.app_mode == AppMode.LEARN_RECORD_OSC
        assert state.learn_state.selected_pad == pad1
        
        # Step 3: Record OSC
        state, _ = handle_osc_event(state, OscEvent(0.0, "/scenes/Scene1", []))
        
        # Step 4: Finish recording
        state, _ = finish_osc_recording(state)
        
        # Step 5: Complete configuration
        state, _ = select_learn_command(
            state, command_index=0, pad_mode=PadMode.SELECTOR,
            group=PadGroupName.SCENES, idle_color=3, active_color=21, label="Scene1"
        )
        
        # VERIFY: Back to NORMAL mode
        assert state.app_mode == AppMode.NORMAL
        assert pad1 in state.pads
        
        # --- SECOND PAD ---
        # Step 1: Enter learn mode AGAIN
        state, effects = enter_learn_mode(state)
        assert state.app_mode == AppMode.LEARN_WAIT_PAD
        # Should NOT have warning about "already in learn mode"
        assert not any("Already" in str(getattr(e, 'message', '')) for e in effects)
        
        # Step 2: Select second pad
        pad2 = PadId(1, 0)
        state, _ = handle_pad_press(state, pad2)
        assert state.app_mode == AppMode.LEARN_RECORD_OSC
        assert state.learn_state.selected_pad == pad2
        
        # Step 3: Record different OSC
        state, _ = handle_osc_event(state, OscEvent(0.0, "/scenes/Scene2", []))
        
        # Step 4: Finish recording
        state, _ = finish_osc_recording(state)
        
        # Step 5: Complete configuration
        state, _ = select_learn_command(
            state, command_index=0, pad_mode=PadMode.SELECTOR,
            group=PadGroupName.SCENES, idle_color=3, active_color=45, label="Scene2"
        )
        
        # VERIFY: Both pads configured
        assert state.app_mode == AppMode.NORMAL
        assert pad1 in state.pads
        assert pad2 in state.pads
        assert state.pads[pad1].label == "Scene1"
        assert state.pads[pad2].label == "Scene2"


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
