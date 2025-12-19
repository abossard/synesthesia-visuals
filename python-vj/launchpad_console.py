#!/usr/bin/env python3
"""
Launchpad Console Panels for VJ Console

Textual UI panels displaying launchpad_osc_lib state:
- Connection status, current phase, learn mode progress
- Configured pads grid visualization
- Interactive tests menu with on-screen instructions
- OSC debug messages (Synesthesia communication)

No keybindings for Launchpad control - all interaction happens
via the Launchpad itself. UI is purely for monitoring and triggering tests.
"""

import time
import threading
import logging
from typing import Optional, List, Dict, Any, Callable

from textual.widgets import Static, Button
from textual.reactive import reactive
from textual.containers import Vertical, Horizontal
from textual.app import ComposeResult

# Import launchpad_osc_lib components
try:
    from launchpad_osc_lib import (
        ButtonId, ControllerState, LearnPhase, LearnRegister,
        PadBehavior, PadMode, PadRuntimeState, LedEffect, OscEvent,
        LP_OFF, LP_RED, LP_GREEN, LP_BLUE, LP_YELLOW, LP_ORANGE, LP_CYAN, LP_PURPLE, LP_WHITE,
    )
    from launchpad_osc_lib.launchpad_device import LaunchpadDevice
    from launchpad_osc_lib.display import render_state
    from launchpad_osc_lib.fsm import handle_pad_press, handle_pad_release, handle_osc_event
    from launchpad_osc_lib.config import load_config, save_config
    from launchpad_osc_lib.synesthesia_config import enrich_event
    from osc import osc
    LAUNCHPAD_LIB_AVAILABLE = True
except ImportError as e:
    LAUNCHPAD_LIB_AVAILABLE = False
    import sys
    print(f"Warning: launchpad_osc_lib not available - {e}", file=sys.stderr)

logger = logging.getLogger('launchpad_console')


# =============================================================================
# HELPER FUNCTIONS (Pure)
# =============================================================================

def format_phase_name(phase: 'LearnPhase') -> str:
    """Human-readable phase name."""
    names = {
        LearnPhase.IDLE: "Ready",
        LearnPhase.WAIT_PAD: "Select Pad",
        LearnPhase.RECORD_OSC: "Recording OSC",
        LearnPhase.CONFIG: "Configure",
    }
    return names.get(phase, str(phase))


def format_register_name(register: 'LearnRegister') -> str:
    """Human-readable register name."""
    names = {
        LearnRegister.OSC_SELECT: "OSC Command",
        LearnRegister.MODE_SELECT: "Button Mode",
        LearnRegister.COLOR_SELECT: "Colors",
    }
    return names.get(register, str(register))


def format_mode_name(mode: 'PadMode') -> str:
    """Human-readable mode name."""
    names = {
        PadMode.SELECTOR: "Selector (Radio)",
        PadMode.TOGGLE: "Toggle (On/Off)",
        PadMode.ONE_SHOT: "One-Shot (Trigger)",
        PadMode.PUSH: "Push (Momentary)",
    }
    return names.get(mode, str(mode))


def color_name_from_velocity(vel: int) -> str:
    """Approximate color name from velocity."""
    if vel == 0:
        return "off"
    elif vel in (1, 5, 6):
        return "red"
    elif vel in (7, 9, 10):
        return "orange"
    elif vel in (11, 13, 14):
        return "yellow"
    elif vel in (19, 21, 22):
        return "green"
    elif vel in (33, 37, 38):
        return "cyan"
    elif vel in (41, 45, 46):
        return "blue"
    elif vel in (49, 53, 54):
        return "purple"
    elif vel in (55, 57, 58):
        return "pink"
    elif vel in (1, 3, 119):
        return "white"
    return f"v{vel}"


# =============================================================================
# TEXTUAL PANELS
# =============================================================================

class LaunchpadStatusPanel(Static):
    """
    Launchpad connection and state overview panel.
    
    Shows:
    - Connection status (connected/disconnected)
    - Current phase (IDLE/WAIT_PAD/RECORD_OSC/CONFIG)
    - Learn mode progress
    - Device info
    """
    status = reactive({})
    
    def on_mount(self) -> None:
        self._safe_render()
    
    def watch_status(self, data: dict) -> None:
        self._safe_render()
    
    def _safe_render(self) -> None:
        try:
            data = self.status or {}
            lines = ["[bold]═══ Launchpad Status ═══[/]\n"]
            
            # Connection
            connected = data.get('connected', False)
            if connected:
                device_id = data.get('device_id', 'Launchpad Mini MK3')
                lines.append(f"[green]● Connected[/]  {device_id}")
            else:
                lines.append("[red]○ Disconnected[/]  No Launchpad found")
            
            # OSC
            osc_connected = data.get('osc_connected', False)
            osc_ports = data.get('osc_ports', '')
            if osc_connected:
                lines.append(f"[green]● OSC Active[/]  {osc_ports}")
            else:
                lines.append(f"[dim]○ OSC Offline[/]  {osc_ports}")
            
            lines.append("")
            
            # Phase
            phase = data.get('phase', 'IDLE')
            phase_color = {
                'IDLE': 'green',
                'WAIT_PAD': 'yellow',
                'RECORD_OSC': 'orange1',
                'CONFIG': 'cyan',
            }.get(phase, 'white')
            lines.append(f"Phase: [{phase_color}]{phase}[/]")
            
            # Learn mode details
            if phase == 'WAIT_PAD':
                lines.append("[dim]  Press any pad to configure it[/]")
            elif phase == 'RECORD_OSC':
                selected_pad = data.get('selected_pad', '')
                event_count = data.get('recorded_events', 0)
                lines.append(f"  Selected: {selected_pad}")
                lines.append(f"  Recorded: {event_count} OSC events")
                lines.append("[dim]  Change scenes in Synesthesia to record[/]")
            elif phase == 'CONFIG':
                register = data.get('active_register', 'OSC_SELECT')
                lines.append(f"  Editing: [cyan]{register}[/]")
                lines.append("[dim]  Use top row to switch registers[/]")
            
            # Pad stats
            lines.append("")
            pad_count = data.get('pad_count', 0)
            lines.append(f"Configured Pads: {pad_count}")
            
            self.update("\n".join(lines))
            
        except Exception as e:
            self.update(f"[red]Status render error: {e}[/]")


class LaunchpadPadsPanel(Static):
    """
    Visual grid showing configured pads.
    
    8x8 grid with symbols for each pad:
    - ○ Empty (unconfigured)
    - ● Configured (shows behavior type)
    - Color indicates current state
    """
    pads_data = reactive({})
    
    def on_mount(self) -> None:
        self._safe_render()
    
    def watch_pads_data(self, data: dict) -> None:
        self._safe_render()
    
    def _safe_render(self) -> None:
        try:
            data = self.pads_data or {}
            pads = data.get('pads', {})
            runtime = data.get('runtime', {})
            
            lines = ["[bold]═══ Pad Configuration ═══[/]\n"]
            
            # Mode symbols
            mode_chars = {
                'SELECTOR': 'S',
                'TOGGLE': 'T',
                'ONE_SHOT': '!',
                'PUSH': 'P',
            }
            
            # Build 8x8 grid (y=7 at top, y=0 at bottom)
            lines.append("    0 1 2 3 4 5 6 7  ← x")
            for y in range(7, -1, -1):
                row = f" {y}: "
                for x in range(8):
                    key = f"{x},{y}"
                    if key in pads:
                        pad = pads[key]
                        mode = pad.get('mode', 'TOGGLE')
                        is_active = runtime.get(key, {}).get('is_active', False)
                        char = mode_chars.get(mode, '?')
                        if is_active:
                            row += f"[green]{char}[/] "
                        else:
                            row += f"[dim]{char}[/] "
                    else:
                        row += "[dim]·[/] "
                lines.append(row)
            
            lines.append("")
            lines.append("[dim]S=Selector T=Toggle !=OneShot P=Push[/]")
            
            # Legend with recent pads
            recent_pads = list(pads.items())[:3]
            if recent_pads:
                lines.append("")
                lines.append("[bold]Recent Pads:[/]")
                for key, pad in recent_pads:
                    label = pad.get('label', '') or pad.get('osc_address', '')
                    mode = pad.get('mode', '')
                    lines.append(f"  [{key}] {mode}: {label[:30]}")
            
            self.update("\n".join(lines))
            
        except Exception as e:
            self.update(f"[red]Pads render error: {e}[/]")


class LaunchpadInstructionsPanel(Static):
    """
    On-screen tutorial instructions for current phase.
    
    Shows context-sensitive help based on learn mode phase.
    """
    phase = reactive("IDLE")
    
    def on_mount(self) -> None:
        self._safe_render()
    
    def watch_phase(self, p: str) -> None:
        self._safe_render()
    
    def _safe_render(self) -> None:
        try:
            phase = self.phase or "IDLE"
            lines = ["[bold]═══ Instructions ═══[/]\n"]
            
            if phase == "IDLE":
                lines.extend([
                    "[green]Normal Operation[/]",
                    "",
                    "Your configured pads are active.",
                    "Press pads to send OSC commands.",
                    "",
                    "[bold]To configure new pads:[/]",
                    "  Press bottom-right scene button",
                    "  (marked green on your Launchpad)",
                    "",
                    "[dim]Hint: In Synesthesia, use OSC to[/]",
                    "[dim]control scenes, presets, and more[/]",
                ])
            elif phase == "WAIT_PAD":
                lines.extend([
                    "[yellow]Select a Pad to Configure[/]",
                    "",
                    "All unconfigured pads are blinking red.",
                    "",
                    "[bold]Press any grid pad (0-7, 0-7)[/]",
                    "to start configuring it.",
                    "",
                    "Already-configured pads show their",
                    "assigned colors.",
                    "",
                    "[dim]Cancel: Press scene button again[/]",
                ])
            elif phase == "RECORD_OSC":
                lines.extend([
                    "[orange1]Recording OSC Messages[/]",
                    "",
                    "Your selected pad is blinking orange.",
                    "",
                    "[bold]Now change scenes in Synesthesia:[/]",
                    "  • Click a scene thumbnail",
                    "  • Use keyboard shortcuts",
                    "  • Cycle through presets",
                    "",
                    "Each action sends OSC - we capture it!",
                    "",
                    "[bold]When done:[/]",
                    "  [green]Green pad (0,0)[/] = Save & configure",
                    "  [red]Red pad (7,0)[/] = Cancel",
                ])
            elif phase == "CONFIG":
                lines.extend([
                    "[cyan]Configure Pad Behavior[/]",
                    "",
                    "[bold]Top row switches registers:[/]",
                    "  Pad 0: [yellow]OSC Command[/] - select action",
                    "  Pad 1: [yellow]Mode[/] - select behavior",
                    "  Pad 2: [yellow]Colors[/] - pick LED colors",
                    "",
                    "[bold]Modes available:[/]",
                    "  [purple]Toggle[/] - On/Off switch",
                    "  [cyan]Push[/] - Momentary (sustain pedal)",
                    "  [orange1]One-Shot[/] - Single trigger",
                    "  [green]Selector[/] - Radio group",
                    "",
                    "[bold]Bottom row:[/]",
                    "  [green]Save[/] (0,0)  [blue]Test[/] (1,0)  [red]Cancel[/] (7,0)",
                ])
            else:
                lines.append(f"[dim]Unknown phase: {phase}[/]")
            
            self.update("\n".join(lines))
            
        except Exception as e:
            self.update(f"[red]Instructions error: {e}[/]")


class LaunchpadOscDebugPanel(Static):
    """
    OSC message debug panel for Synesthesia communication.
    
    Shows recent OSC messages sent/received via launchpad_osc_lib's
    Synesthesia OSC ports (7777/9999).
    """
    messages = reactive([])
    
    def on_mount(self) -> None:
        self._safe_render()
    
    def watch_messages(self, msgs: list) -> None:
        self._safe_render()
    
    def _safe_render(self) -> None:
        try:
            msgs = self.messages or []
            lines = ["[bold]═══ Synesthesia OSC ═══[/]\n"]
            
            if not msgs:
                lines.append("[dim]No OSC traffic yet[/]")
                lines.append("")
                lines.append("[dim]OSC will appear when:[/]")
                lines.append("[dim]  • You press configured pads[/]")
                lines.append("[dim]  • Recording OSC in learn mode[/]")
            else:
                # Show last 15 messages
                for msg in msgs[-15:]:
                    ts = msg.get('timestamp', 0)
                    direction = msg.get('direction', '→')
                    address = msg.get('address', '')
                    args = msg.get('args', [])
                    
                    time_str = time.strftime("%H:%M:%S", time.localtime(ts))
                    
                    # Color by address type
                    if '/scenes/' in address:
                        color = 'green'
                    elif '/presets/' in address:
                        color = 'cyan'
                    elif '/colors/' in address:
                        color = 'yellow'
                    else:
                        color = 'white'
                    
                    args_str = str(args) if args else ''
                    lines.append(f"[dim]{time_str}[/] {direction} [{color}]{address}[/] {args_str}")
            
            self.update("\n".join(lines))
            
        except Exception as e:
            self.update(f"[red]OSC debug error: {e}[/]")


class LaunchpadTestsPanel(Static):
    """
    Interactive tests panel with buttons to trigger device tests.
    
    Uses the tests from launchpad_osc_lib/tests/device_interactive.py.
    """
    test_status = reactive({})
    
    def compose(self) -> ComposeResult:
        yield Static("[bold]═══ Interactive Tests ═══[/]\n", id="tests-header")
        yield Button("🎨 Color Palette", id="test-colors", variant="primary")
        yield Button("💡 Brightness Levels", id="test-brightness", variant="primary")
        yield Button("🔲 Idle State Demo", id="test-idle", variant="primary")
        yield Button("📝 Learn Mode Demo", id="test-learn", variant="primary")
        yield Button("✨ Animation Demo", id="test-animation", variant="primary")
        yield Button("🎵 Beat Sync Demo", id="test-beat", variant="primary")
        yield Static("", id="test-result")
    
    def on_mount(self) -> None:
        self._update_result("[dim]Press a button to run a test[/]")
    
    def watch_test_status(self, data: dict) -> None:
        result = data.get('result', '')
        if result:
            self._update_result(result)
    
    def _update_result(self, text: str) -> None:
        try:
            self.query_one("#test-result", Static).update(text)
        except Exception:
            pass


# =============================================================================
# LAUNCHPAD MANAGER (runs in background thread)
# =============================================================================

class LaunchpadManager:
    """
    Manages Launchpad connection and state for VJ Console integration.
    
    Wraps launchpad_osc_lib's LaunchpadApp pattern but runs non-blocking
    in a background thread, providing callbacks for UI updates.
    
    Usage:
        manager = LaunchpadManager()
        manager.set_state_callback(my_callback)
        manager.start()  # Non-blocking
        # ... later
        manager.stop()
    """
    
    def __init__(self):
        # Components
        self.device: Optional['LaunchpadDevice'] = None
        self._osc_running = False
        self.state = ControllerState() if LAUNCHPAD_LIB_AVAILABLE else None
        
        # Thread management
        self._thread: Optional[threading.Thread] = None
        self._running = False
        self._lock = threading.RLock()
        
        # Callbacks (called from background thread - use call_from_thread!)
        self._state_callback: Optional[Callable[[ControllerState], None]] = None
        self._osc_log_callback: Optional[Callable[[dict], None]] = None
        
        # OSC message log for debug panel
        self._osc_messages: List[dict] = []
    
    def set_state_callback(self, callback: Callable[['ControllerState'], None]) -> None:
        """Set callback for state changes (called from background thread)."""
        self._state_callback = callback
    
    def set_osc_log_callback(self, callback: Callable[[dict], None]) -> None:
        """Set callback for OSC log messages."""
        self._osc_log_callback = callback
    
    def start(self) -> bool:
        """
        Start Launchpad manager (non-blocking).
        
        Returns True if started successfully.
        """
        if not LAUNCHPAD_LIB_AVAILABLE:
            logger.error("launchpad_osc_lib not available")
            return False
        
        if self._running:
            return True
        
        try:
            # Initialize device
            self.device = LaunchpadDevice()
            if not self.device.connect():
                logger.warning("No Launchpad connected - running in offline mode")
                self.device = None
            
            # Initialize OSC via central hub
            osc.start()
            osc.subscribe("/", self._on_osc_raw)
            self._osc_running = True
            
            # Load saved config
            pads = load_config()
            if pads:
                from dataclasses import replace
                self.state = replace(self.state, pads=pads)
            
            # Start background thread if device connected
            if self.device:
                self._running = True
                self._thread = threading.Thread(
                    target=self._run_loop,
                    name="LaunchpadManager",
                    daemon=True
                )
                self._thread.start()
                
                # Initial LED render
                self._render_leds()
            
            logger.info("LaunchpadManager started")
            return True
            
        except Exception as e:
            logger.exception(f"LaunchpadManager start failed: {e}")
            return False
    
    def stop(self) -> None:
        """Stop the manager."""
        self._running = False
        
        if self._osc_running:
            osc.unsubscribe("/", self._on_osc_raw)
            self._osc_running = False
        
        if self.device:
            self.device.stop()
            self.device = None
        
        if self._thread:
            self._thread.join(timeout=2.0)
            self._thread = None
        
        logger.info("LaunchpadManager stopped")
    
    def get_status(self) -> dict:
        """Get current status for UI panel."""
        with self._lock:
            state = self.state
            if not state:
                return {'connected': False, 'phase': 'IDLE'}
            
            phase = state.learn_state.phase
            return {
                'connected': self.device is not None,
                'device_id': 'Launchpad Mini MK3' if self.device else '',
                'osc_connected': self._osc_running,
                'osc_ports': f"send:7777 recv:9999",
                'phase': phase.name,
                'selected_pad': str(state.learn_state.selected_pad) if state.learn_state.selected_pad else '',
                'recorded_events': len(state.learn_state.recorded_events),
                'active_register': state.learn_state.active_register.name if phase == LearnPhase.CONFIG else '',
                'pad_count': len(state.pads),
            }
    
    def get_pads_data(self) -> dict:
        """Get pads configuration for UI panel."""
        with self._lock:
            if not self.state:
                return {}
            
            pads = {}
            runtime = {}
            
            for pad_id, behavior in self.state.pads.items():
                key = f"{pad_id.x},{pad_id.y}"
                pads[key] = {
                    'mode': behavior.mode.name,
                    'label': behavior.label,
                    'osc_address': behavior.osc_action.address if behavior.osc_action else 
                                   behavior.osc_on.address if behavior.osc_on else '',
                    'idle_color': behavior.idle_color,
                    'active_color': behavior.active_color,
                }
                
                rt = self.state.pad_runtime.get(pad_id)
                if rt:
                    runtime[key] = {
                        'is_active': rt.is_active,
                        'is_on': rt.is_on,
                        'current_color': rt.current_color,
                    }
            
            return {'pads': pads, 'runtime': runtime}
    
    def get_osc_messages(self) -> List[dict]:
        """Get recent OSC messages for debug panel."""
        with self._lock:
            return self._osc_messages[-50:]
    
    # === Test functions (for interactive tests panel) ===
    
    def run_test(self, test_name: str) -> str:
        """Run an interactive test. Returns result message."""
        if not self.device:
            return "[red]No Launchpad connected[/]"
        
        try:
            if test_name == "colors":
                self._test_colors()
                return "[green]✓ Color palette displayed[/]"
            elif test_name == "brightness":
                self._test_brightness()
                return "[green]✓ Brightness levels displayed[/]"
            elif test_name == "idle":
                self._test_idle()
                return "[green]✓ Idle state rendered[/]"
            elif test_name == "learn":
                self._test_learn()
                return "[green]✓ Learn mode demo shown[/]"
            elif test_name == "animation":
                self._test_animation()
                return "[green]✓ Animation complete[/]"
            elif test_name == "beat":
                self._test_beat()
                return "[green]✓ Beat sync demo complete[/]"
            else:
                return f"[yellow]Unknown test: {test_name}[/]"
        except Exception as e:
            return f"[red]Test failed: {e}[/]"
    
    def _test_colors(self):
        """Display color palette on grid."""
        colors = [LP_RED, LP_ORANGE, LP_YELLOW, LP_GREEN, LP_CYAN, LP_BLUE, LP_PURPLE, LP_WHITE]
        for y in range(8):
            for x in range(8):
                self.device.set_led(ButtonId(x, y), colors[(x + y) % 8])
    
    def _test_brightness(self):
        """Display brightness levels."""
        self._clear_leds()
        levels = [(1, 5, 6), (7, 9, 10), (11, 13, 14), (19, 21, 22),
                  (33, 37, 38), (41, 45, 46), (49, 53, 54), (55, 57, 58)]
        for col, (dim, normal, bright) in enumerate(levels):
            self.device.set_led(ButtonId(col, 0), dim)
            self.device.set_led(ButtonId(col, 1), normal)
            self.device.set_led(ButtonId(col, 2), bright)
    
    def _test_idle(self):
        """Render current idle state."""
        self._render_leds()
    
    def _test_learn(self):
        """Demo learn mode phases briefly."""
        import time
        # Wait pad phase
        for y in range(8):
            for x in range(8):
                self.device.set_led(ButtonId(x, y), LP_RED, pulse=True)
        time.sleep(1)
        self._clear_leds()
    
    def _test_animation(self):
        """Run animation test."""
        import time
        self._clear_leds()
        for y in range(8):
            for x in range(8):
                self.device.set_led(ButtonId(x, y), LP_WHITE)
            time.sleep(0.05)
            for x in range(8):
                self.device.set_led(ButtonId(x, y), LP_OFF)
        self._render_leds()
    
    def _test_beat(self):
        """Simulate beat sync."""
        import time
        self._clear_leds()
        for _ in range(4):
            for x in range(4):
                self.device.set_led(ButtonId(x, 5), LP_RED)
            time.sleep(0.15)
            for x in range(4):
                self.device.set_led(ButtonId(x, 5), LP_OFF)
            time.sleep(0.35)
        self._render_leds()
    
    def _clear_leds(self):
        """Clear all LEDs."""
        if not self.device:
            return
        for y in range(8):
            for x in range(8):
                self.device.set_led(ButtonId(x, y), LP_OFF)
    
    # === Private methods ===
    
    def _run_loop(self):
        """Background thread running device listener."""
        logger.info("Launchpad listener thread started")
        
        # Set up callbacks
        self.device.set_callbacks(
            on_press=self._on_pad_press,
            on_release=self._on_pad_release,
        )
        
        # This blocks until stop() is called
        try:
            self.device.start_listening()
        except Exception as e:
            logger.error(f"Launchpad listener error: {e}")
        
        logger.info("Launchpad listener thread exiting")
    
    def _on_pad_press(self, pad_id: 'ButtonId', velocity: int):
        """Handle pad press from device (background thread)."""
        with self._lock:
            new_state, effects = handle_pad_press(self.state, pad_id)
            self.state = new_state
            self._execute_effects(effects)
            self._render_leds()
            self._notify_state_change()
    
    def _on_pad_release(self, pad_id: 'ButtonId'):
        """Handle pad release from device (background thread)."""
        with self._lock:
            new_state, effects = handle_pad_release(self.state, pad_id)
            self.state = new_state
            self._execute_effects(effects)
            self._render_leds()
            self._notify_state_change()
    
    def _on_osc_raw(self, path: str, args: list) -> None:
        """Adapter: convert raw OSC to OscEvent and forward."""
        event = enrich_event(path, list(args), time.time())
        self._on_osc_event(event)
    
    def _on_osc_event(self, event: 'OscEvent'):
        """Handle incoming OSC from Synesthesia (background thread)."""
        # Log for debug panel
        with self._lock:
            self._osc_messages.append({
                'timestamp': event.timestamp,
                'direction': '←',
                'address': event.address,
                'args': event.args,
            })
            if len(self._osc_messages) > 100:
                self._osc_messages.pop(0)
        
        # Handle in FSM if recording
        if self.state.learn_state.phase == LearnPhase.RECORD_OSC:
            with self._lock:
                new_state, effects = handle_osc_event(self.state, event)
                self.state = new_state
                self._execute_effects(effects)
                self._render_leds()
                self._notify_state_change()
    
    def _execute_effects(self, effects):
        """Execute FSM effects."""
        from launchpad_osc_lib.model import SendOscEffect, SaveConfigEffect, LogEffect
        
        for effect in effects:
            if isinstance(effect, SendOscEffect):
                if self._osc_running:
                    cmd = effect.command
                    osc.synesthesia.send(cmd.address, *cmd.args)
                    # Log outgoing
                    with self._lock:
                        self._osc_messages.append({
                            'timestamp': time.time(),
                            'direction': '→',
                            'address': cmd.address,
                            'args': cmd.args,
                        })
            elif isinstance(effect, SaveConfigEffect):
                save_config(self.state)
            elif isinstance(effect, LogEffect):
                level = getattr(logging, effect.level, logging.INFO)
                logger.log(level, effect.message)
    
    def _render_leds(self):
        """Render current state to LEDs."""
        if not self.device:
            return
        
        effects = render_state(self.state)
        for effect in effects:
            if isinstance(effect, LedEffect):
                self.device.set_led(effect.pad_id, effect.color, pulse=effect.blink)
    
    def _notify_state_change(self):
        """Notify UI of state change."""
        if self._state_callback:
            try:
                self._state_callback(self.state)
            except Exception as e:
                logger.debug(f"State callback error: {e}")
