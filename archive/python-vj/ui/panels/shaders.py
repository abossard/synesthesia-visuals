"""Shader-related panels for VJ Console."""

from textual.app import ComposeResult
from textual.containers import Horizontal
from textual.reactive import reactive
from textual.widgets import Button, Static

from utils import format_bar, format_status_icon, truncate
from .base import ReactivePanel

# Shader matcher availability
try:
    from shader_matcher import ShaderIndexer, ShaderSelector
    SHADER_MATCHER_AVAILABLE = True
except ImportError:
    SHADER_MATCHER_AVAILABLE = False


class ShaderIndexPanel(ReactivePanel):
    """Shader indexer status panel."""
    status = reactive({})

    def on_mount(self) -> None:
        """Initialize content when mounted."""
        self._safe_render()

    def watch_status(self, data: dict) -> None:
        self._safe_render()

    def _safe_render(self) -> None:
        """Render only if mounted."""
        if not self.is_mounted:
            return

        lines = [self.render_section("Shader Indexer", "═")]

        if not SHADER_MATCHER_AVAILABLE:
            lines.append("[yellow]Shader matcher not available[/]")
            lines.append("[dim]Check shader_matcher.py imports[/]")
        else:
            total = self.status.get('total_shaders', 0)
            analyzed = self.status.get('analyzed', 0)
            unanalyzed = self.status.get('unanalyzed', 0)
            loaded = self.status.get('loaded_in_memory', 0)
            chromadb = self.status.get('chromadb_enabled', False)

            status_icon = format_status_icon(loaded > 0, "● READY", "○ loading")
            chromadb_icon = format_status_icon(chromadb, "● ON", "○ OFF")

            lines.append(f"  Status:        {status_icon}")
            lines.append(f"  Total Shaders: {total}")
            lines.append(f"  Analyzed:      [green]{analyzed}[/]")

            if unanalyzed > 0:
                lines.append(f"  Unanalyzed:    [yellow]{unanalyzed}[/]")
            else:
                lines.append(f"  Unanalyzed:    {unanalyzed}")

            lines.append(f"  Loaded:        {loaded}")
            lines.append(f"  ChromaDB:      {chromadb_icon}")

            shaders_dir = self.status.get('shaders_dir', '')
            if shaders_dir:
                lines.append(f"\n[dim]Path: {truncate(shaders_dir, 50)}[/]")

        self.update("\n".join(lines))


class ShaderMatchPanel(ReactivePanel):
    """Shader matching test panel."""
    match_result = reactive({})

    def on_mount(self) -> None:
        """Initialize content when mounted."""
        self._safe_render()

    def watch_match_result(self, data: dict) -> None:
        self._safe_render()

    def _safe_render(self) -> None:
        """Render only if mounted."""
        if not self.is_mounted:
            return

        lines = [self.render_section("Shader Matching", "═")]

        if not SHADER_MATCHER_AVAILABLE:
            lines.append("[dim]Shader matcher not available[/]")
        elif not self.match_result.get('matches'):
            lines.append("[dim](no matches yet)[/dim]")
            lines.append("")
            lines.append("[dim]Matches update on track change[/]")
        else:
            mood = self.match_result.get('mood', 'unknown')
            energy = self.match_result.get('energy', 0.5)
            lines.append(f"  Mood:   [cyan]{mood}[/]")
            lines.append(f"  Energy: {format_bar(energy)} {energy:.2f}")
            lines.append("")
            lines.append("[bold]Top Matches:[/]")

            for match in self.match_result.get('matches', [])[:5]:
                name = match.get('name', 'Unknown')
                score = match.get('score', 0)
                features = match.get('features', {})

                # Color by match quality (lower score = better match)
                if score < 0.3:
                    color = "green"
                elif score < 0.6:
                    color = "yellow"
                else:
                    color = "dim"

                lines.append(f"  [{color}]{name:25s} {score:.3f}[/]")

                if features:
                    e = features.get('energy_score', 0.5)
                    v = features.get('mood_valence', 0)
                    lines.append(f"    [dim]energy={e:.2f} valence={v:+.2f}[/]")

        self.update("\n".join(lines))


class ShaderAnalysisPanel(ReactivePanel):
    """Panel showing shader analysis progress and recent results."""
    analysis_status = reactive({})

    def on_mount(self) -> None:
        self._safe_render()

    def watch_analysis_status(self, data: dict) -> None:
        self._safe_render()

    def _safe_render(self) -> None:
        if not self.is_mounted:
            return

        lines = [self.render_section("Shader Analysis", "═")]

        if not SHADER_MATCHER_AVAILABLE:
            lines.append("[yellow]Shader matcher not available[/]")
            self.update("\n".join(lines))
            return

        running = self.analysis_status.get('running', False)
        current = self.analysis_status.get('current_shader', '')
        progress = self.analysis_status.get('progress', 0)
        total = self.analysis_status.get('total', 0)
        analyzed = self.analysis_status.get('analyzed', 0)
        errors = self.analysis_status.get('errors', 0)
        last_error = self.analysis_status.get('last_error', '')
        recent = self.analysis_status.get('recent', [])

        # Status
        if running:
            lines.append(f"  Status: [green]● ANALYZING[/]")
            lines.append(f"  Current: [cyan]{truncate(current, 30)}[/]")
        else:
            if total > 0 and progress >= total:
                lines.append(f"  Status: [green]● COMPLETE[/]")
            else:
                lines.append(f"  Status: [yellow]○ PAUSED[/] (press [bold]p[/] to start)")

        # Progress bar
        if total > 0:
            pct = progress / total
            bar = format_bar(pct)
            lines.append(f"  Progress: {bar} {progress}/{total}")

        lines.append("")
        lines.append(f"  ✓ Analyzed: [green]{analyzed}[/]    ✗ Errors: [red]{errors}[/]")

        # Recent analyses table
        if recent:
            lines.append("")
            lines.append("[bold]Recent Analyses:[/]")
            lines.append("[dim]" + "─" * 60 + "[/]")
            lines.append(f"  {'Shader':<22} {'Mood':<12} {'Energy':<8} {'E':>4} {'M':>4} {'G':>4}")
            lines.append("[dim]" + "─" * 60 + "[/]")

            for r in recent[:8]:
                name = truncate(r.get('name', '?'), 20)
                mood = r.get('mood', '?')[:10]
                energy = r.get('energy', '?')[:6]
                features = r.get('features', {})
                e_score = features.get('energy_score', 0)
                m_speed = features.get('motion_speed', 0)
                g_score = features.get('geometric_score', 0)

                # Color mood by type
                mood_colors = {
                    'energetic': 'bright_red', 'aggressive': 'red',
                    'calm': 'bright_blue', 'peaceful': 'blue',
                    'dark': 'dim', 'mysterious': 'magenta',
                    'bright': 'bright_yellow', 'psychedelic': 'bright_magenta',
                    'chaotic': 'orange1', 'dreamy': 'cyan'
                }
                mc = mood_colors.get(mood, 'white')

                lines.append(
                    f"  {name:<22} [{mc}]{mood:<12}[/] {energy:<8} "
                    f"[cyan]{e_score:.1f}[/] [green]{m_speed:.1f}[/] [yellow]{g_score:.1f}[/]"
                )

            lines.append("[dim]" + "─" * 60 + "[/]")
            lines.append("[dim]E=energy M=motion G=geometric[/]")

        if last_error:
            lines.append("")
            lines.append(f"[dim]Last error: {truncate(last_error, 50)}[/]")

        lines.append("")
        lines.append("[dim]Keys: [p] pause/resume, [r] retry errors[/]")

        self.update("\n".join(lines))


class ShaderSearchPanel(ReactivePanel):
    """Panel for semantic shader search testing."""
    search_results = reactive({})

    def on_mount(self) -> None:
        self._safe_render()

    def watch_search_results(self, data: dict) -> None:
        self._safe_render()

    def _safe_render(self) -> None:
        if not self.is_mounted:
            return

        lines = [self.render_section("Semantic Search", "═")]

        if not SHADER_MATCHER_AVAILABLE:
            lines.append("[dim]Shader matcher not available[/]")
            self.update("\n".join(lines))
            return

        query = self.search_results.get('query', '')
        results = self.search_results.get('results', [])
        search_type = self.search_results.get('type', 'mood')

        lines.append(f"  Type: [cyan]{search_type}[/]")
        if query:
            lines.append(f"  Query: [bold]{query}[/]")
        else:
            lines.append("  [dim]Press / to search by mood[/]")
            lines.append("  [dim]Press e to search by energy[/]")

        if results:
            lines.append("")
            lines.append("[bold]Results:[/]")
            for i, result in enumerate(results[:8], 1):
                name = result.get('name', 'Unknown')
                score = result.get('score', 0)
                features = result.get('features', {})

                # Color by rank
                if i <= 2:
                    color = "green"
                elif i <= 5:
                    color = "yellow"
                else:
                    color = "dim"

                lines.append(f"  {i}. [{color}]{name:25s}[/] [dim]dist={score:.3f}[/]")

                if features:
                    e = features.get('energy_score', 0.5)
                    m = features.get('motion_speed', 0.5)
                    lines.append(f"     [dim]energy={e:.2f} motion={m:.2f}[/]")
        elif query:
            lines.append("")
            lines.append("[dim]No results[/]")

        self.update("\n".join(lines))


class ShaderActionsPanel(Static):
    """Action buttons for Shader Indexer screen."""

    analysis_running = reactive(False)

    def compose(self) -> ComposeResult:
        with Horizontal(classes="action-buttons"):
            yield Button("▶ Start Analysis", variant="primary", id="shader-pause-resume")
            yield Button("🔍 Mood", id="shader-search-mood")
            yield Button("⚡ Energy", id="shader-search-energy")
            yield Button("📝 Text", variant="success", id="shader-search-text")
            yield Button("🔄 Rescan", id="shader-rescan")

    def watch_analysis_running(self, running: bool) -> None:
        """Update button label based on analysis state."""
        try:
            btn = self.query_one("#shader-pause-resume", Button)
            btn.label = "⏸ Pause Analysis" if running else "▶ Start Analysis"
            btn.variant = "warning" if running else "primary"
        except Exception:
            pass
