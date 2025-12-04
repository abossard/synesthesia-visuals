#!/usr/bin/env python3
"""
MIDI Domain Models and Pure Functions

Pure calculations with no side effects - immutable data structures
and stateless functions following Grokking Simplicity principles.
"""

from dataclasses import dataclass, replace
from typing import Dict, Optional, Any, Literal, List, Tuple
from enum import IntEnum


# =============================================================================
# MIDI MESSAGE TYPES - Constants
# =============================================================================

class MidiMessageType(IntEnum):
    """MIDI message types."""
    NOTE_OFF = 0x80
    NOTE_ON = 0x90
    POLY_AFTERTOUCH = 0xA0
    CONTROL_CHANGE = 0xB0
    PROGRAM_CHANGE = 0xC0
    CHANNEL_AFTERTOUCH = 0xD0
    PITCH_BEND = 0xE0
    SYSTEM_EXCLUSIVE = 0xF0


# =============================================================================
# IMMUTABLE DATA STRUCTURES - Pure domain models
# =============================================================================

@dataclass(frozen=True)
class MidiMessage:
    """
    A single MIDI message. Immutable.
    
    message_type: Type of MIDI message (note on/off, CC, etc.)
    channel: MIDI channel (0-15)
    note_or_cc: Note number (0-127) or CC number (0-127)
    velocity_or_value: Velocity for notes (0-127) or value for CC (0-127)
    """
    message_type: int
    channel: int
    note_or_cc: int
    velocity_or_value: int
    
    @property
    def is_note_on(self) -> bool:
        """Check if message is note on with non-zero velocity."""
        return (self.message_type == MidiMessageType.NOTE_ON and 
                self.velocity_or_value > 0)
    
    @property
    def is_note_off(self) -> bool:
        """Check if message is note off or note on with zero velocity."""
        return (self.message_type == MidiMessageType.NOTE_OFF or 
                (self.message_type == MidiMessageType.NOTE_ON and 
                 self.velocity_or_value == 0))
    
    @property
    def is_control_change(self) -> bool:
        """Check if message is control change."""
        return self.message_type == MidiMessageType.CONTROL_CHANGE
    
    def __str__(self) -> str:
        """Human-readable representation."""
        msg_types = {
            MidiMessageType.NOTE_ON: "Note On",
            MidiMessageType.NOTE_OFF: "Note Off",
            MidiMessageType.CONTROL_CHANGE: "CC",
            MidiMessageType.PROGRAM_CHANGE: "Program Change",
            MidiMessageType.PITCH_BEND: "Pitch Bend",
        }
        type_str = msg_types.get(self.message_type, f"Type {self.message_type}")
        return f"{type_str} ch{self.channel} #{self.note_or_cc} val={self.velocity_or_value}"


@dataclass(frozen=True)
class ToggleConfig:
    """
    Configuration for a single toggle control. Immutable.
    
    note_or_cc: MIDI note or CC number
    name: Human-readable name for the toggle
    state: Current toggle state (True = ON, False = OFF)
    message_type: 'note' or 'cc'
    led_on_velocity: Velocity to send for ON LED state
    led_off_velocity: Velocity to send for OFF LED state
    output_on_velocity: Velocity to send to Magic for ON state
    output_off_velocity: Velocity to send to Magic for OFF state
    """
    note_or_cc: int
    name: str
    state: bool = False
    message_type: Literal['note', 'cc'] = 'note'
    led_on_velocity: int = 127
    led_off_velocity: int = 0
    output_on_velocity: int = 127
    output_off_velocity: int = 0
    
    def with_state(self, new_state: bool) -> 'ToggleConfig':
        """Create new instance with updated state."""
        return replace(self, state=new_state)
    
    def toggle(self) -> 'ToggleConfig':
        """Create new instance with flipped state."""
        return replace(self, state=not self.state)
    
    @property
    def key(self) -> str:
        """Unique identifier for this toggle."""
        return f"{self.message_type}_{self.note_or_cc}"
    
    @property
    def current_led_velocity(self) -> int:
        """Get LED velocity for current state."""
        return self.led_on_velocity if self.state else self.led_off_velocity
    
    @property
    def current_output_velocity(self) -> int:
        """Get output velocity for current state."""
        return self.output_on_velocity if self.state else self.output_off_velocity


@dataclass(frozen=True)
class DeviceConfig:
    """
    Configuration for a MIDI device. Immutable.
    
    name_pattern: Substring to match device name (e.g. "Launchpad", "MIDImix")
    input_port: Optional - specific port name if not auto-detected
    output_port: Optional - specific port name if not auto-detected
    """
    name_pattern: str
    input_port: Optional[str] = None
    output_port: Optional[str] = None


@dataclass(frozen=True)
class RouterConfig:
    """
    Complete router configuration. Immutable.
    
    controller: Controller device config
    virtual_output: Virtual MIDI port config (for sending to Magic)
    toggles: Dict of toggle configurations (key = note_or_cc)
    """
    controller: DeviceConfig
    virtual_output: DeviceConfig
    toggles: Dict[int, ToggleConfig]
    
    def with_toggle(self, toggle: ToggleConfig) -> 'RouterConfig':
        """Create new instance with updated toggle."""
        new_toggles = dict(self.toggles)
        new_toggles[toggle.note_or_cc] = toggle
        return replace(self, toggles=new_toggles)
    
    def get_toggle(self, note_or_cc: int) -> Optional[ToggleConfig]:
        """Get toggle config for a note/CC number."""
        return self.toggles.get(note_or_cc)
    
    def has_toggle(self, note_or_cc: int) -> bool:
        """Check if a note/CC is configured as a toggle."""
        return note_or_cc in self.toggles


# =============================================================================
# PURE FUNCTIONS - Calculations with no side effects
# =============================================================================

def parse_midi_message(status: int, data1: int, data2: int) -> MidiMessage:
    """
    Parse raw MIDI bytes into MidiMessage. Pure function.
    
    Args:
        status: Status byte (message type + channel)
        data1: First data byte (note/CC number)
        data2: Second data byte (velocity/value)
    
    Returns:
        MidiMessage instance
    """
    message_type = status & 0xF0
    channel = status & 0x0F
    return MidiMessage(
        message_type=message_type,
        channel=channel,
        note_or_cc=data1,
        velocity_or_value=data2
    )


def create_midi_bytes(msg: MidiMessage) -> Tuple[int, int, int]:
    """
    Convert MidiMessage to raw MIDI bytes. Pure function.
    
    Returns:
        Tuple of (status, data1, data2)
    """
    status = msg.message_type | msg.channel
    return (status, msg.note_or_cc, msg.velocity_or_value)


def should_enhance_message(msg: MidiMessage, config: RouterConfig) -> bool:
    """
    Check if a message should be enhanced (toggle logic). Pure function.
    
    Args:
        msg: MIDI message
        config: Router configuration
    
    Returns:
        True if message is a note-on for a configured toggle
    """
    return msg.is_note_on and config.has_toggle(msg.note_or_cc)


def process_toggle(msg: MidiMessage, config: RouterConfig) -> Tuple[RouterConfig, MidiMessage, MidiMessage]:
    """
    Process a toggle button press. Pure function.
    
    Args:
        msg: Incoming MIDI message (note on)
        config: Current router configuration
    
    Returns:
        Tuple of (new_config, led_message, output_message)
        - new_config: Updated config with flipped toggle state
        - led_message: Message to send to controller LED
        - output_message: Message to send to Magic
    """
    toggle = config.get_toggle(msg.note_or_cc)
    if not toggle:
        # Should never happen if should_enhance_message was checked
        raise ValueError(f"No toggle configured for note {msg.note_or_cc}")
    
    # Flip toggle state
    new_toggle = toggle.toggle()
    new_config = config.with_toggle(new_toggle)
    
    # Create LED feedback message (same note, new velocity based on state)
    led_message = MidiMessage(
        message_type=MidiMessageType.NOTE_ON if toggle.message_type == 'note' else MidiMessageType.CONTROL_CHANGE,
        channel=msg.channel,
        note_or_cc=toggle.note_or_cc,
        velocity_or_value=new_toggle.current_led_velocity
    )
    
    # Create output message to Magic (absolute state)
    output_message = MidiMessage(
        message_type=MidiMessageType.NOTE_ON if toggle.message_type == 'note' else MidiMessageType.CONTROL_CHANGE,
        channel=msg.channel,
        note_or_cc=toggle.note_or_cc,
        velocity_or_value=new_toggle.current_output_velocity
    )
    
    return (new_config, led_message, output_message)


def create_state_sync_messages(config: RouterConfig, channel: int = 0) -> List[Tuple[MidiMessage, MidiMessage]]:
    """
    Create messages to sync all toggle states on startup. Pure function.
    
    Args:
        config: Router configuration
        channel: MIDI channel to use
    
    Returns:
        List of (led_message, output_message) tuples for each toggle
    """
    messages = []
    
    for toggle in config.toggles.values():
        # LED feedback message
        led_msg = MidiMessage(
            message_type=MidiMessageType.NOTE_ON if toggle.message_type == 'note' else MidiMessageType.CONTROL_CHANGE,
            channel=channel,
            note_or_cc=toggle.note_or_cc,
            velocity_or_value=toggle.current_led_velocity
        )
        
        # Output message to Magic
        output_msg = MidiMessage(
            message_type=MidiMessageType.NOTE_ON if toggle.message_type == 'note' else MidiMessageType.CONTROL_CHANGE,
            channel=channel,
            note_or_cc=toggle.note_or_cc,
            velocity_or_value=toggle.current_output_velocity
        )
        
        messages.append((led_msg, output_msg))
    
    return messages


def config_to_dict(config: RouterConfig) -> Dict[str, Any]:
    """
    Convert RouterConfig to serializable dict. Pure function.
    
    Returns:
        Dict suitable for JSON serialization
    """
    return {
        "controller": {
            "name_pattern": config.controller.name_pattern,
            "input_port": config.controller.input_port,
            "output_port": config.controller.output_port,
        },
        "virtual_output": {
            "name_pattern": config.virtual_output.name_pattern,
            "input_port": config.virtual_output.input_port,
            "output_port": config.virtual_output.output_port,
        },
        "toggles": {
            str(note): {
                "name": toggle.name,
                "state": toggle.state,
                "message_type": toggle.message_type,
                "led_on_velocity": toggle.led_on_velocity,
                "led_off_velocity": toggle.led_off_velocity,
                "output_on_velocity": toggle.output_on_velocity,
                "output_off_velocity": toggle.output_off_velocity,
            }
            for note, toggle in config.toggles.items()
        }
    }


def config_from_dict(data: Dict[str, Any]) -> RouterConfig:
    """
    Create RouterConfig from dict. Pure function.
    
    Args:
        data: Dict from config_to_dict or JSON load
    
    Returns:
        RouterConfig instance
    """
    controller = DeviceConfig(
        name_pattern=data["controller"]["name_pattern"],
        input_port=data["controller"].get("input_port"),
        output_port=data["controller"].get("output_port"),
    )
    
    virtual_output = DeviceConfig(
        name_pattern=data["virtual_output"]["name_pattern"],
        input_port=data["virtual_output"].get("input_port"),
        output_port=data["virtual_output"].get("output_port"),
    )
    
    toggles = {}
    for note_str, toggle_data in data.get("toggles", {}).items():
        note = int(note_str)
        toggles[note] = ToggleConfig(
            note_or_cc=note,
            name=toggle_data["name"],
            state=toggle_data.get("state", False),
            message_type=toggle_data.get("message_type", "note"),
            led_on_velocity=toggle_data.get("led_on_velocity", 127),
            led_off_velocity=toggle_data.get("led_off_velocity", 0),
            output_on_velocity=toggle_data.get("output_on_velocity", 127),
            output_off_velocity=toggle_data.get("output_off_velocity", 0),
        )
    
    return RouterConfig(
        controller=controller,
        virtual_output=virtual_output,
        toggles=toggles
    )
