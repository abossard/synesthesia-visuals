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

Library: pyliblo3 (C bindings to liblo - faster, cleaner output)
"""

import sys
import time
from typing import Any

try:
    import pyliblo3 as liblo
except ImportError:
    print("Error: pyliblo3 not installed")
    print("Install with: pip install pyliblo3")
    sys.exit(1)


# Configuration
VDJ_HOST = "127.0.0.1"
VDJ_OSC_PORT = 9009       # VirtualDJ oscPort (we send TO this)
VDJ_OSC_PORT_BACK = 9008  # VirtualDJ oscPortBack (we receive FROM this)

# Track received messages
messages_received = 0
start_time = None

# For control test time capture
control_test_times = []


def handle_message(path: str, args: list, types: str, src: Any) -> None:
    """Generic handler for all incoming OSC messages."""
    global messages_received
    messages_received += 1
    
    # Capture time values for control test
    if path == "/vdj/deck/1/get_time" and args:
        control_test_times.append(args[0])
    
    # Format args nicely
    if len(args) == 0:
        args_str = "(no args)"
    elif len(args) == 1:
        # Special formatting for time (show as seconds too)
        if path.endswith("/get_time") and isinstance(args[0], (int, float)):
            args_str = f"{args[0]} ms ({args[0]/1000:.1f}s)"
        elif path.endswith("/play"):
            args_str = "PLAYING" if args[0] else "PAUSED"
        else:
            args_str = repr(args[0])
    else:
        args_str = ", ".join(repr(a) for a in args)
    
    elapsed = time.time() - start_time if start_time else 0
    print(f"[{elapsed:6.2f}s] {path}  →  {args_str}")


def main():
    global start_time
    
    print("=" * 60)
    print("VirtualDJ OSC Test (using pyliblo3)")
    print("=" * 60)
    print(f"Sending to VDJ:      {VDJ_HOST}:{VDJ_OSC_PORT}")
    print(f"Listening on:        {VDJ_HOST}:{VDJ_OSC_PORT_BACK}")
    print("=" * 60)
    print()
    
    # Create OSC server to receive messages from VDJ
    try:
        server = liblo.Server(VDJ_OSC_PORT_BACK)
    except liblo.ServerError as e:
        print(f"Error: Could not bind to port {VDJ_OSC_PORT_BACK}: {e}")
        print("Is another application using this port?")
        sys.exit(1)
    
    # Register catch-all handler (None, None = match any path/types)
    server.add_method(None, None, handle_message)
    
    print(f"✓ OSC server listening on port {VDJ_OSC_PORT_BACK}")
    print()
    
    # Target address for sending to VDJ
    vdj_target = (VDJ_HOST, VDJ_OSC_PORT)
    
    start_time = time.time()
    
    # =========================================================================
    # PHASE 0: Control test - Play, wait, verify time, stop
    # =========================================================================
    print("─" * 60)
    print("Phase 0: Control test (play → wait → verify → stop)")
    print("─" * 60)
    
    # Clear time captures
    control_test_times.clear()
    initial_msg_count = messages_received
    
    # Query initial state
    print("Querying initial play state and time...")
    liblo.send(vdj_target, "/vdj/query/deck/1/play")
    liblo.send(vdj_target, "/vdj/query/deck/1/get_time")
    poll_until = time.time() + 0.5
    while time.time() < poll_until:
        server.recv(50)
    
    # Send PLAY command
    print("\n▶ Sending PLAY command to deck 1...")
    liblo.send(vdj_target, "/vdj/deck/1/play")
    time.sleep(0.2)
    
    # Query play state to confirm
    liblo.send(vdj_target, "/vdj/query/deck/1/play")
    poll_until = time.time() + 0.3
    while time.time() < poll_until:
        server.recv(50)
    
    # Wait 3 seconds
    print("\n⏳ Waiting 3 seconds while playing...")
    wait_start = time.time()
    while time.time() - wait_start < 3.0:
        server.recv(100)  # Keep polling to receive any updates
    
    # Query elapsed time AFTER waiting
    print("\n📊 Querying elapsed time after 3 seconds...")
    liblo.send(vdj_target, "/vdj/query/deck/1/get_time")
    poll_until = time.time() + 0.5
    while time.time() < poll_until:
        server.recv(50)
    
    # Send PAUSE command
    print("\n⏸ Sending PAUSE command to deck 1...")
    liblo.send(vdj_target, "/vdj/deck/1/pause")
    time.sleep(0.2)
    
    # Verify paused
    liblo.send(vdj_target, "/vdj/query/deck/1/play")
    poll_until = time.time() + 0.3
    while time.time() < poll_until:
        server.recv(50)
    
    # Verify time advanced using captured values
    print()
    if len(control_test_times) >= 2:
        time_before = control_test_times[0]
        time_after = control_test_times[1]
        # Note: get_time returns REMAINING time (counts down), so we compute before - after
        delta = time_before - time_after
        print(f"⏱ Time verification:")
        print(f"   Before: {time_before} ms ({time_before/1000:.1f}s remaining)")
        print(f"   After:  {time_after} ms ({time_after/1000:.1f}s remaining)")
        print(f"   Delta:  {delta} ms ({delta/1000:.1f}s played)")
        if 2500 < delta < 4000:
            print("   ✅ Playback confirmed! (~3 seconds elapsed as expected)")
        elif delta > 0:
            print(f"   ⚠️  Time advanced but not by expected ~3s")
        else:
            print("   ❌ Time did not advance (playback may not have started)")
    else:
        print("⚠️ Could not capture time values for verification")
    
    control_msgs = messages_received - initial_msg_count
    print(f"\n✓ Control test complete ({control_msgs} messages during control phase)")
    print()
    
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
        liblo.send(vdj_target, query)
        time.sleep(0.02)  # Small delay between messages
    
    # Wait for responses (poll server)
    print("Waiting for responses...")
    poll_until = time.time() + 1.0
    while time.time() < poll_until:
        server.recv(50)  # 50ms timeout per recv
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
        liblo.send(vdj_target, sub)
        time.sleep(0.02)
    
    print("Listening for updates (move crossfader or change tracks to see updates)...")
    print()
    
    # Listen for live updates (poll server for 5 seconds)
    try:
        poll_until = time.time() + 5.0
        while time.time() < poll_until:
            server.recv(100)  # 100ms timeout per recv
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
        liblo.send(vdj_target, unsub)
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
    
    # Server cleanup (no explicit shutdown needed with pyliblo3)
    print()
    print("Done.")


if __name__ == "__main__":
    main()
