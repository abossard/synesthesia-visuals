"""
OSC Runtime Module - Centralized OSC communication for VJ system.

Wraps the existing OSCHub with a Module interface.

Usage as module:
    from modules.osc_runtime import OSCRuntime, OSCConfig

    config = OSCConfig(receive_port=9999)
    runtime = OSCRuntime(config)
    runtime.on_message = lambda addr, args: print(f"{addr}: {args}")
    runtime.start()
    runtime.send_to_vdj("/some/address", 42)
    runtime.stop()

Standalone CLI:
    python -m modules.osc_runtime --receive-port 9999
"""
import argparse
import signal
import sys
import time
from dataclasses import dataclass, field
from typing import Any, Callable, Dict, List, Optional, Tuple

from modules.base import Module


@dataclass
class OSCConfig:
    """Configuration for OSC Runtime module."""
    receive_port: int = 9999
    forward_targets: List[Tuple[str, int]] = field(default_factory=lambda: [
        ("127.0.0.1", 10000),  # VJUniverse (Processing)
        ("127.0.0.1", 11111),  # Magic Music Visual
    ])
    vdj_port: int = 9009
    synesthesia_port: int = 7777
    textler_port: int = 10000


Handler = Callable[[str, List[Any]], None]


class OSCRuntime(Module):
    """
    OSC Runtime module managing centralized OSC communication.

    Provides:
    - Single receive port for all incoming OSC
    - Forwarding to configured targets
    - Send channels for VDJ, Synesthesia, Textler
    - Pattern-based message subscriptions
    """

    def __init__(self, config: Optional[OSCConfig] = None):
        super().__init__()
        self._config = config or OSCConfig()
        self._hub = None
        self._pending_subscriptions: List[Tuple[str, Handler]] = []  # (pattern, handler)

    @property
    def config(self) -> OSCConfig:
        return self._config

    @property
    def hub(self):
        """Access underlying OSCHub (for backward compatibility)."""
        return self._hub

    def start(self) -> bool:
        """Start OSC runtime."""
        if self._started:
            return True

        # Reuse global singleton instead of creating new hub
        from osc.hub import osc
        self._hub = osc

        # Start hub if not already running
        if not self._hub.is_started:
            if not self._hub.start():
                self._hub = None
                return False

        # Apply any pending subscriptions
        for pattern, handler in self._pending_subscriptions:
            self._hub.subscribe(pattern, handler)

        self._started = True
        return True

    def stop(self) -> None:
        """Stop OSC runtime."""
        if not self._started:
            return

        # Unsubscribe all our subscriptions from the shared hub
        if self._hub:
            for pattern, handler in self._pending_subscriptions:
                self._hub.unsubscribe(pattern, handler)

        self._hub = None
        self._started = False

    def subscribe(self, pattern: str, handler: Handler) -> None:
        """Subscribe to incoming OSC messages matching pattern."""
        self._pending_subscriptions.append((pattern, handler))
        if self._hub:
            self._hub.subscribe(pattern, handler)

    def unsubscribe(self, pattern: str, handler: Handler) -> None:
        """Unsubscribe from OSC messages."""
        entry = (pattern, handler)
        if entry in self._pending_subscriptions:
            self._pending_subscriptions.remove(entry)
        if self._hub:
            self._hub.unsubscribe(pattern, handler)

    def send_to_vdj(self, address: str, *args) -> bool:
        """Send OSC message to VirtualDJ."""
        if not self._hub:
            return False
        return self._hub.vdj.send(address, *args)

    def send_to_synesthesia(self, address: str, *args) -> bool:
        """Send OSC message to Synesthesia."""
        if not self._hub:
            return False
        return self._hub.synesthesia.send(address, *args)

    def send_to_textler(self, address: str, *args) -> bool:
        """Send OSC message to Textler/Processing."""
        if not self._hub:
            return False
        return self._hub.textler.send(address, *args)

    def get_status(self) -> Dict[str, Any]:
        """Get module status."""
        status = super().get_status()
        if self._hub:
            status["receive_port"] = self._hub.receive_port
            status["channels"] = self._hub.get_channel_status()
            status["stats"] = self._hub.get_hub_stats()
        return status


def main():
    """CLI entry point for standalone OSC runtime."""
    parser = argparse.ArgumentParser(
        description="OSC Runtime - Standalone OSC communication module"
    )
    parser.add_argument(
        "--receive-port", type=int, default=9999,
        help="Port to receive OSC messages (default: 9999)"
    )
    parser.add_argument(
        "--verbose", "-v", action="store_true",
        help="Print all received messages"
    )
    args = parser.parse_args()

    config = OSCConfig(receive_port=args.receive_port)
    runtime = OSCRuntime(config)

    message_count = [0]

    def on_message(addr: str, msg_args: List[Any]):
        message_count[0] += 1
        if args.verbose:
            print(f"[{message_count[0]}] {addr}: {msg_args}")

    runtime.subscribe("*", on_message)

    stop_event = [False]

    def signal_handler(sig, frame):
        stop_event[0] = True

    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)

    print(f"Starting OSC Runtime on port {config.receive_port}...")
    if not runtime.start():
        print("Failed to start OSC Runtime", file=sys.stderr)
        sys.exit(1)

    print("OSC Runtime started. Press Ctrl+C to stop.")
    print(f"Forwarding to: {config.forward_targets}")

    try:
        while not stop_event[0]:
            time.sleep(0.5)
            if not args.verbose and message_count[0] > 0:
                print(f"\rReceived {message_count[0]} messages", end="", flush=True)
    except KeyboardInterrupt:
        pass

    print("\nStopping OSC Runtime...")
    runtime.stop()
    print(f"Total messages received: {message_count[0]}")


if __name__ == "__main__":
    main()
