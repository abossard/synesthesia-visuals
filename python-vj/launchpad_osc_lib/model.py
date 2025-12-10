"""
Domain Models for Pad Mapping

Immutable data structures for pad configuration, runtime state,
application state, and FSM effects.
"""

from dataclasses import dataclass, field
from enum import Enum, auto
from typing import Optional, List, Any, Dict

from .button_id import ButtonId


# =============================================================================
# LED MODE (for lpminimk3 compatibility)
# =============================================================================

class LedMode(Enum):
    """LED modes matching lpminimk3.Led constants."""
    STATIC = auto()
    PULSE = auto()
    FLASH = auto()


# =============================================================================
# BRIGHTNESS AND COLOR UTILITIES (shared across launchpad apps)
# =============================================================================

class BrightnessLevel(Enum):
    """Brightness levels for Launchpad LEDs."""
    DIM = 0      # ~33% brightness
    NORMAL = 1   # ~66% brightness
    BRIGHT = 2   # 100% brightness


# Base colors with 3 brightness levels each: [DIM, NORMAL, BRIGHT]
# Velocity values for Launchpad Mini MK3
BASE_COLORS: Dict[str, tuple] = {
    "red":    (1, 5, 6),
    "orange": (7, 9, 10),
    "yellow": (11, 13, 14),
    "lime":   (15, 17, 18),
    "green":  (19, 21, 22),
    "cyan":   (33, 37, 38),
    "blue":   (41, 45, 46),
    "purple": (49, 53, 54),
    "pink":   (55, 57, 58),
    "white":  (1, 3, 119),
}

# Base color indices for palette display (maps index 0-9 to color name)
BASE_COLOR_NAMES = list(BASE_COLORS.keys())


def get_color_at_brightness(base_color: str, level: BrightnessLevel) -> int:
    """
    Get Launchpad velocity for a base color at a specific brightness level.
    
    Args:
        base_color: Color name ("red", "green", "blue", etc.)
        level: BrightnessLevel enum value
    
    Returns:
        Launchpad velocity value (0-127)
    
    Example:
        get_color_at_brightness("green", BrightnessLevel.DIM) -> 19
        get_color_at_brightness("green", BrightnessLevel.BRIGHT) -> 22
    """
    if base_color not in BASE_COLORS:
        return 0  # Off for unknown colors
    return BASE_COLORS[base_color][level.value]


def get_base_color_from_velocity(velocity: int) -> tuple:
    """
    Find base color name and brightness level from a velocity value.
    
    Args:
        velocity: Launchpad velocity value
    
    Returns:
        Tuple of (base_color_name, BrightnessLevel) or ("unknown", BrightnessLevel.NORMAL)
    """
    for color_name, velocities in BASE_COLORS.items():
        for level_idx, vel in enumerate(velocities):
            if vel == velocity:
                return (color_name, BrightnessLevel(level_idx))
    return ("unknown", BrightnessLevel.NORMAL)


# =============================================================================
# PAD MODES AND GROUP TYPES
# =============================================================================

class PadMode(Enum):
    """
    Pad interaction mode.
    
    SELECTOR: Radio button behavior within a group (only one active at a time)
    TOGGLE: On/Off toggle - alternates between osc_on and osc_off commands
    ONE_SHOT: Single action on press only - sends osc_action once
    PUSH: Momentary - sends 1.0 on press, 0.0 on release (like a sustain pedal)
    """
    SELECTOR = auto()  # Radio button behavior within a group (only one active)
    TOGGLE = auto()    # On/Off toggle with two OSC commands
    ONE_SHOT = auto()  # Single action on press, no persistent state
    PUSH = auto()      # Momentary: send 1.0 on press, 0.0 on release


class ButtonGroupType(str, Enum):
    """
    Predefined button group types.
    
    Groups determine radio-button behavior for SELECTOR mode pads.
    When a pad in a group is pressed, all other pads in that group are deselected.
    
    PRESETS is a subgroup of SCENES - when scene changes, presets reset to default.
    """
    SCENES = "scenes"
    PRESETS = "presets"  # Subgroup: resets when SCENES changes
    COLORS = "colors"
    CUSTOM = "custom"

    @property
    def parent_group(self) -> Optional["ButtonGroupType"]:
        """Get parent group if this is a subgroup."""
        if self == ButtonGroupType.PRESETS:
            return ButtonGroupType.SCENES
        return None
    
    @property
    def resets_on_parent_change(self) -> bool:
        """Whether this group resets when parent group changes."""
        return self.parent_group is not None


# Alias for backward compatibility
PadGroupName = ButtonGroupType


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
    pad_id: ButtonId
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
        blink_enabled: Whether this pad should blink with beat (software-based)
        led_mode: Hardware LED mode (STATIC, PULSE, FLASH) - uses Launchpad's native pulsing
    """
    is_active: bool = False
    is_on: bool = False
    current_color: int = 0
    blink_enabled: bool = False
    led_mode: LedMode = LedMode.STATIC


# =============================================================================
# APPLICATION MODES (FSM States)
# =============================================================================

class AppMode(Enum):
    """
    Application mode state machine.
    
    NORMAL: Normal operation - pads execute their configured behaviors
    LEARN_WAIT_PAD: Waiting for user to press a pad to configure
    LEARN_RECORD_OSC: Recording OSC messages until user saves/cancels
    LEARN_SELECT_MSG: User selecting from recorded messages
    """
    NORMAL = auto()
    LEARN_WAIT_PAD = auto()
    LEARN_RECORD_OSC = auto()
    LEARN_SELECT_MSG = auto()


@dataclass(frozen=True)
class LearnState:
    """
    State for Learn Mode FSM.
    
    Attributes:
        selected_pad: Pad being configured (set in LEARN_WAIT_PAD)
        recorded_osc_events: OSC events captured during recording
        candidate_commands: Filtered/deduped commands for selection
        selected_command_index: User's selection from candidates
        selected_mode: User's selected pad mode
        selected_group: User's selected group (for SELECTOR)
        selected_idle_color: User's selected idle color
        selected_active_color: User's selected active color
    """
    selected_pad: Optional[ButtonId] = None
    recorded_osc_events: List[Any] = field(default_factory=list)  # List[OscEvent]
    candidate_commands: List[OscCommand] = field(default_factory=list)
    selected_command_index: Optional[int] = None
    selected_mode: Optional[PadMode] = None
    selected_group: Optional[ButtonGroupType] = None
    selected_idle_color: int = 0
    selected_active_color: int = 5


# =============================================================================
# CONTROLLER STATE (FULL APPLICATION STATE)
# =============================================================================

@dataclass(frozen=True)
class ControllerState:
    """
    Complete controller state (immutable).
    
    Updated by pure functions, never mutated.
    All state transitions return a new ControllerState instance.
    
    Attributes:
        pads: Configuration for each pad
        pad_runtime: Runtime state for each pad
        active_selector_by_group: Currently active pad ID for each selector group
        active_scene: Current active scene name
        active_preset: Current active preset name
        active_color_hue: Current meta color hue
        beat_phase: Beat phase 0-1 from OSC
        beat_pulse: Current beat pulse state
        last_osc_messages: Recent OSC messages for diagnostics
        learn_state: Current learn mode state
        app_mode: Current application mode
    """
    pads: Dict[ButtonId, PadBehavior] = field(default_factory=dict)
    pad_runtime: Dict[ButtonId, PadRuntimeState] = field(default_factory=dict)
    active_selector_by_group: Dict[ButtonGroupType, Optional[ButtonId]] = field(default_factory=dict)
    
    # Synesthesia state
    active_scene: Optional[str] = None
    active_preset: Optional[str] = None
    active_color_hue: Optional[float] = None
    
    # Audio/beat state
    beat_phase: float = 0.0
    beat_pulse: bool = False
    
    # Diagnostics
    last_osc_messages: List[Any] = field(default_factory=list)  # List[OscEvent]
    
    # FSM state
    learn_state: LearnState = field(default_factory=LearnState)
    app_mode: AppMode = AppMode.NORMAL


# =============================================================================
# EFFECTS (Side effect descriptions for imperative shell)
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
    pad_id: ButtonId
    color: int
    blink: bool = False
    led_mode: LedMode = LedMode.STATIC


@dataclass(frozen=True)
class SaveConfigEffect(Effect):
    """Effect: Save configuration to disk."""
    pass


@dataclass(frozen=True)
class LogEffect(Effect):
    """Effect: Log a message."""
    message: str
    level: str = "INFO"  # INFO, WARNING, ERROR
