"""
Domain Models for Launchpad Standalone

Immutable data structures for learn mode state and configuration.
"""

from dataclasses import dataclass, field
from enum import Enum, auto
from typing import Optional, List, Dict, Any

# Import shared brightness utilities from launchpad_osc_lib
try:
    from launchpad_osc_lib.model import (
        BrightnessLevel,
        BASE_COLORS,
        BASE_COLOR_NAMES,
        get_color_at_brightness,
        get_base_color_from_velocity,
    )
except ImportError:
    # Fallback if launchpad_osc_lib not available (shouldn't happen in normal use)
    import sys
    sys.path.insert(0, str(__file__).replace('/launchpad_standalone/model.py', ''))
    from launchpad_osc_lib.model import (
        BrightnessLevel,
        BASE_COLORS,
        BASE_COLOR_NAMES,
        get_color_at_brightness,
        get_base_color_from_velocity,
    )


# =============================================================================
# PAD AND COLOR DEFINITIONS
# =============================================================================

@dataclass(frozen=True)
class PadId:
    """Unique identifier for a Launchpad pad."""
    x: int
    y: int
    
    def is_grid(self) -> bool:
        """Check if this is a main grid pad (8x8)."""
        return 0 <= self.x <= 7 and 0 <= self.y <= 7
    
    def is_scene_button(self) -> bool:
        """Check if this is a right column scene button."""
        return self.x == 8 and 0 <= self.y <= 7
    
    def __str__(self) -> str:
        if self.is_scene_button():
            return f"Scene{self.y}"
        return f"({self.x},{self.y})"


# Launchpad Mini MK3 color palette (velocity values)
# Format: (name, velocity, hex_color)
COLOR_PALETTE = [
    ("Off", 0, "#000000"),
    ("Red Dim", 1, "#1A0000"),
    ("Red", 5, "#FF0000"),
    ("Red Bright", 6, "#FF3333"),
    ("Orange Dim", 7, "#331A00"),
    ("Orange", 9, "#FF6600"),
    ("Orange Bright", 10, "#FF8533"),
    ("Yellow Dim", 11, "#333300"),
    ("Yellow", 13, "#FFFF00"),
    ("Yellow Bright", 14, "#FFFF33"),
    ("Lime Dim", 15, "#1A3300"),
    ("Lime", 17, "#66FF00"),
    ("Lime Bright", 18, "#99FF33"),
    ("Green Dim", 19, "#003300"),
    ("Green", 21, "#00FF00"),
    ("Green Bright", 22, "#33FF33"),
    ("Cyan Dim", 33, "#003333"),
    ("Cyan", 37, "#00FFFF"),
    ("Cyan Bright", 38, "#33FFFF"),
    ("Blue Dim", 41, "#000033"),
    ("Blue", 45, "#0000FF"),
    ("Blue Bright", 46, "#3333FF"),
    ("Purple Dim", 49, "#1A0033"),
    ("Purple", 53, "#9900FF"),
    ("Purple Bright", 54, "#AA33FF"),
    ("Pink Dim", 55, "#330033"),
    ("Pink", 57, "#FF00FF"),
    ("Pink Bright", 58, "#FF33FF"),
    ("White Dim", 1, "#333333"),
    ("White", 3, "#FFFFFF"),
    ("White Bright", 119, "#FFFFFF"),
]

# Common color shortcuts
LP_OFF = 0
LP_RED = 5
LP_RED_DIM = 1
LP_ORANGE = 9
LP_YELLOW = 13
LP_GREEN = 21
LP_GREEN_DIM = 19
LP_CYAN = 37
LP_BLUE = 45
LP_BLUE_DIM = 41
LP_PURPLE = 53
LP_PINK = 57
LP_WHITE = 3

# 16-color preview palette for color selection (4x4 grid on bottom-left)
COLOR_PREVIEW_PALETTE = [
    LP_RED, LP_ORANGE, LP_YELLOW, LP_GREEN,
    LP_CYAN, LP_BLUE, LP_PURPLE, LP_PINK,
    1, 7, 19, 33,   # Dim versions
    41, 49, 55, LP_WHITE,
]


# =============================================================================
# PAD MODES
# =============================================================================

class PadMode(Enum):
    """Pad interaction mode."""
    SELECTOR = auto()  # Radio button behavior (only one active in group)
    TOGGLE = auto()    # On/Off toggle
    ONE_SHOT = auto()  # Single action on press
    PUSH = auto()      # Momentary - 1.0 on press, 0.0 on release


# =============================================================================
# LEARN MODE STATE
# =============================================================================

class LearnPhase(Enum):
    """Phases within learn mode."""
    IDLE = auto()           # Normal operation
    WAIT_PAD = auto()       # Blinking all pads, waiting for pad selection
    RECORD_OSC = auto()     # Recording OSC after pad selected
    CONFIG = auto()         # Configuration phase - selecting options


class LearnRegister(Enum):
    """Register (configuration section) in learn config phase."""
    OSC_SELECT = auto()     # Selecting which OSC command
    MODE_SELECT = auto()    # Selecting button mode
    COLOR_SELECT = auto()   # Selecting colors


@dataclass(frozen=True)
class OscCommand:
    """OSC command to send."""
    address: str
    args: List[Any] = field(default_factory=list)
    
    def __str__(self) -> str:
        args_str = " ".join(str(a) for a in self.args) if self.args else ""
        return f"{self.address} {args_str}".strip()


@dataclass(frozen=True)
class OscEvent:
    """Received OSC event with timestamp."""
    timestamp: float
    address: str
    args: List[Any] = field(default_factory=list)
    priority: int = 99  # Lower = higher priority (scene=1, preset=2, etc.)
    
    def to_command(self) -> OscCommand:
        """Convert to OscCommand (without timestamp)."""
        return OscCommand(address=self.address, args=list(self.args))


@dataclass(frozen=True)
class LearnState:
    """
    Immutable state for learn mode.
    
    All state transitions create new LearnState instances.
    """
    phase: LearnPhase = LearnPhase.IDLE
    
    # Pad selection
    selected_pad: Optional[PadId] = None
    
    # OSC recording
    recorded_events: List[OscEvent] = field(default_factory=list)
    candidate_commands: List[OscCommand] = field(default_factory=list)
    
    # Configuration phase
    active_register: LearnRegister = LearnRegister.OSC_SELECT
    selected_osc_index: int = 0
    selected_mode: PadMode = PadMode.TOGGLE
    selected_idle_color: int = LP_GREEN_DIM
    selected_active_color: int = LP_GREEN
    
    # Brightness levels for color selection (DIM=0, NORMAL=1, BRIGHT=2)
    # Default: idle at normal brightness, active at full brightness
    idle_brightness: BrightnessLevel = BrightnessLevel.NORMAL
    active_brightness: BrightnessLevel = BrightnessLevel.BRIGHT
    
    # Pagination for OSC commands (8 per page)
    osc_page: int = 0


# =============================================================================
# PAD CONFIGURATION (saved to disk)
# =============================================================================

@dataclass(frozen=True)
class PadConfig:
    """Configuration for a single pad (persisted)."""
    pad_id: PadId
    mode: PadMode
    osc_command: OscCommand
    idle_color: int = LP_GREEN_DIM
    active_color: int = LP_GREEN
    label: str = ""
    group: Optional[str] = None  # For SELECTOR mode


@dataclass
class ControllerConfig:
    """Complete controller configuration (mutable for loading/saving)."""
    pads: Dict[str, PadConfig] = field(default_factory=dict)
    
    def add_pad(self, config: PadConfig):
        """Add or update a pad configuration."""
        key = f"{config.pad_id.x},{config.pad_id.y}"
        self.pads[key] = config
    
    def get_pad(self, pad_id: PadId) -> Optional[PadConfig]:
        """Get configuration for a pad."""
        key = f"{pad_id.x},{pad_id.y}"
        return self.pads.get(key)
    
    def remove_pad(self, pad_id: PadId):
        """Remove configuration for a pad."""
        key = f"{pad_id.x},{pad_id.y}"
        if key in self.pads:
            del self.pads[key]


# =============================================================================
# RUNTIME STATE
# =============================================================================

@dataclass(frozen=True)
class PadRuntimeState:
    """Runtime state for a single pad."""
    is_active: bool = False
    is_on: bool = False  # For toggle mode
    current_color: int = LP_OFF


@dataclass(frozen=True)
class AppState:
    """Complete application state."""
    learn: LearnState = field(default_factory=LearnState)
    config: Optional[ControllerConfig] = None
    pad_runtime: Dict[str, PadRuntimeState] = field(default_factory=dict)
    
    # Selector group state (which pad is active in each group)
    active_by_group: Dict[str, PadId] = field(default_factory=dict)
    
    # Blink state for learn mode
    blink_on: bool = False


# =============================================================================
# LED EFFECTS
# =============================================================================

@dataclass(frozen=True)
class LedEffect:
    """Set a single LED."""
    pad_id: PadId
    color: int
    blink: bool = False


@dataclass(frozen=True)
class SendOscEffect:
    """Send an OSC command."""
    command: OscCommand


@dataclass(frozen=True)
class SaveConfigEffect:
    """Save configuration to disk."""
    config: ControllerConfig


@dataclass(frozen=True)
class LogEffect:
    """Log a message."""
    message: str
    level: str = "INFO"
