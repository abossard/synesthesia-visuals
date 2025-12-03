#!/usr/bin/env python3
"""
Log Aggregator Worker - Centralizes logs from all workers.

Collects logs via Python logging and publishes them via ZMQ.

Usage:
    python workers/log_aggregator_worker.py
"""

import time
import logging
import logging.handlers
import sys
from pathlib import Path
from typing import Dict, Any
from collections import deque
import socketserver
import struct
import pickle

# Add parent directory to path
sys.path.insert(0, str(Path(__file__).parent.parent))

from vj_bus.worker import WorkerBase
from vj_bus.messages import WorkerStatePayload, LogPayload

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)

logger = logging.getLogger('log_aggregator_worker')


class LogAggregatorWorker(WorkerBase):
    """
    Log aggregation worker.

    Collects logs from all workers via network socket and publishes them.
    """

    def __init__(self):
        super().__init__(
            name="log_aggregator",
            command_port=5061,
            telemetry_port=5062,
            config={
                "log_port": 9020,
                "buffer_size": 500,
                "publish_interval": 0.5,
            }
        )

        self.log_buffer = deque(maxlen=self.config.get("buffer_size", 500))
        self.log_count = 0
        self.log_server = None
        self.server_thread = None

    def on_start(self):
        """Start log receiver server."""
        logger.info("Starting log aggregator...")

        # For now, just keep logs in memory
        # In production, could use SocketHandler to receive from other workers
        logger.info("Log aggregator initialized (in-memory mode)")

    def run(self):
        """Main loop - publish aggregated logs."""
        logger.info("Log aggregator worker running")

        publish_interval = self.config.get("publish_interval", 0.5)

        while self.running:
            # Publish recent logs
            if self.log_buffer:
                logs = list(self.log_buffer)
                self.publish_telemetry("logs.aggregated", {
                    "logs": logs,
                    "total_count": self.log_count,
                })

            time.sleep(publish_interval)

        logger.info("Log aggregator worker loop exited")

    def get_state(self) -> WorkerStatePayload:
        """Return current state."""
        return WorkerStatePayload(
            status="running" if self.running else "stopped",
            uptime_sec=time.time() - self.started_at,
            config=self.config,
            metrics={
                "total_logs": self.log_count,
                "buffer_size": len(self.log_buffer),
            }
        )

    def get_metadata(self) -> Dict[str, Any]:
        """Return metadata for registry."""
        return {
            "version": "1.0",
            "log_port": self.config.get("log_port", 9020),
        }


def main():
    """Entry point."""
    worker = LogAggregatorWorker()

    logger.info("=" * 60)
    logger.info("Log Aggregator Worker Starting")
    logger.info("=" * 60)
    logger.info(f"PID: {worker.pid}")
    logger.info("=" * 60)

    try:
        worker.start()
    except Exception as e:
        logger.exception(f"Worker failed: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
