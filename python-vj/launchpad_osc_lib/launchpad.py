"""
Launchpad Mini Mk3 MIDI Driver

Device-agnostic Launchpad driver handling:
- Device detection
- Programmer mode setup
- MIDI I/O (pad press events)
- LED color control

No application-specific logic - pure hardware abstraction.
"""

import asyncio
import logging
from dataclasses import dataclass
from typing import Optional, Callable, Tuple, Any

try:
    import mido
    from mido import Message
    MIDO_AVAILABLE = True
except ImportError:
    MIDO_AVAILABLE = False
    mido = None  # type: Any
    Message = None  # type: Any

logger = logging.getLogger(__name__)


# =============================================================================
# PAD IDENTIFIER
# =============================================================================

@dataclass(frozen=True)
class PadId:
    """
    Unique identifier for a Launchpad pad.
    
    Coordinate system:
    - Main 8x8 grid: x, y in range 0-7
    - Top row buttons: x in range 0-7, y = -1
    - Right column buttons: x = 8, y in range 0-7
    """
    x: int
    y: int
    
    def is_grid(self) -> bool:
        """Check if this is a main grid pad (8x8)."""
        return 0 <= self.x <= 7 and 0 <= self.y <= 7
    
    def is_top_row(self) -> bool:
        """Check if this is a top row button."""
        return 0 <= self.x <= 7 and self.y == -1
    
    def is_right_column(self) -> bool:
        """Check if this is a right column button."""
        return self.x == 8 and 0 <= self.y <= 7
    
    def __str__(self) -> str:
        if self.is_top_row():
            return f"Top{self.x}"
        elif self.is_right_column():
            return f"Right{self.y}"
        else:
            return f"({self.x},{self.y})"


# =============================================================================
# LAUNCHPAD MINI MK3 COLORS (velocity values)
# =============================================================================

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

# Named color palette for convenience
COLOR_PALETTE = {
    "off": LP_OFF,
    "red": LP_RED,
    "red_dim": LP_RED_DIM,
    "orange": LP_ORANGE,
    "yellow": LP_YELLOW,
    "green": LP_GREEN,
    "green_dim": LP_GREEN_DIM,
    "cyan": LP_CYAN,
    "blue": LP_BLUE,
    "blue_dim": LP_BLUE_DIM,
    "purple": LP_PURPLE,
    "pink": LP_PINK,
    "white": LP_WHITE,
}


# =============================================================================
# COORDINATE MAPPING (Launchpad Mini Mk3 Programmer Mode)
# =============================================================================

def pad_to_note(pad_id: PadId) -> Tuple[str, int]:
    """
    Convert PadId to MIDI message type and number.
    
    Launchpad Mini Mk3 Programmer Mode layout:
    - Grid: notes 11-88 where note = (row+1)*10 + (col+1)
    - Top row: CC 91-98
    - Right column: notes 19, 29, ..., 89
    
    Returns:
        ("note", note_number) or ("cc", cc_number)
    """
    if pad_id.is_top_row():
        return ("cc", 91 + pad_id.x)
    elif pad_id.is_right_column():
        return ("note", (pad_id.y + 1) * 10 + 9)
    else:
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
        if 91 <= number <= 98:
            return PadId(x=number - 91, y=-1)
        return None
    
    elif msg_type == "note":
        row = (number // 10) - 1
        col = (number % 10) - 1
        
        if col == 8 and 0 <= row <= 7:
            return PadId(x=8, y=row)
        elif 0 <= row <= 7 and 0 <= col <= 7:
            return PadId(x=col, y=row)
    
    return None


# =============================================================================
# DEVICE DETECTION
# =============================================================================

def find_launchpad_ports() -> Tuple[Optional[str], Optional[str]]:
    """
    Auto-detect Launchpad Mini Mk3 MIDI ports.
    
    Searches for common Launchpad port name patterns.
    
    Returns:
        (input_port_name, output_port_name) or (None, None) if not found
    """
    if not MIDO_AVAILABLE:
        logger.error("mido not available - install with: pip install mido python-rtmidi")
        return None, None
    
    try:
        input_ports = mido.get_input_names()
        output_ports = mido.get_output_names()
    except Exception as e:
        logger.warning(f"Could not query MIDI ports: {e}")
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
# CONFIGURATION
# =============================================================================

@dataclass
class LaunchpadConfig:
    """Configuration for Launchpad connection."""
    input_port: Optional[str] = None
    output_port: Optional[str] = None
    auto_detect: bool = True


# =============================================================================
# LAUNCHPAD DEVICE
# =============================================================================

class LaunchpadDevice:
    """
    Async Launchpad Mini Mk3 driver.
    
    Manages MIDI I/O in Programmer mode:
    - Sends SysEx to enter Programmer mode on connect
    - Receives pad press events via callback
    - Controls LED colors with caching to avoid redundant updates
    """
    
    def __init__(self, config: Optional[LaunchpadConfig] = None):
        self.config = config or LaunchpadConfig()
        self._input_port: Any = None
        self._output_port: Any = None
        self._running = False
        self._callback: Optional[Callable[[PadId, int], None]] = None
        self._led_cache: dict = {}
    
    async def connect(self) -> bool:
        """
        Connect to Launchpad device and enter Programmer mode.
        
        Returns:
            True if connected successfully
        """
        if not MIDO_AVAILABLE:
            logger.error("mido not available")
            return False
        
        input_name = self.config.input_port
        output_name = self.config.output_port
        
        if self.config.auto_detect or not (input_name and output_name):
            input_name, output_name = find_launchpad_ports()
        
        if not (input_name and output_name):
            logger.error("Could not find Launchpad ports")
            return False
        
        try:
            self._input_port = mido.open_input(input_name)
            self._output_port = mido.open_output(output_name)
            
            # Enter Programmer mode via SysEx
            # F0h 00h 20h 29h 02h 0Dh 0Eh 01h F7h
            programmer_mode_sysex = [0x00, 0x20, 0x29, 0x02, 0x0D, 0x0E, 0x01]
            self._output_port.send(Message('sysex', data=programmer_mode_sysex))
            
            logger.info("Connected to Launchpad in Programmer mode")
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
    
    def set_pad_release_callback(self, callback: Callable[[PadId], None]):
        """
        Set callback for pad release events.
        
        Args:
            callback: Function called with (pad_id) on pad release
        """
        self._release_callback = callback
    
    async def start_listening(self):
        """Start listening for MIDI input (async loop)."""
        if not self._input_port:
            logger.error("Not connected to Launchpad")
            return
        
        self._running = True
        logger.info("Started listening for Launchpad input")
        
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
    
    def _process_midi_message(self, msg: Any):
        """Process incoming MIDI message."""
        if msg.type == 'note_on':
            pad_id = note_to_pad("note", msg.note)
            if pad_id:
                if msg.velocity > 0 and self._callback:
                    self._callback(pad_id, msg.velocity)
                elif msg.velocity == 0 and hasattr(self, '_release_callback') and self._release_callback:
                    # Note-on with velocity 0 = note-off (common MIDI pattern)
                    self._release_callback(pad_id)
        
        elif msg.type == 'note_off':
            # Explicit note-off message
            pad_id = note_to_pad("note", msg.note)
            if pad_id and hasattr(self, '_release_callback') and self._release_callback:
                self._release_callback(pad_id)
        
        elif msg.type == 'control_change':
            pad_id = note_to_pad("cc", msg.control)
            if pad_id and msg.value > 0 and self._callback:
                self._callback(pad_id, msg.value)
    
    def set_led(self, pad_id: PadId, color: int, blink: bool = False):
        """
        Set LED color for a pad.
        
        Uses caching to avoid redundant MIDI messages.
        
        Args:
            pad_id: Pad to update
            color: Color index 0-127 (see LP_* constants)
            blink: Reserved for future pulse mode support
        """
        if not self._output_port:
            return
        
        cache_key = (pad_id, color, blink)
        if self._led_cache.get(pad_id) == cache_key:
            return
        self._led_cache[pad_id] = cache_key
        
        msg_type, number = pad_to_note(pad_id)
        
        try:
            if msg_type == "note":
                self._output_port.send(Message('note_on', note=number, velocity=color))
            elif msg_type == "cc":
                self._output_port.send(Message('control_change', control=number, value=color))
        except Exception as e:
            logger.error(f"Failed to set LED {pad_id}: {e}")
    
    def clear_all_leds(self):
        """Turn off all LEDs."""
        if not self._output_port:
            return
        
        for y in range(8):
            for x in range(8):
                self.set_led(PadId(x, y), LP_OFF)
        
        for x in range(8):
            self.set_led(PadId(x, -1), LP_OFF)
        
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
