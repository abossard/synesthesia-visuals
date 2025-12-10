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


# Full Launchpad Mini MK3 color palette (128 colors, velocity 0-127)
# Organized by color family for easier selection
# Format: (name, velocity, hex_color_for_preview)
COLOR_PALETTE = [
    # Row 0: Off and basics
    ("Off", 0, "#000000"),
    ("DkGray", 1, "#1E1E1E"),
    ("Gray", 2, "#7F7F7F"),
    ("White", 3, "#FFFFFF"),
    # Row 1: Reds
    ("Red1", 4, "#FF4C4C"),
    ("Red", 5, "#FF0000"),
    ("Red3", 6, "#590000"),
    ("Red4", 7, "#190000"),
    # Row 2: Oranges
    ("Org1", 8, "#FFBD6C"),
    ("Orange", 9, "#FF5400"),
    ("Org3", 10, "#591D00"),
    ("Org4", 11, "#271B00"),
    # Row 3: Yellows
    ("Yel1", 12, "#FFFF4C"),
    ("Yellow", 13, "#FFFF00"),
    ("Yel3", 14, "#595900"),
    ("Yel4", 15, "#191900"),
    # Row 4: Lime/Chartreuse
    ("Lime1", 16, "#88FF4C"),
    ("Lime", 17, "#54FF00"),
    ("Lime3", 18, "#1D5900"),
    ("Lime4", 19, "#142B00"),
    # Row 5: Greens
    ("Grn1", 20, "#4CFF4C"),
    ("Green", 21, "#00FF00"),
    ("Grn3", 22, "#005900"),
    ("Grn4", 23, "#001900"),
    # Row 6: Spring greens
    ("Spg1", 24, "#4CFF5E"),
    ("Spring", 25, "#00FF36"),
    ("Spg3", 26, "#00590D"),
    ("Spg4", 27, "#001902"),
    # Row 7: Teals
    ("Teal1", 28, "#4CFF88"),
    ("Teal", 29, "#00FF54"),
    ("Teal3", 30, "#00591D"),
    ("Teal4", 31, "#001F12"),
    # Row 8: Cyans
    ("Cyn1", 32, "#4CFFB7"),
    ("Cyan", 37, "#00FFFF"),
    ("Cyn3", 34, "#005932"),
    ("Cyn4", 35, "#001912"),
    # Row 9: Sky blues
    ("Sky1", 36, "#4CC3FF"),
    ("Sky", 33, "#00A9FF"),
    ("Sky3", 38, "#004152"),
    ("Sky4", 39, "#001019"),
    # Row 10: Blues
    ("Blu1", 40, "#4C88FF"),
    ("Blue", 45, "#0000FF"),
    ("Blu3", 42, "#001D59"),
    ("Blu4", 43, "#000819"),
    # Row 11: Indigos
    ("Ind1", 44, "#4C4CFF"),
    ("Indigo", 41, "#0054FF"),
    ("Ind3", 46, "#090059"),
    ("Ind4", 47, "#020019"),
    # Row 12: Purples
    ("Pur1", 48, "#874CFF"),
    ("Purple", 53, "#5400FF"),
    ("Pur3", 50, "#190059"),
    ("Pur4", 51, "#0F0030"),
    # Row 13: Violets
    ("Vio1", 52, "#BC4CFF"),
    ("Violet", 49, "#9400FF"),
    ("Vio3", 54, "#2E0059"),
    ("Vio4", 55, "#140019"),
    # Row 14: Magentas
    ("Mag1", 56, "#FF4CFF"),
    ("Magenta", 57, "#FF00FF"),
    ("Mag3", 58, "#590059"),
    ("Mag4", 59, "#190019"),
    # Row 15: Pinks
    ("Pnk1", 60, "#FF4C87"),
    ("Pink", 61, "#FF0054"),
    ("Pnk3", 62, "#59001D"),
    ("Pnk4", 63, "#220013"),
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
        Binding("q", "idle_prev", "Idle-"),
        Binding("w", "idle_next", "Idle+"),
        Binding("a", "active_prev", "Active-"),
        Binding("d", "active_next", "Active+"),  # Changed from 's' to avoid conflict
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
        # Show current color with preview block
        idle_name, idle_val, idle_hex = COLOR_PALETTE[self.selected_color_idle]
        active_name, active_val, active_hex = COLOR_PALETTE[self.selected_color_active]
        
        # Create color preview blocks using Rich markup
        idle_block = f"[on {idle_hex}]      [/]"
        active_block = f"[on {active_hex}]      [/]"
        
        return (
            f"Mode (1-4): {mode_line}\n"
            f"Idle (Q/W):   {idle_block} [{self.selected_color_idle:2d}] {idle_name}\n"
            f"Active (A/D): {active_block} [{self.selected_color_active:2d}] {active_name}"
        )
    
    def action_idle_prev(self):
        self.selected_color_idle = (self.selected_color_idle - 1) % len(COLOR_PALETTE)
        self._update_info()
    
    def action_idle_next(self):
        self.selected_color_idle = (self.selected_color_idle + 1) % len(COLOR_PALETTE)
        self._update_info()
    
    def action_active_prev(self):
        self.selected_color_active = (self.selected_color_active - 1) % len(COLOR_PALETTE)
        self._update_info()
    
    def action_active_next(self):
        self.selected_color_active = (self.selected_color_active + 1) % len(COLOR_PALETTE)
        self._update_info()
    
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
            "idle_color": COLOR_PALETTE[self.selected_color_idle][1],  # velocity value
            "active_color": COLOR_PALETTE[self.selected_color_active][1],  # velocity value
            "label": f"Pad {self.pad_id}",
        }
        self.dismiss(result)
