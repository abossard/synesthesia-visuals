"""
Tests for TUI components - Color mapping and grid rendering.

These tests verify the terminal UI works correctly.
"""

import pytest

# Skip if textual testing is not available
textual_testing = pytest.importorskip(
    "textual.testing",
    reason="textual.testing helpers are unavailable in this Textual build"
)

from textual.testing import ApplicationRunner

from launchpad_synesthesia_control.app.ui.tui import (
    LaunchpadSynesthesiaApp,
    ColorfulLaunchpadGrid,
    StatusPanel,
    HelpPanel,
    LearnModePanel,
    LogPanel,
    velocity_to_rgb,
    get_contrasting_text,
    LAUNCHPAD_TO_TERMINAL_COLOR,
    NAMED_COLORS
)
from launchpad_osc_lib import (
    ButtonId, PadMode, PadGroupName, PadBehavior, PadRuntimeState,
    ControllerState, AppMode, LearnState, OscCommand
)


# =============================================================================
# Color Mapping Tests
# =============================================================================

class TestColorMapping:
    """Test Launchpad to terminal color mapping."""

    def test_known_velocities_map_to_colors(self):
        """Known velocity values map to expected colors."""
        assert velocity_to_rgb(0) == "#1a1a1a"  # Off
        assert velocity_to_rgb(5) == "#ff0000"  # Red
        assert velocity_to_rgb(21) == "#00ff00"  # Green
        assert velocity_to_rgb(45) == "#0066ff"  # Blue

    def test_unknown_velocity_uses_nearest(self):
        """Unknown velocities use nearest known color."""
        # Velocity 2 should use color from velocity 1 (red dim)
        color = velocity_to_rgb(2)
        assert color == "#660000"

    def test_all_launchpad_colors_have_mapping(self):
        """All defined Launchpad colors have terminal mapping."""
        for velocity in LAUNCHPAD_TO_TERMINAL_COLOR:
            rgb = velocity_to_rgb(velocity)
            assert rgb.startswith("#")
            assert len(rgb) == 7

    def test_named_colors_are_complete(self):
        """Named colors include all common colors."""
        expected = ["off", "red", "orange", "yellow", "green", "cyan", "blue", "purple", "pink", "white"]
        for name in expected:
            assert name in NAMED_COLORS


class TestContrastingText:
    """Test contrasting text color selection."""

    def test_dark_background_gets_white_text(self):
        """Dark backgrounds get white text."""
        assert get_contrasting_text("#000000") == "#ffffff"
        assert get_contrasting_text("#1a1a1a") == "#ffffff"
        assert get_contrasting_text("#333333") == "#ffffff"

    def test_light_background_gets_black_text(self):
        """Light backgrounds get black text."""
        assert get_contrasting_text("#ffffff") == "#000000"
        assert get_contrasting_text("#ffff00") == "#000000"  # Yellow
        assert get_contrasting_text("#00ff00") == "#000000"  # Green

    def test_invalid_color_returns_white(self):
        """Invalid color format returns white."""
        assert get_contrasting_text("invalid") == "#ffffff"


# =============================================================================
# Application Tests
# =============================================================================

class TestLaunchpadSynesthesiaApp:
    """Test main application."""

    @pytest.mark.asyncio
    async def test_application_starts(self):
        """Application starts without errors."""
        runner = ApplicationRunner(LaunchpadSynesthesiaApp)
        async with runner.run_test() as pilot:
            await pilot.pause()
        # If we reach here, app started successfully
        assert True

    @pytest.mark.asyncio
    async def test_initial_state_is_normal(self):
        """Application starts in NORMAL mode."""
        runner = ApplicationRunner(LaunchpadSynesthesiaApp)
        async with runner.run_test() as pilot:
            app = pilot.app
            assert app.state.app_mode == AppMode.NORMAL

    @pytest.mark.asyncio
    async def test_learn_mode_keybinding(self):
        """L key enters learn mode."""
        runner = ApplicationRunner(LaunchpadSynesthesiaApp)
        async with runner.run_test() as pilot:
            await pilot.press("l")
            await pilot.pause()
            assert pilot.app.state.app_mode == AppMode.LEARN_WAIT_PAD

    @pytest.mark.asyncio
    async def test_escape_cancels_learn_mode(self):
        """Escape cancels learn mode."""
        runner = ApplicationRunner(LaunchpadSynesthesiaApp)
        async with runner.run_test() as pilot:
            await pilot.press("l")  # Enter learn
            await pilot.pause()
            await pilot.press("escape")  # Cancel
            await pilot.pause()
            assert pilot.app.state.app_mode == AppMode.NORMAL

    @pytest.mark.asyncio
    async def test_injectable_time_function(self):
        """Time function can be injected for testing."""
        mock_time = lambda: 1234567890.0
        app = LaunchpadSynesthesiaApp(time_func=mock_time)
        assert app._time_func() == 1234567890.0


# =============================================================================
# Widget Tests
# =============================================================================

class TestColorfulLaunchpadGrid:
    """Test the colorful grid widget."""

    def test_grid_renders_without_state(self):
        """Grid renders with empty state."""
        grid = ColorfulLaunchpadGrid()
        output = grid.render()

        assert "LAUNCHPAD" in output
        assert "│" in output  # Border characters

    def test_grid_renders_mapped_pads(self):
        """Grid renders mapped pads with indicators."""
        # Create state with a pad
        pad_id = ButtonId(0, 0)
        behavior = PadBehavior(
            pad_id=pad_id, mode=PadMode.ONE_SHOT,
            osc_action=OscCommand("/test"), active_color=21
        )
        state = ControllerState(
            pads={pad_id: behavior},
            pad_runtime={pad_id: PadRuntimeState(is_active=False, current_color=0)}
        )

        grid = ColorfulLaunchpadGrid()
        grid.state = state
        output = grid.render()

        # Should contain pad indicator
        assert "○" in output or "●" in output

    def test_pad_click_mapping(self):
        """Grid correctly maps click coordinates to pads."""
        grid = ColorfulLaunchpadGrid()

        # Test top row (y=1 in render, maps to y=-1)
        pad = grid._pad_from_click(6, 1)
        assert pad is not None
        assert pad.y == -1

        # Test main grid
        pad = grid._pad_from_click(6, 4)
        assert pad is not None
        assert 0 <= pad.y < 8


class TestStatusPanel:
    """Test status panel widget."""

    def test_status_panel_renders(self):
        """Status panel renders all sections."""
        panel = StatusPanel()
        output = panel.render()

        assert "STATUS" in output
        assert "Launchpad" in output
        assert "OSC" in output
        assert "Mode" in output

    def test_status_shows_connected_state(self):
        """Status shows connection state."""
        panel = StatusPanel()
        panel.launchpad_connected = True
        panel.osc_connected = False
        output = panel.render()

        assert "CONNECTED" in output
        assert "DISCONNECTED" in output

    def test_status_shows_app_mode(self):
        """Status shows current app mode."""
        panel = StatusPanel()
        panel.app_mode = AppMode.LEARN_WAIT_PAD
        output = panel.render()

        assert "LEARNING" in output


class TestHelpPanel:
    """Test help panel widget."""

    def test_help_panel_shows_normal_mode_help(self):
        """Help panel shows shortcuts in normal mode."""
        panel = HelpPanel()
        panel.app_mode = AppMode.NORMAL
        output = panel.render()

        assert "HELP" in output
        assert "L" in output  # Learn mode key
        assert "Q" in output  # Quit key

    def test_help_panel_shows_learn_mode_help(self):
        """Help panel shows learn instructions in learn mode."""
        panel = HelpPanel()
        panel.app_mode = AppMode.LEARN_WAIT_PAD
        output = panel.render()

        assert "LEARN MODE" in output
        assert "Select Pad" in output

    def test_help_panel_shows_recording_help(self):
        """Help panel shows recording instructions."""
        panel = HelpPanel()
        panel.app_mode = AppMode.LEARN_RECORD_OSC
        output = panel.render()

        assert "RECORDING" in output
        assert "Synesthesia" in output


class TestLearnModePanel:
    """Test learn mode panel widget."""

    def test_learn_panel_shows_instructions(self):
        """Learn panel shows instructions based on mode."""
        # The panel updates via reactive properties
        # Basic test to verify it creates without error
        panel = LearnModePanel()
        assert panel is not None


class TestLogPanel:
    """Test log panel widget."""

    def test_log_panel_adds_messages(self):
        """Log panel stores messages."""
        panel = LogPanel()
        panel.add_log("Test message", "INFO")

        assert len(panel.logs) == 1
        assert "Test message" in panel.logs[0]

    def test_log_panel_color_coding(self):
        """Log messages are color coded by level."""
        panel = LogPanel()

        panel.add_log("Info", "INFO")
        panel.add_log("Warning", "WARNING")
        panel.add_log("Error", "ERROR")

        assert "cyan" in panel.logs[0]
        assert "yellow" in panel.logs[1]
        assert "red" in panel.logs[2]

    def test_log_panel_limits_size(self):
        """Log panel limits number of stored messages."""
        panel = LogPanel()

        for i in range(150):
            panel.add_log(f"Message {i}", "INFO")

        assert len(panel.logs) == 100


# =============================================================================
# Integration Tests
# =============================================================================

class TestUIIntegration:
    """Integration tests for UI components."""

    @pytest.mark.asyncio
    async def test_learn_mode_workflow(self):
        """Test complete learn mode UI workflow."""
        runner = ApplicationRunner(LaunchpadSynesthesiaApp)
        async with runner.run_test() as pilot:
            app = pilot.app

            # Start in normal mode
            assert app.state.app_mode == AppMode.NORMAL

            # Enter learn mode
            await pilot.press("l")
            await pilot.pause()
            assert app.state.app_mode == AppMode.LEARN_WAIT_PAD

            # Cancel with escape
            await pilot.press("escape")
            await pilot.pause()
            assert app.state.app_mode == AppMode.NORMAL
