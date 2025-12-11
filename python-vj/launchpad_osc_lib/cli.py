"""
Launchpad OSC Library - CLI Application

Device-driven learn mode without any TUI dependency.
All interaction happens through the Launchpad LEDs and pads.

Usage:
    python -m launchpad_osc_lib
    python -m launchpad_osc_lib --send-port 7777 --receive-port 9999
"""

import argparse
import logging
import signal
import sys
from dataclasses import replace
from typing import List, Union

from .button_id import ButtonId
from .model import (
    ControllerState, LearnPhase, OscEvent,
    LedEffect, SendOscEffect, SaveConfigEffect, LogEffect,
)
from .launchpad_device import LaunchpadDevice
from .osc_sync import SyncOscClient
from .display import render_state
from .fsm import handle_pad_press, handle_pad_release, handle_osc_event
from .config import save_config, load_config

logger = logging.getLogger(__name__)

Effect = Union[LedEffect, SendOscEffect, SaveConfigEffect, LogEffect]


class LaunchpadApp:
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
        self.osc = SyncOscClient(
            send_port=osc_send_port,
            receive_port=osc_receive_port,
        )
        
        self.state = ControllerState()
        self._running = False
    
    def start(self):
        """Start the application."""
        logger.info("Starting Launchpad OSC Controller...")
        
        # Load saved config
        pads = load_config()
        if pads:
            self.state = replace(self.state, pads=pads)
        
        # Connect devices
        if not self.launchpad.connect():
            logger.error("Failed to connect Launchpad")
            return
        
        # Start OSC
        if self.osc.start():
            self.osc.add_callback(self._on_osc_event)
        else:
            logger.warning("OSC not available - continuing without OSC")
        
        # Set up Launchpad callbacks
        self.launchpad.set_callbacks(
            on_press=self._on_pad_press,
            on_release=self._on_pad_release,
        )
        
        # Clear and render initial state
        self.launchpad.clear_all()
        self._render_leds()
        
        logger.info("Ready! Press bottom-right scene button to enter learn mode.")
        
        # Start listening (blocking)
        self._running = True
        self.launchpad.start_listening()
    
    def stop(self):
        """Stop the application."""
        self._running = False
        self.osc.stop()
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
        # Only process during OSC recording
        if self.state.learn_state.phase == LearnPhase.RECORD_OSC:
            new_state, effects = handle_osc_event(self.state, event)
            self.state = new_state
            self._execute_effects(effects)
            self._render_leds()
    
    def _render_leds(self):
        """Render current state to Launchpad LEDs."""
        effects = render_state(self.state)
        
        for effect in effects:
            if isinstance(effect, LedEffect):
                # Use lpminimk3's built-in pulse for blinking
                self.launchpad.set_led(effect.pad_id, effect.color, pulse=effect.blink)
    
    def _execute_effects(self, effects: List[Effect]):
        """Execute side effects."""
        for effect in effects:
            if isinstance(effect, SendOscEffect):
                self.osc.send(effect.command)
            
            elif isinstance(effect, SaveConfigEffect):
                save_config(self.state)
            
            elif isinstance(effect, LogEffect):
                level = getattr(logging, effect.level, logging.INFO)
                logger.log(level, effect.message)


def main():
    """Main entry point."""
    parser = argparse.ArgumentParser(
        description="Launchpad OSC Controller - Device-driven configuration"
    )
    parser.add_argument(
        "--send-port", type=int, default=7777,
        help="OSC send port (default: 7777)"
    )
    parser.add_argument(
        "--receive-port", type=int, default=9999,
        help="OSC receive port (default: 9999)"
    )
    parser.add_argument(
        "-v", "--verbose", action="store_true",
        help="Enable verbose logging"
    )
    
    args = parser.parse_args()
    
    # Configure logging
    level = logging.DEBUG if args.verbose else logging.INFO
    logging.basicConfig(
        level=level,
        format="%(asctime)s [%(levelname)s] %(message)s"
    )
    
    app = LaunchpadApp(
        osc_send_port=args.send_port,
        osc_receive_port=args.receive_port,
    )
    
    # Handle Ctrl+C
    def signal_handler(signum, frame):
        logger.info("Shutting down...")
        app.stop()
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
