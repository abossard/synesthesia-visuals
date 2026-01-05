#!/usr/bin/env python3
"""
VirtualDJ OSC Final Test

1. Query all verbs first to verify they work
2. Subscribe and see which ones push updates
3. Definitively determine what needs polling vs subscribing
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
    print("VirtualDJ OSC Final Test")
    print("=" * 70)

    try:
        server = liblo.Server(VDJ_OSC_PORT_BACK)
    except liblo.ServerError as e:
        print(f"Error: {e}")
        sys.exit(1)

    server.add_method(None, None, handle_message)
    vdj_target = (VDJ_HOST, VDJ_OSC_PORT)
    start_time = time.time()

    # Key verbs to test
    test_verbs = [
        # Most likely to work for real-time
        "get_beat",
        "get_level",
        "level",
        "song_pos",
        "get_time",
        "play",
        "is_audible",
        "volume",
        "get_bpm",
        "get_beatpos",
        "get_beat_num",
    ]

    # =========================================================================
    # Phase 1: QUERY to verify VDJ is responding
    # =========================================================================
    print("\n" + "-" * 70)
    print("Phase 1: QUERY test (verify VDJ responds)")
    print("-" * 70)

    for verb in test_verbs:
        liblo.send(vdj_target, f"/vdj/query/deck/1/{verb}")
        time.sleep(0.02)

    print(f"Sent {len(test_verbs)} queries, waiting for responses...")
    poll_until = time.time() + 1.5
    while time.time() < poll_until:
        server.recv(50)

    query_responses = sum(message_counts.values())
    print(f"\n→ Received {query_responses} responses from queries")

    if query_responses == 0:
        print("\n⚠️  VDJ not responding! Check:")
        print("    1. VirtualDJ is running")
        print("    2. oscPort = 9009 in VDJ settings")
        print("    3. oscPortBack = 9999 in VDJ settings")
        print("    4. You have PRO license")
        return

    # =========================================================================
    # Phase 2: Subscribe and start playback
    # =========================================================================
    print("\n" + "-" * 70)
    print("Phase 2: SUBSCRIBE + PLAY test")
    print("-" * 70)

    # Clear counts for subscription phase
    sub_start_counts = dict(message_counts)

    # Subscribe
    print("Subscribing...")
    for verb in test_verbs:
        liblo.send(vdj_target, f"/vdj/subscribe/deck/1/{verb}")
        time.sleep(0.02)

    # Start playback
    print("Starting playback...")
    liblo.send(vdj_target, "/vdj/deck/1/play")

    # Wait and collect
    print("Listening for subscription updates (6 seconds)...")
    print()
    try:
        poll_until = time.time() + 6.0
        while time.time() < poll_until:
            server.recv(50)
    except KeyboardInterrupt:
        print("\nInterrupted")

    # Stop
    liblo.send(vdj_target, "/vdj/deck/1/pause")

    # Calculate subscription-phase counts
    sub_counts = {}
    for path, count in message_counts.items():
        prev = sub_start_counts.get(path, 0)
        sub_counts[path] = count - prev

    # =========================================================================
    # Phase 3: Active polling comparison
    # =========================================================================
    print("\n" + "-" * 70)
    print("Phase 3: POLLING test (query every 100ms while playing)")
    print("-" * 70)

    poll_start_counts = dict(message_counts)

    # Start playback
    liblo.send(vdj_target, "/vdj/deck/1/play")

    poll_until = time.time() + 4.0
    last_query = 0
    while time.time() < poll_until:
        now = time.time()
        if now - last_query >= 0.1:
            for verb in ["song_pos", "get_beat", "get_level"]:
                liblo.send(vdj_target, f"/vdj/query/deck/1/{verb}")
            last_query = now
        server.recv(30)

    liblo.send(vdj_target, "/vdj/deck/1/pause")

    # Calculate poll-phase counts
    poll_counts = {}
    for path, count in message_counts.items():
        prev = poll_start_counts.get(path, 0)
        poll_counts[path] = count - prev

    # Unsubscribe
    for verb in test_verbs:
        liblo.send(vdj_target, f"/vdj/unsubscribe/deck/1/{verb}")
        time.sleep(0.02)

    # =========================================================================
    # Results
    # =========================================================================
    print("\n" + "=" * 70)
    print("FINAL RESULTS")
    print("=" * 70)

    print("\n{:<25} {:>12} {:>12} {:>12}".format(
        "Verb", "Query", "Subscribe", "Poll (4s)"))
    print("-" * 70)

    for verb in test_verbs:
        path = f"/vdj/deck/1/{verb}"
        q_count = 1 if path in sub_start_counts else 0  # Query phase
        s_count = sub_counts.get(path, 0)  # Subscribe phase
        p_count = poll_counts.get(path, 0)  # Poll phase

        status = ""
        if s_count > 5:
            status = "✓ SUB WORKS"
        elif p_count > 5:
            status = "→ POLL ONLY"
        elif q_count > 0:
            status = "→ QUERY OK"

        print(f"{verb:<25} {q_count:>12} {s_count:>12} {p_count:>12}  {status}")

    # Summary
    print("\n" + "=" * 70)
    print("RECOMMENDATIONS")
    print("=" * 70)

    sub_working = [v for v in test_verbs if sub_counts.get(f"/vdj/deck/1/{v}", 0) > 5]
    poll_needed = [v for v in test_verbs if sub_counts.get(f"/vdj/deck/1/{v}", 0) <= 5
                   and poll_counts.get(f"/vdj/deck/1/{v}", 0) > 5]

    if sub_working:
        print("\n✓ Use SUBSCRIBE for (real-time push):")
        for v in sub_working:
            print(f"    /vdj/subscribe/deck/N/{v}")

    if poll_needed:
        print("\n→ Use POLLING for (query every 100-200ms):")
        for v in poll_needed:
            print(f"    /vdj/query/deck/N/{v}")

    if not sub_working and not poll_needed:
        print("\n⚠️  Neither subscriptions nor polling produced many updates.")
        print("    This might indicate VDJ connection issues.")

    print("\nDone.")


if __name__ == "__main__":
    main()
