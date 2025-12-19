"""OSC panels for VJ Console."""

import time

from textual.app import ComposeResult
from textual.reactive import reactive
from textual.widgets import Button, Input, Static

from ui.messages import OSCClearRequested, VJUniverseTestRequested
from .base import ReactivePanel


class OSCPanel(ReactivePanel):
    """OSC messages debug view - grouped by channel and address."""
    stats = reactive({})
    grouped_prefixes = reactive({})
    grouped_messages = reactive({})
    filter_text = reactive("")
    full_view = reactive(False)
    osc_running = reactive(False)

    def on_mount(self) -> None:
        """Initialize content when mounted."""
        self._safe_render()

    def watch_stats(self, stats: dict) -> None:
        self._safe_render()

    def watch_grouped_prefixes(self, _: dict) -> None:
        self._safe_render()

    def watch_grouped_messages(self, _: dict) -> None:
        self._safe_render()

    def watch_filter_text(self, _: str) -> None:
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
        lines = [self.render_section("OSC Debug (grouped by channel)", "═")]

        if not self.osc_running:
            lines.append("[dim]OSC Hub is not running.[/dim]")
            lines.append("[dim]Check logs for startup errors.[/dim]")
        else:
            filter_label = self.filter_text.strip() or "none"
            lines.append(f"[dim]Filter:[/dim] {filter_label}")
            lines.append("")

            if not self.stats:
                lines.append("[dim](monitor idle)[/dim]")
            else:
                lines.extend(self._render_stats())
                lines.append(self.render_section("Grouped Paths (nesting)", "─"))
                lines.extend(self._render_grouped_prefixes())
                lines.append(self.render_section("Grouped Messages", "─"))
                lines.extend(self._render_grouped_messages(limit))

        self.update("\n".join(lines))

    def _render_stats(self) -> list:
        stats = self.stats or {}
        total = stats.get("total", 0)
        unique = stats.get("unique_addresses", 0)
        rate = stats.get("rate", 0.0)
        channels = stats.get("channels", {})

        lines = [
            self.render_section("OSC Stats", "─"),
            f"Total: {total}  Rate: {rate:.1f}/s  Unique: {unique}",
        ]

        if channels:
            sorted_channels = sorted(channels.items(), key=lambda item: item[1], reverse=True)
            counts = " | ".join(f"{name}:{count}" for name, count in sorted_channels)
            lines.append(f"By channel: {counts}")
        else:
            lines.append("[dim]By channel: (none)[/dim]")

        return lines

    def _render_grouped_prefixes(self) -> list:
        grouped = self.grouped_prefixes or {}
        if not grouped:
            return ["[dim](no grouped data)[/dim]"]

        lines = []
        for channel, entries in sorted(grouped.items()):
            lines.append(self._format_channel_header(channel))
            if not entries:
                lines.append("  [dim](no matches)[/dim]")
                continue
            for prefix, count, depth in entries:
                indent = "  " * (depth - 1)
                lines.append(f"{indent}{prefix} [dim]×{count}[/dim]")
        return lines

    def _render_grouped_messages(self, limit: int) -> list:
        grouped = self.grouped_messages or {}
        if not grouped:
            return ["[dim](no grouped messages)[/dim]"]

        lines = []
        for channel, entries in sorted(grouped.items()):
            lines.append(self._format_channel_header(channel))
            if not entries:
                lines.append("  [dim](no matches)[/dim]")
                continue
            for msg in entries[:limit]:
                lines.append(self._format_message_line(msg))
        return lines

    @staticmethod
    def _format_channel_header(channel: str) -> str:
        label = channel or "hub"
        if label.startswith("→"):
            return f"[cyan]{label}[/cyan]"
        if "vdj" in label.lower():
            return f"[blue]{label}[/blue]"
        if "syn" in label.lower():
            return f"[magenta]{label}[/magenta]"
        if "kar" in label.lower():
            return f"[yellow]{label}[/yellow]"
        return f"[white]{label}[/white]"

    @staticmethod
    def _format_message_line(msg) -> str:
        time_str = time.strftime("%H:%M:%S", time.localtime(msg.last_time))
        args_str = str(msg.last_args) if msg.last_args else ""
        if len(args_str) > 50:
            args_str = args_str[:47] + "..."
        count_str = f" [dim]×{msg.count}[/]" if msg.count > 1 else ""
        return f"  [dim]{time_str}[/] {msg.address:30s} {args_str}{count_str}"


class OSCControlPanel(Static):
    """
    OSC hub summary and filters.

    Hub is always on; monitor runs only while OSC View is open.
    """

    # Reactive state
    channel_status = reactive({})
    filter_text = reactive("")

    def compose(self) -> ComposeResult:
        yield Static("[bold]OSC Hub[/bold]", classes="section-title")
        yield Static("[dim]Always-on hub recv :9999 → fwd :10000, :11111[/dim]")
        yield Static("[dim]Monitor runs only while OSC View tab is open[/dim]")
        yield Static("[dim]Filter OSC addresses (substring):[/dim]")
        yield Input(placeholder="e.g. /audio or /textler", id="osc-filter-input")

        yield Static("[bold]Outgoing Channels[/bold]")
        yield Static("[bold cyan]VirtualDJ[/] (send :9009)", id="osc-vdj-label")
        yield Static("[bold magenta]Synesthesia[/] (send :7777)", id="osc-syn-label")
        yield Static("[bold green]Textler/Processing[/] (send :10000)", id="osc-kar-label")

        yield Button("⟳ Clear Log", id="btn-osc-clear", variant="default")
        yield Button("🧪 Test VJUniverse", id="btn-vjuniverse-test", variant="primary")
        yield Static("", id="osc-status-label")

    def on_mount(self) -> None:
        self._update_display()

    def watch_channel_status(self, status: dict) -> None:
        self._update_display()

    def on_input_changed(self, event: Input.Changed) -> None:
        if event.input.id == "osc-filter-input":
            self.filter_text = event.value.strip()

    def _update_display(self) -> None:
        if not self.is_mounted:
            return

        # Update channel status labels
        for key in ["vdj", "synesthesia", "textler"]:
            try:
                ch = self.channel_status.get(key, {})
                active = ch.get("active", False)

                if key == "vdj":
                    label_id = "#osc-vdj-label"
                    status_icon = "[green]● READY[/]" if active else "[dim]○ offline[/]"
                    self.query_one(label_id, Static).update(
                        f"[bold cyan]VirtualDJ[/] (send :9009) {status_icon}"
                    )
                elif key == "synesthesia":
                    label_id = "#osc-syn-label"
                    status_icon = "[green]● READY[/]" if active else "[dim]○ offline[/]"
                    self.query_one(label_id, Static).update(
                        f"[bold magenta]Synesthesia[/] (send :7777) {status_icon}"
                    )
                elif key == "textler":
                    label_id = "#osc-kar-label"
                    status_icon = "[green]● READY[/]" if active else "[dim]○ offline[/]"
                    self.query_one(label_id, Static).update(
                        f"[bold green]Textler/Processing[/] (send :10000) {status_icon}"
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

        if btn_id == "btn-osc-clear":
            self.post_message(OSCClearRequested())
        elif btn_id == "btn-vjuniverse-test":
            self.post_message(VJUniverseTestRequested())
