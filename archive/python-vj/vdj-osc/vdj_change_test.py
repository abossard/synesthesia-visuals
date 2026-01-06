#!/usr/bin/env python3
"""
VirtualDJ Change Events Test

Tests which subscriptions fire when values CHANGE.
(Position doesn't work, but play/stop, crossfader, track load might)
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

message_log = []
start_time = None


def handle_message(path: str, args: list, types: str, src: Any) -> None:
    elapsed = time.time() - start_time if start_time else 0
    val = args[0] if args else None

    # Format value
    if isinstance(val, float):
        val_str = f"{val:.4f}"
    elif isinstance(val, str) and len(val) > 40:
        val_str = val[:40] + "..."
    else:
        val_str = repr(val)

    message_log.append((elapsed, path, val_str))
    print(f"[{elapsed:5.2f}s] {path} = {val_str}")


def main():
    global start_time

    print("=" * 70)
    print("VirtualDJ Change Events Test")
    print("=" * 70)
    print("Testing which subscriptions fire on VALUE CHANGES")
    print()

    try:
        server = liblo.Server(VDJ_OSC_PORT_BACK)
    except liblo.ServerError as e:
        print(f"Error: {e}")
        sys.exit(1)

    server.add_method(None, None, handle_message)
    vdj_target = (VDJ_HOST, VDJ_OSC_PORT)
    start_time = time.time()

    # Subscribe to change-based values
    subs = [
        # Play state
        "/vdj/subscribe/deck/1/play",
        "/vdj/subscribe/deck/2/play",

        # Audible state
        "/vdj/subscribe/deck/1/is_audible",
        "/vdj/subscribe/deck/2/is_audible",

        # Volume/crossfader (might fire on change)
        "/vdj/subscribe/deck/1/volume",
        "/vdj/subscribe/deck/2/volume",
        "/vdj/subscribe/crossfader",

        # Track info (fires on load)
        "/vdj/subscribe/deck/1/get_title",
        "/vdj/subscribe/deck/1/get_artist",
        "/vdj/subscribe/deck/1/get_bpm",

        # Beat (might fire per beat)
        "/vdj/subscribe/deck/1/get_beat",

        # Level (audio level, might update constantly)
        "/vdj/subscribe/deck/1/level",
        "/vdj/subscribe/masterlevel",
    ]

    print("Subscribing to change-based values...")
    for sub in subs:
        liblo.send(vdj_target, sub)
        time.sleep(0.02)

    print("\n" + "-" * 70)
    print("Now triggering changes... (8 seconds)")
    print("-" * 70)

    # Action 1: Play
    print("\n► [1s] Sending PLAY to deck 1...")
    time.sleep(1.0)
    while time.time() - start_time < 1.0:
        server.recv(50)
    liblo.send(vdj_target, "/vdj/deck/1/play")

    # Wait and listen
    while time.time() - start_time < 3.0:
        server.recv(50)

    # Action 2: Pause
    print("\n► [3s] Sending PAUSE to deck 1...")
    liblo.send(vdj_target, "/vdj/deck/1/pause")

    # Wait and listen
    while time.time() - start_time < 5.0:
        server.recv(50)

    # Action 3: Play again
    print("\n► [5s] Sending PLAY again...")
    liblo.send(vdj_target, "/vdj/deck/1/play")

    # Wait and listen
    while time.time() - start_time < 7.0:
        server.recv(50)

    # Action 4: Stop
    print("\n► [7s] Sending PAUSE (final)...")
    liblo.send(vdj_target, "/vdj/deck/1/pause")

    # Wait
    while time.time() - start_time < 8.0:
        server.recv(50)

    # Unsubscribe
    for sub in subs:
        liblo.send(vdj_target, sub.replace("/subscribe/", "/unsubscribe/"))
        time.sleep(0.02)

    # Results
    print("\n" + "=" * 70)
    print("RESULTS: Messages received during change events")
    print("=" * 70)

    # Count by path
    counts = defaultdict(int)
    for _, path, _ in message_log:
        counts[path] += 1

    for path in sorted(counts.keys()):
        count = counts[path]
        status = "✓ WORKS" if count > 0 else ""
        print(f"  {path}: {count} {status}")

    # Check which worked
    print("\n" + "=" * 70)
    print("SUMMARY: Working subscriptions")
    print("=" * 70)

    working = [p for p, c in counts.items() if c > 0]
    not_working = set(sub.replace("/vdj/subscribe/", "/vdj/") for sub in subs) - set(counts.keys())

    if working:
        print("\n✓ WORKING (fire on change):")
        for p in sorted(working):
            print(f"    {p}")

    if not_working:
        print("\n✗ NOT WORKING (no messages received):")
        for p in sorted(not_working):
            print(f"    {p}")

    print("\n" + "=" * 70)
    print("KEY FINDINGS:")
    print("=" * 70)
    print("""
Position tracking:
  - song_pos: Requires POLLING with /vdj/query/deck/N/song_pos
  - Subscriptions do NOT push position continuously

Change events:
  - Subscriptions MAY fire when values change (play/stop, track load)
  - But VDJ seems inconsistent about pushing vs requiring queries

Recommended approach:
  1. Subscribe to is_audible, get_title, get_bpm (change on track load/mix)
  2. POLL song_pos every 100-200ms for position tracking
  3. Use /vdj/query/... for any value you need immediately
""")

    print("Done.")


if __name__ == "__main__":
    main()
