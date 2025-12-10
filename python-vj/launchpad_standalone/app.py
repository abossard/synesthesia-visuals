"""
Launchpad Standalone - Main Application

Device-driven learn mode without any TUI dependency.
All interaction happens through the Launchpad LEDs and pads.
"""

import logging
import signal
import threading
from dataclasses import replace
from typing import List, Union

from .model import (
    AppState, LearnState, LearnPhase, ButtonId, OscEvent,
    LedEffect, SendOscEffect, SaveConfigEffect, LogEffect, ControllerConfig,
)
from .launchpad import LaunchpadDevice
from .osc import OscClient, OscConfig
from .display import render_state
from .fsm import (
    handle_pad_press, handle_pad_release, record_osc_event,
    save_from_recording,
)
from .config import save_config, load_config

logger = logging.getLogger(__name__)

Effect = Union[LedEffect, SendOscEffect, SaveConfigEffect, LogEffect]


class StandaloneApp:
    """
    Main application orchestrating Launchpad + OSC.
    
    All state is managed through the FSM.
    This class only handles I/O and effect execution.
    """
    
    def __init__(
        self,
        osc_send_port: int = 7777,
        osc_receive_port: int = 9999,
    ):
        self.launchpad = LaunchpadDevice()
        self.osc = OscClient(OscConfig(
            send_port=osc_send_port,
            receive_port=osc_receive_port,
        ))
        
        self.state = AppState()
        self._running = False
    
    def start(self):
        """Start the application."""
        logger.info("Starting Launchpad Standalone...")
        
        # Load saved config
        config = load_config()
        if config:
            self.state = replace(self.state, config=config)
        else:
            self.state = replace(self.state, config=ControllerConfig())
        
        # Connect devices
        if not self.launchpad.connect():
            logger.error("Failed to connect Launchpad")
            return
        
        # Note: OSC connect is async in the osc module, but we'll handle it gracefully
        try:
            # OscClient might need async, so we'll just set it up
            self.osc.add_callback(self._on_osc_event)
        except Exception as e:
            logger.warning(f"OSC setup warning: {e}")
        
        # Set up callbacks
        self.launchpad.set_callbacks(
            on_press=self._on_pad_press,
            on_release=self._on_pad_release,
        )
        
        # Simple startup: just clear and render
        self.launchpad.clear_all()
        
        # Initial LED render
        self._render_leds()
        
        logger.info("Ready! Press bottom-right scene button to enter learn mode.")
        
        # Start listening (blocking)
        # lpminimk3 handles LED pulsing internally, no need for blink loop
        self._running = True
        self.launchpad.start_listening()
    
    def stop(self):
        """Stop the application."""
        self._running = False
        self.launchpad.stop()
        logger.info("Stopped")

    def _on_pad_press(self, pad_id: ButtonId, velocity: int):
        """Handle pad press from Launchpad."""
        new_state, effects = handle_pad_press(self.state, pad_id)
        self.state = new_state
        self._execute_effects(effects)
        self._render_leds()
    
    def _on_pad_release(self, pad_id: ButtonId):
        """Handle pad release from Launchpad."""
        new_state, effects = handle_pad_release(self.state, pad_id)
        self.state = new_state
        self._execute_effects(effects)
        self._render_leds()
    
    def _on_osc_event(self, event: OscEvent):
        """Handle incoming OSC event."""
        if self.state.learn.phase == LearnPhase.RECORD_OSC:
            new_state, effects = record_osc_event(self.state, event)
            self.state = new_state
            self._execute_effects(effects)
            self._render_leds()
    

    
    def _render_leds(self):
        """Render current state to Launchpad LEDs."""
        effects = render_state(self.state)
        
        for effect in effects:
            if isinstance(effect, LedEffect):
                # Use lpminimk3's built-in pulse feature for blinking
                self.launchpad.set_led(effect.pad_id, effect.color, pulse=effect.blink)
    
    def _execute_effects(self, effects: List[Effect]):
        """Execute side effects."""
        for effect in effects:
            if isinstance(effect, SendOscEffect):
                self.osc.send(effect.command)
            
            elif isinstance(effect, SaveConfigEffect):
                save_config(effect.config)
            
            elif isinstance(effect, LogEffect):
                level = getattr(logging, effect.level, logging.INFO)
                logger.log(level, effect.message)


def main():
    """Main entry point."""
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s [%(levelname)s] %(message)s"
    )
    
    app = StandaloneApp()
    
    # Handle Ctrl+C
    def signal_handler(signum, frame):
        logger.info("Shutting down...")
        app.stop()
        import sys
        sys.exit(0)
    
    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)
    
    try:
        app.start()
    except KeyboardInterrupt:
        logger.info("Interrupted")
    finally:
        app.stop()


if __name__ == "__main__":
    main()
