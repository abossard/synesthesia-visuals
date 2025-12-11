"""
Launchpad OSC Library

Modern library for Launchpad Mini MK3 control with OSC integration using lpminimk3.

Features:
- Button behaviors: SELECTOR (radio), TOGGLE (on/off), ONE_SHOT (trigger), PUSH (momentary)
- Pure FSM functions for state transitions
- Immutable state management
- Learn mode for dynamic configuration

Usage:
    import lpminimk3
    from launchpad_osc_lib import (
        ControllerState, ButtonId, ButtonGroupType, PadMode,
        handle_pad_press, handle_osc_event, enter_learn_mode,
        SendOscEffect, SetLedEffect
    )
    
    # Connect to Launchpad
    lp = lpminimk3.find_launchpads()[0]
    lp.open()
    lp.mode = lpminimk3.Mode.PROG
    
    # Initialize state
    state = ControllerState()
    
    # Handle events (pure functions return new state + effects)
    state, effects = handle_pad_press(state, ButtonId(0, 0))
    
    # Execute effects
    for effect in effects:
        if isinstance(effect, SendOscEffect):
            osc.send(effect.command)
        elif isinstance(effect, SetLedEffect):
            button = lp.grid.led(effect.pad_id.x, effect.pad_id.y)
            button.color = effect.color
"""

# Re-export lpminimk3 for convenience
from lpminimk3 import (
    LaunchpadMiniMk3,
    find_launchpads,
    Mode,
    ButtonEvent,
)
from lpminimk3.components import Led, Button
from lpminimk3.colors import ColorPalette

from .button_id import ButtonId
from .model import LedMode, COLOR_PALETTE
from .osc_client import OscClient, OscConfig, OscEvent
from .model import (
    # Brightness and colors
    BrightnessLevel,
    BASE_COLORS,
    BASE_COLOR_NAMES,
    get_color_at_brightness,
    get_base_color_from_velocity,
    LP_OFF, LP_RED, LP_RED_DIM, LP_ORANGE, LP_YELLOW,
    LP_GREEN, LP_GREEN_DIM, LP_CYAN, LP_BLUE, LP_BLUE_DIM,
    LP_PURPLE, LP_PINK, LP_WHITE,
    # Pad configuration types
    PadMode,
    ButtonGroupType,
    PadGroupName,  # Alias for ButtonGroupType
    OscCommand,
    PadBehavior,
    PadRuntimeState,
    # FSM state types - unified
    LearnPhase,
    LearnRegister,
    AppMode,  # Alias for LearnPhase
    LearnState,
    OscEvent as OscEventModel,  # Renamed to avoid conflict with osc_client.OscEvent
    ControllerState,
    AppState,  # Alias for ControllerState
    # Effect types
    Effect,
    SendOscEffect,
    LedEffect,
    SetLedEffect,  # Alias for LedEffect
    SaveConfigEffect,
    LogEffect,
)
from .fsm import (
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
# Emulator has been moved to launchpad_synesthesia_control/app/io/emulator.py
from .synesthesia_config import (
    SynesthesiaOscPorts,
    DEFAULT_OSC_PORTS,
    OscAddressCategory,
    CONTROLLABLE_PREFIXES,
    PRIORITY_SCENE,
    PRIORITY_PRESET,
    PRIORITY_CONTROL,
    PRIORITY_NOISE,
    is_controllable,
    is_noisy_audio,
    categorize_address,
    categorize_osc,
    should_stop_recording,
    enrich_event,
    get_default_button_type,
    get_button_type_description,
    get_suggested_colors,
    BEAT_ADDRESS,
    BPM_ADDRESS,
    NOISY_AUDIO_PREFIXES,
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
from .display import (
    render_state,
    render_idle,
    render_learn_wait_pad,
    render_learn_record_osc,
    render_learn_config,
    LEARN_BUTTON,
    SAVE_PAD,
    TEST_PAD,
    CANCEL_PAD,
)
from .controller import (
    LaunchpadController,
    LaunchpadInterface,
    OscInterface,
)
from .synesthesia_osc import SynesthesiaOscManager
from .launchpad_device import LaunchpadDevice
from .osc_sync import SyncOscClient
from .config import save_config, load_config, DEFAULT_CONFIG_PATH
from .cli import LaunchpadApp, main as cli_main

__all__ = [
    # Launchpad (lpminimk3)
    "LaunchpadMiniMk3",
    "find_launchpads",
    "Mode",
    "ButtonEvent",
    "Led",
    "Button",
    "ColorPalette",
    "COLOR_PALETTE",
    "ButtonId",
    "LedMode",
    # Brightness and colors
    "BrightnessLevel",
    "BASE_COLORS",
    "BASE_COLOR_NAMES",
    "get_color_at_brightness",
    "get_base_color_from_velocity",
    "LP_OFF", "LP_RED", "LP_RED_DIM", "LP_ORANGE", "LP_YELLOW",
    "LP_GREEN", "LP_GREEN_DIM", "LP_CYAN", "LP_BLUE", "LP_BLUE_DIM",
    "LP_PURPLE", "LP_PINK", "LP_WHITE",
    # OSC
    "OscClient",
    "OscConfig",
    "OscEvent",
    "OscEventModel",
    "SynesthesiaOscManager",
    # Pad configuration types
    "PadMode",
    "ButtonGroupType",
    "PadGroupName",
    "OscCommand",
    "PadBehavior",
    "PadRuntimeState",
    # FSM state types
    "LearnPhase",
    "LearnRegister",
    "AppMode",
    "LearnState",
    "ControllerState",
    "AppState",
    # Effect types
    "Effect",
    "SendOscEffect",
    "LedEffect",
    "SetLedEffect",
    "SaveConfigEffect",
    "LogEffect",
    # FSM functions
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

    # Synesthesia config
    "SynesthesiaOscPorts",
    "DEFAULT_OSC_PORTS",
    "OscAddressCategory",
    "CONTROLLABLE_PREFIXES",
    "is_controllable",
    "is_noisy_audio",
    "NOISY_AUDIO_PREFIXES",
    "categorize_address",
    "categorize_osc",
    "get_default_button_type",
    "get_button_type_description",
    "get_suggested_colors",
    "enrich_event",
    "BEAT_ADDRESS",
    "BPM_ADDRESS",
    "BUTTON_TYPE_MAPPINGS",
    "OSC_ADDRESS_DOCUMENTATION",
    # Banks
    "Bank",
    "BankManager",
    "BankManagerState",
    "create_default_banks",
    # Display / LED rendering
    "render_state",
    "render_idle",
    "render_learn_wait_pad",
    "render_learn_record_osc",
    "render_learn_config",
    "LEARN_BUTTON",
    "SAVE_PAD",
    "TEST_PAD",
    "CANCEL_PAD",
    # Controller
    "LaunchpadController",
    "LaunchpadInterface",
    "OscInterface",
    # Device and OSC
    "LaunchpadDevice",
    "SyncOscClient",
    # Config persistence
    "save_config",
    "load_config",
    "DEFAULT_CONFIG_PATH",
    # CLI
    "LaunchpadApp",
    "cli_main",
    # Blink / Beat sync
    "compute_blink_phase",
    "should_led_be_lit",
    "compute_all_led_states",
    "get_dimmed_color",
]

__version__ = "1.0.0"  # Major version - lpminimk3 integration
