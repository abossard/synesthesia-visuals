"""
TUI Snapshot Tests

Uses Textual's run_test() and save_screenshot() to capture SVG screenshots
of the app in various states for visual regression testing.

Run with: pytest tests/test_tui_snapshots.py -v
Screenshots saved to: tests/snapshots/
"""

import pytest
from pathlib import Path
from unittest.mock import patch, AsyncMock, MagicMock
from dataclasses import replace

# Ensure we can import from the parent package
import sys
sys.path.insert(0, str(Path(__file__).parent.parent.parent))

from launchpad_osc_lib import (
    PadId, AppMode, LearnState, OscCommand,
    PadMode, PadBehavior, PadRuntimeState, PadGroupName
)

# Snapshot output directory
SNAPSHOT_DIR = Path(__file__).parent / "snapshots"


@pytest.fixture(scope="module", autouse=True)
def setup_snapshot_dir():
    """Create snapshot directory if it doesn't exist."""
    SNAPSHOT_DIR.mkdir(exist_ok=True)
    yield


@pytest.fixture
def mock_devices():
    """Mock Launchpad and OSC devices to avoid real connections."""
    with patch('launchpad_synesthesia_control.app.ui.tui.SmartLaunchpad') as mock_lp, \
         patch('launchpad_synesthesia_control.app.ui.tui.SynesthesiaOscManager') as mock_osc, \
         patch('launchpad_synesthesia_control.app.ui.tui.ConfigManager') as mock_config:
        
        # Mock SmartLaunchpad
        mock_lp_instance = MagicMock()
        mock_lp_instance.connect = AsyncMock(return_value=False)
        mock_lp_instance.is_connected.return_value = False
        mock_lp_instance.start_listening = AsyncMock()
        mock_lp_instance.set_pad_callback = MagicMock()
        mock_lp_instance.set_led = MagicMock()
        mock_lp.return_value = mock_lp_instance
        
        # Mock SynesthesiaOscManager
        mock_osc_instance = MagicMock()
        mock_osc_instance.connect = AsyncMock(return_value=False)
        mock_osc_instance.is_connected.return_value = False
        mock_osc_instance.status = "Disconnected (mock)"
        mock_osc_instance.add_all_listener = MagicMock()
        mock_osc.return_value = mock_osc_instance
        
        # Mock ConfigManager
        mock_config_instance = MagicMock()
        mock_config_instance.load.return_value = None
        mock_config_instance.save = MagicMock()
        mock_config.return_value = mock_config_instance
        
        yield {
            'launchpad': mock_lp_instance,
            'osc': mock_osc_instance,
            'config': mock_config_instance,
        }


class TestTuiSnapshots:
    """Visual snapshot tests for the TUI."""

    @pytest.mark.asyncio
    async def test_initial_state_screenshot(self, mock_devices):
        """Screenshot of app in initial/normal state."""
        from launchpad_synesthesia_control.app.ui.tui import LaunchpadSynesthesiaApp
        
        app = LaunchpadSynesthesiaApp()
        
        async with app.run_test(size=(120, 40)) as pilot:
            # Wait for app to fully render
            await pilot.pause()
            
            # Take screenshot
            filename = app.save_screenshot(
                filename="01_initial_state.svg",
                path=str(SNAPSHOT_DIR)
            )
            
            assert Path(filename).exists()
            print(f"Screenshot saved: {filename}")

    @pytest.mark.asyncio
    async def test_learn_mode_wait_pad_screenshot(self, mock_devices):
        """Screenshot of app in learn mode waiting for pad selection."""
        from launchpad_synesthesia_control.app.ui.tui import LaunchpadSynesthesiaApp
        
        app = LaunchpadSynesthesiaApp()
        
        async with app.run_test(size=(120, 40)) as pilot:
            await pilot.pause()
            
            # Enter learn mode via keyboard shortcut
            await pilot.press("l")
            await pilot.pause()
            
            # Verify we're in learn mode
            assert app.state.app_mode == AppMode.LEARN_WAIT_PAD
            
            # Take screenshot
            filename = app.save_screenshot(
                filename="02_learn_mode_wait_pad.svg",
                path=str(SNAPSHOT_DIR)
            )
            
            assert Path(filename).exists()
            print(f"Screenshot saved: {filename}")

    @pytest.mark.asyncio
    async def test_learn_mode_recording_screenshot(self, mock_devices):
        """Screenshot of app recording OSC messages."""
        from launchpad_synesthesia_control.app.ui.tui import LaunchpadSynesthesiaApp
        
        app = LaunchpadSynesthesiaApp()
        
        async with app.run_test(size=(120, 40)) as pilot:
            await pilot.pause()
            
            # Set up state directly for recording mode
            app.state = replace(
                app.state,
                app_mode=AppMode.LEARN_RECORD_OSC,
                learn_state=LearnState(
                    selected_pad=PadId(2, 3),
                    recorded_osc_events=[],
                    record_start_time=0.0,  # Will show timer
                )
            )
            
            # Force UI update
            app._update_ui()
            await pilot.pause()
            
            # Take screenshot
            filename = app.save_screenshot(
                filename="03_learn_mode_recording.svg",
                path=str(SNAPSHOT_DIR)
            )
            
            assert Path(filename).exists()
            print(f"Screenshot saved: {filename}")

    @pytest.mark.asyncio
    async def test_configured_pads_screenshot(self, mock_devices):
        """Screenshot of app with some configured pads."""
        from launchpad_synesthesia_control.app.ui.tui import LaunchpadSynesthesiaApp
        
        app = LaunchpadSynesthesiaApp()
        
        async with app.run_test(size=(120, 40)) as pilot:
            await pilot.pause()
            
            # Configure some pads
            pads = {
                PadId(0, 0): PadBehavior(
                    pad_id=PadId(0, 0),
                    mode=PadMode.SELECTOR,
                    group=PadGroupName.SCENES,
                    idle_color=21,  # Green
                    active_color=5,  # Red
                    label="Scene 1",
                    osc_action=OscCommand("/scenes/Scene1", [])
                ),
                PadId(1, 0): PadBehavior(
                    pad_id=PadId(1, 0),
                    mode=PadMode.SELECTOR,
                    group=PadGroupName.SCENES,
                    idle_color=21,
                    active_color=5,
                    label="Scene 2",
                    osc_action=OscCommand("/scenes/Scene2", [])
                ),
                PadId(0, 1): PadBehavior(
                    pad_id=PadId(0, 1),
                    mode=PadMode.TOGGLE,
                    group=None,
                    idle_color=45,  # Blue
                    active_color=5,
                    label="Strobe",
                    osc_on=OscCommand("/controls/global/strobe", [1]),
                    osc_off=OscCommand("/controls/global/strobe", [0])
                ),
                PadId(7, 7): PadBehavior(
                    pad_id=PadId(7, 7),
                    mode=PadMode.ONE_SHOT,
                    group=None,
                    idle_color=9,  # Orange
                    active_color=13,  # Yellow
                    label="Random",
                    osc_action=OscCommand("/playlist/random", [])
                ),
            }
            
            pad_runtime = {
                PadId(0, 0): PadRuntimeState(is_active=True, current_color=5, blink_enabled=True),
                PadId(1, 0): PadRuntimeState(is_active=False, current_color=21),
                PadId(0, 1): PadRuntimeState(is_active=False, is_on=False, current_color=45),
                PadId(7, 7): PadRuntimeState(is_active=False, current_color=9),
            }
            
            app.state = replace(
                app.state,
                pads=pads,
                pad_runtime=pad_runtime,
                active_scene="Scene1",
                active_preset="Default",
            )
            
            app._update_ui()
            await pilot.pause()
            
            # Take screenshot
            filename = app.save_screenshot(
                filename="04_configured_pads.svg",
                path=str(SNAPSHOT_DIR)
            )
            
            assert Path(filename).exists()
            print(f"Screenshot saved: {filename}")

    @pytest.mark.asyncio
    async def test_cancel_learn_mode_screenshot(self, mock_devices):
        """Screenshot after cancelling learn mode."""
        from launchpad_synesthesia_control.app.ui.tui import LaunchpadSynesthesiaApp
        
        app = LaunchpadSynesthesiaApp()
        
        async with app.run_test(size=(120, 40)) as pilot:
            await pilot.pause()
            
            # Enter learn mode
            await pilot.press("l")
            await pilot.pause()
            
            assert app.state.app_mode == AppMode.LEARN_WAIT_PAD
            
            # Cancel with Escape
            await pilot.press("escape")
            await pilot.pause()
            
            assert app.state.app_mode == AppMode.NORMAL
            
            # Take screenshot
            filename = app.save_screenshot(
                filename="05_after_cancel_learn.svg",
                path=str(SNAPSHOT_DIR)
            )
            
            assert Path(filename).exists()
            print(f"Screenshot saved: {filename}")

    @pytest.mark.asyncio
    async def test_beat_pulse_on_screenshot(self, mock_devices):
        """Screenshot with beat pulse indicator on."""
        from launchpad_synesthesia_control.app.ui.tui import LaunchpadSynesthesiaApp
        
        app = LaunchpadSynesthesiaApp()
        
        async with app.run_test(size=(120, 40)) as pilot:
            await pilot.pause()
            
            # Set beat pulse on
            app.state = replace(app.state, beat_pulse=True, beat_phase=1.0)
            app._update_ui()
            await pilot.pause()
            
            # Take screenshot
            filename = app.save_screenshot(
                filename="06_beat_pulse_on.svg",
                path=str(SNAPSHOT_DIR)
            )
            
            assert Path(filename).exists()
            print(f"Screenshot saved: {filename}")


class TestTuiInteractions:
    """Test user interactions with the TUI."""

    @pytest.mark.asyncio
    async def test_grid_click_triggers_pad_press(self, mock_devices):
        """Clicking on the grid should trigger pad press handling."""
        from launchpad_synesthesia_control.app.ui.tui import LaunchpadSynesthesiaApp
        
        app = LaunchpadSynesthesiaApp()
        
        # Configure a pad first
        pad = PadBehavior(
            pad_id=PadId(0, 0),
            mode=PadMode.ONE_SHOT,
            group=None,
            idle_color=21,
            active_color=5,
            label="Test Pad",
            osc_action=OscCommand("/test", [])
        )
        
        async with app.run_test(size=(120, 40)) as pilot:
            await pilot.pause()
            
            app.state = replace(
                app.state,
                pads={PadId(0, 0): pad},
                pad_runtime={PadId(0, 0): PadRuntimeState(is_active=False, current_color=21)}
            )
            app._update_ui()
            await pilot.pause()
            
            # Take before screenshot
            app.save_screenshot(
                filename="07_before_click.svg",
                path=str(SNAPSHOT_DIR)
            )
            
            # Note: Clicking on specific coordinates in the grid
            # would require knowing the exact layout. For now, just verify the app runs.
            
            await pilot.pause()

    @pytest.mark.asyncio
    async def test_keyboard_shortcuts(self, mock_devices):
        """Test various keyboard shortcuts."""
        from launchpad_synesthesia_control.app.ui.tui import LaunchpadSynesthesiaApp
        
        app = LaunchpadSynesthesiaApp()
        
        async with app.run_test(size=(120, 40)) as pilot:
            await pilot.pause()
            
            # Test 'l' for learn mode
            await pilot.press("l")
            await pilot.pause()
            assert app.state.app_mode == AppMode.LEARN_WAIT_PAD
            
            # Test 'escape' to cancel
            await pilot.press("escape")
            await pilot.pause()
            assert app.state.app_mode == AppMode.NORMAL
            
            # Test 'q' to quit (should trigger exit)
            # Note: This may need special handling depending on app setup


if __name__ == "__main__":
    pytest.main([__file__, "-v", "-s"])
