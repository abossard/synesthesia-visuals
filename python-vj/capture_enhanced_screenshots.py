#!/usr/bin/env python3
"""Capture screenshots of enhanced VJ console with worker screens."""

import asyncio
import sys
import os
from pathlib import Path

sys.path.insert(0, os.getcwd())

async def capture_enhanced_screenshots():
    """Capture screenshots showing all new worker screens."""
    from vj_console import VJConsoleApp
    
    app = VJConsoleApp()
    
    screenshots_dir = Path("screenshots")
    screenshots_dir.mkdir(exist_ok=True)
    
    async with app.run_test() as pilot:
        await pilot.pause(3.0)
        
        # Screen 0: Overview
        print("📸 Capturing Overview screen (0)...")
        await pilot.press("0")
        await pilot.pause(1.0)
        path = screenshots_dir / "screen_0_overview.svg"
        app.save_screenshot(str(path))
        print(f"   ✓ {path.name}")
        
        # Screen 1: Master Control
        print("📸 Capturing Master Control screen (1)...")
        await pilot.press("1")
        await pilot.pause(1.0)
        path = screenshots_dir / "screen_1_master.svg"
        app.save_screenshot(str(path))
        print(f"   ✓ {path.name}")
        
        # Screen 6: Spotify Worker
        print("📸 Capturing Spotify Worker screen (6)...")
        await pilot.press("6")
        await pilot.pause(1.0)
        path = screenshots_dir / "screen_6_spotify_worker.svg"
        app.save_screenshot(str(path))
        print(f"   ✓ {path.name}")
        
        # Screen 7: VirtualDJ Worker
        print("📸 Capturing VirtualDJ Worker screen (7)...")
        await pilot.press("7")
        await pilot.pause(1.0)
        path = screenshots_dir / "screen_7_vdj_worker.svg"
        app.save_screenshot(str(path))
        print(f"   ✓ {path.name}")
        
        # Screen 8: Lyrics Worker
        print("📸 Capturing Lyrics Worker screen (8)...")
        await pilot.press("8")
        await pilot.pause(1.0)
        path = screenshots_dir / "screen_8_lyrics_worker.svg"
        app.save_screenshot(str(path))
        print(f"   ✓ {path.name}")
        
    print("\n✅ All enhanced screenshots captured!")
    
    # Convert to PNG
    try:
        import cairosvg
        print("\n📸 Converting to PNG...")
        for svg_file in sorted(screenshots_dir.glob("screen_*.svg")):
            png_file = svg_file.with_suffix(".png")
            cairosvg.svg2png(url=str(svg_file), write_to=str(png_file), scale=2.0)
            print(f"   ✓ {png_file.name}")
        print("✅ PNG conversion complete!")
    except ImportError:
        pass

if __name__ == "__main__":
    asyncio.run(capture_enhanced_screenshots())
