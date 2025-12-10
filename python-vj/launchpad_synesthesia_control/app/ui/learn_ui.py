"""
Learn Mode UI Components

Interactive widgets for the learn mode workflow.
"""

import time
from typing import List, Optional, Callable

from textual.widgets import Static, ListView, ListItem, Label, Button, Input
from textual.containers import Container, Vertical, Horizontal
from textual.reactive import reactive
from textual.binding import Binding

from launchpad_osc_lib import OscCommand, OscEvent, PadMode, PadGroupName, AppMode, LearnState

# Default time function (can be overridden for testing)
_time_func: Callable[[], float] = time.time


def set_time_func(func: Callable[[], float]) -> None:
    """Set the time function used by learn UI (for testing)."""
    global _time_func
    _time_func = func


def get_current_time() -> float:
    """Get current time using configured time function."""
    return _time_func()


class LearnModePanel(Container):
    """Panel showing learn mode progress and options."""
    
    learn_state: reactive[LearnState] = reactive(LearnState())
    app_mode: reactive[AppMode] = reactive(AppMode.NORMAL)
    
    def compose(self):
        """Compose the learn mode panel."""
        yield Label("═══ LEARN MODE ═══", classes="panel-title")
        yield Static(id="learn_status")
        yield Static(id="learn_timer")
        yield Container(id="learn_options")
    
    def watch_app_mode(self, new_mode: AppMode):
        """Update display when app mode changes."""
        self.update_display()
    
    def watch_learn_state(self, new_state: LearnState):
        """Update display when learn state changes."""
        self.update_display()
    
    def update_display(self):
        """Update the learn mode display."""
        try:
            status_widget = self.query_one("#learn_status", Static)
            timer_widget = self.query_one("#learn_timer", Static)
            options_container = self.query_one("#learn_options", Container)
            
            if self.app_mode == AppMode.NORMAL:
                status_widget.update("[dim]Press L to enter Learn Mode[/]")
                timer_widget.update("")
                options_container.remove_children()
            
            elif self.app_mode == AppMode.LEARN_WAIT_PAD:
                status_widget.update("[yellow]Press a pad to configure...[/]")
                timer_widget.update("")
                options_container.remove_children()
            
            elif self.app_mode == AppMode.LEARN_RECORD_OSC:
                if self.learn_state.record_start_time:
                    elapsed = get_current_time() - self.learn_state.record_start_time
                    remaining = max(0, 5.0 - elapsed)
                    status_widget.update(f"[yellow]Recording OSC for pad {self.learn_state.selected_pad}[/]")
                    timer_widget.update(f"[cyan]Time remaining: {remaining:.1f}s[/]")
                else:
                    # Waiting for first controllable message
                    status_widget.update(f"[yellow]Waiting for controllable OSC message...[/]")
                    timer_widget.update(f"[dim]Press a button in Synesthesia to start recording[/]")
                options_container.remove_children()
                
                # Show recorded events count
                if self.learn_state.recorded_osc_events:
                    info = Static(f"[green]Recorded: {len(self.learn_state.recorded_osc_events)} controllable events[/]")
                    options_container.mount(info)
            
            elif self.app_mode == AppMode.LEARN_SELECT_MSG:
                status_widget.update(f"[yellow]Select OSC command for pad {self.learn_state.selected_pad}[/]")
                timer_widget.update(f"[cyan]{len(self.learn_state.candidate_commands)} commands available[/]")
                
                options_container.remove_children()
                
                # Show candidate commands
                if self.learn_state.candidate_commands:
                    options_container.mount(Label("[cyan]Candidate Commands:[/]"))
                    for i, cmd in enumerate(self.learn_state.candidate_commands[:10]):  # Show first 10
                        options_container.mount(Label(f"  {i+1}. {cmd}"))
                    if len(self.learn_state.candidate_commands) > 10:
                        options_container.mount(Label(f"  ... and {len(self.learn_state.candidate_commands) - 10} more"))
                else:
                    options_container.mount(Label("[dim]No controllable OSC messages recorded[/]"))
        
        except Exception:
            pass  # UI not ready yet


class CommandSelectionModal(Container):
    """Modal for selecting command and configuring pad."""
    
    candidates: List[OscCommand] = []
    selected_index: int = 0
    
    def compose(self):
        """Compose the modal."""
        with Vertical():
            yield Label("Select OSC Command", classes="modal-title")
            yield ListView(id="command_list")
            yield Label("Pad Type:", classes="section-label")
            yield Horizontal(
                Button("Selector", id="mode_selector", variant="primary"),
                Button("Toggle", id="mode_toggle"),
                Button("One-Shot", id="mode_oneshot"),
                classes="button-row"
            )
            yield Label("Group (for Selector):", classes="section-label")
            yield Horizontal(
                Button("Scenes", id="group_scenes"),
                Button("Presets", id="group_presets"),
                Button("Colors", id="group_colors"),
                Button("Banks", id="group_banks"),
                classes="button-row"
            )
            yield Label("Colors:", classes="section-label")
            yield Horizontal(
                Button("Idle", id="color_idle_select"),
                Static("Red", id="idle_color_preview"),
                classes="button-row"
            )
            yield Horizontal(
                Button("Active", id="color_active_select"),
                Static("Green", id="active_color_preview"),
                classes="button-row"
            )
            yield Label("Label (optional):", classes="section-label")
            yield Input(placeholder="e.g. 'Alien Cavern'", id="pad_label")
            yield Horizontal(
                Button("Save", id="save_learn", variant="success"),
                Button("Cancel", id="cancel_learn", variant="error"),
                classes="button-row"
            )
    
    def set_candidates(self, commands: List[OscCommand]):
        """Set the candidate commands to display."""
        self.candidates = commands
        self.selected_index = 0
        self.update_list()
    
    def update_list(self):
        """Update the command list."""
        try:
            list_view = self.query_one("#command_list", ListView)
            list_view.clear()
            
            for i, cmd in enumerate(self.candidates):
                marker = "► " if i == self.selected_index else "  "
                list_view.append(ListItem(Label(f"{marker}{i+1}. {cmd}")))
        except Exception:
            pass
