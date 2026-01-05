#!/usr/bin/env python3
"""
VirtualDJ Position Test - Query vs Subscribe

Tests whether position updates come from subscriptions or require polling.
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
last_values = {}
start_time = None


def handle_message(path: str, args: list, types: str, src: Any) -> None:
    global message_counts, last_values
    message_counts[path] += 1
    if args:
        last_values[path] = args[0]

    elapsed = time.time() - start_time if start_time else 0
    # Print all messages to see what comes in
    if args:
        val = args[0]
        if isinstance(val, float):
            print(f"[{elapsed:5.2f}s] {path} = {val:.4f}")
        else:
            print(f"[{elapsed:5.2f}s] {path} = {val}")


def main():
    global start_time

    print("=" * 60)
    print("VirtualDJ Position: Query vs Subscribe Test")
    print("=" * 60)

    try:
        server = liblo.Server(VDJ_OSC_PORT_BACK)
    except liblo.ServerError as e:
        print(f"Error: {e}")
        sys.exit(1)

    server.add_method(None, None, handle_message)
    vdj_target = (VDJ_HOST, VDJ_OSC_PORT)
    start_time = time.time()

    # Subscribe to position-related values
    subs = [
        "/vdj/subscribe/deck/1/song_pos",
        "/vdj/subscribe/deck/1/get_time",
        "/vdj/subscribe/deck/1/get_beat",
        "/vdj/subscribe/deck/1/level",
        "/vdj/subscribe/deck/1/play",
    ]

    print("\n1. Subscribing to position values...")
    for sub in subs:
        liblo.send(vdj_target, sub)
        time.sleep(0.02)

    # Start playback
    print("\n2. Starting playback...")
    liblo.send(vdj_target, "/vdj/deck/1/play")
    time.sleep(0.3)

    # Phase 1: Wait for subscription updates (5 sec)
    print("\n" + "-" * 60)
    print("Phase 1: SUBSCRIPTION ONLY (5 seconds)")
    print("Waiting for pushed updates...")
    print("-" * 60)
    sub_start = time.time()
    sub_count_before = dict(message_counts)

    poll_end = time.time() + 5.0
    while time.time() < poll_end:
        server.recv(100)

    sub_count_after = dict(message_counts)
    sub_updates = {k: sub_count_after.get(k, 0) - sub_count_before.get(k, 0)
                   for k in set(sub_count_after) | set(sub_count_before)}
    sub_total = sum(v for v in sub_updates.values() if v > 0)
    print(f"\n→ Received {sub_total} messages during subscription phase")

    # Phase 2: Active polling (5 sec)
    print("\n" + "-" * 60)
    print("Phase 2: ACTIVE POLLING (5 seconds, query every 100ms)")
    print("-" * 60)
    poll_count_before = dict(message_counts)

    poll_end = time.time() + 5.0
    query_interval = 0.1  # 100ms
    last_query = 0

    while time.time() < poll_end:
        now = time.time()
        if now - last_query >= query_interval:
            liblo.send(vdj_target, "/vdj/query/deck/1/song_pos")
            last_query = now
        server.recv(50)

    poll_count_after = dict(message_counts)
    poll_updates = {k: poll_count_after.get(k, 0) - poll_count_before.get(k, 0)
                    for k in set(poll_count_after) | set(poll_count_before)}
    poll_total = sum(v for v in poll_updates.values() if v > 0)
    print(f"\n→ Received {poll_total} messages during polling phase")

    # Stop playback
    print("\n3. Stopping playback...")
    liblo.send(vdj_target, "/vdj/deck/1/pause")

    # Unsubscribe
    for sub in subs:
        liblo.send(vdj_target, sub.replace("/subscribe/", "/unsubscribe/"))
        time.sleep(0.02)

    # Results
    print("\n" + "=" * 60)
    print("RESULTS")
    print("=" * 60)
    print(f"\nSubscription phase: {sub_total} updates")
    print(f"Polling phase:      {poll_total} updates")

    print("\nMessage breakdown:")
    for path in sorted(message_counts.keys()):
        count = message_counts[path]
        val = last_values.get(path)
        val_str = f" (last: {val:.4f})" if isinstance(val, float) else f" (last: {val})"
        print(f"  {path}: {count}{val_str}")

    print("\n" + "=" * 60)
    print("CONCLUSION")
    print("=" * 60)
    if poll_total > sub_total * 2:
        print("→ VDJ position requires POLLING, subscriptions don't push continuously")
        print("→ Use periodic /vdj/query/deck/N/song_pos for position tracking")
    elif sub_total > 5:
        print("→ VDJ subscriptions DO push position updates")
        print("→ Use /vdj/subscribe/deck/N/song_pos")
    else:
        print("→ Neither method produced many updates")
        print("→ Check VDJ is playing and OSC is configured correctly")

    print("\nDone.")


if __name__ == "__main__":
    main()
