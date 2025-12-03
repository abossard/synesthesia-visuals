#!/usr/bin/env python3
"""
Test client for VJ Bus.

Tests the example worker:
1. Discover worker from registry
2. Send health check
3. Subscribe to telemetry
4. Send config change
5. Get state

Usage:
    # Terminal 1: Start worker
    python workers/example_worker.py

    # Terminal 2: Run test client
    python dev/test_client.py
"""

import sys
import time
import logging
from pathlib import Path

# Add parent directory to path
sys.path.insert(0, str(Path(__file__).parent.parent))

from vj_bus.client import VJBusClient
from vj_bus.messages import CommandType

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)

logger = logging.getLogger('test_client')


def main():
    logger.info("=" * 60)
    logger.info("VJ Bus Test Client")
    logger.info("=" * 60)

    client = VJBusClient()

    # 1. Discover workers
    logger.info("\n1. Discovering workers...")
    workers = client.discover_workers()

    if not workers:
        logger.error("No workers found! Make sure example_worker.py is running.")
        return

    logger.info(f"Found {len(workers)} worker(s):")
    for name, info in workers.items():
        logger.info(f"  - {name} (PID {info['pid']})")

    # 2. Health check
    logger.info("\n2. Sending health check to example_worker...")
    try:
        response = client.send_command("example_worker", CommandType.HEALTH_CHECK)
        logger.info(f"Health check response: {response.status}")
        logger.info(f"  Alive: {response.result.get('alive')}")
        logger.info(f"  Uptime: {response.result.get('uptime'):.2f}s")
    except Exception as e:
        logger.error(f"Health check failed: {e}")
        return

    # 3. Subscribe to telemetry
    logger.info("\n3. Subscribing to telemetry...")
    message_count = [0]  # Use list to modify in closure

    def telemetry_handler(msg):
        message_count[0] += 1
        if message_count[0] <= 5:  # Print first 5 messages
            logger.info(f"  Received: {msg.topic} - Counter: {msg.payload.get('counter')}")

    client.subscribe("example.counter", telemetry_handler, worker_name="example_worker")
    client.start()

    logger.info("  Listening for 5 seconds...")
    time.sleep(5)

    logger.info(f"  Received {message_count[0]} telemetry messages")

    # 4. Change config
    logger.info("\n4. Changing config (publish interval to 0.2s)...")
    try:
        response = client.send_command(
            "example_worker",
            CommandType.SET_CONFIG,
            payload={"config": {"publish_interval": 0.2}}
        )
        logger.info(f"Config change response: {response.status}")
        logger.info(f"  Restart required: {response.result.get('restart_required')}")
    except Exception as e:
        logger.error(f"Config change failed: {e}")

    # 5. Get state
    logger.info("\n5. Getting worker state...")
    try:
        response = client.send_command("example_worker", CommandType.GET_STATE)
        if response.status == "ok":
            state = response.result
            logger.info(f"Worker state:")
            logger.info(f"  Status: {state.get('status')}")
            logger.info(f"  Uptime: {state.get('uptime_sec'):.2f}s")
            logger.info(f"  Counter: {state.get('metrics', {}).get('counter')}")
    except Exception as e:
        logger.error(f"Get state failed: {e}")

    # 6. Monitor telemetry with new interval
    logger.info("\n6. Monitoring telemetry with new interval (3 seconds)...")
    initial_count = message_count[0]
    time.sleep(3)
    final_count = message_count[0]
    rate = (final_count - initial_count) / 3.0
    logger.info(f"  Received {final_count - initial_count} messages in 3s ({rate:.1f} msg/s)")
    logger.info(f"  Expected rate: ~5 msg/s (interval 0.2s)")

    # Cleanup
    logger.info("\n7. Cleaning up...")
    client.stop()

    logger.info("\n" + "=" * 60)
    logger.info("Test completed successfully!")
    logger.info("=" * 60)


if __name__ == "__main__":
    main()
