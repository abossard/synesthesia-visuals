#!/usr/bin/env python3
"""
Spotify Monitor Worker - Standalone Process

Monitors Spotify playback and emits track changes via OSC.
Runs as independent process, reconnects to Spotify API automatically.
"""

import os
import sys
import logging
import time
from pathlib import Path
from typing import Optional

# Add parent directory to path
sys.path.insert(0, str(Path(__file__).parent))

from vj_bus import Worker
from vj_bus.schema import CommandMessage, AckMessage
from adapters import SpotifyMonitor

# Setup logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger('vj_spotify_worker')


class SpotifyWorker(Worker):
    """
    Spotify monitor worker process.
    
    Provides:
    - Spotify API polling every 2 seconds
    - OSC output to 127.0.0.1:9000
    - Control socket at /tmp/vj-bus/spotify_monitor.sock
    - Auto-reconnection on API failures
    """
    
    OSC_ADDRESSES = [
        "/karaoke/track",
        "/karaoke/pos",
    ]
    
    def __init__(self):
        super().__init__(
            name="spotify_monitor",
            osc_addresses=self.OSC_ADDRESSES
        )
        
        self.monitor: Optional[SpotifyMonitor] = None
        self.poll_interval = 2.0  # seconds
        self.last_track_key = ""
        
        logger.info("Spotify worker initialized")
    
    def on_start(self):
        """Initialize Spotify monitor."""
        logger.info("Starting Spotify monitor...")
        
        try:
            self.monitor = SpotifyMonitor()
            logger.info("Spotify monitor started successfully")
        except Exception as e:
            logger.exception(f"Failed to start Spotify monitor: {e}")
            self.monitor = None
    
    def on_stop(self):
        """Stop Spotify monitor."""
        logger.info("Stopping Spotify monitor...")
        self.monitor = None
        logger.info("Spotify monitor stopped")
    
    def on_command(self, cmd: CommandMessage) -> AckMessage:
        """
        Handle commands from TUI/process manager.
        
        Supported commands:
        - get_state: Return current status
        - set_config: Update poll interval
        - restart: Graceful restart
        """
        if cmd.cmd == "get_state":
            status = "running" if self.monitor else "stopped"
            available = self.monitor.is_available if self.monitor else False
            
            return AckMessage(
                success=True,
                data={
                    "status": status,
                    "available": available,
                    "poll_interval": self.poll_interval,
                    "last_track": self.last_track_key
                }
            )
        
        elif cmd.cmd == "set_config":
            try:
                if hasattr(cmd, 'poll_interval'):
                    self.poll_interval = float(cmd.poll_interval)
                    logger.info(f"Poll interval updated to {self.poll_interval}s")
                
                return AckMessage(success=True, message="Config updated")
            except Exception as e:
                logger.exception(f"Error updating config: {e}")
                return AckMessage(success=False, message=f"Config update failed: {e}")
        
        elif cmd.cmd == "restart":
            try:
                self.on_stop()
                self.on_start()
                return AckMessage(success=True, message="Restarted")
            except Exception as e:
                logger.exception(f"Restart failed: {e}")
                return AckMessage(success=False, message=f"Restart failed: {e}")
        
        else:
            return AckMessage(success=False, message=f"Unknown command: {cmd.cmd}")
    
    def get_stats(self) -> dict:
        """Get current stats for heartbeat."""
        if not self.monitor:
            return {
                "running": False,
                "available": False,
            }
        
        return {
            "running": True,
            "available": self.monitor.is_available,
            "poll_interval": self.poll_interval,
        }
    
    def on_loop(self):
        """Called every loop iteration - handle Spotify polling."""
        if not hasattr(self, '_last_poll'):
            self._last_poll = 0
        
        now = time.time()
        if now - self._last_poll >= self.poll_interval:
            self._poll_spotify()
            self._last_poll = now
    
    def _poll_spotify(self):
        """Poll Spotify and emit OSC if track changed."""
        if not self.monitor:
            return
        
        try:
            playback = self.monitor.get_playback()
            
            if playback:
                # Create track key for change detection
                track_key = f"{playback['artist']}|{playback['title']}"
                
                # Emit track info if changed
                if track_key != self.last_track_key:
                    self.last_track_key = track_key
                    
                    self.telemetry.send("/karaoke/track", [
                        1,  # active
                        "spotify",
                        playback['artist'],
                        playback['title'],
                        playback.get('album', ''),
                        playback.get('duration_ms', 0) / 1000.0,
                        0  # has_lyrics (unknown)
                    ])
                    
                    logger.info(f"Track: {playback['artist']} - {playback['title']}")
                
                # Always emit position
                self.telemetry.send("/karaoke/pos", [
                    playback.get('progress_ms', 0) / 1000.0,
                    1 if playback.get('is_playing') else 0
                ])
            else:
                # No playback - emit stopped state if we had a track
                if self.last_track_key:
                    self.telemetry.send("/karaoke/track", [
                        0,  # not active
                        "spotify",
                        "", "", "", 0, 0
                    ])
                    self.last_track_key = ""
        
        except Exception as e:
            logger.error(f"Error polling Spotify: {e}")
    
def main():
    """Main entry point for Spotify worker."""
    logger.info("=" * 60)
    logger.info("Spotify Monitor Worker starting...")
    logger.info(f"PID: {os.getpid()}")
    logger.info("=" * 60)
    
    # Create and start worker
    worker = SpotifyWorker()
    try:
        worker.start()  # Blocks until shutdown
    except KeyboardInterrupt:
        logger.info("Keyboard interrupt received")
    except Exception as e:
        logger.exception(f"Fatal error: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
