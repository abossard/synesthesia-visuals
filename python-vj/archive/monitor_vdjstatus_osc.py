#!/usr/bin/env python3
"""
Monitor OSC messages from VDJStatus.app.

Simple OSC listener that displays messages received from the native VDJStatus macOS app.
Does NOT integrate with python-vj - this is purely for monitoring/testing.
"""

import time
import argparse
from pythonosc import dispatcher, osc_server


def handle_deck1(unused_addr, artist, title, elapsed, fader):
    """Handle /vdj/deck1 OSC message."""
    print(f"[Deck 1] {artist} - {title}")
    print(f"         Elapsed: {elapsed:.1f}s, Fader: {fader:.2f}")


def handle_deck2(unused_addr, artist, title, elapsed, fader):
    """Handle /vdj/deck2 OSC message."""
    print(f"[Deck 2] {artist} - {title}")
    print(f"         Elapsed: {elapsed:.1f}s, Fader: {fader:.2f}")


def handle_master(unused_addr, deck_num):
    """Handle /vdj/master OSC message."""
    print(f"[Master] Deck {deck_num}")


def handle_performance(unused_addr, d1_conf, d2_conf):
    """Handle /vdj/performance OSC message."""
    print(f"[Performance] Deck 1 confidence: {d1_conf:.2f}, Deck 2 confidence: {d2_conf:.2f}")


def monitor_osc(host="127.0.0.1", port=9001):
    """Start OSC server and monitor messages from VDJStatus.app."""
    print("=" * 60)
    print(f"VDJStatus OSC Monitor")
    print(f"Listening on {host}:{port}")
    print("=" * 60)
    print()
    print("Waiting for messages from VDJStatus.app...")
    print("Press Ctrl+C to stop")
    print()
    
    # Create dispatcher and map handlers
    disp = dispatcher.Dispatcher()
    disp.map("/vdj/deck1", handle_deck1)
    disp.map("/vdj/deck2", handle_deck2)
    disp.map("/vdj/master", handle_master)
    disp.map("/vdj/performance", handle_performance)
    
    # Start server
    server = osc_server.ThreadingOSCUDPServer((host, port), disp)
    
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\n\nShutting down...")
        server.shutdown()


if __name__ == '__main__':
    parser = argparse.ArgumentParser(
        description='Monitor OSC messages from VDJStatus.app',
        epilog='Example: python test_vdjstatus_osc.py --port 9001'
    )
    parser.add_argument('--host', type=str, default="127.0.0.1", help='OSC host (default: 127.0.0.1)')
    parser.add_argument('--port', type=int, default=9001, help='OSC port (default: 9001)')
    args = parser.parse_args()
    
    monitor_osc(host=args.host, port=args.port)
