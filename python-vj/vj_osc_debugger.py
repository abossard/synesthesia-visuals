#!/usr/bin/env python3
"""
OSC Debugger Worker - Standalone Process

Captures OSC messages and aggregates logs from all workers.
Runs as independent process for debugging and monitoring.
"""

import os
import sys
import logging
import time
from pathlib import Path
from typing import List, Dict, Any, Deque
from collections import deque
from threading import Thread, Lock

# Add parent directory to path
sys.path.insert(0, str(Path(__file__).parent))

from vj_bus import Worker
from vj_bus.schema import CommandMessage, AckMessage

# Try to import OSC server
try:
    from pythonosc import dispatcher, osc_server
    OSC_AVAILABLE = True
except ImportError:
    OSC_AVAILABLE = False
    osc_server = None
    dispatcher = None

# Setup logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger('vj_osc_debugger')


class OSCDebuggerWorker(Worker):
    """
    OSC debugger worker process.
    
    Provides:
    - OSC message capture (listens on port 9001 to avoid conflict with main port 9000)
    - Log aggregation from worker heartbeats
    - Control socket at /tmp/vj-bus/osc_debugger.sock
    - Commands to retrieve messages and logs
    """
    
    OSC_ADDRESSES = []  # This worker doesn't emit OSC, it receives it
    
    MAX_MESSAGES = 1000  # Keep last 1000 OSC messages
    MAX_LOGS = 500  # Keep last 500 log entries
    
    def __init__(self):
        super().__init__(
            name="osc_debugger",
            osc_addresses=self.OSC_ADDRESSES
        )
        
        self.osc_messages: Deque[Dict[str, Any]] = deque(maxlen=self.MAX_MESSAGES)
        self.log_entries: Deque[Dict[str, Any]] = deque(maxlen=self.MAX_LOGS)
        self.message_lock = Lock()
        self.log_lock = Lock()
        
        self.osc_server = None
        self.osc_thread = None
        self.osc_enabled = True
        self.logging_enabled = True
        
        # Listen on different port to avoid conflict with workers emitting to 9000
        self.osc_port = 9001
        
        logger.info("OSC debugger worker initialized")
    
    def on_start(self):
        """Initialize OSC message capture."""
        if not OSC_AVAILABLE:
            logger.warning("pythonosc not available - OSC capture disabled")
            logger.info("Install with: pip install python-osc")
            return
        
        logger.info("Starting OSC message capture...")
        
        try:
            # Create OSC server to capture messages
            disp = dispatcher.Dispatcher()
            disp.map("/*", self._osc_handler)  # Capture all OSC messages
            
            self.osc_server = osc_server.ThreadingOSCUDPServer(
                ("127.0.0.1", self.osc_port),
                disp
            )
            
            # Start OSC server in background thread
            self.osc_thread = Thread(target=self.osc_server.serve_forever, daemon=True)
            self.osc_thread.start()
            
            logger.info(f"OSC debugger listening on port {self.osc_port}")
        
        except Exception as e:
            logger.exception(f"Failed to start OSC server: {e}")
            self.osc_server = None
    
    def on_stop(self):
        """Stop OSC capture."""
        logger.info("Stopping OSC debugger...")
        
        if self.osc_server:
            try:
                self.osc_server.shutdown()
            except Exception as e:
                logger.error(f"Error stopping OSC server: {e}")
            finally:
                self.osc_server = None
        
        logger.info("OSC debugger stopped")
    
    def on_command(self, cmd: CommandMessage) -> AckMessage:
        """Handle commands from TUI/process manager."""
        if cmd.cmd == "get_state":
            return AckMessage(
                success=True,
                data={
                    "status": "running" if self.osc_server else "stopped",
                    "osc_port": self.osc_port,
                    "osc_enabled": self.osc_enabled,
                    "logging_enabled": self.logging_enabled,
                    "message_count": len(self.osc_messages),
                    "log_count": len(self.log_entries),
                }
            )
        
        elif cmd.cmd == "get_messages":
            # Return recent OSC messages
            count = getattr(cmd, 'count', 50)
            count = min(count, self.MAX_MESSAGES)
            
            with self.message_lock:
                messages = list(self.osc_messages)[-count:]
            
            return AckMessage(
                success=True,
                data={
                    "messages": messages,
                    "total_count": len(self.osc_messages)
                }
            )
        
        elif cmd.cmd == "get_logs":
            # Return recent log entries
            count = getattr(cmd, 'count', 100)
            count = min(count, self.MAX_LOGS)
            
            with self.log_lock:
                logs = list(self.log_entries)[-count:]
            
            return AckMessage(
                success=True,
                data={
                    "logs": logs,
                    "total_count": len(self.log_entries)
                }
            )
        
        elif cmd.cmd == "clear":
            # Clear all captured data
            with self.message_lock:
                self.osc_messages.clear()
            with self.log_lock:
                self.log_entries.clear()
            
            return AckMessage(success=True, message="Cleared all captured data")
        
        elif cmd.cmd == "set_config":
            try:
                if hasattr(cmd, 'osc_enabled'):
                    self.osc_enabled = bool(cmd.osc_enabled)
                if hasattr(cmd, 'logging_enabled'):
                    self.logging_enabled = bool(cmd.logging_enabled)
                
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
        return {
            "running": self.osc_server is not None,
            "osc_port": self.osc_port,
            "message_count": len(self.osc_messages),
            "log_count": len(self.log_entries),
        }
    
    def _osc_handler(self, address: str, *args):
        """Handle incoming OSC message."""
        if not self.osc_enabled:
            return
        
        # Capture message
        message = {
            "timestamp": time.time(),
            "address": address,
            "args": list(args),
        }
        
        with self.message_lock:
            self.osc_messages.append(message)
        
        # Log at debug level
        logger.debug(f"OSC: {address} {args}")
    
    def _log(self, level: str, source: str, message: str):
        """Add a log entry."""
        if not self.logging_enabled:
            return
        
        entry = {
            "timestamp": time.time(),
            "level": level,
            "source": source,
            "message": message,
        }
        
        with self.log_lock:
            self.log_entries.append(entry)


def main():
    """Main entry point for OSC debugger worker."""
    logger.info("=" * 60)
    logger.info("OSC Debugger Worker starting...")
    logger.info(f"PID: {os.getpid()}")
    logger.info(f"OSC available: {OSC_AVAILABLE}")
    logger.info("=" * 60)
    
    if not OSC_AVAILABLE:
        logger.error("OSC debugger requires python-osc. Install with: pip install python-osc")
        # Continue anyway - worker can still aggregate logs
    
    worker = OSCDebuggerWorker()
    try:
        worker.start()
    except KeyboardInterrupt:
        logger.info("Keyboard interrupt received")
    except Exception as e:
        logger.exception(f"Fatal error: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
