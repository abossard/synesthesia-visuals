"""
Launchpad Synesthesia Control - Textual TUI

Main application with async event handling and graceful degradation.
"""

import asyncio
import logging
from pathlib import Path
from typing import Optional, List

from textual.app import App, ComposeResult
from textual.containers import Container, Horizontal, Vertical, VerticalScroll
from textual.widgets import Header, Footer, Static, Label, Button, Input
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
# TUI WIDGETS
# =============================================================================

class LaunchpadGrid(Static):
    """Visual representation of Launchpad 8x8 grid + top row + right column."""
    
    state: reactive[ControllerState] = reactive(ControllerState)
    
    def render(self) -> str:
        """Render the Launchpad grid as ASCII art."""
        lines = []
        
        # Top row (y=-1)
        top_row = "╔"
        for x in range(8):
            pad_id = PadId(x, -1)
            char = self._get_pad_char(pad_id)
            top_row += f"═{char}═╦" if x < 7 else f"═{char}═╗"
        lines.append(top_row)
        
        # Main grid (8x8)
        for y in range(8):
            row = "║"
            for x in range(8):
                pad_id = PadId(x, y)
                char = self._get_pad_char(pad_id)
                row += f" {char} ║"
            
            # Right column
            right_pad = PadId(8, y)
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
    
    def _get_pad_char(self, pad_id: PadId) -> str:
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


class OscConfigPanel(Container):
    """OSC configuration panel."""
    
    def compose(self) -> ComposeResult:
        yield Label("OSC Configuration", classes="panel-title")
        yield Label("Host: localhost (fixed)")
        yield Horizontal(
            Label("Send Port:"),
            Input(value="9000", id="osc_send_port", classes="port-input"),
            classes="config-row"
        )
        yield Horizontal(
            Label("Receive Port:"),
            Input(value="9001", id="osc_receive_port", classes="port-input"),
            classes="config-row"
        )
        yield Button("Apply", id="apply_osc", variant="primary")


# =============================================================================
# MAIN APPLICATION
# =============================================================================

class LaunchpadSynesthesiaApp(App):
    """Main Textual application."""
    
    CSS = """
    Screen {
        layout: grid;
        grid-size: 3 2;
        grid-columns: 2fr 1fr 1fr;
        grid-rows: 3fr 2fr;
    }
    
    #grid_container {
        column-span: 2;
        row-span: 2;
        border: solid green;
        padding: 1;
    }
    
    #status_container {
        border: solid cyan;
        padding: 1;
    }
    
    #osc_config_container {
        border: solid yellow;
        padding: 1;
    }
    
    #log_container {
        border: solid blue;
        padding: 1;
        height: 100%;
    }
    
    .panel-title {
        text-align: center;
        text-style: bold;
        color: cyan;
    }
    
    .config-row {
        height: 3;
        margin: 1 0;
    }
    
    .port-input {
        width: 10;
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
        self.launchpad: Optional[LaunchpadDevice] = None
        self.osc: Optional[OscManager] = None
        self.config_manager = ConfigManager(get_default_config_path())
        self._blink_task: Optional[asyncio.Task] = None
        self._reconnect_task: Optional[asyncio.Task] = None
    
    def compose(self) -> ComposeResult:
        """Create UI layout."""
        yield Header()
        
        with Container(id="grid_container"):
            yield Label("Launchpad Mini Mk3", classes="panel-title")
            yield LaunchpadGrid(id="launchpad_grid")
        
        with Container(id="status_container"):
            yield StatusPanel(id="status_panel")
        
        with Container(id="osc_config_container"):
            yield OscConfigPanel()
        
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
        
        # Update UI
        self._update_ui()
    
    async def _init_launchpad(self):
        """Initialize Launchpad connection."""
        self.launchpad = LaunchpadDevice(LaunchpadConfig(auto_detect=True))
        
        connected = await self.launchpad.connect()
        if connected:
            self.launchpad.set_pad_callback(self._on_pad_press)
            # Start listening in background
            asyncio.create_task(self.launchpad.start_listening())
            self.add_log("Launchpad connected", "INFO")
        else:
            self.add_log("Launchpad not found - will retry", "WARNING")
        
        self._update_connection_status()
    
    async def _init_osc(self):
        """Initialize OSC connection."""
        # Get port from inputs
        send_port = 9000
        receive_port = 9001
        
        self.osc = OscManager(OscConfig(
            host="127.0.0.1",
            send_port=send_port,
            receive_port=receive_port
        ))
        
        connected = await self.osc.connect()
        if connected:
            self.osc.set_osc_callback(self._on_osc_event)
            self.add_log(f"OSC connected: :{send_port} → :{receive_port}", "INFO")
        else:
            self.add_log("OSC not available - will retry", "WARNING")
        
        self._update_connection_status()
    
    async def _reconnect_loop(self):
        """Periodically check and reconnect devices."""
        while True:
            await asyncio.sleep(5)
            
            # Try to reconnect Launchpad
            if self.launchpad and not self.launchpad.is_connected():
                await self._init_launchpad()
            
            # Try to reconnect OSC
            if self.osc and not self.osc.is_connected():
                await self._init_osc()
    
    def _on_pad_press(self, pad_id: PadId, velocity: int):
        """Handle Launchpad pad press (called from MIDI thread)."""
        # Schedule in main event loop
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
        # Schedule in main event loop
        asyncio.create_task(self._handle_osc_event_async(event))
    
    async def _handle_osc_event_async(self, event: OscEvent):
        """Handle OSC event in async context."""
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
            if isinstance(effect, SendOscEffect):
                if self.osc:
                    self.osc.send(effect.command)
            
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
        # Update grid
        grid = self.query_one("#launchpad_grid", LaunchpadGrid)
        grid.state = self.state
        
        # Update status
        status = self.query_one("#status_panel", StatusPanel)
        status.app_mode = self.state.app_mode
        status.active_scene = self.state.active_scene
        status.active_preset = self.state.active_preset
        status.beat_pulse = self.state.beat_pulse
    
    def _update_connection_status(self):
        """Update connection status in UI."""
        status = self.query_one("#status_panel", StatusPanel)
        status.launchpad_connected = self.launchpad.is_connected() if self.launchpad else False
        status.osc_connected = self.osc.is_connected() if self.osc else False
        status.osc_status = self.osc.status if self.osc else "Not initialized"
    
    def add_log(self, message: str, level: str = "INFO"):
        """Add log message."""
        try:
            log_panel = self.query_one("#log_panel", LogPanel)
            log_panel.add_log(message, level)
        except:
            # UI not ready yet
            pass
    
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
        if event.button.id == "apply_osc":
            # Reload OSC with new ports
            await self._init_osc()


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
