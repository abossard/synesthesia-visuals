#!/usr/bin/env python3
"""
VirtualDJ Monitor Worker - Monitors VirtualDJ via file watching.

Watches the VirtualDJ history file for playback changes and publishes state.

Usage:
    python workers/virtualdj_monitor_worker.py
"""

import time
import logging
import sys
from pathlib import Path
from typing import Dict, Any, Optional
import xml.etree.ElementTree as ET

# Add parent directory to path
sys.path.insert(0, str(Path(__file__).parent.parent))

from vj_bus.worker import WorkerBase
from vj_bus.messages import WorkerStatePayload

# Import existing VirtualDJ adapter
try:
    from adapters import VirtualDJFileMonitor
    VIRTUALDJ_AVAILABLE = True
except ImportError:
    VIRTUALDJ_AVAILABLE = False
    VirtualDJFileMonitor = None

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)

logger = logging.getLogger('virtualdj_monitor_worker')


class VirtualDJMonitorWorker(WorkerBase):
    """
    VirtualDJ playback monitoring worker.

    Watches VirtualDJ history file and publishes state changes.
    """

    def __init__(self):
        super().__init__(
            name="virtualdj_monitor",
            command_port=5031,
            telemetry_port=5032,
            config={"poll_interval": 1.0}
        )

        if not VIRTUALDJ_AVAILABLE:
            # Create fallback implementation
            logger.warning("VirtualDJ adapter not available, using fallback")

        self.monitor: Optional[Any] = None
        self.last_state: Optional[Dict[str, Any]] = None
        self.last_file_mtime = 0.0

    def on_start(self):
        """Initialize VirtualDJ monitor."""
        logger.info("Starting VirtualDJ monitor...")

        try:
            if VIRTUALDJ_AVAILABLE:
                self.monitor = VirtualDJFileMonitor()
            else:
                # Fallback: manual file watching
                self.monitor = VirtualDJFileWatcher()

            logger.info("VirtualDJ monitor initialized")
        except Exception as e:
            logger.error(f"Failed to initialize VirtualDJ monitor: {e}")
            raise

    def run(self):
        """Main loop - poll VirtualDJ state."""
        logger.info("VirtualDJ monitor worker running")

        poll_interval = self.config.get("poll_interval", 1.0)

        while self.running:
            try:
                if self.monitor:
                    # Get current state
                    state = self.monitor.get_playback_state()

                    # Publish if changed
                    if state != self.last_state:
                        self.publish_telemetry("virtualdj.state", {
                            "is_playing": state.is_playing if hasattr(state, 'is_playing') else False,
                            "track": {
                                "artist": state.track.artist if hasattr(state, 'track') and state.track else None,
                                "title": state.track.title if hasattr(state, 'track') and state.track else None,
                                "duration": state.track.duration if hasattr(state, 'track') and state.track else 0.0,
                            },
                            "position": state.position if hasattr(state, 'position') else 0.0,
                            "timestamp": time.time(),
                        })

                        self.last_state = state

            except Exception as e:
                logger.error(f"Error polling VirtualDJ: {e}")

            time.sleep(poll_interval)

        logger.info("VirtualDJ monitor worker loop exited")

    def get_state(self) -> WorkerStatePayload:
        """Return current state."""
        return WorkerStatePayload(
            status="running" if self.running else "stopped",
            uptime_sec=time.time() - self.started_at,
            config=self.config,
            metrics={
                "last_poll": time.time() if self.last_state else None,
                "has_track": bool(self.last_state) if self.last_state else False,
            }
        )

    def get_metadata(self) -> Dict[str, Any]:
        """Return metadata for registry."""
        return {
            "version": "1.0",
            "platform": "cross-platform",
            "monitor_type": "file_watcher"
        }


class VirtualDJFileWatcher:
    """
    Fallback VirtualDJ file watcher.

    Watches the history file for changes.
    """

    def __init__(self):
        # Find VirtualDJ history file
        self.history_file = self._find_history_file()
        self.last_mtime = 0.0

        if self.history_file:
            logger.info(f"Watching VirtualDJ file: {self.history_file}")
        else:
            logger.warning("VirtualDJ history file not found")

    def _find_history_file(self) -> Optional[Path]:
        """Find VirtualDJ history file."""
        # Common locations
        possible_paths = [
            Path.home() / "Documents" / "VirtualDJ" / "History" / "history.xml",
            Path.home() / "Music" / "VirtualDJ" / "History" / "history.xml",
            Path("/Users") / "Shared" / "VirtualDJ" / "History" / "history.xml",
        ]

        for path in possible_paths:
            if path.exists():
                return path

        return None

    def get_playback_state(self):
        """Get current playback state from file."""
        if not self.history_file or not self.history_file.exists():
            return MockPlaybackState()

        try:
            mtime = self.history_file.stat().st_mtime

            if mtime > self.last_mtime:
                self.last_mtime = mtime

                # Parse history file
                tree = ET.parse(self.history_file)
                root = tree.getroot()

                # Get most recent song
                songs = root.findall('.//Song')
                if songs:
                    latest = songs[-1]
                    artist = latest.get('Artist', 'Unknown')
                    title = latest.get('Title', 'Unknown')
                    duration_str = latest.get('Duration', '0')

                    # Parse duration (format: "MM:SS")
                    try:
                        parts = duration_str.split(':')
                        duration = int(parts[0]) * 60 + int(parts[1]) if len(parts) == 2 else 0
                    except:
                        duration = 0

                    state = MockPlaybackState()
                    state.is_playing = True
                    state.track = MockTrack(artist, title, duration)
                    state.position = 0.0

                    return state

        except Exception as e:
            logger.error(f"Error reading VirtualDJ file: {e}")

        return MockPlaybackState()


class MockTrack:
    """Mock track for fallback."""
    def __init__(self, artist, title, duration):
        self.artist = artist
        self.title = title
        self.duration = duration


class MockPlaybackState:
    """Mock playback state for fallback."""
    def __init__(self):
        self.is_playing = False
        self.track = None
        self.position = 0.0


def main():
    """Entry point."""
    worker = VirtualDJMonitorWorker()

    logger.info("=" * 60)
    logger.info("VirtualDJ Monitor Worker Starting")
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
