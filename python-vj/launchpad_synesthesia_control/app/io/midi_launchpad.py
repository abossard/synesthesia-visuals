"""
Launchpad Mini Mk3 MIDI Driver

Handles MIDI communication with Launchpad Mini Mk3 in Programmer mode.
Uses async I/O for low latency.
"""

import asyncio
import logging
from typing import Optional, Callable, Tuple, List
from dataclasses import dataclass

try:
    import mido
    from mido import Message
    MIDO_AVAILABLE = True
except ImportError:
    MIDO_AVAILABLE = False
    mido = None
    Message = None

from ..domain.model import PadId

logger = logging.getLogger(__name__)


# =============================================================================
# LAUNCHPAD MINI MK3 CONSTANTS (PROGRAMMER MODE)
# =============================================================================

# Grid pads: notes 11-88 where note = (row+1)*10 + (col+1)
# Example: (0,0) -> 11, (7,7) -> 88
# Top row: CC 91-98 (x=0-7, y=-1)
# Right column: notes 19, 29, 39, 49, 59, 69, 79, 89 (x=8, y=0-7)

# Standard Launchpad colors (velocity values)
LP_OFF = 0
LP_RED = 5
LP_RED_DIM = 1
LP_ORANGE = 9
LP_YELLOW = 13
LP_GREEN = 21
LP_GREEN_DIM = 17
LP_CYAN = 37
LP_BLUE = 45
LP_BLUE_DIM = 41
LP_PURPLE = 53
LP_PINK = 57
LP_WHITE = 3

# Color palette for selection
COLOR_PALETTE = {
    "off": LP_OFF,
    "red": LP_RED,
    "orange": LP_ORANGE,
    "yellow": LP_YELLOW,
    "green": LP_GREEN,
    "cyan": LP_CYAN,
    "blue": LP_BLUE,
    "purple": LP_PURPLE,
    "pink": LP_PINK,
    "white": LP_WHITE,
}


# =============================================================================
# PAD COORDINATE MAPPING
# =============================================================================

def pad_to_note(pad_id: PadId) -> Tuple[str, int]:
    """
    Convert PadId to MIDI message type and number.
    
    Returns:
        ("note", note_number) or ("cc", cc_number)
    """
    if pad_id.is_top_row():
        # Top row uses CC 91-98
        return ("cc", 91 + pad_id.x)
    elif pad_id.is_right_column():
        # Right column uses notes 19, 29, ..., 89
        return ("note", (pad_id.y + 1) * 10 + 9)
    else:
        # Main grid uses notes 11-88
        return ("note", (pad_id.y + 1) * 10 + (pad_id.x + 1))


def note_to_pad(msg_type: str, number: int) -> Optional[PadId]:
    """
    Convert MIDI note/CC to PadId.
    
    Args:
        msg_type: "note" or "cc"
        number: MIDI note or CC number
    
    Returns:
        PadId or None if not a valid pad
    """
    if msg_type == "cc":
        # Top row: CC 91-98
        if 91 <= number <= 98:
            return PadId(x=number - 91, y=-1)
        return None
    
    elif msg_type == "note":
        # Decode note number
        # Format: (row+1)*10 + (col+1)
        row = (number // 10) - 1
        col = (number % 10) - 1
        
        # Validate
        if col == 8 and 0 <= row <= 7:
            # Right column
            return PadId(x=8, y=row)
        elif 0 <= row <= 7 and 0 <= col <= 7:
            # Main grid
            return PadId(x=col, y=row)
    
    return None


# =============================================================================
# DEVICE DETECTION
# =============================================================================

def find_launchpad_ports() -> Tuple[Optional[str], Optional[str]]:
    """
    Auto-detect Launchpad Mini Mk3 MIDI ports.
    
    Returns:
        (input_port_name, output_port_name) or (None, None) if not found
    """
    if not MIDO_AVAILABLE:
        logger.error("mido not available - install with: pip install mido python-rtmidi")
        return None, None
    
    # Look for Launchpad in available ports
    try:
        input_ports = mido.get_input_names()
        output_ports = mido.get_output_names()
    except Exception as e:
        logger.warning(f"Could not query MIDI ports (expected in CI/headless): {e}")
        return None, None
    
    logger.debug(f"Available input ports: {input_ports}")
    logger.debug(f"Available output ports: {output_ports}")
    
    # Search patterns for Launchpad Mini Mk3
    patterns = ["Launchpad Mini MK3", "LPMiniMK3", "MIDIIN2", "MIDIOUT2"]
    
    input_port = None
    output_port = None
    
    for pattern in patterns:
        for port in input_ports:
            if pattern.lower() in port.lower():
                input_port = port
                break
        if input_port:
            break
    
    for pattern in patterns:
        for port in output_ports:
            if pattern.lower() in port.lower():
                output_port = port
                break
        if output_port:
            break
    
    if input_port and output_port:
        logger.info(f"Found Launchpad: IN={input_port}, OUT={output_port}")
    else:
        logger.warning("Launchpad Mini Mk3 not found")
    
    return input_port, output_port


# =============================================================================
# LAUNCHPAD DEVICE MANAGER
# =============================================================================

@dataclass
class LaunchpadConfig:
    """Configuration for Launchpad connection."""
    input_port: Optional[str] = None
    output_port: Optional[str] = None
    auto_detect: bool = True


class LaunchpadDevice:
    """
    Async Launchpad Mini Mk3 driver.
    
    Manages MIDI I/O in Programmer mode with low latency.
    """
    
    def __init__(self, config: LaunchpadConfig):
        self.config = config
        self._input_port: Optional[mido.ports.BaseInput] = None
        self._output_port: Optional[mido.ports.BaseOutput] = None
        self._running = False
        self._callback: Optional[Callable[[PadId, int], None]] = None
        self._led_cache: dict = {}  # Cache current LED states to avoid redundant updates
    
    async def connect(self) -> bool:
        """
        Connect to Launchpad device.
        
        Returns:
            True if connected successfully
        """
        if not MIDO_AVAILABLE:
            logger.error("mido not available")
            return False
        
        # Auto-detect if needed
        input_name = self.config.input_port
        output_name = self.config.output_port
        
        if self.config.auto_detect or not (input_name and output_name):
            input_name, output_name = find_launchpad_ports()
        
        if not (input_name and output_name):
            logger.error("Could not find Launchpad ports")
            return False
        
        try:
            # Open ports
            self._input_port = mido.open_input(input_name)
            self._output_port = mido.open_output(output_name)
            
            # Enter Programmer mode (SysEx)
            # F0h 00h 20h 29h 02h 0Dh 0Eh 01h F7h
            programmer_mode = [0xF0, 0x00, 0x20, 0x29, 0x02, 0x0D, 0x0E, 0x01, 0xF7]
            self._output_port.send(Message('sysex', data=programmer_mode[1:-1]))
            
            logger.info(f"Connected to Launchpad in Programmer mode")
            return True
            
        except Exception as e:
            logger.error(f"Failed to connect to Launchpad: {e}")
            return False
    
    def set_pad_callback(self, callback: Callable[[PadId, int], None]):
        """
        Set callback for pad press events.
        
        Args:
            callback: Function called with (pad_id, velocity) on pad press
        """
        self._callback = callback
    
    async def start_listening(self):
        """Start listening for MIDI input (async loop)."""
        if not self._input_port:
            logger.error("Not connected to Launchpad")
            return
        
        self._running = True
        logger.info("Started listening for Launchpad input")
        
        # Run in executor to avoid blocking
        loop = asyncio.get_event_loop()
        await loop.run_in_executor(None, self._listen_loop)
    
    def _listen_loop(self):
        """Blocking MIDI input loop (runs in executor)."""
        while self._running:
            try:
                msg = self._input_port.receive(block=True, timeout=0.1)
                if msg and self._callback:
                    self._process_midi_message(msg)
            except Exception as e:
                if self._running:
                    logger.error(f"MIDI receive error: {e}")
    
    def _process_midi_message(self, msg: Message):
        """Process incoming MIDI message."""
        # Convert to pad press event
        if msg.type == 'note_on':
            pad_id = note_to_pad("note", msg.note)
            if pad_id and msg.velocity > 0:
                self._callback(pad_id, msg.velocity)
        
        elif msg.type == 'control_change':
            pad_id = note_to_pad("cc", msg.control)
            if pad_id and msg.value > 0:
                self._callback(pad_id, msg.value)
    
    def set_led(self, pad_id: PadId, color: int, blink: bool = False):
        """
        Set LED color for a pad (sync, non-blocking).
        
        Args:
            pad_id: Pad to update
            color: Color index 0-127
            blink: Whether to blink (uses pulse mode on Launchpad)
        """
        if not self._output_port:
            return
        
        # Check cache to avoid redundant updates
        cache_key = (pad_id, color, blink)
        if self._led_cache.get(pad_id) == cache_key:
            return
        self._led_cache[pad_id] = cache_key
        
        msg_type, number = pad_to_note(pad_id)
        
        try:
            if msg_type == "note":
                # Note on for grid and right column
                self._output_port.send(Message('note_on', note=number, velocity=color))
            elif msg_type == "cc":
                # CC for top row
                self._output_port.send(Message('control_change', control=number, value=color))
        except Exception as e:
            logger.error(f"Failed to set LED {pad_id}: {e}")
    
    def clear_all_leds(self):
        """Clear all LEDs."""
        if not self._output_port:
            return
        
        # Clear grid
        for y in range(8):
            for x in range(8):
                self.set_led(PadId(x, y), LP_OFF)
        
        # Clear top row
        for x in range(8):
            self.set_led(PadId(x, -1), LP_OFF)
        
        # Clear right column
        for y in range(8):
            self.set_led(PadId(8, y), LP_OFF)
        
        self._led_cache.clear()
    
    async def stop(self):
        """Stop listening and close ports."""
        self._running = False
        
        if self._output_port:
            self.clear_all_leds()
            self._output_port.close()
            self._output_port = None
        
        if self._input_port:
            self._input_port.close()
            self._input_port = None
        
        logger.info("Disconnected from Launchpad")
    
    def is_connected(self) -> bool:
        """Check if device is connected."""
        return self._input_port is not None and self._output_port is not None
