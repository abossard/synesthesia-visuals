#!/usr/bin/env python3
"""
MIDI Router Console Integration

Reactive UI panels for MIDI router functionality within VJ Console.
"""

from typing import List, Dict, Optional
from textual.widgets import Static
from textual.reactive import reactive
from midi_domain import MidiMessage


# =============================================================================
# PURE FUNCTIONS - Formatting for UI
# =============================================================================

def format_toggle_state(state: bool) -> str:
    """Format toggle state as ON/OFF with color."""
    return "[green bold]● ON [/]" if state else "[dim]○ OFF[/]"


def format_midi_message(msg: MidiMessage, direction: str = "→") -> str:
    """
    Format MIDI message for display.
    
    Args:
        msg: MidiMessage to format
        direction: "→" for outgoing, "←" for incoming
    
    Returns:
        Formatted string
    """
    msg_types = {
        0x90: "Note On",
        0x80: "Note Off", 
        0xB0: "CC",
        0xC0: "PC",
        0xE0: "PB",
    }
    
    msg_type = msg_types.get(msg.message_type, f"0x{msg.message_type:02X}")
    
    # Color based on direction
    arrow_color = "cyan" if direction == "→" else "yellow"
    
    return (
        f"[{arrow_color}]{direction}[/] "
        f"[bold]{msg_type:8s}[/] "
        f"ch{msg.channel} "
        f"#{msg.note_or_cc:3d} "
        f"val={msg.velocity_or_value:3d}"
    )


def format_toggle_line(note: int, name: str, state: bool, selected: bool = False) -> str:
    """
    Format a single toggle line.
    
    Args:
        note: Note/CC number
        name: Toggle name
        state: Current state
        selected: Whether this toggle is selected
    
    Returns:
        Formatted string
    """
    state_str = format_toggle_state(state)
    prefix = " ▸ " if selected else "   "
    line = f"{prefix}Note {note:3d}: {name:20s} {state_str}"
    
    return f"[black on cyan]{line}[/]" if selected else line


# =============================================================================
# REACTIVE PANELS
# =============================================================================

class MidiTogglesPanel(Static):
    """Panel showing all configured MIDI toggles."""
    
    toggles = reactive([])  # List of (note, name, state) tuples
    selected = reactive(0)
    
    def on_mount(self) -> None:
        """Initialize content when mounted."""
        self._safe_render()
    
    def watch_toggles(self, _: list) -> None:
        self._safe_render()
    
    def watch_selected(self, _: int) -> None:
        self._safe_render()
    
    def _safe_render(self) -> None:
        """Render only if mounted."""
        if not self.is_mounted:
            return
        
        lines = ["[bold]═══ MIDI Toggles ═══[/]\n"]
        
        if not self.toggles:
            lines.append("[dim](no toggles configured - use learn mode to add)[/dim]")
        else:
            for i, (note, name, state) in enumerate(self.toggles):
                is_selected = i == self.selected
                lines.append(format_toggle_line(note, name, state, is_selected))
        
        self.update("\n".join(lines))


class MidiActionsPanel(Static):
    """Panel showing available MIDI router actions."""
    
    learn_mode = reactive(False)
    router_running = reactive(False)
    device_info = reactive("")
    
    def on_mount(self) -> None:
        """Initialize content when mounted."""
        self._safe_render()
    
    def watch_learn_mode(self, _: bool) -> None:
        self._safe_render()
    
    def watch_router_running(self, _: bool) -> None:
        self._safe_render()
    
    def watch_device_info(self, _: str) -> None:
        self._safe_render()
    
    def _safe_render(self) -> None:
        """Render only if mounted."""
        if not self.is_mounted:
            return
        
        lines = ["[bold]═══ MIDI Router ═══[/]\n"]
        
        # Router status
        if self.router_running:
            lines.append("[green]● Router Running[/]")
        else:
            lines.append("[dim]○ Router Stopped[/]")
        
        if self.device_info:
            lines.append(f"[dim]{self.device_info}[/]")
        
        lines.append("")
        
        # Learn mode status
        if self.learn_mode:
            lines.append("[yellow bold]🎹 LEARN MODE ACTIVE[/]")
            lines.append("[yellow]Press a pad on your controller to learn...[/]")
        else:
            lines.append("[dim]Learn mode: inactive[/dim]")
        
        lines.append("\n[bold]═══ Actions ═══[/]\n")
        
        # Key bindings
        lines.append("[cyan]l[/]     Enter learn mode (capture next pad)")
        lines.append("[cyan]r[/]     Rename selected toggle")
        lines.append("[cyan]d[/]     Delete selected toggle")
        lines.append("[cyan]k/j[/]   Navigate up/down")
        lines.append("[cyan]space[/] Toggle selected on/off (test)")
        
        self.update("\n".join(lines))


class MidiDebugPanel(Static):
    """Panel showing MIDI message traffic."""
    
    messages = reactive([])  # List of (timestamp, direction, MidiMessage) tuples
    
    def on_mount(self) -> None:
        """Initialize content when mounted."""
        self._safe_render()
    
    def watch_messages(self, _: list) -> None:
        self._safe_render()
    
    def _safe_render(self) -> None:
        """Render only if mounted."""
        if not self.is_mounted:
            return
        
        lines = ["[bold]═══ MIDI Traffic ═══[/]\n"]
        
        if not self.messages:
            lines.append("[dim](no MIDI messages yet)[/dim]")
        else:
            # Show last 30 messages
            import time
            for ts, direction, msg in reversed(self.messages[-30:]):
                time_str = time.strftime("%H:%M:%S", time.localtime(ts))
                msg_str = format_midi_message(msg, direction)
                lines.append(f"[dim]{time_str}[/] {msg_str}")
        
        self.update("\n".join(lines))


class MidiStatusPanel(Static):
    """Panel showing MIDI router configuration and status."""
    
    config_info = reactive({})
    
    def on_mount(self) -> None:
        """Initialize content when mounted."""
        self._safe_render()
    
    def watch_config_info(self, _: dict) -> None:
        self._safe_render()
    
    def _safe_render(self) -> None:
        """Render only if mounted."""
        if not self.is_mounted:
            return
        
        lines = ["[bold]═══ Configuration ═══[/]\n"]
        
        if not self.config_info:
            lines.append("[dim](router not configured)[/dim]")
        else:
            lines.append(f"[bold]Controller:[/] {self.config_info.get('controller', 'N/A')}")
            lines.append(f"[bold]Virtual Port:[/] {self.config_info.get('virtual_port', 'N/A')}")
            lines.append(f"[bold]Toggles:[/] {self.config_info.get('toggle_count', 0)}")
            lines.append(f"[bold]Config File:[/] [dim]{self.config_info.get('config_file', 'N/A')}[/]")
            
            if self.config_info.get('error'):
                lines.append(f"\n[red]Error:[/] {self.config_info['error']}")
        
        self.update("\n".join(lines))
