#!/usr/bin/env python3
"""
OSC Debugger Worker - Captures and logs OSC messages.

Listens for all OSC traffic and publishes messages for debugging.

Usage:
    python workers/osc_debugger_worker.py
"""

import time
import logging
import sys
from pathlib import Path
from typing import Dict, Any
from collections import deque

# Add parent directory to path
sys.path.insert(0, str(Path(__file__).parent.parent))

from vj_bus.worker import WorkerBase
from vj_bus.messages import WorkerStatePayload

# OSC imports
try:
    from pythonosc import dispatcher, osc_server
    import threading
    OSC_AVAILABLE = True
except ImportError:
    OSC_AVAILABLE = False

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)

logger = logging.getLogger('osc_debugger_worker')


class OSCDebuggerWorker(WorkerBase):
    """
    OSC message debugger worker.

    Captures all OSC messages and publishes them for debugging.
    """

    def __init__(self):
        super().__init__(
            name="osc_debugger",
            command_port=5041,
            telemetry_port=5042,
            config={
                "osc_port": 9000,
                "buffer_size": 100,
                "publish_interval": 0.5,
            }
        )

        if not OSC_AVAILABLE:
            raise RuntimeError("OSC not available (missing python-osc)")

        self.osc_server = None
        self.server_thread = None
        self.message_buffer = deque(maxlen=self.config.get("buffer_size", 100))
        self.message_count = 0

    def on_start(self):
        """Start OSC server."""
        logger.info("Starting OSC debugger...")

        osc_port = self.config.get("osc_port", 9000)

        # Create dispatcher that captures all messages
        disp = dispatcher.Dispatcher()
        disp.set_default_handler(self._osc_handler)

        # Start server
        self.osc_server = osc_server.ThreadingOSCUDPServer(
            ("127.0.0.1", osc_port),
            disp
        )

        self.server_thread = threading.Thread(
            target=self.osc_server.serve_forever,
            daemon=True
        )
        self.server_thread.start()

        logger.info(f"OSC debugger listening on port {osc_port}")

    def on_stop(self):
        """Stop OSC server."""
        if self.osc_server:
            logger.info("Stopping OSC server...")
            self.osc_server.shutdown()

    def run(self):
        """Main loop - publish captured messages periodically."""
        logger.info("OSC debugger worker running")

        publish_interval = self.config.get("publish_interval", 0.5)

        while self.running:
            # Publish recent messages
            if self.message_buffer:
                messages = list(self.message_buffer)
                self.publish_telemetry("osc.messages", {
                    "messages": messages,
                    "total_count": self.message_count,
                })

            time.sleep(publish_interval)

        logger.info("OSC debugger worker loop exited")

    def _osc_handler(self, address: str, *args):
        """OSC message handler (called from OSC server thread)."""
        self.message_count += 1

        # Add to buffer
        self.message_buffer.append({
            "timestamp": time.time(),
            "address": address,
            "args": list(args),
        })

    def get_state(self) -> WorkerStatePayload:
        """Return current state."""
        return WorkerStatePayload(
            status="running" if self.running else "stopped",
            uptime_sec=time.time() - self.started_at,
            config=self.config,
            metrics={
                "total_messages": self.message_count,
                "buffer_size": len(self.message_buffer),
            }
        )

    def get_metadata(self) -> Dict[str, Any]:
        """Return metadata for registry."""
        return {
            "version": "1.0",
            "osc_port": self.config.get("osc_port", 9000),
        }


def main():
    """Entry point."""
    if not OSC_AVAILABLE:
        logger.error("OSC not available (install python-osc)")
        sys.exit(1)

    worker = OSCDebuggerWorker()

    logger.info("=" * 60)
    logger.info("OSC Debugger Worker Starting")
    logger.info("=" * 60)
    logger.info(f"PID: {worker.pid}")
    logger.info(f"OSC Port: {worker.config['osc_port']}")
    logger.info("=" * 60)

    try:
        worker.start()
    except Exception as e:
        logger.exception(f"Worker failed: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
