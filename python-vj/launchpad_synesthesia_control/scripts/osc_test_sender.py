#!/usr/bin/env python3
"""
OSC Test Sender - Send test OSC messages to port 8000

This script sends test OSC messages to verify the app is receiving correctly.
Run this while the TUI is running to test OSC reception.

Usage:
    python scripts/osc_test_sender.py
"""

import time
from pythonosc import udp_client


def main():
    print("\n" + "="*60)
    print("OSC Test Sender - Sending to 127.0.0.1:9999")
    print("="*60)
    print("\nThis will send test OSC messages to your app.")
    print("Watch the OSC Monitor panel in the TUI to see them appear.\n")

    # Create client that sends TO port 9999 (where app listens)
    client = udp_client.SimpleUDPClient("127.0.0.1", 9999)

    messages = [
        ("/scenes/TestScene1", []),
        ("/scenes/TestScene2", []),
        ("/presets/TestPreset", []),
        ("/audio/beat/onbeat", [1]),
        ("/audio/beat/onbeat", [0]),
        ("/controls/meta/hue", [0.5]),
        ("/controls/meta/saturation", [0.8]),
        ("/audio/bpm", [128]),
    ]

    print("Sending test messages...")
    for i, (address, args) in enumerate(messages, 1):
        print(f"  {i}. Sending: {address} {args}")
        client.send_message(address, args)
        time.sleep(0.5)

    print("\n" + "="*60)
    print("✓ All test messages sent!")
    print("="*60)
    print("\nCheck the TUI OSC Monitor panel:")
    print("  - Should show ~8 messages")
    print("  - Green ✓ = controllable messages")
    print("  - Cyan · = non-controllable messages")
    print("  - Total counter should increment")
    print("\nIf you see messages → OSC receiving is working!")
    print("If no messages → Check firewall or network settings")
    print()


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\n\nStopped by user")
    except Exception as e:
        print(f"\nError: {e}")
        print("\nMake sure python-osc is installed:")
        print("  pip install python-osc")
