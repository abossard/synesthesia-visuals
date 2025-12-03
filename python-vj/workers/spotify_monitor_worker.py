#!/usr/bin/env python3
"""
Spotify Monitor Worker - Monitors Spotify playback via AppleScript.

Publishes playback state changes via ZMQ telemetry.

Usage:
    python workers/spotify_monitor_worker.py
"""

import time
import logging
import sys
from pathlib import Path
from typing import Dict, Any, Optional

# Add parent directory to path
sys.path.insert(0, str(Path(__file__).parent.parent))

from vj_bus.worker import WorkerBase
from vj_bus.messages import WorkerStatePayload

# Import existing Spotify adapter
try:
    from adapters import AppleScriptSpotifyMonitor
    SPOTIFY_AVAILABLE = True
except ImportError:
    SPOTIFY_AVAILABLE = False
    AppleScriptSpotifyMonitor = None

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)

logger = logging.getLogger('spotify_monitor_worker')


class SpotifyMonitorWorker(WorkerBase):
    """
    Spotify playback monitoring worker.

    Monitors Spotify via AppleScript and publishes state changes.
    """

    def __init__(self):
        super().__init__(
            name="spotify_monitor",
            command_port=5021,
            telemetry_port=5022,
            config={"poll_interval": 1.0}
        )

        if not SPOTIFY_AVAILABLE:
            raise RuntimeError("Spotify monitor not available")

        self.monitor: Optional[AppleScriptSpotifyMonitor] = None
        self.last_state: Optional[Dict[str, Any]] = None

    def on_start(self):
        """Initialize Spotify monitor."""
        logger.info("Starting Spotify monitor...")

        try:
            self.monitor = AppleScriptSpotifyMonitor()
            logger.info("Spotify monitor initialized")
        except Exception as e:
            logger.error(f"Failed to initialize Spotify monitor: {e}")
            raise

    def run(self):
        """Main loop - poll Spotify state."""
        logger.info("Spotify monitor worker running")

        poll_interval = self.config.get("poll_interval", 1.0)

        while self.running:
            try:
                if self.monitor:
                    # Get current state
                    state = self.monitor.get_playback_state()

                    # Publish if changed
                    if state != self.last_state:
                        self.publish_telemetry("spotify.state", {
                            "is_playing": state.is_playing,
                            "track": {
                                "artist": state.track.artist if state.track else None,
                                "title": state.track.title if state.track else None,
                                "album": state.track.album if state.track else None,
                                "duration": state.track.duration if state.track else 0.0,
                            },
                            "position": state.position,
                            "timestamp": state.last_update,
                        })

                        self.last_state = state

            except Exception as e:
                logger.error(f"Error polling Spotify: {e}")

            time.sleep(poll_interval)

        logger.info("Spotify monitor worker loop exited")

    def get_state(self) -> WorkerStatePayload:
        """Return current state."""
        return WorkerStatePayload(
            status="running" if self.running else "stopped",
            uptime_sec=time.time() - self.started_at,
            config=self.config,
            metrics={
                "last_poll": time.time() if self.last_state else None,
                "has_track": bool(self.last_state and self.last_state.track) if self.last_state else False,
            }
        )

    def get_metadata(self) -> Dict[str, Any]:
        """Return metadata for registry."""
        return {
            "version": "1.0",
            "platform": "macOS",
            "monitor_type": "AppleScript"
        }


def main():
    """Entry point."""
    if not SPOTIFY_AVAILABLE:
        logger.error("Spotify monitor not available")
        sys.exit(1)

    worker = SpotifyMonitorWorker()

    logger.info("=" * 60)
    logger.info("Spotify Monitor Worker Starting")
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
