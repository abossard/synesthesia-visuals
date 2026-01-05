#!/usr/bin/env python3
"""Create a screenshot showing the Workers panel integration."""

import asyncio
import sys
import os
from pathlib import Path

sys.path.insert(0, os.getcwd())

async def capture_worker_panel_screenshot():
    """Capture screenshot showing Workers panel."""
    from vj_console import VJConsoleApp
    
    app = VJConsoleApp()
    
    screenshots_dir = Path("screenshots")
    screenshots_dir.mkdir(exist_ok=True)
    
    async with app.run_test() as pilot:
        # Wait for app to initialize and discover workers
        await pilot.pause(3.0)
        
        # Ensure we're on Master Control screen (screen 1)
        await pilot.press("1")
        await pilot.pause(1.0)
        
        # Capture screenshot with Workers panel visible
        print("📸 Capturing VJ Console with Workers Panel...")
        screenshot_path = screenshots_dir / "vj_console_with_workers_panel.svg"
        app.save_screenshot(str(screenshot_path))
        print(f"   Saved to: {screenshot_path}")
        
    print("\n✅ Screenshot captured successfully!")
    
    # Convert to PNG
    try:
        import cairosvg
        print("\n📸 Converting to PNG...")
        png_path = screenshot_path.with_suffix(".png")
        cairosvg.svg2png(url=str(screenshot_path), write_to=str(png_path), scale=2.0)
        print(f"   ✓ {png_path.name}")
        print("✅ PNG conversion complete!")
        return png_path
    except ImportError:
        print("\nℹ️  Install cairosvg to convert SVG to PNG")
        return screenshot_path

if __name__ == "__main__":
    asyncio.run(capture_worker_panel_screenshot())
