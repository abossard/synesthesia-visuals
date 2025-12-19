"""
End-to-end screenshot tests for VJ Console UI.

Captures screenshots of each tab/screen for documentation.
Run with: pytest tests/e2e/test_ui_screenshots.py -v

Screenshots are saved to: tests/e2e/screenshots/
"""

import pytest
import sys
from pathlib import Path

# Ensure python-vj is in path
sys.path.insert(0, str(Path(__file__).parent.parent.parent))

# Screenshot output directory
SCREENSHOTS_DIR = Path(__file__).parent / "screenshots"


class TestUIScreenshots:
    """Capture screenshots of VJ Console for documentation."""

    @pytest.fixture(autouse=True)
    def setup_screenshots_dir(self):
        """Ensure screenshots directory exists."""
        SCREENSHOTS_DIR.mkdir(parents=True, exist_ok=True)

    @pytest.fixture
    def app(self):
        """Create VJConsoleApp instance for testing."""
        from vj_console import VJConsoleApp
        return VJConsoleApp()

    @pytest.mark.asyncio
    async def test_screenshot_master_control(self, app):
        """Screenshot Tab 1: Master Control - main dashboard."""
        async with app.run_test(size=(120, 40)) as pilot:
            # Already on master tab by default
            await pilot.pause()

            # Save screenshot
            path = SCREENSHOTS_DIR / "01_master_control.svg"
            app.save_screenshot(str(path))

            assert path.exists(), "Screenshot should be saved"

    @pytest.mark.asyncio
    async def test_screenshot_osc_view(self, app):
        """Screenshot Tab 2: OSC View - message debugging."""
        async with app.run_test(size=(120, 40)) as pilot:
            # Switch to OSC tab (press 2)
            await pilot.press("2")
            await pilot.pause()

            path = SCREENSHOTS_DIR / "02_osc_view.svg"
            app.save_screenshot(str(path))

            assert path.exists()

    @pytest.mark.asyncio
    async def test_screenshot_ai_debug(self, app):
        """Screenshot Tab 3: Song AI Debug - categorization view."""
        async with app.run_test(size=(120, 40)) as pilot:
            # Switch to AI Debug tab (press 3)
            await pilot.press("3")
            await pilot.pause()

            path = SCREENSHOTS_DIR / "03_ai_debug.svg"
            app.save_screenshot(str(path))

            assert path.exists()

    @pytest.mark.asyncio
    async def test_screenshot_logs(self, app):
        """Screenshot Tab 4: All Logs - application logs."""
        async with app.run_test(size=(120, 40)) as pilot:
            # Switch to Logs tab (press 4)
            await pilot.press("4")
            await pilot.pause()

            path = SCREENSHOTS_DIR / "04_logs.svg"
            app.save_screenshot(str(path))

            assert path.exists()

    @pytest.mark.asyncio
    async def test_screenshot_launchpad(self, app):
        """Screenshot Tab 5: Launchpad Controller."""
        async with app.run_test(size=(120, 40)) as pilot:
            # Switch to Launchpad tab (press 6 - it's bound to "6" key)
            await pilot.press("6")
            await pilot.pause()

            path = SCREENSHOTS_DIR / "05_launchpad.svg"
            app.save_screenshot(str(path))

            assert path.exists()

    @pytest.mark.asyncio
    async def test_screenshot_shaders(self, app):
        """Screenshot Tab 6: Shader Index - shader analysis."""
        async with app.run_test(size=(120, 40)) as pilot:
            # Switch to Shaders tab (press 7)
            await pilot.press("7")
            await pilot.pause()

            path = SCREENSHOTS_DIR / "06_shaders.svg"
            app.save_screenshot(str(path))

            assert path.exists()


class TestUIInteractions:
    """Test UI interactions and capture states."""

    @pytest.fixture(autouse=True)
    def setup_screenshots_dir(self):
        """Ensure screenshots directory exists."""
        SCREENSHOTS_DIR.mkdir(parents=True, exist_ok=True)

    @pytest.fixture
    def app(self):
        """Create VJConsoleApp instance for testing."""
        from vj_console import VJConsoleApp
        return VJConsoleApp()

    @pytest.mark.asyncio
    async def test_screenshot_all_tabs_sequence(self, app):
        """Capture all tabs in sequence for documentation."""
        tabs = [
            ("1", "01_master_control"),
            ("2", "02_osc_view"),
            ("3", "03_ai_debug"),
            ("4", "04_logs"),
            ("6", "05_launchpad"),
            ("7", "06_shaders"),
        ]

        async with app.run_test(size=(120, 40)) as pilot:
            for key, name in tabs:
                await pilot.press(key)
                await pilot.pause()

                path = SCREENSHOTS_DIR / f"{name}.svg"
                app.save_screenshot(str(path))

                assert path.exists(), f"Screenshot {name} should be saved"


def generate_documentation():
    """Generate markdown documentation from screenshots."""
    doc_path = SCREENSHOTS_DIR.parent.parent.parent / "UI_GUIDE.md"

    screenshots = sorted(SCREENSHOTS_DIR.glob("*.svg"))
    if not screenshots:
        print("No screenshots found. Run tests first.")
        return

    tab_descriptions = {
        "01_master_control": {
            "title": "Master Control",
            "key": "1",
            "description": """
The main dashboard showing all key information at a glance.

**Left Column:**
- **Startup Control** - Start/stop all services, configure auto-start
- **Playback Source** - Select music source (Spotify, VirtualDJ, etc.)
- **Master Control** - Quick controls for timing adjustment
- **Apps List** - Processing apps status and controls
- **Services** - External service health (LM Studio, etc.)

**Right Column:**
- **Now Playing** - Current track info with progress
- **Categories** - AI-detected song categories (mood, genre, era)
- **Pipeline** - Processing pipeline status
""",
        },
        "02_osc_view": {
            "title": "OSC View",
            "key": "2",
            "description": """
Full OSC message debugging view.

- **OSC Control Panel** - Start/stop individual channels or all at once
- **Message Log** - Live stream of all OSC messages grouped by address
- Shows message frequency, last values, and timestamps
- Useful for debugging communication with Synesthesia, VirtualDJ, etc.
""",
        },
        "03_ai_debug": {
            "title": "Song AI Debug",
            "key": "3",
            "description": """
Detailed view of song categorization and AI analysis.

**Left Column:**
- **Categories** - Full breakdown of detected categories with confidence scores

**Right Column:**
- **Pipeline** - Detailed processing pipeline with timing for each step
""",
        },
        "04_logs": {
            "title": "All Logs",
            "key": "4",
            "description": """
Complete application log output.

- Shows INFO, WARNING, and ERROR level messages
- Timestamps and source module for each entry
- Scrollable history
- Useful for debugging issues
""",
        },
        "05_launchpad": {
            "title": "Launchpad Controller",
            "key": "6",
            "description": """
Launchpad MIDI controller integration.

**Left Column:**
- **Status** - Controller connection status
- **Pads** - Current pad mappings and learn mode status

**Right Column:**
- **Instructions** - How to use the controller
- **Tests** - Test buttons for debugging
- **OSC Debug** - OSC messages sent/received by controller
""",
        },
        "06_shaders": {
            "title": "Shader Index",
            "key": "7",
            "description": """
Shader analysis and matching system.

**Actions:** Pause/Resume analysis, Search by mood/energy, Rescan

**Left Column:**
- **Shader Index** - List of indexed shaders with feature scores
- **Analysis** - Current analysis status and progress

**Right Column:**
- **Search Results** - Matching shaders for current song
- **Match Details** - Why a shader was matched (feature similarity)
""",
        },
    }

    content = """# VJ Console UI Guide

This document provides an overview of each screen in the VJ Console terminal UI.

## Quick Navigation

| Key | Screen |
|-----|--------|
| 1 | Master Control |
| 2 | OSC View |
| 3 | Song AI Debug |
| 4 | All Logs |
| 6 | Launchpad Controller |
| 7 | Shader Index |
| q | Quit |

---

"""

    for screenshot in screenshots:
        name = screenshot.stem
        info = tab_descriptions.get(name, {})

        title = info.get("title", name.replace("_", " ").title())
        key = info.get("key", "?")
        desc = info.get("description", "")

        content += f"""## {title} (Press {key})

{desc.strip()}

![{title}](tests/e2e/screenshots/{screenshot.name})

---

"""

    content += """## Keyboard Shortcuts

| Key | Action |
|-----|--------|
| s | Toggle Synesthesia |
| m | Toggle MilkSyphon |
| + | Increase timing offset |
| - | Decrease timing offset |
| p | Pause/Resume shader analysis (on Shaders tab) |
| / | Search shaders by mood (on Shaders tab) |
| e | Search shaders by energy (on Shaders tab) |
| R | Rescan shaders (on Shaders tab) |

---

*Generated from UI screenshots*
"""

    doc_path.write_text(content)
    print(f"Documentation written to: {doc_path}")
    return doc_path


if __name__ == "__main__":
    # If run directly, generate documentation from existing screenshots
    generate_documentation()
