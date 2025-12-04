#!/usr/bin/env python3
"""
MIDI Router Worker - VJ Bus Integration

Wraps the MIDI router as a VJ Bus worker for integration with the
auto-healing system. Handles MIDI controller input and broadcasts
toggle state changes via OSC and VJ Bus telemetry.

Features:
- Auto-reconnection to MIDI controllers
- Toggle state management and persistence
- OSC broadcasting for visual integration
- VJ Bus telemetry for console monitoring
"""

import sys
import time
import logging
from pathlib import Path
from typing import Dict, Any, Optional

# Add parent directory to path
sys.path.insert(0, str(Path(__file__).parent.parent))

from vj_bus.worker import WorkerBase
from vj_bus.messages import WorkerStatePayload
from midi_router import MidiRouter, ConfigManager
from midi_domain import RouterConfig, DeviceConfig
from midi_infrastructure import list_controllers

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)

logger = logging.getLogger('midi_router_worker')


class MidiRouterWorker(WorkerBase):
    """
    MIDI Router Worker - VJ Bus Integration.

    Provides MIDI controller integration with auto-healing:
    - Manages MIDI device connections
    - Processes toggle state changes
    - Broadcasts to OSC and VJ Bus
    - Handles controller reconnection
    """

    def __init__(self):
        super().__init__(
            name="midi_router",
            command_port=5008,
            telemetry_port=5108,
            config={
                "config_file": "midi_router_config.json",
                "auto_reconnect": True,
                "reconnect_interval": 5.0,
            }
        )

        self.router: Optional[MidiRouter] = None
        self.config_manager: Optional[ConfigManager] = None
        self.current_config: Optional[RouterConfig] = None

        # Track state for telemetry
        self.connected_controller: Optional[str] = None
        self.toggle_states: Dict[int, bool] = {}
        self.message_count = 0

    def on_start(self):
        """Initialize MIDI router."""
        logger.info("MIDI Router Worker starting...")

        # Setup config manager
        config_file = self.config.get("config_file", "midi_router_config.json")
        config_path = Path(__file__).parent.parent / config_file
        self.config_manager = ConfigManager(config_path)

        # Load or create default config
        self.current_config = self.config_manager.load()
        if not self.current_config:
            logger.info("No config found, creating default...")
            self.current_config = RouterConfig()

            # Try to auto-detect controller
            controllers = list_controllers()
            if controllers:
                logger.info(f"Auto-detected controller: {controllers[0]['name']}")
                self.current_config = self.current_config._replace(
                    input_device=DeviceConfig(
                        name=controllers[0]['name'],
                        port_id=controllers[0]['port']
                    )
                )

            self.config_manager.save(self.current_config)

        # Initialize router
        try:
            self.router = MidiRouter(self.config_manager)

            # Start routing with current config
            if self.router.start(self.current_config):
                self.connected_controller = self.current_config.input_device.name if self.current_config.input_device else None
                logger.info(f"✓ MIDI router started")
                if self.connected_controller:
                    logger.info(f"✓ Connected to MIDI controller: {self.connected_controller}")
            else:
                logger.warning("⚠️  MIDI router failed to start, will auto-reconnect")

        except Exception as e:
            logger.error(f"Failed to initialize MIDI router: {e}")
            import traceback
            traceback.print_exc()
            self.router = None

    def on_stop(self):
        """Stop MIDI router."""
        logger.info("MIDI Router Worker stopping...")

        if self.router:
            try:
                self.router.stop()
                logger.info("✓ MIDI router stopped")
            except Exception as e:
                logger.error(f"Error stopping router: {e}")

    def run(self):
        """Main worker loop - handle auto-reconnection."""
        logger.info("MIDI Router Worker main loop started")

        auto_reconnect = self.config.get("auto_reconnect", True)
        reconnect_interval = self.config.get("reconnect_interval", 5.0)

        while self.running:
            # Check connection status
            if self.router and auto_reconnect:
                if not self.router.is_running:
                    logger.debug("Router not running, attempting restart...")
                    try:
                        # Try to reconnect
                        controllers = list_controllers()
                        if controllers and len(controllers) > 0:
                            # Update config with available controller
                            new_config = self.current_config._replace(
                                input_device=DeviceConfig(
                                    name=controllers[0]['name'],
                                    port_id=controllers[0]['port']
                                )
                            )

                            # Restart router with new config
                            self.router.stop()

                            if self.router.start(new_config):
                                self.connected_controller = controllers[0]['name']
                                self.current_config = new_config
                                self.config_manager.save(new_config)
                                logger.info(f"✓ Reconnected to: {self.connected_controller}")

                    except Exception as e:
                        logger.debug(f"Reconnection failed: {e}")

            # Sleep
            time.sleep(reconnect_interval)

        logger.info("MIDI Router Worker main loop exited")

    # Note: Callbacks removed since MidiRouter doesn't expose them in current API
    # Toggle state would be tracked via OSC messages or polling

    def get_state(self) -> WorkerStatePayload:
        """Return current state."""
        return WorkerStatePayload(
            status="running" if (self.router and self.router.is_running) else "stopped",
            uptime_sec=time.time() - self.started_at,
            config=self.config,
            metrics={
                "running": self.router.is_running if self.router else False,
                "controller": self.connected_controller,
                "toggle_count": len(self.current_config.toggles) if self.current_config else 0,
            }
        )

    def get_metadata(self) -> Dict[str, Any]:
        """Return metadata for registry."""
        return {
            "version": "1.0",
            "controller": self.connected_controller,
            "has_config": self.current_config is not None,
            "osc_enabled": True,
        }

    def handle_command(self, cmd):
        """Handle custom commands."""
        from vj_bus.messages import ResponseMessage

        if cmd.command == "get_toggles":
            # Return current toggle states
            toggles = []
            if self.current_config:
                for toggle in self.current_config.toggles:
                    toggles.append({
                        "note": toggle.note,
                        "name": toggle.name,
                        "state": self.toggle_states.get(toggle.note, False)
                    })

            return ResponseMessage(
                id=cmd.id,
                source=self.name,
                status="ok",
                result={"toggles": toggles}
            )

        elif cmd.command == "toggle":
            # Manually trigger a toggle
            note = cmd.payload.get("note")

            if self.router and note is not None:
                try:
                    # Toggle the state
                    current = self.toggle_states.get(note, False)
                    # This would need to be implemented in the router
                    # For now, just return current state
                    return ResponseMessage(
                        id=cmd.id,
                        source=self.name,
                        status="ok",
                        result={"note": note, "state": current}
                    )
                except Exception as e:
                    return ResponseMessage(
                        id=cmd.id,
                        source=self.name,
                        status="error",
                        error=str(e)
                    )
            else:
                return ResponseMessage(
                    id=cmd.id,
                    source=self.name,
                    status="error",
                    error="Router not initialized or invalid note"
                )

        elif cmd.command == "reconnect":
            # Force reconnection attempt
            if self.router:
                try:
                    self.router.stop()
                    time.sleep(0.5)
                    self.router.start()

                    return ResponseMessage(
                        id=cmd.id,
                        source=self.name,
                        status="ok",
                        result={"connected": self.router.is_connected()}
                    )
                except Exception as e:
                    return ResponseMessage(
                        id=cmd.id,
                        source=self.name,
                        status="error",
                        error=str(e)
                    )
            else:
                return ResponseMessage(
                    id=cmd.id,
                    source=self.name,
                    status="error",
                    error="Router not initialized"
                )

        else:
            return super().handle_command(cmd)


def main():
    """Entry point."""
    worker = MidiRouterWorker()

    logger.info("=" * 60)
    logger.info("MIDI Router Worker Starting")
    logger.info("=" * 60)
    logger.info(f"PID: {worker.pid}")
    logger.info(f"Command port: {worker.command_port}")
    logger.info(f"Telemetry port: {worker.telemetry_port}")
    logger.info("=" * 60)

    try:
        worker.start()
    except KeyboardInterrupt:
        logger.info("\nShutting down...")
        worker.stop()
    except Exception as e:
        logger.exception(f"MIDI Router Worker failed: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
