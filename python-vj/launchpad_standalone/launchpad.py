"""
Launchpad Mini Mk3 MIDI Driver

Self-contained driver for the standalone app.
"""

import asyncio
import logging
from dataclasses import dataclass
from typing import Optional, Callable, Tuple, Any

from .model import ButtonId

try:
    import mido
    from mido import Message
    MIDO_AVAILABLE = True
except ImportError:
    MIDO_AVAILABLE = False
    mido = None
    Message = None

logger = logging.getLogger(__name__)


# =============================================================================
# COORDINATE MAPPING
# =============================================================================

def pad_to_note(pad_id: ButtonId) -> Tuple[str, int]:
    """Convert ButtonId to MIDI message type and number."""
    if pad_id.is_scene_button():
        # Scene buttons: notes 19, 29, ..., 89
        return ("note", (pad_id.y + 1) * 10 + 9)
    else:
        # Grid: notes 11-88
        return ("note", (pad_id.y + 1) * 10 + (pad_id.x + 1))


def note_to_pad(msg_type: str, number: int) -> Optional[ButtonId]:
    """Convert MIDI note to ButtonId."""
    if msg_type != "note":
        return None
    
    row = (number // 10) - 1
    col = (number % 10) - 1
    
    # Scene button (column 8)
    if col == 8 and 0 <= row <= 7:
        return ButtonId(x=8, y=row)
    # Grid pad
    elif 0 <= row <= 7 and 0 <= col <= 7:
        return ButtonId(x=col, y=row)
    
    return None


# =============================================================================
# DEVICE DETECTION
# =============================================================================

def find_launchpad_ports() -> Tuple[Optional[str], Optional[str]]:
    """Auto-detect Launchpad Mini Mk3 MIDI ports."""
    if not MIDO_AVAILABLE:
        logger.error("mido not available")
        return None, None
    
    try:
        input_ports = mido.get_input_names()
        output_ports = mido.get_output_names()
    except Exception as e:
        logger.warning(f"Could not query MIDI ports: {e}")
        return None, None
    
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
    
    return input_port, output_port


# =============================================================================
# LAUNCHPAD DEVICE
# =============================================================================

@dataclass
class LaunchpadConfig:
    """Configuration for Launchpad connection."""
    input_port: Optional[str] = None
    output_port: Optional[str] = None
    auto_detect: bool = True


class LaunchpadDevice:
    """Async Launchpad Mini Mk3 driver."""
    
    def __init__(self, config: Optional[LaunchpadConfig] = None):
        self.config = config or LaunchpadConfig()
        self._input_port: Any = None
        self._output_port: Any = None
        self._running = False
        self._press_callback: Optional[Callable[[ButtonId, int], None]] = None
        self._release_callback: Optional[Callable[[ButtonId], None]] = None
        self._led_cache: dict = {}
    
    async def connect(self) -> bool:
        """Connect and enter Programmer mode."""
        if not MIDO_AVAILABLE:
            logger.error("mido not available")
            return False
        
        input_name, output_name = self.config.input_port, self.config.output_port
        
        if self.config.auto_detect or not (input_name and output_name):
            input_name, output_name = find_launchpad_ports()
        
        if not (input_name and output_name):
            logger.error("Launchpad not found")
            return False
        
        try:
            self._input_port = mido.open_input(input_name)
            self._output_port = mido.open_output(output_name)
            
            # Enter Programmer mode
            programmer_mode = [0x00, 0x20, 0x29, 0x02, 0x0D, 0x0E, 0x01]
            self._output_port.send(Message('sysex', data=programmer_mode))
            
            logger.info(f"Connected to Launchpad: {input_name}")
            return True
            
        except Exception as e:
            logger.error(f"Connection failed: {e}")
            return False
    
    def set_callbacks(
        self,
        on_press: Optional[Callable[[ButtonId, int], None]] = None,
        on_release: Optional[Callable[[ButtonId], None]] = None
    ):
        """Set pad press/release callbacks."""
        self._press_callback = on_press
        self._release_callback = on_release
    
    async def start_listening(self):
        """Start MIDI input loop."""
        if not self._input_port:
            return
        
        self._running = True
        logger.info("Listening for Launchpad input")
        
        loop = asyncio.get_event_loop()
        await loop.run_in_executor(None, self._listen_loop)
    
    def _listen_loop(self):
        """Blocking MIDI input loop."""
        while self._running:
            try:
                msg = self._input_port.receive(block=True, timeout=0.1)
                if msg:
                    self._process_message(msg)
            except Exception as e:
                if self._running:
                    logger.error(f"MIDI error: {e}")
    
    def _process_message(self, msg: Any):
        """Process MIDI message."""
        if msg.type == 'note_on':
            pad_id = note_to_pad("note", msg.note)
            if pad_id:
                if msg.velocity > 0 and self._press_callback:
                    logger.info(f"MIDI RX: Press {pad_id} (note={msg.note}, vel={msg.velocity})")
                    self._press_callback(pad_id, msg.velocity)
                elif msg.velocity == 0 and self._release_callback:
                    logger.info(f"MIDI RX: Release {pad_id} (note={msg.note})")
                    self._release_callback(pad_id)
        
        elif msg.type == 'note_off':
            pad_id = note_to_pad("note", msg.note)
            if pad_id and self._release_callback:
                logger.info(f"MIDI RX: Release {pad_id} (note={msg.note})")
                self._release_callback(pad_id)
    
    def set_led(self, pad_id: ButtonId, color: int):
        """Set LED color."""
        if not self._output_port:
            return
        
        cache_key = (pad_id.x, pad_id.y)
        if self._led_cache.get(cache_key) == color:
            return
        self._led_cache[cache_key] = color
        
        _, note = pad_to_note(pad_id)
        
        try:
            logger.info(f"MIDI TX: LED {pad_id} → color={color} (note={note})")
            self._output_port.send(Message('note_on', note=note, velocity=color))
        except Exception as e:
            logger.error(f"LED error: {e}")
    
    def clear_all(self):
        """Turn off all LEDs."""
        if not self._output_port:
            return
        
        for y in range(8):
            for x in range(9):  # Include scene buttons
                self.set_led(ButtonId(x, y), 0)
        
        self._led_cache.clear()
    
    async def stop(self):
        """Stop and disconnect."""
        self._running = False
        
        if self._output_port:
            self.clear_all()
            self._output_port.close()
        
        if self._input_port:
            self._input_port.close()
        
        self._input_port = None
        self._output_port = None
        logger.info("Disconnected from Launchpad")
    
    def is_connected(self) -> bool:
        """Check connection status."""
        return self._input_port is not None
