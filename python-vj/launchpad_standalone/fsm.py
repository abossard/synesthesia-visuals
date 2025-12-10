"""
Learn Mode FSM (Finite State Machine)

Pure functions for state transitions. No side effects.
All transitions return (new_state, effects_list).
"""

from dataclasses import replace
from typing import List, Tuple, Union, Optional
import time

from .model import (
    AppState, LearnState, LearnPhase, LearnRegister, PadId, PadConfig,
    OscCommand, OscEvent, PadMode, ControllerConfig,
    LedEffect, SendOscEffect, SaveConfigEffect, LogEffect,
    LP_OFF, LP_GREEN, LP_GREEN_DIM, COLOR_PREVIEW_PALETTE,
)
from .osc_categories import categorize_osc, should_stop_recording, is_controllable
from .display import (
    LEARN_BUTTON, SAVE_PAD, TEST_PAD, CANCEL_PAD,
    REGISTER_OSC_PAD, REGISTER_MODE_PAD, REGISTER_COLOR_PAD,
    OSC_PAGE_PREV, OSC_PAGE_NEXT,
)


Effect = Union[LedEffect, SendOscEffect, SaveConfigEffect, LogEffect]


# =============================================================================
# STATE TRANSITIONS
# =============================================================================

def enter_learn_mode(state: AppState) -> Tuple[AppState, List[Effect]]:
    """Enter learn mode - start waiting for pad selection."""
    new_learn = LearnState(phase=LearnPhase.WAIT_PAD)
    new_state = replace(state, learn=new_learn)
    
    effects: List[Effect] = [LogEffect("Entered learn mode - press a pad to configure")]
    return new_state, effects


def exit_learn_mode(state: AppState) -> Tuple[AppState, List[Effect]]:
    """Exit learn mode - return to normal operation."""
    new_learn = LearnState(phase=LearnPhase.IDLE)
    new_state = replace(state, learn=new_learn)
    
    effects: List[Effect] = [LogEffect("Exited learn mode")]
    return new_state, effects


def select_pad(state: AppState, pad_id: PadId) -> Tuple[AppState, List[Effect]]:
    """User selected a pad to configure - start recording OSC."""
    new_learn = replace(
        state.learn,
        phase=LearnPhase.RECORD_OSC,
        selected_pad=pad_id,
        recorded_events=[],
    )
    new_state = replace(state, learn=new_learn)
    
    effects: List[Effect] = [LogEffect(f"Recording OSC for pad {pad_id}")]
    return new_state, effects


def record_osc_event(state: AppState, event: OscEvent) -> Tuple[AppState, List[Effect]]:
    """Record an incoming OSC event during recording phase."""
    if state.learn.phase != LearnPhase.RECORD_OSC:
        return state, []
    
    # Skip non-controllable addresses
    if not is_controllable(event.address):
        return state, []
    
    # Add to recorded events
    new_events = list(state.learn.recorded_events) + [event]
    new_learn = replace(state.learn, recorded_events=new_events)
    new_state = replace(state, learn=new_learn)
    
    effects: List[Effect] = [LogEffect(f"Recorded: {event.address}", "DEBUG")]
    
    # Check if this event should stop recording
    if should_stop_recording(event):
        return finish_recording(new_state)
    
    return new_state, effects


def finish_recording(state: AppState) -> Tuple[AppState, List[Effect]]:
    """Finish OSC recording and move to config phase."""
    events = state.learn.recorded_events
    
    if not events:
        # No events recorded - cancel
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
        state.learn,
        phase=LearnPhase.CONFIG,
        candidate_commands=unique_commands,
        selected_osc_index=0,
        selected_mode=suggested_mode,
        active_register=LearnRegister.OSC_SELECT,
    )
    new_state = replace(state, learn=new_learn)
    
    effects: List[Effect] = [
        LogEffect(f"Recorded {len(unique_commands)} unique commands")
    ]
    return new_state, effects


def handle_config_pad_press(state: AppState, pad_id: PadId) -> Tuple[AppState, List[Effect]]:
    """Handle pad press during config phase."""
    learn = state.learn
    
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
        return replace(state, learn=new_learn), []
    elif pad_id == REGISTER_MODE_PAD:
        new_learn = replace(learn, active_register=LearnRegister.MODE_SELECT)
        return replace(state, learn=new_learn), []
    elif pad_id == REGISTER_COLOR_PAD:
        new_learn = replace(learn, active_register=LearnRegister.COLOR_SELECT)
        return replace(state, learn=new_learn), []
    
    # Handle register-specific input
    if learn.active_register == LearnRegister.OSC_SELECT:
        return _handle_osc_select(state, pad_id)
    elif learn.active_register == LearnRegister.MODE_SELECT:
        return _handle_mode_select(state, pad_id)
    elif learn.active_register == LearnRegister.COLOR_SELECT:
        return _handle_color_select(state, pad_id)
    
    return state, []


def _handle_osc_select(state: AppState, pad_id: PadId) -> Tuple[AppState, List[Effect]]:
    """Handle pad press in OSC selection register."""
    learn = state.learn
    
    # Pagination
    if pad_id == OSC_PAGE_PREV and learn.osc_page > 0:
        new_learn = replace(learn, osc_page=learn.osc_page - 1)
        return replace(state, learn=new_learn), []
    
    max_pages = (len(learn.candidate_commands) - 1) // 8
    if pad_id == OSC_PAGE_NEXT and learn.osc_page < max_pages:
        new_learn = replace(learn, osc_page=learn.osc_page + 1)
        return replace(state, learn=new_learn), []
    
    # OSC selection (row 3, columns 0-7)
    if pad_id.y == 3 and 0 <= pad_id.x <= 7:
        index = learn.osc_page * 8 + pad_id.x
        if index < len(learn.candidate_commands):
            # Also auto-detect mode for new selection
            cmd = learn.candidate_commands[index]
            _, suggested_mode, _ = categorize_osc(cmd.address)
            new_learn = replace(
                learn,
                selected_osc_index=index,
                selected_mode=suggested_mode
            )
            return replace(state, learn=new_learn), []
    
    return state, []


def _handle_mode_select(state: AppState, pad_id: PadId) -> Tuple[AppState, List[Effect]]:
    """Handle pad press in mode selection register."""
    learn = state.learn
    
    # Mode buttons (row 3, cols 0-3)
    if pad_id.y == 3 and 0 <= pad_id.x <= 3:
        modes = [PadMode.TOGGLE, PadMode.PUSH, PadMode.ONE_SHOT, PadMode.SELECTOR]
        new_learn = replace(learn, selected_mode=modes[pad_id.x])
        return replace(state, learn=new_learn), []
    
    return state, []


def _handle_color_select(state: AppState, pad_id: PadId) -> Tuple[AppState, List[Effect]]:
    """Handle pad press in color selection register."""
    learn = state.learn
    
    # Left 4x4 grid: Idle color (cols 0-3, rows 2-5)
    if 0 <= pad_id.x <= 3 and 2 <= pad_id.y <= 5:
        idx = (pad_id.y - 2) * 4 + pad_id.x
        if idx < len(COLOR_PREVIEW_PALETTE):
            new_learn = replace(learn, selected_idle_color=COLOR_PREVIEW_PALETTE[idx])
            return replace(state, learn=new_learn), []
    
    # Right 4x4 grid: Active color (cols 4-7, rows 2-5)
    if 4 <= pad_id.x <= 7 and 2 <= pad_id.y <= 5:
        idx = (pad_id.y - 2) * 4 + (pad_id.x - 4)
        if idx < len(COLOR_PREVIEW_PALETTE):
            new_learn = replace(learn, selected_active_color=COLOR_PREVIEW_PALETTE[idx])
            return replace(state, learn=new_learn), []
    
    return state, []


def test_config(state: AppState) -> Tuple[AppState, List[Effect]]:
    """Send the selected OSC command as a test."""
    learn = state.learn
    
    if learn.candidate_commands and learn.selected_osc_index < len(learn.candidate_commands):
        cmd = learn.candidate_commands[learn.selected_osc_index]
        
        # For toggle/push modes, send with 1.0 argument
        if learn.selected_mode in (PadMode.TOGGLE, PadMode.PUSH):
            test_cmd = OscCommand(cmd.address, [1.0])
        else:
            test_cmd = cmd
        
        effects: List[Effect] = [
            SendOscEffect(test_cmd),
            LogEffect(f"Test: {test_cmd}")
        ]
        return state, effects
    
    return state, []


def save_config(state: AppState) -> Tuple[AppState, List[Effect]]:
    """Save the current configuration."""
    learn = state.learn
    
    if not learn.selected_pad or not learn.candidate_commands:
        return exit_learn_mode(state)
    
    cmd = learn.candidate_commands[learn.selected_osc_index]
    _, _, group = categorize_osc(cmd.address)
    
    pad_config = PadConfig(
        pad_id=learn.selected_pad,
        mode=learn.selected_mode,
        osc_command=cmd,
        idle_color=learn.selected_idle_color,
        active_color=learn.selected_active_color,
        label=cmd.address.split("/")[-1],
        group=group,
    )
    
    # Update config
    config = state.config or ControllerConfig()
    config.add_pad(pad_config)
    
    new_state, effects = exit_learn_mode(replace(state, config=config))
    
    effects.append(SaveConfigEffect(config))
    effects.append(LogEffect(f"Saved config for pad {learn.selected_pad}"))
    
    return new_state, effects


def toggle_blink(state: AppState) -> AppState:
    """Toggle blink state (for animations)."""
    return replace(state, blink_on=not state.blink_on)


# =============================================================================
# MAIN EVENT HANDLERS
# =============================================================================

def handle_pad_press(state: AppState, pad_id: PadId) -> Tuple[AppState, List[Effect]]:
    """
    Main pad press handler.
    
    Routes to appropriate handler based on current phase.
    """
    phase = state.learn.phase
    
    # Scene button handling
    if pad_id == LEARN_BUTTON:
        if phase == LearnPhase.IDLE:
            return enter_learn_mode(state)
        else:
            return exit_learn_mode(state)
    
    # Phase-specific handling
    if phase == LearnPhase.IDLE:
        return handle_normal_press(state, pad_id)
    elif phase == LearnPhase.WAIT_PAD:
        if pad_id.is_grid():
            return select_pad(state, pad_id)
    elif phase == LearnPhase.RECORD_OSC:
        # During recording, pad presses don't do anything
        return state, []
    elif phase == LearnPhase.CONFIG:
        return handle_config_pad_press(state, pad_id)
    
    return state, []


def handle_normal_press(state: AppState, pad_id: PadId) -> Tuple[AppState, List[Effect]]:
    """Handle pad press during normal operation."""
    if not state.config:
        return state, []
    
    pad_config = state.config.get_pad(pad_id)
    if not pad_config:
        return state, []
    
    effects: List[Effect] = []
    
    # Handle based on mode
    if pad_config.mode == PadMode.ONE_SHOT:
        effects.append(SendOscEffect(pad_config.osc_command))
    
    elif pad_config.mode == PadMode.TOGGLE:
        key = f"{pad_id.x},{pad_id.y}"
        runtime = state.pad_runtime.get(key)
        is_on = not (runtime and runtime.is_on) if runtime else True
        
        # Derive on/off commands from address
        if is_on:
            cmd = OscCommand(pad_config.osc_command.address, [1.0])
        else:
            cmd = OscCommand(pad_config.osc_command.address, [0.0])
        
        effects.append(SendOscEffect(cmd))
        
        # Update runtime state
        from .model import PadRuntimeState
        new_runtime = dict(state.pad_runtime)
        new_runtime[key] = PadRuntimeState(is_on=is_on, is_active=is_on)
        new_state = replace(state, pad_runtime=new_runtime)
        return new_state, effects
    
    elif pad_config.mode == PadMode.PUSH:
        cmd = OscCommand(pad_config.osc_command.address, [1.0])
        effects.append(SendOscEffect(cmd))
    
    elif pad_config.mode == PadMode.SELECTOR:
        effects.append(SendOscEffect(pad_config.osc_command))
        
        # Update group state
        if pad_config.group:
            new_active = dict(state.active_by_group)
            old_active = new_active.get(pad_config.group)
            new_active[pad_config.group] = pad_id
            
            # Update runtime states
            from .model import PadRuntimeState
            new_runtime = dict(state.pad_runtime)
            
            if old_active:
                old_key = f"{old_active.x},{old_active.y}"
                new_runtime[old_key] = PadRuntimeState(is_active=False)
            
            key = f"{pad_id.x},{pad_id.y}"
            new_runtime[key] = PadRuntimeState(is_active=True)
            
            new_state = replace(state, active_by_group=new_active, pad_runtime=new_runtime)
            return new_state, effects
    
    return state, effects


def handle_pad_release(state: AppState, pad_id: PadId) -> Tuple[AppState, List[Effect]]:
    """Handle pad release (for PUSH mode)."""
    if not state.config or state.learn.phase != LearnPhase.IDLE:
        return state, []
    
    pad_config = state.config.get_pad(pad_id)
    if not pad_config or pad_config.mode != PadMode.PUSH:
        return state, []
    
    # Send 0.0 on release
    cmd = OscCommand(pad_config.osc_command.address, [0.0])
    return state, [SendOscEffect(cmd)]
