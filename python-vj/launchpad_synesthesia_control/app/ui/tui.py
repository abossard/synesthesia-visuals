"""
Launchpad Synesthesia Control - Colorful Terminal UI

Main application with async event handling, colorful grid representation,
and comprehensive user guidance.
"""

import asyncio
import logging
import time
from pathlib import Path
from typing import Optional, List, Callable

from textual.app import App, ComposeResult
from textual.containers import Container, Horizontal, Vertical, VerticalScroll
from textual.widgets import Header, Footer, Static, Label, Button
from textual.binding import Binding
from textual.reactive import reactive

from ..domain.model import (
    ControllerState, PadId, AppMode, OscEvent, PadMode, PadGroupName,
    Effect, SendOscEffect, SetLedEffect, SaveConfigEffect, LogEffect
)
from ..domain.fsm import (
    handle_pad_press, handle_osc_event,
    enter_learn_mode, cancel_learn_mode, finish_osc_recording,
    select_learn_command
)
from ..domain.blink import compute_blink_phase, compute_all_led_states, get_dimmed_color
from ..io.midi_launchpad import LaunchpadDevice, LaunchpadConfig, COLOR_PALETTE
from ..io.osc_synesthesia import OscManager, OscConfig
from ..io.config import ConfigManager, get_default_config_path

logger = logging.getLogger(__name__)


# =============================================================================
# COLOR MAPPING - Launchpad velocity to terminal colors (Rich markup)
# =============================================================================

# Map Launchpad color velocities to terminal RGB colors
# These approximate the actual Launchpad Mini Mk3 LED colors
LAUNCHPAD_TO_TERMINAL_COLOR = {
    0: "#1a1a1a",       # Off (dark gray to show empty slot)
    1: "#660000",       # Red dim
    3: "#ffffff",       # White
    5: "#ff0000",       # Red
    9: "#ff6600",       # Orange
    13: "#ffff00",      # Yellow
    17: "#006600",      # Green dim
    21: "#00ff00",      # Green
    37: "#00ffff",      # Cyan
    41: "#000066",      # Blue dim
    45: "#0066ff",      # Blue
    53: "#9900ff",      # Purple
    57: "#ff00ff",      # Pink/Magenta
}

# Named colors for the UI
NAMED_COLORS = {
    "off": (0, "#1a1a1a"),
    "red": (5, "#ff0000"),
    "red_dim": (1, "#660000"),
    "orange": (9, "#ff6600"),
    "yellow": (13, "#ffff00"),
    "green": (21, "#00ff00"),
    "green_dim": (17, "#006600"),
    "cyan": (37, "#00ffff"),
    "blue": (45, "#0066ff"),
    "blue_dim": (41, "#000066"),
    "purple": (53, "#9900ff"),
    "pink": (57, "#ff00ff"),
    "white": (3, "#ffffff"),
}


def velocity_to_rgb(velocity: int) -> str:
    """Convert Launchpad velocity to terminal RGB color."""
    if velocity in LAUNCHPAD_TO_TERMINAL_COLOR:
        return LAUNCHPAD_TO_TERMINAL_COLOR[velocity]

    # Interpolate for unknown velocities based on closest known
    known = sorted(LAUNCHPAD_TO_TERMINAL_COLOR.keys())
    for i, v in enumerate(known):
        if velocity < v:
            return LAUNCHPAD_TO_TERMINAL_COLOR[known[max(0, i-1)]]
    return LAUNCHPAD_TO_TERMINAL_COLOR[known[-1]]


def get_contrasting_text(bg_color: str) -> str:
    """Get contrasting text color (black or white) for readability."""
    # Parse hex color
    if bg_color.startswith("#"):
        r = int(bg_color[1:3], 16)
        g = int(bg_color[3:5], 16)
        b = int(bg_color[5:7], 16)
        # Calculate luminance
        luminance = (0.299 * r + 0.587 * g + 0.114 * b) / 255
        return "#000000" if luminance > 0.5 else "#ffffff"
    return "#ffffff"


# =============================================================================
# COLORFUL LAUNCHPAD GRID WIDGET
# =============================================================================

class ColorfulLaunchpadGrid(Static):
    """
    Visual representation of Launchpad 8x8 grid + top row + right column.

    Uses actual terminal colors to represent Launchpad LED colors.
    Clickable - selecting a pad in the TUI acts like pressing it on hardware.
    """

    state: reactive[ControllerState] = reactive(ControllerState)
    selected_pad: reactive[Optional[PadId]] = reactive(None)
    beat_pulse: reactive[bool] = reactive(False)

    def on_click(self, event) -> None:
        """Handle clicks on the grid to select pads."""
        event.stop()

        pad_id = self._pad_from_click(event.x, event.y)
        if not pad_id:
            return

        handler = getattr(self.app, "_handle_pad_press_async", None)
        if handler:
            asyncio.create_task(handler(pad_id))

    def _pad_from_click(self, x: int, y: int) -> Optional[PadId]:
        """Map click coordinates to a pad id based on ASCII grid layout."""
        # Header takes line 0, top row is line 1
        if y == 1:
            # Top row - each cell is 5 chars wide including separator
            pad_x = (x - 1) // 5
            if 0 <= pad_x < 8:
                return PadId(pad_x, -1)
            return None

        # Main grid starts at line 2
        if y < 2 or y > 9:
            return None

        pad_y = y - 2
        # Check if clicking on right column (after the 8 grid columns)
        col_x = (x - 1) // 5

        if col_x == 8:
            return PadId(8, pad_y)
        elif 0 <= col_x < 8:
            return PadId(col_x, pad_y)

        return None

    def render(self) -> str:
        """Render the Launchpad grid with actual colors."""
        lines = []

        # Header line
        lines.append("[bold cyan]╔═══ LAUNCHPAD MINI MK3 ════════════════════╗[/]")

        # Top row (y=-1) - special buttons
        top_line = "│"
        for x in range(8):
            pad_id = PadId(x, -1)
            cell = self._render_pad_cell(pad_id)
            top_line += cell
        top_line += "    │"  # Space for right column alignment
        lines.append(top_line)

        # Separator
        lines.append("├" + "────" * 8 + "─────┤")

        # Main grid (8x8) + right column
        for y in range(8):
            row = "│"
            for x in range(8):
                pad_id = PadId(x, y)
                cell = self._render_pad_cell(pad_id)
                row += cell

            # Right column
            right_pad = PadId(8, y)
            right_cell = self._render_pad_cell(right_pad)
            row += right_cell + "│"

            lines.append(row)

        # Bottom border
        lines.append("[bold cyan]╚══════════════════════════════════════════╝[/]")

        return "\n".join(lines)

    def _render_pad_cell(self, pad_id: PadId) -> str:
        """Render a single pad cell with color."""
        # Default unmapped appearance
        bg_color = "#1a1a1a"
        char = " · "
        is_selected = self.selected_pad == pad_id
        is_blinking = False

        if pad_id in self.state.pads:
            behavior = self.state.pads[pad_id]
            runtime = self.state.pad_runtime.get(pad_id)

            if runtime:
                # Get the appropriate color based on state
                if runtime.is_active or runtime.is_on:
                    color_vel = behavior.active_color
                    is_blinking = runtime.blink_enabled
                else:
                    color_vel = behavior.idle_color

                # Apply beat-based dimming for blinking pads
                if is_blinking and not self.beat_pulse:
                    color_vel = get_dimmed_color(color_vel)

                bg_color = velocity_to_rgb(color_vel)

                # Show indicator
                if runtime.is_active:
                    char = " ● "
                elif runtime.is_on:
                    char = " ◉ "
                else:
                    char = " ○ "
            else:
                # Has behavior but no runtime state
                bg_color = velocity_to_rgb(behavior.idle_color)
                char = " ○ "

        # Highlight selected pad in learn mode
        if is_selected:
            return f"[bold on #0066ff] ▶ [/]"

        # Apply background color to cell
        text_color = get_contrasting_text(bg_color)
        return f"[{text_color} on {bg_color}]{char}[/]"


# =============================================================================
# STATUS PANEL WITH ENHANCED INDICATORS
# =============================================================================

class StatusPanel(Static):
    """Shows connection status, app state, and helpful indicators."""

    launchpad_connected: reactive[bool] = reactive(False)
    osc_connected: reactive[bool] = reactive(False)
    osc_status: reactive[str] = reactive("Not connected")
    app_mode: reactive[AppMode] = reactive(AppMode.NORMAL)
    active_scene: reactive[Optional[str]] = reactive(None)
    active_preset: reactive[Optional[str]] = reactive(None)
    beat_pulse: reactive[bool] = reactive(False)
    mapped_pads: reactive[int] = reactive(0)

    def render(self) -> str:
        """Render status panel with visual indicators."""
        # Connection indicators
        lp_status = "[bold green]● CONNECTED[/]" if self.launchpad_connected else "[bold red]○ DISCONNECTED[/]"
        osc_status = "[bold green]● CONNECTED[/]" if self.osc_connected else "[bold red]○ DISCONNECTED[/]"

        # Beat indicator
        beat = "[bold yellow]♫[/]" if self.beat_pulse else "[dim]♪[/]"

        # Mode indicator with color
        mode_display = self._format_mode()

        lines = [
            "[bold cyan]╔════ STATUS ═════════════════╗[/]",
            f"│ [bold]Launchpad:[/] {lp_status}",
            f"│ [bold]OSC:[/]       {osc_status}",
            "│",
            f"│ [bold]Mode:[/]  {mode_display}",
            f"│ [bold]Beat:[/]  {beat}",
            "│",
            f"│ [bold]Scene:[/]  {self.active_scene or '[dim]None[/]'}",
            f"│ [bold]Preset:[/] {self.active_preset or '[dim]None[/]'}",
            "│",
            f"│ [bold]Mapped Pads:[/] {self.mapped_pads}/82",
            "[bold cyan]╚═════════════════════════════╝[/]",
        ]
        return "\n".join(lines)

    def _format_mode(self) -> str:
        """Format app mode with appropriate color and icon."""
        mode_map = {
            AppMode.NORMAL: ("[bold green]● NORMAL[/]", "Ready to perform"),
            AppMode.LEARN_WAIT_PAD: ("[bold yellow]◐ LEARNING[/]", "Select a pad..."),
            AppMode.LEARN_RECORD_OSC: ("[bold yellow]◑ RECORDING[/]", "Recording OSC..."),
            AppMode.LEARN_SELECT_MSG: ("[bold yellow]◒ CONFIGURE[/]", "Select command..."),
        }
        status, _ = mode_map.get(self.app_mode, ("[dim]Unknown[/]", ""))
        return status


# =============================================================================
# HELP PANEL - USER GUIDANCE
# =============================================================================

class HelpPanel(Static):
    """Displays contextual help and keyboard shortcuts."""

    app_mode: reactive[AppMode] = reactive(AppMode.NORMAL)

    def render(self) -> str:
        """Render contextual help based on current mode."""
        lines = ["[bold cyan]╔════ HELP ═══════════════════╗[/]"]

        if self.app_mode == AppMode.NORMAL:
            lines.extend([
                "│ [bold]Keyboard Shortcuts:[/]",
                "│  [cyan]L[/]   Enter Learn Mode",
                "│  [cyan]Q[/]   Quit Application",
                "│  [cyan]Esc[/] Cancel / Exit",
                "│",
                "│ [bold]Mouse:[/]",
                "│  Click pads to activate",
                "│",
                "│ [bold]Status:[/]",
                "│  [green]●[/] Active selector",
                "│  [yellow]◉[/] Toggle ON",
                "│  [dim]○[/] Inactive/OFF",
            ])

        elif self.app_mode == AppMode.LEARN_WAIT_PAD:
            lines.extend([
                "│ [bold yellow]⚡ LEARN MODE[/]",
                "│",
                "│ [bold]Step 1: Select Pad[/]",
                "│",
                "│ Click a pad on the grid",
                "│ or press it on hardware",
                "│ to configure it.",
                "│",
                "│ [cyan]Esc[/] Cancel learning",
            ])

        elif self.app_mode == AppMode.LEARN_RECORD_OSC:
            lines.extend([
                "│ [bold yellow]⚡ RECORDING OSC[/]",
                "│",
                "│ [bold]Step 2: Trigger Action[/]",
                "│",
                "│ In Synesthesia, click",
                "│ the scene/preset you",
                "│ want to map to this pad.",
                "│",
                "│ Recording for 5 seconds",
                "│ after first message...",
                "│",
                "│ [cyan]Esc[/] Cancel learning",
            ])

        elif self.app_mode == AppMode.LEARN_SELECT_MSG:
            lines.extend([
                "│ [bold yellow]⚡ SELECT COMMAND[/]",
                "│",
                "│ [bold]Step 3: Configure[/]",
                "│",
                "│ Use number keys 1-9",
                "│ to select a command.",
                "│",
                "│ Configuration will be",
                "│ saved automatically.",
                "│",
                "│ [cyan]Esc[/] Cancel learning",
            ])

        lines.append("[bold cyan]╚═════════════════════════════╝[/]")
        return "\n".join(lines)


# =============================================================================
# LEARN MODE PANEL - DETAILED PROGRESS
# =============================================================================

class LearnModePanel(Container):
    """Shows learn mode progress and recorded commands."""

    learn_state: reactive = reactive(None)
    app_mode: reactive[AppMode] = reactive(AppMode.NORMAL)

    def compose(self):
        """Compose the learn mode panel."""
        yield Static(id="learn_content")

    def watch_app_mode(self, new_mode: AppMode):
        self.update_display()

    def watch_learn_state(self, new_state):
        self.update_display()

    def update_display(self):
        """Update the learn mode display."""
        try:
            content = self.query_one("#learn_content", Static)
            content.update(self._render_content())
        except Exception:
            pass

    def _render_content(self) -> str:
        """Render learn mode content."""
        lines = ["[bold cyan]╔════ LEARN MODE ══════════════════════════╗[/]"]

        if self.app_mode == AppMode.NORMAL:
            lines.extend([
                "│ [dim]Press [cyan]L[/dim] to enter Learn Mode[/]",
                "│",
                "│ [dim]Learn Mode allows you to configure[/]",
                "│ [dim]pads by clicking in Synesthesia.[/]",
            ])

        elif self.app_mode == AppMode.LEARN_WAIT_PAD:
            lines.extend([
                "│ [bold yellow]⏳ Waiting for pad selection...[/]",
                "│",
                "│ Click a pad on the grid above or",
                "│ press a button on your Launchpad.",
            ])

        elif self.app_mode == AppMode.LEARN_RECORD_OSC:
            # Show recording progress
            from ..domain.model import LearnState
            learn_state = self.learn_state or LearnState()

            pad_str = str(learn_state.selected_pad) if learn_state.selected_pad else "?"

            if learn_state.record_start_time:
                elapsed = time.time() - learn_state.record_start_time
                remaining = max(0, 5.0 - elapsed)
                progress = int((elapsed / 5.0) * 20)
                bar = "█" * progress + "░" * (20 - progress)

                lines.extend([
                    f"│ [bold]Recording for pad {pad_str}[/]",
                    "│",
                    f"│ [cyan]{bar}[/] {remaining:.1f}s",
                    "│",
                    f"│ [bold]Captured:[/] {len(learn_state.recorded_osc_events)} OSC messages",
                ])
            else:
                lines.extend([
                    f"│ [bold]Selected pad: {pad_str}[/]",
                    "│",
                    "│ [yellow]Waiting for OSC message...[/]",
                    "│",
                    "│ Click something in Synesthesia",
                    "│ to start recording.",
                ])

        elif self.app_mode == AppMode.LEARN_SELECT_MSG:
            from ..domain.model import LearnState
            learn_state = self.learn_state or LearnState()

            lines.extend([
                "│ [bold green]Recording complete![/]",
                "│",
                f"│ [bold]Candidates:[/] {len(learn_state.candidate_commands)}",
                "│",
            ])

            # Show candidate commands
            for i, cmd in enumerate(learn_state.candidate_commands[:8]):
                # Truncate long addresses
                addr = cmd.address
                if len(addr) > 30:
                    addr = addr[:27] + "..."
                lines.append(f"│ [cyan]{i+1}[/] {addr}")

            if len(learn_state.candidate_commands) > 8:
                lines.append(f"│ [dim]... +{len(learn_state.candidate_commands) - 8} more[/]")

            if not learn_state.candidate_commands:
                lines.append("│ [red]No controllable commands recorded![/]")

        lines.append("[bold cyan]╚════════════════════════════════════════╝[/]")
        return "\n".join(lines)


# =============================================================================
# LOG PANEL
# =============================================================================

class LogPanel(VerticalScroll):
    """Scrolling log panel for events with colored output."""

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.logs: List[str] = []

    def add_log(self, message: str, level: str = "INFO"):
        """Add a log message with appropriate color."""
        color_map = {
            "INFO": "cyan",
            "SUCCESS": "green",
            "WARNING": "yellow",
            "ERROR": "red",
            "DEBUG": "dim"
        }
        color = color_map.get(level, "white")
        timestamp = time.strftime("%H:%M:%S")
        self.logs.append(f"[{color}]{timestamp}[/] {message}")

        # Keep last 100 logs
        if len(self.logs) > 100:
            self.logs.pop(0)

        self.update_display()

    def update_display(self):
        """Update log display."""
        self.remove_children()
        for log in self.logs[-15:]:  # Show last 15
            self.mount(Label(log))


# =============================================================================
# MAIN APPLICATION
# =============================================================================

class LaunchpadSynesthesiaApp(App):
    """Main Textual application with colorful grid and user guidance."""

    TITLE = "Launchpad Synesthesia Control"
    SUB_TITLE = "Press L to learn, Q to quit"

    CSS = """
    Screen {
        layout: grid;
        grid-size: 2 2;
        grid-columns: 3fr 1fr;
        grid-rows: 2fr 1fr;
    }

    #main_container {
        row-span: 2;
        padding: 0 1;
    }

    #grid_container {
        height: auto;
        padding: 0;
    }

    #right_panel {
        padding: 0 1;
    }

    #log_container {
        border: solid cyan;
        padding: 0 1;
        height: 100%;
    }

    .panel-title {
        text-align: center;
        text-style: bold;
        color: cyan;
    }

    LogPanel {
        height: 100%;
    }
    """

    BINDINGS = [
        Binding("l", "learn", "Learn Mode"),
        Binding("escape", "cancel_learn", "Cancel"),
        Binding("q", "quit", "Quit"),
        Binding("1", "select_command(1)", "Select 1", show=False),
        Binding("2", "select_command(2)", "Select 2", show=False),
        Binding("3", "select_command(3)", "Select 3", show=False),
        Binding("4", "select_command(4)", "Select 4", show=False),
        Binding("5", "select_command(5)", "Select 5", show=False),
        Binding("6", "select_command(6)", "Select 6", show=False),
        Binding("7", "select_command(7)", "Select 7", show=False),
        Binding("8", "select_command(8)", "Select 8", show=False),
        Binding("9", "select_command(9)", "Select 9", show=False),
    ]

    def __init__(self, time_func: Optional[Callable[[], float]] = None):
        """
        Initialize the app.

        Args:
            time_func: Optional time function for testing (defaults to time.time)
        """
        super().__init__()
        self.state = ControllerState()
        self.launchpad: Optional[LaunchpadDevice] = None
        self.osc: Optional[OscManager] = None
        self.config_manager = ConfigManager(get_default_config_path())
        self._blink_task: Optional[asyncio.Task] = None
        self._reconnect_task: Optional[asyncio.Task] = None
        self._learn_timer_task: Optional[asyncio.Task] = None
        self._time_func = time_func or time.time

    def compose(self) -> ComposeResult:
        """Create UI layout."""
        yield Header()

        with Vertical(id="main_container"):
            with Container(id="grid_container"):
                yield ColorfulLaunchpadGrid(id="launchpad_grid")

            yield LearnModePanel(id="learn_panel")

        with Vertical(id="right_panel"):
            yield StatusPanel(id="status_panel")
            yield HelpPanel(id="help_panel")

        with Container(id="log_container"):
            yield Label("[bold cyan]═══ EVENT LOG ═══[/]", classes="panel-title")
            yield LogPanel(id="log_panel")

        yield Footer()

    async def on_mount(self) -> None:
        """Initialize on mount."""
        self.add_log("Starting Launchpad Synesthesia Control...", "INFO")

        # Load config
        loaded_state = self.config_manager.load()
        if loaded_state:
            self.state = loaded_state
            self.add_log(f"Loaded {len(self.state.pads)} pad configurations", "SUCCESS")
        else:
            self.add_log("No configuration found - starting fresh", "INFO")

        # Initialize Launchpad
        await self._init_launchpad()

        # Initialize OSC
        await self._init_osc()

        # Start background tasks
        self._blink_task = asyncio.create_task(self._blink_loop())
        self._reconnect_task = asyncio.create_task(self._reconnect_loop())
        self._learn_timer_task = asyncio.create_task(self._learn_timer_loop())

        # Update UI
        self._update_ui()

        self.add_log("Ready! Press L to enter Learn Mode", "SUCCESS")

    async def _init_launchpad(self):
        """Initialize Launchpad connection with error handling."""
        try:
            self.launchpad = LaunchpadDevice(LaunchpadConfig(auto_detect=True))

            connected = await self.launchpad.connect()
            if connected:
                self.launchpad.set_pad_callback(self._on_pad_press)
                asyncio.create_task(self.launchpad.start_listening())
                self.add_log("Launchpad connected", "SUCCESS")

                # Restore LED states for mapped pads
                await self._restore_led_states()
            else:
                self.add_log("Launchpad not found - using virtual grid", "WARNING")
        except Exception as e:
            self.add_log(f"Launchpad init error: {e}", "ERROR")

        self._update_connection_status()

    async def _restore_led_states(self):
        """Restore LED states for all mapped pads."""
        if not self.launchpad or not self.launchpad.is_connected():
            return

        for pad_id, behavior in self.state.pads.items():
            runtime = self.state.pad_runtime.get(pad_id)
            color = runtime.current_color if runtime else behavior.idle_color
            self.launchpad.set_led(pad_id, color, blink=False)

    async def _init_osc(self):
        """Initialize OSC connection with fixed ports."""
        send_port = 9000
        receive_port = 8000

        try:
            if self.osc:
                await self.osc.stop()
        except Exception:
            pass

        try:
            self.osc = OscManager(OscConfig(
                host="127.0.0.1",
                send_port=send_port,
                receive_port=receive_port
            ))

            connected = await self.osc.connect()
            if connected:
                self.osc.set_osc_callback(self._on_osc_event)
                self.add_log(f"OSC connected (send:{send_port}, recv:{receive_port})", "SUCCESS")
            else:
                self.add_log("OSC not available - will retry", "WARNING")
        except Exception as e:
            self.add_log(f"OSC init error: {e}", "ERROR")

        self._update_connection_status()

    async def _reconnect_loop(self):
        """Periodically check and reconnect devices."""
        while True:
            await asyncio.sleep(5)

            try:
                # Try to reconnect Launchpad
                if self.launchpad and not self.launchpad.is_connected():
                    await self._init_launchpad()

                # Try to reconnect OSC
                if self.osc and not self.osc.is_connected():
                    await self._init_osc()
            except Exception as e:
                logger.debug(f"Reconnect error: {e}")

    async def _learn_timer_loop(self):
        """Check learn mode recording timer."""
        while True:
            await asyncio.sleep(0.1)

            try:
                if self.state.app_mode == AppMode.LEARN_RECORD_OSC:
                    if self.state.learn_state.record_start_time:
                        elapsed = self._time_func() - self.state.learn_state.record_start_time

                        if elapsed >= 5.0:
                            # Time's up - finish recording
                            new_state, effects = finish_osc_recording(self.state)
                            self.state = new_state
                            await self._execute_effects(effects)
                            self._update_ui()

                # Update learn panel display periodically
                if self.state.app_mode in (AppMode.LEARN_RECORD_OSC, AppMode.LEARN_WAIT_PAD, AppMode.LEARN_SELECT_MSG):
                    self._update_ui()
            except Exception as e:
                logger.debug(f"Timer loop error: {e}")

    def _on_pad_press(self, pad_id: PadId, velocity: int):
        """Handle Launchpad pad press (called from MIDI thread)."""
        asyncio.create_task(self._handle_pad_press_async(pad_id))

    async def _handle_pad_press_async(self, pad_id: PadId):
        """Handle pad press in async context."""
        self.add_log(f"Pad pressed: {pad_id}", "DEBUG")

        # Process through FSM
        new_state, effects = handle_pad_press(self.state, pad_id)
        self.state = new_state

        # Execute effects
        await self._execute_effects(effects)

        # Update UI
        self._update_ui()

    def _on_osc_event(self, event: OscEvent):
        """Handle OSC event (called from OSC thread)."""
        asyncio.create_task(self._handle_osc_event_async(event))

    async def _handle_osc_event_async(self, event: OscEvent):
        """Handle OSC event in async context."""
        # Log controllable messages
        from ..domain.model import OscCommand
        if OscCommand.is_controllable(event.address):
            self.add_log(f"OSC: {event.address}", "DEBUG")

        # Process through FSM
        new_state, effects = handle_osc_event(self.state, event)
        self.state = new_state

        # Execute effects
        await self._execute_effects(effects)

        # Update UI
        self._update_ui()

    async def _execute_effects(self, effects: List[Effect]):
        """Execute side effects."""
        for effect in effects:
            try:
                if isinstance(effect, SendOscEffect):
                    if self.osc:
                        self.osc.send(effect.command)

                elif isinstance(effect, SetLedEffect):
                    if self.launchpad and self.launchpad.is_connected():
                        self.launchpad.set_led(effect.pad_id, effect.color, effect.blink)

                elif isinstance(effect, SaveConfigEffect):
                    self.config_manager.save(self.state)
                    self.add_log("Configuration saved", "SUCCESS")

                elif isinstance(effect, LogEffect):
                    self.add_log(effect.message, effect.level)
            except Exception as e:
                self.add_log(f"Effect error: {e}", "ERROR")

    async def _blink_loop(self):
        """Update blinking LEDs based on beat."""
        while True:
            await asyncio.sleep(0.05)  # 20 FPS

            try:
                if not self.launchpad or not self.launchpad.is_connected():
                    continue

                # Compute blink phase
                blink_phase = compute_blink_phase(self.state.beat_pulse, self.state.beat_phase)

                # Update LEDs that need blinking
                led_states = compute_all_led_states(self.state, blink_phase)

                for pad_id, (color, is_lit) in led_states.items():
                    runtime = self.state.pad_runtime.get(pad_id)
                    if runtime and runtime.blink_enabled:
                        actual_color = color if is_lit else get_dimmed_color(color)
                        self.launchpad.set_led(pad_id, actual_color, blink=False)
            except Exception as e:
                logger.debug(f"Blink loop error: {e}")

    def _update_ui(self):
        """Update all UI widgets with current state."""
        try:
            # Update grid
            grid = self.query_one("#launchpad_grid", ColorfulLaunchpadGrid)
            grid.state = self.state
            grid.beat_pulse = self.state.beat_pulse
            if self.state.app_mode == AppMode.LEARN_RECORD_OSC:
                grid.selected_pad = self.state.learn_state.selected_pad
            else:
                grid.selected_pad = None

            # Update status
            status = self.query_one("#status_panel", StatusPanel)
            status.app_mode = self.state.app_mode
            status.active_scene = self.state.active_scene
            status.active_preset = self.state.active_preset
            status.beat_pulse = self.state.beat_pulse
            status.mapped_pads = len(self.state.pads)

            # Update help panel
            help_panel = self.query_one("#help_panel", HelpPanel)
            help_panel.app_mode = self.state.app_mode

            # Update learn panel
            learn_panel = self.query_one("#learn_panel", LearnModePanel)
            learn_panel.app_mode = self.state.app_mode
            learn_panel.learn_state = self.state.learn_state
        except Exception as e:
            logger.debug(f"UI update error: {e}")

    def _update_connection_status(self):
        """Update connection status in UI."""
        try:
            status = self.query_one("#status_panel", StatusPanel)
            status.launchpad_connected = self.launchpad.is_connected() if self.launchpad else False
            status.osc_connected = self.osc.is_connected() if self.osc else False
        except Exception:
            pass

    def add_log(self, message: str, level: str = "INFO"):
        """Add log message."""
        try:
            log_panel = self.query_one("#log_panel", LogPanel)
            log_panel.add_log(message, level)
        except Exception:
            pass  # UI not ready yet

    def action_learn(self):
        """Enter learn mode."""
        new_state, effects = enter_learn_mode(self.state)
        self.state = new_state
        asyncio.create_task(self._execute_effects(effects))
        self._update_ui()
        self.add_log("Entered Learn Mode - select a pad", "INFO")

    def action_cancel_learn(self):
        """Cancel learn mode."""
        if self.state.app_mode != AppMode.NORMAL:
            new_state, effects = cancel_learn_mode(self.state)
            self.state = new_state
            asyncio.create_task(self._execute_effects(effects))
            self._update_ui()
            self.add_log("Learn mode cancelled", "INFO")

    def action_select_command(self, index: int):
        """Select a command by number (1-9)."""
        if self.state.app_mode != AppMode.LEARN_SELECT_MSG:
            return

        cmd_index = index - 1  # Convert 1-based to 0-based
        if 0 <= cmd_index < len(self.state.learn_state.candidate_commands):
            # Auto-detect mode and group from address
            cmd = self.state.learn_state.candidate_commands[cmd_index]
            mode, group = self._infer_mode_and_group(cmd.address)

            # Use default colors
            idle_color = 0  # Off
            active_color = 21  # Green

            # Infer label from address
            label = cmd.address.split("/")[-1]

            new_state, effects = select_learn_command(
                self.state,
                cmd_index,
                mode,
                group,
                idle_color,
                active_color,
                label
            )
            self.state = new_state
            asyncio.create_task(self._execute_effects(effects))
            self._update_ui()
            self.add_log(f"Configured pad with: {cmd.address}", "SUCCESS")

    def _infer_mode_and_group(self, address: str) -> tuple:
        """Infer pad mode and group from OSC address."""
        if address.startswith("/scenes/"):
            return PadMode.SELECTOR, PadGroupName.SCENES
        elif address.startswith("/presets/") or address.startswith("/favslots/"):
            return PadMode.SELECTOR, PadGroupName.PRESETS
        elif address.startswith("/controls/meta/"):
            return PadMode.SELECTOR, PadGroupName.COLORS
        elif address.startswith("/playlist/"):
            return PadMode.ONE_SHOT, None
        else:
            return PadMode.ONE_SHOT, None


def run_app():
    """Run the application."""
    # Setup logging
    logging.basicConfig(
        level=logging.WARNING,  # Reduce noise
        format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
    )

    app = LaunchpadSynesthesiaApp()
    app.run()


if __name__ == "__main__":
    run_app()
