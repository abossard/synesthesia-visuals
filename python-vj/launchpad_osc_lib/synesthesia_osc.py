"""
Synesthesia OSC Manager

High-level OSC interface with message filtering.
Wraps osc_hub.osc.synesthesia with controllable-message filtering.
"""

import time
import logging
from typing import Callable, List

# Import central OSC hub
import sys as _sys
_sys.path.insert(0, str(__file__).rsplit('/', 2)[0])
from osc_hub import osc

from .model import OscCommand, OscEvent
from .synesthesia_config import (
    is_controllable,
    is_noisy_audio,
    enrich_event,
    BEAT_ADDRESS,
)

logger = logging.getLogger(__name__)


class SynesthesiaOscManager:
    """
    High-level OSC manager for Synesthesia communication.
    
    Features:
    - Wraps osc_hub.osc.synesthesia
    - Separate callbacks for controllable vs all messages
    - Beat pulse tracking for LED sync
    """
    
    def __init__(self):
        self._controllable_listeners: List[Callable[[OscEvent], None]] = []
        self._monitor_listeners: List[Callable[[OscEvent], None]] = []
        self._all_listeners: List[Callable[[OscEvent], None]] = []
        self._beat_pulse: bool = False
        self._running = False
    
    def start(self) -> bool:
        if self._running:
            return True
        osc.start()
        osc.synesthesia.subscribe("/", self._on_osc_raw)
        self._running = True
        return True
    
    def stop(self):
        if self._running:
            osc.synesthesia.unsubscribe("/", self._on_osc_raw)
            self._running = False
    
    def is_connected(self) -> bool:
        return self._running
    
    @property
    def status(self) -> str:
        return "running" if self._running else "stopped"
    
    def add_controllable_listener(self, callback: Callable[[OscEvent], None]):
        if callback not in self._controllable_listeners:
            self._controllable_listeners.append(callback)
    
    def remove_controllable_listener(self, callback: Callable[[OscEvent], None]):
        if callback in self._controllable_listeners:
            self._controllable_listeners.remove(callback)
    
    def add_monitor_listener(self, callback: Callable[[OscEvent], None]):
        if callback not in self._monitor_listeners:
            self._monitor_listeners.append(callback)
    
    def remove_monitor_listener(self, callback: Callable[[OscEvent], None]):
        if callback in self._monitor_listeners:
            self._monitor_listeners.remove(callback)
    
    def add_all_listener(self, callback: Callable[[OscEvent], None]):
        if callback not in self._all_listeners:
            self._all_listeners.append(callback)
    
    def remove_all_listener(self, callback: Callable[[OscEvent], None]):
        if callback in self._all_listeners:
            self._all_listeners.remove(callback)
    
    def send(self, command: OscCommand):
        osc.synesthesia.send(command.address, *command.args)
    
    def send_raw(self, address: str, *args):
        osc.synesthesia.send(address, *args)
    
    def _on_osc_raw(self, path: str, args: list) -> None:
        event = enrich_event(path, list(args), time.time())
        self._dispatch_event(event)
    
    def _dispatch_event(self, event: OscEvent):
        address = event.address
        
        if address == BEAT_ADDRESS:
            self._beat_pulse = bool(event.args[0]) if event.args else False
        
        for callback in self._all_listeners:
            try:
                callback(event)
            except Exception as e:
                logger.error(f"Error in OSC all-listener: {e}")
        
        if not is_noisy_audio(address):
            for callback in self._monitor_listeners:
                try:
                    callback(event)
                except Exception as e:
                    logger.error(f"Error in OSC monitor-listener: {e}")
        
        if is_controllable(address):
            for callback in self._controllable_listeners:
                try:
                    callback(event)
                except Exception as e:
                    logger.error(f"Error in OSC controllable-listener: {e}")
    
    @property
    def beat_pulse(self) -> bool:
        return self._beat_pulse
