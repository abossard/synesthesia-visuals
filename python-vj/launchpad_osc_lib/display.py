"""
LED Display Renderer

Pure functions that render application state to LED effects.
No side effects - just converts state to a list of LedEffect.
"""

from typing import List

from .button_id import ButtonId
from .model import (
    ControllerState, LearnState, LearnPhase, LearnRegister,
    LedEffect, PadMode,
    LP_OFF, LP_RED, LP_RED_DIM, LP_ORANGE, LP_YELLOW, LP_GREEN,
    LP_GREEN_DIM, LP_CYAN, LP_BLUE, LP_BLUE_DIM, LP_PURPLE, LP_WHITE,
    BrightnessLevel, BASE_COLOR_NAMES, get_color_at_brightness,
)


# =============================================================================
# SPECIAL BUTTON POSITIONS
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
# RENDER FUNCTIONS
# =============================================================================

def render_idle(state: ControllerState) -> List[LedEffect]:
    """Render normal operation state (show configured pad colors)."""
    effects = []
    
    for pad_id, behavior in state.pads.items():
        runtime = state.pad_runtime.get(pad_id)
        if runtime and runtime.is_active:
            color = behavior.active_color
        else:
            color = behavior.idle_color
        effects.append(LedEffect(pad_id=pad_id, color=color))
    
    # Learn button always green (available)
    effects.append(LedEffect(pad_id=LEARN_BUTTON, color=LP_GREEN_DIM))
    
    return effects


def render_learn_wait_pad(state: ControllerState) -> List[LedEffect]:
    """
    Render 'waiting for pad selection' phase.
    
    - Unconfigured pads pulse red (available for recording)
    - Configured pads show their idle color (already assigned)
    - Scene buttons show learn active
    """
    effects = []
    
    # 8x8 grid pads
    for y in range(8):
        for x in range(8):
            pad_id = ButtonId(x, y)
            behavior = state.pads.get(pad_id)
            
            if behavior:
                effects.append(LedEffect(pad_id=pad_id, color=behavior.idle_color, blink=False))
            else:
                effects.append(LedEffect(pad_id=pad_id, color=LP_RED, blink=True))
    
    # Learn button shows we're in learn mode
    effects.append(LedEffect(pad_id=LEARN_BUTTON, color=LP_ORANGE))
    
    # Cancel button
    effects.append(LedEffect(pad_id=ButtonId(8, 7), color=LP_RED))  # Top scene = cancel
    
    return effects


def render_learn_record_osc(state: ControllerState) -> List[LedEffect]:
    """
    Render 'recording OSC' phase.
    
    Selected pad blinks, shows event count, save/cancel buttons visible.
    """
    effects = []
    learn = state.learn_state
    
    # Clear all grid pads
    for y in range(8):
        for x in range(8):
            effects.append(LedEffect(pad_id=ButtonId(x, y), color=LP_OFF))
    
    # Selected pad pulses orange
    if learn.selected_pad:
        effects.append(LedEffect(pad_id=learn.selected_pad, color=LP_ORANGE, blink=True))
    
    # Learn button shows recording (also acts as cancel)
    effects.append(LedEffect(pad_id=LEARN_BUTTON, color=LP_ORANGE))
    
    # Show number of unique recorded events on scene buttons (cols 1-6)
    unique_addresses = set(e.address for e in learn.recorded_events)
    num_unique = len(unique_addresses)
    for i in range(min(num_unique, 6)):
        effects.append(LedEffect(pad_id=ButtonId(8, i + 1), color=LP_CYAN))
    
    # Save button (green) - only show if we have recorded events
    if learn.recorded_events:
        effects.append(LedEffect(pad_id=SAVE_PAD, color=LP_GREEN))
    
    # Cancel button (red) - always visible
    effects.append(LedEffect(pad_id=CANCEL_PAD, color=LP_RED))
    
    return effects


def render_learn_config(state: ControllerState) -> List[LedEffect]:
    """
    Render configuration phase.
    
    Layout:
    - Top row (y=7): 3 register buttons (OSC, Mode, Color), pagination
    - Rows 1-6: Content based on active register
    - Row 0: Save (green), Test (blue), Cancel (red)
    """
    effects = []
    learn = state.learn_state
    
    # Clear all first
    for y in range(8):
        for x in range(8):
            effects.append(LedEffect(pad_id=ButtonId(x, y), color=LP_OFF))
    
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
    page_start = learn.osc_page * 8
    commands = learn.candidate_commands[page_start:page_start + 8]
    
    for i, cmd in enumerate(commands):
        is_selected = (page_start + i) == learn.selected_osc_index
        color = LP_WHITE if is_selected else LP_CYAN
        effects.append(LedEffect(pad_id=ButtonId(i, 3), color=color))
    
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
        effects.append(LedEffect(pad_id=ButtonId(x, 3), color=color))
    
    return effects


def _render_color_select(learn: LearnState) -> List[LedEffect]:
    """
    Render color selection with brightness controls.
    
    Layout:
    - Row 6: Preview of selected idle (col 1) and active (col 5) colors
    - Rows 2-5: 4x4 color grid for idle (cols 0-3) and active (cols 4-7)
    - Row 1: Brightness controls
    """
    effects = []
    base_colors_to_show = BASE_COLOR_NAMES[:10]
    
    # Left 4x4 area: Idle color selection
    for i, color_name in enumerate(base_colors_to_show[:8]):
        x = i % 4
        y = 2 + (i // 4)
        color_vel = get_color_at_brightness(color_name, learn.idle_brightness)
        is_selected = color_vel == learn.selected_idle_color
        effects.append(LedEffect(pad_id=ButtonId(x, y), color=LP_WHITE if is_selected else color_vel))
    
    # Remaining 2 colors on row 4 (cols 0-1)
    for i, color_name in enumerate(base_colors_to_show[8:10]):
        x = i
        y = 4
        color_vel = get_color_at_brightness(color_name, learn.idle_brightness)
        is_selected = color_vel == learn.selected_idle_color
        effects.append(LedEffect(pad_id=ButtonId(x, y), color=LP_WHITE if is_selected else color_vel))
    
    # Right 4x4 area: Active color selection
    for i, color_name in enumerate(base_colors_to_show[:8]):
        x = 4 + (i % 4)
        y = 2 + (i // 4)
        color_vel = get_color_at_brightness(color_name, learn.active_brightness)
        is_selected = color_vel == learn.selected_active_color
        effects.append(LedEffect(pad_id=ButtonId(x, y), color=LP_WHITE if is_selected else color_vel))
    
    # Remaining 2 colors on row 4 (cols 6-7)
    for i, color_name in enumerate(base_colors_to_show[8:10]):
        x = 6 + i
        y = 4
        color_vel = get_color_at_brightness(color_name, learn.active_brightness)
        is_selected = color_vel == learn.selected_active_color
        effects.append(LedEffect(pad_id=ButtonId(x, y), color=LP_WHITE if is_selected else color_vel))
    
    # Preview labels (row 6)
    effects.append(LedEffect(pad_id=ButtonId(1, 6), color=learn.selected_idle_color))
    effects.append(LedEffect(pad_id=ButtonId(5, 6), color=learn.selected_active_color))
    
    # Row 5: Brightness level indicator
    for level in BrightnessLevel:
        x = level.value
        is_current = learn.idle_brightness == level
        effects.append(LedEffect(pad_id=ButtonId(x, 5), color=LP_GREEN if is_current else LP_GREEN_DIM))
    
    for level in BrightnessLevel:
        x = 5 + level.value
        is_current = learn.active_brightness == level
        effects.append(LedEffect(pad_id=ButtonId(x, 5), color=LP_GREEN if is_current else LP_GREEN_DIM))
    
    # Row 1: Brightness adjustment buttons
    can_decrease_idle = learn.idle_brightness.value > BrightnessLevel.DIM.value
    can_increase_idle = learn.idle_brightness.value < BrightnessLevel.BRIGHT.value
    effects.append(LedEffect(pad_id=IDLE_BRIGHTNESS_DOWN, color=LP_BLUE if can_decrease_idle else LP_BLUE_DIM))
    effects.append(LedEffect(pad_id=IDLE_BRIGHTNESS_UP, color=LP_BLUE if can_increase_idle else LP_BLUE_DIM))
    
    can_decrease_active = learn.active_brightness.value > BrightnessLevel.DIM.value
    can_increase_active = learn.active_brightness.value < BrightnessLevel.BRIGHT.value
    effects.append(LedEffect(pad_id=ACTIVE_BRIGHTNESS_DOWN, color=LP_BLUE if can_decrease_active else LP_BLUE_DIM))
    effects.append(LedEffect(pad_id=ACTIVE_BRIGHTNESS_UP, color=LP_BLUE if can_increase_active else LP_BLUE_DIM))
    
    return effects


def render_state(state: ControllerState) -> List[LedEffect]:
    """
    Main render dispatch - renders current state to LED effects.
    
    Pure function: state in, effects out.
    """
    phase = state.learn_state.phase
    
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
