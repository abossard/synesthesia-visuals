"""
Button identification - type-safe (x, y) coordinates.

Uses NamedTuple for type safety while remaining compatible with
lpminimk3.components.Button which has .x and .y properties.
"""

from typing import NamedTuple, TYPE_CHECKING

if TYPE_CHECKING:
    from lpminimk3.components import Button


class ButtonId(NamedTuple):
    """
    Type-safe button identifier using (x, y) coordinates.
    
    Coordinate System (after y-1 fix applied to lpminimk3 events):
    - Main 8x8 grid: x=0-7, y=0-7 (matches LED grid addressing)
    - Top row buttons: x=0-7, y=-1 (Up, Down, Left, Right, Session, Drums, Keys, User)
    - Right column buttons (scene launch): x=8, y=0-7
    
    lpminimk3 Raw Coordinates:
    - panel.y=0 is top row control buttons
    - panel.y=1-8 is the 8x8 grid
    - panel.x=8 is scene launch column
    
    LED Control:
    - Grid: lp.grid.led(x, y) where x=0-7, y=0-7
    - Top row: lp.panel.led(x, 0) where x=0-7
    - Scene launch: lp.panel.led(8, y) where y=0-7 (raw y, not fixed)
    
    Can be used as dictionary keys and compared for equality.
    Immutable and hashable.
    """
    x: int
    y: int
    
    @classmethod
    def from_button(cls, button: 'Button') -> 'ButtonId':
        """Create ButtonId from lpminimk3 Button object."""
        return cls(x=button.x, y=button.y)
    
    def is_grid(self) -> bool:
        """Check if this is a main grid pad (8x8)."""
        return 0 <= self.x <= 7 and 0 <= self.y <= 7
    
    def is_top_row(self) -> bool:
        """Check if this is a top row button."""
        return 0 <= self.x <= 7 and self.y == -1
    
    def is_right_column(self) -> bool:
        """Check if this is a right column button (scene buttons)."""
        return self.x == 8 and 0 <= self.y <= 7
    
    # Alias for standalone app compatibility
    def is_scene_button(self) -> bool:
        """Alias for is_right_column() - check if this is a scene button."""
        return self.is_right_column()
    
    def __str__(self) -> str:
        if self.is_top_row():
            return f"Top{self.x}"
        elif self.is_right_column():
            return f"Scene{self.y}"
        else:
            return f"({self.x},{self.y})"
