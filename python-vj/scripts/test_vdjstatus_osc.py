#!/usr/bin/env python3
"""
Test VDJStatusOSCMonitor integration.

Simulates OSC messages from VDJStatus.app and tests Python adapter.
"""

import time
import threading
from pythonosc import udp_client

# Import the adapter
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent.parent))

from adapters import VDJStatusOSCMonitor


def send_test_messages(port: int = 9001, count: int = 5):
    """Send test OSC messages simulating VDJStatus.app."""
    client = udp_client.SimpleUDPClient("127.0.0.1", port)
    
    print(f"\n=== Sending {count} test messages to port {port} ===")
    
    for i in range(count):
        # Send deck 1 info
        artist1 = f"Artist {i+1}"
        title1 = f"Track {i+1}"
        elapsed1 = 120.0 + i * 10
        fader1 = 0.8 - (i * 0.1)
        
        client.send_message("/vdj/deck1", [artist1, title1, elapsed1, fader1])
        print(f"  → /vdj/deck1: {artist1} - {title1} @ {elapsed1:.1f}s, fader={fader1:.2f}")
        
        # Send deck 2 info
        artist2 = f"Artist {i+10}"
        title2 = f"Track {i+10}"
        elapsed2 = 60.0 + i * 5
        fader2 = 0.5 + (i * 0.05)
        
        client.send_message("/vdj/deck2", [artist2, title2, elapsed2, fader2])
        print(f"  → /vdj/deck2: {artist2} - {title2} @ {elapsed2:.1f}s, fader={fader2:.2f}")
        
        # Send master deck (alternating)
        master = 1 if i % 2 == 0 else 2
        client.send_message("/vdj/master", [master])
        print(f"  → /vdj/master: {master}")
        
        # Send performance metrics
        d1_conf = 0.85 + (i * 0.02)
        d2_conf = 0.90 - (i * 0.02)
        client.send_message("/vdj/performance", [d1_conf, d2_conf])
        print(f"  → /vdj/performance: d1={d1_conf:.2f}, d2={d2_conf:.2f}")
        
        print()
        time.sleep(0.5)


def test_monitor():
    """Test VDJStatusOSCMonitor."""
    print("=== Testing VDJStatusOSCMonitor ===\n")
    
    # Create monitor (starts OSC server)
    print("Creating monitor (OSC server on port 9001)...")
    monitor = VDJStatusOSCMonitor(osc_host="127.0.0.1", osc_port=9001)
    
    # Wait for server to start
    time.sleep(1)
    
    # Check initial status
    print(f"Initial status: {monitor.status}")
    print()
    
    # Start sender thread
    sender_thread = threading.Thread(target=send_test_messages, args=(9001, 5))
    sender_thread.start()
    
    # Wait for messages and poll monitor
    time.sleep(1)  # Wait for first message
    
    print("=== Reading playback from monitor ===")
    for i in range(6):
        time.sleep(0.5)
        
        playback = monitor.get_playback()
        status = monitor.status
        
        print(f"\n[{i+1}] Playback:")
        if playback:
            print(f"  Artist: {playback['artist']}")
            print(f"  Title: {playback['title']}")
            print(f"  Progress: {playback['progress_ms']/1000:.1f}s")
            print(f"  Status: {status.get('label', 'unknown')}")
            print(f"  Master Deck: {status.get('master_deck', '?')}")
            print(f"  Confidence: D1={status.get('deck1_confidence', 0):.2f}, D2={status.get('deck2_confidence', 0):.2f}")
        else:
            print(f"  No playback (status: {status.get('label', 'unknown')})")
    
    # Wait for sender to finish
    sender_thread.join()
    
    # Cleanup
    print("\n=== Shutting down ===")
    monitor.shutdown()
    print("Done!")


if __name__ == '__main__':
    import argparse
    
    parser = argparse.ArgumentParser(description='Test VDJStatus OSC integration')
    parser.add_argument('--send-only', action='store_true', help='Only send test messages (no monitor)')
    parser.add_argument('--port', type=int, default=9001, help='OSC port (default: 9001)')
    args = parser.parse_args()
    
    if args.send_only:
        send_test_messages(port=args.port, count=10)
    else:
        test_monitor()
