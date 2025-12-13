#!/usr/bin/env python3
"""
DJ.Studio Monitor Test Script

Test DJ.Studio integration by running the monitor in isolation.
Shows which strategy is working and displays current track info.

Usage:
    python scripts/test_djstudio.py
    
    # Test with custom file path:
    python scripts/test_djstudio.py --file /path/to/track.txt
    
    # Test continuously (press Ctrl+C to stop):
    python scripts/test_djstudio.py --watch
"""

import sys
import time
import argparse
from pathlib import Path

# Add parent directory to path for imports
sys.path.insert(0, str(Path(__file__).parent.parent))

from adapters import DJStudioMonitor
from infrastructure import Config


def test_monitor(file_path=None, watch=False):
    """Test DJ.Studio monitor with optional file path."""
    
    print("=" * 60)
    print("DJ.Studio Monitor Test")
    print("=" * 60)
    print()
    
    # Show configuration
    config = Config.djstudio_config()
    print("Configuration:")
    print(f"  Enabled: {config['enabled']}")
    print(f"  Script path: {config['script_path']}")
    print(f"  File path: {file_path or config['file_path'] or 'auto-detect'}")
    print(f"  Timeout: {config['timeout']}s")
    print()
    
    if not config['enabled']:
        print("⚠️  DJ.Studio monitoring is DISABLED")
        print("   Set DJSTUDIO_ENABLED=1 to enable")
        return 1
    
    # Create monitor
    monitor = DJStudioMonitor(
        file_path=Path(file_path) if file_path else config['file_path']
    )
    
    if watch:
        print("Watching for DJ.Studio track changes...")
        print("Press Ctrl+C to stop\n")
        
        last_track = None
        try:
            while True:
                playback = monitor.get_playback()
                status = monitor.status
                
                if playback:
                    current_track = f"{playback['artist']} - {playback['title']}"
                    if current_track != last_track:
                        last_track = current_track
                        print(f"\n[{time.strftime('%H:%M:%S')}] 🎵 Now Playing:")
                        print(f"  Artist:   {playback['artist']}")
                        print(f"  Title:    {playback['title']}")
                        if playback['album']:
                            print(f"  Album:    {playback['album']}")
                        print(f"  Duration: {playback['duration_ms'] / 1000:.1f}s")
                        print(f"  Progress: {playback['progress_ms'] / 1000:.1f}s")
                        print(f"  Source:   {status.get('detail', 'Unknown')}")
                else:
                    if last_track is not None:
                        print(f"\n[{time.strftime('%H:%M:%S')}] ⏸️  DJ.Studio: {status.get('detail', 'Not detected')}")
                        last_track = None
                
                time.sleep(1)
        except KeyboardInterrupt:
            print("\n\nStopped watching.")
            return 0
    else:
        print("Testing DJ.Studio detection...\n")
        
        playback = monitor.get_playback()
        status = monitor.status
        
        print(f"Status: {status.get('detail', 'Unknown')}")
        print()
        
        if playback:
            print("✅ DJ.Studio detected!")
            print()
            print("Current Track:")
            print(f"  Artist:     {playback['artist']}")
            print(f"  Title:      {playback['title']}")
            print(f"  Album:      {playback['album'] or '(none)'}")
            print(f"  Duration:   {playback['duration_ms'] / 1000:.1f}s")
            print(f"  Progress:   {playback['progress_ms'] / 1000:.1f}s")
            print(f"  Is Playing: {playback['is_playing']}")
            print()
            print(f"Detection method: {status.get('detail', 'Unknown')}")
            return 0
        else:
            print("❌ DJ.Studio not detected")
            print()
            print("Troubleshooting:")
            print("  1. Is DJ.Studio running?")
            print("  2. Is a track currently playing?")
            print("  3. Does the window title show track info?")
            print()
            print("If using file export:")
            print("  - Check file exists and is readable")
            print("  - Verify file contains 'Artist - Title' or JSON")
            print("  - Try: --file /path/to/your/track/file.txt")
            print()
            print("For more help, see: docs/guides/djstudio-integration.md")
            return 1


def main():
    parser = argparse.ArgumentParser(
        description="Test DJ.Studio monitor integration",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  python scripts/test_djstudio.py                    # Single test
  python scripts/test_djstudio.py --watch            # Continuous monitoring
  python scripts/test_djstudio.py --file track.txt   # Test with custom file
        """
    )
    parser.add_argument(
        '--file', '-f',
        help='Path to DJ.Studio track export file',
        metavar='PATH'
    )
    parser.add_argument(
        '--watch', '-w',
        action='store_true',
        help='Watch for track changes (Ctrl+C to stop)'
    )
    
    args = parser.parse_args()
    
    try:
        return test_monitor(file_path=args.file, watch=args.watch)
    except Exception as e:
        print(f"\n❌ Error: {e}")
        import traceback
        traceback.print_exc()
        return 1


if __name__ == '__main__':
    sys.exit(main())
