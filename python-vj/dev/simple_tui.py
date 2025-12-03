#!/usr/bin/env python3
"""
Simple TUI - Demonstrates VJ Bus integration pattern.

Shows how the TUI should integrate with workers via VJBusClient.

Usage:
    # Terminal 1: Start workers
    python dev/start_all_workers.py

    # Terminal 2: Start TUI
    python dev/simple_tui.py
"""

import sys
import time
from pathlib import Path

# Add parent directory to path
sys.path.insert(0, str(Path(__file__).parent.parent))

from textual.app import App, ComposeResult
from textual.containers import Container, Vertical, Horizontal
from textual.widgets import Header, Footer, Static, Button
from textual.binding import Binding
from textual.reactive import reactive

from vj_bus.client import VJBusClient


class WorkerStatus(Static):
    """Display worker status."""

    worker_info = reactive({})

    def watch_worker_info(self, info: dict):
        """Update display when worker info changes."""
        if not info:
            self.update("[dim]No workers connected[/dim]")
            return

        lines = ["[bold]Connected Workers[/bold]\n"]

        for name, data in sorted(info.items()):
            pid = data.get("pid", "?")
            status = data.get("status", "unknown")
            uptime = time.time() - data.get("started_at", time.time())

            color = "green" if status == "running" else "red"
            lines.append(f"[{color}]●[/] {name:20s} PID: {pid:6} ({uptime:.1f}s)")

        self.update("\n".join(lines))


class AudioFeatures(Static):
    """Display audio features."""

    features = reactive({})

    def watch_features(self, data: dict):
        """Update display when features change."""
        if not data:
            self.update("[dim]No audio data[/dim]")
            return

        bands = data.get("bands", [])
        rms = data.get("rms", 0.0)
        beat = data.get("beat", 0)
        bpm = data.get("bpm", 0.0)

        lines = ["[bold]Audio Features[/bold]\n"]

        if beat:
            lines.append("[red]● BEAT[/]")
        else:
            lines.append("[dim]○ beat[/]")

        lines.append(f"BPM: {bpm:.1f}")
        lines.append(f"RMS: {rms:.2f}")

        if bands and len(bands) >= 3:
            lines.append(f"\nBass:  {'█' * int(bands[1] * 20)}")
            lines.append(f"Mids:  {'█' * int(bands[3] * 20) if len(bands) > 3 else ''}")
            lines.append(f"Highs: {'█' * int(bands[6] * 20) if len(bands) > 6 else ''}")

        self.update("\n".join(lines))


class SimpleTUI(App):
    """Simple TUI demonstrating VJ Bus integration."""

    CSS = """
    Screen { background: $surface; }
    Container { padding: 1; }
    .panel { border: solid $primary; padding: 1; height: auto; }
    """

    BINDINGS = [
        Binding("q", "quit", "Quit"),
        Binding("r", "refresh", "Refresh"),
        Binding("s", "start_worker", "Start Worker"),
    ]

    def __init__(self):
        super().__init__()
        self.bus_client = VJBusClient()

    def compose(self) -> ComposeResult:
        yield Header(show_clock=True)

        with Horizontal():
            with Vertical():
                yield WorkerStatus(id="workers", classes="panel")

            with Vertical():
                yield AudioFeatures(id="audio", classes="panel")

        yield Footer()

    def on_mount(self):
        """Initialize VJ Bus connection."""
        self.title = "VJ Bus Simple TUI"

        # Discover workers
        workers = self.bus_client.discover_workers(include_stale=False)
        self.query_one("#workers", WorkerStatus).worker_info = workers

        # Subscribe to audio features
        def audio_handler(msg):
            self.query_one("#audio", AudioFeatures).features = msg.payload

        self.bus_client.subscribe("audio.features", audio_handler)

        # Subscribe to events
        def event_handler(msg):
            self.log(f"Event: {msg.payload.get('event')} - {msg.payload.get('worker')}")

        self.bus_client.subscribe("events.*", event_handler)

        # Start telemetry receiver
        self.bus_client.start()

        # Periodic refresh
        self.set_interval(2.0, self._refresh_workers)

    def _refresh_workers(self):
        """Periodically refresh worker status."""
        try:
            workers = self.bus_client.discover_workers(include_stale=False)
            self.query_one("#workers", WorkerStatus).worker_info = workers
        except Exception as e:
            self.log(f"Failed to refresh workers: {e}")

    def action_refresh(self):
        """Manually refresh worker status."""
        self._refresh_workers()
        self.notify("Refreshed worker status")

    def action_start_worker(self):
        """Start example worker via process manager."""
        try:
            response = self.bus_client.send_command(
                "process_manager",
                "start_worker",
                payload={"worker": "example_worker"}
            )

            if response.status == "ok":
                self.notify("Started example_worker")
            else:
                self.notify(f"Failed: {response.error}", severity="error")

        except Exception as e:
            self.notify(f"Error: {e}", severity="error")

    def on_unmount(self):
        """Cleanup."""
        self.bus_client.stop()


def main():
    app = SimpleTUI()
    app.run()


if __name__ == "__main__":
    main()
