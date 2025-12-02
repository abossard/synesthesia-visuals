#!/usr/bin/env python3
"""
MIDI Infrastructure - Device Discovery and I/O

Handles MIDI port discovery, connection management, and message I/O.
Wraps python-rtmidi for clean interfaces.
"""

import logging
from typing import Optional, List, Tuple, Callable
from dataclasses import dataclass
import time

try:
    import rtmidi
    RTMIDI_AVAILABLE = True
except ImportError:
    RTMIDI_AVAILABLE = False

from midi_domain import MidiMessage, DeviceConfig, create_midi_bytes

logger = logging.getLogger('midi_router')


# =============================================================================
# DEVICE DISCOVERY - Pure functions
# =============================================================================

def find_port_by_pattern(port_names: List[str], pattern: str) -> Optional[str]:
    """
    Find a MIDI port by substring match. Pure function.
    
    Args:
        port_names: List of available port names
        pattern: Substring to match (case-insensitive)
    
    Returns:
        Matching port name or None
    """
    pattern_lower = pattern.lower()
    for name in port_names:
        if pattern_lower in name.lower():
            return name
    return None


def list_available_ports() -> Tuple[List[str], List[str]]:
    """
    List all available MIDI ports.
    
    Returns:
        Tuple of (input_ports, output_ports)
    """
    if not RTMIDI_AVAILABLE:
        logger.warning("python-rtmidi not available")
        return ([], [])
    
    try:
        midi_in = rtmidi.MidiIn()
        midi_out = rtmidi.MidiOut()
        
        input_ports = midi_in.get_ports()
        output_ports = midi_out.get_ports()
        
        # Clean up (explicit close before del)
        midi_in.close_port()
        midi_out.close_port()
        del midi_in
        del midi_out
        
        return (input_ports, output_ports)
    except Exception as e:
        logger.error(f"Failed to list MIDI ports: {e}")
        return ([], [])


# =============================================================================
# MIDI PORT WRAPPERS
# =============================================================================

class MidiInputPort:
    """
    Wrapper for MIDI input port with callback support.
    
    Deep module: Simple interface (open, set_callback, close)
    hiding rtmidi complexity.
    """
    
    def __init__(self, port_name: str):
        """
        Initialize MIDI input port.
        
        Args:
            port_name: Name of the MIDI input port to open
        """
        if not RTMIDI_AVAILABLE:
            raise RuntimeError("python-rtmidi not installed. Install with: pip install python-rtmidi")
        
        self._port_name = port_name
        self._midi_in: Optional[rtmidi.MidiIn] = None
        self._callback: Optional[Callable[[MidiMessage], None]] = None
    
    def open(self) -> bool:
        """
        Open the MIDI input port.
        
        Returns:
            True if successful, False otherwise
        """
        try:
            self._midi_in = rtmidi.MidiIn()
            
            # Find port index
            ports = self._midi_in.get_ports()
            port_index = None
            for i, name in enumerate(ports):
                if name == self._port_name:
                    port_index = i
                    break
            
            if port_index is None:
                logger.error(f"MIDI input port not found: {self._port_name}")
                return False
            
            # Open port
            self._midi_in.open_port(port_index)
            self._midi_in.set_callback(self._on_midi_message)
            
            logger.info(f"Opened MIDI input: {self._port_name}")
            return True
            
        except Exception as e:
            logger.error(f"Failed to open MIDI input {self._port_name}: {e}")
            return False
    
    def _on_midi_message(self, event, data=None):
        """
        Internal callback for rtmidi.
        
        Args:
            event: (message, timestamp) tuple from rtmidi
            data: User data (unused)
        """
        if not self._callback:
            return
        
        message, timestamp = event
        
        # Parse MIDI message
        if len(message) < 2:
            return  # Invalid message
        
        status = message[0]
        data1 = message[1] if len(message) > 1 else 0
        data2 = message[2] if len(message) > 2 else 0
        
        # Extract message type and channel
        message_type = status & 0xF0
        channel = status & 0x0F
        
        msg = MidiMessage(
            message_type=message_type,
            channel=channel,
            note_or_cc=data1,
            velocity_or_value=data2
        )
        
        # Call user callback
        try:
            self._callback(msg)
        except Exception as e:
            logger.error(f"Error in MIDI callback: {e}")
    
    def set_callback(self, callback: Callable[[MidiMessage], None]):
        """
        Set callback for incoming MIDI messages.
        
        Args:
            callback: Function that takes a MidiMessage
        """
        self._callback = callback
    
    def close(self):
        """Close the MIDI input port."""
        if self._midi_in:
            try:
                self._midi_in.close_port()
                del self._midi_in
                self._midi_in = None
                logger.info(f"Closed MIDI input: {self._port_name}")
            except Exception as e:
                logger.error(f"Error closing MIDI input: {e}")
    
    def __del__(self):
        """Cleanup on destruction."""
        self.close()


class MidiOutputPort:
    """
    Wrapper for MIDI output port.
    
    Deep module: Simple interface (open, send, close)
    hiding rtmidi complexity.
    """
    
    def __init__(self, port_name: str):
        """
        Initialize MIDI output port.
        
        Args:
            port_name: Name of the MIDI output port to open
        """
        if not RTMIDI_AVAILABLE:
            raise RuntimeError("python-rtmidi not installed. Install with: pip install python-rtmidi")
        
        self._port_name = port_name
        self._midi_out: Optional[rtmidi.MidiOut] = None
    
    def open(self) -> bool:
        """
        Open the MIDI output port.
        
        Returns:
            True if successful, False otherwise
        """
        try:
            self._midi_out = rtmidi.MidiOut()
            
            # Find port index
            ports = self._midi_out.get_ports()
            port_index = None
            for i, name in enumerate(ports):
                if name == self._port_name:
                    port_index = i
                    break
            
            if port_index is None:
                logger.error(f"MIDI output port not found: {self._port_name}")
                return False
            
            # Open port
            self._midi_out.open_port(port_index)
            
            logger.info(f"Opened MIDI output: {self._port_name}")
            return True
            
        except Exception as e:
            logger.error(f"Failed to open MIDI output {self._port_name}: {e}")
            return False
    
    def send(self, msg: MidiMessage) -> bool:
        """
        Send a MIDI message.
        
        Args:
            msg: MidiMessage to send
        
        Returns:
            True if successful, False otherwise
        """
        if not self._midi_out:
            logger.error("MIDI output port not open")
            return False
        
        try:
            status, data1, data2 = create_midi_bytes(msg)
            self._midi_out.send_message([status, data1, data2])
            return True
        except Exception as e:
            logger.error(f"Failed to send MIDI message: {e}")
            return False
    
    def close(self):
        """Close the MIDI output port."""
        if self._midi_out:
            try:
                self._midi_out.close_port()
                del self._midi_out
                self._midi_out = None
                logger.info(f"Closed MIDI output: {self._port_name}")
            except Exception as e:
                logger.error(f"Error closing MIDI output: {e}")
    
    def __del__(self):
        """Cleanup on destruction."""
        self.close()


# =============================================================================
# DEVICE MANAGER - High-level device management
# =============================================================================

@dataclass
class MidiDeviceInfo:
    """Information about discovered MIDI devices."""
    name: str
    input_available: bool
    output_available: bool


class MidiDeviceManager:
    """
    High-level MIDI device management.
    
    Handles device discovery, connection, and provides
    clean interfaces for input/output operations.
    """
    
    def __init__(self):
        """Initialize device manager."""
        self._input_port: Optional[MidiInputPort] = None
        self._output_ports: List[MidiOutputPort] = []
    
    def discover_devices(self) -> List[MidiDeviceInfo]:
        """
        Discover available MIDI devices.
        
        Returns:
            List of MidiDeviceInfo
        """
        input_ports, output_ports = list_available_ports()
        
        # Build device info
        devices = {}
        
        for port in input_ports:
            if port not in devices:
                devices[port] = MidiDeviceInfo(
                    name=port,
                    input_available=True,
                    output_available=False
                )
            else:
                devices[port].input_available = True
        
        for port in output_ports:
            if port not in devices:
                devices[port] = MidiDeviceInfo(
                    name=port,
                    input_available=False,
                    output_available=True
                )
            else:
                devices[port].output_available = True
        
        return list(devices.values())
    
    def connect_input(self, config: DeviceConfig) -> bool:
        """
        Connect to input device.
        
        Args:
            config: Device configuration
        
        Returns:
            True if successful
        """
        # Get available ports
        input_ports, _ = list_available_ports()
        
        # Find port
        port_name = config.input_port
        if not port_name:
            port_name = find_port_by_pattern(input_ports, config.name_pattern)
        
        if not port_name:
            logger.error(f"No input port found matching: {config.name_pattern}")
            return False
        
        # Open port
        self._input_port = MidiInputPort(port_name)
        return self._input_port.open()
    
    def connect_outputs(self, configs: List[DeviceConfig]) -> bool:
        """
        Connect to output devices.
        
        Args:
            configs: List of device configurations
        
        Returns:
            True if all successful
        """
        _, output_ports = list_available_ports()
        
        success = True
        for config in configs:
            # Find port
            port_name = config.output_port
            if not port_name:
                port_name = find_port_by_pattern(output_ports, config.name_pattern)
            
            if not port_name:
                logger.error(f"No output port found matching: {config.name_pattern}")
                success = False
                continue
            
            # Open port
            output = MidiOutputPort(port_name)
            if output.open():
                self._output_ports.append(output)
            else:
                success = False
        
        return success
    
    def set_input_callback(self, callback: Callable[[MidiMessage], None]):
        """
        Set callback for incoming MIDI messages.
        
        Args:
            callback: Function that takes a MidiMessage
        """
        if self._input_port:
            self._input_port.set_callback(callback)
    
    def send_to_output(self, output_index: int, msg: MidiMessage) -> bool:
        """
        Send message to specific output.
        
        Args:
            output_index: Index of output port (0 = controller, 1 = virtual)
            msg: MidiMessage to send
        
        Returns:
            True if successful
        """
        if output_index >= len(self._output_ports):
            logger.error(f"Output index {output_index} out of range")
            return False
        
        return self._output_ports[output_index].send(msg)
    
    def close_all(self):
        """Close all open ports."""
        if self._input_port:
            self._input_port.close()
            self._input_port = None
        
        for output in self._output_ports:
            output.close()
        self._output_ports.clear()
        
        logger.info("Closed all MIDI ports")
    
    def __del__(self):
        """Cleanup on destruction."""
        self.close_all()
