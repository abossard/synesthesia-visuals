"""
Launchpad OSC Library

A reusable library for Launchpad MIDI control with OSC integration.
Supports button behaviors: SELECTOR (radio), TOGGLE (on/off), ONE_SHOT (trigger).

Usage:
    from launchpad_osc_lib import LaunchpadDevice, OscClient, PadMapper, PadId, ButtonGroupType

    # Setup devices
    launchpad = LaunchpadDevice()
    osc = OscClient()
    mapper = PadMapper(launchpad, osc)
    
    # Configure pads
    mapper.add_selector(PadId(0, 0), "/scenes/Scene1", ButtonGroupType.SCENES, label="Scene 1")
    mapper.add_toggle(PadId(0, 1), "/controls/global/strobe", label="Strobe")
    mapper.add_oneshot(PadId(0, 2), "/playlist/random", label="Random")
"""

from .launchpad import (
    LaunchpadDevice,
    LaunchpadConfig,
    find_launchpad_ports,
    PadId,
    pad_to_note,
    note_to_pad,
    LP_OFF, LP_RED, LP_RED_DIM, LP_ORANGE, LP_YELLOW, LP_GREEN, LP_GREEN_DIM,
    LP_CYAN, LP_BLUE, LP_BLUE_DIM, LP_PURPLE, LP_PINK, LP_WHITE,
    COLOR_PALETTE,
)
from .osc_client import OscClient, OscConfig, OscEvent
from .model import (
    PadMode,
    ButtonGroupType,
    OscCommand,
    PadBehavior,
    PadRuntimeState,
)
from .engine import PadMapper, PadMapperState
from .emulator import (
    LaunchpadInterface,
    LaunchpadEmulator,
    SmartLaunchpad,
    LedState,
    EmulatorView,
    FullGridLayout,
    create_launchpad,
)
from .synesthesia_config import (
    SynesthesiaOscPorts,
    DEFAULT_OSC_PORTS,
    OscAddressCategory,
    CONTROLLABLE_PREFIXES,
    is_controllable,
    categorize_address,
    get_default_button_type,
    get_button_type_description,
    get_suggested_colors,
    BEAT_ADDRESS,
    BPM_ADDRESS,
    BUTTON_TYPE_MAPPINGS,
    OSC_ADDRESS_DOCUMENTATION,
)
from .banks import (
    Bank,
    BankManager,
    BankManagerState,
    create_default_banks,
)
from .synesthesia_osc import SynesthesiaOscManager

__all__ = [
    # Launchpad
    "LaunchpadDevice",
    "LaunchpadConfig",
    "find_launchpad_ports",
    "PadId",
    "pad_to_note",
    "note_to_pad",
    "LP_OFF", "LP_RED", "LP_RED_DIM", "LP_ORANGE", "LP_YELLOW", "LP_GREEN", "LP_GREEN_DIM",
    "LP_CYAN", "LP_BLUE", "LP_BLUE_DIM", "LP_PURPLE", "LP_PINK", "LP_WHITE",
    "COLOR_PALETTE",
    # Emulator / Smart Launchpad
    "LaunchpadInterface",
    "LaunchpadEmulator",
    "SmartLaunchpad",
    "LedState",
    "EmulatorView",
    "FullGridLayout",
    "create_launchpad",
    # OSC
    "OscClient",
    "OscConfig",
    "OscEvent",
    "SynesthesiaOscManager",
    # Mapping
    "PadMode",
    "ButtonGroupType",
    "OscCommand",
    "PadBehavior",
    "PadRuntimeState",
    "PadMapper",
    "PadMapperState",
    # Synesthesia config
    "SynesthesiaOscPorts",
    "DEFAULT_OSC_PORTS",
    "OscAddressCategory",
    "CONTROLLABLE_PREFIXES",
    "is_controllable",
    "categorize_address",
    "get_default_button_type",
    "get_button_type_description",
    "get_suggested_colors",
    "BEAT_ADDRESS",
    "BPM_ADDRESS",
    "BUTTON_TYPE_MAPPINGS",
    "OSC_ADDRESS_DOCUMENTATION",
    # Banks
    "Bank",
    "BankManager",
    "BankManagerState",
    "create_default_banks",
]

__version__ = "0.1.0"
