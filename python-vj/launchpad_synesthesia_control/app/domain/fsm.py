"""
Finite State Machine Logic - Pure Functions

All functions are pure: same input = same output, no side effects.
Returns new state and list of effects to be executed by imperative shell.
"""

from typing import List, Tuple, Optional
from dataclasses import replace
import time

from .model import (
    ControllerState, PadId, PadBehavior, PadRuntimeState,
    PadMode, PadGroupName, AppMode, LearnState,
    OscEvent, OscCommand,
    Effect, SendOscEffect, SetLedEffect, SaveConfigEffect, LogEffect
)


# =============================================================================
# PAD INTERACTION FSM
# =============================================================================

def handle_pad_press(
    state: ControllerState,
    pad_id: PadId
) -> Tuple[ControllerState, List[Effect]]:
    """
    Handle a pad press event (pure function).
    
    Behavior depends on current app mode:
    - NORMAL: Execute pad behavior
    - LEARN_WAIT_PAD: Select this pad for learning
    - Other learn modes: Ignored
    
    Returns:
        (new_state, effects_to_execute)
    """
    if state.app_mode == AppMode.LEARN_WAIT_PAD:
        # Select this pad for learning
        new_learn_state = replace(state.learn_state, selected_pad=pad_id)
        new_state = replace(
            state,
            learn_state=new_learn_state,
            app_mode=AppMode.LEARN_RECORD_OSC
        )
        # Start recording timer will be set by imperative shell
        new_learn_state = replace(new_learn_state, record_start_time=time.time())
        new_state = replace(state, learn_state=new_learn_state, app_mode=AppMode.LEARN_RECORD_OSC)
        
        effects = [
            LogEffect(f"Learning mode: Selected pad {pad_id}, recording OSC for 5 seconds..."),
            SetLedEffect(pad_id, color=45, blink=True)  # Blue blinking during record
        ]
        return new_state, effects
    
    elif state.app_mode != AppMode.NORMAL:
        # Ignore pad presses in other learn modes
        return state, []
    
    # Normal mode: execute pad behavior
    if pad_id not in state.pads:
        # Unmapped pad
        return state, [LogEffect(f"Pad {pad_id} not mapped", level="WARNING")]
    
    behavior = state.pads[pad_id]
    
    if behavior.mode == PadMode.SELECTOR:
        return _handle_selector_press(state, pad_id, behavior)
    elif behavior.mode == PadMode.TOGGLE:
        return _handle_toggle_press(state, pad_id, behavior)
    elif behavior.mode == PadMode.ONE_SHOT:
        return _handle_one_shot_press(state, pad_id, behavior)
    else:
        return state, [LogEffect(f"Unknown pad mode: {behavior.mode}", level="ERROR")]


def _handle_selector_press(
    state: ControllerState,
    pad_id: PadId,
    behavior: PadBehavior
) -> Tuple[ControllerState, List[Effect]]:
    """Handle SELECTOR pad press."""
    effects: List[Effect] = []
    
    # Get current active pad in this group
    group = behavior.group
    previous_active = state.active_selector_by_group.get(group)
    
    # Deactivate previous pad in group
    new_pad_runtime = dict(state.pad_runtime)
    if previous_active and previous_active in state.pads:
        prev_behavior = state.pads[previous_active]
        new_pad_runtime[previous_active] = PadRuntimeState(
            is_active=False,
            current_color=prev_behavior.idle_color,
            blink_enabled=False
        )
        effects.append(SetLedEffect(previous_active, prev_behavior.idle_color, blink=False))
    
    # Activate this pad
    new_pad_runtime[pad_id] = PadRuntimeState(
        is_active=True,
        current_color=behavior.active_color,
        blink_enabled=True  # Active selectors blink with beat
    )
    effects.append(SetLedEffect(pad_id, behavior.active_color, blink=True))
    
    # Update active selector tracking
    new_active_selectors = dict(state.active_selector_by_group)
    new_active_selectors[group] = pad_id
    
    # Send OSC command
    if behavior.osc_action:
        effects.append(SendOscEffect(behavior.osc_action))
    
    # Create new state
    new_state = replace(
        state,
        pad_runtime=new_pad_runtime,
        active_selector_by_group=new_active_selectors
    )
    
    effects.append(LogEffect(f"Selector {group.value}: {behavior.label or pad_id}"))
    
    return new_state, effects


def _handle_toggle_press(
    state: ControllerState,
    pad_id: PadId,
    behavior: PadBehavior
) -> Tuple[ControllerState, List[Effect]]:
    """Handle TOGGLE pad press."""
    effects: List[Effect] = []
    
    # Get current toggle state
    current_runtime = state.pad_runtime.get(pad_id, PadRuntimeState())
    new_is_on = not current_runtime.is_on
    
    # Choose OSC command
    osc_cmd = behavior.osc_on if new_is_on else behavior.osc_off
    
    # Update runtime state
    new_color = behavior.active_color if new_is_on else behavior.idle_color
    new_pad_runtime = dict(state.pad_runtime)
    new_pad_runtime[pad_id] = PadRuntimeState(
        is_active=new_is_on,
        is_on=new_is_on,
        current_color=new_color,
        blink_enabled=False  # Toggles don't blink
    )
    
    # Set LED
    effects.append(SetLedEffect(pad_id, new_color, blink=False))
    
    # Send OSC if command defined
    if osc_cmd:
        effects.append(SendOscEffect(osc_cmd))
    
    new_state = replace(state, pad_runtime=new_pad_runtime)
    
    state_str = "ON" if new_is_on else "OFF"
    effects.append(LogEffect(f"Toggle {behavior.label or pad_id}: {state_str}"))
    
    return new_state, effects


def _handle_one_shot_press(
    state: ControllerState,
    pad_id: PadId,
    behavior: PadBehavior
) -> Tuple[ControllerState, List[Effect]]:
    """Handle ONE_SHOT pad press."""
    effects: List[Effect] = []
    
    # Flash the pad briefly
    new_pad_runtime = dict(state.pad_runtime)
    new_pad_runtime[pad_id] = PadRuntimeState(
        is_active=False,
        current_color=behavior.active_color,
        blink_enabled=False
    )
    
    effects.append(SetLedEffect(pad_id, behavior.active_color, blink=False))
    
    # Send OSC command
    if behavior.osc_action:
        effects.append(SendOscEffect(behavior.osc_action))
    
    new_state = replace(state, pad_runtime=new_pad_runtime)
    
    effects.append(LogEffect(f"One-shot: {behavior.label or pad_id}"))
    
    return new_state, effects


# =============================================================================
# OSC EVENT HANDLING
# =============================================================================

def handle_osc_event(
    state: ControllerState,
    event: OscEvent
) -> Tuple[ControllerState, List[Effect]]:
    """
    Handle incoming OSC event (pure function).
    
    Updates state based on OSC address:
    - /audio/beat/onbeat: Update beat pulse
    - /scenes/*: Update active scene and selector
    - /presets/*: Update active preset and selector
    - /controls/meta/hue: Update color selector
    
    If in LEARN_RECORD_OSC mode, also records the event.
    **NEW: Timer starts on FIRST CONTROLLABLE OSC message received**
    
    Returns:
        (new_state, effects_to_execute)
    """
    effects: List[Effect] = []
    
    # Record OSC events during learn mode
    if state.app_mode == AppMode.LEARN_RECORD_OSC:
        # Only record controllable messages
        if OscCommand.is_controllable(event.address):
            new_recorded = list(state.learn_state.recorded_osc_events) + [event]
            new_learn_state = replace(state.learn_state, recorded_osc_events=new_recorded)
            
            # Start timer on FIRST CONTROLLABLE message
            if state.learn_state.record_start_time is None:
                new_learn_state = replace(new_learn_state, record_start_time=event.timestamp)
                effects.append(LogEffect(f"Learn mode: First controllable message received ({event.address}), starting 5s timer"))
            
            state = replace(state, learn_state=new_learn_state)
    
    # Update diagnostics
    new_last_messages = list(state.last_osc_messages[-49:]) + [event]  # Keep last 50
    state = replace(state, last_osc_messages=new_last_messages)
    
    # Handle specific OSC addresses
    if event.address == "/audio/beat/onbeat":
        new_pulse = bool(event.args[0]) if event.args else False
        state = replace(state, beat_pulse=new_pulse)
    
    elif event.address.startswith("/scenes/"):
        scene_name = event.address.split("/")[-1]
        state = replace(state, active_scene=scene_name)
        # Find and activate matching selector pad
        state, led_effects = _activate_matching_selector(state, event.to_command(), PadGroupName.SCENES)
        effects.extend(led_effects)
    
    elif event.address.startswith("/presets/") or event.address.startswith("/favslots/"):
        preset_name = event.address.split("/")[-1]
        state = replace(state, active_preset=preset_name)
        state, led_effects = _activate_matching_selector(state, event.to_command(), PadGroupName.PRESETS)
        effects.extend(led_effects)
    
    elif event.address == "/controls/meta/hue":
        if event.args:
            hue = float(event.args[0])
            state = replace(state, active_color_hue=hue)
            # Find and activate matching color pad
            state, led_effects = _activate_matching_selector(state, event.to_command(), PadGroupName.COLORS)
            effects.extend(led_effects)
    
    return state, effects


def _activate_matching_selector(
    state: ControllerState,
    command: OscCommand,
    group: PadGroupName
) -> Tuple[ControllerState, List[Effect]]:
    """
    Find and activate a selector pad matching the given OSC command.
    
    Returns:
        (new_state, led_effects)
    """
    effects: List[Effect] = []
    
    # Find matching pad
    matching_pad = None
    for pad_id, behavior in state.pads.items():
        if (behavior.mode == PadMode.SELECTOR and 
            behavior.group == group and
            behavior.osc_action and
            behavior.osc_action.address == command.address):
            matching_pad = pad_id
            break
    
    if not matching_pad:
        return state, effects
    
    # Deactivate previous active in group
    new_pad_runtime = dict(state.pad_runtime)
    previous_active = state.active_selector_by_group.get(group)
    
    if previous_active and previous_active in state.pads:
        prev_behavior = state.pads[previous_active]
        new_pad_runtime[previous_active] = PadRuntimeState(
            is_active=False,
            current_color=prev_behavior.idle_color,
            blink_enabled=False
        )
        effects.append(SetLedEffect(previous_active, prev_behavior.idle_color, blink=False))
    
    # Activate matching pad
    behavior = state.pads[matching_pad]
    new_pad_runtime[matching_pad] = PadRuntimeState(
        is_active=True,
        current_color=behavior.active_color,
        blink_enabled=True
    )
    effects.append(SetLedEffect(matching_pad, behavior.active_color, blink=True))
    
    # Update active selector tracking
    new_active_selectors = dict(state.active_selector_by_group)
    new_active_selectors[group] = matching_pad
    
    new_state = replace(
        state,
        pad_runtime=new_pad_runtime,
        active_selector_by_group=new_active_selectors
    )
    
    return new_state, effects


# =============================================================================
# LEARN MODE FSM TRANSITIONS
# =============================================================================

def enter_learn_mode(state: ControllerState) -> Tuple[ControllerState, List[Effect]]:
    """
    Enter learn mode (pure function).
    
    Transitions from NORMAL → LEARN_WAIT_PAD.
    
    Returns:
        (new_state, effects)
    """
    if state.app_mode != AppMode.NORMAL:
        return state, [LogEffect("Already in learn mode", level="WARNING")]
    
    new_learn_state = LearnState()  # Reset learn state
    new_state = replace(
        state,
        learn_state=new_learn_state,
        app_mode=AppMode.LEARN_WAIT_PAD
    )
    
    effects = [LogEffect("Learn mode: Press a pad to configure...")]
    
    return new_state, effects


def cancel_learn_mode(state: ControllerState) -> Tuple[ControllerState, List[Effect]]:
    """
    Cancel learn mode (pure function).
    
    Transitions to NORMAL from any learn state.
    
    Returns:
        (new_state, effects)
    """
    if state.app_mode == AppMode.NORMAL:
        return state, []
    
    # Clear any learn-mode LED states
    effects: List[Effect] = []
    if state.learn_state.selected_pad:
        pad_id = state.learn_state.selected_pad
        if pad_id in state.pads:
            behavior = state.pads[pad_id]
            runtime = state.pad_runtime.get(pad_id, PadRuntimeState())
            color = behavior.active_color if runtime.is_active else behavior.idle_color
            effects.append(SetLedEffect(pad_id, color, blink=runtime.blink_enabled))
    
    new_state = replace(
        state,
        learn_state=LearnState(),
        app_mode=AppMode.NORMAL
    )
    
    effects.append(LogEffect("Learn mode cancelled"))
    
    return new_state, effects


def finish_osc_recording(state: ControllerState) -> Tuple[ControllerState, List[Effect]]:
    """
    Finish OSC recording phase (pure function).
    
    Transitions from LEARN_RECORD_OSC → LEARN_SELECT_MSG.
    Processes recorded events into candidate commands.
    
    Returns:
        (new_state, effects)
    """
    if state.app_mode != AppMode.LEARN_RECORD_OSC:
        return state, []
    
    # Filter to controllable addresses and deduplicate
    candidates: List[OscCommand] = []
    seen_addresses = set()
    
    for event in state.learn_state.recorded_osc_events:
        if OscCommand.is_controllable(event.address):
            addr_key = (event.address, tuple(event.args))
            if addr_key not in seen_addresses:
                candidates.append(event.to_command())
                seen_addresses.add(addr_key)
    
    new_learn_state = replace(
        state.learn_state,
        candidate_commands=candidates
    )
    
    new_state = replace(
        state,
        learn_state=new_learn_state,
        app_mode=AppMode.LEARN_SELECT_MSG
    )
    
    effects = [
        LogEffect(f"Recorded {len(candidates)} unique controllable OSC messages")
    ]
    
    return new_state, effects


def select_learn_command(
    state: ControllerState,
    command_index: int,
    pad_mode: PadMode,
    group: Optional[PadGroupName],
    idle_color: int,
    active_color: int,
    label: str = ""
) -> Tuple[ControllerState, List[Effect]]:
    """
    Complete learn mode by selecting command and configuring pad (pure function).
    
    Transitions from LEARN_SELECT_MSG → NORMAL.
    Creates/updates pad behavior and saves config.
    
    Returns:
        (new_state, effects)
    """
    if state.app_mode != AppMode.LEARN_SELECT_MSG:
        return state, [LogEffect("Not in command selection mode", level="ERROR")]
    
    if not (0 <= command_index < len(state.learn_state.candidate_commands)):
        return state, [LogEffect("Invalid command index", level="ERROR")]
    
    pad_id = state.learn_state.selected_pad
    if not pad_id:
        return state, [LogEffect("No pad selected", level="ERROR")]
    
    # Get selected command
    osc_command = state.learn_state.candidate_commands[command_index]
    
    # Create pad behavior
    if pad_mode == PadMode.SELECTOR:
        if not group:
            return state, [LogEffect("SELECTOR mode requires group", level="ERROR")]
        behavior = PadBehavior(
            pad_id=pad_id,
            mode=pad_mode,
            group=group,
            idle_color=idle_color,
            active_color=active_color,
            label=label,
            osc_action=osc_command
        )
    elif pad_mode == PadMode.TOGGLE:
        # For toggle, use command as osc_on
        # Could enhance to derive osc_off
        behavior = PadBehavior(
            pad_id=pad_id,
            mode=pad_mode,
            idle_color=idle_color,
            active_color=active_color,
            label=label,
            osc_on=osc_command,
            osc_off=None  # TODO: Could derive from pattern
        )
    else:  # ONE_SHOT
        behavior = PadBehavior(
            pad_id=pad_id,
            mode=pad_mode,
            idle_color=idle_color,
            active_color=active_color,
            label=label,
            osc_action=osc_command
        )
    
    # Update pads configuration
    new_pads = dict(state.pads)
    new_pads[pad_id] = behavior
    
    # Initialize runtime state
    new_pad_runtime = dict(state.pad_runtime)
    new_pad_runtime[pad_id] = PadRuntimeState(
        is_active=False,
        current_color=idle_color,
        blink_enabled=False
    )
    
    new_state = replace(
        state,
        pads=new_pads,
        pad_runtime=new_pad_runtime,
        learn_state=LearnState(),
        app_mode=AppMode.NORMAL
    )
    
    effects = [
        SetLedEffect(pad_id, idle_color, blink=False),
        SaveConfigEffect(),
        LogEffect(f"Learned {pad_mode.name} pad: {label or pad_id} → {osc_command}")
    ]
    
    return new_state, effects


# =============================================================================
# BANK SWITCHING
# =============================================================================

def switch_bank(state: ControllerState, bank_index: int) -> Tuple[ControllerState, List[Effect]]:
    """
    Switch to a different bank (pure function).
    
    Args:
        state: Current controller state
        bank_index: Target bank index (0-7)
    
    Returns:
        (new_state, effects)
    """
    if not (0 <= bank_index < len(state.available_banks)):
        return state, [LogEffect(f"Invalid bank index: {bank_index}", level="ERROR")]
    
    bank = state.available_banks[bank_index]
    
    new_state = replace(
        state,
        active_bank_index=bank_index,
        active_bank_name=bank.name
    )
    
    effects = [
        LogEffect(f"Switched to bank {bank_index}: {bank.name}"),
        SaveConfigEffect()  # Save bank preference
    ]
    
    return new_state, effects
