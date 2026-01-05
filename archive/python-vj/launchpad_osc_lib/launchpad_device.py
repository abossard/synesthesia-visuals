"""
Launchpad Mini Mk3 Device Driver

Synchronous wrapper around lpminimk3 for the Launchpad Mini MK3.
Provides a simple interface for button events and LED control.
"""

import logging
import threading
from typing import Optional, Callable

from .button_id import ButtonId

try:
    import lpminimk3
    from lpminimk3 import LaunchpadMiniMk3, Mode, ButtonEvent
    LPMINIMK3_AVAILABLE = True
except ImportError:
    LPMINIMK3_AVAILABLE = False
    lpminimk3 = None  # type: ignore
    LaunchpadMiniMk3 = None  # type: ignore
    Mode = None  # type: ignore
    ButtonEvent = None  # type: ignore

logger = logging.getLogger(__name__)


class LaunchpadDevice:
    """
    Launchpad Mini Mk3 driver using lpminimk3.
    
    Provides synchronous interface with threaded event polling.
    
    Example:
        device = LaunchpadDevice()
        if device.connect():
            device.set_callbacks(on_press=my_handler)
            device.start_listening()  # Blocks until stop()
    """
    
    def __init__(self):
        self._lp: Optional[LaunchpadMiniMk3] = None
        self._running = False
        self._press_callback: Optional[Callable[[ButtonId, int], None]] = None
        self._release_callback: Optional[Callable[[ButtonId], None]] = None
        self._listen_thread: Optional[threading.Thread] = None
        self._led_cache: dict = {}
    
    def connect(self) -> bool:
        """
        Connect to Launchpad and enter Programmer mode.
        
        Returns:
            True if connected successfully
        """
        if not LPMINIMK3_AVAILABLE:
            logger.error("lpminimk3 not available - install with: pip install lpminimk3")
            return False
        
        try:
            devices = lpminimk3.find_launchpads()
            if not devices:
                logger.error("No Launchpad Mini MK3 found")
                return False
            
            self._lp = devices[0]
            self._lp.open()
            self._lp.mode = Mode.PROG
            
            logger.info(f"Connected to Launchpad: {self._lp.id}")
            return True
            
        except Exception as e:
            logger.error(f"Connection failed: {e}")
            return False
    
    def set_callbacks(
        self,
        on_press: Optional[Callable[[ButtonId, int], None]] = None,
        on_release: Optional[Callable[[ButtonId], None]] = None
    ):
        """
        Set button press/release callbacks.
        
        Args:
            on_press: Called with (ButtonId, velocity) on button press
            on_release: Called with (ButtonId) on button release
        """
        self._press_callback = on_press
        self._release_callback = on_release
    
    def start_listening(self):
        """
        Start listening for button events (blocking).
        
        Spawns a background thread for event polling and blocks
        the main thread until stop() is called or KeyboardInterrupt.
        """
        if not self._lp:
            logger.error("Not connected to Launchpad")
            return
        
        self._running = True
        logger.info("Listening for Launchpad input")
        
        # Start event polling in background thread
        self._listen_thread = threading.Thread(target=self._listen_loop, daemon=True)
        self._listen_thread.start()
        
        # Block main thread
        try:
            while self._running:
                threading.Event().wait(1)
        except KeyboardInterrupt:
            logger.info("Interrupted")
            self.stop()
    
    def _listen_loop(self):
        """Internal event polling loop."""
        while self._running:
            try:
                event = self._lp.panel.buttons().poll_for_event(timeout=0.1)
                if event:
                    self._process_event(event)
            except Exception as e:
                if self._running:
                    logger.error(f"Event error: {e}")
    
    def _process_event(self, event):
        """Process button event from lpminimk3.
        
        Note: lpminimk3 button events report y+1 compared to LED coordinates.
        LEDs use y=0-7, but button events report y=1-8 for the same grid.
        We convert to LED coordinates (y-1) for consistency.
        """
        try:
            if event.button is None:
                return
            
            # Convert button event coordinates to LED coordinates
            # lpminimk3 quirk: button y = LED y + 1
            button_id = ButtonId(x=event.button.x, y=event.button.y - 1)
            
            if event.type == ButtonEvent.PRESS:
                if self._press_callback:
                    logger.debug(f"Button press: {button_id}")
                    self._press_callback(button_id, 127)
            
            elif event.type == ButtonEvent.RELEASE:
                if self._release_callback:
                    logger.debug(f"Button release: {button_id}")
                    self._release_callback(button_id)
                    
        except Exception as e:
            logger.error(f"Error processing event: {e}")
    
    def set_led(self, pad_id: ButtonId, color: int, pulse: bool = False):
        """
        Set LED color for a button.
        
        Handles all button types:
        - Grid (x=0-7, y=0-7): Uses lp.grid.led(x, y)
        - Top row (x=0-7, y=-1): Uses lp.panel.led(x, 0)
        - Scene buttons (x=8, y=0-7): Uses lp.panel.led(8, y+1)
        
        Args:
            pad_id: Button identifier (in our coordinate system)
            color: Launchpad color value (0-127)
            pulse: If True, LED will flash (lpminimk3 uses 'flash' mode for blinking)
        """
        if not self._lp:
            return
        
        # Cache check to avoid redundant updates
        cache_key = (pad_id.x, pad_id.y, pulse)
        if self._led_cache.get(cache_key) == color:
            return
        
        # Clear old cache entry if mode changed
        old_key = (pad_id.x, pad_id.y, not pulse)
        self._led_cache.pop(old_key, None)
        self._led_cache[cache_key] = color
        
        try:
            # lpminimk3 supports 'static' and 'flash' modes
            mode = 'flash' if pulse else 'static'
            
            if pad_id.is_top_row():
                # Top row: y=-1 in our coords → panel.led(x, 0) in lpminimk3
                led = self._lp.panel.led(pad_id.x, 0, mode=mode)
            elif pad_id.is_right_column():
                # Scene buttons: x=8, y=0-7 in our coords → panel.led(8, y+1) in lpminimk3
                led = self._lp.panel.led(8, pad_id.y + 1, mode=mode)
            else:
                # Grid: x=0-7, y=0-7 in our coords → grid.led(x, y) in lpminimk3
                led = self._lp.grid.led(pad_id.x, pad_id.y, mode=mode)
            
            led.color = color
            logger.debug(f"LED {pad_id} → color={color} (mode={mode})")
        except Exception as e:
            logger.error(f"LED error for {pad_id}: {e}")
    
    def clear_all(self):
        """Turn off all LEDs (grid and panel)."""
        if not self._lp:
            return
        
        try:
            self._lp.grid.reset()
            self._lp.panel.reset()
            self._led_cache.clear()
            logger.info("Cleared all LEDs")
        except Exception as e:
            logger.error(f"Clear error: {e}")
    
    def stop(self):
        """Stop listening and disconnect."""
        self._running = False
        
        if self._listen_thread:
            self._listen_thread.join(timeout=2.0)
        
        if self._lp:
            try:
                self.clear_all()
                self._lp.close()
                logger.info("Disconnected from Launchpad")
            except Exception as e:
                logger.error(f"Disconnect error: {e}")
        
        self._lp = None
    
    def is_connected(self) -> bool:
        """Check if connected to Launchpad."""
        return self._lp is not None and self._lp.is_open()
