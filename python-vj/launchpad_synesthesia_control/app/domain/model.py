"""
Domain Models - Immutable Data Structures

Pure domain models following Grokking Simplicity principles.
All data structures are immutable (frozen dataclasses).
"""

from dataclasses import dataclass, field
from typing import Optional, List, Dict, Any, Tuple
from enum import Enum, auto


# =============================================================================
# PAD IDENTIFIERS AND LAYOUT
# =============================================================================

@dataclass(frozen=True)
class PadId:
    """
    Unique identifier for a Launchpad pad.
    
    For 8x8 grid: x, y in range 0-7
    For top row: x in range 0-7, y = -1
    For right column: x = 8, y in range 0-7
    """
    x: int
    y: int
    
    def is_grid(self) -> bool:
        """Check if this is a main grid pad (8x8)."""
        return 0 <= self.x <= 7 and 0 <= self.y <= 7
    
    def is_top_row(self) -> bool:
        """Check if this is a top row button."""
        return 0 <= self.x <= 7 and self.y == -1
    
    def is_right_column(self) -> bool:
        """Check if this is a right column button."""
        return self.x == 8 and 0 <= self.y <= 7
    
    def __str__(self) -> str:
        if self.is_top_row():
            return f"Top{self.x}"
        elif self.is_right_column():
            return f"Right{self.y}"
        else:
            return f"({self.x},{self.y})"


# =============================================================================
# PAD MODES AND GROUPS
# =============================================================================

class PadMode(Enum):
    """Pad interaction mode."""
    SELECTOR = auto()  # Radio button behavior within a group
    TOGGLE = auto()    # On/Off toggle with two OSC commands
    ONE_SHOT = auto()  # Single action on press


class PadGroupName(str, Enum):
    """Predefined pad groups for selectors."""
    SCENES = "scenes"
    PRESETS = "presets"
    BANKS = "banks"
    COLORS = "colors"
    CUSTOM = "custom"


# =============================================================================
# OSC COMMANDS
# =============================================================================

@dataclass(frozen=True)
class OscCommand:
    """
    OSC command to send to Synesthesia.
    
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
        """Check if this OSC address is controllable (can be mapped to pads)."""
        controllable_prefixes = [
            "/scenes/",
            "/presets/",
            "/favslots/",
            "/playlist/",
            "/controls/meta/",
            "/controls/global/"
        ]
        return any(address.startswith(prefix) for prefix in controllable_prefixes)


@dataclass(frozen=True)
class OscEvent:
    """
    Received OSC event with timestamp.
    
    timestamp: Unix timestamp when received
    address: OSC address
    args: List of arguments
    """
    timestamp: float
    address: str
    args: List[Any] = field(default_factory=list)
    
    def to_command(self) -> OscCommand:
        """Convert to OscCommand (without timestamp)."""
        return OscCommand(address=self.address, args=self.args)


# =============================================================================
# PAD BEHAVIOR CONFIGURATION
# =============================================================================

@dataclass(frozen=True)
class PadBehavior:
    """
    Configuration for how a pad behaves.
    
    pad_id: Pad identifier
    mode: Interaction mode (selector/toggle/one-shot)
    group: Optional group name (only for selectors)
    idle_color: Launchpad color index when inactive
    active_color: Launchpad color index when active
    label: Optional human-readable label
    
    For TOGGLE mode:
        osc_on: Command to send when toggling ON
        osc_off: Optional command to send when toggling OFF
    
    For SELECTOR and ONE_SHOT modes:
        osc_action: Command to send on press
    """
    pad_id: PadId
    mode: PadMode
    group: Optional[PadGroupName] = None
    idle_color: int = 0  # Off
    active_color: int = 5  # Red
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
    Runtime state of a pad (can change frequently).
    
    is_active: Whether pad is currently highlighted/active
    is_on: Current toggle state (for TOGGLE mode)
    current_color: Current LED color index
    blink_enabled: Whether this pad should blink with beat
    """
    is_active: bool = False
    is_on: bool = False
    current_color: int = 0
    blink_enabled: bool = False


# =============================================================================
# APP MODES (FSM)
# =============================================================================

class AppMode(Enum):
    """Application mode state machine."""
    NORMAL = auto()               # Normal operation
    LEARN_WAIT_PAD = auto()       # Waiting for user to press a pad
    LEARN_RECORD_OSC = auto()     # Recording OSC messages for 5 seconds
    LEARN_SELECT_MSG = auto()     # User selecting from recorded messages


@dataclass(frozen=True)
class LearnState:
    """
    State for Learn Mode FSM.
    
    selected_pad: Pad being configured (set in LEARN_WAIT_PAD)
    recorded_osc_events: OSC events captured during recording
    record_start_time: When recording started
    candidate_commands: Filtered/deduped commands for selection
    selected_command_index: User's selection from candidates
    selected_mode: User's selected pad mode
    selected_group: User's selected group (for SELECTOR)
    selected_idle_color: User's selected idle color
    selected_active_color: User's selected active color
    """
    selected_pad: Optional[PadId] = None
    recorded_osc_events: List[OscEvent] = field(default_factory=list)
    record_start_time: Optional[float] = None
    candidate_commands: List[OscCommand] = field(default_factory=list)
    selected_command_index: Optional[int] = None
    selected_mode: Optional[PadMode] = None
    selected_group: Optional[PadGroupName] = None
    selected_idle_color: int = 0
    selected_active_color: int = 5


# =============================================================================
# CONTROLLER STATE (FULL APPLICATION STATE)
# =============================================================================

@dataclass(frozen=True)
class BankConfig:
    """Configuration for a Launchpad bank (preset layout)."""
    name: str  # Human-readable bank name
    index: int  # Bank number 0-7 (for 8 banks)


# =============================================================================
# CONTROLLER STATE (FULL APPLICATION STATE)
# =============================================================================

@dataclass(frozen=True)
class ControllerState:
    """
    Complete controller state (immutable).
    
    Updated by pure functions, never mutated.
    All state transitions return a new ControllerState instance.
    
    pads: Configuration for each pad
    pad_runtime: Runtime state for each pad
    active_selector_by_group: Currently active pad ID for each selector group
    active_scene: Current active scene name
    active_preset: Current active preset name
    active_color_hue: Current meta color hue
    active_bank_index: Current bank index (0-7)
    active_bank_name: Current bank name
    available_banks: List of available banks
    beat_phase: Beat phase 0-1 from OSC
    beat_pulse: Current beat pulse state
    last_osc_messages: Recent OSC messages for diagnostics
    learn_state: Current learn mode state
    app_mode: Current application mode
    """
    pads: Dict[PadId, PadBehavior] = field(default_factory=dict)
    pad_runtime: Dict[PadId, PadRuntimeState] = field(default_factory=dict)
    active_selector_by_group: Dict[PadGroupName, Optional[PadId]] = field(default_factory=dict)
    
    # Synesthesia state
    active_scene: Optional[str] = None
    active_preset: Optional[str] = None
    active_color_hue: Optional[float] = None
    
    # Bank state
    active_bank_index: int = 0
    active_bank_name: str = "Default"
    available_banks: List[BankConfig] = field(default_factory=lambda: [
        BankConfig("Default", 0),
        BankConfig("Scenes", 1),
        BankConfig("Effects", 2),
        BankConfig("Colors", 3),
    ])
    
    # Audio/beat state
    beat_phase: float = 0.0
    beat_pulse: bool = False
    
    # Diagnostics
    last_osc_messages: List[OscEvent] = field(default_factory=list)
    
    # FSM state
    learn_state: LearnState = field(default_factory=LearnState)
    app_mode: AppMode = AppMode.NORMAL


# =============================================================================
# EFFECTS (Side effect descriptions to be executed by imperative shell)
# =============================================================================

@dataclass(frozen=True)
class Effect:
    """Base class for side effects."""
    pass


@dataclass(frozen=True)
class SendOscEffect(Effect):
    """Effect: Send an OSC command."""
    command: OscCommand


@dataclass(frozen=True)
class SetLedEffect(Effect):
    """Effect: Set a Launchpad LED."""
    pad_id: PadId
    color: int
    blink: bool = False


@dataclass(frozen=True)
class SaveConfigEffect(Effect):
    """Effect: Save configuration to disk."""
    pass


@dataclass(frozen=True)
class LogEffect(Effect):
    """Effect: Log a message."""
    message: str
    level: str = "INFO"  # INFO, WARNING, ERROR
