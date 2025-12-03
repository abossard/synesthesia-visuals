#!/usr/bin/env python3
"""
Example VJ Bus worker.

Demonstrates the worker pattern:
- Publishes dummy telemetry every 100ms
- Responds to standard commands (health_check, get_state, etc.)
- Survives TUI crashes and reconnects

Usage:
    python workers/example_worker.py
"""

import time
import logging
import sys
from pathlib import Path

# Add parent directory to path for imports
sys.path.insert(0, str(Path(__file__).parent.parent))

from vj_bus.worker import WorkerBase
from vj_bus.messages import WorkerStatePayload

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)

logger = logging.getLogger('example_worker')


class ExampleWorker(WorkerBase):
    """
    Example worker for testing VJ Bus architecture.

    Publishes counter telemetry to demonstrate high-frequency messaging.
    """

    def __init__(self):
        super().__init__(
            name="example_worker",
            command_port=5051,
            telemetry_port=5052,
            config={"publish_interval": 0.1}  # 100ms = 10 Hz
        )

        self.counter = 0

    def run(self):
        """Main loop - publish counter telemetry."""
        logger.info("Example worker running")

        publish_interval = self.config.get("publish_interval", 0.1)

        while self.running:
            # Increment counter
            self.counter += 1

            # Publish telemetry
            self.publish_telemetry("example.counter", {
                "counter": self.counter,
                "timestamp": time.time()
            })

            # Sleep
            time.sleep(publish_interval)

        logger.info("Example worker loop exited")

    def get_state(self) -> WorkerStatePayload:
        """Return current state."""
        return WorkerStatePayload(
            status="running" if self.running else "stopped",
            uptime_sec=time.time() - self.started_at,
            config=self.config,
            metrics={
                "counter": self.counter,
                "messages_published": self.counter
            }
        )

    def get_metadata(self) -> dict:
        """Return metadata for registry."""
        return {
            "version": "1.0",
            "counter": self.counter
        }

    def on_config_change(self, new_config: dict) -> bool:
        """Handle config updates."""
        if "publish_interval" in new_config:
            logger.info(f"Updated publish_interval to {new_config['publish_interval']}")
            # No restart required for this change
            return False
        return False


def main():
    """Entry point."""
    worker = ExampleWorker()

    logger.info("=" * 60)
    logger.info("Example Worker Starting")
    logger.info("=" * 60)
    logger.info(f"PID: {worker.pid}")
    logger.info(f"Command port: {worker.command_port}")
    logger.info(f"Telemetry port: {worker.telemetry_port}")
    logger.info("=" * 60)

    try:
        worker.start()
    except Exception as e:
        logger.exception(f"Worker failed: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
