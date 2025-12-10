"""
Launchpad Mini Mk3 Driver using lpminimk3

Thin wrapper around lpminimk3 for the standalone app.
"""

import logging
import threading
from typing import Optional, Callable

from .model import ButtonId

try:
    import lpminimk3
    from lpminimk3 import LaunchpadMiniMk3, Mode, ButtonEvent
    LPMINIMK3_AVAILABLE = True
except ImportError:
    LPMINIMK3_AVAILABLE = False
    lpminimk3 = None
    LaunchpadMiniMk3 = None
    Mode = None
    ButtonEvent = None

logger = logging.getLogger(__name__)


class LaunchpadDevice:
    """
    Launchpad Mini Mk3 driver using lpminimk3.
    
    Provides simple synchronous interface compatible with the standalone app.
    """
    
    def __init__(self):
        self._lp: Optional[LaunchpadMiniMk3] = None
        self._running = False
        self._press_callback: Optional[Callable[[ButtonId, int], None]] = None
        self._release_callback: Optional[Callable[[ButtonId], None]] = None
        self._listen_thread: Optional[threading.Thread] = None
        self._led_cache: dict = {}
    
    def connect(self) -> bool:
        """Connect to Launchpad and enter Programmer mode."""
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
        """Set button press/release callbacks."""
        self._press_callback = on_press
        self._release_callback = on_release
    
    def start_listening(self):
        """Start listening for button events (blocking)."""
        if not self._lp:
            logger.error("Not connected to Launchpad")
            return
        
        self._running = True
        logger.info("Listening for Launchpad input")
        
        # Start in a separate thread to not block
        self._listen_thread = threading.Thread(target=self._listen_loop, daemon=True)
        self._listen_thread.start()
        
        # Keep main thread alive
        try:
            while self._running:
                threading.Event().wait(1)
        except KeyboardInterrupt:
            logger.info("Interrupted")
            self.stop()
    
    def _listen_loop(self):
        """Event polling loop."""
        while self._running:
            try:
                event = self._lp.panel.buttons().poll_for_event(timeout=0.1)
                if event:
                    self._process_event(event)
            except Exception as e:
                if self._running:
                    logger.error(f"Event error: {e}")
    
    def _process_event(self, event):
        """Process button event from lpminimk3."""
        try:
            button_id = ButtonId(x=event.button.x, y=event.button.y)
            
            if event.type == ButtonEvent.PRESS:
                if self._press_callback:
                    logger.info(f"Button press: {button_id}")
                    self._press_callback(button_id, 127)  # lpminimk3 doesn't provide velocity
            
            elif event.type == ButtonEvent.RELEASE:
                if self._release_callback:
                    logger.info(f"Button release: {button_id}")
                    self._release_callback(button_id)
                    
        except Exception as e:
            logger.error(f"Error processing event: {e}")
    
    def set_led(self, pad_id: ButtonId, color: int, pulse: bool = False):
        """
        Set LED color for a button.
        
        Args:
            pad_id: Button identifier
            color: Color value (0-127)
            pulse: If True, LED will pulse/breathe
        """
        if not self._lp:
            return
        
        # Check cache to avoid redundant updates (include pulse in cache key)
        cache_key = (pad_id.x, pad_id.y, pulse)
        if self._led_cache.get(cache_key) == color:
            return
        # Clear old cache entry if mode changed
        old_key = (pad_id.x, pad_id.y, not pulse)
        self._led_cache.pop(old_key, None)
        self._led_cache[cache_key] = color
        
        try:
            # Get LED with appropriate mode
            mode = lpminimk3.Led.PULSE if pulse else lpminimk3.Led.STATIC
            led = self._lp.grid.led(pad_id.x, pad_id.y, mode=mode)
            led.color = color
            logger.debug(f"LED {pad_id} → color={color} (pulse={pulse})")
        except Exception as e:
            logger.error(f"LED error for {pad_id}: {e}")
    
    def clear_all(self):
        """Turn off all LEDs."""
        if not self._lp:
            return
        
        try:
            self._lp.grid.reset()
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
