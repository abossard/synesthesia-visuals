#!/usr/bin/env python3
"""Capture screenshots of the VJ console for documentation."""

import asyncio
import sys
import os
from pathlib import Path

# Add current directory to path
sys.path.insert(0, os.getcwd())

async def capture_screenshots():
    """Capture screenshots of the VJ console."""
    from vj_console import VJConsoleApp
    from textual.pilot import Pilot
    
    app = VJConsoleApp()
    
    # Create screenshots directory
    screenshots_dir = Path("screenshots")
    screenshots_dir.mkdir(exist_ok=True)
    
    async with app.run_test() as pilot:
        # Wait for app to initialize
        await pilot.pause(2.0)
        
        # Screenshot 1: Main screen with workers panel
        print("📸 Capturing main screen with workers panel...")
        await pilot.press("1")  # Switch to master control
        await pilot.pause(1.0)
        screenshot1_path = screenshots_dir / "01_main_screen_with_workers.svg"
        app.save_screenshot(str(screenshot1_path))
        print(f"   Saved to: {screenshot1_path}")
        
        # Screenshot 2: After starting workers
        print("📸 Capturing screen after starting workers...")
        await pilot.press("w")  # Start all workers
        await pilot.pause(2.0)
        screenshot2_path = screenshots_dir / "02_workers_starting.svg"
        app.save_screenshot(str(screenshot2_path))
        print(f"   Saved to: {screenshot2_path}")
        
        # Screenshot 3: Karaoke screen
        print("📸 Capturing karaoke screen...")
        await pilot.press("2")  # Switch to karaoke
        await pilot.pause(1.0)
        screenshot3_path = screenshots_dir / "03_karaoke_screen.svg"
        app.save_screenshot(str(screenshot3_path))
        print(f"   Saved to: {screenshot3_path}")
        
        # Screenshot 4: Audio screen
        print("📸 Capturing audio screen...")
        await pilot.press("3")  # Switch to audio
        await pilot.pause(1.0)
        screenshot4_path = screenshots_dir / "04_audio_screen.svg"
        app.save_screenshot(str(screenshot4_path))
        print(f"   Saved to: {screenshot4_path}")
        
        # Screenshot 5: Back to main with worker status
        print("📸 Capturing final main screen with worker status...")
        await pilot.press("1")  # Back to master control
        await pilot.pause(2.0)
        screenshot5_path = screenshots_dir / "05_main_screen_workers_running.svg"
        app.save_screenshot(str(screenshot5_path))
        print(f"   Saved to: {screenshot5_path}")
        
    print("\n✅ All screenshots captured successfully!")
    print(f"   Location: {screenshots_dir.absolute()}")
    
    # Convert SVG to PNG if possible
    try:
        import cairosvg
        print("\n📸 Converting SVG to PNG...")
        for svg_file in screenshots_dir.glob("*.svg"):
            png_file = svg_file.with_suffix(".png")
            cairosvg.svg2png(url=str(svg_file), write_to=str(png_file))
            print(f"   ✓ {png_file.name}")
        print("✅ PNG conversion complete!")
    except ImportError:
        print("\nℹ️  Install cairosvg to convert SVG screenshots to PNG")
        print("   pip install cairosvg")

if __name__ == "__main__":
    asyncio.run(capture_screenshots())
