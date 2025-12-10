"""
Pad Mapping Engine

Handles button behaviors:
- SELECTOR: Radio button behavior within groups
- TOGGLE: On/off with two states
- ONE_SHOT: Single trigger, no persistent state

Bridges between Launchpad events, OSC communication, and LED feedback.
"""

import logging
from dataclasses import dataclass, field
from typing import Dict, Optional, List, Callable, Any

from .button_id import ButtonId
try:
    from lpminimk3 import LaunchpadMiniMk3 as LaunchpadDevice
except ImportError:
    LaunchpadDevice = None

# Color constant
LP_OFF = 0
from .osc_client import OscClient, OscEvent
from .model import PadMode, ButtonGroupType, OscCommand, PadBehavior, PadRuntimeState
from .synesthesia_config import (
    is_controllable,
    categorize_address,
    OscAddressCategory,
    BEAT_ADDRESS,
)

# Import SynesthesiaOscManager for type checking only
from typing import TYPE_CHECKING
if TYPE_CHECKING:
    from .synesthesia_osc import SynesthesiaOscManager

logger = logging.getLogger(__name__)


# =============================================================================
# EFFECTS (Side effects to be executed)
# =============================================================================

@dataclass(frozen=True)
class SendOscEffect:
    """Effect: Send an OSC command."""
    address: str
    args: List[Any] = field(default_factory=list)


@dataclass(frozen=True)
class SetLedEffect:
    """Effect: Set a Launchpad LED."""
    pad_id: ButtonId
    color: int
    blink: bool = False


# =============================================================================
# PAD MAPPER STATE
# =============================================================================

@dataclass
class PadMapperState:
    """
    Mutable state for the pad mapper.
    
    Attributes:
        pads: Configured pad behaviors
        runtime: Runtime state for each pad
        active_by_group: Currently active pad for each selector group
        beat_pulse: Current beat state (for LED blinking)
    """
    pads: Dict[ButtonId, PadBehavior] = field(default_factory=dict)
    runtime: Dict[ButtonId, PadRuntimeState] = field(default_factory=dict)
    active_by_group: Dict[ButtonGroupType, Optional[ButtonId]] = field(default_factory=dict)
    beat_pulse: bool = False


# =============================================================================
# PAD MAPPER
# =============================================================================

class PadMapper:
    """
    Mapping engine connecting Launchpad pads to OSC commands.
    
    Responsibilities:
    - Handle pad press events
    - Manage button behaviors (selector/toggle/one-shot)
    - Update LED states
    - Send/receive OSC messages
    - Sync state from incoming OSC
    """
    
    def __init__(
        self,
        launchpad: Optional[LaunchpadDevice] = None,
        osc: Optional[OscClient] = None,
        osc_manager: Optional["SynesthesiaOscManager"] = None,
    ):
        """
        Initialize PadMapper.
        
        Args:
            launchpad: LaunchpadDevice for LED control
            osc: Low-level OscClient (deprecated, use osc_manager)
            osc_manager: SynesthesiaOscManager for OSC communication
        """
        self.launchpad = launchpad
        self.osc = osc
        self._osc_manager: Optional["SynesthesiaOscManager"] = osc_manager
        self.state = PadMapperState()
        self._on_state_change: Optional[Callable[[PadMapperState], None]] = None
        
        # If osc_manager provided, register as listener
        if self._osc_manager:
            self._osc_manager.add_all_listener(self.handle_osc_event)
    
    def set_state_callback(self, callback: Callable[[PadMapperState], None]):
        """Set callback for state changes (for UI updates)."""
        self._on_state_change = callback
    
    # =========================================================================
    # PAD CONFIGURATION
    # =========================================================================
    
    def add_pad(self, behavior: PadBehavior):
        """
        Add or update a pad configuration.
        
        Args:
            behavior: Pad behavior configuration
        """
        self.state.pads[behavior.pad_id] = behavior
        
        # Initialize runtime state
        self.state.runtime[behavior.pad_id] = PadRuntimeState(
            is_active=False,
            is_on=False,
            current_color=behavior.idle_color,
            blink_enabled=False,
        )
        
        # Set initial LED
        self._apply_led(behavior.pad_id, behavior.idle_color)
        
        logger.debug(f"Added pad {behavior.pad_id}: {behavior.mode.name} -> {behavior.osc_action or behavior.osc_on}")
    
    def remove_pad(self, pad_id: ButtonId):
        """Remove a pad configuration."""
        if pad_id in self.state.pads:
            del self.state.pads[pad_id]
        if pad_id in self.state.runtime:
            del self.state.runtime[pad_id]
        self._apply_led(pad_id, LP_OFF)
    
    def clear_all_pads(self):
        """Remove all pad configurations."""
        self.state.pads.clear()
        self.state.runtime.clear()
        self.state.active_by_group.clear()
        if self.launchpad:
            self.launchpad.clear_all_leds()
    
    # =========================================================================
    # PAD PRESS HANDLING
    # =========================================================================
    
    def handle_pad_press(self, pad_id: ButtonId, velocity: int = 127):
        """
        Handle a pad press event.
        
        Dispatches to appropriate handler based on pad mode.
        
        Args:
            pad_id: Pressed pad
            velocity: MIDI velocity (unused, but available for pressure sensitivity)
        """
        if pad_id not in self.state.pads:
            logger.debug(f"Unmapped pad pressed: {pad_id}")
            return
        
        behavior = self.state.pads[pad_id]
        
        if behavior.mode == PadMode.SELECTOR:
            self._handle_selector_press(pad_id, behavior)
        elif behavior.mode == PadMode.TOGGLE:
            self._handle_toggle_press(pad_id, behavior)
        elif behavior.mode == PadMode.ONE_SHOT:
            self._handle_oneshot_press(pad_id, behavior)
        
        self._notify_state_change()
    
    def _handle_selector_press(self, pad_id: ButtonId, behavior: PadBehavior):
        """Handle SELECTOR pad press - radio button behavior."""
        group = behavior.group
        if group is None:
            return
        
        # Deactivate previous active pad in this group
        previous = self.state.active_by_group.get(group)
        if previous and previous in self.state.pads:
            prev_behavior = self.state.pads[previous]
            self.state.runtime[previous] = PadRuntimeState(
                is_active=False,
                current_color=prev_behavior.idle_color,
                blink_enabled=False,
            )
            self._apply_led(previous, prev_behavior.idle_color)
        
        # Activate this pad
        self.state.runtime[pad_id] = PadRuntimeState(
            is_active=True,
            current_color=behavior.active_color,
            blink_enabled=True,  # Active selectors blink with beat
        )
        self.state.active_by_group[group] = pad_id
        self._apply_led(pad_id, behavior.active_color)
        
        # Send OSC
        if behavior.osc_action:
            self._send_osc(behavior.osc_action)
        
        logger.debug(f"Selector {group.value}: {behavior.label or pad_id}")
    
    def _handle_toggle_press(self, pad_id: ButtonId, behavior: PadBehavior):
        """Handle TOGGLE pad press - flip on/off state."""
        current = self.state.runtime.get(pad_id, PadRuntimeState())
        new_is_on = not current.is_on
        
        # Update runtime
        new_color = behavior.active_color if new_is_on else behavior.idle_color
        self.state.runtime[pad_id] = PadRuntimeState(
            is_active=new_is_on,
            is_on=new_is_on,
            current_color=new_color,
            blink_enabled=False,  # Toggles don't blink
        )
        self._apply_led(pad_id, new_color)
        
        # Send OSC
        osc_cmd = behavior.osc_on if new_is_on else behavior.osc_off
        if osc_cmd:
            self._send_osc(osc_cmd)
        
        logger.debug(f"Toggle {behavior.label or pad_id}: {'ON' if new_is_on else 'OFF'}")
    
    def _handle_oneshot_press(self, pad_id: ButtonId, behavior: PadBehavior):
        """Handle ONE_SHOT pad press - trigger once, no persistent state."""
        # Flash the pad briefly (will reset on next beat or manually)
        self.state.runtime[pad_id] = PadRuntimeState(
            is_active=False,
            current_color=behavior.active_color,
            blink_enabled=False,
        )
        self._apply_led(pad_id, behavior.active_color)
        
        # Send OSC
        if behavior.osc_action:
            self._send_osc(behavior.osc_action)
        
        logger.debug(f"One-shot: {behavior.label or pad_id}")
        
        # Reset to idle color after brief flash (could use async delay)
        # For now, let beat sync or next event reset it
    
    # =========================================================================
    # OSC EVENT HANDLING
    # =========================================================================
    
    def handle_osc_event(self, event: OscEvent):
        """
        Handle incoming OSC event.
        
        Updates internal state and LED feedback based on OSC messages.
        
        Args:
            event: Received OSC event
        """
        address = event.address
        args = event.args
        
        # Handle beat for LED blinking
        if address == BEAT_ADDRESS:
            self.state.beat_pulse = bool(args[0]) if args else False
            self._update_blinking_leds()
            return
        
        # Handle controllable messages - sync state from external changes
        if is_controllable(address):
            category = categorize_address(address)
            
            if category == OscAddressCategory.SCENE:
                self._sync_selector_from_osc(address, ButtonGroupType.SCENES)
            elif category in (OscAddressCategory.PRESET, OscAddressCategory.FAVSLOT):
                self._sync_selector_from_osc(address, ButtonGroupType.PRESETS)
            elif category == OscAddressCategory.META_CONTROL:
                if "/hue" in address:
                    self._sync_selector_from_osc(address, ButtonGroupType.COLORS)
            # Toggle sync could be added here if Synesthesia sends toggle state
        
        self._notify_state_change()
    
    def _sync_selector_from_osc(self, address: str, group: ButtonGroupType):
        """Sync selector state when OSC message received from external source."""
        # Find matching pad
        matching_pad = None
        for pad_id, behavior in self.state.pads.items():
            if (behavior.mode == PadMode.SELECTOR and 
                behavior.group == group and
                behavior.osc_action and
                behavior.osc_action.address == address):
                matching_pad = pad_id
                break
        
        if not matching_pad:
            return
        
        # Deactivate previous
        previous = self.state.active_by_group.get(group)
        if previous and previous in self.state.pads and previous != matching_pad:
            prev_behavior = self.state.pads[previous]
            self.state.runtime[previous] = PadRuntimeState(
                is_active=False,
                current_color=prev_behavior.idle_color,
                blink_enabled=False,
            )
            self._apply_led(previous, prev_behavior.idle_color)
        
        # Activate matching pad
        behavior = self.state.pads[matching_pad]
        self.state.runtime[matching_pad] = PadRuntimeState(
            is_active=True,
            current_color=behavior.active_color,
            blink_enabled=True,
        )
        self.state.active_by_group[group] = matching_pad
        self._apply_led(matching_pad, behavior.active_color)
        
        logger.debug(f"Synced {group.value} from OSC: {behavior.label or matching_pad}")
    
    # =========================================================================
    # LED MANAGEMENT
    # =========================================================================
    
    def _apply_led(self, pad_id: ButtonId, color: int, blink: bool = False):
        """Apply LED color to Launchpad."""
        if self.launchpad:
            self.launchpad.set_led(pad_id, color, blink)
    
    def _update_blinking_leds(self):
        """Update all LEDs that should blink with beat."""
        for pad_id, runtime in self.state.runtime.items():
            if runtime.blink_enabled:
                behavior = self.state.pads.get(pad_id)
                if behavior:
                    # Blink between active and dim color on beat
                    if self.state.beat_pulse:
                        self._apply_led(pad_id, behavior.active_color)
                    else:
                        # Dim version (could calculate dim color)
                        self._apply_led(pad_id, behavior.active_color)
    
    def refresh_all_leds(self):
        """Refresh all LEDs based on current state."""
        for pad_id, behavior in self.state.pads.items():
            runtime = self.state.runtime.get(pad_id, PadRuntimeState())
            self._apply_led(pad_id, runtime.current_color)
    
    # =========================================================================
    # OSC SENDING
    # =========================================================================
    
    def _send_osc(self, command: OscCommand):
        """Send OSC command."""
        # Prefer SynesthesiaOscManager if available
        if self._osc_manager:
            self._osc_manager.send(command)
        elif self.osc:
            self.osc.send(command.address, command.args)
    
    # =========================================================================
    # STATE NOTIFICATION
    # =========================================================================
    
    def _notify_state_change(self):
        """Notify listener of state change."""
        if self._on_state_change:
            self._on_state_change(self.state)
    
    # =========================================================================
    # QUICK CONFIG HELPERS
    # =========================================================================
    
    def add_selector(
        self,
        pad_id: ButtonId,
        osc_address: str,
        group: ButtonGroupType,
        label: str = "",
        idle_color: int = 0,
        active_color: int = 5,
        args: Optional[List[Any]] = None,
    ):
        """
        Quick helper to add a SELECTOR pad.
        
        Args:
            pad_id: Pad position
            osc_address: OSC address to send
            group: Button group for radio behavior
            label: Human-readable label
            idle_color: LED color when inactive
            active_color: LED color when active
            args: Optional OSC arguments
        """
        self.add_pad(PadBehavior(
            pad_id=pad_id,
            mode=PadMode.SELECTOR,
            group=group,
            idle_color=idle_color,
            active_color=active_color,
            label=label,
            osc_action=OscCommand(osc_address, args or []),
        ))
    
    def add_toggle(
        self,
        pad_id: ButtonId,
        osc_on_address: str,
        osc_off_address: Optional[str] = None,
        label: str = "",
        idle_color: int = 0,
        active_color: int = 5,
        on_args: Optional[List[Any]] = None,
        off_args: Optional[List[Any]] = None,
    ):
        """
        Quick helper to add a TOGGLE pad.
        
        Args:
            pad_id: Pad position
            osc_on_address: OSC address for ON state
            osc_off_address: OSC address for OFF state (if different)
            label: Human-readable label
            idle_color: LED color when OFF
            active_color: LED color when ON
            on_args: OSC arguments for ON
            off_args: OSC arguments for OFF
        """
        self.add_pad(PadBehavior(
            pad_id=pad_id,
            mode=PadMode.TOGGLE,
            idle_color=idle_color,
            active_color=active_color,
            label=label,
            osc_on=OscCommand(osc_on_address, on_args or [1]),
            osc_off=OscCommand(osc_off_address or osc_on_address, off_args or [0]) if osc_off_address or off_args else None,
        ))
    
    def add_oneshot(
        self,
        pad_id: ButtonId,
        osc_address: str,
        label: str = "",
        idle_color: int = 0,
        active_color: int = 5,
        args: Optional[List[Any]] = None,
    ):
        """
        Quick helper to add a ONE_SHOT pad.
        
        Args:
            pad_id: Pad position
            osc_address: OSC address to send
            label: Human-readable label
            idle_color: LED color when idle
            active_color: LED color on press (flash)
            args: OSC arguments
        """
        self.add_pad(PadBehavior(
            pad_id=pad_id,
            mode=PadMode.ONE_SHOT,
            idle_color=idle_color,
            active_color=active_color,
            label=label,
            osc_action=OscCommand(osc_address, args or []),
        ))
