"""
Launchpad OSC Library

A reusable library for Launchpad MIDI control with OSC integration.
Supports button behaviors: SELECTOR (radio), TOGGLE (on/off), ONE_SHOT (trigger), PUSH (momentary).

Architecture:
- Pure FSM functions for state transitions (fsm.py)
- Immutable state (ControllerState)
- Effect descriptions (Effect subclasses) for imperative shell
- Learn mode for dynamic pad configuration

Usage:
    from launchpad_osc_lib import (
        ControllerState, PadId, ButtonGroupType, PadMode,
        handle_pad_press, handle_osc_event, enter_learn_mode,
        SendOscEffect, SetLedEffect
    )

    # Initialize state
    state = ControllerState()
    
    # Handle events (pure functions return new state + effects)
    state, effects = handle_pad_press(state, PadId(0, 0))
    
    # Execute effects in imperative shell
    for effect in effects:
        if isinstance(effect, SendOscEffect):
            osc.send(effect.command)
        elif isinstance(effect, SetLedEffect):
            launchpad.set_led(effect.pad_id, effect.color)
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
    # Pad configuration types
    PadMode,
    ButtonGroupType,
    PadGroupName,  # Alias for ButtonGroupType
    OscCommand,
    PadBehavior,
    PadRuntimeState,
    # FSM state types
    AppMode,
    LearnState,
    ControllerState,
    # Effect types
    Effect,
    SendOscEffect,
    SetLedEffect,
    SaveConfigEffect,
    LogEffect,
)
from .fsm import (
    # Time functions (for testing)
    set_time_func,
    reset_time_func,
    get_current_time,
    # Pad interaction
    handle_pad_press,
    handle_pad_release,
    # OSC handling
    handle_osc_event,
    # Learn mode
    enter_learn_mode,
    cancel_learn_mode,
    finish_osc_recording,
    select_learn_command,
    # Utility functions
    add_pad_behavior,
    remove_pad,
    clear_all_pads,
    refresh_all_leds,
)
from .engine import PadMapper, PadMapperState  # Legacy - keep for backward compat
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
from .blink import (
    compute_blink_phase,
    should_led_be_lit,
    compute_all_led_states,
    get_dimmed_color,
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
    # Pad configuration types
    "PadMode",
    "ButtonGroupType",
    "PadGroupName",
    "OscCommand",
    "PadBehavior",
    "PadRuntimeState",
    # FSM state types
    "AppMode",
    "LearnState",
    "ControllerState",
    # Effect types
    "Effect",
    "SendOscEffect",
    "SetLedEffect",
    "SaveConfigEffect",
    "LogEffect",
    # FSM functions
    "set_time_func",
    "reset_time_func",
    "get_current_time",
    "handle_pad_press",
    "handle_pad_release",
    "handle_osc_event",
    "enter_learn_mode",
    "cancel_learn_mode",
    "finish_osc_recording",
    "select_learn_command",
    "add_pad_behavior",
    "remove_pad",
    "clear_all_pads",
    "refresh_all_leds",
    # Legacy (backward compat)
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
    # Blink / Beat sync
    "compute_blink_phase",
    "should_led_be_lit",
    "compute_all_led_states",
    "get_dimmed_color",
]

__version__ = "0.2.0"
