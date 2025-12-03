#!/usr/bin/env python3
"""
Audio Analyzer Worker - Standalone process for audio analysis.

Analyzes audio input in real-time and emits features via:
- ZMQ telemetry (for TUI)
- OSC (for external visualizers)

Features:
- Per-band energy, beat detection, BPM, pitch
- Survives TUI crashes
- Hot-reload config without restart (where possible)

Usage:
    python workers/audio_analyzer_worker.py
"""

import time
import logging
import sys
from pathlib import Path
from typing import Dict, Any, List, Optional

# Add parent directory to path
sys.path.insert(0, str(Path(__file__).parent.parent))

from vj_bus.worker import WorkerBase
from vj_bus.messages import WorkerStatePayload, AudioFeaturesPayload, CommandMessage, ResponseMessage

# Import existing audio analyzer code
try:
    from audio_analyzer import (
        AudioAnalyzer,
        AudioConfig,
        DeviceManager,
        AUDIO_ANALYZER_AVAILABLE,
    )
except ImportError as e:
    print(f"Error: Cannot import audio_analyzer: {e}")
    print("Make sure audio_analyzer.py is in the python-vj directory")
    sys.exit(1)

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)

logger = logging.getLogger('audio_analyzer_worker')


class AudioAnalyzerWorker(WorkerBase):
    """
    Audio analyzer as a standalone worker process.

    Publishes high-frequency telemetry (60+ fps) to telemetry port.
    Accepts commands for config changes, device selection, etc.
    """

    def __init__(self, command_port: int = 5001, telemetry_port: int = 5002):
        super().__init__(
            name="audio_analyzer",
            command_port=command_port,
            telemetry_port=telemetry_port
        )

        if not AUDIO_ANALYZER_AVAILABLE:
            raise RuntimeError("Audio analyzer not available (missing dependencies)")

        # Initialize audio analyzer components
        self.device_manager = DeviceManager()
        self.audio_config = AudioConfig()
        self.analyzer: Optional[AudioAnalyzer] = None

        # Telemetry aggregation (reduce ZMQ messages)
        self.telemetry_buffer: Dict[str, Any] = {}
        self.last_telemetry_send = time.time()
        self.telemetry_send_interval = 1.0 / 30.0  # 30 Hz for TUI updates

    def on_start(self):
        """Initialize and start audio analyzer."""
        logger.info("Starting audio analyzer...")

        # Create analyzer with OSC callback that also publishes to ZMQ
        self.analyzer = AudioAnalyzer(
            config=self.audio_config,
            device_manager=self.device_manager,
            osc_callback=self._audio_osc_callback
        )

        self.analyzer.start()
        logger.info("Audio analyzer started")

    def on_stop(self):
        """Stop audio analyzer."""
        if self.analyzer:
            logger.info("Stopping audio analyzer...")
            self.analyzer.stop()
            logger.info("Audio analyzer stopped")

    def run(self):
        """Main loop - monitor analyzer and publish aggregated stats."""
        logger.info("Audio analyzer worker running")

        while self.running:
            # Periodically publish aggregated statistics
            if self.analyzer:
                stats = self.analyzer.get_stats()
                self.publish_telemetry("audio.stats", stats)

            time.sleep(1.0)

        logger.info("Audio analyzer worker loop exited")

    def _audio_osc_callback(self, address: str, args: List):
        """
        Called by audio analyzer for each OSC message.

        Bridges OSC -> ZMQ telemetry + sends to external OSC.
        """
        # Aggregate features for batch sending to TUI (reduce ZMQ overhead)
        if address == "/audio/levels":
            # args: [band0, band1, ..., band6, rms]
            self.telemetry_buffer["bands"] = args[:7]
            self.telemetry_buffer["rms"] = args[7] if len(args) > 7 else 0.0

        elif address == "/audio/beat":
            # args: [beat, flux]
            self.telemetry_buffer["beat"] = int(args[0]) if args else 0
            self.telemetry_buffer["flux"] = args[1] if len(args) > 1 else 0.0

        elif address == "/audio/bpm":
            # args: [bpm, confidence]
            self.telemetry_buffer["bpm"] = args[0] if args else 0.0
            self.telemetry_buffer["bpm_confidence"] = args[1] if len(args) > 1 else 0.0

        elif address == "/audio/pitch":
            # args: [pitch_hz, confidence]
            self.telemetry_buffer["pitch_hz"] = args[0] if args else 0.0
            self.telemetry_buffer["pitch_conf"] = args[1] if len(args) > 1 else 0.0

        elif address == "/audio/structure":
            # args: [buildup, drop, energy_trend, brightness]
            self.telemetry_buffer["buildup"] = bool(args[0]) if args else False
            self.telemetry_buffer["drop"] = bool(args[1]) if len(args) > 1 else False
            self.telemetry_buffer["energy_trend"] = args[2] if len(args) > 2 else 0.0
            self.telemetry_buffer["brightness"] = args[3] if len(args) > 3 else 0.0

        # Send aggregated features to TUI at reduced rate
        now = time.time()
        if now - self.last_telemetry_send >= self.telemetry_send_interval:
            if self.telemetry_buffer:
                # Get additional levels from analyzer
                if self.analyzer and "bands" in self.telemetry_buffer:
                    # Calculate aggregate levels
                    bands = self.telemetry_buffer["bands"]
                    self.telemetry_buffer["bass_level"] = bands[1] if len(bands) > 1 else 0.0
                    mid_bands = [bands[i] for i in [2, 3, 4] if i < len(bands)]
                    self.telemetry_buffer["mid_level"] = sum(mid_bands) / len(mid_bands) if mid_bands else 0.0
                    high_bands = [bands[i] for i in [5, 6] if i < len(bands)]
                    self.telemetry_buffer["high_level"] = sum(high_bands) / len(high_bands) if high_bands else 0.0

                # Publish to TUI
                self.publish_telemetry("audio.features", self.telemetry_buffer.copy())
                self.last_telemetry_send = now

        # Always send OSC for external tools (Synesthesia, etc.)
        try:
            from osc_manager import osc
            osc.send(address, args)
        except Exception as e:
            logger.error(f"OSC send error: {e}")

    def get_state(self) -> WorkerStatePayload:
        """Return current state."""
        status = "running" if (self.analyzer and self.analyzer.running) else "stopped"
        uptime = time.time() - self.started_at

        stats = self.analyzer.get_stats() if self.analyzer else {}

        return WorkerStatePayload(
            status=status,
            uptime_sec=uptime,
            config=self.config,
            metrics=stats
        )

    def get_metadata(self) -> Dict[str, Any]:
        """Return metadata for registry."""
        return {
            "device": self.device_manager.config.device_name if self.device_manager else "unknown",
            "sample_rate": self.audio_config.sample_rate,
            "running": self.analyzer.running if self.analyzer else False,
        }

    def on_config_change(self, new_config: Dict[str, Any]) -> bool:
        """Handle config updates."""
        # Check if restart required
        restart_keys = {"sample_rate", "device_index", "enable_essentia", "fft_size", "block_size"}
        restart_required = any(k in new_config for k in restart_keys)

        if restart_required and self.analyzer:
            logger.info("Restarting analyzer due to config change")
            self.analyzer.stop()

            # Update config
            config_dict = self.audio_config.__dict__.copy()
            config_dict.update(new_config)
            self.audio_config = AudioConfig(**config_dict)

            # Restart
            self.analyzer = AudioAnalyzer(
                config=self.audio_config,
                device_manager=self.device_manager,
                osc_callback=self._audio_osc_callback
            )
            self.analyzer.start()

        return restart_required

    def handle_command(self, cmd: CommandMessage) -> ResponseMessage:
        """Handle custom commands."""
        if cmd.command == "list_devices":
            # List available audio devices
            devices = self.device_manager.list_devices() if self.device_manager else []
            return ResponseMessage(
                id=cmd.id,
                source=self.name,
                status="ok",
                result={"devices": devices}
            )

        elif cmd.command == "set_device":
            # Change audio device
            device_index = cmd.payload.get("device_index")
            if device_index is None:
                return ResponseMessage(
                    id=cmd.id,
                    source=self.name,
                    status="error",
                    error="Missing device_index in payload"
                )

            try:
                self.device_manager.set_device(device_index)
                # Restart analyzer with new device
                return self.on_config_change({"device_index": device_index})
            except Exception as e:
                return ResponseMessage(
                    id=cmd.id,
                    source=self.name,
                    status="error",
                    error=str(e)
                )

        else:
            # Unknown command
            return super().handle_command(cmd)


def main():
    """Entry point for standalone audio analyzer worker."""
    if not AUDIO_ANALYZER_AVAILABLE:
        logger.error("Audio analyzer not available (missing dependencies)")
        logger.error("Install: pip install sounddevice numpy essentia")
        sys.exit(1)

    worker = AudioAnalyzerWorker()

    logger.info("=" * 60)
    logger.info("Audio Analyzer Worker Starting")
    logger.info("=" * 60)
    logger.info(f"PID: {worker.pid}")
    logger.info(f"Command port: {worker.command_port}")
    logger.info(f"Telemetry port: {worker.telemetry_port}")
    logger.info("=" * 60)

    try:
        worker.start()
    except Exception as e:
        logger.exception(f"Worker failed: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
