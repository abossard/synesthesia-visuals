"""
Command Selection Screen - Modal for Learn Mode Configuration

Uses Textual's built-in widgets for reliable selection.
"""

from typing import List
from textual.app import ComposeResult
from textual.screen import ModalScreen
from textual.widgets import Label, Button, Select, RadioButton, RadioSet
from textual.containers import Container, Vertical, Horizontal
from textual.binding import Binding

from launchpad_osc_lib import OscCommand, PadMode, PadGroupName, get_default_button_type


# Color palette: name -> launchpad_color_index
COLOR_PALETTE = [
    ("Red", 5),
    ("Orange", 9),
    ("Yellow", 13),
    ("Green", 21),
    ("Cyan", 37),
    ("Blue", 45),
    ("Purple", 53),
    ("White", 3),
]

MODES = [
    (PadMode.TOGGLE, "Toggle - On/Off switch"),
    (PadMode.PUSH, "Push - Momentary (while held)"),
    (PadMode.ONE_SHOT, "One-Shot - Trigger once"),
    (PadMode.SELECTOR, "Selector - Radio button group"),
]

GROUPS = ["scenes", "presets", "colors", "custom"]


class CommandSelectionScreen(ModalScreen):
    """Modal screen for configuring a pad."""
    
    BINDINGS = [
        Binding("escape", "cancel", "Cancel"),
        Binding("enter", "confirm", "Save"),
    ]
    
    CSS = """
    CommandSelectionScreen {
        align: center middle;
    }
    
    #dialog {
        width: 70;
        height: auto;
        max-height: 90%;
        border: thick $accent;
        background: $surface;
        padding: 1 2;
    }
    
    .title {
        text-align: center;
        text-style: bold;
        color: $accent;
        margin-bottom: 1;
    }
    
    .section-label {
        margin-top: 1;
        color: $text-muted;
    }
    
    Select {
        width: 100%;
        margin-bottom: 1;
    }
    
    RadioSet {
        width: 100%;
        height: auto;
        margin-bottom: 1;
    }
    
    .button-row {
        margin-top: 2;
        align: center middle;
    }
    
    .button-row Button {
        margin: 0 2;
    }
    """
    
    def __init__(self, candidates: List[OscCommand], pad_id: str, **kwargs):
        super().__init__(**kwargs)
        self.candidates = candidates
        self.pad_id = pad_id
        
        # Auto-detect from first candidate
        if candidates:
            auto_mode, auto_group = get_default_button_type(candidates[0].address)
            self.initial_mode = auto_mode
            self.initial_group = auto_group.value if auto_group else "scenes"
        else:
            self.initial_mode = PadMode.TOGGLE
            self.initial_group = "scenes"
    
    def compose(self) -> ComposeResult:
        with Container(id="dialog"):
            yield Label(f"Configure Pad {self.pad_id}", classes="title")
            
            # Command selection
            yield Label("OSC Command:")
            cmd_options = [(f"{cmd.address} {cmd.args}", i) for i, cmd in enumerate(self.candidates[:20])]
            yield Select(cmd_options, id="cmd_select", value=0)
            
            # Mode selection
            yield Label("Button Mode:", classes="section-label")
            with RadioSet(id="mode_select"):
                for mode, label in MODES:
                    yield RadioButton(label, value=mode == self.initial_mode, name=mode.name)
            
            # Group selection
            yield Label("Group (for Selector mode):", classes="section-label")
            group_options = [(g.title(), g) for g in GROUPS]
            yield Select(group_options, id="group_select", value=self.initial_group)
            
            # Color selection
            yield Label("Idle Color:", classes="section-label")
            color_options = [(name, i) for i, (name, _) in enumerate(COLOR_PALETTE)]
            yield Select(color_options, id="idle_color", value=0)
            
            yield Label("Active Color:", classes="section-label")
            yield Select(color_options, id="active_color", value=3)  # Default green
            
            # Buttons
            with Horizontal(classes="button-row"):
                yield Button("Save", id="save", variant="success")
                yield Button("Cancel", id="cancel", variant="error")
    
    def on_button_pressed(self, event: Button.Pressed) -> None:
        if event.button.id == "save":
            self._confirm()
        elif event.button.id == "cancel":
            self.dismiss(None)
    
    def action_cancel(self):
        self.dismiss(None)
    
    def action_confirm(self):
        self._confirm()
    
    def _confirm(self):
        """Gather selections and dismiss with result."""
        # Get command
        cmd_select = self.query_one("#cmd_select", Select)
        cmd_idx = cmd_select.value if cmd_select.value is not None else 0
        
        # Get mode from RadioSet
        mode_set = self.query_one("#mode_select", RadioSet)
        selected_mode = PadMode.TOGGLE
        for btn in mode_set.query(RadioButton):
            if btn.value:
                selected_mode = PadMode[btn.name]
                break
        
        # Get group
        group_select = self.query_one("#group_select", Select)
        selected_group = group_select.value if group_select.value else "scenes"
        
        # Get colors
        idle_select = self.query_one("#idle_color", Select)
        active_select = self.query_one("#active_color", Select)
        idle_idx = idle_select.value if idle_select.value is not None else 0
        active_idx = active_select.value if active_select.value is not None else 3
        
        group_enum = PadGroupName(selected_group) if selected_mode == PadMode.SELECTOR else None
        
        result = {
            "command": self.candidates[cmd_idx],
            "mode": selected_mode,
            "group": group_enum,
            "idle_color": COLOR_PALETTE[idle_idx][1],
            "active_color": COLOR_PALETTE[active_idx][1],
            "label": f"Pad {self.pad_id}",
        }
        self.dismiss(result)
