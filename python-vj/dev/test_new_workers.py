#!/usr/bin/env python3
"""
Test client for new workers (VirtualDJ monitor + Lyrics fetcher).

Demonstrates VJBusClient integration with the new workers.

Usage:
    # Terminal 1: Start workers
    python dev/start_all_workers.py virtualdj_monitor lyrics_fetcher

    # Terminal 2: Run this test
    python dev/test_new_workers.py
"""

import sys
import time
import logging
from pathlib import Path

# Add parent directory to path
sys.path.insert(0, str(Path(__file__).parent.parent))

from vj_bus.client import VJBusClient
from vj_bus.messages import CommandMessage

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)

logger = logging.getLogger('test_new_workers')


def test_virtualdj_monitor(client: VJBusClient):
    """Test VirtualDJ monitor worker."""
    logger.info("\n" + "=" * 60)
    logger.info("Testing VirtualDJ Monitor Worker")
    logger.info("=" * 60)

    # Check if worker is available
    workers = client.discover_workers()
    virtualdj_worker = next((w for w in workers if w.name == "virtualdj_monitor"), None)

    if not virtualdj_worker:
        logger.warning("⚠️  VirtualDJ monitor worker not found")
        logger.info("Start it with: python workers/virtualdj_monitor_worker.py")
        return False

    logger.info(f"✓ Found worker: {virtualdj_worker.name}")
    logger.info(f"  Command port: {virtualdj_worker.command_port}")
    logger.info(f"  Telemetry port: {virtualdj_worker.telemetry_port}")

    # Get worker state
    try:
        response = client.send_command("virtualdj_monitor", "get_state", {})
        logger.info(f"✓ Worker state: {response.payload.get('status', 'unknown')}")
        metrics = response.payload.get('metrics', {})
        logger.info(f"  Last poll: {metrics.get('last_poll', 'N/A')}")
        logger.info(f"  Has track: {metrics.get('has_track', False)}")
    except Exception as e:
        logger.error(f"✗ Failed to get state: {e}")
        return False

    # Subscribe to telemetry
    logger.info("\n📡 Subscribing to VirtualDJ telemetry...")
    logger.info("   (Play a track in VirtualDJ to see updates)")

    track_count = [0]  # Mutable to modify in callback

    def on_virtualdj_state(msg):
        track_count[0] += 1
        state = msg.payload
        is_playing = state.get('is_playing', False)
        track = state.get('track', {})
        artist = track.get('artist', 'Unknown')
        title = track.get('title', 'Unknown')
        position = state.get('position', 0.0)

        status = "▶️  Playing" if is_playing else "⏸️  Paused"
        logger.info(f"\n🎵 VirtualDJ Update #{track_count[0]}")
        logger.info(f"   {status}: {artist} - {title}")
        logger.info(f"   Position: {position:.1f}s")

    client.subscribe("virtualdj.state", on_virtualdj_state)

    # Wait for a few updates
    logger.info("   Listening for 10 seconds...")
    time.sleep(10)

    if track_count[0] > 0:
        logger.info(f"\n✓ Received {track_count[0]} updates from VirtualDJ")
    else:
        logger.info("\nℹ️  No updates received (VirtualDJ not playing?)")

    return True


def test_lyrics_fetcher(client: VJBusClient):
    """Test Lyrics Fetcher worker."""
    logger.info("\n" + "=" * 60)
    logger.info("Testing Lyrics Fetcher Worker")
    logger.info("=" * 60)

    # Check if worker is available
    workers = client.discover_workers()
    lyrics_worker = next((w for w in workers if w.name == "lyrics_fetcher"), None)

    if not lyrics_worker:
        logger.warning("⚠️  Lyrics fetcher worker not found")
        logger.info("Start it with: python workers/lyrics_fetcher_worker.py")
        return False

    logger.info(f"✓ Found worker: {lyrics_worker.name}")
    logger.info(f"  Command port: {lyrics_worker.command_port}")
    logger.info(f"  Telemetry port: {lyrics_worker.telemetry_port}")

    # Get worker state
    try:
        response = client.send_command("lyrics_fetcher", "get_state", {})
        logger.info(f"✓ Worker state: {response.payload.get('status', 'unknown')}")
        metrics = response.payload.get('metrics', {})
        logger.info(f"  LLM backend: {metrics.get('llm_backend', 'unknown')}")
        logger.info(f"  Lyrics cached: {metrics.get('lyrics_cached', 0)}")
        logger.info(f"  LLM analyses: {metrics.get('llm_analyses', 0)}")
    except Exception as e:
        logger.error(f"✗ Failed to get state: {e}")
        return False

    # Test fetching lyrics
    logger.info("\n📝 Testing lyrics fetch...")
    test_track = {
        "artist": "Coldplay",
        "title": "Fix You",
        "album": "X&Y",
        "duration": 295,
    }

    try:
        logger.info(f"   Fetching: {test_track['artist']} - {test_track['title']}")
        response = client.send_command(
            "lyrics_fetcher",
            "fetch_and_analyze",
            test_track
        )

        result = response.payload
        if result.get("success"):
            logger.info(f"✓ Lyrics fetch successful")
            logger.info(f"  Has lyrics: {result.get('has_lyrics', False)}")

            if result.get('has_lyrics'):
                logger.info(f"  Line count: {result.get('line_count', 0)}")

                # Check if we got analysis
                if 'analysis' in result:
                    analysis = result['analysis']
                    logger.info(f"\n🤖 LLM Analysis:")
                    logger.info(f"  Keywords: {', '.join(analysis.get('keywords', [])[:5])}")
                    logger.info(f"  Themes: {', '.join(analysis.get('themes', []))}")
                    logger.info(f"  Cached: {analysis.get('cached', False)}")

                # Check if we got categorization
                if 'categories' in result:
                    logger.info(f"\n🎭 Categorization:")
                    logger.info(f"  Primary mood: {result.get('primary_mood', 'unknown')}")
                    categories = result.get('categories', {})
                    top_cats = sorted(categories.items(), key=lambda x: x[1], reverse=True)[:3]
                    for cat, score in top_cats:
                        logger.info(f"  {cat}: {score:.2f}")
        else:
            logger.error(f"✗ Lyrics fetch failed: {result.get('error', 'unknown')}")
            return False

    except Exception as e:
        logger.error(f"✗ Command failed: {e}")
        return False

    # Subscribe to telemetry
    logger.info("\n📡 Subscribing to lyrics telemetry...")

    telemetry_count = [0]

    def on_lyrics_fetched(msg):
        telemetry_count[0] += 1
        data = msg.payload
        artist = data.get('artist', 'Unknown')
        title = data.get('title', 'Unknown')
        line_count = data.get('line_count', 0)
        logger.info(f"\n📥 Lyrics fetched: {artist} - {title} ({line_count} lines)")

    def on_lyrics_analyzed(msg):
        telemetry_count[0] += 1
        data = msg.payload
        artist = data.get('artist', 'Unknown')
        title = data.get('title', 'Unknown')
        keywords = data.get('keywords', [])
        logger.info(f"\n🔍 Analysis: {artist} - {title}")
        logger.info(f"   Keywords: {', '.join(keywords[:5])}")

    client.subscribe("lyrics.fetched", on_lyrics_fetched)
    client.subscribe("lyrics.analyzed", on_lyrics_analyzed)

    logger.info("   (Already received telemetry from test above)")
    logger.info(f"✓ Telemetry subscription active")

    return True


def main():
    """Main test runner."""
    logger.info("=" * 60)
    logger.info("VJ Bus New Workers Test Client")
    logger.info("=" * 60)

    # Create client
    client = VJBusClient()

    # Discover all workers
    logger.info("\n🔍 Discovering workers...")
    workers = client.discover_workers()

    if not workers:
        logger.error("✗ No workers found!")
        logger.info("\nStart workers with:")
        logger.info("  python dev/start_all_workers.py virtualdj_monitor lyrics_fetcher")
        sys.exit(1)

    logger.info(f"✓ Found {len(workers)} worker(s):")
    for worker in workers:
        logger.info(f"  - {worker.name} (ports: {worker.command_port}, {worker.telemetry_port})")

    # Start telemetry receiver
    logger.info("\n🚀 Starting telemetry receiver...")
    client.start()
    time.sleep(0.5)  # Give it a moment to start

    # Run tests
    results = []

    try:
        results.append(("VirtualDJ Monitor", test_virtualdj_monitor(client)))
        results.append(("Lyrics Fetcher", test_lyrics_fetcher(client)))

    except KeyboardInterrupt:
        logger.info("\n\n⚠️  Test interrupted by user")
    finally:
        client.stop()

    # Print summary
    logger.info("\n" + "=" * 60)
    logger.info("Test Summary")
    logger.info("=" * 60)

    for name, success in results:
        status = "✓ PASS" if success else "✗ FAIL"
        logger.info(f"{status}: {name}")

    all_passed = all(success for _, success in results)
    if all_passed:
        logger.info("\n🎉 All tests passed!")
        sys.exit(0)
    else:
        logger.info("\n⚠️  Some tests failed")
        sys.exit(1)


if __name__ == "__main__":
    main()
