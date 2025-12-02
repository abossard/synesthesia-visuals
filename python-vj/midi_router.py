#!/usr/bin/env python3
"""
MIDI Router Orchestrator

Coordinates MIDI device management, toggle state, and message routing.
Follows dependency injection pattern for testability.
"""

import json
import logging
from pathlib import Path
from typing import Optional, Callable
from threading import Lock

from midi_domain import (
    RouterConfig, ToggleConfig, MidiMessage,
    should_enhance_message, process_toggle, 
    create_state_sync_messages, config_to_dict, config_from_dict
)
from midi_infrastructure import MidiDeviceManager

logger = logging.getLogger('midi_router')


# =============================================================================
# CONFIG PERSISTENCE
# =============================================================================

class ConfigManager:
    """
    Manages persistent router configuration.
    
    Handles loading/saving config from JSON file.
    """
    
    def __init__(self, config_path: Path):
        """
        Initialize config manager.
        
        Args:
            config_path: Path to JSON config file
        """
        self._config_path = config_path
        self._config_path.parent.mkdir(parents=True, exist_ok=True)
    
    def load(self) -> Optional[RouterConfig]:
        """
        Load configuration from file.
        
        Returns:
            RouterConfig or None if file doesn't exist or is invalid
        """
        if not self._config_path.exists():
            logger.info(f"No config file found at {self._config_path}")
            return None
        
        try:
            with open(self._config_path, 'r') as f:
                data = json.load(f)
            
            config = config_from_dict(data)
            logger.info(f"Loaded config with {len(config.toggles)} toggles")
            return config
            
        except Exception as e:
            logger.error(f"Failed to load config: {e}")
            return None
    
    def save(self, config: RouterConfig):
        """
        Save configuration to file.
        
        Args:
            config: RouterConfig to save
        """
        try:
            data = config_to_dict(config)
            
            with open(self._config_path, 'w') as f:
                json.dump(data, f, indent=2)
            
            logger.info(f"Saved config with {len(config.toggles)} toggles")
            
        except Exception as e:
            logger.error(f"Failed to save config: {e}")


# =============================================================================
# MIDI ROUTER - Main orchestrator
# =============================================================================

class MidiRouter:
    """
    Main MIDI router orchestrator.
    
    Coordinates:
    - Device discovery and connection
    - Toggle state management
    - Message routing (controller -> LED, controller -> Magic)
    - Config persistence
    
    Dependency injection: Accepts ConfigManager and MidiDeviceManager
    for testability.
    """
    
    def __init__(
        self,
        config_manager: ConfigManager,
        device_manager: Optional[MidiDeviceManager] = None
    ):
        """
        Initialize MIDI router.
        
        Args:
            config_manager: ConfigManager instance
            device_manager: MidiDeviceManager instance (creates if None)
        """
        self._config_manager = config_manager
        self._device_manager = device_manager or MidiDeviceManager()
        
        # State
        self._config: Optional[RouterConfig] = None
        self._config_lock = Lock()
        self._running = False
        self._learn_mode = False
        self._learn_callback: Optional[Callable[[int, str], None]] = None
    
    @property
    def is_running(self) -> bool:
        """Check if router is running."""
        return self._running
    
    @property
    def is_learn_mode(self) -> bool:
        """Check if learn mode is active."""
        return self._learn_mode
    
    @property
    def config(self) -> Optional[RouterConfig]:
        """Get current configuration (thread-safe)."""
        with self._config_lock:
            return self._config
    
    def start(self, config: RouterConfig) -> bool:
        """
        Start the MIDI router.
        
        Args:
            config: RouterConfig to use
        
        Returns:
            True if successful
        """
        if self._running:
            logger.warning("Router already running")
            return False
        
        logger.info("Starting MIDI router...")
        
        # Store config
        with self._config_lock:
            self._config = config
        
        # Connect to devices
        # Output 0: Controller LED feedback
        # Output 1: Virtual port to Magic
        success = True
        
        # Connect input (controller)
        if not self._device_manager.connect_input(config.controller):
            logger.error("Failed to connect controller input")
            success = False
        
        # Connect outputs (controller LED, virtual output)
        if not self._device_manager.connect_outputs([
            config.controller,  # For LED feedback
            config.virtual_output  # For Magic
        ]):
            logger.error("Failed to connect outputs")
            success = False
        
        if not success:
            self._device_manager.close_all()
            return False
        
        # Set up message callback
        self._device_manager.set_input_callback(self._on_midi_message)
        
        # Sync all toggle states (send to LEDs and Magic)
        self._sync_all_toggles()
        
        self._running = True
        logger.info("MIDI router started successfully")
        return True
    
    def stop(self):
        """Stop the MIDI router."""
        if not self._running:
            return
        
        logger.info("Stopping MIDI router...")
        
        self._running = False
        self._device_manager.close_all()
        
        # Save final state
        if self._config:
            self._config_manager.save(self._config)
        
        logger.info("MIDI router stopped")
    
    def _sync_all_toggles(self):
        """Send sync messages for all toggles (on startup)."""
        if not self._config:
            return
        
        logger.info("Syncing all toggle states...")
        
        messages = create_state_sync_messages(self._config)
        
        for led_msg, output_msg in messages:
            # Send to controller LED
            self._device_manager.send_to_output(0, led_msg)
            
            # Send to Magic
            self._device_manager.send_to_output(1, output_msg)
        
        logger.info(f"Synced {len(messages)} toggles")
    
    def _on_midi_message(self, msg: MidiMessage):
        """
        Handle incoming MIDI message from controller.
        
        Args:
            msg: MidiMessage from controller
        """
        if not self._running:
            return
        
        # Learn mode: capture next message
        if self._learn_mode and msg.is_note_on:
            self._handle_learn_message(msg)
            return
        
        # Get current config
        with self._config_lock:
            if not self._config:
                return
            
            config = self._config
        
        # Check if this is a toggle message
        if should_enhance_message(msg, config):
            self._handle_toggle_message(msg)
        else:
            # Pass-through: forward to Magic unchanged
            self._device_manager.send_to_output(1, msg)
    
    def _handle_toggle_message(self, msg: MidiMessage):
        """
        Handle a toggle button press.
        
        Args:
            msg: MidiMessage (note on for a configured toggle)
        """
        with self._config_lock:
            if not self._config:
                return
            
            # Process toggle (pure function)
            new_config, led_msg, output_msg = process_toggle(msg, self._config)
            
            # Update config
            self._config = new_config
            
            # Log state change
            toggle = new_config.get_toggle(msg.note_or_cc)
            if toggle:
                state_str = "ON" if toggle.state else "OFF"
                logger.info(f"Toggle {toggle.name} (note {toggle.note_or_cc}): {state_str}")
        
        # Send LED feedback to controller
        self._device_manager.send_to_output(0, led_msg)
        
        # Send absolute state to Magic
        self._device_manager.send_to_output(1, output_msg)
        
        # Auto-save config (with updated states)
        self._config_manager.save(self._config)
    
    def _handle_learn_message(self, msg: MidiMessage):
        """
        Handle message in learn mode.
        
        Args:
            msg: MidiMessage (note on) to learn
        """
        logger.info(f"Learn mode: captured {msg}")
        
        # Create new toggle with default name
        new_toggle = ToggleConfig(
            note_or_cc=msg.note_or_cc,
            name=f"Toggle_{msg.note_or_cc}",
            state=False,
            message_type='note'
        )
        
        # Add to config
        with self._config_lock:
            if self._config:
                self._config = self._config.with_toggle(new_toggle)
                self._config_manager.save(self._config)
        
        # Turn off LED initially
        led_msg = MidiMessage(
            message_type=msg.message_type,
            channel=msg.channel,
            note_or_cc=msg.note_or_cc,
            velocity_or_value=0
        )
        self._device_manager.send_to_output(0, led_msg)
        
        # Notify callback
        if self._learn_callback:
            self._learn_callback(msg.note_or_cc, new_toggle.name)
        
        # Exit learn mode
        self._learn_mode = False
        logger.info(f"Added toggle {new_toggle.name} (note {msg.note_or_cc})")
    
    def enter_learn_mode(self, callback: Optional[Callable[[int, str], None]] = None):
        """
        Enter learn mode for next MIDI message.
        
        Args:
            callback: Optional callback(note, name) called when toggle is learned
        """
        self._learn_mode = True
        self._learn_callback = callback
        logger.info("Entered learn mode - press a pad to learn")
    
    def exit_learn_mode(self):
        """Exit learn mode without learning."""
        self._learn_mode = False
        self._learn_callback = None
        logger.info("Exited learn mode")
    
    def set_toggle_name(self, note_or_cc: int, name: str) -> bool:
        """
        Set the name of a toggle.
        
        Args:
            note_or_cc: Note/CC number
            name: New name
        
        Returns:
            True if successful
        """
        with self._config_lock:
            if not self._config:
                return False
            
            toggle = self._config.get_toggle(note_or_cc)
            if not toggle:
                logger.warning(f"No toggle found for note {note_or_cc}")
                return False
            
            # Update toggle name
            new_toggle = ToggleConfig(
                note_or_cc=toggle.note_or_cc,
                name=name,
                state=toggle.state,
                message_type=toggle.message_type,
                led_on_velocity=toggle.led_on_velocity,
                led_off_velocity=toggle.led_off_velocity,
                output_on_velocity=toggle.output_on_velocity,
                output_off_velocity=toggle.output_off_velocity,
            )
            
            self._config = self._config.with_toggle(new_toggle)
            self._config_manager.save(self._config)
            
            logger.info(f"Renamed toggle {note_or_cc} to '{name}'")
            return True
    
    def remove_toggle(self, note_or_cc: int) -> bool:
        """
        Remove a toggle from configuration.
        
        Args:
            note_or_cc: Note/CC number to remove
        
        Returns:
            True if successful
        """
        with self._config_lock:
            if not self._config:
                return False
            
            if not self._config.has_toggle(note_or_cc):
                logger.warning(f"No toggle found for note {note_or_cc}")
                return False
            
            # Create new toggles dict without this one
            new_toggles = {
                k: v for k, v in self._config.toggles.items()
                if k != note_or_cc
            }
            
            self._config = RouterConfig(
                controller=self._config.controller,
                virtual_output=self._config.virtual_output,
                toggles=new_toggles
            )
            
            self._config_manager.save(self._config)
            
            logger.info(f"Removed toggle {note_or_cc}")
            return True
    
    def get_toggle_list(self) -> list[tuple[int, str, bool]]:
        """
        Get list of all toggles.
        
        Returns:
            List of (note, name, state) tuples
        """
        with self._config_lock:
            if not self._config:
                return []
            
            return [
                (toggle.note_or_cc, toggle.name, toggle.state)
                for toggle in self._config.toggles.values()
            ]
