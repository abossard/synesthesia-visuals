"""
Integration tests for Learn Mode UI flow in the TUI.

Tests the interaction between the timer loop, modal display,
and state transitions in the actual Textual app.
"""

import pytest
from unittest.mock import Mock, AsyncMock, patch, MagicMock
from dataclasses import replace

from launchpad_osc_lib import (
    ControllerState, PadId, AppMode, LearnState, OscCommand,
    PadMode, PadGroupName
)


class TestLearnModeModalIntegration:
    """Test modal display and interaction."""

    @pytest.mark.asyncio
    async def test_modal_shown_on_learn_select_msg_transition(self):
        """Modal should appear when transitioning to LEARN_SELECT_MSG."""
        from launchpad_synesthesia_control.app.ui.tui import LaunchpadSynesthesiaApp

        with patch('launchpad_synesthesia_control.app.ui.tui.SmartLaunchpad') as mock_lp, \
             patch('launchpad_synesthesia_control.app.ui.tui.SynesthesiaOscManager') as mock_osc:

            # Mock devices to avoid connection attempts
            mock_lp.return_value.connect = AsyncMock(return_value=False)
            mock_lp.return_value.is_connected.return_value = False
            mock_osc.return_value.connect = AsyncMock(return_value=False)
            mock_osc.return_value.is_connected.return_value = False

            app = LaunchpadSynesthesiaApp()

            # Set up state with candidate commands
            app.state = replace(
                app.state,
                app_mode=AppMode.LEARN_SELECT_MSG,
                learn_state=LearnState(
                    selected_pad=PadId(2, 3),
                    candidate_commands=[
                        OscCommand("/scenes/Test", [])
                    ]
                )
            )

            # Mock push_screen_wait to simulate user confirming
            result = {
                "command": OscCommand("/scenes/Test", []),
                "mode": PadMode.SELECTOR,
                "group": PadGroupName.SCENES,
                "idle_color": 3,
                "active_color": 21,
                "label": "Test Scene"
            }
            app.push_screen_wait = AsyncMock(return_value=result)

            # Call the modal method directly
            await app._show_command_selection_modal()

            # Verify modal was shown
            app.push_screen_wait.assert_called_once()

            # Verify configuration was saved
            assert PadId(2, 3) in app.state.pads
            assert app.state.app_mode == AppMode.NORMAL

    @pytest.mark.asyncio
    async def test_modal_handles_user_cancellation(self):
        """Modal cancellation should return to NORMAL mode."""
        from launchpad_synesthesia_control.app.ui.tui import LaunchpadSynesthesiaApp

        with patch('launchpad_synesthesia_control.app.ui.tui.SmartLaunchpad') as mock_lp, \
             patch('launchpad_synesthesia_control.app.ui.tui.SynesthesiaOscManager') as mock_osc:

            mock_lp.return_value.connect = AsyncMock(return_value=False)
            mock_lp.return_value.is_connected.return_value = False
            mock_osc.return_value.connect = AsyncMock(return_value=False)
            mock_osc.return_value.is_connected.return_value = False

            app = LaunchpadSynesthesiaApp()

            app.state = replace(
                app.state,
                app_mode=AppMode.LEARN_SELECT_MSG,
                learn_state=LearnState(
                    selected_pad=PadId(2, 3),
                    candidate_commands=[OscCommand("/scenes/Test", [])]
                )
            )

            # User cancels (returns None)
            app.push_screen_wait = AsyncMock(return_value=None)

            await app._show_command_selection_modal()

            # Should return to normal mode without saving
            assert app.state.app_mode == AppMode.NORMAL
            assert PadId(2, 3) not in app.state.pads

    @pytest.mark.asyncio
    async def test_modal_handles_no_osc_messages(self):
        """Edge case: No OSC messages should show warning and cancel."""
        from launchpad_synesthesia_control.app.ui.tui import LaunchpadSynesthesiaApp

        with patch('launchpad_synesthesia_control.app.ui.tui.SmartLaunchpad') as mock_lp, \
             patch('launchpad_synesthesia_control.app.ui.tui.SynesthesiaOscManager') as mock_osc:

            mock_lp.return_value.connect = AsyncMock(return_value=False)
            mock_lp.return_value.is_connected.return_value = False
            mock_osc.return_value.connect = AsyncMock(return_value=False)
            mock_osc.return_value.is_connected.return_value = False

            app = LaunchpadSynesthesiaApp()

            # State with no candidate commands
            app.state = replace(
                app.state,
                app_mode=AppMode.LEARN_SELECT_MSG,
                learn_state=LearnState(
                    selected_pad=PadId(0, 0),
                    candidate_commands=[]  # Empty!
                )
            )

            # Mock add_log to capture warning
            app.add_log = Mock()

            await app._show_command_selection_modal()

            # Should log warning (may also log cancellation)
            warning_calls = [c for c in app.add_log.call_args_list
                            if "No controllable OSC messages" in str(c)]
            assert len(warning_calls) == 1

            # Should return to normal mode
            assert app.state.app_mode == AppMode.NORMAL

    @pytest.mark.asyncio
    async def test_modal_warns_about_existing_pad_configuration(self):
        """Edge case: Reconfiguring existing pad should show warning."""
        from launchpad_synesthesia_control.app.ui.tui import LaunchpadSynesthesiaApp
        from launchpad_osc_lib import PadBehavior

        with patch('launchpad_synesthesia_control.app.ui.tui.SmartLaunchpad') as mock_lp, \
             patch('launchpad_synesthesia_control.app.ui.tui.SynesthesiaOscManager') as mock_osc:

            mock_lp.return_value.connect = AsyncMock(return_value=False)
            mock_lp.return_value.is_connected.return_value = False
            mock_osc.return_value.connect = AsyncMock(return_value=False)
            mock_osc.return_value.is_connected.return_value = False

            app = LaunchpadSynesthesiaApp()

            pad_id = PadId(2, 3)

            # Configure pad first
            existing_behavior = PadBehavior(
                pad_id=pad_id,
                mode=PadMode.SELECTOR,
                group=PadGroupName.SCENES,
                idle_color=3,
                active_color=21,
                label="Old Scene",
                osc_action=OscCommand("/scenes/Old", [])
            )

            app.state = replace(
                app.state,
                app_mode=AppMode.LEARN_SELECT_MSG,
                pads={pad_id: existing_behavior},
                learn_state=LearnState(
                    selected_pad=pad_id,
                    candidate_commands=[OscCommand("/scenes/New", [])]
                )
            )

            # Mock logging and modal
            app.add_log = Mock()
            app.push_screen_wait = AsyncMock(return_value={
                "command": OscCommand("/scenes/New", []),
                "mode": PadMode.SELECTOR,
                "group": PadGroupName.SCENES,
                "idle_color": 3,
                "active_color": 21,
                "label": "New Scene"
            })

            await app._show_command_selection_modal()

            # Should have logged warning about overwrite
            warning_calls = [call for call in app.add_log.call_args_list
                           if "already configured" in str(call)]
            assert len(warning_calls) > 0

            # But should still proceed with configuration
            assert app.state.pads[pad_id].label == "New Scene"


class TestCommandSelectionScreen:
    """Test the CommandSelectionScreen modal widget."""

    def test_modal_initializes_with_candidates(self):
        """Modal should initialize with candidate commands."""
        from launchpad_synesthesia_control.app.ui.command_selection_screen import CommandSelectionScreen

        candidates = [
            OscCommand("/scenes/Scene1", []),
            OscCommand("/scenes/Scene2", []),
        ]

        screen = CommandSelectionScreen(candidates=candidates, pad_id="2,3")

        assert screen.candidates == candidates
        assert screen.pad_id == "2,3"
        assert screen.selected_command_idx == 0
        assert screen.selected_mode == PadMode.SELECTOR

    def test_modal_default_colors_by_mode(self):
        """Modal should have sensible default colors."""
        from launchpad_synesthesia_control.app.ui.command_selection_screen import CommandSelectionScreen

        screen = CommandSelectionScreen(
            candidates=[OscCommand("/scenes/Test", [])],
            pad_id="0,0"
        )

        # Check defaults
        assert screen.idle_color_idx >= 0
        assert screen.active_color_idx >= 0
        assert screen.idle_color_idx < 8
        assert screen.active_color_idx < 8

    def test_modal_confirms_with_all_fields(self):
        """Confirming modal should return all configuration fields."""
        from launchpad_synesthesia_control.app.ui.command_selection_screen import CommandSelectionScreen

        candidates = [OscCommand("/scenes/Test", [])]
        screen = CommandSelectionScreen(candidates=candidates, pad_id="2,3")

        # Simulate user selections
        screen.selected_mode = PadMode.SELECTOR
        screen.selected_group = "scenes"
        screen.label_text = "Test Label"

        # Mock the query_one to avoid UI dependency
        with patch.object(screen, 'query_one') as mock_query:
            mock_input = Mock()
            mock_input.value = "Test Label"
            mock_query.return_value = mock_input

            # Call action_confirm
            with patch.object(screen, 'dismiss') as mock_dismiss:
                screen.action_confirm()

                # Verify dismiss called with correct result
                result = mock_dismiss.call_args[0][0]
                assert result["command"] == candidates[0]
                assert result["mode"] == PadMode.SELECTOR
                assert result["group"] == "scenes"
                assert result["label"] == "Test Label"
                assert "idle_color" in result
                assert "active_color" in result


class TestLearnModeKeyboardShortcuts:
    """Test keyboard shortcuts in learn mode."""

    @pytest.mark.asyncio
    async def test_l_key_enters_learn_mode(self):
        """Pressing L should enter learn mode."""
        from launchpad_synesthesia_control.app.ui.tui import LaunchpadSynesthesiaApp

        with patch('launchpad_synesthesia_control.app.ui.tui.SmartLaunchpad') as mock_lp, \
             patch('launchpad_synesthesia_control.app.ui.tui.SynesthesiaOscManager') as mock_osc:

            mock_lp.return_value.connect = AsyncMock(return_value=False)
            mock_lp.return_value.is_connected.return_value = False
            mock_osc.return_value.connect = AsyncMock(return_value=False)
            mock_osc.return_value.is_connected.return_value = False

            app = LaunchpadSynesthesiaApp()
            assert app.state.app_mode == AppMode.NORMAL

            # Mock _execute_effects to avoid async issues
            app._execute_effects = AsyncMock()
            app.action_learn()

            assert app.state.app_mode == AppMode.LEARN_WAIT_PAD

    @pytest.mark.asyncio
    async def test_escape_cancels_learn_mode(self):
        """Pressing ESC should cancel learn mode."""
        from launchpad_synesthesia_control.app.ui.tui import LaunchpadSynesthesiaApp

        with patch('launchpad_synesthesia_control.app.ui.tui.SmartLaunchpad') as mock_lp, \
             patch('launchpad_synesthesia_control.app.ui.tui.SynesthesiaOscManager') as mock_osc:

            mock_lp.return_value.connect = AsyncMock(return_value=False)
            mock_lp.return_value.is_connected.return_value = False
            mock_osc.return_value.connect = AsyncMock(return_value=False)
            mock_osc.return_value.is_connected.return_value = False

            app = LaunchpadSynesthesiaApp()
            app.state = replace(app.state, app_mode=AppMode.LEARN_WAIT_PAD)

            # Mock _execute_effects to avoid async issues
            app._execute_effects = AsyncMock()
            app.action_cancel_learn()

            assert app.state.app_mode == AppMode.NORMAL


class TestLearnModeUIUpdates:
    """Test that UI updates correctly during learn mode."""

    def test_status_panel_shows_learn_mode_state(self):
        """Status panel should reflect current learn mode state."""
        from launchpad_synesthesia_control.app.ui.tui import StatusPanel

        panel = StatusPanel()

        # Test each mode
        panel.app_mode = AppMode.NORMAL
        assert "Normal" in panel._format_mode()

        panel.app_mode = AppMode.LEARN_WAIT_PAD
        assert "Select Pad" in panel._format_mode()

        panel.app_mode = AppMode.LEARN_RECORD_OSC
        assert "Recording" in panel._format_mode()

        panel.app_mode = AppMode.LEARN_SELECT_MSG
        assert "Select Message" in panel._format_mode()

    def test_grid_updates_when_pad_configured(self):
        """Grid should update to show newly configured pads."""
        from launchpad_synesthesia_control.app.ui.tui import LaunchpadGrid
        from launchpad_osc_lib import PadBehavior, PadRuntimeState

        grid = LaunchpadGrid()

        pad_id = PadId(2, 3)
        behavior = PadBehavior(
            pad_id=pad_id,
            mode=PadMode.SELECTOR,
            group=PadGroupName.SCENES,
            idle_color=3,
            active_color=21,
            label="Test",
            osc_action=OscCommand("/scenes/Test", [])
        )

        state = ControllerState()
        state = replace(
            state,
            pads={pad_id: behavior},
            pad_runtime={pad_id: PadRuntimeState(is_active=False, current_color=3)}
        )

        grid.state = state

        # Check that pad is shown as configured
        char = grid._get_pad_char(pad_id)
        assert char == "○"  # Configured but inactive


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
