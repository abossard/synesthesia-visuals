"""Modal screens for VJ Console."""

from textual.app import ComposeResult
from textual.binding import Binding
from textual.containers import Horizontal, Vertical
from textual.screen import ModalScreen
from textual.widgets import Button, Input, Label


class ShaderSearchModal(ModalScreen):
    """Modal for text-based shader search."""

    BINDINGS = [
        Binding("escape", "dismiss", "Cancel"),
    ]

    def __init__(self):
        super().__init__()
        self.search_query = ""

    def compose(self) -> ComposeResult:
        with Vertical(id="shader-search-modal"):
            yield Label("[bold cyan]🔍 Search Shaders[/]")
            yield Label("[dim]Search by: name, mood, colors, effects, description, geometry, objects, inputNames[/]\n")
            yield Label("Examples: love, colorful, psychedelic, distortion, bloom, waves, particles")
            yield Input(placeholder="Enter search term...", id="search-input")
            with Horizontal(id="modal-buttons"):
                yield Button("Search", variant="primary", id="search-btn")
                yield Button("Cancel", variant="default", id="cancel-btn")

    def on_mount(self) -> None:
        """Focus the input when modal opens."""
        self.query_one("#search-input", Input).focus()

    def on_input_submitted(self, event: Input.Submitted) -> None:
        """Handle enter key in input."""
        self.search_query = event.value.strip()
        if self.search_query:
            self.dismiss(self.search_query)

    def on_button_pressed(self, event: Button.Pressed) -> None:
        """Handle button press."""
        if event.button.id == "search-btn":
            inp = self.query_one("#search-input", Input)
            self.search_query = inp.value.strip()
            if self.search_query:
                self.dismiss(self.search_query)
        elif event.button.id == "cancel-btn":
            self.dismiss(None)
