"""
OSC Categorization and Priority

Determines priority of OSC messages for smart recording:
- Priority 1: Scenes (stop recording immediately)
- Priority 2: Presets (stop recording immediately)
- Priority 3: Toggle/Push controls (stop recording immediately)
- Other: Wait for timeout
"""

from typing import Tuple, Optional
from .model import PadMode, OscEvent


# =============================================================================
# OSC ADDRESS CATEGORIES
# =============================================================================

# Priority levels (lower = higher priority, stops recording immediately)
PRIORITY_SCENE = 1
PRIORITY_PRESET = 2
PRIORITY_CONTROL = 3
PRIORITY_NOISE = 99  # Ignore completely


def categorize_osc(address: str) -> Tuple[int, PadMode, Optional[str]]:
    """
    Categorize an OSC address.
    
    Returns:
        (priority, suggested_mode, group_name)
        - priority: 1-99 (lower = higher priority)
        - suggested_mode: PadMode for this address type
        - group_name: Group for SELECTOR mode, None otherwise
    """
    # Scenes - highest priority, selector mode
    if address.startswith("/scenes/"):
        return (PRIORITY_SCENE, PadMode.SELECTOR, "scenes")
    
    # Presets - high priority, selector mode
    if address.startswith("/presets/"):
        return (PRIORITY_PRESET, PadMode.SELECTOR, "presets")
    
    # Favorite slots - similar to presets
    if address.startswith("/favslots/"):
        return (PRIORITY_PRESET, PadMode.SELECTOR, "favslots")
    
    # Playlist controls - one-shot
    if address.startswith("/playlist/"):
        return (PRIORITY_CONTROL, PadMode.ONE_SHOT, None)
    
    # Global controls - toggle
    if address.startswith("/controls/global/"):
        return (PRIORITY_CONTROL, PadMode.TOGGLE, None)
    
    # Meta controls - toggle (or selector for hue)
    if address.startswith("/controls/meta/"):
        if "hue" in address:
            return (PRIORITY_CONTROL, PadMode.SELECTOR, "colors")
        return (PRIORITY_CONTROL, PadMode.TOGGLE, None)
    
    # Audio/beat messages - noise, ignore
    if address.startswith("/audio/"):
        return (PRIORITY_NOISE, PadMode.ONE_SHOT, None)
    
    # Unknown - default to toggle
    return (50, PadMode.TOGGLE, None)


def is_controllable(address: str) -> bool:
    """Check if an OSC address can be mapped to a pad."""
    priority, _, _ = categorize_osc(address)
    return priority < PRIORITY_NOISE


def should_stop_recording(event: OscEvent) -> bool:
    """
    Check if receiving this event should stop OSC recording.
    
    High-priority events (scenes, presets, controls) stop recording
    immediately - no need to wait 5 seconds.
    """
    priority, _, _ = categorize_osc(event.address)
    return priority <= PRIORITY_CONTROL


def enrich_event(address: str, args: list, timestamp: float) -> OscEvent:
    """Create an OscEvent with priority metadata."""
    priority, _, _ = categorize_osc(address)
    return OscEvent(
        timestamp=timestamp,
        address=address,
        args=args,
        priority=priority
    )
