"""
Launchpad Synesthesia Control - Textual TUI

Main application with async event handling and graceful degradation.
"""

import asyncio
import logging
import time
from pathlib import Path
from typing import Optional, List

from textual import work
from textual.app import App, ComposeResult
from textual.containers import Container, Horizontal, Vertical, VerticalScroll
from textual.widgets import Header, Footer, Static, Label, Button
from textual.binding import Binding
from textual.reactive import reactive

from launchpad_osc_lib import (
    ControllerState, ButtonId, AppMode, OscEvent, PadMode, PadGroupName,
    Effect, SendOscEffect, SetLedEffect, SaveConfigEffect, LogEffect,
    OscCommand, COLOR_PALETTE,
    handle_pad_press, handle_pad_release, handle_osc_event,
    enter_learn_mode, cancel_learn_mode, finish_osc_recording,
    select_learn_command,
    SynesthesiaOscManager,
    compute_blink_phase, compute_all_led_states, get_dimmed_color,
)
from ..io.emulator import SmartLaunchpad, LaunchpadConfig
from ..io.config import ConfigManager, get_default_config_path
from .command_selection_screen import CommandSelectionScreen

logger = logging.getLogger(__name__)


# =============================================================================
# TUI WIDGETS
# =============================================================================

class LaunchpadGrid(Static):
    """Visual representation of Launchpad 8x8 grid + top row + right column.
    
    Clickable - selecting a pad in the TUI acts like pressing it on hardware.
    """
    
    state: reactive[ControllerState] = reactive(ControllerState)
    
    # Add message handler for clicks
    BINDINGS = [
        # No bindings needed - will handle mouse clicks
    ]
    
    def on_click(self, event) -> None:
        """Handle clicks on the grid to select pads."""
        event.stop()
        
        pad_id = self._pad_from_click(event.x, event.y)
        if not pad_id:
            return
        
        handler = getattr(self.app, "_handle_pad_press_async", None)
        if handler:
            asyncio.create_task(handler(pad_id))
    
    def _pad_from_click(self, x: int, y: int) -> Optional[ButtonId]:
        """Map click coordinates to a pad id based on ASCII grid layout."""
        # Skip the hint line
        if y == 1:
            pad_x = self._column_to_pad(x, include_right_column=False)
            if pad_x is not None and 0 <= pad_x < 8:
                return ButtonId(pad_x, -1)
            return None
        
        # Each row occupies two lines: pad row then separator
        if y < 2 or y > 16 or y % 2 != 0:
            return None
        
        pad_y = (y - 2) // 2
        pad_x = self._column_to_pad(x, include_right_column=True)
        if pad_x is None or not (0 <= pad_x <= 8):
            return None
        
        return ButtonId(pad_x, pad_y)
    
    def _column_to_pad(self, x: int, include_right_column: bool) -> Optional[int]:
        """Convert horizontal click position into pad column index."""
        if x < 2:
            return None
        
        if include_right_column and x >= 33:
            return 8  # Right column pads have narrower cell
        
        pad_x = (x - 2) // 4
        if 0 <= pad_x < 8:
            return pad_x
        return None
    
    def render(self) -> str:
        """Render the Launchpad grid as ASCII art with clickable indicators."""
        lines = []
        
        # Title with hint
        lines.append("[dim]Click pads to select in Learn Mode[/]")
        
        # Top row (y=-1)
        top_row = "╔"
        for x in range(8):
            pad_id = ButtonId(x, -1)
            char = self._get_pad_char(pad_id)
            top_row += f"═{char}═╦" if x < 7 else f"═{char}═╗"
        lines.append(top_row)
        
        # Main grid (8x8)
        for y in range(8):
            row = "║"
            for x in range(8):
                pad_id = ButtonId(x, y)
                char = self._get_pad_char(pad_id)
                row += f" {char} ║"
            
            # Right column
            right_pad = ButtonId(8, y)
            right_char = self._get_pad_char(right_pad)
            row += f" {right_char}"
            
            lines.append(row)
            
            # Separator
            if y < 7:
                sep = "╠"
                for x in range(8):
                    sep += "═══╬" if x < 7 else "═══╣"
                lines.append(sep)
        
        # Bottom border
        bottom = "╚"
        for x in range(8):
            bottom += "═══╩" if x < 7 else "═══╝"
        lines.append(bottom)
        
        return "\n".join(lines)
    
    def _get_pad_char(self, pad_id: ButtonId) -> str:
        """Get character for pad based on state (no blinking in TUI)."""
        if pad_id not in self.state.pads:
            return "·"  # Unmapped pad
        
        behavior = self.state.pads[pad_id]
        runtime = self.state.pad_runtime.get(pad_id)
        
        if not runtime:
            return "○"
        
        # Show static active/inactive (no blinking in TUI as per requirement)
        if runtime.is_active or runtime.is_on:
            return "●"  # Active/On
        else:
            return "○"  # Inactive/Off


class StatusPanel(Static):
    """Shows connection status and current state."""
    
    launchpad_connected: reactive[bool] = reactive(False)
    osc_connected: reactive[bool] = reactive(False)
    osc_status: reactive[str] = reactive("Not connected")
    app_mode: reactive[AppMode] = reactive(AppMode.NORMAL)
    active_scene: reactive[Optional[str]] = reactive(None)
    active_preset: reactive[Optional[str]] = reactive(None)
    beat_pulse: reactive[bool] = reactive(False)
    
    def render(self) -> str:
        """Render status panel."""
        lines = [
            "╔═══ CONNECTION STATUS ═══╗",
            f"║ Launchpad: {'[green]●[/] Connected' if self.launchpad_connected else '[red]○[/] Disconnected'}",
            f"║ OSC: {'[green]●[/]' if self.osc_connected else '[red]○[/]'} {self.osc_status}",
            "║ [dim]Listen: :9999 (← Synesthesia)[/]",
            "║ [dim]Send: :7777 (→ Synesthesia)[/]",
            "╠═══ SYNESTHESIA STATE ═══╣",
            f"║ Scene: {self.active_scene or 'None'}",
            f"║ Preset: {self.active_preset or 'None'}",
            f"║ Beat: {'[yellow]♪[/]' if self.beat_pulse else '♪'}",
            "╠═══ APP MODE ═══════════╣",
            f"║ Mode: {self._format_mode()}",
            "╚═════════════════════════╝",
        ]
        return "\n".join(lines)
    
    def _format_mode(self) -> str:
        """Format app mode for display."""
        if self.app_mode == AppMode.NORMAL:
            return "[green]Normal[/]"
        elif self.app_mode == AppMode.LEARN_WAIT_PAD:
            return "[yellow]Learn: Select Pad[/]"
        elif self.app_mode == AppMode.LEARN_RECORD_OSC:
            return "[yellow]Learn: Recording OSC[/]"
        elif self.app_mode == AppMode.LEARN_SELECT_MSG:
            return "[yellow]Learn: Select Message[/]"
        return str(self.app_mode.name)


class OscMonitorPanel(VerticalScroll):
    """
    Shows ALL OSC messages from Synesthesia, grouped by path.

    Performance optimized for high message rates (1000+ msg/sec):
    - Groups by path, shows only latest value
    - Throttles UI updates to max 2-3 per second
    - Dictionary updates are O(1), UI updates are batched
    """

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        # Track messages by path: {address: {'args': [...], 'timestamp': float, 'count': int, 'controllable': bool}}
        self.messages_by_path: dict = {}
        self.total_message_count = 0
        self.last_update_time = 0
        self.update_throttle = 0.5  # Update display max once per 500ms (2x per second)
        self.needs_update = False

    def add_osc_message(self, address: str, args: list):
        """
        Add ANY OSC message (grouped by path, shows latest value).

        This method is called on EVERY OSC message, so must be fast.
        Dictionary updates are O(1) and non-blocking.
        UI updates are throttled and batched.
        """
        import time
        # OscCommand is already imported at module level from launchpad_osc_lib

        # Increment total counter (fast)
        self.total_message_count += 1

        # Update or create entry for this path (O(1) dict operation, fast)
        current_time = time.time()
        if address in self.messages_by_path:
            self.messages_by_path[address]['args'] = args
            self.messages_by_path[address]['timestamp'] = current_time
            self.messages_by_path[address]['count'] += 1
        else:
            self.messages_by_path[address] = {
                'args': args,
                'timestamp': current_time,
                'count': 1,
                'controllable': OscCommand.is_controllable(address)
            }

        # Mark that we need an update, but don't update immediately
        self.needs_update = True

        # Throttle display updates to avoid blocking on high message rates
        # At 10,000 msg/sec with 500ms throttle, UI updates only 2x per second
        if current_time - self.last_update_time >= self.update_throttle:
            if self.needs_update:
                self.update_display()
                self.last_update_time = current_time
                self.needs_update = False

    def update_display(self):
        """Update OSC message display."""
        self.remove_children()

        if not self.messages_by_path:
            self.mount(Label("[dim]Waiting for OSC messages...[/]"))
            self.mount(Label(f"[dim]Total received: {self.total_message_count}[/]"))
            return

        # Sort by most recently updated (newest first)
        sorted_paths = sorted(
            self.messages_by_path.items(),
            key=lambda x: x[1]['timestamp'],
            reverse=True
        )

        # Header with stats
        unique_paths = len(self.messages_by_path)
        self.mount(Label(
            f"[bold]Total: {self.total_message_count}[/] "
            f"[dim]Unique: {unique_paths} (✓=controllable ·=other)[/]"
        ))

        # Show top 20 most recently updated paths
        for address, data in sorted_paths[:20]:
            # Color code: controllable = green, non-controllable = cyan
            if data['controllable']:
                color = "green"
                marker = "✓"
            else:
                color = "cyan"
                marker = "·"

            # Format: marker + address + args + count
            args_str = f" {data['args']}" if data['args'] else " []"
            count_str = f" [dim]×{data['count']}[/]" if data['count'] > 1 else ""

            msg = f"[{color}]{marker} {address}[/][dim]{args_str}[/]{count_str}"
            self.mount(Label(msg))


class LogPanel(VerticalScroll):
    """Scrolling log panel for events."""

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.logs: List[str] = []

    def add_log(self, message: str, level: str = "INFO"):
        """Add a log message."""
        color_map = {
            "INFO": "cyan",
            "WARNING": "yellow",
            "ERROR": "red",
            "DEBUG": "dim"
        }
        color = color_map.get(level, "white")
        self.logs.append(f"[{color}]{level}:[/] {message}")

        # Keep last 100 logs
        if len(self.logs) > 100:
            self.logs.pop(0)

        self.update_display()

    def update_display(self):
        """Update log display."""
        self.remove_children()
        for log in self.logs[-20:]:  # Show last 20
            self.mount(Label(log))


# =============================================================================
# MAIN APPLICATION
# =============================================================================

class LaunchpadSynesthesiaApp(App):
    """Main Textual application."""
    
    CSS = """
    Screen {
        layout: grid;
        grid-size: 3 4;
        grid-columns: 2fr 1fr 1fr;
        grid-rows: 2fr 1fr 1fr 1fr;
    }

    #grid_container {
        column-span: 2;
        row-span: 3;
        border: solid green;
        padding: 1;
    }

    #status_container {
        border: solid cyan;
        padding: 1;
    }

    #osc_monitor_container {
        border: solid magenta;
        padding: 1;
    }

    #learn_mode_container {
        border: solid yellow;
        padding: 1;
    }

    #log_container {
        column-span: 3;
        border: solid blue;
        padding: 1;
        height: 100%;
    }

    .panel-title {
        text-align: center;
        text-style: bold;
        color: cyan;
    }
    """
    
    BINDINGS = [
        Binding("l", "learn", "Learn Mode"),
        Binding("escape", "cancel_learn", "Cancel Learn"),
        Binding("q", "quit", "Quit"),
    ]
    
    def __init__(self):
        super().__init__()
        self.state = ControllerState()
        self.launchpad: Optional[SmartLaunchpad] = None
        self.osc: Optional[SynesthesiaOscManager] = None
        self.config_manager = ConfigManager(get_default_config_path())
        self._blink_task: Optional[asyncio.Task] = None
        self._reconnect_task: Optional[asyncio.Task] = None
    
    def compose(self) -> ComposeResult:
        """Create UI layout."""
        from .learn_ui import LearnModePanel

        yield Header()

        with Container(id="grid_container"):
            yield Label("Launchpad Mini Mk3", classes="panel-title")
            yield LaunchpadGrid(id="launchpad_grid")

        with Container(id="status_container"):
            yield StatusPanel(id="status_panel")

        with Container(id="osc_monitor_container"):
            yield Label("OSC Monitor (ALL Messages)", classes="panel-title")
            yield OscMonitorPanel(id="osc_monitor")

        with Container(id="learn_mode_container"):
            yield LearnModePanel(id="learn_panel")

        with Container(id="log_container"):
            yield Label("Event Log", classes="panel-title")
            yield LogPanel(id="log_panel")

        yield Footer()
    
    async def on_mount(self) -> None:
        """Initialize on mount."""
        # Load config
        loaded_state = self.config_manager.load()
        if loaded_state:
            self.state = loaded_state
            self.add_log("Loaded configuration", "INFO")
        else:
            self.add_log("No configuration found - starting fresh", "INFO")
        
        # Initialize Launchpad
        await self._init_launchpad()
        
        # Initialize OSC
        await self._init_osc()
        
        # Start blink loop
        self._blink_task = asyncio.create_task(self._blink_loop())
        
        # Start reconnection loop
        self._reconnect_task = asyncio.create_task(self._reconnect_loop())
        
        # Start learn mode timer loop
        self._learn_timer_task = asyncio.create_task(self._learn_timer_loop())
        
        # Update UI
        self._update_ui()

        # Default focus away from port inputs so app doesn't feel stuck there
        try:
            self.set_focus("#launchpad_grid")
        except Exception:
            pass
    
    async def _init_launchpad(self):
        """Initialize Launchpad connection using SmartLaunchpad."""
        self.launchpad = SmartLaunchpad(config=LaunchpadConfig(auto_detect=True))
        
        connected = await self.launchpad.connect()
        if connected:
            self.launchpad.set_pad_callback(self._on_pad_press)
            self.launchpad.set_pad_release_callback(self._on_pad_release)
            # Start listening in background
            asyncio.create_task(self.launchpad.start_listening())
            self.add_log("Launchpad connected", "INFO")
        else:
            self.add_log("Launchpad not found - using emulator", "WARNING")
            # SmartLaunchpad falls back to emulator automatically
        
        self._update_connection_status()
    
    async def _init_osc(self):
        """Initialize OSC connection using library's SynesthesiaOscManager."""
        if self.osc:
            try:
                await self.osc.stop()
            except Exception:
                pass

        # SynesthesiaOscManager uses default ports (7777/9999) and auto-reconnect
        self.osc = SynesthesiaOscManager(auto_reconnect_interval=10.0)
        
        connected = await self.osc.connect()
        if connected:
            # Register for monitor messages (filtered - no noisy audio spam)
            self.osc.add_monitor_listener(self._on_osc_event)
            self.add_log(f"OSC connected: {self.osc.status}", "INFO")
        else:
            self.add_log("OSC not available - auto-reconnect enabled", "WARNING")
        
        self._update_connection_status()
    
    async def _reconnect_loop(self):
        """Periodically check and reconnect devices."""
        while True:
            await asyncio.sleep(5)
            
            # Try to reconnect Launchpad (OSC auto-reconnect is handled by library)
            if self.launchpad and not self.launchpad.is_connected():
                await self._init_launchpad()
            
            # Update connection status display
            self._update_connection_status()
    
    async def _learn_timer_loop(self):
        """Check learn mode recording timer."""
        # finish_osc_recording is already imported at module level from launchpad_osc_lib

        previous_mode = AppMode.NORMAL

        while True:
            await asyncio.sleep(0.1)  # Check every 100ms

            if self.state.app_mode == AppMode.LEARN_RECORD_OSC:
                if self.state.learn_state.record_start_time:
                    elapsed = time.time() - self.state.learn_state.record_start_time

                    if elapsed >= 5.0:
                        # Time's up - finish recording
                        new_state, effects = finish_osc_recording(self.state)
                        self.state = new_state
                        await self._execute_effects(effects)
                        self._update_ui()

            # Detect transition to LEARN_SELECT_MSG and show modal via worker
            if self.state.app_mode == AppMode.LEARN_SELECT_MSG and previous_mode != AppMode.LEARN_SELECT_MSG:
                # Must use run_worker for push_screen_wait to work
                self._show_command_selection_worker()

            previous_mode = self.state.app_mode

            # Update learn panel timer display
            if self.state.app_mode in (AppMode.LEARN_RECORD_OSC, AppMode.LEARN_WAIT_PAD, AppMode.LEARN_SELECT_MSG):
                self._update_ui()

    @work(exclusive=True)
    async def _show_command_selection_worker(self):
        """Worker wrapper for showing command selection modal."""
        await self._show_command_selection_modal()
    
    def _on_pad_press(self, pad_id: ButtonId, velocity: int):
        """Handle Launchpad pad press (called from MIDI thread)."""
        # Schedule in main event loop
        asyncio.create_task(self._handle_pad_press_async(pad_id))
    
    def _on_pad_release(self, pad_id: ButtonId):
        """Handle Launchpad pad release (called from MIDI thread)."""
        # Schedule in main event loop
        asyncio.create_task(self._handle_pad_release_async(pad_id))
    
    async def _handle_pad_press_async(self, pad_id: ButtonId):
        """Handle pad press in async context."""
        self.add_log(f"Pad pressed: {pad_id}", "DEBUG")
        
        # Process through FSM
        new_state, effects = handle_pad_press(self.state, pad_id)
        self.state = new_state
        
        # Execute effects
        await self._execute_effects(effects)
        
        # Update UI
        self._update_ui()
    
    async def _handle_pad_release_async(self, pad_id: ButtonId):
        """Handle pad release in async context (for PUSH mode)."""
        # Process through FSM - only PUSH mode pads respond to release
        new_state, effects = handle_pad_release(self.state, pad_id)
        self.state = new_state
        
        # Execute effects
        await self._execute_effects(effects)
        
        # Update UI
        self._update_ui()
    
    def _on_osc_event(self, event: OscEvent):
        """Handle OSC event (called from OSC thread)."""
        # Schedule in main event loop
        asyncio.create_task(self._handle_osc_event_async(event))
    
    async def _handle_osc_event_async(self, event: OscEvent):
        """
        Handle OSC event in async context.

        Performance note: Uses monitor_listener which filters noisy audio.
        - Skip debug logging (expensive string formatting)
        - Use fast O(1) dictionary updates in monitor panel
        - Throttle UI updates to 2x per second
        """
        # Update OSC monitor (fast O(1) dict update, throttled UI)
        try:
            osc_monitor = self.query_one("#osc_monitor", OscMonitorPanel)
            osc_monitor.add_osc_message(event.address, event.args)
        except Exception as e:
            # Only log errors, not every message
            self.add_log(f"OSC monitor error: {e}", "ERROR")

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
            if isinstance(effect, SendOscEffect):
                if self.osc:
                    self.add_log(f"OSC TX: {effect.command.address} {effect.command.args}", "DEBUG")
                    self.osc.send(effect.command)
                else:
                    self.add_log(f"OSC not connected - would send: {effect.command.address}", "WARNING")
            
            elif isinstance(effect, SetLedEffect):
                if self.launchpad and self.launchpad.is_connected():
                    # Actual color depends on blink state
                    color = effect.color if not effect.blink else effect.color
                    self.launchpad.set_led(effect.pad_id, color, effect.blink)
            
            elif isinstance(effect, SaveConfigEffect):
                self.config_manager.save(self.state)
            
            elif isinstance(effect, LogEffect):
                self.add_log(effect.message, effect.level)
    
    async def _blink_loop(self):
        """Update blinking LEDs based on beat."""
        while True:
            await asyncio.sleep(0.05)  # 20 FPS for LED updates
            
            if not self.launchpad or not self.launchpad.is_connected():
                continue
            
            # Compute blink phase
            blink_phase = compute_blink_phase(self.state.beat_pulse, self.state.beat_phase)
            
            # Update LEDs that need blinking
            led_states = compute_all_led_states(self.state, blink_phase)
            
            for pad_id, (color, is_lit) in led_states.items():
                runtime = self.state.pad_runtime.get(pad_id)
                if runtime and runtime.blink_enabled:
                    # Apply dimming for off-phase
                    actual_color = color if is_lit else get_dimmed_color(color)
                    self.launchpad.set_led(pad_id, actual_color, blink=False)
    
    def _update_ui(self):
        """Update all UI widgets with current state."""
        try:
            # Update grid
            grid = self.query_one("#launchpad_grid", LaunchpadGrid)
            grid.state = self.state
        except Exception:
            pass  # Grid not mounted yet (e.g., during modal screens)
        
        try:
            # Update status
            status = self.query_one("#status_panel", StatusPanel)
            status.app_mode = self.state.app_mode
            status.active_scene = self.state.active_scene
            status.active_preset = self.state.active_preset
            status.beat_pulse = self.state.beat_pulse
        except Exception:
            pass  # Status panel not mounted yet
        
        # Update learn panel
        try:
            from .learn_ui import LearnModePanel
            learn_panel = self.query_one("#learn_panel", LearnModePanel)
            learn_panel.app_mode = self.state.app_mode
            learn_panel.learn_state = self.state.learn_state
        except Exception:
            pass  # Learn panel might not be mounted yet
    
    def _update_connection_status(self):
        """Update connection status in UI."""
        try:
            status = self.query_one("#status_panel", StatusPanel)
            status.launchpad_connected = self.launchpad.is_connected() if self.launchpad else False
            status.osc_connected = self.osc.is_connected() if self.osc else False
            status.osc_status = self.osc.status if self.osc else "Not initialized"
        except Exception:
            pass  # Status panel not mounted yet
    
    def add_log(self, message: str, level: str = "INFO"):
        """Add log message."""
        try:
            log_panel = self.query_one("#log_panel", LogPanel)
            log_panel.add_log(message, level)
        except:
            # UI not ready yet
            pass

    async def _show_command_selection_modal(self):
        """Show command selection modal with edge-case handling."""
        # Edge case: No OSC messages received
        if not self.state.learn_state.candidate_commands:
            self.add_log("No controllable OSC messages received - try again", "WARNING")
            new_state, effects = cancel_learn_mode(self.state)
            self.state = new_state
            await self._execute_effects(effects)
            self._update_ui()
            return

        # Edge case: Pad already configured - show warning in log but proceed
        pad_id = self.state.learn_state.selected_pad
        if pad_id and pad_id in self.state.pads:
            existing = self.state.pads[pad_id]
            self.add_log(f"Pad {pad_id} already configured as {existing.mode.name} - will be overwritten", "WARNING")

        # Show the modal
        pad_id_str = f"{pad_id.x},{pad_id.y}" if pad_id else "?"
        result = await self.push_screen_wait(
            CommandSelectionScreen(
                candidates=self.state.learn_state.candidate_commands,
                pad_id=pad_id_str
            )
        )

        # Handle result
        if result is None:
            # User cancelled
            new_state, effects = cancel_learn_mode(self.state)
            self.state = new_state
            await self._execute_effects(effects)
            self._update_ui()
        else:
            # User confirmed - apply configuration
            command_idx = self.state.learn_state.candidate_commands.index(result["command"])
            new_state, effects = select_learn_command(
                self.state,
                command_index=command_idx,
                pad_mode=result["mode"],
                group=result["group"],
                idle_color=result["idle_color"],
                active_color=result["active_color"],
                label=result["label"]
            )
            self.state = new_state
            await self._execute_effects(effects)
            self._update_ui()

    def action_learn(self):
        """Enter learn mode."""
        new_state, effects = enter_learn_mode(self.state)
        self.state = new_state
        asyncio.create_task(self._execute_effects(effects))
        self._update_ui()
    
    def action_cancel_learn(self):
        """Cancel learn mode."""
        new_state, effects = cancel_learn_mode(self.state)
        self.state = new_state
        asyncio.create_task(self._execute_effects(effects))
        self._update_ui()
    
    async def on_button_pressed(self, event: Button.Pressed):
        """Handle button press."""
        # No buttons now
        return


def run_app():
    """Run the application."""
    # Setup logging
    logging.basicConfig(
        level=logging.INFO,
        format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
    )
    
    app = LaunchpadSynesthesiaApp()
    app.run()


if __name__ == "__main__":
    run_app()
