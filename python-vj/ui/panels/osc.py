"""OSC panels for VJ Console."""

from textual.app import ComposeResult
from textual.containers import Horizontal
from textual.reactive import reactive
from textual.widgets import Button, Static

from ui.messages import (
    OSCStartRequested,
    OSCStopRequested,
    OSCChannelStartRequested,
    OSCChannelStopRequested,
    OSCClearRequested,
)
from utils import render_aggregated_osc
from .base import ReactivePanel


class OSCPanel(ReactivePanel):
    """OSC messages debug view - aggregated by address."""
    messages = reactive([])  # List of AggregatedMessage
    full_view = reactive(False)
    osc_running = reactive(False)

    def on_mount(self) -> None:
        """Initialize content when mounted."""
        self._safe_render()

    def watch_messages(self, msgs: list) -> None:
        self._safe_render()

    def watch_full_view(self, _: bool) -> None:
        self._safe_render()

    def watch_osc_running(self, _: bool) -> None:
        self._safe_render()

    def _safe_render(self) -> None:
        """Render only if mounted."""
        if not self.is_mounted:
            return
        limit = 50 if self.full_view else 15
        lines = [self.render_section("OSC Debug (grouped by address)", "═")]

        if not self.osc_running:
            lines.append("[dim]OSC Hub is stopped.[/dim]")
            lines.append("[dim]Use the controls above to start OSC.[/dim]")
        elif not self.messages:
            lines.append("[dim](no OSC messages yet)[/dim]")
        else:
            # Messages already sorted by recency from osc_monitor
            for msg in self.messages[:limit]:
                lines.append(render_aggregated_osc(msg))

        self.update("\n".join(lines))


class OSCControlPanel(Static):
    """
    Panel for controlling OSC hub - granular per-channel control.

    Shows channel configuration and allows user to start/stop individual channels.
    """

    # Reactive state
    channel_status = reactive({})

    def compose(self) -> ComposeResult:
        yield Static("[bold]OSC Hub Control[/bold]", classes="section-title")

        # Individual channel controls
        yield Static("[bold cyan]VirtualDJ[/] (send :9009, recv :9008)", id="osc-vdj-label")
        with Horizontal(classes="startup-buttons"):
            yield Button("▶ Start VDJ", id="btn-osc-vdj-start", variant="success")
            yield Button("■ Stop VDJ", id="btn-osc-vdj-stop", variant="error")

        yield Static("[bold magenta]Synesthesia[/] (send :7777, recv :9999)", id="osc-syn-label")
        with Horizontal(classes="startup-buttons"):
            yield Button("▶ Start Synesthesia", id="btn-osc-syn-start", variant="success")
            yield Button("■ Stop Synesthesia", id="btn-osc-syn-stop", variant="error")

        yield Static("[bold green]Karaoke/Processing[/] (send :9000, send-only)", id="osc-kar-label")
        with Horizontal(classes="startup-buttons"):
            yield Button("▶ Start Karaoke", id="btn-osc-kar-start", variant="success")
            yield Button("■ Stop Karaoke", id="btn-osc-kar-stop", variant="error")

        # Global controls
        with Horizontal(classes="startup-buttons"):
            yield Button("▶ Start All", id="btn-osc-start-all", variant="primary")
            yield Button("■ Stop All", id="btn-osc-stop-all", variant="warning")
            yield Button("⟳ Clear Log", id="btn-osc-clear", variant="default")

        yield Static("", id="osc-status-label")

    def on_mount(self) -> None:
        self._update_display()

    def watch_channel_status(self, status: dict) -> None:
        self._update_display()

    def _update_display(self) -> None:
        if not self.is_mounted:
            return

        # Update channel status labels
        for key in ["vdj", "synesthesia", "karaoke"]:
            try:
                ch = self.channel_status.get(key, {})
                active = ch.get("active", False)

                if key == "vdj":
                    label_id = "#osc-vdj-label"
                    status_icon = "[green]● LISTENING[/]" if active else "[dim]○ stopped[/]"
                    self.query_one(label_id, Static).update(
                        f"[bold cyan]VirtualDJ[/] (send :9009, recv :9008) {status_icon}"
                    )
                elif key == "synesthesia":
                    label_id = "#osc-syn-label"
                    status_icon = "[green]● LISTENING[/]" if active else "[dim]○ stopped[/]"
                    self.query_one(label_id, Static).update(
                        f"[bold magenta]Synesthesia[/] (send :7777, recv :9999) {status_icon}"
                    )
                elif key == "karaoke":
                    label_id = "#osc-kar-label"
                    status_icon = "[green]● READY[/]" if active else "[dim]○ stopped[/]"
                    self.query_one(label_id, Static).update(
                        f"[bold green]Karaoke/Processing[/] (send :9000, send-only) {status_icon}"
                    )
            except Exception:
                pass

        # Overall status
        try:
            status_label = self.query_one("#osc-status-label", Static)
            active_channels = sum(1 for ch in self.channel_status.values() if ch.get("active"))
            total_channels = len(self.channel_status)

            if active_channels > 0:
                status_label.update(f"\n[green]● OSC Hub Active[/] ({active_channels}/{total_channels} channels)")
            else:
                status_label.update("\n[dim]○ OSC Hub Inactive[/]")
        except Exception:
            pass

    def on_button_pressed(self, event: Button.Pressed) -> None:
        btn_id = event.button.id

        if btn_id == "btn-osc-vdj-start":
            self.post_message(OSCChannelStartRequested("vdj"))
        elif btn_id == "btn-osc-vdj-stop":
            self.post_message(OSCChannelStopRequested("vdj"))
        elif btn_id == "btn-osc-syn-start":
            self.post_message(OSCChannelStartRequested("synesthesia"))
        elif btn_id == "btn-osc-syn-stop":
            self.post_message(OSCChannelStopRequested("synesthesia"))
        elif btn_id == "btn-osc-kar-start":
            self.post_message(OSCChannelStartRequested("karaoke"))
        elif btn_id == "btn-osc-kar-stop":
            self.post_message(OSCChannelStopRequested("karaoke"))
        elif btn_id == "btn-osc-start-all":
            self.post_message(OSCStartRequested())
        elif btn_id == "btn-osc-stop-all":
            self.post_message(OSCStopRequested())
        elif btn_id == "btn-osc-clear":
            self.post_message(OSCClearRequested())
