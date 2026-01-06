#!/usr/bin/env python3
"""
VirtualDJ OSC Listen Test

This test does NOT control playback - just subscribes and listens.
Start playback in VDJ BEFORE running this test!
"""

import sys
import time
from collections import defaultdict
from typing import Any

try:
    import pyliblo3 as liblo
except ImportError:
    print("Error: pyliblo3 not installed")
    sys.exit(1)

VDJ_HOST = "127.0.0.1"
VDJ_OSC_PORT = 9009
VDJ_OSC_PORT_BACK = 9999

message_counts = defaultdict(int)
message_values = {}
start_time = None


def handle_message(path: str, args: list, types: str, src: Any) -> None:
    global message_counts, message_values
    message_counts[path] += 1
    if args:
        message_values[path] = args[0]

    elapsed = time.time() - start_time if start_time else 0
    val = args[0] if args else None
    if isinstance(val, float):
        val_str = f"{val:.4f}"
    elif isinstance(val, str) and len(val) > 30:
        val_str = val[:30] + "..."
    else:
        val_str = repr(val)
    print(f"[{elapsed:5.2f}s] {path} = {val_str}  (#{message_counts[path]})")


def main():
    global start_time

    print("=" * 70)
    print("VirtualDJ OSC Listen Test")
    print("=" * 70)
    print("⚠️  Make sure a track is PLAYING in VDJ before running this!")
    print("    This test will NOT control playback.")
    print("=" * 70)
    print()

    try:
        server = liblo.Server(VDJ_OSC_PORT_BACK)
    except liblo.ServerError as e:
        print(f"Error: {e}")
        sys.exit(1)

    server.add_method(None, None, handle_message)
    vdj_target = (VDJ_HOST, VDJ_OSC_PORT)
    start_time = time.time()

    # All verbs to test
    test_verbs = [
        # Position/time
        "song_pos", "get_time", "get_beatpos", "get_beat_num",
        # Beat/level
        "get_beat", "get_level", "get_level_left", "get_level_right",
        "get_vu_meter", "get_beatgrid",
        # State
        "play", "is_audible", "volume", "level",
        # Info
        "get_bpm", "get_title", "get_artist",
    ]

    # =========================================================================
    # Phase 1: Subscribe to everything
    # =========================================================================
    print("Subscribing to all verbs...")
    for verb in test_verbs:
        liblo.send(vdj_target, f"/vdj/subscribe/deck/1/{verb}")
        time.sleep(0.01)

    print(f"Subscribed to {len(test_verbs)} verbs")
    print()

    # =========================================================================
    # Phase 2: Listen for subscription updates (10 sec)
    # =========================================================================
    print("-" * 70)
    print("Phase 1: SUBSCRIPTION ONLY (listening 10 seconds)")
    print("         Keep VDJ playing! Watch for pushed updates...")
    print("-" * 70)

    sub_start = dict(message_counts)
    try:
        poll_until = time.time() + 10.0
        while time.time() < poll_until:
            server.recv(50)
    except KeyboardInterrupt:
        print("\nInterrupted")

    sub_counts = {k: v - sub_start.get(k, 0) for k, v in message_counts.items()}
    sub_total = sum(v for v in sub_counts.values() if v > 0)
    print(f"\n→ Subscription phase: {sub_total} messages received")

    # =========================================================================
    # Phase 3: Polling comparison (5 sec)
    # =========================================================================
    print()
    print("-" * 70)
    print("Phase 2: POLLING (query every 100ms for 5 seconds)")
    print("-" * 70)

    poll_start = dict(message_counts)
    poll_until = time.time() + 5.0
    last_query = 0
    poll_verbs = ["song_pos", "get_beat", "get_level", "get_beatpos"]

    while time.time() < poll_until:
        now = time.time()
        if now - last_query >= 0.1:
            for verb in poll_verbs:
                liblo.send(vdj_target, f"/vdj/query/deck/1/{verb}")
            last_query = now
        server.recv(30)

    poll_counts = {k: v - poll_start.get(k, 0) for k, v in message_counts.items()}
    poll_total = sum(v for v in poll_counts.values() if v > 0)
    print(f"\n→ Polling phase: {poll_total} messages received")

    # Unsubscribe
    for verb in test_verbs:
        liblo.send(vdj_target, f"/vdj/unsubscribe/deck/1/{verb}")
        time.sleep(0.01)

    # =========================================================================
    # Results
    # =========================================================================
    print()
    print("=" * 70)
    print("RESULTS COMPARISON")
    print("=" * 70)
    print()
    print(f"{'Verb':<20} {'Subscribe (10s)':>15} {'Poll (5s)':>15} {'Method'}")
    print("-" * 70)

    for verb in test_verbs:
        path = f"/vdj/deck/1/{verb}"
        s = sub_counts.get(path, 0)
        p = poll_counts.get(path, 0)

        if s > 5:
            method = "✓ SUBSCRIBE WORKS!"
        elif p > 5:
            method = "→ Needs polling"
        elif s > 0 or p > 0:
            method = "~ Partial"
        else:
            method = "✗ No data"

        print(f"{verb:<20} {s:>15} {p:>15}   {method}")

    # Key conclusion
    print()
    print("=" * 70)
    print("CONCLUSION")
    print("=" * 70)

    sub_working = [v for v in test_verbs if sub_counts.get(f"/vdj/deck/1/{v}", 0) > 5]

    if sub_working:
        print("\n✓ These subscriptions PUSH updates continuously:")
        for v in sub_working:
            c = sub_counts.get(f"/vdj/deck/1/{v}", 0)
            print(f"    /vdj/subscribe/deck/N/{v}  ({c} msgs in 10s)")
    else:
        print("\n✗ NO subscriptions pushed continuous updates during playback")
        print("  VirtualDJ requires POLLING for real-time data:")
        print("    /vdj/query/deck/N/song_pos")
        print("    /vdj/query/deck/N/get_beat")
        print("    /vdj/query/deck/N/get_level")

    print("\nDone.")


if __name__ == "__main__":
    main()
