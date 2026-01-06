"""
Beat-Synced Blinking Logic - Pure Functions

Computes LED blink states synchronized with Synesthesia's audio beat.
"""

from typing import Dict, Tuple
from .model import ControllerState, PadRuntimeState
from .button_id import ButtonId


def compute_blink_phase(beat_pulse: bool, beat_phase: float) -> float:
    """
    Compute blink phase from beat state (pure function).
    
    Args:
        beat_pulse: True on beat, False off beat
        beat_phase: Beat phase 0.0-1.0 (optional, for smooth transitions)
    
    Returns:
        Blink intensity 0.0-1.0 (1.0 = fully visible, 0.0 = off)
    """
    # Use pulse-based blinking for sharp beat sync
    # When beat_pulse is True, show full intensity
    # When False, dim significantly
    if beat_pulse:
        return 1.0
    else:
        return 0.3  # Dim but visible when off-beat


def should_led_be_lit(
    runtime: PadRuntimeState,
    blink_phase: float
) -> bool:
    """
    Determine if LED should be lit based on runtime state and blink phase.
    
    Args:
        runtime: Pad runtime state
        blink_phase: Current blink phase 0.0-1.0
    
    Returns:
        True if LED should be lit (at active_color), False if dimmed
    """
    if not runtime.blink_enabled:
        # No blinking - always show current color
        return True
    
    # Blink enabled - modulate based on phase
    # Show LED at full brightness when phase > 0.5
    return blink_phase > 0.5


def compute_all_led_states(
    state: ControllerState,
    blink_phase: float
) -> Dict[ButtonId, Tuple[int, bool]]:
    """
    Compute desired LED state for all pads (pure function).
    
    Args:
        state: Current controller state
        blink_phase: Current blink phase 0.0-1.0
    
    Returns:
        Dict mapping ButtonId to (color, is_lit)
        is_lit: True = show color, False = show dimmed/off
    """
    led_states: Dict[ButtonId, Tuple[int, bool]] = {}
    
    for pad_id, behavior in state.pads.items():
        runtime = state.pad_runtime.get(pad_id, PadRuntimeState())
        
        # Determine if LED should be lit
        is_lit = should_led_be_lit(runtime, blink_phase)
        
        # Use current color (already set by FSM)
        color = runtime.current_color
        
        led_states[pad_id] = (color, is_lit)
    
    return led_states


def get_dimmed_color(color: int) -> int:
    """
    Get dimmed version of a color for blink-off state.
    
    For Launchpad Mini Mk3, colors 0-127 where:
    - 0 = off
    - Lower values = dimmer
    - Higher values = brighter
    
    This is a simple dimming strategy - could be enhanced with
    color palette mapping.
    
    Args:
        color: Original color index
    
    Returns:
        Dimmed color index
    """
    if color == 0:
        return 0  # Already off
    
    # Reduce brightness by ~70%
    # For most colors, this means using color // 3
    dimmed = max(1, color // 3)
    return min(dimmed, 127)
