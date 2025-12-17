#!/usr/bin/env python3
"""
VirtualDJ OSC Test Script

Tests bidirectional OSC communication with VirtualDJ.
Sends queries and subscriptions, prints responses, then exits.

VirtualDJ Settings Required:
  - oscPort: 9009 (VDJ listens here)
  - oscPortBack: 9008 (VDJ sends responses here)

Usage:
  python vdj_osc_test.py
"""

import sys
import time
import threading
from typing import Any

try:
    from pythonosc import udp_client, dispatcher, osc_server
except ImportError:
    print("Error: python-osc not installed")
    print("Install with: pip install python-osc")
    sys.exit(1)


# Configuration
VDJ_HOST = "127.0.0.1"
VDJ_OSC_PORT = 9009       # VirtualDJ oscPort (we send TO this)
VDJ_OSC_PORT_BACK = 9008  # VirtualDJ oscPortBack (we receive FROM this)

# Track received messages
messages_received = 0
start_time = None


def handle_message(address: str, *args: Any) -> None:
    """Generic handler for all incoming OSC messages."""
    global messages_received
    messages_received += 1
    
    # Format args nicely
    if len(args) == 0:
        args_str = "(no args)"
    elif len(args) == 1:
        args_str = repr(args[0])
    else:
        args_str = ", ".join(repr(a) for a in args)
    
    elapsed = time.time() - start_time if start_time else 0
    print(f"[{elapsed:6.2f}s] {address}  →  {args_str}")


def main():
    global start_time
    
    print("=" * 60)
    print("VirtualDJ OSC Test")
    print("=" * 60)
    print(f"Sending to VDJ:      {VDJ_HOST}:{VDJ_OSC_PORT}")
    print(f"Listening on:        {VDJ_HOST}:{VDJ_OSC_PORT_BACK}")
    print("=" * 60)
    print()
    
    # Create OSC client to send messages to VDJ
    client = udp_client.SimpleUDPClient(VDJ_HOST, VDJ_OSC_PORT)
    
    # Create dispatcher to handle incoming messages
    disp = dispatcher.Dispatcher()
    disp.set_default_handler(handle_message)  # Catch all messages
    
    # Create and start OSC server to receive messages from VDJ
    try:
        server = osc_server.ThreadingOSCUDPServer(
            (VDJ_HOST, VDJ_OSC_PORT_BACK), disp
        )
    except OSError as e:
        print(f"Error: Could not bind to port {VDJ_OSC_PORT_BACK}: {e}")
        print("Is another application using this port?")
        sys.exit(1)
    
    server_thread = threading.Thread(target=server.serve_forever, daemon=True)
    server_thread.start()
    print(f"✓ OSC server listening on port {VDJ_OSC_PORT_BACK}")
    print()
    
    start_time = time.time()
    
    # =========================================================================
    # PHASE 1: Query current state
    # =========================================================================
    print("─" * 60)
    print("Phase 1: Querying current state...")
    print("─" * 60)
    
    queries = [
        # Deck 1: Track info
        "/vdj/query/deck/1/get_artist",
        "/vdj/query/deck/1/get_title",
        "/vdj/query/deck/1/get_bpm",
        "/vdj/query/deck/1/play",
        "/vdj/query/deck/1/is_audible",
        
        # Deck 1: Time & position
        "/vdj/query/deck/1/get_time",
        "/vdj/query/deck/1/get_songlength",
        "/vdj/query/deck/1/song_pos",
        
        # Deck 1: Volume faders (not crossfader)
        "/vdj/query/deck/1/volume",
        "/vdj/query/deck/1/level",
        "/vdj/query/deck/1/gain",
        
        # Deck 2: Track info
        "/vdj/query/deck/2/get_artist",
        "/vdj/query/deck/2/get_title",
        "/vdj/query/deck/2/get_bpm",
        "/vdj/query/deck/2/play",
        "/vdj/query/deck/2/is_audible",
        
        # Deck 2: Time & position
        "/vdj/query/deck/2/get_time",
        "/vdj/query/deck/2/get_songlength",
        "/vdj/query/deck/2/song_pos",
        
        # Deck 2: Volume faders (not crossfader)
        "/vdj/query/deck/2/volume",
        "/vdj/query/deck/2/level",
        "/vdj/query/deck/2/gain",
        
        # Mixer state
        "/vdj/query/crossfader",
        "/vdj/query/get_crossfader_result",
        
        # Master/active deck
        "/vdj/query/get_activedeck",
    ]
    
    print(f"Sending {len(queries)} queries...")
    for query in queries:
        client.send_message(query, [])
        time.sleep(0.02)  # Small delay between messages
    
    # Wait for responses
    print("Waiting for responses...")
    time.sleep(1.0)
    print()
    
    # =========================================================================
    # PHASE 2: Subscribe to live updates
    # =========================================================================
    print("─" * 60)
    print("Phase 2: Subscribing to live updates (5 seconds)...")
    print("─" * 60)
    
    subscriptions = [
        # Deck 1
        "/vdj/subscribe/deck/1/get_bpm",
        "/vdj/subscribe/deck/1/get_title",
        "/vdj/subscribe/deck/1/is_audible",
        "/vdj/subscribe/deck/1/get_beat",
        "/vdj/subscribe/deck/1/volume",
        "/vdj/subscribe/deck/1/get_time",
        
        # Deck 2
        "/vdj/subscribe/deck/2/get_bpm",
        "/vdj/subscribe/deck/2/get_title",
        "/vdj/subscribe/deck/2/is_audible",
        "/vdj/subscribe/deck/2/volume",
        "/vdj/subscribe/deck/2/get_time",
        
        # Mixer
        "/vdj/subscribe/crossfader",
    ]
    
    print(f"Subscribing to {len(subscriptions)} values...")
    for sub in subscriptions:
        client.send_message(sub, [])
        time.sleep(0.02)
    
    print("Listening for updates (move crossfader or change tracks to see updates)...")
    print()
    
    # Listen for live updates
    try:
        time.sleep(5.0)
    except KeyboardInterrupt:
        print("\nInterrupted by user")
    
    # =========================================================================
    # PHASE 3: Unsubscribe and cleanup
    # =========================================================================
    print()
    print("─" * 60)
    print("Phase 3: Cleaning up...")
    print("─" * 60)
    
    # Unsubscribe
    for sub in subscriptions:
        unsub = sub.replace("/subscribe/", "/unsubscribe/")
        client.send_message(unsub, [])
        time.sleep(0.02)
    
    print(f"Unsubscribed from {len(subscriptions)} values")
    
    # Summary
    print()
    print("=" * 60)
    print("Summary")
    print("=" * 60)
    elapsed = time.time() - start_time
    print(f"Total messages received: {messages_received}")
    print(f"Elapsed time: {elapsed:.1f}s")
    
    if messages_received == 0:
        print()
        print("⚠️  No messages received from VirtualDJ!")
        print("   Check that:")
        print(f"   1. VirtualDJ is running")
        print(f"   2. oscPort is set to {VDJ_OSC_PORT} in VirtualDJ settings")
        print(f"   3. oscPortBack is set to {VDJ_OSC_PORT_BACK} in VirtualDJ settings")
        print(f"   4. You have a VirtualDJ PRO license (OSC requires PRO)")
    else:
        print("✓ Communication successful!")
    
    # Shutdown server
    server.shutdown()
    print()
    print("Done.")


if __name__ == "__main__":
    main()
