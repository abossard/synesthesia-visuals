"""CLI entry point — python -m show_builder.

Action module: argument parsing and orchestration.
"""

import argparse
import sys

from .fixtures import DEFAULT_ADDRESSES
from .mcp_client import MCPClient
from .builder import patch_fixtures, clean_existing_functions, build_show


def main():
    parser = argparse.ArgumentParser(
        description="Phase-Based DJ Show Builder v2.0"
    )
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=9696)
    parser.add_argument("--skip-patch", action="store_true",
                        help="Skip fixture patching")
    parser.add_argument("--skip-vc", action="store_true",
                        help="Skip Virtual Console layout")
    parser.add_argument("--hero-id", type=int, default=None)
    parser.add_argument("--haze-id", type=int, default=None)
    parser.add_argument("--uv-id", type=int, default=None)
    parser.add_argument("--hero-addr", type=int,
                        default=DEFAULT_ADDRESSES["hero"])
    parser.add_argument("--haze-addr", type=int,
                        default=DEFAULT_ADDRESSES["haze"])
    parser.add_argument("--uv-addr", type=int,
                        default=DEFAULT_ADDRESSES["uv"])
    args = parser.parse_args()

    print("╔══════════════════════════════════════════════╗")
    print("║  Phase-Based DJ Show Builder v2.0            ║")
    print("║  Creative Performance Controller for QLC+    ║")
    print("╚══════════════════════════════════════════════╝")

    # Connect
    print("\n📡 Connecting to MCP server...")
    client = MCPClient(args.host, args.port)
    client.connect()

    # Clean slate
    clean_existing_functions(client)

    # Patch or reuse fixtures
    if not args.skip_patch:
        addresses = [args.hero_addr, args.haze_addr, args.uv_addr]
        hero_id, haze_id, uv_id = patch_fixtures(client, addresses)
    else:
        hero_id = args.hero_id if args.hero_id is not None else 0
        haze_id = args.haze_id if args.haze_id is not None else 2
        uv_id = args.uv_id if args.uv_id is not None else 1
        print(f"\n🔌 Using existing fixtures: hero={hero_id}, "
              f"haze={haze_id}, uv={uv_id}")

    # Build the show
    ids = build_show(client, hero_id, haze_id, uv_id, skip_vc=args.skip_vc)

    # Summary
    total = sum(len(v) for v in ids.values())
    print("\n╔══════════════════════════════════════════════╗")
    print(f"║  ✅ PHASE SHOW COMPLETE                      ║")
    print(f"║  {total:3d} functions │ Launchpad mapped           ║")
    print("╚══════════════════════════════════════════════╝")
    print("\n  Layer architecture:")
    print("    Row 8: Phase   → texture/gobo/UV atmosphere")
    print("    Row 7: Energy  → movement speed, gobo rotation")
    print("    Row 6: Mood    → wash color (RGBW)")
    print("    Row 5: Auto    → chasers, buildups, impacts")
    print("    Row 4: Move    → EFX pan/tilt patterns")
    print("    Row 3: Master  → dimmer level + haze")
    print("    Row 2: Strobe  → spot + UV strobe speed")
    print("    Row 1: Shots   → flash accents")
    print("\n  Save the project in QLC+ (Ctrl+S) to persist!")


if __name__ == "__main__":
    main()
