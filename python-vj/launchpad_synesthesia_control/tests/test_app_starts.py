"""Smoke test to ensure the Textual app launches without crashing."""

import pytest

pytest.importorskip(
    "textual.testing",
    reason="textual.testing helpers are unavailable in this Textual build",
)

from textual.testing import ApplicationRunner

from launchpad_synesthesia_control.app.ui.tui import LaunchpadSynesthesiaApp


@pytest.mark.asyncio
async def test_application_starts():
    """Verify that the TUI can be mounted and shut down cleanly."""
    runner = ApplicationRunner(LaunchpadSynesthesiaApp)

    async with runner.run_test() as pilot:
        # Allow a single cycle to ensure on_mount completes.
        await pilot.pause()

    # If we reach this point without exceptions, the app booted successfully.
    assert True
