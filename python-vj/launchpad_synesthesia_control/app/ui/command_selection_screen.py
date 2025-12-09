"""
Command Selection Screen - Modal for Learn Mode Configuration

Keyboard-navigable interface for selecting OSC commands and configuring pads.
"""

from typing import List, Optional
from textual.app import ComposeResult
from textual.screen import ModalScreen
from textual.widgets import Static, Label, Input, ListView, ListItem
from textual.containers import Container, Vertical, Horizontal, VerticalScroll
from textual.binding import Binding
from textual import on

from ..domain.model import OscCommand, PadMode, PadGroupName, COLOR_PALETTE as LP_COLORS


# Color palette: name -> (display_name, launchpad_color_index)
COLOR_PALETTE = {
    "red": ("Red", 5),
    "orange": ("Orange", 9),
    "yellow": ("Yellow", 13),
    "green": ("Green", 21),
    "cyan": ("Cyan", 37),
    "blue": ("Blue", 45),
    "purple": ("Purple", 53),
    "white": ("White", 3),
}

COLOR_NAMES = list(COLOR_PALETTE.keys())


class CommandSelectionScreen(ModalScreen):
    """Modal screen for selecting command and configuring pad in Learn Mode."""
    
    BINDINGS = [
        Binding("escape", "cancel", "Cancel"),
        Binding("enter", "confirm", "Confirm"),
        Binding("up", "cursor_up", "Up", show=False),
        Binding("down", "cursor_down", "Down", show=False),
        Binding("tab", "next_field", "Next Field", show=False),
        Binding("s", "mode_selector", "Selector", show=False),
        Binding("t", "mode_toggle", "Toggle", show=False),
        Binding("o", "mode_oneshot", "One-Shot", show=False),
        Binding("1,2,3,4,5,6,7,8,9", "number_select", "Select", show=False),
    ]
    
    CSS = """
    CommandSelectionScreen {
        align: center middle;
    }
    
    #dialog {
        width: 80;
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
    
    .section-title {
        text-style: bold;
        color: $secondary;
        margin-top: 1;
    }
    
    .option-row {
        height: 3;
        margin: 0 1;
    }
    
    .selected {
        background: $accent;
        color: $text;
    }
    
    .help-text {
        color: $text-muted;
        text-align: center;
        margin-top: 1;
    }
    
    #command_list {
        height: 10;
        border: solid $primary;
    }
    """
    
    def __init__(
        self,
        candidates: List[OscCommand],
        pad_id: str,
        **kwargs
    ):
        super().__init__(**kwargs)
        self.candidates = candidates
        self.pad_id = pad_id
        self.selected_command_idx = 0
        self.selected_mode = PadMode.SELECTOR
        self.selected_group = "scenes"
        self.idle_color_idx = 0  # Index into COLOR_NAMES
        self.active_color_idx = 3  # Default to green for active
        self.label_text = ""
        self.current_field = "command"  # command, mode, group, idle_color, active_color, label
    
    def compose(self) -> ComposeResult:
        """Compose the modal dialog."""
        with Container(id="dialog"):
            yield Label(f"Configure Pad {self.pad_id}", classes="title")
            
            # Command selection
            yield Label("OSC Command (↑/↓ or 1-9):", classes="section-title")
            with VerticalScroll(id="command_list"):
                for i, cmd in enumerate(self.candidates[:20]):  # Show first 20
                    marker = "► " if i == self.selected_command_idx else "  "
                    yield Label(f"{marker}{i+1}. {cmd.address} {cmd.args}")
            
            # Pad type selection
            yield Label("Pad Type (Tab or S/T/O):", classes="section-title")
            with Horizontal(classes="option-row"):
                yield Static("Selector", id="mode_selector", classes="selected" if self.selected_mode == PadMode.SELECTOR else "")
                yield Static("Toggle", id="mode_toggle", classes="selected" if self.selected_mode == PadMode.TOGGLE else "")
                yield Static("One-Shot", id="mode_oneshot", classes="selected" if self.selected_mode == PadMode.ONE_SHOT else "")
            
            # Group selection (only for selector)
            yield Label("Group (for Selector, Tab to cycle):", classes="section-title", id="group_label")
            with Horizontal(classes="option-row", id="group_row"):
                for group in ["scenes", "presets", "colors", "custom"]:
                    yield Static(group.title(), id=f"group_{group}", classes="selected" if group == self.selected_group else "")
            
            # Color selection
            yield Label(f"Idle Color (Tab/1-8): {COLOR_NAMES[self.idle_color_idx].title()}", classes="section-title", id="idle_color_label")
            with Horizontal(classes="option-row", id="idle_color_row"):
                for i, color in enumerate(COLOR_NAMES[:8]):
                    yield Static(color[0].upper(), id=f"idle_color_{i}", classes="selected" if i == self.idle_color_idx else "")
            
            yield Label(f"Active Color (Tab/1-8): {COLOR_NAMES[self.active_color_idx].title()}", classes="section-title", id="active_color_label")
            with Horizontal(classes="option-row", id="active_color_row"):
                for i, color in enumerate(COLOR_NAMES[:8]):
                    yield Static(color[0].upper(), id=f"active_color_{i}", classes="selected" if i == self.active_color_idx else "")
            
            # Label input
            yield Label("Label (optional, type and press Enter):", classes="section-title")
            yield Input(placeholder="e.g., 'Scene 1' or 'Strobe'", id="label_input")
            
            yield Label("[Enter: Save Configuration]  [ESC: Cancel]", classes="help-text")
    
    def action_cursor_up(self):
        """Move selection up in command list."""
        if self.current_field == "command" and self.selected_command_idx > 0:
            self.selected_command_idx -= 1
            self.update_command_list()
    
    def action_cursor_down(self):
        """Move selection down in command list."""
        if self.current_field == "command" and self.selected_command_idx < len(self.candidates) - 1:
            self.selected_command_idx += 1
            self.update_command_list()
    
    def action_next_field(self):
        """Cycle to next field with Tab."""
        fields = ["command", "mode", "group", "idle_color", "active_color", "label"]
        current_idx = fields.index(self.current_field)
        self.current_field = fields[(current_idx + 1) % len(fields)]
        
        # Apply field-specific actions
        if self.current_field == "mode":
            # Cycle mode
            modes = [PadMode.SELECTOR, PadMode.TOGGLE, PadMode.ONE_SHOT]
            current_mode_idx = modes.index(self.selected_mode)
            self.selected_mode = modes[(current_mode_idx + 1) % len(modes)]
            self.update_mode_display()
        elif self.current_field == "group":
            # Cycle group
            groups = ["scenes", "presets", "colors", "custom"]
            current_group_idx = groups.index(self.selected_group)
            self.selected_group = groups[(current_group_idx + 1) % len(groups)]
            self.update_group_display()
        elif self.current_field == "idle_color":
            # Cycle idle color
            self.idle_color_idx = (self.idle_color_idx + 1) % len(COLOR_NAMES)
            self.update_color_display()
        elif self.current_field == "active_color":
            # Cycle active color
            self.active_color_idx = (self.active_color_idx + 1) % len(COLOR_NAMES)
            self.update_color_display()
        elif self.current_field == "label":
            # Focus label input
            try:
                self.query_one("#label_input", Input).focus()
            except:
                pass
    
    def action_mode_selector(self):
        """Set mode to SELECTOR."""
        self.selected_mode = PadMode.SELECTOR
        self.update_mode_display()
    
    def action_mode_toggle(self):
        """Set mode to TOGGLE."""
        self.selected_mode = PadMode.TOGGLE
        self.update_mode_display()
    
    def action_mode_oneshot(self):
        """Set mode to ONE_SHOT."""
        self.selected_mode = PadMode.ONE_SHOT
        self.update_mode_display()
    
    def action_number_select(self, key: str):
        """Handle number key press for direct selection."""
        try:
            num = int(key) - 1
            if self.current_field == "command" and 0 <= num < len(self.candidates):
                self.selected_command_idx = num
                self.update_command_list()
            elif self.current_field in ("idle_color", "active_color") and 0 <= num < len(COLOR_NAMES):
                if self.current_field == "idle_color":
                    self.idle_color_idx = num
                else:
                    self.active_color_idx = num
                self.update_color_display()
        except ValueError:
            pass
    
    def action_cancel(self):
        """Cancel and close without saving."""
        self.dismiss(None)
    
    def action_confirm(self):
        """Confirm selection and save configuration."""
        # Get label from input
        try:
            label_input = self.query_one("#label_input", Input)
            self.label_text = label_input.value.strip()
        except:
            self.label_text = ""
        
        # Build result
        result = {
            "command": self.candidates[self.selected_command_idx],
            "mode": self.selected_mode,
            "group": self.selected_group if self.selected_mode == PadMode.SELECTOR else None,
            "idle_color": COLOR_PALETTE[COLOR_NAMES[self.idle_color_idx]][1],
            "active_color": COLOR_PALETTE[COLOR_NAMES[self.active_color_idx]][1],
            "label": self.label_text or f"Pad {self.pad_id}",
        }
        
        self.dismiss(result)
    
    def update_command_list(self):
        """Update the command list display."""
        try:
            scroll = self.query_one("#command_list", VerticalScroll)
            scroll.remove_children()
            for i, cmd in enumerate(self.candidates[:20]):
                marker = "► " if i == self.selected_command_idx else "  "
                scroll.mount(Label(f"{marker}{i+1}. {cmd.address} {cmd.args}"))
        except Exception:
            pass
    
    def update_mode_display(self):
        """Update mode selection display."""
        try:
            for mode_val, mode_id in [(PadMode.SELECTOR, "mode_selector"), 
                                       (PadMode.TOGGLE, "mode_toggle"), 
                                       (PadMode.ONE_SHOT, "mode_oneshot")]:
                widget = self.query_one(f"#{mode_id}", Static)
                if mode_val == self.selected_mode:
                    widget.add_class("selected")
                else:
                    widget.remove_class("selected")
        except Exception:
            pass
    
    def update_group_display(self):
        """Update group selection display."""
        try:
            for group in ["scenes", "presets", "colors", "custom"]:
                widget = self.query_one(f"#group_{group}", Static)
                if group == self.selected_group:
                    widget.add_class("selected")
                else:
                    widget.remove_class("selected")
        except Exception:
            pass
    
    def update_color_display(self):
        """Update color selection display."""
        try:
            # Update idle color
            for i in range(len(COLOR_NAMES)):
                widget = self.query_one(f"#idle_color_{i}", Static)
                if i == self.idle_color_idx:
                    widget.add_class("selected")
                else:
                    widget.remove_class("selected")
            
            # Update active color
            for i in range(len(COLOR_NAMES)):
                widget = self.query_one(f"#active_color_{i}", Static)
                if i == self.active_color_idx:
                    widget.add_class("selected")
                else:
                    widget.remove_class("selected")
            
            # Update labels
            idle_label = self.query_one("#idle_color_label", Label)
            idle_label.update(f"Idle Color (Tab/1-8): {COLOR_NAMES[self.idle_color_idx].title()}")
            
            active_label = self.query_one("#active_color_label", Label)
            active_label.update(f"Active Color (Tab/1-8): {COLOR_NAMES[self.active_color_idx].title()}")
        except Exception:
            pass
