#!/usr/bin/env python3
"""
VirtualDJ OSC Comprehensive Subscription Test

Tests ALL known VDJScript verbs that might work with subscriptions.
Based on official VDJ documentation: https://www.virtualdj.com/manuals/virtualdj/appendix/vdjscriptverbs.html

VirtualDJ OSC format:
  - Action:    /vdj/deck/N/verb
  - Query:     /vdj/query/deck/N/verb
  - Subscribe: /vdj/subscribe/deck/N/verb
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
    print(f"[{elapsed:5.2f}s] {path} = {val_str}")


def main():
    global start_time

    print("=" * 70)
    print("VirtualDJ OSC Comprehensive Subscription Test")
    print("=" * 70)
    print("Testing ALL known VDJScript verbs from official documentation")
    print("Source: https://www.virtualdj.com/manuals/virtualdj/appendix/vdjscriptverbs.html")
    print("=" * 70)

    try:
        server = liblo.Server(VDJ_OSC_PORT_BACK)
    except liblo.ServerError as e:
        print(f"Error: {e}")
        sys.exit(1)

    server.add_method(None, None, handle_message)
    vdj_target = (VDJ_HOST, VDJ_OSC_PORT)
    start_time = time.time()

    # =========================================================================
    # ALL VERBS TO TEST (from VDJ documentation)
    # =========================================================================

    # Position & Time verbs
    position_verbs = [
        "song_pos",           # Position slider (0-1)
        "get_time",           # Elapsed/remaining time
        "get_time_ms",        # Time in milliseconds
        "get_time_sec",       # Time in seconds
        "get_elapsed",        # Elapsed time
        "get_remaining",      # Remaining time
        "get_totaltime",      # Total duration
        "get_songlength",     # Song length
        "songpos_remain",     # Remaining percentage
        "songpos_warning",    # < 30 sec remaining
    ]

    # Beat & Sync verbs
    beat_verbs = [
        "get_beat",           # Beat intensity (0-100%)
        "get_beat2",          # Beat intensity both decks
        "get_beatgrid",       # Beat from grid
        "get_beatpos",        # Position in beats
        "get_beatdiff",       # Beat difference
        "get_beat_counter",   # Beat counter
        "get_beat_num",       # Beat in measure (1-4)
        "get_beat_bar",       # Position in bar
        "get_bpm",            # BPM value
        "get_bpm_engine",     # Engine BPM
        "pitch",              # Current pitch
    ]

    # Level & Volume verbs
    level_verbs = [
        "get_level",          # Signal level
        "get_level_peak",     # Peak level
        "get_level_left",     # Left channel
        "get_level_right",    # Right channel
        "get_vu_meter",       # VU meter (post-master)
        "level",              # Deck level
        "volume",             # Deck volume
        "gain",               # Deck gain
        "get_limiter",        # Limiter status
    ]

    # Playback state verbs
    playback_verbs = [
        "play",               # Play state
        "is_audible",         # Audible state
        "loaded",             # Track loaded
        "reverse",            # Reverse state
        "loop",               # Loop state
        "get_active_loop",    # Active loop beats
        "loop_position",      # Position in loop
    ]

    # Track info verbs
    track_verbs = [
        "get_title",
        "get_artist",
        "get_album",
        "get_genre",
        "get_key",
        "get_year",
        "get_filepath",
    ]

    # Visual/rotation verbs
    visual_verbs = [
        "get_rotation",       # Turntable angle
        "get_arm",            # Arm position
        "get_rotation_cue",   # Cue angle
        "get_phase",          # Phase
    ]

    # Global verbs (no deck prefix)
    global_verbs = [
        "crossfader",
        "masterlevel",
        "master_volume",
        "get_crossfader_result",
        "get_activedeck",
        "headphone_volume",
    ]

    all_deck_verbs = position_verbs + beat_verbs + level_verbs + playback_verbs + track_verbs + visual_verbs

    # =========================================================================
    # Subscribe to everything
    # =========================================================================
    print(f"\nSubscribing to {len(all_deck_verbs)} deck verbs + {len(global_verbs)} global verbs...")
    print("-" * 70)

    # Deck subscriptions
    for verb in all_deck_verbs:
        liblo.send(vdj_target, f"/vdj/subscribe/deck/1/{verb}")
        time.sleep(0.01)

    # Global subscriptions
    for verb in global_verbs:
        liblo.send(vdj_target, f"/vdj/subscribe/{verb}")
        time.sleep(0.01)

    print(f"Subscribed to {len(all_deck_verbs) + len(global_verbs)} total values")

    # =========================================================================
    # Start playback and listen
    # =========================================================================
    print("\n" + "=" * 70)
    print("Starting playback - listening for 8 seconds...")
    print("=" * 70)

    liblo.send(vdj_target, "/vdj/deck/1/play")

    # Listen for messages
    try:
        poll_until = time.time() + 8.0
        while time.time() < poll_until:
            server.recv(50)
    except KeyboardInterrupt:
        print("\nInterrupted")

    # Stop playback
    liblo.send(vdj_target, "/vdj/deck/1/pause")
    time.sleep(0.3)

    # Drain remaining messages
    drain_until = time.time() + 0.5
    while time.time() < drain_until:
        server.recv(50)

    # Unsubscribe
    for verb in all_deck_verbs:
        liblo.send(vdj_target, f"/vdj/unsubscribe/deck/1/{verb}")
        time.sleep(0.01)
    for verb in global_verbs:
        liblo.send(vdj_target, f"/vdj/unsubscribe/{verb}")
        time.sleep(0.01)

    # =========================================================================
    # Results
    # =========================================================================
    print("\n" + "=" * 70)
    print("RESULTS: Subscriptions that sent updates")
    print("=" * 70)

    # Group by category
    categories = {
        "Position & Time": position_verbs,
        "Beat & Sync": beat_verbs,
        "Level & Volume": level_verbs,
        "Playback State": playback_verbs,
        "Track Info": track_verbs,
        "Visual/Rotation": visual_verbs,
        "Global": global_verbs,
    }

    working = {}
    not_working = {}

    for category, verbs in categories.items():
        working[category] = []
        not_working[category] = []

        for verb in verbs:
            if category == "Global":
                path = f"/vdj/{verb}"
            else:
                path = f"/vdj/deck/1/{verb}"

            count = message_counts.get(path, 0)
            if count > 0:
                working[category].append((verb, count, message_values.get(path)))
            else:
                not_working[category].append(verb)

    # Print working subscriptions
    print("\n✓ WORKING SUBSCRIPTIONS (pushed updates during playback):")
    print("-" * 70)
    total_working = 0
    for category, items in working.items():
        if items:
            print(f"\n  [{category}]")
            for verb, count, val in items:
                val_str = f"{val:.4f}" if isinstance(val, float) else repr(val)
                if len(str(val_str)) > 25:
                    val_str = str(val_str)[:25] + "..."
                print(f"    {verb:25} : {count:4} msgs  (last: {val_str})")
                total_working += 1

    # Print non-working subscriptions
    print("\n\n✗ NO UPDATES RECEIVED (may need polling):")
    print("-" * 70)
    total_not_working = 0
    for category, items in not_working.items():
        if items:
            print(f"\n  [{category}]")
            for verb in items:
                print(f"    {verb}")
                total_not_working += 1

    # =========================================================================
    # Summary
    # =========================================================================
    print("\n" + "=" * 70)
    print("SUMMARY")
    print("=" * 70)
    print(f"\nTotal subscriptions tested: {len(all_deck_verbs) + len(global_verbs)}")
    print(f"Working (pushed updates):   {total_working}")
    print(f"Not working (need polling): {total_not_working}")

    # Key findings
    print("\n" + "=" * 70)
    print("KEY FINDINGS FOR REAL-TIME DATA")
    print("=" * 70)

    # Check specific important verbs
    key_verbs = {
        "song_pos": "Position tracking",
        "get_beat": "Beat sync / intensity",
        "get_beatpos": "Beat position",
        "get_level": "Audio level",
        "get_level_peak": "Peak level",
        "get_vu_meter": "VU meter",
        "play": "Play state",
        "get_bpm": "BPM",
    }

    print("\nFor real-time visuals, use these methods:\n")
    for verb, desc in key_verbs.items():
        path = f"/vdj/deck/1/{verb}"
        count = message_counts.get(path, 0)
        if count > 0:
            print(f"  ✓ {desc:20} → SUBSCRIBE to /vdj/subscribe/deck/N/{verb}")
        else:
            print(f"  ✗ {desc:20} → POLL with /vdj/query/deck/N/{verb}")

    print("\n" + "=" * 70)
    print("Done.")


if __name__ == "__main__":
    main()
