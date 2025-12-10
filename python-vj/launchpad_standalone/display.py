"""
LED Display Renderer

Pure functions that render application state to LED effects.
No side effects - just converts state to a list of LedEffect.
"""

from typing import List
from .model import (
    AppState, LearnState, LearnPhase, LearnRegister, PadId,
    LedEffect, PadMode,
    LP_OFF, LP_RED, LP_RED_DIM, LP_ORANGE, LP_YELLOW, LP_GREEN,
    LP_GREEN_DIM, LP_CYAN, LP_BLUE, LP_PURPLE, LP_PINK, LP_WHITE,
    COLOR_PREVIEW_PALETTE,
)


# =============================================================================
# SPECIAL BUTTON POSITIONS
# =============================================================================

# Scene buttons (right column, x=8)
LEARN_BUTTON = PadId(8, 0)  # Bottom-right scene button

# Bottom row: Save (green), Test (blue), Cancel (red)
SAVE_PAD = PadId(0, 0)
TEST_PAD = PadId(1, 0)
CANCEL_PAD = PadId(7, 0)

# Top row (y=7): Register selection (3 yellow pads)
REGISTER_OSC_PAD = PadId(0, 7)
REGISTER_MODE_PAD = PadId(1, 7)
REGISTER_COLOR_PAD = PadId(2, 7)

# OSC pagination (in top row)
OSC_PAGE_PREV = PadId(6, 7)
OSC_PAGE_NEXT = PadId(7, 7)


# =============================================================================
# RENDER FUNCTIONS
# =============================================================================

def render_idle(state: AppState) -> List[LedEffect]:
    """Render normal operation state (show configured pad colors)."""
    effects = []
    
    if state.config:
        for key, pad_config in state.config.pads.items():
            runtime = state.pad_runtime.get(key)
            if runtime and runtime.is_active:
                color = pad_config.active_color
            else:
                color = pad_config.idle_color
            
            effects.append(LedEffect(pad_id=pad_config.pad_id, color=color))
    
    # Learn button always green (available)
    effects.append(LedEffect(pad_id=LEARN_BUTTON, color=LP_GREEN_DIM))
    
    return effects


def render_learn_wait_pad(state: AppState) -> List[LedEffect]:
    """
    Render 'waiting for pad selection' phase.
    
    All grid pads blink red, scene buttons show learn active.
    """
    effects = []
    blink_color = LP_RED if state.blink_on else LP_RED_DIM
    
    # All 8x8 grid pads blink
    for y in range(8):
        for x in range(8):
            effects.append(LedEffect(pad_id=PadId(x, y), color=blink_color))
    
    # Learn button shows we're in learn mode
    effects.append(LedEffect(pad_id=LEARN_BUTTON, color=LP_ORANGE))
    
    # Cancel button
    effects.append(LedEffect(pad_id=PadId(8, 7), color=LP_RED))  # Top scene = cancel
    
    return effects


def render_learn_record_osc(state: AppState) -> List[LedEffect]:
    """
    Render 'recording OSC' phase.
    
    Selected pad blinks, others off, status shown.
    """
    effects = []
    learn = state.learn
    
    # Clear all grid pads
    for y in range(8):
        for x in range(8):
            effects.append(LedEffect(pad_id=PadId(x, y), color=LP_OFF))
    
    # Selected pad blinks orange
    if learn.selected_pad:
        color = LP_ORANGE if state.blink_on else LP_YELLOW
        effects.append(LedEffect(pad_id=learn.selected_pad, color=color))
    
    # Learn button shows recording
    effects.append(LedEffect(pad_id=LEARN_BUTTON, color=LP_ORANGE))
    
    # Show number of recorded events on scene buttons
    num_events = len(learn.recorded_events)
    for i in range(min(num_events, 7)):
        effects.append(LedEffect(pad_id=PadId(8, i + 1), color=LP_CYAN))
    
    return effects


def render_learn_config(state: AppState) -> List[LedEffect]:
    """
    Render configuration phase.
    
    Layout:
    - Top row (y=7): 3 register buttons (OSC, Mode, Color), pagination
    - Rows 1-6: Content based on active register
    - Row 0: Save (green), Test (blue), Cancel (red)
    """
    effects = []
    learn = state.learn
    
    # Clear all first
    for y in range(8):
        for x in range(8):
            effects.append(LedEffect(pad_id=PadId(x, y), color=LP_OFF))
    
    # ---- Top row: Register selection ----
    reg_colors = {
        LearnRegister.OSC_SELECT: (REGISTER_OSC_PAD, LP_ORANGE if learn.active_register == LearnRegister.OSC_SELECT else LP_YELLOW),
        LearnRegister.MODE_SELECT: (REGISTER_MODE_PAD, LP_ORANGE if learn.active_register == LearnRegister.MODE_SELECT else LP_YELLOW),
        LearnRegister.COLOR_SELECT: (REGISTER_COLOR_PAD, LP_ORANGE if learn.active_register == LearnRegister.COLOR_SELECT else LP_YELLOW),
    }
    for reg, (pad, color) in reg_colors.items():
        effects.append(LedEffect(pad_id=pad, color=color))
    
    # ---- Content area based on register ----
    if learn.active_register == LearnRegister.OSC_SELECT:
        effects.extend(_render_osc_select(learn))
    elif learn.active_register == LearnRegister.MODE_SELECT:
        effects.extend(_render_mode_select(learn))
    elif learn.active_register == LearnRegister.COLOR_SELECT:
        effects.extend(_render_color_select(learn))
    
    # ---- Bottom row: Action buttons ----
    effects.append(LedEffect(pad_id=SAVE_PAD, color=LP_GREEN))
    effects.append(LedEffect(pad_id=TEST_PAD, color=LP_BLUE))
    effects.append(LedEffect(pad_id=CANCEL_PAD, color=LP_RED))
    
    # Learn button (can exit)
    effects.append(LedEffect(pad_id=LEARN_BUTTON, color=LP_RED_DIM))
    
    return effects


def _render_osc_select(learn: LearnState) -> List[LedEffect]:
    """Render OSC command selection (rows 1-6)."""
    effects = []
    
    # Show up to 8 commands (one per column, row 3)
    # Selected one is brighter
    page_start = learn.osc_page * 8
    commands = learn.candidate_commands[page_start:page_start + 8]
    
    for i, cmd in enumerate(commands):
        is_selected = (page_start + i) == learn.selected_osc_index
        color = LP_WHITE if is_selected else LP_CYAN
        effects.append(LedEffect(pad_id=PadId(i, 3), color=color))
    
    # Page indicators
    if learn.osc_page > 0:
        effects.append(LedEffect(pad_id=OSC_PAGE_PREV, color=LP_BLUE))
    if page_start + 8 < len(learn.candidate_commands):
        effects.append(LedEffect(pad_id=OSC_PAGE_NEXT, color=LP_BLUE))
    
    return effects


def _render_mode_select(learn: LearnState) -> List[LedEffect]:
    """Render mode selection (4 options in row 3)."""
    effects = []
    
    modes = [
        (PadMode.TOGGLE, 0, LP_PURPLE),
        (PadMode.PUSH, 1, LP_CYAN),
        (PadMode.ONE_SHOT, 2, LP_ORANGE),
        (PadMode.SELECTOR, 3, LP_GREEN),
    ]
    
    for mode, x, base_color in modes:
        is_selected = learn.selected_mode == mode
        color = LP_WHITE if is_selected else base_color
        effects.append(LedEffect(pad_id=PadId(x, 3), color=color))
    
    return effects


def _render_color_select(learn: LearnState) -> List[LedEffect]:
    """
    Render color selection.
    
    - 4x4 color grid (rows 2-5, cols 0-3) for idle color
    - 4x4 color grid (rows 2-5, cols 4-7) for active color
    - Selected colors highlighted
    """
    effects = []
    
    # Left 4x4: Idle color selection
    for i, color_vel in enumerate(COLOR_PREVIEW_PALETTE):
        x = i % 4
        y = 2 + (i // 4)
        is_selected = color_vel == learn.selected_idle_color
        # Show the color itself, with white ring if selected
        effects.append(LedEffect(pad_id=PadId(x, y), color=LP_WHITE if is_selected else color_vel))
    
    # Right 4x4: Active color selection
    for i, color_vel in enumerate(COLOR_PREVIEW_PALETTE):
        x = 4 + (i % 4)
        y = 2 + (i // 4)
        is_selected = color_vel == learn.selected_active_color
        effects.append(LedEffect(pad_id=PadId(x, y), color=LP_WHITE if is_selected else color_vel))
    
    # Preview labels (row 6)
    # "I" for idle on left, "A" for active on right
    effects.append(LedEffect(pad_id=PadId(1, 6), color=learn.selected_idle_color))
    effects.append(LedEffect(pad_id=PadId(5, 6), color=learn.selected_active_color))
    
    return effects


def render_state(state: AppState) -> List[LedEffect]:
    """
    Main render dispatch - renders current state to LED effects.
    
    Pure function: state in, effects out.
    """
    phase = state.learn.phase
    
    if phase == LearnPhase.IDLE:
        return render_idle(state)
    elif phase == LearnPhase.WAIT_PAD:
        return render_learn_wait_pad(state)
    elif phase == LearnPhase.RECORD_OSC:
        return render_learn_record_osc(state)
    elif phase == LearnPhase.CONFIG:
        return render_learn_config(state)
    else:
        return []
