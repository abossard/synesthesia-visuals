"""
Finite State Machine Logic - Pure Functions

All functions are pure: same input = same output, no side effects.
Returns new state and list of effects to be executed by imperative shell.

Unified FSM supporting:
- Normal pad interaction (SELECTOR, TOGGLE, ONE_SHOT, PUSH)
- Learn mode with CONFIG phase (OSC/Mode/Color selection)
- Bank-aware operation (top row blocked during CONFIG)
"""

from typing import List, Tuple, Optional
from dataclasses import replace

from .button_id import ButtonId
from .model import (
    ControllerState, PadBehavior, PadRuntimeState,
    PadMode, ButtonGroupType, LearnPhase, LearnRegister, LearnState,
    OscCommand, OscEvent,
    Effect, SendOscEffect, LedEffect, SaveConfigEffect, LogEffect,
    BrightnessLevel, BASE_COLOR_NAMES, get_color_at_brightness,
)
from .synesthesia_config import categorize_osc, is_controllable

# Backward compatibility aliases
AppMode = LearnPhase
PadGroupName = ButtonGroupType


# =============================================================================
# BUTTON CONSTANTS (for CONFIG phase)
# =============================================================================

# Scene buttons (right column, x=8)
LEARN_BUTTON = ButtonId(8, 0)  # Bottom-right scene button

# Bottom row: Save (green), Test (blue), Cancel (red)
SAVE_PAD = ButtonId(0, 0)
TEST_PAD = ButtonId(1, 0)
CANCEL_PAD = ButtonId(7, 0)

# Top row (y=7): Register selection (3 yellow pads)
REGISTER_OSC_PAD = ButtonId(0, 7)
REGISTER_MODE_PAD = ButtonId(1, 7)
REGISTER_COLOR_PAD = ButtonId(2, 7)

# OSC pagination (in top row)
OSC_PAGE_PREV = ButtonId(6, 7)
OSC_PAGE_NEXT = ButtonId(7, 7)

# Brightness controls (row 1 in color selection)
IDLE_BRIGHTNESS_DOWN = ButtonId(0, 1)
IDLE_BRIGHTNESS_UP = ButtonId(1, 1)
ACTIVE_BRIGHTNESS_DOWN = ButtonId(6, 1)
ACTIVE_BRIGHTNESS_UP = ButtonId(7, 1)


# =============================================================================
# STATE TRANSITION HELPERS
# =============================================================================

def is_in_config_phase(state: ControllerState) -> bool:
    """Check if app is in CONFIG phase (blocks bank switching)."""
    return state.learn_state.phase == LearnPhase.CONFIG


# =============================================================================
# LEARN MODE TRANSITIONS
# =============================================================================

def enter_learn_mode(state: ControllerState) -> Tuple[ControllerState, List[Effect]]:
    """Enter learn mode - start waiting for pad selection."""
    new_learn = LearnState(phase=LearnPhase.WAIT_PAD)
    new_state = replace(state, learn_state=new_learn)
    
    effects: List[Effect] = [LogEffect("Entered learn mode - press a pad to configure")]
    return new_state, effects


def exit_learn_mode(state: ControllerState) -> Tuple[ControllerState, List[Effect]]:
    """Exit learn mode - return to normal operation."""
    new_learn = LearnState(phase=LearnPhase.IDLE)
    new_state = replace(state, learn_state=new_learn)
    
    effects: List[Effect] = [LogEffect("Exited learn mode")]
    return new_state, effects


# Alias for backward compatibility
cancel_learn_mode = exit_learn_mode


def select_pad(state: ControllerState, pad_id: ButtonId) -> Tuple[ControllerState, List[Effect]]:
    """User selected a pad to configure - start recording OSC."""
    new_learn = replace(
        state.learn_state,
        phase=LearnPhase.RECORD_OSC,
        selected_pad=pad_id,
        recorded_events=[],
    )
    new_state = replace(state, learn_state=new_learn)
    
    effects: List[Effect] = [LogEffect(f"Recording OSC for pad {pad_id}")]
    return new_state, effects


def record_osc_event(state: ControllerState, event: OscEvent) -> Tuple[ControllerState, List[Effect]]:
    """Record an incoming OSC event during recording phase."""
    if state.learn_state.phase != LearnPhase.RECORD_OSC:
        return state, []
    
    # Skip non-controllable addresses
    if not is_controllable(event.address):
        return state, []
    
    # Add to recorded events
    new_events = list(state.learn_state.recorded_events) + [event]
    new_learn = replace(state.learn_state, recorded_events=new_events)
    new_state = replace(state, learn_state=new_learn)
    
    # Log the event
    unique_count = len(set(e.address for e in new_events))
    effects: List[Effect] = [LogEffect(f"Recorded ({unique_count}): {event.address}")]
    
    return new_state, effects


def finish_recording(state: ControllerState) -> Tuple[ControllerState, List[Effect]]:
    """Finish OSC recording and move to config phase."""
    events = state.learn_state.recorded_events
    
    if not events:
        return exit_learn_mode(state)
    
    # Sort by priority and dedupe
    sorted_events = sorted(events, key=lambda e: (e.priority, e.timestamp))
    seen_addresses = set()
    unique_commands = []
    
    for event in sorted_events:
        if event.address not in seen_addresses:
            seen_addresses.add(event.address)
            unique_commands.append(event.to_command())
    
    # Auto-select mode based on first (highest priority) command
    first_cmd = unique_commands[0] if unique_commands else None
    if first_cmd:
        _, suggested_mode, _ = categorize_osc(first_cmd.address)
    else:
        suggested_mode = PadMode.TOGGLE
    
    new_learn = replace(
        state.learn_state,
        phase=LearnPhase.CONFIG,
        candidate_commands=unique_commands,
        selected_osc_index=0,
        selected_mode=suggested_mode,
        active_register=LearnRegister.OSC_SELECT,
    )
    new_state = replace(state, learn_state=new_learn)
    
    effects: List[Effect] = [
        LogEffect(f"Recorded {len(unique_commands)} unique commands")
    ]
    return new_state, effects


# Alias for backward compatibility
finish_osc_recording = finish_recording


# =============================================================================
# CONFIG PHASE HANDLERS
# =============================================================================

def handle_config_pad_press(state: ControllerState, pad_id: ButtonId) -> Tuple[ControllerState, List[Effect]]:
    """Handle pad press during config phase."""
    learn = state.learn_state
    
    # Check for action buttons
    if pad_id == SAVE_PAD:
        return save_config(state)
    elif pad_id == TEST_PAD:
        return test_config(state)
    elif pad_id == CANCEL_PAD:
        return exit_learn_mode(state)
    
    # Check for register selection
    if pad_id == REGISTER_OSC_PAD:
        new_learn = replace(learn, active_register=LearnRegister.OSC_SELECT)
        return replace(state, learn_state=new_learn), []
    elif pad_id == REGISTER_MODE_PAD:
        new_learn = replace(learn, active_register=LearnRegister.MODE_SELECT)
        return replace(state, learn_state=new_learn), []
    elif pad_id == REGISTER_COLOR_PAD:
        new_learn = replace(learn, active_register=LearnRegister.COLOR_SELECT)
        return replace(state, learn_state=new_learn), []
    
    # Handle register-specific input
    if learn.active_register == LearnRegister.OSC_SELECT:
        return _handle_osc_select(state, pad_id)
    elif learn.active_register == LearnRegister.MODE_SELECT:
        return _handle_mode_select(state, pad_id)
    elif learn.active_register == LearnRegister.COLOR_SELECT:
        return _handle_color_select(state, pad_id)
    
    return state, []


def _handle_osc_select(state: ControllerState, pad_id: ButtonId) -> Tuple[ControllerState, List[Effect]]:
    """Handle pad press in OSC selection register."""
    learn = state.learn_state
    
    # Pagination
    if pad_id == OSC_PAGE_PREV and learn.osc_page > 0:
        new_learn = replace(learn, osc_page=learn.osc_page - 1)
        return replace(state, learn_state=new_learn), []
    
    max_pages = (len(learn.candidate_commands) - 1) // 8
    if pad_id == OSC_PAGE_NEXT and learn.osc_page < max_pages:
        new_learn = replace(learn, osc_page=learn.osc_page + 1)
        return replace(state, learn_state=new_learn), []
    
    # OSC selection (row 3, columns 0-7)
    if pad_id.y == 3 and 0 <= pad_id.x <= 7:
        index = learn.osc_page * 8 + pad_id.x
        if index < len(learn.candidate_commands):
            cmd = learn.candidate_commands[index]
            _, suggested_mode, _ = categorize_osc(cmd.address)
            new_learn = replace(
                learn,
                selected_osc_index=index,
                selected_mode=suggested_mode
            )
            return replace(state, learn_state=new_learn), []
    
    return state, []


def _handle_mode_select(state: ControllerState, pad_id: ButtonId) -> Tuple[ControllerState, List[Effect]]:
    """Handle pad press in mode selection register."""
    learn = state.learn_state
    
    # Mode buttons (row 3, cols 0-3)
    if pad_id.y == 3 and 0 <= pad_id.x <= 3:
        modes = [PadMode.TOGGLE, PadMode.PUSH, PadMode.ONE_SHOT, PadMode.SELECTOR]
        new_learn = replace(learn, selected_mode=modes[pad_id.x])
        return replace(state, learn_state=new_learn), []
    
    return state, []


def _handle_color_select(state: ControllerState, pad_id: ButtonId) -> Tuple[ControllerState, List[Effect]]:
    """Handle pad press in color selection register."""
    learn = state.learn_state
    base_colors_to_show = BASE_COLOR_NAMES[:10]
    
    # Brightness level selection (row 5)
    if pad_id.y == 5 and 0 <= pad_id.x <= 2:
        new_brightness = BrightnessLevel(pad_id.x)
        color_name, _ = _find_base_color_for_velocity(learn.selected_idle_color, base_colors_to_show, learn.idle_brightness)
        new_color = get_color_at_brightness(color_name, new_brightness) if color_name else learn.selected_idle_color
        new_learn = replace(learn, idle_brightness=new_brightness, selected_idle_color=new_color)
        return replace(state, learn_state=new_learn), []
    
    if pad_id.y == 5 and 5 <= pad_id.x <= 7:
        new_brightness = BrightnessLevel(pad_id.x - 5)
        color_name, _ = _find_base_color_for_velocity(learn.selected_active_color, base_colors_to_show, learn.active_brightness)
        new_color = get_color_at_brightness(color_name, new_brightness) if color_name else learn.selected_active_color
        new_learn = replace(learn, active_brightness=new_brightness, selected_active_color=new_color)
        return replace(state, learn_state=new_learn), []
    
    # Brightness adjustment buttons (row 1)
    if pad_id == IDLE_BRIGHTNESS_DOWN:
        new_level = max(0, learn.idle_brightness.value - 1)
        new_brightness = BrightnessLevel(new_level)
        color_name, _ = _find_base_color_for_velocity(learn.selected_idle_color, base_colors_to_show, learn.idle_brightness)
        new_color = get_color_at_brightness(color_name, new_brightness) if color_name else learn.selected_idle_color
        new_learn = replace(learn, idle_brightness=new_brightness, selected_idle_color=new_color)
        return replace(state, learn_state=new_learn), []
    
    if pad_id == IDLE_BRIGHTNESS_UP:
        new_level = min(2, learn.idle_brightness.value + 1)
        new_brightness = BrightnessLevel(new_level)
        color_name, _ = _find_base_color_for_velocity(learn.selected_idle_color, base_colors_to_show, learn.idle_brightness)
        new_color = get_color_at_brightness(color_name, new_brightness) if color_name else learn.selected_idle_color
        new_learn = replace(learn, idle_brightness=new_brightness, selected_idle_color=new_color)
        return replace(state, learn_state=new_learn), []
    
    if pad_id == ACTIVE_BRIGHTNESS_DOWN:
        new_level = max(0, learn.active_brightness.value - 1)
        new_brightness = BrightnessLevel(new_level)
        color_name, _ = _find_base_color_for_velocity(learn.selected_active_color, base_colors_to_show, learn.active_brightness)
        new_color = get_color_at_brightness(color_name, new_brightness) if color_name else learn.selected_active_color
        new_learn = replace(learn, active_brightness=new_brightness, selected_active_color=new_color)
        return replace(state, learn_state=new_learn), []
    
    if pad_id == ACTIVE_BRIGHTNESS_UP:
        new_level = min(2, learn.active_brightness.value + 1)
        new_brightness = BrightnessLevel(new_level)
        color_name, _ = _find_base_color_for_velocity(learn.selected_active_color, base_colors_to_show, learn.active_brightness)
        new_color = get_color_at_brightness(color_name, new_brightness) if color_name else learn.selected_active_color
        new_learn = replace(learn, active_brightness=new_brightness, selected_active_color=new_color)
        return replace(state, learn_state=new_learn), []
    
    # Color selection grids (rows 2-4)
    if 0 <= pad_id.x <= 3 and 2 <= pad_id.y <= 3:
        idx = (pad_id.y - 2) * 4 + pad_id.x
        if idx < len(base_colors_to_show):
            color_name = base_colors_to_show[idx]
            new_color = get_color_at_brightness(color_name, learn.idle_brightness)
            new_learn = replace(learn, selected_idle_color=new_color)
            return replace(state, learn_state=new_learn), []
    
    if pad_id.y == 4 and 0 <= pad_id.x <= 1:
        idx = 8 + pad_id.x
        if idx < len(base_colors_to_show):
            color_name = base_colors_to_show[idx]
            new_color = get_color_at_brightness(color_name, learn.idle_brightness)
            new_learn = replace(learn, selected_idle_color=new_color)
            return replace(state, learn_state=new_learn), []
    
    if 4 <= pad_id.x <= 7 and 2 <= pad_id.y <= 3:
        idx = (pad_id.y - 2) * 4 + (pad_id.x - 4)
        if idx < len(base_colors_to_show):
            color_name = base_colors_to_show[idx]
            new_color = get_color_at_brightness(color_name, learn.active_brightness)
            new_learn = replace(learn, selected_active_color=new_color)
            return replace(state, learn_state=new_learn), []
    
    if pad_id.y == 4 and 6 <= pad_id.x <= 7:
        idx = 8 + (pad_id.x - 6)
        if idx < len(base_colors_to_show):
            color_name = base_colors_to_show[idx]
            new_color = get_color_at_brightness(color_name, learn.active_brightness)
            new_learn = replace(learn, selected_active_color=new_color)
            return replace(state, learn_state=new_learn), []
    
    return state, []


def _find_base_color_for_velocity(velocity: int, base_colors: list, current_brightness: BrightnessLevel) -> Tuple[Optional[str], Optional[BrightnessLevel]]:
    """Find which base color matches a velocity value."""
    for color_name in base_colors:
        if get_color_at_brightness(color_name, current_brightness) == velocity:
            return color_name, current_brightness
    for color_name in base_colors:
        for level in BrightnessLevel:
            if get_color_at_brightness(color_name, level) == velocity:
                return color_name, level
    return None, None


def test_config(state: ControllerState) -> Tuple[ControllerState, List[Effect]]:
    """Send the selected OSC command as a test."""
    learn = state.learn_state
    
    if learn.candidate_commands and learn.selected_osc_index < len(learn.candidate_commands):
        cmd = learn.candidate_commands[learn.selected_osc_index]
        test_cmd = OscCommand(cmd.address, [1.0]) if learn.selected_mode in (PadMode.TOGGLE, PadMode.PUSH) else cmd
        return state, [SendOscEffect(test_cmd), LogEffect(f"Test: {test_cmd}")]
    
    return state, []


def save_from_recording(state: ControllerState) -> Tuple[ControllerState, List[Effect]]:
    """Save directly from recording phase using the last recorded OSC event."""
    learn = state.learn_state
    events = learn.recorded_events
    
    if not learn.selected_pad or not events:
        return exit_learn_mode(state)
    
    last_event = events[-1]
    cmd = last_event.to_command()
    _, suggested_mode, group = categorize_osc(cmd.address)
    
    behavior = _create_pad_behavior(
        pad_id=learn.selected_pad, mode=suggested_mode, osc_command=cmd,
        idle_color=learn.selected_idle_color, active_color=learn.selected_active_color,
        label=cmd.address.split("/")[-1], group=ButtonGroupType(group) if group else None,
    )
    
    new_pads = dict(state.pads)
    new_pads[learn.selected_pad] = behavior
    new_pad_runtime = dict(state.pad_runtime)
    new_pad_runtime[learn.selected_pad] = PadRuntimeState(is_active=False, current_color=learn.selected_idle_color)
    
    new_state, effects = exit_learn_mode(replace(state, pads=new_pads, pad_runtime=new_pad_runtime))
    effects.extend([SaveConfigEffect(), LogEffect(f"Saved: {cmd.address} for pad {learn.selected_pad}")])
    return new_state, effects


def save_config(state: ControllerState) -> Tuple[ControllerState, List[Effect]]:
    """Save the current configuration (from CONFIG phase)."""
    learn = state.learn_state
    
    if not learn.selected_pad or not learn.candidate_commands:
        return exit_learn_mode(state)
    
    cmd = learn.candidate_commands[learn.selected_osc_index]
    _, _, group = categorize_osc(cmd.address)
    
    behavior = _create_pad_behavior(
        pad_id=learn.selected_pad, mode=learn.selected_mode or PadMode.TOGGLE, osc_command=cmd,
        idle_color=learn.selected_idle_color, active_color=learn.selected_active_color,
        label=cmd.address.split("/")[-1], group=ButtonGroupType(group) if group else None,
    )
    
    new_pads = dict(state.pads)
    new_pads[learn.selected_pad] = behavior
    new_pad_runtime = dict(state.pad_runtime)
    new_pad_runtime[learn.selected_pad] = PadRuntimeState(is_active=False, current_color=learn.selected_idle_color)
    
    new_state, effects = exit_learn_mode(replace(state, pads=new_pads, pad_runtime=new_pad_runtime))
    effects.extend([SaveConfigEffect(), LogEffect(f"Saved config for pad {learn.selected_pad}")])
    return new_state, effects


def _create_pad_behavior(pad_id, mode, osc_command, idle_color, active_color, label, group):
    """Create a PadBehavior based on mode."""
    if mode == PadMode.TOGGLE:
        return PadBehavior(pad_id=pad_id, mode=mode, idle_color=idle_color, active_color=active_color, label=label,
                          osc_on=OscCommand(osc_command.address, [1.0]), osc_off=OscCommand(osc_command.address, [0.0]))
    elif mode == PadMode.SELECTOR:
        return PadBehavior(pad_id=pad_id, mode=mode, group=group or ButtonGroupType.CUSTOM,
                          idle_color=idle_color, active_color=active_color, label=label, osc_action=osc_command)
    else:
        return PadBehavior(pad_id=pad_id, mode=mode, idle_color=idle_color, active_color=active_color, label=label, osc_action=osc_command)


# =============================================================================
# MAIN PAD PRESS HANDLER
# =============================================================================

def handle_pad_press(state: ControllerState, pad_id: ButtonId) -> Tuple[ControllerState, List[Effect]]:
    """Main pad press handler - routes based on current phase."""
    phase = state.learn_state.phase
    
    if pad_id == LEARN_BUTTON:
        return enter_learn_mode(state) if phase == LearnPhase.IDLE else exit_learn_mode(state)
    
    if phase == LearnPhase.IDLE:
        return handle_normal_press(state, pad_id)
    elif phase == LearnPhase.WAIT_PAD:
        return select_pad(state, pad_id) if pad_id.is_grid() else (state, [])
    elif phase == LearnPhase.RECORD_OSC:
        if pad_id == SAVE_PAD:
            return save_from_recording(state)
        elif pad_id == CANCEL_PAD:
            return exit_learn_mode(state)
        return state, []
    elif phase == LearnPhase.CONFIG:
        return handle_config_pad_press(state, pad_id)
    
    return state, []


def handle_normal_press(state: ControllerState, pad_id: ButtonId) -> Tuple[ControllerState, List[Effect]]:
    """Handle pad press during normal operation."""
    if pad_id not in state.pads:
        return state, []
    
    behavior = state.pads[pad_id]
    
    if behavior.mode == PadMode.SELECTOR:
        return _handle_selector_press(state, pad_id, behavior)
    elif behavior.mode == PadMode.TOGGLE:
        return _handle_toggle_press(state, pad_id, behavior)
    elif behavior.mode == PadMode.ONE_SHOT:
        return _handle_one_shot_press(state, pad_id, behavior)
    elif behavior.mode == PadMode.PUSH:
        return _handle_push_press(state, pad_id, behavior)
    return state, []


def _handle_selector_press(state, pad_id, behavior):
    """Handle SELECTOR pad press."""
    effects = []
    group = behavior.group
    previous_active = state.active_selector_by_group.get(group)
    new_pad_runtime = dict(state.pad_runtime)
    
    if previous_active and previous_active in state.pads:
        prev_behavior = state.pads[previous_active]
        new_pad_runtime[previous_active] = PadRuntimeState(is_active=False, current_color=prev_behavior.idle_color)
        effects.append(LedEffect(previous_active, prev_behavior.idle_color, blink=False))
    
    new_pad_runtime[pad_id] = PadRuntimeState(is_active=True, current_color=behavior.active_color)
    effects.append(LedEffect(pad_id, behavior.active_color, blink=True))
    
    new_active_selectors = dict(state.active_selector_by_group)
    new_active_selectors[group] = pad_id
    
    if behavior.osc_action:
        effects.append(SendOscEffect(behavior.osc_action))
    
    return replace(state, pad_runtime=new_pad_runtime, active_selector_by_group=new_active_selectors), effects


def _handle_toggle_press(state, pad_id, behavior):
    """Handle TOGGLE pad press."""
    effects = []
    current_runtime = state.pad_runtime.get(pad_id, PadRuntimeState())
    new_is_on = not current_runtime.is_on
    osc_cmd = behavior.osc_on if new_is_on else behavior.osc_off
    new_color = behavior.active_color if new_is_on else behavior.idle_color
    
    new_pad_runtime = dict(state.pad_runtime)
    new_pad_runtime[pad_id] = PadRuntimeState(is_active=new_is_on, is_on=new_is_on, current_color=new_color)
    effects.append(LedEffect(pad_id, new_color, blink=False))
    
    if osc_cmd:
        effects.append(SendOscEffect(osc_cmd))
    
    return replace(state, pad_runtime=new_pad_runtime), effects


def _handle_one_shot_press(state, pad_id, behavior):
    """Handle ONE_SHOT pad press."""
    effects = []
    new_pad_runtime = dict(state.pad_runtime)
    new_pad_runtime[pad_id] = PadRuntimeState(is_active=False, current_color=behavior.active_color)
    effects.append(LedEffect(pad_id, behavior.active_color, blink=False))
    
    if behavior.osc_action:
        effects.append(SendOscEffect(behavior.osc_action))
    
    return replace(state, pad_runtime=new_pad_runtime), effects


def _handle_push_press(state, pad_id, behavior):
    """Handle PUSH pad press."""
    effects = []
    new_pad_runtime = dict(state.pad_runtime)
    new_pad_runtime[pad_id] = PadRuntimeState(is_active=True, is_on=True, current_color=behavior.active_color)
    effects.append(LedEffect(pad_id, behavior.active_color, blink=False))
    
    if behavior.osc_action:
        effects.append(SendOscEffect(OscCommand(behavior.osc_action.address, [1.0])))
    
    return replace(state, pad_runtime=new_pad_runtime), effects


def handle_pad_release(state: ControllerState, pad_id: ButtonId) -> Tuple[ControllerState, List[Effect]]:
    """Handle pad release (for PUSH mode)."""
    if state.learn_state.phase != LearnPhase.IDLE or pad_id not in state.pads:
        return state, []
    
    behavior = state.pads[pad_id]
    if behavior.mode != PadMode.PUSH:
        return state, []
    
    effects = []
    new_pad_runtime = dict(state.pad_runtime)
    new_pad_runtime[pad_id] = PadRuntimeState(is_active=False, is_on=False, current_color=behavior.idle_color)
    effects.append(LedEffect(pad_id, behavior.idle_color, blink=False))
    
    if behavior.osc_action:
        effects.append(SendOscEffect(OscCommand(behavior.osc_action.address, [0.0])))
    
    return replace(state, pad_runtime=new_pad_runtime), effects


def toggle_blink(state: ControllerState) -> ControllerState:
    """Toggle blink state (for animations)."""
    return replace(state, blink_on=not state.blink_on)


# =============================================================================
# OSC EVENT HANDLING
# =============================================================================

def handle_osc_event(state: ControllerState, event: OscEvent) -> Tuple[ControllerState, List[Effect]]:
    """Handle incoming OSC event."""
    effects = []
    
    if state.learn_state.phase == LearnPhase.RECORD_OSC and is_controllable(event.address):
        new_recorded = list(state.learn_state.recorded_events) + [event]
        new_learn = replace(state.learn_state, recorded_events=new_recorded)
        state = replace(state, learn_state=new_learn)
    
    new_last_messages = list(state.last_osc_messages[-49:]) + [event]
    state = replace(state, last_osc_messages=new_last_messages)
    
    if event.address == "/audio/beat/onbeat":
        state = replace(state, beat_pulse=bool(event.args[0]) if event.args else False)
    elif event.address.startswith("/scenes/"):
        scene_name = event.address.split("/")[-1]
        state = replace(state, active_scene=scene_name)
        state, led_effects = _activate_matching_selector(state, event.to_command(), ButtonGroupType.SCENES)
        effects.extend(led_effects)
        state, reset_effects = _reset_subgroup(state, ButtonGroupType.SCENES)
        effects.extend(reset_effects)
    elif event.address.startswith("/presets/") or event.address.startswith("/favslots/"):
        preset_name = event.address.split("/")[-1]
        state = replace(state, active_preset=preset_name)
        state, led_effects = _activate_matching_selector(state, event.to_command(), ButtonGroupType.PRESETS)
        effects.extend(led_effects)
    elif event.address == "/controls/meta/hue" and event.args:
        state = replace(state, active_color_hue=float(event.args[0]))
        state, led_effects = _activate_matching_selector(state, event.to_command(), ButtonGroupType.COLORS)
        effects.extend(led_effects)
    
    return state, effects


def _activate_matching_selector(state, command, group):
    """Find and activate a selector pad matching the given OSC command."""
    effects = []
    matching_pad = None
    for pad_id, behavior in state.pads.items():
        if behavior.mode == PadMode.SELECTOR and behavior.group == group and behavior.osc_action and behavior.osc_action.address == command.address:
            matching_pad = pad_id
            break
    
    if not matching_pad:
        return state, effects
    
    new_pad_runtime = dict(state.pad_runtime)
    previous_active = state.active_selector_by_group.get(group)
    
    if previous_active and previous_active in state.pads:
        prev_behavior = state.pads[previous_active]
        new_pad_runtime[previous_active] = PadRuntimeState(is_active=False, current_color=prev_behavior.idle_color)
        effects.append(LedEffect(previous_active, prev_behavior.idle_color, blink=False))
    
    behavior = state.pads[matching_pad]
    new_pad_runtime[matching_pad] = PadRuntimeState(is_active=True, current_color=behavior.active_color)
    effects.append(LedEffect(matching_pad, behavior.active_color, blink=True))
    
    new_active_selectors = dict(state.active_selector_by_group)
    new_active_selectors[group] = matching_pad
    
    return replace(state, pad_runtime=new_pad_runtime, active_selector_by_group=new_active_selectors), effects


def _reset_subgroup(state, parent_group):
    """Reset child groups when parent group changes."""
    effects = []
    new_pad_runtime = dict(state.pad_runtime)
    new_active_selectors = dict(state.active_selector_by_group)
    
    for group_type in ButtonGroupType:
        if group_type.parent_group == parent_group:
            previous_active = new_active_selectors.get(group_type)
            if previous_active and previous_active in state.pads:
                prev_behavior = state.pads[previous_active]
                new_pad_runtime[previous_active] = PadRuntimeState(is_active=False, current_color=prev_behavior.idle_color)
                effects.append(LedEffect(previous_active, prev_behavior.idle_color, blink=False))
            new_active_selectors[group_type] = None
            for pad_id, behavior in state.pads.items():
                if behavior.mode == PadMode.SELECTOR and behavior.group == group_type and pad_id != previous_active:
                    new_pad_runtime[pad_id] = PadRuntimeState(is_active=False, current_color=behavior.idle_color)
                    effects.append(LedEffect(pad_id, behavior.idle_color, blink=False))
    
    return replace(state, pad_runtime=new_pad_runtime, active_selector_by_group=new_active_selectors, active_preset=None), effects


# =============================================================================
# BACKWARD COMPATIBILITY
# =============================================================================

def select_learn_command(state, command_index, pad_mode, group, idle_color, active_color, label=""):
    """Legacy function for completing learn mode."""
    learn = state.learn_state
    new_learn = replace(learn, selected_osc_index=command_index, selected_mode=pad_mode, selected_group=group,
                        selected_idle_color=idle_color, selected_active_color=active_color)
    return save_config(replace(state, learn_state=new_learn))


# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

def add_pad_behavior(state, behavior):
    """Add or update a pad configuration."""
    new_pads = dict(state.pads)
    new_pads[behavior.pad_id] = behavior
    new_pad_runtime = dict(state.pad_runtime)
    new_pad_runtime[behavior.pad_id] = PadRuntimeState(is_active=False, current_color=behavior.idle_color)
    return replace(state, pads=new_pads, pad_runtime=new_pad_runtime), [LedEffect(behavior.pad_id, behavior.idle_color), LogEffect(f"Added pad {behavior.pad_id}: {behavior.mode.name}")]


def remove_pad(state, pad_id):
    """Remove a pad configuration."""
    if pad_id not in state.pads:
        return state, []
    new_pads = dict(state.pads)
    del new_pads[pad_id]
    new_pad_runtime = dict(state.pad_runtime)
    if pad_id in new_pad_runtime:
        del new_pad_runtime[pad_id]
    new_active_selectors = {g: p for g, p in state.active_selector_by_group.items() if p != pad_id}
    return replace(state, pads=new_pads, pad_runtime=new_pad_runtime, active_selector_by_group=new_active_selectors), [LedEffect(pad_id, 0), LogEffect(f"Removed pad {pad_id}")]


def clear_all_pads(state):
    """Remove all pad configurations."""
    effects = [LedEffect(pad_id, 0) for pad_id in state.pads] + [LogEffect("Cleared all pads")]
    return replace(state, pads={}, pad_runtime={}, active_selector_by_group={}), effects


def refresh_all_leds(state):
    """Generate effects to refresh all LEDs based on current state."""
    effects = []
    for pad_id, behavior in state.pads.items():
        runtime = state.pad_runtime.get(pad_id, PadRuntimeState())
        blink = runtime.is_active and behavior.mode == PadMode.SELECTOR
        effects.append(LedEffect(pad_id, runtime.current_color, blink=blink))
    return effects
