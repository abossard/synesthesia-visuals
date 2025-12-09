#!/usr/bin/env python3
"""
OSC Monitor - Listen to all incoming OSC messages from Synesthesia

Run this while Synesthesia is sending OSC to see what messages are actually sent.
This will help you identify the correct beat pulse message path.

Usage:
    python scripts/osc_monitor.py [port]

    Default port: 9999 (matches Synesthesia send port)
"""

import sys
import asyncio
from pythonosc import dispatcher, osc_server
from datetime import datetime


class OSCMonitor:
    def __init__(self, port=9999):
        self.port = port
        self.message_count = {}
        self.last_messages = {}

    def handle_message(self, address, *args):
        """Handle any OSC message."""
        timestamp = datetime.now().strftime("%H:%M:%S.%f")[:-3]

        # Count messages
        self.message_count[address] = self.message_count.get(address, 0) + 1

        # Store last message
        self.last_messages[address] = args

        # Print if it's beat-related or new
        if "beat" in address.lower() or "bpm" in address.lower() or self.message_count[address] == 1:
            print(f"[{timestamp}] {address} {args}")

    async def run(self):
        """Start monitoring."""
        print(f"\n{'='*60}")
        print(f"OSC Monitor - Listening on port {self.port}")
        print(f"{'='*60}")
        print("Waiting for OSC messages from Synesthesia...")
        print("Beat-related messages will be highlighted.")
        print("Press Ctrl+C to stop and show summary.\n")

        # Set up dispatcher to catch all messages
        disp = dispatcher.Dispatcher()
        disp.set_default_handler(self.handle_message)

        # Create server
        server = osc_server.AsyncIOOSCUDPServer(
            ("0.0.0.0", self.port),
            disp,
            asyncio.get_event_loop()
        )

        transport, protocol = await server.create_serve_endpoint()

        try:
            # Run until interrupted
            await asyncio.Event().wait()
        except KeyboardInterrupt:
            self.print_summary()
        finally:
            transport.close()

    def print_summary(self):
        """Print summary of messages received."""
        print(f"\n\n{'='*60}")
        print("Summary of OSC Messages Received:")
        print(f"{'='*60}\n")

        if not self.message_count:
            print("No messages received!")
            print("\nTroubleshooting:")
            print("1. Is Synesthesia running?")
            print("2. Is OSC output enabled in Synesthesia?")
            print("3. Is Synesthesia configured to send to 127.0.0.1:8000?")
            return

        # Sort by frequency
        sorted_msgs = sorted(self.message_count.items(), key=lambda x: x[1], reverse=True)

        print("Most Common Messages:")
        for address, count in sorted_msgs[:20]:
            args = self.last_messages.get(address, ())
            beat_marker = " ⭐ BEAT!" if "beat" in address.lower() else ""
            print(f"  {count:6} × {address:40} {args}{beat_marker}")

        print(f"\nTotal unique addresses: {len(self.message_count)}")

        # Highlight beat-related
        beat_msgs = [addr for addr in self.message_count.keys() if "beat" in addr.lower() or "bpm" in addr.lower()]
        if beat_msgs:
            print(f"\n{'='*60}")
            print("⭐ BEAT-RELATED MESSAGES FOUND:")
            print(f"{'='*60}")
            for addr in beat_msgs:
                args = self.last_messages.get(addr, ())
                count = self.message_count[addr]
                print(f"  {addr}")
                print(f"    Format: {args}")
                print(f"    Count: {count}")
                print()

            print("💡 Use the address above for beat synchronization in your config!")
        else:
            print("\n⚠️  No beat-related messages detected.")
            print("   Make sure Synesthesia is playing audio and OSC output is enabled.")


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 9999

    monitor = OSCMonitor(port)

    try:
        asyncio.run(monitor.run())
    except KeyboardInterrupt:
        print("\nStopped by user")
