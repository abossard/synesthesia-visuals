"""Playback panels for VJ Console."""

from textual.app import ComposeResult
from textual.reactive import reactive
from textual.widgets import Static, RadioSet, RadioButton

from infrastructure import Settings
from karaoke_engine import PLAYBACK_SOURCES
from ui.messages import PlaybackSourceChanged
from utils import format_status_icon, format_duration
from .base import ReactivePanel


class NowPlayingPanel(ReactivePanel):
    """Current track display."""
    track_data = reactive({})
    shader_name = reactive("")  # Current active shader

    def on_mount(self) -> None:
        """Initialize content when mounted."""
        self.update("[dim]Waiting for playback...[/dim]")

    def watch_track_data(self, data: dict) -> None:
        self._safe_render()

    def watch_shader_name(self, name: str) -> None:
        self._safe_render()

    def _safe_render(self) -> None:
        if not self.is_mounted:
            return
        data = self.track_data
        if not data:
            self.update("[dim]Waiting for playback...[/dim]")
            return

        error = data.get('error')
        backoff = data.get('backoff', 0.0)
        raw_source_value = data.get('source') or ""
        source_raw = raw_source_value.lower()
        if source_raw.startswith("spotify"):
            source_label = "Spotify"
        else:
            source_label = (raw_source_value or "Playback").replace("_", " ").title()
        if not data.get('artist'):
            if error:
                msg = "[yellow]Playback paused:[/] {error}".format(error=error)
                if backoff:
                    msg += f" (retry in {backoff:.1f}s)"
                self.update(msg)
            else:
                self.update("[dim]Waiting for playback...[/dim]")
            return

        conn = format_status_icon(data.get('connected', False), "● Connected", "◐ Connecting...")
        time_str = format_duration(data.get('position', 0), data.get('duration', 0))
        icon = "🎵" if source_raw.startswith("spotify") else "🎧"
        warning = ""
        if error:
            warning = f"\n[yellow]{error}"
            if backoff:
                warning += f" (retry in {backoff:.1f}s)"

        # Add shader info if available
        shader_info = ""
        if self.shader_name:
            shader_info = f"  │  [magenta]🎨 {self.shader_name}[/]"

        self.update(
            f"{source_label}: {conn}\n"
            f"[bold]Now Playing:[/] [cyan]{data.get('artist', '')}[/] — {data.get('title', '')}\n"
            f"{icon} {source_label}  │  [dim]{time_str}[/]{shader_info}{warning}"
        )


class PlaybackSourcePanel(Static):
    """
    Panel for selecting playback source with radio buttons.
    Shows: source selection, running status with latency.
    """

    # Reactive data
    lookup_ms = reactive(0.0)
    monitor_running = reactive(False)

    def __init__(self, settings: Settings, **kwargs):
        super().__init__(**kwargs)
        self.settings = settings
        self._source_keys = list(PLAYBACK_SOURCES.keys())

    def compose(self) -> ComposeResult:
        """Create the playback source UI."""
        yield Static("[bold]🎵 Playback Source[/]", classes="section-title")

        # Status line showing if monitor is running
        yield Static("[dim]○ Not running[/]", id="monitor-status-label")

        # Radio buttons for source selection
        current_source = self.settings.playback_source
        with RadioSet(id="source-radio"):
            for key in self._source_keys:
                info = PLAYBACK_SOURCES[key]
                label = info['label']
                is_selected = key == current_source
                yield RadioButton(label, value=is_selected, id=f"src-{key}")

        # Poll interval display
        yield Static(f"[dim]Poll interval: {self.settings.playback_poll_interval_ms}ms[/]", id="poll-interval-label")

    def watch_monitor_running(self, running: bool) -> None:
        """Update status when monitor running state changes."""
        self._update_status_label()

    def watch_lookup_ms(self, ms: float) -> None:
        """Update status when lookup time changes."""
        self._update_status_label()

    def _update_status_label(self) -> None:
        """Update the status label with running state and latency."""
        if not self.is_mounted:
            return
        try:
            label = self.query_one("#monitor-status-label", Static)
            source = self.settings.playback_source
            if not self.monitor_running:
                if source:
                    source_label = PLAYBACK_SOURCES.get(source, {}).get('label', source)
                    label.update(f"[dim]○ {source_label} (not running)[/]")
                else:
                    label.update("[dim]○ No source selected[/]")
            else:
                source_label = PLAYBACK_SOURCES.get(source, {}).get('label', source)
                ms = self.lookup_ms
                if ms > 0:
                    color = "green" if ms < 100 else ("yellow" if ms < 500 else "red")
                    label.update(f"[{color}]● {source_label} ({ms:.0f}ms)[/]")
                else:
                    label.update(f"[green]● {source_label}[/]")
        except Exception:
            pass

    def on_radio_set_changed(self, event: RadioSet.Changed) -> None:
        """Handle source selection change."""
        if event.radio_set.id != "source-radio":
            return

        # Get the selected button's id and extract source key
        pressed = event.pressed
        if pressed and pressed.id and pressed.id.startswith("src-"):
            source_key = pressed.id[4:]  # Remove "src-" prefix
            if source_key in PLAYBACK_SOURCES:
                self.settings.playback_source = source_key
                # Notify app to switch the monitor
                self.post_message(PlaybackSourceChanged(source_key))
