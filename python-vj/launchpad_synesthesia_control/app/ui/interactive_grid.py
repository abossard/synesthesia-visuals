"""
Interactive Launchpad Grid Widget

Clickable grid that works without physical hardware.
"""

from textual.widgets import Button, Label, DataTable
from textual.containers import Container, Grid as GridContainer
from textual.reactive import reactive
from textual.message import Message

from ..domain.model import PadId, ControllerState


class PadButton(Button):
    """A single pad button in the grid."""
    
    def __init__(self, pad_id: PadId, *args, **kwargs):
        super().__init__("·", *args, **kwargs)
        self.pad_id = pad_id
        self.add_class("pad-button")
    
    def update_appearance(self, state: ControllerState):
        """Update button appearance based on controller state."""
        if self.pad_id not in state.pads:
            self.label = "·"
            self.variant = "default"
            return
        
        behavior = state.pads[self.pad_id]
        runtime = state.pad_runtime.get(self.pad_id)
        
        if runtime and (runtime.is_active or runtime.is_on):
            self.label = "●"
            self.variant = "success"
        else:
            self.label = "○"
            self.variant = "primary"


class InteractiveLaunchpadGrid(Container):
    """Interactive grid of pad buttons."""
    
    state: reactive[ControllerState] = reactive(ControllerState)
    
    class PadPressed(Message):
        """Message sent when a pad is pressed."""
        
        def __init__(self, pad_id: PadId):
            super().__init__()
            self.pad_id = pad_id
    
    def compose(self):
        """Compose the interactive grid."""
        yield Label("Launchpad Mini Mk3 [dim](Click pads to select)[/]", classes="panel-title")
        
        with GridContainer(id="pad_grid"):
            # Top row (y=-1)
            for x in range(8):
                yield PadButton(PadId(x, -1), id=f"pad_{x}_-1")
            
            # Main grid (8x8) + right column
            for y in range(8):
                for x in range(8):
                    yield PadButton(PadId(x, y), id=f"pad_{x}_{y}")
                # Right column
                yield PadButton(PadId(8, y), id=f"pad_8_{y}")
    
    def watch_state(self, new_state: ControllerState):
        """Update all pad buttons when state changes."""
        for widget in self.query(PadButton):
            widget.update_appearance(new_state)
    
    async def on_button_pressed(self, event: Button.Pressed):
        """Handle pad button press."""
        if isinstance(event.button, PadButton):
            # Prevent button from handling the click itself
            event.stop()
            # Post message to parent
            self.post_message(self.PadPressed(event.button.pad_id))


# CSS for the interactive grid
INTERACTIVE_GRID_CSS = """
#pad_grid {
    grid-size: 9 9;
    grid-columns: 1fr 1fr 1fr 1fr 1fr 1fr 1fr 1fr 1fr;
    grid-rows: 1fr 1fr 1fr 1fr 1fr 1fr 1fr 1fr 1fr;
    height: auto;
    padding: 1;
}

.pad-button {
    width: 100%;
    height: 1;
    min-width: 3;
    padding: 0 1;
}
"""
