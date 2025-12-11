"""
Domain Models for Launchpad Standalone

This module re-exports types from launchpad_osc_lib for backward compatibility.
The standalone app now uses the library as the single source of truth.
"""
from __future__ import annotations
from dataclasses import dataclass, field
from typing import Optional, Dict

# Re-export everything from the library
from launchpad_osc_lib import (  # noqa: F401
    # Button ID
    ButtonId,
    
    # Colors and brightness
    BrightnessLevel,
    BASE_COLORS,
    BASE_COLOR_NAMES,
    get_color_at_brightness,
    get_base_color_from_velocity,
    LP_OFF, LP_RED, LP_RED_DIM, LP_ORANGE, LP_YELLOW,
    LP_GREEN, LP_GREEN_DIM, LP_CYAN, LP_BLUE, LP_BLUE_DIM,
    LP_PURPLE, LP_PINK, LP_WHITE,
    
    # Pad modes
    PadMode,
    
    # Learn mode state
    LearnPhase,
    LearnRegister,
    OscCommand,
    LearnState,
    
    # Pad configuration
    PadBehavior,
    PadRuntimeState,
    ButtonGroupType,
    
    # Effects
    LedEffect,
    SendOscEffect,
    SaveConfigEffect,
    LogEffect,
    
    # Controller state
    ControllerState,
)

# Import OscEvent
from launchpad_osc_lib.model import OscEvent  # noqa: F401

# Backward compatibility: AppState is now ControllerState
AppState = ControllerState

# Color palette for display
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

# 16-color preview palette for color selection
COLOR_PREVIEW_PALETTE = [
    LP_RED, LP_ORANGE, LP_YELLOW, LP_GREEN,
    LP_CYAN, LP_BLUE, LP_PURPLE, LP_PINK,
    1, 7, 19, 33,
    41, 49, 55, LP_WHITE,
]


# =============================================================================
# BACKWARD COMPATIBILITY: PadConfig wrapper around PadBehavior
# =============================================================================


@dataclass(frozen=True)
class PadConfig:
    """
    Configuration for a single pad (persisted).
    
    Backward compatibility wrapper - internally uses PadBehavior.
    """
    pad_id: ButtonId
    mode: PadMode
    osc_command: OscCommand
    idle_color: int = LP_GREEN_DIM
    active_color: int = LP_GREEN
    label: str = ""
    group: Optional[str] = None
    
    def to_behavior(self) -> PadBehavior:
        """Convert to PadBehavior for library compatibility."""
        group_type = None
        if self.group:
            try:
                group_type = ButtonGroupType(self.group)
            except ValueError:
                group_type = ButtonGroupType.CUSTOM
        
        if self.mode == PadMode.TOGGLE:
            return PadBehavior(
                pad_id=self.pad_id,
                mode=self.mode,
                group=group_type,
                idle_color=self.idle_color,
                active_color=self.active_color,
                label=self.label,
                osc_on=OscCommand(self.osc_command.address, [1.0]),
                osc_off=OscCommand(self.osc_command.address, [0.0]),
            )
        else:
            return PadBehavior(
                pad_id=self.pad_id,
                mode=self.mode,
                group=group_type,
                idle_color=self.idle_color,
                active_color=self.active_color,
                label=self.label,
                osc_action=self.osc_command,
            )


@dataclass
class ControllerConfig:
    """Complete controller configuration (mutable for loading/saving)."""
    pads: Dict[str, PadConfig] = field(default_factory=dict)
    
    def add_pad(self, config: PadConfig):
        """Add or update a pad configuration."""
        key = f"{config.pad_id.x},{config.pad_id.y}"
        self.pads[key] = config
    
    def get_pad(self, pad_id: ButtonId) -> Optional[PadConfig]:
        """Get configuration for a pad."""
        key = f"{pad_id.x},{pad_id.y}"
        return self.pads.get(key)
    
    def remove_pad(self, pad_id: ButtonId):
        """Remove configuration for a pad."""
        key = f"{pad_id.x},{pad_id.y}"
        if key in self.pads:
            del self.pads[key]
