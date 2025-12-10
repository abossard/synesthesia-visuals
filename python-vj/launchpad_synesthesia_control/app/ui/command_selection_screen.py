"""
Command Selection Screen - Simple full screen config
"""

from typing import List
from textual.app import ComposeResult
from textual.screen import Screen
from textual.widgets import Static, Button, OptionList, Header, Footer
from textual.widgets.option_list import Option
from textual.containers import Horizontal
from textual.binding import Binding

from launchpad_osc_lib import OscCommand, PadMode, PadGroupName, get_default_button_type


COLOR_PALETTE = [
    ("Red", 5), ("Orange", 9), ("Yellow", 13), ("Green", 21),
    ("Cyan", 37), ("Blue", 45), ("Purple", 53), ("White", 3),
]

MODES = [
    (PadMode.TOGGLE, "Toggle"),
    (PadMode.PUSH, "Push"),
    (PadMode.ONE_SHOT, "One-Shot"),
    (PadMode.SELECTOR, "Selector"),
]

GROUPS = ["scenes", "presets", "colors", "custom"]


class CommandSelectionScreen(Screen):
    """Full screen for configuring a pad - simple layout."""
    
    BINDINGS = [
        Binding("escape", "cancel", "Cancel", show=True),
        Binding("s", "confirm", "Save", show=True),
        Binding("1", "mode_toggle", "Toggle"),
        Binding("2", "mode_push", "Push"),
        Binding("3", "mode_oneshot", "One-Shot"),
        Binding("4", "mode_selector", "Selector"),
    ]
    
    CSS = """
    #info {
        height: 3;
        padding: 1;
        background: $primary;
        color: $text;
    }
    
    #commands {
        height: 1fr;
        border: solid $accent;
    }
    
    #options {
        height: 10;
        padding: 1;
    }
    
    #actions {
        dock: bottom;
        height: 3;
    }
    """
    
    def __init__(self, candidates: List[OscCommand], pad_id: str, **kwargs):
        super().__init__(**kwargs)
        self.candidates = candidates
        self.pad_id = pad_id
        self.selected_mode = PadMode.TOGGLE
        self.selected_color_idle = 0
        self.selected_color_active = 3
        
        if candidates:
            auto_mode, auto_group = get_default_button_type(candidates[0].address)
            self.selected_mode = auto_mode
            self.selected_group = auto_group.value if auto_group else "scenes"
        else:
            self.selected_group = "scenes"
    
    def compose(self) -> ComposeResult:
        yield Header()
        yield Static(f"Configure Pad {self.pad_id} | Mode: [bold]{self.selected_mode.name}[/] | Press 1-4 to change mode, S to save", id="info")
        
        options = [Option(f"{cmd.address} {cmd.args}", id=str(i)) for i, cmd in enumerate(self.candidates[:50])]
        yield OptionList(*options, id="commands")
        
        yield Static(self._build_options_text(), id="options")
        
        with Horizontal(id="actions"):
            yield Button("Save [S]", id="save", variant="success")
            yield Button("Cancel [Esc]", id="cancel", variant="error")
        
        yield Footer()
    
    def _build_options_text(self) -> str:
        mode_line = " | ".join(
            f"[bold green]{i+1}:{m.name}[/]" if m == self.selected_mode else f"{i+1}:{m.name}"
            for i, (m, _) in enumerate(MODES)
        )
        color_idle = COLOR_PALETTE[self.selected_color_idle][0]
        color_active = COLOR_PALETTE[self.selected_color_active][0]
        return f"Mode: {mode_line}\nIdle: {color_idle} | Active: {color_active}"
    
    def _update_info(self):
        self.query_one("#info", Static).update(
            f"Configure Pad {self.pad_id} | Mode: [bold]{self.selected_mode.name}[/] | Press 1-4 to change mode, S to save"
        )
        self.query_one("#options", Static).update(self._build_options_text())
    
    def action_mode_toggle(self):
        self.selected_mode = PadMode.TOGGLE
        self._update_info()
    
    def action_mode_push(self):
        self.selected_mode = PadMode.PUSH
        self._update_info()
    
    def action_mode_oneshot(self):
        self.selected_mode = PadMode.ONE_SHOT
        self._update_info()
    
    def action_mode_selector(self):
        self.selected_mode = PadMode.SELECTOR
        self._update_info()
    
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
        cmd_list = self.query_one("#commands", OptionList)
        idx = cmd_list.highlighted if cmd_list.highlighted is not None else 0
        
        group_enum = PadGroupName(self.selected_group) if self.selected_mode == PadMode.SELECTOR else None
        
        result = {
            "command": self.candidates[idx],
            "mode": self.selected_mode,
            "group": group_enum,
            "idle_color": COLOR_PALETTE[self.selected_color_idle][1],
            "active_color": COLOR_PALETTE[self.selected_color_active][1],
            "label": f"Pad {self.pad_id}",
        }
        self.dismiss(result)
