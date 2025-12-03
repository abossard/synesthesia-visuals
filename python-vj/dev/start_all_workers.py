#!/usr/bin/env python3
"""
Development Harness - Start all workers for testing.

Usage:
    python dev/start_all_workers.py              # Start all workers
    python dev/start_all_workers.py --list       # List available workers
    python dev/start_all_workers.py worker1 worker2  # Start specific workers
"""

import subprocess
import time
import signal
import sys
import argparse
from pathlib import Path

# Add parent directory to path
sys.path.insert(0, str(Path(__file__).parent.parent))

from vj_bus.client import VJBusClient

# Available workers
WORKERS = {
    "process_manager": "workers/process_manager_daemon.py",
    "example": "workers/example_worker.py",
    "audio_analyzer": "workers/audio_analyzer_worker.py",
    "spotify_monitor": "workers/spotify_monitor_worker.py",
    "osc_debugger": "workers/osc_debugger_worker.py",
    "log_aggregator": "workers/log_aggregator_worker.py",
}


def start_workers(worker_names):
    """Start specified workers."""
    procs = []

    for name in worker_names:
        if name not in WORKERS:
            print(f"Unknown worker: {name}")
            continue

        script = WORKERS[name]
        print(f"Starting {name}...")

        proc = subprocess.Popen(
            [sys.executable, script],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            start_new_session=True  # Detach from parent
        )

        procs.append((name, proc))
        time.sleep(1)

    return procs


def stop_all(procs):
    """Stop all workers gracefully."""
    for name, proc in procs:
        print(f"Stopping {name}...")
        proc.terminate()

    # Wait for graceful shutdown
    time.sleep(2)

    # Force kill if still running
    for name, proc in procs:
        if proc.poll() is None:
            print(f"Force killing {name}...")
            proc.kill()


def list_workers():
    """List available workers and their status."""
    client = VJBusClient()

    print("\nAvailable workers:")
    print("-" * 60)

    for name, script in WORKERS.items():
        print(f"  {name:20s} {script}")

    print()

    # Check running workers
    print("Currently running workers:")
    print("-" * 60)

    running = client.discover_workers(include_stale=False)

    if not running:
        print("  (none)")
    else:
        for name, info in running.items():
            pid = info.get("pid", "?")
            uptime = time.time() - info.get("started_at", time.time())
            print(f"  {name:20s} PID: {pid:6d}  Uptime: {uptime:.1f}s")

    print()


def monitor_workers():
    """Monitor running workers."""
    client = VJBusClient()

    print("\nMonitoring workers (Ctrl+C to stop)...")
    print("-" * 60)

    try:
        while True:
            workers = client.discover_workers(include_stale=False)

            # Clear screen
            print("\033[H\033[J", end="")

            print(f"Active Workers: {len(workers)}")
            print("-" * 60)

            for name, info in sorted(workers.items()):
                pid = info.get("pid", "?")
                status = info.get("status", "unknown")
                uptime = time.time() - info.get("started_at", time.time())

                print(f"{name:20s} [{status:8s}] PID: {pid:6d} Uptime: {uptime:6.1f}s")

            time.sleep(1)

    except KeyboardInterrupt:
        print("\nMonitoring stopped")


def main():
    parser = argparse.ArgumentParser(
        description="VJ Workers Development Harness"
    )

    parser.add_argument(
        "workers",
        nargs="*",
        help="Workers to start (default: all)"
    )

    parser.add_argument(
        "--list",
        action="store_true",
        help="List available workers and status"
    )

    parser.add_argument(
        "--monitor",
        action="store_true",
        help="Monitor running workers"
    )

    args = parser.parse_args()

    if args.list:
        list_workers()
        return

    if args.monitor:
        monitor_workers()
        return

    # Determine which workers to start
    if args.workers:
        worker_names = args.workers
    else:
        # Start all workers by default
        worker_names = list(WORKERS.keys())

    print("=" * 60)
    print("VJ Workers Development Harness")
    print("=" * 60)
    print(f"Starting {len(worker_names)} workers...")
    print()

    procs = start_workers(worker_names)

    print()
    print(f"Started {len(procs)} workers successfully")
    print()
    print("Press Ctrl+C to stop all workers")
    print("=" * 60)

    try:
        # Wait indefinitely
        signal.pause()
    except KeyboardInterrupt:
        print("\n\nShutting down...")
    finally:
        stop_all(procs)
        print("All workers stopped")


if __name__ == "__main__":
    main()
