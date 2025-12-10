"""
Synesthesia OSC Configuration

Single source of truth for all Synesthesia-specific constants:
- OSC address patterns
- Button type mappings (which OSC paths map to which button behavior)
- Default ports
- Controllable vs informational message categorization

This is the ONLY place where Synesthesia-specific knowledge should live.
"""

from enum import Enum, auto
from dataclasses import dataclass
from typing import Dict, List, Optional

from .model import PadMode, ButtonGroupType


# =============================================================================
# OSC PORT CONFIGURATION
# =============================================================================

@dataclass(frozen=True)
class SynesthesiaOscPorts:
    """Default OSC ports for Synesthesia communication."""
    send_port: int = 7777     # Synesthesia listens here
    receive_port: int = 9999  # Synesthesia sends here
    host: str = "127.0.0.1"


DEFAULT_OSC_PORTS = SynesthesiaOscPorts()


# =============================================================================
# OSC ADDRESS CATEGORIES
# =============================================================================

class OscAddressCategory(Enum):
    """Categories of Synesthesia OSC addresses."""
    # Controllable - can be mapped to pads
    SCENE = auto()           # /scenes/* - Scene selection
    PRESET = auto()          # /presets/* - Preset selection
    FAVSLOT = auto()         # /favslots/* - Favorite slots
    PLAYLIST = auto()        # /playlist/* - Playlist control (next/prev/play)
    META_CONTROL = auto()    # /controls/meta/* - Hue, saturation, brightness, etc.
    GLOBAL_CONTROL = auto()  # /controls/global/* - Mirror, kaleidoscope, blur, etc.
    
    # Informational - not controllable
    BEAT = auto()            # /audio/beat/* - Beat pulses
    BPM = auto()             # /audio/bpm - Current BPM
    AUDIO_LEVEL = auto()     # /audio/level* - Audio levels
    FFT = auto()             # /audio/fft/* - FFT data
    TIMECODE = auto()        # /audio/timecode - Playback position
    
    UNKNOWN = auto()         # Not recognized


# =============================================================================
# CONTROLLABLE ADDRESS PREFIXES
# =============================================================================

# These prefixes identify OSC addresses that can be mapped to Launchpad pads
CONTROLLABLE_PREFIXES: List[str] = [
    "/scenes/",
    "/presets/",
    "/favslots/",
    "/playlist/",
    "/controls/meta/",
    "/controls/global/",
]


def is_controllable(address: str) -> bool:
    """
    Check if an OSC address is controllable (can be mapped to a pad).
    
    Args:
        address: OSC address path
        
    Returns:
        True if the address can be mapped to a Launchpad pad
    """
    return any(address.startswith(prefix) for prefix in CONTROLLABLE_PREFIXES)


# =============================================================================
# ADDRESS TO CATEGORY MAPPING
# =============================================================================

def categorize_address(address: str) -> OscAddressCategory:
    """
    Categorize an OSC address.
    
    Args:
        address: OSC address path
        
    Returns:
        OscAddressCategory enum value
    """
    if address.startswith("/scenes/"):
        return OscAddressCategory.SCENE
    elif address.startswith("/presets/"):
        return OscAddressCategory.PRESET
    elif address.startswith("/favslots/"):
        return OscAddressCategory.FAVSLOT
    elif address.startswith("/playlist/"):
        return OscAddressCategory.PLAYLIST
    elif address.startswith("/controls/meta/"):
        return OscAddressCategory.META_CONTROL
    elif address.startswith("/controls/global/"):
        return OscAddressCategory.GLOBAL_CONTROL
    elif address.startswith("/audio/beat/"):
        return OscAddressCategory.BEAT
    elif address == "/audio/bpm":
        return OscAddressCategory.BPM
    elif address.startswith("/audio/level"):
        return OscAddressCategory.AUDIO_LEVEL
    elif address.startswith("/audio/fft/"):
        return OscAddressCategory.FFT
    elif address == "/audio/timecode":
        return OscAddressCategory.TIMECODE
    else:
        return OscAddressCategory.UNKNOWN


# =============================================================================
# BUTTON TYPE MAPPING
# =============================================================================

# Maps OSC address patterns to their default button behavior
# Key: (prefix, optional pattern) -> (PadMode, Optional[ButtonGroupType])

@dataclass(frozen=True)
class ButtonTypeMapping:
    """Mapping from OSC address pattern to button behavior."""
    pattern: str
    mode: PadMode
    group: Optional[ButtonGroupType] = None
    description: str = ""


# Default button type mappings for Synesthesia OSC addresses
# More specific patterns should come before more general ones
BUTTON_TYPE_MAPPINGS: List[ButtonTypeMapping] = [
    # Scenes - radio buttons (only one scene active at a time)
    ButtonTypeMapping(
        pattern="/scenes/",
        mode=PadMode.SELECTOR,
        group=ButtonGroupType.SCENES,
        description="Scene selection - only one active at a time"
    ),
    
    # Presets - radio buttons within scenes
    ButtonTypeMapping(
        pattern="/presets/",
        mode=PadMode.SELECTOR,
        group=ButtonGroupType.PRESETS,
        description="Preset selection - only one active at a time"
    ),
    
    # Favorite slots - radio buttons
    ButtonTypeMapping(
        pattern="/favslots/",
        mode=PadMode.SELECTOR,
        group=ButtonGroupType.PRESETS,  # Shares group with presets
        description="Favorite slot selection"
    ),
    
    # Playlist random - one-shot (trigger once)
    ButtonTypeMapping(
        pattern="/playlist/random",
        mode=PadMode.ONE_SHOT,
        description="Random scene - fires once on press"
    ),
    
    # Playlist next/prev/play - one-shot
    ButtonTypeMapping(
        pattern="/playlist/next",
        mode=PadMode.ONE_SHOT,
        description="Next in playlist - fires once"
    ),
    ButtonTypeMapping(
        pattern="/playlist/previous",
        mode=PadMode.ONE_SHOT,
        description="Previous in playlist - fires once"
    ),
    ButtonTypeMapping(
        pattern="/playlist/play",
        mode=PadMode.ONE_SHOT,
        description="Play/pause playlist - fires once"
    ),
    ButtonTypeMapping(
        pattern="/playlist/",
        mode=PadMode.ONE_SHOT,
        description="Other playlist controls - fires once"
    ),
    
    # Global controls with toggle behavior
    ButtonTypeMapping(
        pattern="/controls/global/strobe",
        mode=PadMode.TOGGLE,
        description="Strobe effect on/off"
    ),
    ButtonTypeMapping(
        pattern="/controls/global/mirror",
        mode=PadMode.TOGGLE,
        description="Mirror effect on/off"
    ),
    ButtonTypeMapping(
        pattern="/controls/global/kaleidoscope",
        mode=PadMode.TOGGLE,
        description="Kaleidoscope effect on/off"
    ),
    ButtonTypeMapping(
        pattern="/controls/global/invert",
        mode=PadMode.TOGGLE,
        description="Color inversion on/off"
    ),
    ButtonTypeMapping(
        pattern="/controls/global/blur",
        mode=PadMode.TOGGLE,
        description="Blur effect on/off"
    ),
    ButtonTypeMapping(
        pattern="/controls/global/",
        mode=PadMode.TOGGLE,
        description="Other global controls - toggle"
    ),
    
    # Meta controls - typically toggles or one-shots depending on use
    # Hue is special - could be selector for color palette
    ButtonTypeMapping(
        pattern="/controls/meta/hue",
        mode=PadMode.SELECTOR,
        group=ButtonGroupType.COLORS,
        description="Hue selection (color palette)"
    ),
    ButtonTypeMapping(
        pattern="/controls/meta/",
        mode=PadMode.TOGGLE,
        description="Other meta controls - toggle"
    ),
]


def get_default_button_type(address: str) -> tuple[PadMode, Optional[ButtonGroupType]]:
    """
    Get the default button type for an OSC address.
    
    Matches against BUTTON_TYPE_MAPPINGS in order (first match wins).
    
    Args:
        address: OSC address path
        
    Returns:
        (PadMode, Optional[ButtonGroupType]) tuple
    """
    for mapping in BUTTON_TYPE_MAPPINGS:
        if address.startswith(mapping.pattern):
            return (mapping.mode, mapping.group)
    
    # Default fallback
    return (PadMode.ONE_SHOT, None)


def get_button_type_description(address: str) -> str:
    """
    Get description of the button type for an OSC address.
    
    Args:
        address: OSC address path
        
    Returns:
        Human-readable description
    """
    for mapping in BUTTON_TYPE_MAPPINGS:
        if address.startswith(mapping.pattern):
            return mapping.description
    
    return "Unknown button type"


# =============================================================================
# INFORMATIONAL OSC ADDRESSES (for state sync)
# =============================================================================

# Beat address for LED blinking sync
BEAT_ADDRESS = "/audio/beat/onbeat"

# BPM address for tempo info
BPM_ADDRESS = "/audio/bpm"

# Audio level addresses
AUDIO_LEVEL_ADDRESSES = [
    "/audio/level",
    "/audio/level/bass",
    "/audio/level/mid",
    "/audio/level/high",
]

# Noisy audio prefixes - high-frequency messages that spam the OSC stream
# These are sent continuously and should be filtered from UI displays
NOISY_AUDIO_PREFIXES: List[str] = [
    "/audio/level",      # Audio levels (sent every frame)
    "/audio/fft/",       # FFT data (sent every frame)
    "/audio/timecode",   # Timecode (sent continuously)
]


def is_noisy_audio(address: str) -> bool:
    """
    Check if an OSC address is a noisy audio message.
    
    Noisy audio messages are sent at high frequency (every frame) and 
    spam the OSC stream. They should be filtered from UI displays but
    may still be processed for beat sync, etc.
    
    NOT noisy (keep):
    - /audio/beat/onbeat - beat pulses (sparse, useful for LED blink)
    - /audio/bpm - BPM updates (sparse)
    
    Noisy (filter):
    - /audio/level* - audio levels (every frame)
    - /audio/fft/* - FFT data (every frame)
    - /audio/timecode - playback position (every frame)
    
    Args:
        address: OSC address path
        
    Returns:
        True if the address is a noisy audio message
    """
    return any(address.startswith(prefix) for prefix in NOISY_AUDIO_PREFIXES)


# =============================================================================
# STATE SYNC - OSC addresses that update internal state
# =============================================================================

def extract_scene_name(address: str) -> Optional[str]:
    """Extract scene name from /scenes/* address."""
    if address.startswith("/scenes/"):
        return address.split("/")[-1]
    return None


def extract_preset_name(address: str) -> Optional[str]:
    """Extract preset name from /presets/* or /favslots/* address."""
    if address.startswith("/presets/") or address.startswith("/favslots/"):
        return address.split("/")[-1]
    return None


# =============================================================================
# COLOR SUGGESTIONS BY ADDRESS TYPE
# =============================================================================

# Suggested colors for different address categories (Launchpad color indices)
DEFAULT_COLORS_BY_CATEGORY: Dict[OscAddressCategory, tuple[int, int]] = {
    # (idle_color, active_color)
    OscAddressCategory.SCENE: (21, 5),      # Green dim -> Red
    OscAddressCategory.PRESET: (45, 21),    # Blue -> Green
    OscAddressCategory.FAVSLOT: (37, 21),   # Cyan -> Green
    OscAddressCategory.PLAYLIST: (9, 13),   # Orange -> Yellow
    OscAddressCategory.META_CONTROL: (53, 57),  # Purple -> Pink
    OscAddressCategory.GLOBAL_CONTROL: (13, 5),  # Yellow -> Red
}


def get_suggested_colors(address: str) -> tuple[int, int]:
    """
    Get suggested idle and active colors for an OSC address.
    
    Args:
        address: OSC address path
        
    Returns:
        (idle_color, active_color) tuple of Launchpad color indices
    """
    category = categorize_address(address)
    return DEFAULT_COLORS_BY_CATEGORY.get(category, (0, 5))  # Default: off -> red


# =============================================================================
# DOCUMENTATION / REFERENCE
# =============================================================================

OSC_ADDRESS_DOCUMENTATION = """
# Synesthesia OSC Address Reference

## Controllable Addresses (map to Launchpad pads)

### Scenes - `/scenes/[SceneName]`
- **Button Type**: SELECTOR (radio button)
- **Group**: scenes
- **Behavior**: Only one scene active at a time
- **Example**: `/scenes/AlienCavern`, `/scenes/NeonCity`

### Presets - `/presets/[PresetName]`
- **Button Type**: SELECTOR (radio button)
- **Group**: presets
- **Behavior**: Only one preset active at a time
- **Example**: `/presets/Preset1`, `/presets/FastStrobe`

### Favorite Slots - `/favslots/[SlotNumber]`
- **Button Type**: SELECTOR (radio button)
- **Group**: presets (shares group with presets)
- **Behavior**: Trigger saved favorites
- **Example**: `/favslots/1`, `/favslots/2`

### Playlist Control - `/playlist/[Action]`
- **Button Type**: ONE_SHOT
- **Behavior**: Fires once on press
- **Actions**: `next`, `previous`, `play`, `random`

### Meta Controls - `/controls/meta/[Parameter]`
- **Button Type**: TOGGLE (on/off) or SELECTOR (for hue)
- **Parameters**: `hue`, `saturation`, `brightness`, `contrast`, `speed`, `strobe`
- **Value Range**: 0.0-1.0 (or 0.0-2.0 for speed)

### Global Controls - `/controls/global/[Parameter]`
- **Button Type**: TOGGLE (on/off)
- **Parameters**: `mirror`, `kaleidoscope`, `blur`, `invert`
- **Behavior**: Toggle effects on/off

## Informational Addresses (state sync, not controllable)

### Beat - `/audio/beat/onbeat`
- **Use**: LED blink sync
- **Value**: 1 on beat, 0 off

### BPM - `/audio/bpm`
- **Use**: Display tempo
- **Value**: Float (e.g., 128.5)

### Audio Levels - `/audio/level*`
- **Use**: VU meters, audio visualization
- **Value**: 0.0-1.0
"""
