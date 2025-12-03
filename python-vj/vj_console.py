#!/usr/bin/env python3
"""
VJ Console - Textual Edition with Multi-Screen Support

Screens (press 1-5 to switch):
1. Master Control - Main dashboard with all controls
2. OSC View - Full OSC message debug view  
3. Song AI Debug - Song categorization and pipeline details
4. All Logs - Complete application logs
5. Audio Analysis - Real-time audio analysis and OSC emission
"""

from dotenv import load_dotenv
from pathlib import Path
from typing import Optional, List, Dict, Tuple, Any
import logging
import subprocess
import time
import threading

from textual.app import App, ComposeResult
from textual.containers import Horizontal, VerticalScroll
from textual.widgets import Header, Footer, Static, TabbedContent, TabPane
from textual.reactive import reactive
from textual.binding import Binding

from process_manager import ProcessManager
from karaoke_engine import Config as KaraokeConfig  # Only for config utilities
from domain import get_active_line_index

# VJ Bus - Required for pure worker architecture
from vj_bus.client import VJBusClient

# Audio analysis (imported conditionally to handle missing dependencies)
try:
    from audio_analyzer import (
        AudioConfig, DeviceConfig, DeviceManager, 
        AudioAnalyzer, AudioAnalyzerWatchdog, LatencyTester
    )
    AUDIO_ANALYZER_AVAILABLE = True
except ImportError as e:
    AUDIO_ANALYZER_AVAILABLE = False
    # Logger might not be initialized yet at module level, so use print as fallback
    import sys
    print(f"Warning: Audio analyzer not available - {e}", file=sys.stderr)
    print("Install dependencies: pip install sounddevice numpy essentia", file=sys.stderr)

load_dotenv(override=True, verbose=True)

logger = logging.getLogger('vj_console')

# ============================================================================
# PURE FUNCTIONS (Calculations) - No side effects, same input = same output
# ============================================================================

def format_time(seconds: float) -> str:
    """Format seconds as MM:SS."""
    try:
        mins, secs = int(seconds // 60), int(seconds % 60)
        return f"{mins}:{secs:02d}"
    except (ValueError, TypeError):
        return "0:00"

def format_duration(position: float, duration: float) -> str:
    """Format position/duration as MM:SS / MM:SS."""
    return f"{format_time(position)} / {format_time(duration)}"

def format_status_icon(active: bool, running_text: str = "● ON", stopped_text: str = "○ OFF") -> str:
    """Format a status indicator."""
    return f"[green]{running_text}[/]" if active else f"[dim]{stopped_text}[/]"

def format_bar(value: float, width: int = 15) -> str:
    """Create a visual bar from 0.0-1.0 value."""
    filled = int(value * width)
    return "█" * filled + "░" * (width - filled)

def color_by_score(score: float) -> str:
    """Get color name based on score threshold."""
    if score >= 0.7:
        return "green"
    if score >= 0.4:
        return "yellow"
    return "dim"

def color_by_level(text: str) -> str:
    """Get color based on log level in text."""
    if "ERROR" in text or "EXCEPTION" in text:
        return "red"
    if "WARNING" in text:
        return "yellow"
    if "INFO" in text:
        return "green"
    return "dim"

def color_by_osc_channel(address: str) -> str:
    """Get color based on OSC address channel."""
    if "/karaoke/categories" in address:
        return "yellow"
    if "/vj/" in address:
        return "cyan"
    if "/karaoke/" in address:
        return "green"
    return "white"

def truncate(text: str, max_len: int, suffix: str = "...") -> str:
    """Truncate text with suffix if too long."""
    return text[:max_len - len(suffix)] + suffix if len(text) > max_len else text

def render_category_line(name: str, score: float) -> str:
    """Render a single category with bar."""
    color = color_by_score(score)
    bar = format_bar(score)
    return f"  [{color}]{name:15s} {bar} {score:.2f}[/]"

def render_osc_message(msg: Tuple[float, str, Any]) -> str:
    """Render a single OSC message with full args."""
    ts, address, args = msg
    time_str = time.strftime("%H:%M:%S", time.localtime(ts))
    args_str = str(args)  # Show full message content
    color = color_by_osc_channel(address)
    return f"[dim]{time_str}[/] [{color}]{address}[/] {args_str}"

def render_log_line(log: str) -> str:
    """Render a single log line with color."""
    return f"[{color_by_level(log)}]{log}[/]"


def estimate_position(state: PlaybackState) -> float:
    """Estimate real-time playback position from cached state."""
    if not state.is_playing:
        return state.position
    return state.position + max(0.0, time.time() - state.last_update)


def build_track_data(snapshot: PlaybackSnapshot, source_available: bool) -> Dict[str, Any]:
    """Derive track panel data from snapshot."""
    state = snapshot.state
    track = state.track
    base = {
        'error': snapshot.error,
        'backoff': snapshot.backoff_seconds,
        'source': snapshot.source,
        # If we have live track data, the monitor clearly responded, so treat it as connected
        'connected': source_available or bool(state.track),
    }
    if not track:
        return base
    return {
        **base,
        'artist': track.artist,
        'title': track.title,
        'duration': track.duration,
        'position': estimate_position(state),
    }


def build_pipeline_data(engine: KaraokeEngine, snapshot: PlaybackSnapshot) -> Dict[str, Any]:
    """Assemble pipeline panel payload."""
    pipeline_data = {
        'display_lines': engine.pipeline.get_display_lines(),
        'image_prompt': engine.pipeline.image_prompt,
        'error': snapshot.error,
        'backoff': snapshot.backoff_seconds,
    }
    lines = engine.current_lines
    state = snapshot.state
    if lines and state.track:
        offset_ms = engine.timing_offset_ms
        position = estimate_position(state)
        idx = get_active_line_index(lines, position + offset_ms / 1000.0)
        if 0 <= idx < len(lines):
            line = lines[idx]
            pipeline_data['current_lyric'] = {
                'text': line.text,
                'keywords': line.keywords,
                'is_refrain': line.is_refrain
            }
    return pipeline_data


def build_categories_payload(categories) -> Dict[str, Any]:
    """Format categories for UI panels."""
    if not categories:
        return {}
    return {
        'primary_mood': categories.primary_mood,
        'categories': [
            {'name': cat.name, 'score': cat.score}
            for cat in categories.get_top(10)
        ]
    }

# ============================================================================
# WIDGETS - Reactive UI components
# ============================================================================

class ReactivePanel(Static):
    """Base class for reactive panels with common patterns."""
    
    def render_section(self, title: str, emoji: str = "═") -> str:
        return f"[bold]{emoji * 3} {title} {emoji * 3}[/]\n"


class NowPlayingPanel(ReactivePanel):
    """Current track display."""
    track_data = reactive({})

    def on_mount(self) -> None:
        """Initialize content when mounted."""
        self.update("[dim]Waiting for playback...[/dim]")

    def watch_track_data(self, data: dict) -> None:
        if not self.is_mounted:
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
        
        self.update(
            f"{source_label}: {conn}\n"
            f"[bold]Now Playing:[/] [cyan]{data.get('artist', '')}[/] — {data.get('title', '')}\n"
            f"{icon} {source_label}  │  [dim]{time_str}[/]{warning}"
        )


class CategoriesPanel(ReactivePanel):
    """Song mood/theme categories."""
    categories_data = reactive({})

    def on_mount(self) -> None:
        """Initialize content when mounted."""
        self._safe_render()

    def watch_categories_data(self, data: dict) -> None:
        self._safe_render()

    def _safe_render(self) -> None:
        """Render only if mounted."""
        if not self.is_mounted:
            return
        lines = [self.render_section("Song Categories", "═")]
        
        if not self.categories_data.get('categories'):
            lines.append("[dim](waiting for song analysis...)[/dim]")
        else:
            if self.categories_data.get('primary_mood'):
                lines.append(f"[bold cyan]Primary Mood:[/] [bold]{self.categories_data['primary_mood'].upper()}[/]\n")
            lines.extend(render_category_line(c['name'], c['score']) for c in self.categories_data.get('categories', [])[:10])
        
        self.update("\n".join(lines))


class OSCPanel(ReactivePanel):
    """OSC messages debug view."""
    messages = reactive([])
    full_view = reactive(False)

    def on_mount(self) -> None:
        """Initialize content when mounted."""
        self._safe_render()

    def watch_messages(self, msgs: list) -> None:
        self._safe_render()
    
    def watch_full_view(self, _: bool) -> None:
        self._safe_render()

    def _safe_render(self) -> None:
        """Render only if mounted."""
        if not self.is_mounted:
            return
        limit = 50 if self.full_view else 15
        lines = [self.render_section("OSC Debug", "═")]
        
        if not self.messages:
            lines.append("[dim](no OSC messages yet)[/dim]")
        else:
            lines.extend(render_osc_message(m) for m in reversed(self.messages[-limit:]))
        
        self.update("\n".join(lines))


class LogsPanel(ReactivePanel):
    """Application logs view."""
    logs = reactive([])

    def on_mount(self) -> None:
        """Initialize content when mounted."""
        self._safe_render()

    def watch_logs(self, data: list) -> None:
        self._safe_render()

    def _safe_render(self) -> None:
        """Render only if mounted."""
        if not self.is_mounted:
            return
        lines = [self.render_section("Application Logs", "═")]
        
        if not self.logs:
            lines.append("[dim](no logs yet)[/dim]")
        else:
            lines.extend(render_log_line(log) for log in reversed(self.logs[-100:]))
        
        self.update("\n".join(lines))


class MasterControlPanel(ReactivePanel):
    """VJ app control panel."""
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
        syn = format_status_icon(bool(self.status.get('synesthesia')), "● RUNNING", "○ stopped")
        pms = format_status_icon(bool(self.status.get('milksyphon')), "● RUNNING", "○ stopped")
        kar = format_status_icon(bool(self.status.get('karaoke')), "● ACTIVE", "○ inactive")
        proc = self.status.get('processing_apps', 0)
        
        self.update(
            self.render_section("Master Control", "═") +
            f"  [S] Synesthesia     {syn}\n"
            f"  [M] ProjMilkSyphon  {pms}\n"
            f"  [P] Processing Apps {proc} running\n"
            f"  [K] Karaoke Engine  {kar}\n\n"
            "[dim]Press letter key to toggle app[/dim]"
        )


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
        
        if self.pipeline_data.get('image_prompt'):
            prompt = self.pipeline_data['image_prompt']
            if isinstance(prompt, dict):
                prompt = prompt.get('description', str(prompt))
            lines.append(f"\n[bold cyan]Image Prompt:[/]\n[cyan]{truncate(str(prompt), 200)}[/]")
            has_content = True
        
        if self.pipeline_data.get('current_lyric'):
            lyric = self.pipeline_data['current_lyric']
            lines.append(f"\n[bold white]♪ {lyric.get('text', '')}[/]")
            if lyric.get('keywords'):
                lines.append(f"[yellow]  Keywords: {lyric['keywords']}[/]")
            if lyric.get('is_refrain'):
                lines.append("[magenta]  [REFRAIN][/]")
            has_content = True

        if self.pipeline_data.get('error'):
            retry = self.pipeline_data.get('backoff', 0.0)
            extra = f" (retry in {retry:.1f}s)" if retry else ""
            lines.append(f"[yellow]Playback warning: {self.pipeline_data['error']}{extra}[/]")
            has_content = True
        
        if not has_content:
            lines.append("[dim]No active processing...[/]")
        
        self.update("\n".join(lines))


class ServicesPanel(ReactivePanel):
    """External services status."""
    services = reactive({})

    def on_mount(self) -> None:
        """Initialize content when mounted."""
        self._safe_render()

    def watch_services(self, s: dict) -> None:
        self._safe_render()

    def _safe_render(self) -> None:
        """Render only if mounted."""
        if not self.is_mounted:
            return
        def svc(ok, name, detail): 
            return f"[green]✓ {name:14s} {detail}[/]" if ok else f"[dim]○ {name:14s} {detail}[/]"
        
        s = self.services
        lines = [self.render_section("Services", "═")]

        # VJ Bus worker mode indicator (always shown)
        workers = s.get('vj_bus_workers', [])
        connected = s.get('vj_bus_connected', False)

        if connected and workers:
            lines.append(f"[green]✓ VJ Bus Mode   {len(workers)} workers connected[/]")
            for worker in workers:
                lines.append(f"    [cyan]•[/] {worker}")
        else:
            lines.append(f"[yellow]⚠ VJ Bus Mode   Waiting for workers...[/]")
            lines.append(f"    [dim]Run: python dev/start_all_workers.py[/]")

        lines.append("")  # Spacing

        lines.append(svc(s.get('spotify'), "Spotify API", "Credentials configured" if s.get('spotify') else "Set SPOTIPY_CLIENT_ID/SECRET"))
        lines.append(svc(s.get('virtualdj'), "VirtualDJ", s.get('vdj_file', 'found') if s.get('virtualdj') else "Folder not found"))
        lines.append(svc(s.get('ollama'), "Ollama LLM", ', '.join(s.get('ollama_models', [])) or "Not running"))
        lines.append(svc(s.get('comfyui'), "ComfyUI", "http://127.0.0.1:8188" if s.get('comfyui') else "Not running"))
        lines.append(svc(s.get('openai'), "OpenAI API", "Key configured" if s.get('openai') else "OPENAI_API_KEY not set"))
        lines.append(svc(s.get('synesthesia'), "Synesthesia", "Running" if s.get('synesthesia') else "Installed" if s.get('synesthesia_installed') else "Not installed"))

        monitors = s.get('playback_monitors') or {}
        if monitors:
            lines.append("\n[bold]Playback Sources[/bold]")
            for name, status in monitors.items():
                ok = status.get('available', False)
                detail = "OK" if ok else status.get('error', 'Unavailable')
                color = "green" if ok else "yellow"
                mark = "✓" if ok else "△"
                lines.append(f"  [{color}]{mark}[/] {name.title()}: {detail}")
        if s.get('playback_error'):
            retry = s.get('playback_backoff', 0.0)
            extra = f" (retry in {retry:.1f}s)" if retry else ""
            lines.append(f"[yellow]Playback warning: {s['playback_error']}{extra}[/]")
        self.update("\n".join(lines))


class AppsListPanel(ReactivePanel):
    """Processing apps list."""
    apps = reactive([])
    selected = reactive(0)

    def on_mount(self) -> None:
        """Initialize content when mounted."""
        self._safe_render()

    def watch_apps(self, _: list) -> None:
        self._safe_render()
    
    def watch_selected(self, _: int) -> None:
        self._safe_render()

    def _safe_render(self) -> None:
        """Render only if mounted."""
        if not self.is_mounted:
            return
        lines = [self.render_section("Processing Apps", "═")]
        
        if not self.apps:
            lines.append("[dim](no apps found)[/dim]")
        else:
            for i, app in enumerate(self.apps):
                is_sel = i == self.selected
                is_run = hasattr(app, 'process') and app.process and app.process.poll() is None
                prefix = " ▸ " if is_sel else "   "
                status = " [green][running][/]" if is_run else ""
                name = getattr(app, 'name', 'Unknown')
                line = f"{prefix}{name}{status}"
                lines.append(f"[black on cyan]{line}[/]" if is_sel else line)
        
        self.update("\n".join(lines))


class AudioAnalysisPanel(ReactivePanel):
    """Live audio analysis visualization."""
    features = reactive({})
    GUIDE_NOTES = {
        'sub_bass': "Rumble / shake",
        'bass': "Main pulse",
        'low_mid': "Body / warmth",
        'mid': "Vocals / melody",
        'high_mid': "Clarity",
        'presence': "Definition",
        'air': "Sparkle",
    }

    def on_mount(self) -> None:
        """Initialize content when mounted."""
        self._safe_render()

    def watch_features(self, data: dict) -> None:
        self._safe_render()

    def _format_pulse(self, label: str, address: str, value: float, threshold: float, color: str) -> str:
        bar = format_bar(value, 12)
        hot = value >= threshold
        marker = f"[{color}]⚡[/]" if hot else "[dim]·[/]"
        return f"  {marker} {label:8s} {bar} {value:.2f}  ({address})"

    def _safe_render(self) -> None:
        """Render only if mounted."""
        if not self.is_mounted:
            return
        
        lines = [self.render_section("Audio Analysis", "═")]
        
        if not self.features:
            lines.append("[dim](audio analyzer not running)[/dim]")
        else:
            bands = self.features.get('bands', {})
            bass_val = self.features.get('bass_level', 0.0)
            mid_val = self.features.get('mid_level', 0.0)
            high_val = self.features.get('high_level', 0.0)
            lines.append("[bold]Guide Pulse Stack[/]")
            lines.append(self._format_pulse("Bass", "/audio/levels[1]", bass_val, 0.55, "red"))
            lines.append(self._format_pulse("Mids", "/audio/levels[3]", mid_val, 0.45, "cyan"))
            lines.append(self._format_pulse("Highs", "/audio/levels[6]", high_val, 0.40, "magenta"))

            overall = self.features.get('overall', 0.0)
            lines.append(f"\n[bold cyan]Overall Energy[/] /audio/levels[7]  {format_bar(overall, 20)} {overall:.2f}")

            beat = self.features.get('beat', 0)
            beat_str = "[green]● synced[/]" if beat else "[dim]○ idle[/]"
            bpm = self.features.get('bpm', 0.0)
            bpm_conf = self.features.get('bpm_confidence', 0.0)
            pitch_hz = self.features.get('pitch_hz', 0.0)
            pitch_conf = self.features.get('pitch_conf', 0.0)
            lines.append("\n[bold]Core Triggers[/]")
            lines.append(f"  {beat_str}  /audio/beat[0]   BPM {bpm:.1f} (conf {bpm_conf:.2f})")
            lines.append(f"  Pitch {pitch_hz:.1f} Hz (conf {pitch_conf:.2f})  /audio/pitch")

            buildup = self.features.get('buildup', False)
            drop = self.features.get('drop', False)
            energy_trend = self.features.get('energy_trend', 0.0)
            brightness = self.features.get('brightness', 0.0)
            lines.append("\n[bold]Structure Signals[/]")
            build_label = "[yellow]↗ BUILD-UP[/]" if buildup else "[dim]↗ build-up[/]"
            drop_label = "[red]↓ DROP[/]" if drop else "[dim]↓ drop[/]"
            lines.append(f"  {build_label}  /audio/structure[0]  energy {energy_trend:+.2f}")
            lines.append(f"  {drop_label}  /audio/structure[1]  brightness {brightness:.2f}")

            if bands:
                lines.append("\n[bold]Frequency Layers (OSC Guide)[/]")
                for name, value in bands.items():
                    bar = format_bar(value, 18)
                    note = self.GUIDE_NOTES.get(name, "")
                    note_str = f"  {note}" if note else ""
                    lines.append(f"  {name:10s} {bar} {value:.2f}{note_str}")
        
        self.update("\n".join(lines))


class AudioDevicePanel(ReactivePanel):
    """Audio device selection and status."""
    device_info = reactive({})
    
    def on_mount(self) -> None:
        """Initialize content when mounted."""
        self._safe_render()
    
    def watch_device_info(self, data: dict) -> None:
        self._safe_render()
    
    def _safe_render(self) -> None:
        """Render only if mounted."""
        if not self.is_mounted:
            return
        
        lines = [self.render_section("Audio Device", "═")]
        
        if not self.device_info:
            lines.append("[dim](audio analyzer not available)[/dim]")
        else:
            current = self.device_info.get('current_device', 'Unknown')
            available = self.device_info.get('available_devices', [])
            
            lines.append(f"[bold cyan]Current Device:[/] {current}")
            lines.append(f"[bold]Available Devices:[/]")
            
            for dev in available[:10]:  # Show first 10
                name = dev.get('name', 'Unknown')
                idx = dev.get('index', -1)
                lines.append(f"  [{idx}] {name}")
            
            if len(available) > 10:
                lines.append(f"  [dim]... and {len(available) - 10} more[/]")
        
        self.update("\n".join(lines))


class AudioStatsPanel(ReactivePanel):
    """OSC statistics for audio analyzer."""
    stats = reactive({})
    
    def on_mount(self) -> None:
        """Initialize content when mounted."""
        self._safe_render()
    
    def watch_stats(self, data: dict) -> None:
        self._safe_render()
    
    def _safe_render(self) -> None:
        """Render only if mounted."""
        if not self.is_mounted:
            return
        
        lines = [self.render_section("OSC Statistics", "═")]
        
        if not self.stats:
            lines.append("[dim](no statistics available)[/dim]")
        else:
            # Analyzer stats
            running = self.stats.get('running', False)
            audio_alive = self.stats.get('audio_alive', False)
            fps = self.stats.get('fps', 0.0)
            frames = self.stats.get('frames_processed', 0)
            
            status = "[green]● RUNNING[/]" if running else "[dim]○ STOPPED[/]"
            audio_status = "[green]✓[/]" if audio_alive else "[red]✗[/]"
            
            lines.append(f"[bold]Analyzer:[/] {status}")
            lines.append(f"[bold]Audio Input:[/] {audio_status}")
            lines.append(f"[bold]Processing:[/] {fps:.1f} fps ({frames} frames)")
            
            # OSC message counts
            osc_counts = self.stats.get('osc_counts', {})
            if osc_counts:
                lines.append("\n[bold]OSC Messages Sent:[/]")
                for address, count in sorted(osc_counts.items()):
                    lines.append(f"  {address:20s} {count:6d}")
        
        self.update("\n".join(lines))


class AudioBenchmarkPanel(ReactivePanel):
    """Audio latency benchmark results."""
    benchmark = reactive({})
    
    def on_mount(self) -> None:
        """Initialize content when mounted."""
        self._safe_render()
    
    def watch_benchmark(self, data: dict) -> None:
        self._safe_render()
    
    def _safe_render(self) -> None:
        """Render only if mounted."""
        if not self.is_mounted:
            return
        
        lines = [self.render_section("Latency Benchmark", "═")]
        
        if not self.benchmark:
            lines.append("[dim]Press [B] to run 10-second benchmark test[/dim]")
        else:
            # Overall stats
            lines.append(f"[bold cyan]Test Duration:[/] {self.benchmark.get('duration_sec', 0):.1f}s")
            lines.append(f"[bold cyan]Frames Processed:[/] {self.benchmark.get('total_frames', 0)}")
            lines.append(f"[bold cyan]Average FPS:[/] [green]{self.benchmark.get('avg_fps', 0):.1f}[/]\n")
            
            # Latency percentiles
            lines.append("[bold]Latency Percentiles (ms)[/]")
            lines.append(f"  Min:     {self.benchmark.get('min_latency_ms', 0):.2f}")
            lines.append(f"  Average: {self.benchmark.get('avg_latency_ms', 0):.2f}")
            lines.append(f"  P95:     {self.benchmark.get('p95_latency_ms', 0):.2f}")
            lines.append(f"  P99:     {self.benchmark.get('p99_latency_ms', 0):.2f}")
            lines.append(f"  Max:     {self.benchmark.get('max_latency_ms', 0):.2f}\n")
            
            # Component timing breakdown
            lines.append("[bold]Component Timing (µs)[/]")
            lines.append(f"  FFT:            {self.benchmark.get('fft_time_us', 0):.1f}")
            lines.append(f"  Band Extract:   {self.benchmark.get('band_extraction_time_us', 0):.1f}")
            lines.append(f"  Essentia:       {self.benchmark.get('essentia_time_us', 0):.1f}")
            lines.append(f"  OSC Send:       {self.benchmark.get('osc_send_time_us', 0):.1f}")
            lines.append(f"  [bold]Total:          {self.benchmark.get('total_processing_time_us', 0):.1f}[/]\n")
            
            # Queue stats
            lines.append("[bold]Queue Metrics[/]")
            lines.append(f"  Max Size: {self.benchmark.get('max_queue_size', 0)}")
            lines.append(f"  Drops:    {self.benchmark.get('queue_drops', 0)}")
            
            # Interpretation
            avg_lat = self.benchmark.get('avg_latency_ms', 0)
            if avg_lat < 15:
                lines.append("\n[green]✓ Excellent latency (<15ms)[/]")
            elif avg_lat < 30:
                lines.append("\n[yellow]△ Good latency (15-30ms)[/]")
            else:
                lines.append("\n[red]✗ High latency (>30ms)[/]")
        
        self.update("\n".join(lines))


class AudioFeaturePanel(ReactivePanel):
    """Display and control audio analyzer feature toggles."""
    feature_data = reactive({})

    def on_mount(self) -> None:
        self._safe_render()

    def watch_feature_data(self, data: dict) -> None:
        self._safe_render()

    def _safe_render(self) -> None:
        if not self.is_mounted:
            return
        lines = [self.render_section("Audio Feature Toggles", "═")]
        flags = self.feature_data.get('flags') or []
        if not flags:
            lines.append("[dim](feature flags unavailable)[/dim]")
        else:
            lines.append("[bold]Press listed keys to toggle (auto restarts analyzer)[/bold]\n")
            for entry in flags:
                key = entry.get('key', '?')
                label = entry.get('label', entry.get('name', ''))
                enabled = entry.get('enabled', False)
                state = "ON" if enabled else "off"
                color = "green" if enabled else "dim"
                lines.append(f"  [{key.upper()}] {label:22s} [{color}]{state}[/]")
            running = self.feature_data.get('running', False)
            if running:
                lines.append("\n[dim]Analyzer restarts automatically after changes[/dim]")
            else:
                lines.append("\n[dim]Analyzer stopped - toggles apply on next start[/dim]")
        self.update("\n".join(lines))


# ============================================================================
# MAIN APPLICATION
# ============================================================================

class VJConsoleApp(App):
    """Multi-screen VJ Console application."""

    CSS = """
    Screen { background: $surface; }
    TabbedContent { height: 1fr; }
    TabPane { padding: 1; }
    .panel { padding: 1; border: solid $primary; height: auto; }
    .full-height { height: 1fr; overflow-y: auto; }
    #left-col { width: 40%; }
    #right-col { width: 60%; }
    """

    BINDINGS = [
        Binding("q", "quit", "Quit"),
        Binding("1", "screen_master", "Master"),
        Binding("2", "screen_osc", "OSC"),
        Binding("3", "screen_ai", "AI Debug"),
        Binding("4", "screen_logs", "Logs"),
        Binding("5", "screen_audio", "Audio"),
        Binding("s", "toggle_synesthesia", "Synesthesia"),
        Binding("m", "toggle_milksyphon", "MilkSyphon"),
        Binding("a", "toggle_audio_analyzer", "Audio Analyzer"),
        Binding("b", "run_audio_benchmark", "Benchmark"),
        Binding("e", "toggle_audio_essentia", "Essentia DSP"),
        Binding("p", "toggle_audio_pitch", "Pitch"),
        Binding("o", "toggle_audio_bpm", "Beat/BPM"),
        Binding("t", "toggle_audio_structure", "Structure"),
        Binding("y", "toggle_audio_spectrum", "Spectrum"),
        Binding("l", "toggle_audio_logging", "Analyzer Log"),
        Binding("k,up", "nav_up", "Up"),
        Binding("j,down", "nav_down", "Down"),
        Binding("enter", "select_app", "Select"),
        Binding("plus,equals", "timing_up", "+Timing"),
        Binding("minus", "timing_down", "-Timing"),
    ]

    current_tab = reactive("master")
    synesthesia_running = reactive(False)
    milksyphon_running = reactive(False)

    def __init__(self):
        super().__init__()
        self.process_manager = ProcessManager()
        self.process_manager.discover_apps(self._find_project_root())
        self._logs: List[str] = []
        self._last_master_status: Optional[Dict[str, Any]] = None

        # VJ Bus client - Pure worker architecture
        self.vj_bus_client: VJBusClient = VJBusClient()
        self.workers_connected = False
        self._worker_telemetry = {
            'virtualdj_state': None,
            'spotify_state': None,
            'lyrics_data': None,
            'categories_data': None,
            'audio_features': None,
        }
        self._discovered_workers = []
        
        # Audio analyzer (always send OSC when active)
        self.audio_analyzer: Optional['AudioAnalyzer'] = None
        self.audio_watchdog: Optional['AudioAnalyzerWatchdog'] = None
        self.audio_device_manager: Optional['DeviceManager'] = None
        self.audio_running = False
        self.audio_osc_counts: Dict[str, int] = {}  # Track OSC message counts
        if AUDIO_ANALYZER_AVAILABLE:
            defaults = AudioConfig()
            self.audio_feature_flags = {
                'enable_essentia': defaults.enable_essentia,
                'enable_pitch': defaults.enable_pitch,
                'enable_bpm': defaults.enable_bpm,
                'enable_structure': defaults.enable_structure,
                'enable_spectrum': defaults.enable_spectrum,
                'enable_logging': defaults.enable_logging,
                'log_level': defaults.log_level,
            }
            self.audio_feature_labels = {
                'enable_essentia': "Essentia DSP",
                'enable_pitch': "Pitch Detection",
                'enable_bpm': "Beat/BPM",
                'enable_structure': "Structure Detector",
                'enable_spectrum': "Spectrum OSC",
                'enable_logging': "Analyzer Logging",
            }
            self.audio_feature_bindings = {
                'enable_essentia': 'E',
                'enable_pitch': 'P',
                'enable_bpm': 'O',
                'enable_structure': 'T',
                'enable_spectrum': 'Y',
                'enable_logging': 'L',
            }
        else:
            self.audio_feature_flags = {}
            self.audio_feature_labels = {}
            self.audio_feature_bindings = {}
        self._audio_osc_callback = None
        
        # Track current screen for conditional updates
        self._current_screen = "master"
        
        self._setup_log_capture()

    def _find_project_root(self) -> Path:
        for p in [Path(__file__).parent.parent, Path.cwd()]:
            if (p / "processing-vj").exists():
                return p
        return Path.cwd()
    
    def _setup_log_capture(self) -> None:
        """Setup logging handler to capture logs to _logs list."""
        class ListHandler(logging.Handler):
            def __init__(self, log_list: List[str]):
                super().__init__()
                self.log_list = log_list
                self.setFormatter(logging.Formatter('%(asctime)s - %(name)s - %(levelname)s - %(message)s'))
            
            def emit(self, record):
                try:
                    msg = self.format(record)
                    self.log_list.append(msg)
                    # Keep only last 500 lines
                    if len(self.log_list) > 500:
                        self.log_list.pop(0)
                except Exception:
                    pass
        
        # Add handler to root logger to capture all logs
        handler = ListHandler(self._logs)
        logging.getLogger().addHandler(handler)

    def compose(self) -> ComposeResult:
        yield Header(show_clock=True)
        
        with TabbedContent(id="screens"):
            # Tab 1: Master Control
            with TabPane("1️⃣ Master Control", id="master"):
                with Horizontal():
                    with VerticalScroll(id="left-col"):
                        yield MasterControlPanel(id="master-ctrl", classes="panel")
                        yield AppsListPanel(id="apps", classes="panel")
                        yield ServicesPanel(id="services", classes="panel")
                    with VerticalScroll(id="right-col"):
                        yield NowPlayingPanel(id="now-playing", classes="panel")
                        yield CategoriesPanel(id="categories", classes="panel")
                        yield PipelinePanel(id="pipeline", classes="panel")
                        yield OSCPanel(id="osc-mini", classes="panel")

            # Tab 2: OSC View
            with TabPane("2️⃣ OSC View", id="osc"):
                yield OSCPanel(id="osc-full", classes="panel full-height")

            # Tab 3: Song AI Debug  
            with TabPane("3️⃣ Song AI Debug", id="ai"):
                with Horizontal():
                    with VerticalScroll(id="left-col"):
                        yield CategoriesPanel(id="categories-full", classes="panel full-height")
                    with VerticalScroll(id="right-col"):
                        yield PipelinePanel(id="pipeline-full", classes="panel full-height")

            # Tab 4: All Logs
            with TabPane("4️⃣ All Logs", id="logs"):
                yield LogsPanel(id="logs-panel", classes="panel full-height")

            # Tab 5: Audio Analysis
            if AUDIO_ANALYZER_AVAILABLE:
                with TabPane("5️⃣ Audio Analysis", id="audio"):
                    with Horizontal():
                        with VerticalScroll(id="left-col"):
                            yield AudioAnalysisPanel(id="audio-analysis", classes="panel")
                            yield AudioDevicePanel(id="audio-device", classes="panel")
                            yield AudioFeaturePanel(id="audio-features", classes="panel")
                            yield AudioBenchmarkPanel(id="audio-benchmark", classes="panel")
                        with VerticalScroll(id="right-col"):
                            yield AudioStatsPanel(id="audio-stats", classes="panel full-height")

        yield Footer()

    def on_mount(self) -> None:
        self.title = "🎛 VJ Console - VJ Bus Mode"
        self.sub_title = "Press 1-5 to switch screens" if AUDIO_ANALYZER_AVAILABLE else "Press 1-4 to switch screens"

        # Initialize
        self.query_one("#apps", AppsListPanel).apps = self.process_manager.apps
        self.process_manager.start_monitoring(daemon_mode=True)

        # Connect to VJ Bus workers (required)
        self._connect_to_workers()

        # Initialize audio analyzer if available
        if AUDIO_ANALYZER_AVAILABLE:
            self._init_audio_analyzer()

        # Background updates
        self.set_interval(0.5, self._update_data)
        self.set_interval(2.0, self._check_apps)
        self.set_interval(5.0, self._reconnect_workers)  # Periodic reconnection attempt

    # === Actions (impure, side effects) ===

    def _build_audio_config(self) -> AudioConfig:
        flags = self.audio_feature_flags
        return AudioConfig(
            enable_essentia=flags.get('enable_essentia', True),
            enable_pitch=flags.get('enable_pitch', True),
            enable_bpm=flags.get('enable_bpm', True),
            enable_structure=flags.get('enable_structure', True),
            enable_spectrum=flags.get('enable_spectrum', True),
            enable_logging=flags.get('enable_logging', True),
            log_level=flags.get('log_level', logging.INFO),
        )

    def _update_audio_feature_panel(self) -> None:
        if not AUDIO_ANALYZER_AVAILABLE:
            return
        try:
            panel = self.query_one("#audio-features", AudioFeaturePanel)
        except Exception:
            return
        rows = []
        for key, label in self.audio_feature_labels.items():
            rows.append({
                'name': key,
                'label': label,
                'key': self.audio_feature_bindings.get(key, '?'),
                'enabled': self.audio_feature_flags.get(key, False),
            })
        panel.feature_data = {
            'flags': rows,
            'running': self.audio_running,
        }

    def _recreate_audio_analyzer(self) -> None:
        if not AUDIO_ANALYZER_AVAILABLE:
            self._update_audio_feature_panel()
            return
        was_running = self.audio_running and self.audio_analyzer is not None
        if self.audio_analyzer:
            try:
                self.audio_analyzer.stop()
            except Exception as exc:
                logger.exception(f"Error stopping audio analyzer during reconfigure: {exc}")
            finally:
                self.audio_running = False
        self.audio_analyzer = None
        self.audio_watchdog = None
        self._init_audio_analyzer()
        if was_running:
            self._start_audio_analyzer()
        self._update_audio_feature_panel()

    def _toggle_audio_feature(self, key: str) -> None:
        if not AUDIO_ANALYZER_AVAILABLE or key not in self.audio_feature_flags:
            logger.warning("Audio feature toggle unavailable: %s", key)
            return
        self.audio_feature_flags[key] = not self.audio_feature_flags[key]
        state = "enabled" if self.audio_feature_flags[key] else "disabled"
        logger.info("Audio feature %s %s", key, state)
        self._recreate_audio_analyzer()
    
    def _init_audio_analyzer(self) -> None:
        """Initialize audio analyzer (called on mount)."""
        try:
            from osc_manager import osc
            
            self.audio_device_manager = DeviceManager()
            audio_config = self._build_audio_config()
            
            # OSC callback that always sends (not conditional on screen)
            def audio_osc_callback(address: str, args: List):
                """Send OSC and track statistics."""
                osc.send(address, args)
                # Track counts for statistics display
                self.audio_osc_counts[address] = self.audio_osc_counts.get(address, 0) + 1
            
            self.audio_analyzer = AudioAnalyzer(
                config=audio_config,
                device_manager=self.audio_device_manager,
                osc_callback=audio_osc_callback
            )
            
            self.audio_watchdog = AudioAnalyzerWatchdog(self.audio_analyzer)
            
            logger.info("Audio analyzer initialized")
            self._update_audio_feature_panel()
            
        except Exception as e:
            logger.exception(f"Audio analyzer initialization failed: {e}")
    
    def _start_audio_analyzer(self) -> None:
        """Start the audio analyzer."""
        if not AUDIO_ANALYZER_AVAILABLE or not self.audio_analyzer:
            logger.warning("Audio analyzer not available")
            return
        
        try:
            if not self.audio_running:
                self.audio_analyzer.start()
                self.audio_running = True
                logger.info("Audio analyzer started")
                self._update_audio_feature_panel()
        except Exception as e:
            logger.exception(f"Failed to start audio analyzer: {e}")
    
    def _stop_audio_analyzer(self) -> None:
        """Stop the audio analyzer."""
        if self.audio_analyzer and self.audio_running:
            try:
                self.audio_analyzer.stop()
                self.audio_running = False
                logger.info("Audio analyzer stopped")
                self._update_audio_feature_panel()
            except Exception as e:
                logger.exception(f"Failed to stop audio analyzer: {e}")
    
    def _update_audio_panels(self) -> None:
        """Update audio analysis panels (only when screen is active)."""
        if not AUDIO_ANALYZER_AVAILABLE or not self.audio_analyzer:
            return
        
        try:
            # Get current stats
            stats = self.audio_analyzer.get_stats()

            if self.audio_running and not stats.get('running', False):
                logger.warning("Audio analyzer thread stopped unexpectedly; rebuilding analyzer")
                self._recreate_audio_analyzer()
                return
            
            # Update watchdog only when analyzer should be running
            if self.audio_watchdog and self.audio_running:
                self.audio_watchdog.update()
            
            # Extract current features from analyzer state
            latest = self.audio_analyzer.latest_features
            def _avg_band(indices: List[int]) -> float:
                values = [self.audio_analyzer.smoothed_bands[i] for i in indices if i < len(self.audio_analyzer.smoothed_bands)]
                return sum(values) / len(values) if values else 0.0

            features = {
                'bands': {
                    name: self.audio_analyzer.smoothed_bands[i]
                    for i, name in enumerate(self.audio_analyzer.config.band_names)
                },
                'overall': self.audio_analyzer.smoothed_rms,
                'beat': latest.get('beat', 0),
                'bpm': latest.get('bpm', 0.0),
                'bpm_confidence': latest.get('bpm_confidence', 0.0),
                'buildup': latest.get('buildup', False),
                'drop': latest.get('drop', False),
                'bass_level': latest.get('bass_level', self.audio_analyzer.smoothed_bands[1] if len(self.audio_analyzer.smoothed_bands) > 1 else self.audio_analyzer.smoothed_rms),
                'mid_level': latest.get('mid_level', _avg_band([2, 3, 4])),
                'high_level': latest.get('high_level', _avg_band([5, 6])),
                'energy_trend': latest.get('energy_trend', 0.0),
                'brightness': latest.get('brightness', 0.0),
                'pitch_hz': latest.get('pitch_hz', 0.0),
                'pitch_conf': latest.get('pitch_conf', 0.0),
            }
            
            # Update panels
            try:
                self.query_one("#audio-analysis", AudioAnalysisPanel).features = features
            except Exception:
                pass
            
            # Device info
            device_info = {
                'current_device': stats.get('device_name', 'Unknown'),
                'available_devices': self.audio_device_manager.list_devices() if self.audio_device_manager else [],
            }
            
            try:
                self.query_one("#audio-device", AudioDevicePanel).device_info = device_info
            except Exception:
                pass
            
            # Statistics (including OSC counts)
            stats_data = {
                **stats,
                'osc_counts': self.audio_osc_counts.copy(),
            }
            
            try:
                self.query_one("#audio-stats", AudioStatsPanel).stats = stats_data
            except Exception:
                pass
                
        except Exception as e:
            logger.error(f"Error updating audio panels: {e}")
    
    def _connect_to_workers(self) -> None:
        """Connect to VJ Bus workers (required for operation)."""
        try:
            # Discover workers
            self._discovered_workers = self.vj_bus_client.discover_workers()

            if not self._discovered_workers:
                logger.warning("⚠️  No VJ Bus workers found - waiting for workers to start")
                logger.warning("   Start workers with: python dev/start_all_workers.py")
                self.workers_connected = False
                return

            logger.info(f"✓ Discovered {len(self._discovered_workers)} workers:")
            for worker in self._discovered_workers:
                logger.info(f"  - {worker.name}")

            # Subscribe to telemetry
            self.vj_bus_client.subscribe("virtualdj.state", self._on_virtualdj_telemetry)
            self.vj_bus_client.subscribe("spotify.state", self._on_spotify_telemetry)
            self.vj_bus_client.subscribe("lyrics.fetched", self._on_lyrics_telemetry)
            self.vj_bus_client.subscribe("lyrics.analyzed", self._on_lyrics_analyzed)
            self.vj_bus_client.subscribe("song.categorized", self._on_song_categorized)
            self.vj_bus_client.subscribe("audio.features", self._on_audio_features_telemetry)

            # Start telemetry receiver
            self.vj_bus_client.start()

            self.workers_connected = True
            logger.info("✓ VJ Bus client started")

        except Exception as e:
            logger.error(f"Failed to connect to VJ Bus workers: {e}")
            self.workers_connected = False

    def _reconnect_workers(self) -> None:
        """Periodically attempt to reconnect to workers if disconnected."""
        if not self.workers_connected:
            logger.debug("Attempting to reconnect to workers...")
            self._connect_to_workers()

    # === VJ Bus telemetry callbacks ===

    def _on_virtualdj_telemetry(self, msg):
        """Handle VirtualDJ state telemetry."""
        self._worker_telemetry['virtualdj_state'] = msg.payload

    def _on_spotify_telemetry(self, msg):
        """Handle Spotify state telemetry."""
        self._worker_telemetry['spotify_state'] = msg.payload

    def _on_lyrics_telemetry(self, msg):
        """Handle lyrics fetched telemetry."""
        data = msg.payload
        self._worker_telemetry['lyrics_data'] = {
            'artist': data.get('artist'),
            'title': data.get('title'),
            'lrc_text': data.get('lrc_text'),
            'line_count': data.get('line_count'),
            'has_lyrics': data.get('has_lyrics', False),
        }

    def _on_lyrics_analyzed(self, msg):
        """Handle lyrics analysis telemetry."""
        data = msg.payload
        if self._worker_telemetry['lyrics_data']:
            self._worker_telemetry['lyrics_data'].update({
                'keywords': data.get('keywords', []),
                'themes': data.get('themes', []),
                'refrain_lines': data.get('refrain_lines', []),
            })

    def _on_song_categorized(self, msg):
        """Handle song categorization telemetry."""
        data = msg.payload
        self._worker_telemetry['categories_data'] = {
            'categories': data.get('categories', {}),
            'primary_mood': data.get('primary_mood', ''),
        }

    def _on_audio_features_telemetry(self, msg):
        """Handle audio features telemetry from worker."""
        self._worker_telemetry['audio_features'] = msg.payload

    def _run_process(self, cmd: List[str], timeout: int = 2) -> bool:
        """Run a subprocess, return True if successful."""
        try:
            result = subprocess.run(cmd, capture_output=True, timeout=timeout)
            return result.returncode == 0
        except Exception:
            return False

    def _check_apps(self) -> None:
        """Check running status of external apps."""
        self.synesthesia_running = self._run_process(['pgrep', '-x', 'Synesthesia'], 1)
        self.milksyphon_running = self._run_process(['pgrep', '-f', 'projectMilkSyphon'], 1)
        self._update_services()

    def _update_services(self) -> None:
        """Update services panel with current status."""
        import os
        ollama_ok, ollama_models, comfyui_ok = False, [], False
        
        try:
            import requests
            # Single request to Ollama - reuse response
            ollama_resp = requests.get("http://localhost:11434/api/tags", timeout=1)
            if ollama_resp.status_code == 200:
                ollama_ok = True
                ollama_models = ollama_resp.json().get('models', [])
            
            comfyui_ok = requests.get("http://127.0.0.1:8188/system_stats", timeout=1).status_code == 200
        except Exception:
            pass

        vdj_path = KaraokeConfig.find_vdj_path()
        
        try:
            services_data = {
                'spotify': KaraokeConfig.has_spotify_credentials(),
                'virtualdj': bool(vdj_path),
                'vdj_file': vdj_path.name if vdj_path else '',
                'ollama': ollama_ok,
                'ollama_models': [m.get('name', '').split(':')[0] for m in ollama_models[:3]],
                'comfyui': comfyui_ok,
                'openai': bool(os.environ.get('OPENAI_API_KEY')),
                'synesthesia': self.synesthesia_running,
                'synesthesia_installed': Path('/Applications/Synesthesia.app').exists(),
                # VJ Bus worker information
                'vj_bus_mode': True,  # Always in VJ Bus mode
                'vj_bus_connected': self.workers_connected,
                'vj_bus_workers': [w.name for w in self._discovered_workers],
            }

            self.query_one("#services", ServicesPanel).services = services_data
        except Exception:
            pass

    def _update_data_from_workers(self) -> None:
        """Update panels using worker telemetry data."""
        screen = self._current_screen

        if screen == "master":
            # Build track data from worker telemetry
            vdj_state = self._worker_telemetry.get('virtualdj_state')
            spotify_state = self._worker_telemetry.get('spotify_state')

            # Use whichever source has data
            source_state = vdj_state or spotify_state
            if source_state:
                track = source_state.get('track', {})
                track_data = {
                    'artist': track.get('artist', 'Unknown'),
                    'title': track.get('title', 'Unknown'),
                    'duration': track.get('duration', 0),
                    'position': source_state.get('position', 0),
                    'source': 'VirtualDJ' if vdj_state else 'Spotify',
                    'connected': True,
                    'error': '',
                    'backoff': 0,
                }

                try:
                    self.query_one("#now-playing", NowPlayingPanel).track_data = track_data
                except Exception:
                    pass

            # Categories from worker
            cat_data = self._worker_telemetry.get('categories_data', {})
            if cat_data:
                try:
                    self.query_one("#categories", CategoriesPanel).categories_data = cat_data
                except Exception:
                    pass

            # Show worker status
            running_apps = sum(1 for app in self.process_manager.apps if self.process_manager.is_running(app))
            try:
                self.query_one("#master-ctrl", MasterControlPanel).status = {
                    'synesthesia': self.synesthesia_running,
                    'milksyphon': self.milksyphon_running,
                    'processing_apps': running_apps,
                    'karaoke': True,  # Workers are running
                }
            except Exception:
                pass

        elif screen == "logs":
            try:
                self.query_one("#logs-panel", LogsPanel).logs = self._logs.copy()
            except Exception:
                pass

        elif screen == "audio" and AUDIO_ANALYZER_AVAILABLE:
            # Audio panels still updated from direct analyzer
            self._update_audio_panels()

    def _update_data(self) -> None:
        """Update all panels with current data from worker telemetry."""
        # Pure worker mode - all data from telemetry
        self._update_data_from_workers()

    # === Screen switching ===
    
    def _switch_screen(self, screen_name: str):
        """Switch screen and manage OSC logging (performance optimization)."""
        from osc_manager import osc
        
        # Disable OSC logging when leaving OSC screen
        if self._current_screen == "osc" and screen_name != "osc":
            osc.disable_logging()
        
        # Enable OSC logging when entering OSC screen
        if screen_name == "osc" and self._current_screen != "osc":
            osc.enable_logging()
        
        self._current_screen = screen_name
        self.query_one("#screens", TabbedContent).active = screen_name
    
    def action_screen_master(self) -> None:
        self._switch_screen("master")
    
    def action_screen_osc(self) -> None:
        self._switch_screen("osc")
    
    def action_screen_ai(self) -> None:
        self._switch_screen("ai")
    
    def action_screen_logs(self) -> None:
        self._switch_screen("logs")
    
    def action_screen_audio(self) -> None:
        """Switch to audio analysis screen."""
        if AUDIO_ANALYZER_AVAILABLE:
            self._switch_screen("audio")

    # === App control ===
    
    def action_toggle_audio_analyzer(self) -> None:
        """Toggle audio analyzer on/off."""
        if not AUDIO_ANALYZER_AVAILABLE:
            logger.warning("Audio analyzer not available (missing dependencies)")
            return
        
        if self.audio_running:
            self._stop_audio_analyzer()
        else:
            self._start_audio_analyzer()
        self._update_audio_feature_panel()

    def action_toggle_audio_essentia(self) -> None:
        self._toggle_audio_feature('enable_essentia')

    def action_toggle_audio_pitch(self) -> None:
        self._toggle_audio_feature('enable_pitch')

    def action_toggle_audio_bpm(self) -> None:
        self._toggle_audio_feature('enable_bpm')

    def action_toggle_audio_structure(self) -> None:
        self._toggle_audio_feature('enable_structure')

    def action_toggle_audio_spectrum(self) -> None:
        self._toggle_audio_feature('enable_spectrum')

    def action_toggle_audio_logging(self) -> None:
        self._toggle_audio_feature('enable_logging')
    
    def action_toggle_synesthesia(self) -> None:
        if self.synesthesia_running:
            self._run_process(['pkill', '-x', 'Synesthesia'])
        else:
            subprocess.Popen(['open', '-a', 'Synesthesia'])
        self._check_apps()

    def action_toggle_milksyphon(self) -> None:
        if self.milksyphon_running:
            self._run_process(['pkill', '-f', 'projectMilkSyphon'])
        else:
            for p in [Path("/Applications/projectMilkSyphon.app"), Path.home() / "Applications/projectMilkSyphon.app"]:
                if p.exists():
                    subprocess.Popen(['open', '-a', str(p)])
                    break
        self._check_apps()

    def action_nav_up(self) -> None:
        panel = self.query_one("#apps", AppsListPanel)
        if panel.selected > 0:
            panel.selected -= 1

    def action_nav_down(self) -> None:
        panel = self.query_one("#apps", AppsListPanel)
        if panel.selected < len(self.process_manager.apps) - 1:
            panel.selected += 1

    def action_select_app(self) -> None:
        panel = self.query_one("#apps", AppsListPanel)
        if 0 <= panel.selected < len(self.process_manager.apps):
            app = self.process_manager.apps[panel.selected]
            if self.process_manager.is_running(app):
                self.process_manager.stop_app(app)
            else:
                self.process_manager.launch_app(app)

    def action_timing_up(self) -> None:
        if self.karaoke_engine:
            self.karaoke_engine.adjust_timing(+200)

    def action_timing_down(self) -> None:
        if self.karaoke_engine:
            self.karaoke_engine.adjust_timing(-200)
    
    def action_run_audio_benchmark(self) -> None:
        """Run 10-second audio latency benchmark."""
        if not AUDIO_ANALYZER_AVAILABLE or not self.audio_analyzer or not self.audio_running:
            logger.warning("Audio analyzer must be running to benchmark")
            return
        
        try:
            logger.info("Starting 10-second latency benchmark...")
            
            # Run benchmark in background thread to not block UI
            def run_benchmark():
                tester = LatencyTester(self.audio_analyzer)
                results = tester.run_benchmark(duration_sec=10.0)
                
                # Update benchmark panel
                try:
                    self.query_one("#audio-benchmark", AudioBenchmarkPanel).benchmark = results.to_dict()
                except Exception as e:
                    logger.error(f"Failed to update benchmark panel: {e}")
            
            benchmark_thread = threading.Thread(target=run_benchmark, daemon=True)
            benchmark_thread.start()
            
        except Exception as e:
            logger.exception(f"Benchmark failed: {e}")

    def on_unmount(self) -> None:
        """Cleanup when app is closing."""
        # Stop VJBusClient
        if self.vj_bus_client:
            try:
                self.vj_bus_client.stop()
                logger.info("VJ Bus client stopped")
            except Exception as e:
                logger.error(f"Error stopping VJ Bus client: {e}")

        self.process_manager.cleanup()

        # Stop audio analyzer
        if AUDIO_ANALYZER_AVAILABLE and self.audio_running:
            self._stop_audio_analyzer()


def main():
    VJConsoleApp().run()


if __name__ == '__main__':
    main()
