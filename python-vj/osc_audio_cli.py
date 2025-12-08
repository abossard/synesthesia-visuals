#!/usr/bin/env python3
"""
Standalone OSC audio analyzer CLI (Essentia-based)

- Prompts for audio input device on every start (no persistence).
- Streams OSC features compatible with processing-vj AudioAnalysisOSCVisualizer.
- Reuses AudioAnalyzer for feature extraction.

Usage:
    python osc_audio_cli.py run --host 127.0.0.1 --port 9000
    python osc_audio_cli.py run --duration 30
"""

import argparse
import logging
import sys
import time
from typing import Callable, List, Optional

from audio_analyzer import (
    AudioAnalyzer,
    AudioConfig,
    DeviceManager,
    SOUNDDEVICE_AVAILABLE,
)

try:
    from pythonosc import udp_client
except ImportError as exc:  # pragma: no cover - import guard
    udp_client = None
    raise SystemExit("python-osc is required. Install with: pip install python-osc") from exc

logger = logging.getLogger("osc_audio_cli")


def build_config(args: argparse.Namespace) -> AudioConfig:
    level = getattr(logging, args.log_level.upper(), logging.INFO)
    return AudioConfig(
        sample_rate=args.sample_rate,
        block_size=args.block_size,
        fft_size=args.fft_size,
        channels=args.channels,
        osc_host=args.host,
        osc_port=args.port,
        enable_essentia=not args.disable_essentia,
        enable_pitch=not args.disable_pitch,
        enable_bpm=not args.disable_bpm,
        enable_structure=not args.disable_structure,
        enable_spectrum=not args.disable_spectrum,
        enable_logging=True,
        log_level=level,
    )


def create_osc_sender(host: str, port: int) -> Callable[[str, List], None]:
    if udp_client is None:
        raise RuntimeError("python-osc import failed")
    client = udp_client.SimpleUDPClient(host, port)

    def send(addr: str, payload: List):
        client.send_message(addr, payload)

    return send


def prompt_for_device(dm: DeviceManager) -> Optional[int]:
    devices = dm.list_devices()
    if not SOUNDDEVICE_AVAILABLE or not devices:
        print("sounddevice unavailable or no input devices found; using default.")
        return None

    print("Select audio input device (blank = default):")
    for dev in devices:
        idx = dev.get("index", -1)
        name = dev.get("name", "unknown")
        ch = dev.get("channels", 0)
        rate = dev.get("sample_rate", 0)
        print(f"[{idx}] {name} - {ch}ch @ {rate}Hz")

    while True:
        choice = input("Device index: ").strip()
        if choice == "":
            return None
        if choice.isdigit():
            sel = int(choice)
            if any(d.get("index") == sel for d in devices):
                return sel
        print("Invalid selection. Try again or press Enter for default.")


def run_live(args: argparse.Namespace) -> int:
    if not SOUNDDEVICE_AVAILABLE:
        logger.error("sounddevice is required for live mode. Install PortAudio + sounddevice.")
        return 1

    config = build_config(args)
    dm = DeviceManager()
    dm.config.auto_select_blackhole = False  # always prompt, never auto-pick
    dm.config.device_index = prompt_for_device(dm)

    try:
        osc_cb = create_osc_sender(config.osc_host, config.osc_port) if not args.log_only else None
    except Exception as exc:
        logger.error("OSC setup failed: %s", exc)
        return 1

    def log_cb(addr: str, payload: List):
        logger.info("%s %s", addr, payload)

    callback = osc_cb if osc_cb else log_cb

    analyzer = AudioAnalyzer(config, dm, osc_callback=callback)
    analyzer.start()

    end_time = time.monotonic() + args.duration if args.duration else None
    try:
        while analyzer.is_alive():
            if end_time and time.monotonic() > end_time:
                break
            time.sleep(0.25)
    except KeyboardInterrupt:
        logger.info("Stopping (Ctrl+C pressed)...")
    finally:
        analyzer.stop()

    return 0


def list_devices(args: argparse.Namespace) -> int:
    dm = DeviceManager()
    devices = dm.list_devices()
    if not devices:
        print("No input devices found or sounddevice unavailable.")
        return 1
    for dev in devices:
        idx = dev.get("index", -1)
        name = dev.get("name", "unknown")
        ch = dev.get("channels", 0)
        rate = dev.get("sample_rate", 0)
        print(f"[{idx}] {name} - {ch}ch @ {rate}Hz")
    return 0


def parse_args(argv: Optional[List[str]] = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Standalone OSC audio analyzer (Essentia)")
    parser.add_argument("--host", default="127.0.0.1", help="OSC host")
    parser.add_argument("--port", type=int, default=9000, help="OSC port")
    parser.add_argument("--sample-rate", type=int, default=44100)
    parser.add_argument("--block-size", type=int, default=512)
    parser.add_argument("--fft-size", type=int, default=512)
    parser.add_argument("--channels", type=int, default=2)
    parser.add_argument("--disable-essentia", action="store_true")
    parser.add_argument("--disable-pitch", action="store_true")
    parser.add_argument("--disable-bpm", action="store_true")
    parser.add_argument("--disable-structure", action="store_true")
    parser.add_argument("--disable-spectrum", action="store_true")
    parser.add_argument("--log-only", action="store_true", help="Log features instead of sending OSC")
    parser.add_argument("--duration", type=float, default=0.0, help="Stop after N seconds (0 = until Ctrl+C)")
    parser.add_argument("--log-level", default="INFO", choices=["DEBUG", "INFO", "WARNING", "ERROR"])

    sub = parser.add_subparsers(dest="mode")
    sub.add_parser("run", help="Live input (prompts for device)")
    sub.add_parser("list-devices", help="List input devices")

    args = parser.parse_args(argv)
    if args.mode is None:
        parser.error("mode is required: run | list-devices")
    return args


def main(argv: Optional[List[str]] = None) -> int:
    args = parse_args(argv)
    logging.basicConfig(level=getattr(logging, args.log_level.upper(), logging.INFO), format="%(asctime)s %(levelname)s %(message)s")

    if args.mode == "list-devices":
        return list_devices(args)
    if args.mode == "run":
        return run_live(args)
    logger.error("Unknown mode: %s", args.mode)
    return 1


if __name__ == "__main__":
    sys.exit(main())
