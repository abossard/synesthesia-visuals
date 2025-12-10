"""
Launchpad Emulator - Transparent Drop-in Replacement.

The LaunchpadEmulator implements the same interface as LaunchpadDevice,
allowing transparent substitution. Consumers don't know if they're using
real hardware or an emulator.

For TUI visualization, use get_view() to access LED state inspection.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import TYPE_CHECKING, Callable, Dict, Optional, Protocol

from .button_id import ButtonId

# Color constant
LP_OFF = 0

if TYPE_CHECKING:
    from .launchpad import LaunchpadDevice, LaunchpadConfig


# =============================================================================
# Protocol: Interface for Launchpad-like devices
# =============================================================================


class LaunchpadInterface(Protocol):
    """
    Protocol for Launchpad-like devices (structural subtyping).
    
    Both LaunchpadDevice and LaunchpadEmulator implement this interface,
    making them interchangeable. Consumers use this interface and don't
    know whether they're talking to real hardware or an emulator.
    """

    async def connect(self) -> bool:
        """Connect to device."""
        ...

    def set_pad_callback(self, callback: Callable[[ButtonId, int], None]) -> None:
        """Register callback for pad press events."""
        ...

    def set_pad_release_callback(self, callback: Callable[[ButtonId], None]) -> None:
        """Register callback for pad release events (for PUSH mode)."""
        ...

    async def start_listening(self) -> None:
        """Start listening for pad presses."""
        ...

    def set_led(self, pad_id: ButtonId, color: int, blink: bool = False) -> None:
        """Set LED color for a pad."""
        ...

    def clear_all_leds(self) -> None:
        """Turn off all LEDs."""
        ...

    async def stop(self) -> None:
        """Stop and disconnect."""
        ...

    def is_connected(self) -> bool:
        """Check if connected."""
        ...


# =============================================================================
# LED State: Tracks color and blink for each pad
# =============================================================================


@dataclass(frozen=True)
class LedState:
    """LED state for a single pad."""

    color: int = LP_OFF
    blink: bool = False


# =============================================================================
# Grid Layout for Launchpad Mini Mk3
# =============================================================================


@dataclass(frozen=True)
class FullGridLayout:
    """
    Full Launchpad Mini Mk3 layout including all pads.
    
    Layout (as seen from above):
        Top row:    x=0-7, y=-1  (CC buttons)
        Grid:       x=0-7, y=0-7 (main 8x8 grid, y=7 is top)
        Right col:  x=8, y=0-7   (scene launch buttons)
    
    Visual representation:
        [T0][T1][T2][T3][T4][T5][T6][T7]
        [70][71][72][73][74][75][76][77][R7]
        [60][61][62][63][64][65][66][67][R6]
        [50][51][52][53][54][55][56][57][R5]
        [40][41][42][43][44][45][46][47][R4]
        [30][31][32][33][34][35][36][37][R3]
        [20][21][22][23][24][25][26][27][R2]
        [10][11][12][13][14][15][16][17][R1]
        [00][01][02][03][04][05][06][07][R0]
    """
    
    # Grid dimensions
    GRID_WIDTH: int = 8
    GRID_HEIGHT: int = 8
    TOP_ROW_COUNT: int = 8
    RIGHT_COL_COUNT: int = 8
    
    @staticmethod
    def all_grid_pads() -> list[ButtonId]:
        """Get all 8x8 grid pads."""
        return [ButtonId(x, y) for y in range(8) for x in range(8)]
    
    @staticmethod
    def all_top_row_pads() -> list[ButtonId]:
        """Get all top row pads (y=-1)."""
        return [ButtonId(x, -1) for x in range(8)]
    
    @staticmethod
    def all_right_column_pads() -> list[ButtonId]:
        """Get all right column pads (x=8)."""
        return [ButtonId(8, y) for y in range(8)]
    
    @staticmethod
    def all_pads() -> list[ButtonId]:
        """Get all pads on the Launchpad."""
        pads = []
        pads.extend(FullGridLayout.all_top_row_pads())
        pads.extend(FullGridLayout.all_grid_pads())
        pads.extend(FullGridLayout.all_right_column_pads())
        return pads


# =============================================================================
# Emulator View: Read-only access to emulator state (for TUI)
# =============================================================================


class EmulatorView:
    """
    Read-only view into emulator LED state.
    
    Use this for TUI visualization. Separate from LaunchpadInterface
    to keep the main interface clean and transparent.
    """

    def __init__(self, emulator: "LaunchpadEmulator"):
        self._emulator = emulator

    def get_led_state(self, pad_id: ButtonId) -> LedState:
        """Get current LED state for a pad (color and blink)."""
        return self._emulator._led_states.get(pad_id, LedState())

    def get_led_color(self, pad_id: ButtonId) -> int:
        """Get current LED color for a pad."""
        return self._emulator._led_states.get(pad_id, LedState()).color

    def get_led_grid(self) -> Dict[ButtonId, LedState]:
        """Get dict mapping ButtonId -> LedState for all pads with non-default state."""
        return dict(self._emulator._led_states)

    def get_8x8_grid(self) -> list[list[LedState]]:
        """
        Get 8x8 main grid as 2D list for TUI rendering.
        
        Returns list[row][col] where row 0 is bottom (y=0), row 7 is top (y=7).
        """
        grid: list[list[LedState]] = []
        for y in range(8):
            row: list[LedState] = []
            for x in range(8):
                row.append(self.get_led_state(ButtonId(x, y)))
            grid.append(row)
        return grid

    def get_top_row(self) -> list[LedState]:
        """Get top row buttons (y=-1) as list."""
        return [self.get_led_state(ButtonId(x, -1)) for x in range(8)]

    def get_right_column(self) -> list[LedState]:
        """Get right column buttons (x=8) as list, bottom to top."""
        return [self.get_led_state(ButtonId(8, y)) for y in range(8)]

    def get_full_grid(self) -> dict:
        """
        Get complete Launchpad state for TUI rendering.
        
        Returns:
            {
                "top_row": [LedState x 8],      # y=-1, left to right
                "grid": [[LedState x 8] x 8],   # 8x8 grid, row 0=bottom
                "right_column": [LedState x 8]  # x=8, bottom to top
            }
        """
        return {
            "top_row": self.get_top_row(),
            "grid": self.get_8x8_grid(),
            "right_column": self.get_right_column(),
        }

    def set_state_changed_callback(self, callback: Callable[[], None]) -> None:
        """Register callback to be notified when LED state changes."""
        self._emulator._state_changed_callback = callback

    def simulate_press(self, pad_id: ButtonId, velocity: int = 127) -> None:
        """
        Inject a simulated pad press.
        
        Triggers the registered callback as if the pad was physically pressed.
        Works for any pad: grid, top row, or right column.
        """
        if self._emulator._callback:
            self._emulator._callback(pad_id, velocity)


# =============================================================================
# Emulator: Virtual Launchpad - Same interface as LaunchpadDevice
# =============================================================================


@dataclass
class LaunchpadEmulator:
    """
    Virtual Launchpad that maintains LED state in memory.
    
    Implements LaunchpadInterface - can be used anywhere LaunchpadDevice is used.
    Consumers don't know if they're using real hardware or this emulator.
    
    Supports all pads:
    - 8x8 grid (x=0-7, y=0-7)
    - Top row (x=0-7, y=-1)
    - Right column (x=8, y=0-7)
    
    For TUI access to LED state, use get_view() to get an EmulatorView.
    """

    _led_states: Dict[ButtonId, LedState] = field(default_factory=dict)
    _callback: Optional[Callable[[ButtonId, int], None]] = None
    _connected: bool = False
    _listening: bool = False
    _state_changed_callback: Optional[Callable[[], None]] = None

    # =========================================================================
    # LaunchpadInterface implementation (same as LaunchpadDevice)
    # =========================================================================

    async def connect(self) -> bool:
        """Connect to emulator (always succeeds)."""
        self._connected = True
        return True

    def set_pad_callback(self, callback: Callable[[ButtonId, int], None]) -> None:
        """Register callback for pad press events."""
        self._callback = callback

    def set_pad_release_callback(self, callback: Callable[[ButtonId], None]) -> None:
        """Register callback for pad release events (for PUSH mode)."""
        self._release_callback = callback

    async def start_listening(self) -> None:
        """Start listening (no-op for emulator, state is reactive)."""
        self._listening = True

    def set_led(self, pad_id: ButtonId, color: int, blink: bool = False) -> None:
        """Set LED color for a pad (stores in memory)."""
        self._led_states[pad_id] = LedState(color=color, blink=blink)
        if self._state_changed_callback:
            self._state_changed_callback()

    def clear_all_leds(self) -> None:
        """Turn off all LEDs (grid, top row, right column)."""
        self._led_states.clear()
        if self._state_changed_callback:
            self._state_changed_callback()

    async def stop(self) -> None:
        """Stop and disconnect."""
        self._listening = False
        self._connected = False

    def is_connected(self) -> bool:
        """Check if connected."""
        return self._connected

    # =========================================================================
    # Emulator-specific: Get view for TUI access
    # =========================================================================

    def get_view(self) -> EmulatorView:
        """
        Get a view for TUI visualization and simulated input.
        
        Returns an EmulatorView that provides read access to LED state
        and ability to simulate pad presses.
        """
        return EmulatorView(self)


# =============================================================================
# Smart Launchpad: Auto-selects real device or emulator
# =============================================================================


@dataclass
class SmartLaunchpad:
    """
    Smart wrapper that uses real device if available, emulator otherwise.
    
    Implements LaunchpadInterface - consumers use it like any Launchpad.
    Automatically falls back to emulator when no hardware is connected.
    Supports hot-swap: attach/detach real device at runtime.
    
    For TUI access, use get_view() - works whether using real device or emulator.
    LED state is always tracked in the emulator for visualization.
    
    Usage:
        # Simple: emulator only
        lp = SmartLaunchpad()
        
        # With config: tries to connect real device
        lp = SmartLaunchpad(config=LaunchpadConfig(auto_detect=True))
    """

    config: Optional["LaunchpadConfig"] = None
    _emulator: LaunchpadEmulator = field(default_factory=LaunchpadEmulator)
    _real_device: Optional["LaunchpadDevice"] = None
    _pad_callback: Optional[Callable[[ButtonId, int], None]] = None
    _use_real: bool = False  # True when real device is active
    
    def __post_init__(self):
        """Initialize real device from config if provided."""
        if self.config is not None:
            from .launchpad import LaunchpadDevice
            self._real_device = LaunchpadDevice(self.config)

    # =========================================================================
    # LaunchpadInterface implementation
    # =========================================================================

    async def connect(self) -> bool:
        """Connect - tries real device first, falls back to emulator."""
        # Always connect emulator (for state tracking)
        await self._emulator.connect()

        if self._real_device:
            self._use_real = await self._real_device.connect()
            return self._use_real

        return True  # Emulator is always available

    def set_pad_callback(self, callback: Callable[[ButtonId, int], None]) -> None:
        """Register callback for pad press events."""
        self._pad_callback = callback
        self._emulator.set_pad_callback(callback)

        if self._real_device:
            self._real_device.set_pad_callback(callback)

    def set_pad_release_callback(self, callback: Callable[[ButtonId], None]) -> None:
        """Register callback for pad release events (for PUSH mode)."""
        self._release_callback = callback
        self._emulator.set_pad_release_callback(callback)

        if self._real_device:
            self._real_device.set_pad_release_callback(callback)

    async def start_listening(self) -> None:
        """Start listening for pad presses."""
        await self._emulator.start_listening()

        if self._real_device and self._use_real:
            await self._real_device.start_listening()

    def set_led(self, pad_id: ButtonId, color: int, blink: bool = False) -> None:
        """Set LED color - mirrors to emulator, sends to real device if connected."""
        # Always update emulator (for TUI state)
        self._emulator.set_led(pad_id, color, blink)

        # Forward to real device if active
        if self._real_device and self._use_real:
            self._real_device.set_led(pad_id, color, blink)

    def clear_all_leds(self) -> None:
        """Turn off all LEDs."""
        self._emulator.clear_all_leds()

        if self._real_device and self._use_real:
            self._real_device.clear_all_leds()

    async def stop(self) -> None:
        """Stop and disconnect."""
        await self._emulator.stop()

        if self._real_device:
            await self._real_device.stop()
        self._use_real = False

    def is_connected(self) -> bool:
        """Check if connected (real or emulator)."""
        if self._use_real and self._real_device:
            return self._real_device.is_connected()
        return self._emulator.is_connected()

    # =========================================================================
    # Device management
    # =========================================================================

    def has_real_device(self) -> bool:
        """Check if real hardware is active."""
        return self._use_real and self._real_device is not None

    async def attach_device(self, device: "LaunchpadDevice") -> bool:
        """
        Attach a real Launchpad device.
        
        Syncs LED state from emulator to device and starts using real hardware.
        Returns True if device connected successfully.
        """
        self._real_device = device

        # Register callback on real device
        if self._pad_callback:
            device.set_pad_callback(self._pad_callback)

        # Connect device
        connected = await device.connect()

        if connected:
            self._use_real = True

            # Replay all LED states to real device
            for pad_id, led_state in self._emulator._led_states.items():
                device.set_led(pad_id, led_state.color, led_state.blink)

            # Start listening on real device
            await device.start_listening()

        return connected

    async def detach_device(self) -> None:
        """Detach real device, continue with emulator only."""
        if self._real_device:
            await self._real_device.stop()
            self._real_device = None
        self._use_real = False

    # =========================================================================
    # View access (for TUI)
    # =========================================================================

    def get_view(self) -> EmulatorView:
        """
        Get view for TUI visualization.
        
        Returns EmulatorView - LED state is always tracked in emulator
        regardless of whether real device is connected.
        """
        return self._emulator.get_view()


# =============================================================================
# Factory function
# =============================================================================


def create_launchpad(real_device: Optional["LaunchpadDevice"] = None) -> SmartLaunchpad:
    """
    Create a SmartLaunchpad with optional real device.
    
    If real_device is provided and connects successfully, uses hardware.
    Otherwise falls back to emulator transparently.
    
    Usage:
        # Auto-detect and use real device or emulator
        launchpad = create_launchpad()
        
        # Or with explicit real device
        from launchpad_osc_lib import LaunchpadDevice
        launchpad = create_launchpad(LaunchpadDevice())
    """
    smart = SmartLaunchpad()
    if real_device:
        smart._real_device = real_device
    return smart
