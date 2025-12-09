"""
Tests for Launchpad Emulator and SmartLaunchpad.

Tests transparent replacement behavior and full grid support.
"""

import pytest
from launchpad_osc_lib.launchpad import PadId, LP_RED, LP_GREEN, LP_OFF, LP_BLUE
from launchpad_osc_lib.emulator import (
    LaunchpadEmulator,
    SmartLaunchpad,
    LedState,
    EmulatorView,
    FullGridLayout,
    create_launchpad,
)


class TestLedState:
    """Test LedState dataclass."""

    def test_default_state(self):
        """Default state is off, no blink."""
        state = LedState()
        assert state.color == LP_OFF
        assert state.blink is False

    def test_custom_state(self):
        """Custom state with color and blink."""
        state = LedState(color=LP_RED, blink=True)
        assert state.color == LP_RED
        assert state.blink is True

    def test_immutability(self):
        """LedState is immutable."""
        state = LedState()
        with pytest.raises(AttributeError):
            state.color = 5


class TestFullGridLayout:
    """Test FullGridLayout helper."""

    def test_all_grid_pads(self):
        """Returns 64 grid pads."""
        pads = FullGridLayout.all_grid_pads()
        assert len(pads) == 64
        assert PadId(0, 0) in pads
        assert PadId(7, 7) in pads

    def test_all_top_row_pads(self):
        """Returns 8 top row pads."""
        pads = FullGridLayout.all_top_row_pads()
        assert len(pads) == 8
        assert all(p.y == -1 for p in pads)
        assert PadId(0, -1) in pads
        assert PadId(7, -1) in pads

    def test_all_right_column_pads(self):
        """Returns 8 right column pads."""
        pads = FullGridLayout.all_right_column_pads()
        assert len(pads) == 8
        assert all(p.x == 8 for p in pads)
        assert PadId(8, 0) in pads
        assert PadId(8, 7) in pads

    def test_all_pads(self):
        """Returns all 80 pads (64 grid + 8 top + 8 right)."""
        pads = FullGridLayout.all_pads()
        assert len(pads) == 80


class TestLaunchpadEmulatorInterface:
    """Test LaunchpadEmulator implements same interface as LaunchpadDevice."""

    @pytest.mark.asyncio
    async def test_connect_always_succeeds(self):
        """Emulator connect always returns True."""
        emu = LaunchpadEmulator()
        result = await emu.connect()
        assert result is True
        assert emu.is_connected() is True

    @pytest.mark.asyncio
    async def test_stop_disconnects(self):
        """stop() sets connected to False."""
        emu = LaunchpadEmulator()
        await emu.connect()
        await emu.stop()
        assert emu.is_connected() is False

    def test_set_led_all_pad_types(self):
        """set_led works for grid, top row, and right column."""
        emu = LaunchpadEmulator()
        
        # Grid pad
        emu.set_led(PadId(3, 4), LP_RED)
        # Top row
        emu.set_led(PadId(5, -1), LP_GREEN)
        # Right column
        emu.set_led(PadId(8, 2), LP_BLUE)
        
        view = emu.get_view()
        assert view.get_led_color(PadId(3, 4)) == LP_RED
        assert view.get_led_color(PadId(5, -1)) == LP_GREEN
        assert view.get_led_color(PadId(8, 2)) == LP_BLUE

    def test_clear_all_leds(self):
        """clear_all_leds resets all LED states."""
        emu = LaunchpadEmulator()
        emu.set_led(PadId(0, 0), LP_RED)
        emu.set_led(PadId(5, -1), LP_GREEN)
        emu.set_led(PadId(8, 3), LP_BLUE)
        
        emu.clear_all_leds()
        
        view = emu.get_view()
        assert view.get_led_color(PadId(0, 0)) == LP_OFF
        assert view.get_led_color(PadId(5, -1)) == LP_OFF
        assert view.get_led_color(PadId(8, 3)) == LP_OFF

    def test_set_pad_callback(self):
        """Callback is registered and callable via view.simulate_press."""
        emu = LaunchpadEmulator()
        presses = []
        
        emu.set_pad_callback(lambda p, v: presses.append((p, v)))
        emu.get_view().simulate_press(PadId(2, 3), 100)
        
        assert presses == [(PadId(2, 3), 100)]


class TestEmulatorView:
    """Test EmulatorView for TUI access."""

    def test_get_led_state(self):
        """get_led_state returns LedState with color and blink."""
        emu = LaunchpadEmulator()
        emu.set_led(PadId(0, 0), LP_RED, blink=True)
        
        view = emu.get_view()
        state = view.get_led_state(PadId(0, 0))
        
        assert state.color == LP_RED
        assert state.blink is True

    def test_get_led_state_default(self):
        """Unset pads return default state."""
        emu = LaunchpadEmulator()
        view = emu.get_view()
        
        state = view.get_led_state(PadId(5, 5))
        assert state.color == LP_OFF
        assert state.blink is False

    def test_get_8x8_grid(self):
        """get_8x8_grid returns 2D list for main grid."""
        emu = LaunchpadEmulator()
        emu.set_led(PadId(2, 3), LP_RED)
        
        view = emu.get_view()
        grid = view.get_8x8_grid()
        
        assert len(grid) == 8
        assert len(grid[0]) == 8
        assert grid[3][2].color == LP_RED  # row 3, col 2

    def test_get_top_row(self):
        """get_top_row returns top row buttons."""
        emu = LaunchpadEmulator()
        emu.set_led(PadId(3, -1), LP_GREEN)
        
        view = emu.get_view()
        top_row = view.get_top_row()
        
        assert len(top_row) == 8
        assert top_row[3].color == LP_GREEN

    def test_get_right_column(self):
        """get_right_column returns right column buttons."""
        emu = LaunchpadEmulator()
        emu.set_led(PadId(8, 5), LP_BLUE)
        
        view = emu.get_view()
        right_col = view.get_right_column()
        
        assert len(right_col) == 8
        assert right_col[5].color == LP_BLUE

    def test_get_full_grid(self):
        """get_full_grid returns all pad regions."""
        emu = LaunchpadEmulator()
        emu.set_led(PadId(0, 0), LP_RED)      # Grid
        emu.set_led(PadId(4, -1), LP_GREEN)   # Top row
        emu.set_led(PadId(8, 6), LP_BLUE)     # Right column
        
        view = emu.get_view()
        full = view.get_full_grid()
        
        assert "top_row" in full
        assert "grid" in full
        assert "right_column" in full
        
        assert len(full["top_row"]) == 8
        assert len(full["grid"]) == 8
        assert len(full["right_column"]) == 8
        
        assert full["grid"][0][0].color == LP_RED
        assert full["top_row"][4].color == LP_GREEN
        assert full["right_column"][6].color == LP_BLUE

    def test_simulate_press_all_pad_types(self):
        """simulate_press works for all pad types."""
        emu = LaunchpadEmulator()
        presses = []
        emu.set_pad_callback(lambda p, v: presses.append(p))
        
        view = emu.get_view()
        view.simulate_press(PadId(1, 2))       # Grid
        view.simulate_press(PadId(3, -1))      # Top row
        view.simulate_press(PadId(8, 4))       # Right column
        
        assert PadId(1, 2) in presses
        assert PadId(3, -1) in presses
        assert PadId(8, 4) in presses

    def test_state_changed_callback(self):
        """State changed callback fires on set_led."""
        emu = LaunchpadEmulator()
        changes = []
        
        view = emu.get_view()
        view.set_state_changed_callback(lambda: changes.append(1))
        
        emu.set_led(PadId(0, 0), LP_RED)
        emu.set_led(PadId(1, -1), LP_GREEN)
        emu.clear_all_leds()
        
        assert len(changes) == 3


class TestSmartLaunchpad:
    """Test SmartLaunchpad transparent wrapper."""

    @pytest.mark.asyncio
    async def test_connect_without_device(self):
        """SmartLaunchpad connects emulator when no real device."""
        smart = SmartLaunchpad()
        result = await smart.connect()
        
        assert result is True
        assert smart.is_connected() is True
        assert smart.has_real_device() is False

    def test_set_led_updates_emulator(self):
        """set_led updates emulator state (visible via view)."""
        smart = SmartLaunchpad()
        
        smart.set_led(PadId(2, 3), LP_RED, blink=True)
        
        view = smart.get_view()
        state = view.get_led_state(PadId(2, 3))
        assert state.color == LP_RED
        assert state.blink is True

    def test_set_led_all_pad_types(self):
        """set_led works for all pad types."""
        smart = SmartLaunchpad()
        
        smart.set_led(PadId(0, 0), LP_RED)
        smart.set_led(PadId(7, -1), LP_GREEN)
        smart.set_led(PadId(8, 7), LP_BLUE)
        
        view = smart.get_view()
        assert view.get_led_color(PadId(0, 0)) == LP_RED
        assert view.get_led_color(PadId(7, -1)) == LP_GREEN
        assert view.get_led_color(PadId(8, 7)) == LP_BLUE

    def test_clear_all_leds(self):
        """clear_all_leds clears emulator."""
        smart = SmartLaunchpad()
        smart.set_led(PadId(0, 0), LP_RED)
        
        smart.clear_all_leds()
        
        view = smart.get_view()
        assert view.get_led_state(PadId(0, 0)).color == LP_OFF

    def test_simulate_press_via_view(self):
        """simulate_press on view triggers callback."""
        smart = SmartLaunchpad()
        presses = []
        
        smart.set_pad_callback(lambda p, v: presses.append((p, v)))
        smart.get_view().simulate_press(PadId(5, 6), velocity=80)
        
        assert presses == [(PadId(5, 6), 80)]

    def test_get_view_returns_emulator_view(self):
        """get_view returns EmulatorView instance."""
        smart = SmartLaunchpad()
        view = smart.get_view()
        assert isinstance(view, EmulatorView)

    def test_get_full_grid(self):
        """get_view().get_full_grid() returns complete state."""
        smart = SmartLaunchpad()
        smart.set_led(PadId(1, 2), LP_GREEN)
        smart.set_led(PadId(6, -1), LP_RED)
        
        full = smart.get_view().get_full_grid()
        
        assert full["grid"][2][1].color == LP_GREEN
        assert full["top_row"][6].color == LP_RED

    @pytest.mark.asyncio
    async def test_stop(self):
        """stop() stops emulator."""
        smart = SmartLaunchpad()
        await smart.connect()
        await smart.stop()
        
        assert smart._emulator.is_connected() is False

    @pytest.mark.asyncio
    async def test_detach_device_without_device(self):
        """detach_device with no device does not crash."""
        smart = SmartLaunchpad()
        await smart.detach_device()  # Should not raise

    def test_has_real_device_false_initially(self):
        """has_real_device is False with no device."""
        smart = SmartLaunchpad()
        assert smart.has_real_device() is False


class TestCreateLaunchpad:
    """Test factory function."""

    def test_create_launchpad_no_device(self):
        """create_launchpad with no device returns SmartLaunchpad."""
        lp = create_launchpad()
        assert isinstance(lp, SmartLaunchpad)
        assert lp.has_real_device() is False

    def test_create_launchpad_returns_smart(self):
        """Factory returns SmartLaunchpad instance."""
        lp = create_launchpad()
        assert isinstance(lp, SmartLaunchpad)


class TestTransparency:
    """Test that emulator is transparent to consumers."""

    @pytest.mark.asyncio
    async def test_consumer_code_works_with_emulator(self):
        """
        Simulated consumer code works without knowing it's an emulator.
        
        This is the key test: consumer uses LaunchpadInterface methods
        and doesn't know if it's real or emulated.
        """
        # Consumer creates launchpad (doesn't know it's emulated)
        launchpad = create_launchpad()
        
        # Consumer connects
        connected = await launchpad.connect()
        assert connected is True
        
        # Consumer sets up callback
        events = []
        launchpad.set_pad_callback(lambda p, v: events.append((p, v)))
        
        # Consumer sets LEDs
        launchpad.set_led(PadId(0, 0), LP_RED)
        launchpad.set_led(PadId(4, -1), LP_GREEN)  # Top row
        launchpad.set_led(PadId(8, 3), LP_BLUE)    # Right column
        
        # Consumer checks connection
        assert launchpad.is_connected() is True
        
        # Consumer clears and stops
        launchpad.clear_all_leds()
        await launchpad.stop()
        
        # All worked without consumer knowing it's emulated
        assert launchpad.is_connected() is False

    def test_view_is_separate_from_interface(self):
        """
        EmulatorView is separate - consumers don't see it unless they ask.
        
        The main LaunchpadInterface has no get_view, get_led_state, etc.
        Those are only on SmartLaunchpad/EmulatorView.
        """
        lp = create_launchpad()
        
        # Interface methods (what consumers use)
        assert hasattr(lp, 'connect')
        assert hasattr(lp, 'set_led')
        assert hasattr(lp, 'set_pad_callback')
        assert hasattr(lp, 'clear_all_leds')
        assert hasattr(lp, 'stop')
        assert hasattr(lp, 'is_connected')
        
        # View access (for TUI, optional)
        assert hasattr(lp, 'get_view')
        view = lp.get_view()
        assert hasattr(view, 'get_full_grid')
        assert hasattr(view, 'simulate_press')


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
