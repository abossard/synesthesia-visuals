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
    
    Compatible with lpminimk3's Button.x and Button.y properties.
    - Main 8x8 grid: x, y in range 0-7
    - Top row buttons: x in range 0-7, y = -1
    - Right column buttons: x = 8, y in range 0-7
    
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
