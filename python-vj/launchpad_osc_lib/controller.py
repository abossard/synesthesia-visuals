"""
Launchpad Controller

High-level controller that orchestrates:
- Bank management (top row switching)
- FSM state transitions (pad behavior)
- OSC communication
- LED updates

This module provides the core control logic without lpminimk3 dependency.
The actual hardware connection is handled by the application layer.
"""

from __future__ import annotations

import json
import logging
from dataclasses import replace
from pathlib import Path
from typing import Any, Callable, Dict, List, Optional, Protocol

from .button_id import ButtonId
from .banks import create_default_banks
from .model import (
    ControllerState, LearnPhase,
    PadBehavior, OscCommand, OscEvent,
    Effect, SendOscEffect, LedEffect, SaveConfigEffect, LogEffect,
    ButtonGroupType, PadMode,
)
from .fsm import (
    handle_pad_press,
    handle_pad_release,
    handle_osc_event,
    record_osc_event,
    is_in_config_phase,
)
from .display import render_state

logger = logging.getLogger(__name__)


# =============================================================================
# PROTOCOL FOR HARDWARE ABSTRACTION
# =============================================================================

class LaunchpadInterface(Protocol):
    """Protocol for Launchpad hardware abstraction."""
    
    def set_led(self, x: int, y: int, color: int, blink: bool = False) -> None:
        """Set LED color at grid position."""
        ...
    
    def set_panel_led(self, index: int, color: int, blink: bool = False) -> None:
        """Set LED on panel button (top row or scene)."""
        ...
    
    def clear_all(self) -> None:
        """Clear all LEDs."""
        ...


class OscInterface(Protocol):
    """Protocol for OSC communication abstraction."""
    
    def send(self, address: str, *args: Any) -> None:
        """Send OSC message."""
        ...


# =============================================================================
# CONTROLLER
# =============================================================================

class LaunchpadController:
    """
    High-level Launchpad controller with bank switching and OSC.
    
    This class manages the application state and FSM, but delegates
    actual hardware and OSC I/O to injected interfaces.
    
    Features:
    - Bank-aware: Top row switches between configuration banks
    - OSC integration via interface: Sends/receives OSC
    - Learn mode: Record OSC to configure pads
    - Bank switching blocked during CONFIG phase
    
    Usage:
        controller = LaunchpadController(config_path="my_config.json")
        controller.set_launchpad(my_launchpad_adapter)
        controller.set_osc(my_osc_adapter)
        
        # Feed button events from your hardware layer
        controller.on_button_press(ButtonId(0, 0))
        controller.on_button_release(ButtonId(0, 0))
        
        # Feed OSC events from your OSC layer
        controller.on_osc_event(address, args)
    """
    
    def __init__(
        self,
        config_path: Optional[str | Path] = None,
        auto_save: bool = True,
    ):
        """
        Initialize controller.
        
        Args:
            config_path: Path to save/load configuration. If None, uses in-memory only.
            auto_save: Whether to automatically save config on changes
        """
        self.config_path = Path(config_path) if config_path else None
        self.auto_save = auto_save
        
        # State
        self.state = ControllerState()
        self.bank_manager = create_default_banks()
        
        # Hardware interfaces (injected)
        self._launchpad: Optional[LaunchpadInterface] = None
        self._osc: Optional[OscInterface] = None
        
        # Callbacks
        self._on_state_change: Optional[Callable[[ControllerState], None]] = None
        self._on_log: Optional[Callable[[str], None]] = None
        
        # Wire up bank manager callbacks
        self.bank_manager.set_led_update_callback(self._on_bank_led_update)
        self.bank_manager.set_config_phase_checker(self._is_in_config_phase)
        
        # Load config if exists
        if self.config_path and self.config_path.exists():
            self._load_config()
    
    # =========================================================================
    # INTERFACE INJECTION
    # =========================================================================
    
    def set_launchpad(self, launchpad: LaunchpadInterface) -> None:
        """Set Launchpad hardware interface."""
        self._launchpad = launchpad
    
    def set_osc(self, osc: OscInterface) -> None:
        """Set OSC communication interface."""
        self._osc = osc
    
    # =========================================================================
    # EVENT HANDLERS (called by application layer)
    # =========================================================================
    
    def on_button_press(self, pad_id: ButtonId) -> None:
        """Handle pad press from hardware."""
        # Check if top row (bank switching)
        if pad_id.is_top_row():
            if self.bank_manager.handle_top_row_press(pad_id):
                return
        
        # Handle via FSM
        new_state, effects = handle_pad_press(self.state, pad_id)
        self._apply_state_and_effects(new_state, effects)
    
    def on_button_release(self, pad_id: ButtonId) -> None:
        """Handle pad release from hardware (for PUSH mode)."""
        new_state, effects = handle_pad_release(self.state, pad_id)
        self._apply_state_and_effects(new_state, effects)
    
    def on_osc_event(self, address: str, args: List[Any]) -> None:
        """Handle incoming OSC message."""
        import time
        event = OscEvent(address=address, args=args, timestamp=time.time())
        
        # Record if in recording phase
        if self.state.learn_state.phase == LearnPhase.RECORD_OSC:
            new_state, effects = record_osc_event(self.state, event)
            self._apply_state_and_effects(new_state, effects)
        else:
            # Normal OSC handling
            new_state, effects = handle_osc_event(self.state, event)
            self._apply_state_and_effects(new_state, effects)
    
    # =========================================================================
    # STATE MANAGEMENT
    # =========================================================================
    
    def _apply_state_and_effects(
        self,
        new_state: ControllerState,
        effects: List[Effect],
    ) -> None:
        """Apply new state and execute effects."""
        self.state = new_state
        
        for effect in effects:
            self._execute_effect(effect)
        
        # Notify state change callback
        if self._on_state_change:
            self._on_state_change(self.state)
    
    def _execute_effect(self, effect: Effect) -> None:
        """Execute a single effect."""
        if isinstance(effect, SendOscEffect):
            if self._osc:
                self._osc.send(effect.command.address, *effect.command.args)
        
        elif isinstance(effect, LedEffect):
            self._set_led(effect.pad_id, effect.color, effect.blink)
        
        elif isinstance(effect, SaveConfigEffect):
            if self.auto_save and self.config_path:
                self._save_config()
        
        elif isinstance(effect, LogEffect):
            logger.info(effect.message)
            if self._on_log:
                self._on_log(effect.message)
    
    def _is_in_config_phase(self) -> bool:
        """Check if currently in CONFIG phase (for bank manager)."""
        return is_in_config_phase(self.state)
    
    @property
    def is_config_phase(self) -> bool:
        """Public property to check if in CONFIG phase."""
        return self._is_in_config_phase()
    
    # =========================================================================
    # LED MANAGEMENT
    # =========================================================================
    
    def _set_led(self, pad_id: ButtonId, color: int, blink: bool = False) -> None:
        """Set LED color via interface."""
        if not self._launchpad:
            return
        
        if pad_id.is_top_row():
            # Top row: panel index 0-7
            self._launchpad.set_panel_led(pad_id.x, color, blink)
        elif pad_id.is_right_column():
            # Scene buttons: panel index 8+
            self._launchpad.set_panel_led(8 + pad_id.y, color, blink)
        else:
            # Grid buttons
            self._launchpad.set_led(pad_id.x, pad_id.y, color, blink)
    
    def _on_bank_led_update(self, pad_id: ButtonId, color: int, blink: bool) -> None:
        """Callback from bank manager for LED updates."""
        self._set_led(pad_id, color, blink)
    
    def refresh_all_leds(self) -> None:
        """Refresh all LEDs based on current state."""
        # Bank manager handles top row
        self.bank_manager.refresh_all_leds()
        
        # Render current state for grid
        effects = render_state(self.state)
        for effect in effects:
            if isinstance(effect, LedEffect):
                self._set_led(effect.pad_id, effect.color, effect.blink)
    
    # =========================================================================
    # PERSISTENCE
    # =========================================================================
    
    def _save_config(self) -> None:
        """Save configuration to file."""
        if not self.config_path:
            return
        
        try:
            data = {
                "version": 2,
                "pads": {
                    f"{pad_id.x},{pad_id.y}": self._behavior_to_dict(behavior)
                    for pad_id, behavior in self.state.pads.items()
                },
            }
            
            with open(self.config_path, 'w') as f:
                json.dump(data, f, indent=2)
            
            logger.info(f"Saved config to {self.config_path}")
        except Exception as e:
            logger.error(f"Failed to save config: {e}")
    
    def _load_config(self) -> None:
        """Load configuration from file."""
        if not self.config_path or not self.config_path.exists():
            return
        
        try:
            with open(self.config_path, 'r') as f:
                data = json.load(f)
            
            pads: Dict[ButtonId, PadBehavior] = {}
            for key, behavior_data in data.get("pads", {}).items():
                x, y = map(int, key.split(","))
                pad_id = ButtonId(x, y)
                pads[pad_id] = self._dict_to_behavior(pad_id, behavior_data)
            
            self.state = replace(self.state, pads=pads)
            
            logger.info(f"Loaded {len(pads)} pads from {self.config_path}")
        except Exception as e:
            logger.error(f"Failed to load config: {e}")
    
    def _behavior_to_dict(self, behavior: PadBehavior) -> Dict[str, Any]:
        """Convert PadBehavior to dictionary."""
        data: Dict[str, Any] = {
            "mode": behavior.mode.value,
            "idle_color": behavior.idle_color,
            "active_color": behavior.active_color,
            "label": behavior.label,
        }
        
        if behavior.group:
            data["group"] = behavior.group.value
        
        if behavior.osc_action:
            data["osc_action"] = {
                "address": behavior.osc_action.address,
                "args": list(behavior.osc_action.args),
            }
        
        if behavior.osc_on:
            data["osc_on"] = {
                "address": behavior.osc_on.address,
                "args": list(behavior.osc_on.args),
            }
        
        if behavior.osc_off:
            data["osc_off"] = {
                "address": behavior.osc_off.address,
                "args": list(behavior.osc_off.args),
            }
        
        return data
    
    def _dict_to_behavior(self, pad_id: ButtonId, data: Dict[str, Any]) -> PadBehavior:
        """Convert dictionary to PadBehavior."""
        mode = PadMode(data.get("mode", "one_shot"))
        
        group = None
        if "group" in data:
            try:
                group = ButtonGroupType(data["group"])
            except ValueError:
                pass
        
        osc_action = None
        if "osc_action" in data:
            osc_action = OscCommand(
                address=data["osc_action"]["address"],
                args=list(data["osc_action"].get("args", [])),
            )
        
        osc_on = None
        if "osc_on" in data:
            osc_on = OscCommand(
                address=data["osc_on"]["address"],
                args=list(data["osc_on"].get("args", [])),
            )
        
        osc_off = None
        if "osc_off" in data:
            osc_off = OscCommand(
                address=data["osc_off"]["address"],
                args=list(data["osc_off"].get("args", [])),
            )
        
        return PadBehavior(
            pad_id=pad_id,
            mode=mode,
            group=group,
            idle_color=data.get("idle_color", 0),
            active_color=data.get("active_color", 5),
            label=data.get("label", ""),
            osc_action=osc_action,
            osc_on=osc_on,
            osc_off=osc_off,
        )
    
    # =========================================================================
    # CALLBACKS
    # =========================================================================
    
    def set_state_change_callback(
        self,
        callback: Callable[[ControllerState], None],
    ) -> None:
        """Set callback for state changes."""
        self._on_state_change = callback
    
    def set_log_callback(self, callback: Callable[[str], None]) -> None:
        """Set callback for log messages."""
        self._on_log = callback
