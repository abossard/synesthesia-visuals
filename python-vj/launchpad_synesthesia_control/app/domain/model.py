"""
Domain Models - App-Specific Types

App-specific models for learn mode, FSM, and effects.
Shared types (PadId, PadMode, etc.) are imported from launchpad_osc_lib.
"""

from dataclasses import dataclass, field
from typing import Optional, List, Dict
from enum import Enum, auto

# =============================================================================
# RE-EXPORT LIBRARY TYPES FOR CONVENIENCE
# =============================================================================

from launchpad_osc_lib import (
    # Core types
    PadId,
    PadMode,
    OscCommand,
    PadBehavior,
    PadRuntimeState,
    # Group types - alias for backward compatibility
    ButtonGroupType,
    # OSC
    OscEvent,
    # Colors
    LP_OFF,
    LP_RED,
    LP_RED_DIM,
    LP_ORANGE,
    LP_YELLOW,
    LP_GREEN,
    LP_GREEN_DIM,
    LP_CYAN,
    LP_BLUE,
    LP_BLUE_DIM,
    LP_PURPLE,
    LP_PINK,
    LP_WHITE,
    COLOR_PALETTE,
)

# Alias for backward compatibility with existing code
PadGroupName = ButtonGroupType


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
