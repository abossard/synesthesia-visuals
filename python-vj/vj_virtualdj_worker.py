#!/usr/bin/env python3
"""
VirtualDJ Monitor Worker - Standalone Process

Monitors VirtualDJ now_playing.txt file and emits track changes via OSC.
Runs as independent process with file watching.
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
from adapters import VirtualDJMonitor

# Setup logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger('vj_virtualdj_worker')


class VirtualDJWorker(Worker):
    """
    VirtualDJ monitor worker process.
    
    Provides:
    - File watching for VirtualDJ now_playing.txt
    - OSC output to 127.0.0.1:9000
    - Control socket at /tmp/vj-bus/virtualdj_monitor.sock
    - Auto-detection of file changes
    """
    
    OSC_ADDRESSES = [
        "/karaoke/track",
        "/karaoke/pos",
    ]
    
    def __init__(self):
        super().__init__(
            name="virtualdj_monitor",
            osc_addresses=self.OSC_ADDRESSES
        )
        
        self.monitor: Optional[VirtualDJMonitor] = None
        self.poll_interval = 1.0  # seconds
        self.last_track_key = ""
        self.file_path: Optional[str] = None
        
        logger.info("VirtualDJ worker initialized")
    
    def on_start(self):
        """Initialize VirtualDJ monitor."""
        logger.info("Starting VirtualDJ monitor...")
        
        try:
            self.monitor = VirtualDJMonitor(self.file_path)
            logger.info("VirtualDJ monitor started successfully")
        except Exception as e:
            logger.exception(f"Failed to start VirtualDJ monitor: {e}")
            self.monitor = None
    
    def on_stop(self):
        """Stop VirtualDJ monitor."""
        logger.info("Stopping VirtualDJ monitor...")
        self.monitor = None
        logger.info("VirtualDJ monitor stopped")
    
    def on_command(self, cmd: CommandMessage) -> AckMessage:
        """Handle commands from TUI/process manager."""
        if cmd.cmd == "get_state":
            status = "running" if self.monitor else "stopped"
            available = self.monitor.is_available if self.monitor else False
            
            return AckMessage(
                success=True,
                data={
                    "status": status,
                    "available": available,
                    "file_path": str(self.file_path) if self.file_path else "auto-detect",
                    "last_track": self.last_track_key
                }
            )
        
        elif cmd.cmd == "set_config":
            try:
                if hasattr(cmd, 'file_path'):
                    self.file_path = cmd.file_path
                    logger.info(f"File path updated to {self.file_path}")
                    # Restart monitor with new path
                    self.on_stop()
                    self.on_start()
                
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
            return {"running": False, "available": False}
        
        return {
            "running": True,
            "available": self.monitor.is_available,
            "poll_interval": self.poll_interval,
        }
    
    def on_loop(self):
        """Called every loop iteration - handle file polling."""
        if not hasattr(self, '_last_poll'):
            self._last_poll = 0
        
        now = time.time()
        if now - self._last_poll >= self.poll_interval:
            self._poll_virtualdj()
            self._last_poll = now
    
    def _poll_virtualdj(self):
        """Poll VirtualDJ file and emit OSC if track changed."""
        if not self.monitor:
            return
        
        try:
            playback = self.monitor.get_playback()
            
            if playback:
                track_key = f"{playback['artist']}|{playback['title']}"
                
                if track_key != self.last_track_key:
                    self.last_track_key = track_key
                    
                    self.telemetry.send("/karaoke/track", [
                        1,  # active
                        "virtualdj",
                        playback['artist'],
                        playback['title'],
                        playback.get('album', ''),
                        playback.get('duration_ms', 0) / 1000.0,
                        0  # has_lyrics
                    ])
                    
                    logger.info(f"Track: {playback['artist']} - {playback['title']}")
                
                # Emit position
                self.telemetry.send("/karaoke/pos", [
                    playback.get('progress_ms', 0) / 1000.0,
                    1 if playback.get('is_playing') else 0
                ])
            else:
                if self.last_track_key:
                    self.telemetry.send("/karaoke/track", [
                        0, "virtualdj", "", "", "", 0, 0
                    ])
                    self.last_track_key = ""
        
        except Exception as e:
            logger.error(f"Error polling VirtualDJ: {e}")


def main():
    """Main entry point for VirtualDJ worker."""
    logger.info("=" * 60)
    logger.info("VirtualDJ Monitor Worker starting...")
    logger.info(f"PID: {os.getpid()}")
    logger.info("=" * 60)
    
    worker = VirtualDJWorker()
    try:
        worker.start()
    except KeyboardInterrupt:
        logger.info("Keyboard interrupt received")
    except Exception as e:
        logger.exception(f"Fatal error: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
