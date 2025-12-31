#!/usr/bin/env python3
"""
VirtualDJ OSC Subscription Test

Tests WHICH subscriptions actually send updates.
Particularly focused on position/time-related values.

VirtualDJ Settings Required:
  - oscPort: 9009 (VDJ listens here)
  - oscPortBack: 9999 (VDJ sends responses here)
"""

import sys
import time
from collections import defaultdict
from typing import Any

try:
    import pyliblo3 as liblo
except ImportError:
    print("Error: pyliblo3 not installed")
    print("Install with: pip install pyliblo3")
    sys.exit(1)

# Configuration
VDJ_HOST = "127.0.0.1"
VDJ_OSC_PORT = 9009
VDJ_OSC_PORT_BACK = 9999

# Track message counts per path
message_counts = defaultdict(int)
message_values = defaultdict(list)
start_time = None


def handle_message(path: str, args: list, types: str, src: Any) -> None:
    """Track all incoming messages."""
    global message_counts, message_values
    message_counts[path] += 1

    # Store last few values (max 5)
    if args:
        val = args[0]
        message_values[path].append(val)
        if len(message_values[path]) > 5:
            message_values[path].pop(0)

    # Print live updates for position-related messages
    elapsed = time.time() - start_time if start_time else 0
    if "pos" in path.lower() or "time" in path.lower() or "beat" in path.lower():
        val_str = f"{args[0]:.4f}" if args and isinstance(args[0], float) else repr(args[0] if args else None)
        print(f"[{elapsed:5.1f}s] {path} = {val_str}  (count: {message_counts[path]})")


def main():
    global start_time

    print("=" * 70)
    print("VirtualDJ OSC Subscription Test")
    print("=" * 70)
    print(f"Send to VDJ:    {VDJ_HOST}:{VDJ_OSC_PORT}")
    print(f"Listen on:      {VDJ_HOST}:{VDJ_OSC_PORT_BACK}")
    print("=" * 70)
    print()

    # Create server
    try:
        server = liblo.Server(VDJ_OSC_PORT_BACK)
    except liblo.ServerError as e:
        print(f"Error binding to port {VDJ_OSC_PORT_BACK}: {e}")
        sys.exit(1)

    server.add_method(None, None, handle_message)
    print(f"✓ Listening on port {VDJ_OSC_PORT_BACK}")

    vdj_target = (VDJ_HOST, VDJ_OSC_PORT)
    start_time = time.time()

    # =========================================================================
    # Test subscriptions - focus on position-related values
    # =========================================================================

    # All position/time related subscriptions to test
    position_subs = [
        # Per-deck position values
        "/vdj/subscribe/deck/1/song_pos",           # 0.0-1.0 position (most useful!)
        "/vdj/subscribe/deck/1/get_time",           # remaining time ms
        "/vdj/subscribe/deck/1/get_elapsed",        # elapsed time?
        "/vdj/subscribe/deck/1/get_position",       # might be same as song_pos
        "/vdj/subscribe/deck/1/get_songpos",        # alternative naming
        "/vdj/subscribe/deck/1/position",           # without get_

        # Beat-related (useful for sync)
        "/vdj/subscribe/deck/1/get_beat",           # beat position
        "/vdj/subscribe/deck/1/beat",               # alternative
        "/vdj/subscribe/deck/1/get_phase",          # phase in bar
        "/vdj/subscribe/deck/1/phase",              # alternative

        # Other potentially useful
        "/vdj/subscribe/deck/1/get_bpm",
        "/vdj/subscribe/deck/1/play",
        "/vdj/subscribe/deck/1/is_audible",
        "/vdj/subscribe/deck/1/level",              # audio level (changes constantly)
        "/vdj/subscribe/deck/1/volume",
        "/vdj/subscribe/deck/1/loaded",
    ]

    # Also test deck 2 for song_pos
    position_subs.append("/vdj/subscribe/deck/2/song_pos")
    position_subs.append("/vdj/subscribe/deck/2/get_time")

    print(f"\nSubscribing to {len(position_subs)} values...")
    print("-" * 70)
    for sub in position_subs:
        liblo.send(vdj_target, sub)
        print(f"  → {sub}")
        time.sleep(0.02)

    # Also query initial values
    print("\nQuerying initial values...")
    queries = [
        "/vdj/query/deck/1/song_pos",
        "/vdj/query/deck/1/get_time",
        "/vdj/query/deck/1/get_songlength",
        "/vdj/query/deck/1/play",
        "/vdj/query/deck/1/get_title",
    ]
    for q in queries:
        liblo.send(vdj_target, q)
        time.sleep(0.02)

    # Start playback for testing
    print("\n" + "=" * 70)
    print("Starting playback on deck 1 to test position updates...")
    print("=" * 70)
    liblo.send(vdj_target, "/vdj/deck/1/play")

    # Listen for updates
    print("\nListening for position updates (10 seconds)...")
    print("Position-related messages will be printed as they arrive.\n")
    print("-" * 70)

    try:
        poll_until = time.time() + 10.0
        while time.time() < poll_until:
            server.recv(100)
    except KeyboardInterrupt:
        print("\nInterrupted")

    # Stop playback
    print("\n" + "-" * 70)
    print("Stopping playback...")
    liblo.send(vdj_target, "/vdj/deck/1/pause")
    time.sleep(0.3)

    # Unsubscribe
    print("Unsubscribing...")
    for sub in position_subs:
        unsub = sub.replace("/subscribe/", "/unsubscribe/")
        liblo.send(vdj_target, unsub)
        time.sleep(0.02)

    # =========================================================================
    # Results Summary
    # =========================================================================
    print("\n" + "=" * 70)
    print("RESULTS: Which subscriptions sent updates?")
    print("=" * 70)

    # Group by whether they received messages
    received = {k: v for k, v in message_counts.items() if v > 0}

    print(f"\n✓ WORKING ({len(received)} paths received messages):")
    print("-" * 70)
    for path in sorted(received.keys()):
        count = received[path]
        vals = message_values.get(path, [])
        val_str = ""
        if vals:
            if isinstance(vals[-1], float):
                val_str = f" (last: {vals[-1]:.4f})"
            else:
                val_str = f" (last: {vals[-1]})"
        print(f"  {path}: {count} messages{val_str}")

    # Show which subscriptions did NOT work
    tested_paths = set()
    for sub in position_subs:
        # Convert subscribe path to response path
        resp_path = sub.replace("/vdj/subscribe/", "/vdj/")
        tested_paths.add(resp_path)

    not_working = tested_paths - set(received.keys())
    if not_working:
        print(f"\n✗ NO RESPONSE ({len(not_working)} paths):")
        print("-" * 70)
        for path in sorted(not_working):
            print(f"  {path}")

    # Key findings
    print("\n" + "=" * 70)
    print("KEY FINDINGS FOR POSITION TRACKING:")
    print("=" * 70)

    # Check song_pos specifically
    song_pos_count = message_counts.get("/vdj/deck/1/song_pos", 0)
    get_time_count = message_counts.get("/vdj/deck/1/get_time", 0)
    beat_count = message_counts.get("/vdj/deck/1/get_beat", 0)
    level_count = message_counts.get("/vdj/deck/1/level", 0)

    print(f"\n  song_pos:   {song_pos_count:3} updates  {'✓ WORKS' if song_pos_count > 0 else '✗ No updates'}")
    print(f"  get_time:   {get_time_count:3} updates  {'✓ WORKS' if get_time_count > 0 else '✗ No updates'}")
    print(f"  get_beat:   {beat_count:3} updates  {'✓ WORKS' if beat_count > 0 else '✗ No updates'}")
    print(f"  level:      {level_count:3} updates  {'✓ WORKS' if level_count > 0 else '✗ No updates'}")

    if song_pos_count > 0:
        print("\n  → Use /vdj/subscribe/deck/N/song_pos for position (0.0-1.0)")
    elif get_time_count > 0:
        print("\n  → Use /vdj/subscribe/deck/N/get_time for position (remaining ms)")
    elif level_count > 0:
        print("\n  → VDJ may only send position on QUERY, not subscription")
        print("    Use periodic queries: /vdj/query/deck/N/song_pos")

    total = sum(message_counts.values())
    print(f"\nTotal messages received: {total}")
    print("\nDone.")


if __name__ == "__main__":
    main()
