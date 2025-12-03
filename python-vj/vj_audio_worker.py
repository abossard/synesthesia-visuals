#!/usr/bin/env python3
"""
Audio Analyzer Worker - Standalone Process

Wraps the AudioAnalyzer in a vj_bus Worker for multi-process architecture.
Runs audio analysis in standalone process, sends features via OSC.
"""

import os
import sys
import logging
from pathlib import Path
from typing import Optional

# Add parent directory to path
sys.path.insert(0, str(Path(__file__).parent))

from vj_bus import Worker
from vj_bus.schema import CommandMessage, AckMessage
from audio_analyzer import (
    AudioAnalyzer, AudioConfig, DeviceManager, AudioAnalyzerWatchdog,
    SOUNDDEVICE_AVAILABLE, ESSENTIA_AVAILABLE
)

# Setup logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger('vj_audio_worker')


class AudioWorker(Worker):
    """
    Audio analyzer worker process.
    
    Provides:
    - Real-time audio analysis @ 60 fps
    - OSC output to 127.0.0.1:9000
    - Control socket at /tmp/vj-bus/audio_analyzer.sock
    - Feature toggles via commands
    - Graceful restart on config change
    """
    
    OSC_ADDRESSES = [
        "/audio/levels",
        "/audio/spectrum",
        "/audio/beat",
        "/audio/bpm",
        "/audio/pitch",
        "/audio/structure",
    ]
    
    def __init__(self):
        super().__init__(
            name="audio_analyzer",
            osc_addresses=self.OSC_ADDRESSES
        )
        
        self.analyzer: Optional[AudioAnalyzer] = None
        self.watchdog: Optional[AudioAnalyzerWatchdog] = None
        self.device_manager: Optional[DeviceManager] = None
        
        # Load config from disk (persisted)
        self.config = self._load_config()
        
        logger.info("Audio worker initialized")
    
    def _load_config(self) -> AudioConfig:
        """Load audio config from disk or use defaults."""
        # Audio analyzer loads from ~/.vj_audio_config.json
        # We use the same defaults
        return AudioConfig()
    
    def on_start(self):
        """Initialize audio analyzer."""
        if not SOUNDDEVICE_AVAILABLE:
            logger.error("sounddevice not available - audio input disabled")
            logger.info("Install with: pip install sounddevice")
            return
        
        logger.info("Starting audio analyzer...")
        
        try:
            # Create device manager
            self.device_manager = DeviceManager()
            
            # Create analyzer with OSC callback
            self.analyzer = AudioAnalyzer(
                config=self.config,
                device_manager=self.device_manager,
                osc_callback=self.telemetry.send  # Use vj_bus telemetry sender
            )
            
            # Create watchdog for self-healing
            self.watchdog = AudioAnalyzerWatchdog(self.analyzer)
            
            # Start analyzer
            self.analyzer.start()
            
            logger.info("Audio analyzer started successfully")
        
        except Exception as e:
            logger.exception(f"Failed to start audio analyzer: {e}")
            self.analyzer = None
            self.watchdog = None
    
    def on_stop(self):
        """Stop audio analyzer."""
        logger.info("Stopping audio analyzer...")
        
        if self.analyzer:
            try:
                self.analyzer.stop()
            except Exception as e:
                logger.error(f"Error stopping analyzer: {e}")
            finally:
                self.analyzer = None
                self.watchdog = None
        
        logger.info("Audio analyzer stopped")
    
    def on_command(self, cmd: CommandMessage) -> AckMessage:
        """
        Handle commands from TUI/process manager.
        
        Supported commands:
        - get_state: Return current config and status
        - set_config: Update config (restarts analyzer)
        - restart: Graceful restart
        """
        if cmd.cmd == "get_state":
            # Return current state
            config_dict = {
                'enable_essentia': self.config.enable_essentia,
                'enable_pitch': self.config.enable_pitch,
                'enable_bpm': self.config.enable_bpm,
                'enable_structure': self.config.enable_structure,
                'enable_spectrum': self.config.enable_spectrum,
                'enable_logging': self.config.enable_logging,
            }
            
            status = "running" if self.analyzer else "stopped"
            
            return AckMessage(
                success=True,
                data={
                    "config": config_dict,
                    "status": status,
                    "device_name": self.device_manager.get_current_device_name() if self.device_manager else "Unknown"
                }
            )
        
        elif cmd.cmd == "set_config":
            # Update config from command
            try:
                # Build new config with updated values
                config_dict = {
                    'enable_essentia': getattr(cmd, 'enable_essentia', self.config.enable_essentia),
                    'enable_pitch': getattr(cmd, 'enable_pitch', self.config.enable_pitch),
                    'enable_bpm': getattr(cmd, 'enable_bpm', self.config.enable_bpm),
                    'enable_structure': getattr(cmd, 'enable_structure', self.config.enable_structure),
                    'enable_spectrum': getattr(cmd, 'enable_spectrum', self.config.enable_spectrum),
                    'enable_logging': getattr(cmd, 'enable_logging', self.config.enable_logging),
                    'log_level': getattr(cmd, 'log_level', self.config.log_level),
                }
                
                # Create new config
                self.config = AudioConfig(**config_dict)
                
                # Restart analyzer with new config
                self.on_stop()
                self.on_start()
                
                return AckMessage(
                    success=True,
                    message="Config updated, analyzer restarted"
                )
            
            except Exception as e:
                logger.exception(f"Error updating config: {e}")
                return AckMessage(
                    success=False,
                    message=f"Config update failed: {e}"
                )
        
        elif cmd.cmd == "restart":
            # Graceful restart
            try:
                self.on_stop()
                self.on_start()
                return AckMessage(success=True, message="Restarted")
            except Exception as e:
                logger.exception(f"Restart failed: {e}")
                return AckMessage(success=False, message=f"Restart failed: {e}")
        
        else:
            return AckMessage(
                success=False,
                message=f"Unknown command: {cmd.cmd}"
            )
    
    def get_stats(self) -> dict:
        """Get current stats for heartbeat."""
        if not self.analyzer:
            return {
                "running": False,
                "audio_alive": False,
                "frames_processed": 0,
                "fps": 0.0,
            }
        
        stats = self.analyzer.get_stats()
        
        # Update watchdog if running
        if self.watchdog and stats.get('running', False):
            self.watchdog.update()
        
        return stats


def main():
    """Main entry point for audio worker."""
    logger.info("=" * 60)
    logger.info("Audio Analyzer Worker starting...")
    logger.info(f"PID: {os.getpid()}")
    logger.info(f"Sounddevice available: {SOUNDDEVICE_AVAILABLE}")
    logger.info(f"Essentia available: {ESSENTIA_AVAILABLE}")
    logger.info("=" * 60)
    
    if not SOUNDDEVICE_AVAILABLE:
        logger.error("Audio worker requires sounddevice. Install with: pip install sounddevice")
        sys.exit(1)
    
    # Create and start worker
    worker = AudioWorker()
    try:
        worker.start()  # Blocks until shutdown
    except KeyboardInterrupt:
        logger.info("Keyboard interrupt received")
    except Exception as e:
        logger.exception(f"Fatal error: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
