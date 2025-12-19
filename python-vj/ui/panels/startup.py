"""Startup control panel for VJ Console."""

from textual.app import ComposeResult
from textual.containers import Horizontal
from textual.reactive import reactive
from textual.widgets import Button, Checkbox, Static

from infrastructure import Settings


class StartupControlPanel(Static):
    """
    Panel with checkboxes for startup services and resource monitoring.
    Persists preferences to Settings and shows CPU/memory for running services.
    """

    # Reactive data for resource stats
    stats_data = reactive({})
    lmstudio_status = reactive({})  # {'available': bool, 'model': str, 'warning': str}

    def __init__(self, settings: Settings, **kwargs):
        super().__init__(**kwargs)
        self.settings = settings

    def compose(self) -> ComposeResult:
        """Create the startup control UI."""
        yield Static("[bold]🚀 Startup Services[/]", classes="section-title")

        # Service checkboxes with auto-restart option
        with Horizontal(classes="startup-row"):
            yield Checkbox("Synesthesia", self.settings.start_synesthesia, id="chk-synesthesia")
            yield Checkbox("Auto-restart", self.settings.autorestart_synesthesia, id="chk-ar-synesthesia")
            yield Static("", id="stat-synesthesia", classes="stat-label")

        with Horizontal(classes="startup-row"):
            yield Checkbox("VJUniverse", self.settings.start_vjuniverse, id="chk-vjuniverse")
            yield Checkbox("Auto-restart", self.settings.autorestart_vjuniverse, id="chk-ar-vjuniverse")
            yield Static("", id="stat-vjuniverse", classes="stat-label")

        with Horizontal(classes="startup-row"):
            yield Checkbox("LM Studio", self.settings.start_lmstudio, id="chk-lmstudio")
            yield Checkbox("Auto-restart", self.settings.autorestart_lmstudio, id="chk-ar-lmstudio")
            yield Static("", id="stat-lmstudio", classes="stat-label")

        with Horizontal(classes="startup-row"):
            yield Checkbox("Magic Music Visuals", self.settings.start_magic, id="chk-magic")
            yield Checkbox("Auto-restart", self.settings.autorestart_magic, id="chk-ar-magic")
            yield Static("", id="stat-magic", classes="stat-label")

        # Start/Stop All buttons
        with Horizontal(classes="startup-buttons"):
            yield Button("▶ Start All", id="btn-start-all", variant="success")
            yield Button("■ Stop All", id="btn-stop-all", variant="error")

    def on_checkbox_changed(self, event: Checkbox.Changed) -> None:
        """Persist checkbox changes to settings."""
        checkbox_id = event.checkbox.id
        value = event.value

        # Map checkbox IDs to settings properties
        mappings = {
            "chk-synesthesia": "start_synesthesia",
            "chk-vjuniverse": "start_vjuniverse",
            "chk-lmstudio": "start_lmstudio",
            "chk-magic": "start_magic",
            "chk-ar-synesthesia": "autorestart_synesthesia",
            "chk-ar-vjuniverse": "autorestart_vjuniverse",
            "chk-ar-lmstudio": "autorestart_lmstudio",
            "chk-ar-magic": "autorestart_magic",
        }

        if checkbox_id in mappings:
            setattr(self.settings, mappings[checkbox_id], value)

    def watch_stats_data(self, stats: dict) -> None:
        """Update resource display when stats change."""
        self._update_stat_labels()

    def watch_lmstudio_status(self, status: dict) -> None:
        """Update LM Studio status display."""
        self._update_stat_labels()

    def _update_stat_labels(self) -> None:
        """Update all stat labels with current data."""
        if not self.is_mounted:
            return

        stats = self.stats_data
        lm_status = self.lmstudio_status

        # Synesthesia stats
        try:
            label = self.query_one("#stat-synesthesia", Static)
            syn_stats = stats.get("Synesthesia")
            if syn_stats and syn_stats.running:
                label.update(f"[green]● {syn_stats.cpu_percent:.0f}% / {syn_stats.memory_mb:.0f}MB[/]")
            else:
                label.update("[dim]○ Not running[/]")
        except Exception:
            pass

        # VJUniverse stats (Processing/Java)
        try:
            label = self.query_one("#stat-vjuniverse", Static)
            vj_stats = stats.get("java") or stats.get("Java")
            if vj_stats and vj_stats.running:
                label.update(f"[green]● {vj_stats.cpu_percent:.0f}% / {vj_stats.memory_mb:.0f}MB[/]")
            else:
                label.update("[dim]○ Not running[/]")
        except Exception:
            pass

        # LM Studio stats
        try:
            label = self.query_one("#stat-lmstudio", Static)
            lm_stats = stats.get("LM Studio")
            if lm_stats and lm_stats.running:
                if lm_status.get('available'):
                    model = lm_status.get('model', 'loaded')
                    if lm_status.get('warning'):
                        label.update(f"[yellow]● {lm_stats.cpu_percent:.0f}% / {lm_stats.memory_mb:.0f}MB - ⚠ {lm_status['warning']}[/]")
                    else:
                        label.update(f"[green]● {lm_stats.cpu_percent:.0f}% / {lm_stats.memory_mb:.0f}MB - {model[:20]}[/]")
                else:
                    label.update(f"[yellow]● {lm_stats.cpu_percent:.0f}% / {lm_stats.memory_mb:.0f}MB - No model loaded[/]")
            else:
                label.update("[dim]○ Not running[/]")
        except Exception:
            pass

        # Magic Music Visuals stats
        try:
            label = self.query_one("#stat-magic", Static)
            magic_stats = stats.get("Magic")
            if magic_stats and magic_stats.running:
                label.update(f"[green]● {magic_stats.cpu_percent:.0f}% / {magic_stats.memory_mb:.0f}MB[/]")
            else:
                label.update("[dim]○ Not running[/]")
        except Exception:
            pass
