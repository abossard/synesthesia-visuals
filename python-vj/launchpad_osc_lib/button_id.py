"""
Button identifier for use with lpminimk3.

Simple (x, y) coordinate tuple that can be used as dictionary keys
and matches lpminimk3's Button.x, Button.y properties.
"""

from dataclasses import dataclass
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from lpminimk3 import Button


@dataclass(frozen=True)
class ButtonId:
    """
    Button identifier using (x, y) coordinates.
    
    Compatible with lpminimk3's Button.x and Button.y properties.
    - Main 8x8 grid: x, y in range 0-7
    - Top row buttons: x in range 0-7, y = -1
    - Right column buttons: x = 8, y in range 0-7
    """
    x: int
    y: int
    
    @classmethod
    def from_button(cls, button: 'Button') -> 'ButtonId':
        """Create ButtonId from lpminimk3 Button."""
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
    
    def __str__(self) -> str:
        if self.is_top_row():
            return f"Top{self.x}"
        elif self.is_right_column():
            return f"Right{self.y}"
        else:
            return f"({self.x},{self.y})"
