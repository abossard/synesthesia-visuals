"""Pipeline panel for VJ Console."""

from textual.reactive import reactive

from utils import truncate
from .base import ReactivePanel


class PipelinePanel(ReactivePanel):
    """Processing pipeline status."""
    pipeline_data = reactive({})

    def on_mount(self) -> None:
        """Initialize content when mounted."""
        self._safe_render()

    def watch_pipeline_data(self, data: dict) -> None:
        self._safe_render()

    def _safe_render(self) -> None:
        """Render only if mounted."""
        if not self.is_mounted:
            return
        lines = [self.render_section("Processing Pipeline", "═")]

        has_content = False

        # Display pipeline steps with status
        for label, status, color, message in self.pipeline_data.get('display_lines', []):
            status_text = f"[{color}]{status}[/] {label}"
            if message:
                status_text += f": [dim]{message}[/]"
            lines.append(f"  {status_text}")
            has_content = True

        if self.pipeline_data.get('current_lyric'):
            lyric = self.pipeline_data['current_lyric']
            refrain_tag = " [magenta][REFRAIN][/]" if lyric.get('is_refrain') else ""
            lines.append(f"\n[bold white]♪ {lyric.get('text', '')}{refrain_tag}[/]")
            if lyric.get('keywords'):
                lines.append(f"[yellow]   🔑 {lyric['keywords']}[/]")
            has_content = True

        summary = self.pipeline_data.get('analysis_summary')
        if summary:
            lines.append("\n[bold cyan]═══ AI Analysis ═══[/]")
            if summary.get('summary'):
                lines.append(f"[cyan]💭 {truncate(str(summary['summary']), 180)}[/]")
            if summary.get('keywords'):
                kw = ', '.join(summary['keywords'][:8])
                lines.append(f"[yellow]🔑 {kw}[/]")
            if summary.get('themes'):
                th = ' · '.join(summary['themes'][:4])
                lines.append(f"[green]🎭 {th}[/]")
            if summary.get('visuals'):
                vis = ' · '.join(summary['visuals'][:5])
                lines.append(f"[magenta]🎨 {vis}[/]")
            if summary.get('refrain_lines'):
                hooks = summary['refrain_lines'][:3]
                for hook in hooks:
                    lines.append(f"[dim]♫ \"{truncate(str(hook), 60)}\"[/]")
            if summary.get('tempo'):
                lines.append(f"[dim]⏱️  {summary['tempo']}[/]")
            has_content = True

        if self.pipeline_data.get('error'):
            retry = self.pipeline_data.get('backoff', 0.0)
            extra = f" (retry in {retry:.1f}s)" if retry else ""
            lines.append(f"[yellow]Playback warning: {self.pipeline_data['error']}{extra}[/]")
            has_content = True

        if not has_content:
            lines.append("[dim]No active processing...[/]")

        self.update("\n".join(lines))
