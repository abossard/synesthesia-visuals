"""
Domain Models for Pad Mapping

Immutable data structures for pad configuration and runtime state.
"""

from dataclasses import dataclass, field
from enum import Enum, auto
from typing import Optional, List, Any

from .launchpad import PadId


# =============================================================================
# PAD MODES AND GROUP TYPES
# =============================================================================

class PadMode(Enum):
    """Pad interaction mode."""
    SELECTOR = auto()  # Radio button behavior within a group (only one active)
    TOGGLE = auto()    # On/Off toggle with two OSC commands
    ONE_SHOT = auto()  # Single action on press, no persistent state


class ButtonGroupType(str, Enum):
    """
    Predefined button group types.
    
    Groups determine radio-button behavior for SELECTOR mode pads.
    When a pad in a group is pressed, all other pads in that group are deselected.
    """
    SCENES = "scenes"
    PRESETS = "presets"
    COLORS = "colors"
    CUSTOM = "custom"


# =============================================================================
# OSC COMMAND
# =============================================================================

@dataclass(frozen=True)
class OscCommand:
    """
    OSC command to send.
    
    Attributes:
        address: OSC address pattern (e.g., "/scenes/AlienCavern")
        args: List of arguments (strings, floats, ints)
    """
    address: str
    args: List[Any] = field(default_factory=list)
    
    def __str__(self) -> str:
        args_str = " ".join(str(a) for a in self.args) if self.args else ""
        return f"{self.address} {args_str}".strip()
    
    @staticmethod
    def is_controllable(address: str) -> bool:
        """
        Check if this OSC address is controllable (can be mapped to pads).
        
        Delegates to synesthesia_config.is_controllable().
        """
        from .synesthesia_config import is_controllable
        return is_controllable(address)


# =============================================================================
# PAD BEHAVIOR CONFIGURATION
# =============================================================================

@dataclass(frozen=True)
class PadBehavior:
    """
    Configuration for how a pad behaves.
    
    Attributes:
        pad_id: Pad identifier
        mode: Interaction mode (SELECTOR/TOGGLE/ONE_SHOT)
        group: Group name (required for SELECTOR mode)
        idle_color: Launchpad color index when inactive
        active_color: Launchpad color index when active
        label: Optional human-readable label
        
    For TOGGLE mode:
        osc_on: Command to send when toggling ON
        osc_off: Optional command to send when toggling OFF (if None, no message sent on OFF)
    
    For SELECTOR and ONE_SHOT modes:
        osc_action: Command to send on press
    """
    pad_id: PadId
    mode: PadMode
    group: Optional[ButtonGroupType] = None
    idle_color: int = 0
    active_color: int = 5
    label: str = ""
    
    # Toggle-specific
    osc_on: Optional[OscCommand] = None
    osc_off: Optional[OscCommand] = None
    
    # Selector/One-shot specific
    osc_action: Optional[OscCommand] = None
    
    def __post_init__(self):
        """Validate configuration."""
        if self.mode == PadMode.TOGGLE:
            if self.osc_on is None:
                raise ValueError("TOGGLE mode requires osc_on")
        elif self.mode in (PadMode.SELECTOR, PadMode.ONE_SHOT):
            if self.osc_action is None:
                raise ValueError(f"{self.mode.name} mode requires osc_action")
        
        if self.mode == PadMode.SELECTOR and self.group is None:
            raise ValueError("SELECTOR mode requires group")


# =============================================================================
# PAD RUNTIME STATE
# =============================================================================

@dataclass(frozen=True)
class PadRuntimeState:
    """
    Runtime state of a pad (changes during operation).
    
    Attributes:
        is_active: Whether pad is currently highlighted/active (for SELECTOR)
        is_on: Current toggle state (for TOGGLE mode)
        current_color: Current LED color index
        blink_enabled: Whether this pad should blink with beat
    """
    is_active: bool = False
    is_on: bool = False
    current_color: int = 0
    blink_enabled: bool = False
