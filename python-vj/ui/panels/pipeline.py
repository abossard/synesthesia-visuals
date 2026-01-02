"""Pipeline panel for VJ Console."""

from textual.reactive import reactive

from utils import truncate
from .base import ReactivePanel


class PipelinePanel(ReactivePanel):
    """Processing pipeline status with timing."""
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

        running = self.pipeline_data.get('running', False)
        result = self.pipeline_data.get('result', {})

        # Header with total time if complete
        if result.get('time_ms'):
            header = f"Pipeline [{result['time_ms']}ms]"
        elif running:
            header = "Pipeline [running...]"
        else:
            header = "Pipeline"
        lines = [self.render_section(header, "═")]

        has_content = False

        # Display pipeline steps as a visual graph
        display_lines = self.pipeline_data.get('display_lines', [])
        if display_lines:
            # Draw pipeline graph
            for i, step_data in enumerate(display_lines):
                # Handle both old format (4 elements) and new format (5 elements)
                if len(step_data) == 5:
                    label, status_icon, color, message, timing = step_data
                else:
                    label, status_icon, color, message = step_data
                    timing = ""

                # Draw connector
                is_last = i == len(display_lines) - 1
                connector = "└" if is_last else "├"

                # Build line with status, label, message and timing
                status_text = f"[{color}]{status_icon}[/]"
                timing_text = f"[dim]{timing}[/]" if timing else ""

                if message:
                    line = f"  {connector}─ {status_text} [bold]{label}[/]: {message}{timing_text}"
                else:
                    line = f"  {connector}─ {status_text} [dim]{label}[/]{timing_text}"

                lines.append(line)
                has_content = True

        # Show current lyric if available
        if self.pipeline_data.get('current_lyric'):
            lyric = self.pipeline_data['current_lyric']
            refrain_tag = " [magenta][REFRAIN][/]" if lyric.get('is_refrain') else ""
            lines.append(f"\n[bold white]♪ {lyric.get('text', '')}{refrain_tag}[/]")
            if lyric.get('keywords'):
                lines.append(f"[yellow]   🔑 {lyric['keywords']}[/]")
            has_content = True

        # Show analysis summary if available
        summary = self.pipeline_data.get('analysis_summary')
        if summary:
            lines.append("\n[bold cyan]═══ Analysis ═══[/]")
            if summary.get('keywords'):
                kw = ', '.join(summary['keywords'][:8])
                lines.append(f"[yellow]🔑 {kw}[/]")
            if summary.get('themes'):
                th = ' · '.join(summary['themes'][:4])
                lines.append(f"[green]🎭 {th}[/]")
            if summary.get('visuals'):
                vis = ' · '.join(summary['visuals'][:5])
                lines.append(f"[magenta]🎨 {vis}[/]")
            has_content = True

        if self.pipeline_data.get('error'):
            retry = self.pipeline_data.get('backoff', 0.0)
            extra = f" (retry in {retry:.1f}s)" if retry else ""
            lines.append(f"[yellow]Warning: {self.pipeline_data['error']}{extra}[/]")
            has_content = True

        if not has_content:
            lines.append("[dim]No active processing...[/]")

        self.update("\n".join(lines))
