"""
Launchpad Standalone - Main Application

Device-driven learn mode without any TUI dependency.
All interaction happens through the Launchpad LEDs and pads.
"""

import asyncio
import logging
import signal
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
    save_from_recording, toggle_blink,
)
from .config import save_config, load_config
from launchpad_osc_lib.demo import run_startup_demo

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
        self._blink_task = None
    
    async def start(self):
        """Start the application."""
        logger.info("Starting Launchpad Standalone...")
        
        # Load saved config
        config = load_config()
        if config:
            self.state = replace(self.state, config=config)
        else:
            self.state = replace(self.state, config=ControllerConfig())
        
        # Connect devices
        if not await self.launchpad.connect():
            logger.error("Failed to connect Launchpad")
            return
        
        if not await self.osc.connect():
            logger.warning("OSC not connected - continuing without OSC")
        
        # Set up callbacks
        self.launchpad.set_callbacks(
            on_press=self._on_pad_press,
            on_release=self._on_pad_release,
        )
        self.osc.add_callback(self._on_osc_event)
        
        # Run startup demo
        await self._run_startup_demo()
        
        # Initial LED render
        self._render_leds()
        
        # Start blink animation
        self._blink_task = asyncio.create_task(self._blink_loop())
        
        # Start listening
        self._running = True
        logger.info("Ready! Press bottom-right scene button to enter learn mode.")
        
        await self.launchpad.start_listening()
    
    async def stop(self):
        """Stop the application."""
        self._running = False
        
        if self._blink_task:
            self._blink_task.cancel()
        
        await self.launchpad.stop()
        await self.osc.stop()
        
        logger.info("Stopped")
    
    async def _run_startup_demo(self):
        """Run a brief startup demo to show the device is connected."""
        await run_startup_demo(self.launchpad)

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
    
    async def _blink_loop(self):
        """Blink animation loop (200ms interval)."""
        while self._running:
            await asyncio.sleep(0.2)
            
            # Only update if in a blinking phase
            phase = self.state.learn.phase
            if phase in (LearnPhase.WAIT_PAD, LearnPhase.RECORD_OSC):
                self.state = toggle_blink(self.state)
                self._render_leds()
    
    def _render_leds(self):
        """Render current state to Launchpad LEDs."""
        effects = render_state(self.state)
        
        for effect in effects:
            if isinstance(effect, LedEffect):
                self.launchpad.set_led(effect.pad_id, effect.color)
    
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


async def main():
    """Main entry point."""
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s [%(levelname)s] %(message)s"
    )
    
    app = StandaloneApp()
    
    # Handle Ctrl+C
    loop = asyncio.get_event_loop()
    
    def signal_handler():
        logger.info("Shutting down...")
        asyncio.create_task(app.stop())
    
    loop.add_signal_handler(signal.SIGINT, signal_handler)
    loop.add_signal_handler(signal.SIGTERM, signal_handler)
    
    try:
        await app.start()
    except asyncio.CancelledError:
        pass
    finally:
        await app.stop()


if __name__ == "__main__":
    asyncio.run(main())
