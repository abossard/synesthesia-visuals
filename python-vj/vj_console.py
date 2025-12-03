#!/usr/bin/env python3
"""
VJ Console - Textual Edition with Multi-Screen Support

Screens (press 0-9 to switch):
0. Overview - Key metrics from all workers and services
1. Master Control - Main dashboard with all controls
2. OSC View - Full OSC message debug view  
3. Song AI Debug - Song categorization and pipeline details
4. All Logs - Complete application logs
5. Audio Analysis - Real-time audio analysis and OSC emission
6. Spotify Worker - Spotify API monitor details
7. VirtualDJ Worker - VirtualDJ file watcher details
8. Lyrics Worker - Lyrics fetcher with LLM analysis
9. Audio Worker - Audio analyzer worker details
🔧. Process Manager - Worker supervisor status
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
from karaoke_engine import KaraokeEngine, Config as KaraokeConfig, get_active_line_index
from domain import PlaybackSnapshot, PlaybackState
from worker_coordinator import WorkerCoordinator

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
    
    # Create dummy classes for type hints when audio analyzer is not available
    class AudioConfig:
        """Dummy AudioConfig for when audio_analyzer is not available."""
        pass
    class DeviceConfig:
        """Dummy DeviceConfig for when audio_analyzer is not available."""
        pass
    class DeviceManager:
        """Dummy DeviceManager for when audio_analyzer is not available."""
        pass
    class AudioAnalyzer:
        """Dummy AudioAnalyzer for when audio_analyzer is not available."""
        pass
    class AudioAnalyzerWatchdog:
        """Dummy AudioAnalyzerWatchdog for when audio_analyzer is not available."""
        pass
    class LatencyTester:
        """Dummy LatencyTester for when audio_analyzer is not available."""
        pass

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
            f"  [W] Start All Workers\n"
            f"  [R] Restart Workers\n"
            f"  [S] Synesthesia     {syn}\n"
            f"  [M] ProjMilkSyphon  {pms}\n"
            f"  [P] Processing Apps {proc} running\n"
            f"  [K] Karaoke Engine  {kar}\n\n"
            "[dim]Press letter key to toggle/control[/dim]"
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


class WorkersPanel(ReactivePanel):
    """Multi-process workers status."""
    workers_data = reactive({})

    def on_mount(self) -> None:
        """Initialize content when mounted."""
        self._safe_render()

    def watch_workers_data(self, _: dict) -> None:
        self._safe_render()

    def _safe_render(self) -> None:
        """Render only if mounted."""
        if not self.is_mounted:
            return
        lines = [self.render_section("Workers (Multi-Process)", "═")]
        
        workers = self.workers_data.get('workers', [])
        if not workers:
            lines.append("[dim]No workers discovered yet...[/dim]")
        else:
            for worker in workers:
                name = worker.get('name', 'unknown')
                connected = worker.get('connected', False)
                state = worker.get('state', {})
                
                status_icon = "✓" if connected else "○"
                color = "green" if connected else "dim"
                
                # Show relevant state info
                info = ""
                if state.get('running'):
                    info = " [running]"
                elif state.get('status'):
                    info = f" [{state.get('status')}]"
                
                lines.append(f"  [{color}]{status_icon}[/] {name:20s}{info}")
        
        self.update("\n".join(lines))


class WorkerOverviewPanel(ReactivePanel):
    """Compact overview of all workers for overview screen."""
    workers_data = reactive({})

    def on_mount(self) -> None:
        self._safe_render()

    def watch_workers_data(self, _: dict) -> None:
        self._safe_render()

    def _safe_render(self) -> None:
        if not self.is_mounted:
            return
        lines = [self.render_section("Workers Overview", "═")]
        
        workers = self.workers_data.get('workers', [])
        if not workers:
            lines.append("[dim]No workers discovered[/dim]")
        else:
            for worker in workers:
                name = worker.get('name', 'unknown')
                connected = worker.get('connected', False)
                state = worker.get('state', {})
                
                # Format status
                if connected and state.get('running'):
                    status = "[green]● RUNNING[/]"
                elif connected:
                    status = "[yellow]● IDLE[/]"
                else:
                    status = "[dim]○ disconnected[/]"
                
                # Get key info
                info = ""
                if name == 'audio_analyzer' and state.get('fps'):
                    info = f"  {state['fps']:.1f} fps"
                elif name == 'spotify_monitor' and state.get('track'):
                    info = f"  {state['track'][:30]}"
                elif name == 'lyrics_fetcher' and state.get('lyrics_count'):
                    info = f"  {state['lyrics_count']} lyrics"
                
                lines.append(f"  {name:20s} {status}{info}")
        
        self.update("\n".join(lines))


class SpotifyWorkerPanel(ReactivePanel):
    """Detailed Spotify monitor worker status."""
    worker_data = reactive({})

    def on_mount(self) -> None:
        self._safe_render()

    def watch_worker_data(self, _: dict) -> None:
        self._safe_render()

    def _safe_render(self) -> None:
        if not self.is_mounted:
            return
        lines = [self.render_section("Spotify Monitor Worker", "═")]
        
        state = self.worker_data.get('state', {})
        connected = self.worker_data.get('connected', False)
        
        if not connected:
            lines.append("[dim]Worker not connected[/dim]")
        else:
            lines.append(f"Status: {format_status_icon(state.get('running', False), '● RUNNING', '○ stopped')}")
            lines.append(f"Poll interval: {state.get('poll_interval', 2.0)}s")
            lines.append("")
            
            # Current track
            lines.append("[bold]Current Track:[/]")
            if state.get('track'):
                lines.append(f"  Artist: {state.get('artist', 'Unknown')}")
                lines.append(f"  Title:  {state.get('track', 'Unknown')}")
                lines.append(f"  Album:  {state.get('album', 'Unknown')}")
                pos = state.get('position', 0)
                dur = state.get('duration', 0)
                lines.append(f"  Time:   {format_duration(pos, dur)}")
            else:
                lines.append("  [dim]No track playing[/dim]")
            
            lines.append("")
            lines.append(f"Last update: {state.get('last_update', 'never')}")
            lines.append(f"API calls: {state.get('api_calls', 0)}")
        
        self.update("\n".join(lines))


class VirtualDJWorkerPanel(ReactivePanel):
    """Detailed VirtualDJ monitor worker status."""
    worker_data = reactive({})

    def on_mount(self) -> None:
        self._safe_render()

    def watch_worker_data(self, _: dict) -> None:
        self._safe_render()

    def _safe_render(self) -> None:
        if not self.is_mounted:
            return
        lines = [self.render_section("VirtualDJ Monitor Worker", "═")]
        
        state = self.worker_data.get('state', {})
        connected = self.worker_data.get('connected', False)
        
        if not connected:
            lines.append("[dim]Worker not connected[/dim]")
        else:
            lines.append(f"Status: {format_status_icon(state.get('running', False), '● RUNNING', '○ stopped')}")
            lines.append(f"Watch file: {state.get('watch_file', 'not set')}")
            lines.append(f"Poll interval: {state.get('poll_interval', 1.0)}s")
            lines.append("")
            
            # Current track
            lines.append("[bold]Current Track:[/]")
            if state.get('track'):
                lines.append(f"  {state.get('track', 'Unknown')}")
                pos = state.get('position', 0)
                lines.append(f"  Position: {format_time(pos)}")
            else:
                lines.append("  [dim]No track detected[/dim]")
            
            lines.append("")
            lines.append(f"File checks: {state.get('file_checks', 0)}")
            lines.append(f"Last change: {state.get('last_change', 'never')}")
        
        self.update("\n".join(lines))


class LyricsWorkerPanel(ReactivePanel):
    """Detailed lyrics fetcher worker status."""
    worker_data = reactive({})

    def on_mount(self) -> None:
        self._safe_render()

    def watch_worker_data(self, _: dict) -> None:
        self._safe_render()

    def _safe_render(self) -> None:
        if not self.is_mounted:
            return
        lines = [self.render_section("Lyrics Fetcher Worker", "═")]
        
        state = self.worker_data.get('state', {})
        connected = self.worker_data.get('connected', False)
        
        if not connected:
            lines.append("[dim]Worker not connected[/dim]")
        else:
            lines.append(f"Status: {format_status_icon(state.get('running', False), '● RUNNING', '○ stopped')}")
            lines.append(f"LLM enabled: {format_status_icon(state.get('llm_enabled', False), '✓ Yes', '✗ No')}")
            lines.append("")
            
            # Current lyrics
            lines.append("[bold]Current Song:[/]")
            if state.get('current_artist'):
                lines.append(f"  Artist: {state.get('current_artist')}")
                lines.append(f"  Title:  {state.get('current_title')}")
                lines.append(f"  Lyrics: {state.get('lyrics_count', 0)} lines")
                
                if state.get('categories'):
                    lines.append(f"  Vibe:   {state['categories'].get('vibe', 'unknown')}")
                    lines.append(f"  Tempo:  {state['categories'].get('tempo', 'unknown')}")
            else:
                lines.append("  [dim]No lyrics loaded[/dim]")
            
            lines.append("")
            lines.append(f"Total fetches: {state.get('total_fetches', 0)}")
            lines.append(f"Cache hits: {state.get('cache_hits', 0)}")
            lines.append(f"LLM calls: {state.get('llm_calls', 0)}")
        
        self.update("\n".join(lines))


class AudioWorkerPanel(ReactivePanel):
    """Detailed audio analyzer worker status."""
    worker_data = reactive({})

    def on_mount(self) -> None:
        self._safe_render()

    def watch_worker_data(self, _: dict) -> None:
        self._safe_render()

    def _safe_render(self) -> None:
        if not self.is_mounted:
            return
        lines = [self.render_section("Audio Analyzer Worker", "═")]
        
        state = self.worker_data.get('state', {})
        connected = self.worker_data.get('connected', False)
        
        if not connected:
            lines.append("[dim]Worker not connected[/dim]")
        else:
            lines.append(f"Status: {format_status_icon(state.get('running', False), '● RUNNING', '○ stopped')}")
            lines.append(f"Device: {state.get('device', 'not set')}")
            lines.append(f"Sample rate: {state.get('sample_rate', 0)} Hz")
            lines.append("")
            
            # Performance
            lines.append("[bold]Performance:[/]")
            lines.append(f"  FPS: {state.get('fps', 0):.1f}")
            lines.append(f"  Frames: {state.get('frames_processed', 0)}")
            
            lines.append("")
            lines.append("[bold]Features Enabled:[/]")
            lines.append(f"  Essentia: {format_status_icon(state.get('enable_essentia', False), '✓', '✗')}")
            lines.append(f"  Pitch:    {format_status_icon(state.get('enable_pitch', False), '✓', '✗')}")
            lines.append(f"  BPM:      {format_status_icon(state.get('enable_bpm', False), '✓', '✗')}")
            lines.append(f"  Spectrum: {format_status_icon(state.get('enable_spectrum', False), '✓', '✗')}")
            
            # Current levels
            if state.get('levels'):
                lines.append("")
                lines.append("[bold]Current Levels:[/]")
                levels = state['levels']
                lines.append(f"  Bass: {format_bar(levels.get('bass', 0))}")
                lines.append(f"  Mid:  {format_bar(levels.get('mid', 0))}")
                lines.append(f"  High: {format_bar(levels.get('high', 0))}")
        
        self.update("\n".join(lines))


class ProcessManagerPanel(ReactivePanel):
    """Detailed process manager status."""
    worker_data = reactive({})

    def on_mount(self) -> None:
        self._safe_render()

    def watch_worker_data(self, _: dict) -> None:
        self._safe_render()

    def _safe_render(self) -> None:
        if not self.is_mounted:
            return
        lines = [self.render_section("Process Manager", "═")]
        
        state = self.worker_data.get('state', {})
        connected = self.worker_data.get('connected', False)
        
        if not connected:
            lines.append("[dim]Worker not connected[/dim]")
        else:
            lines.append(f"Status: {format_status_icon(True, '● ACTIVE', '○ inactive')}")
            lines.append("")
            
            # Managed workers
            lines.append("[bold]Managed Workers:[/]")
            managed = state.get('managed_workers', {})
            if not managed:
                lines.append("  [dim]No workers managed[/dim]")
            else:
                for name, info in managed.items():
                    alive = info.get('alive', False)
                    pid = info.get('pid', 0)
                    restarts = info.get('restart_count', 0)
                    
                    status = "[green]✓ alive[/]" if alive else "[red]✗ dead[/]"
                    restart_info = f" (restarts: {restarts})" if restarts > 0 else ""
                    
                    lines.append(f"  {name:20s} {status}  PID:{pid}{restart_info}")
            
            lines.append("")
            lines.append(f"Total restarts: {state.get('total_restarts', 0)}")
            lines.append(f"Uptime: {state.get('uptime', 'unknown')}")
        
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
        Binding("0", "screen_overview", "Overview"),
        Binding("1", "screen_master", "Master"),
        Binding("2", "screen_osc", "OSC"),
        Binding("3", "screen_ai", "AI Debug"),
        Binding("4", "screen_logs", "Logs"),
        Binding("5", "screen_audio", "Audio"),
        Binding("6", "screen_worker_spotify", "Spotify"),
        Binding("7", "screen_worker_vdj", "VDJ"),
        Binding("8", "screen_worker_lyrics", "Lyrics"),
        Binding("9", "screen_worker_audio", "Audio W"),
        Binding("s", "toggle_synesthesia", "Synesthesia"),
        Binding("m", "toggle_milksyphon", "MilkSyphon"),
        Binding("w", "start_all_workers", "Start All Workers"),
        Binding("r", "restart_all_workers", "Restart Workers"),
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
        self.karaoke_engine: Optional[KaraokeEngine] = None
        self._logs: List[str] = []
        self._last_master_status: Optional[Dict[str, Any]] = None
        self._latest_snapshot: Optional[PlaybackSnapshot] = None
        
        # Worker coordinator for multi-process architecture
        self.worker_coordinator = WorkerCoordinator()
        
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
            # Tab 0: Overview (NEW - shows all key metrics)
            with TabPane("0️⃣ Overview", id="overview"):
                with Horizontal():
                    with VerticalScroll(id="left-col"):
                        yield WorkerOverviewPanel(id="workers-overview", classes="panel")
                        yield NowPlayingPanel(id="now-playing-overview", classes="panel")
                        yield ServicesPanel(id="services-overview", classes="panel")
                    with VerticalScroll(id="right-col"):
                        yield CategoriesPanel(id="categories-overview", classes="panel")
                        yield PipelinePanel(id="pipeline-overview", classes="panel")
                        yield OSCPanel(id="osc-overview", classes="panel")
            
            # Tab 1: Master Control
            with TabPane("1️⃣ Master Control", id="master"):
                with Horizontal():
                    with VerticalScroll(id="left-col"):
                        yield MasterControlPanel(id="master-ctrl", classes="panel")
                        yield WorkersPanel(id="workers", classes="panel")
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
            
            # Tab 6-9: Worker Details (NEW)
            with TabPane("6️⃣ Spotify Worker", id="worker-spotify"):
                with Horizontal():
                    with VerticalScroll(id="left-col"):
                        yield SpotifyWorkerPanel(id="spotify-worker-detail", classes="panel full-height")
                    with VerticalScroll(id="right-col"):
                        yield NowPlayingPanel(id="now-playing-spotify", classes="panel")
            
            with TabPane("7️⃣ VirtualDJ Worker", id="worker-vdj"):
                with Horizontal():
                    with VerticalScroll(id="left-col"):
                        yield VirtualDJWorkerPanel(id="vdj-worker-detail", classes="panel full-height")
                    with VerticalScroll(id="right-col"):
                        yield NowPlayingPanel(id="now-playing-vdj", classes="panel")
            
            with TabPane("8️⃣ Lyrics Worker", id="worker-lyrics"):
                with Horizontal():
                    with VerticalScroll(id="left-col"):
                        yield LyricsWorkerPanel(id="lyrics-worker-detail", classes="panel full-height")
                    with VerticalScroll(id="right-col"):
                        yield CategoriesPanel(id="categories-lyrics", classes="panel")
            
            with TabPane("9️⃣ Audio Worker", id="worker-audio"):
                yield AudioWorkerPanel(id="audio-worker-detail", classes="panel full-height")
            
            with TabPane("🔧 Process Manager", id="worker-pm"):
                yield ProcessManagerPanel(id="pm-detail", classes="panel full-height")

        yield Footer()

    def on_mount(self) -> None:
        self.title = "🎛 VJ Console"
        self.sub_title = "Press 0-9 to switch screens" if AUDIO_ANALYZER_AVAILABLE else "Press 0-8 to switch screens"
        
        # Initialize
        self.query_one("#apps", AppsListPanel).apps = self.process_manager.apps
        self.process_manager.start_monitoring(daemon_mode=True)
        self._start_karaoke()
        
        # Start worker coordinator
        self.worker_coordinator.start()
        logger.info("Worker coordinator started")
        
        # Initialize audio analyzer if available
        if AUDIO_ANALYZER_AVAILABLE:
            self._init_audio_analyzer()
        
        # Background updates
        self.set_interval(0.5, self._update_data)
        self.set_interval(2.0, self._check_apps)

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
    
    def _start_karaoke(self) -> None:
        try:
            self.karaoke_engine = KaraokeEngine()
            self.karaoke_engine.start()
        except Exception as e:
            logger.exception(f"Karaoke start error: {e}")

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
            self.query_one("#services", ServicesPanel).services = {
                'spotify': KaraokeConfig.has_spotify_credentials(),
                'virtualdj': bool(vdj_path),
                'vdj_file': vdj_path.name if vdj_path else '',
                'ollama': ollama_ok,
                'ollama_models': [m.get('name', '').split(':')[0] for m in ollama_models[:3]],
                'comfyui': comfyui_ok,
                'openai': bool(os.environ.get('OPENAI_API_KEY')),
                'synesthesia': self.synesthesia_running,
                'synesthesia_installed': Path('/Applications/Synesthesia.app').exists(),
                'playback_monitors': (self._latest_snapshot.monitor_status if self._latest_snapshot else {}),
                'playback_error': (self._latest_snapshot.error if self._latest_snapshot else ""),
                'playback_backoff': (self._latest_snapshot.backoff_seconds if self._latest_snapshot else 0.0),
            }
        except Exception:
            pass

    def _update_data(self) -> None:
        """Update all panels with current data (only update visible screens)."""
        if not self.karaoke_engine:
            return
        
        # Always update snapshot (needed for OSC)
        snapshot = self.karaoke_engine.get_snapshot()
        self._latest_snapshot = snapshot
        
        # Only update UI panels for visible screens (optimization)
        screen = self._current_screen
        
        if screen == "master":
            # Update master screen panels only
            monitor_status = snapshot.monitor_status or {}
            if snapshot.source and snapshot.source in monitor_status:
                source_connected = monitor_status[snapshot.source].get('available', False)
            else:
                source_connected = any(status.get('available', False) for status in monitor_status.values())
            track_data = build_track_data(snapshot, source_connected)
            
            try:
                self.query_one("#now-playing", NowPlayingPanel).track_data = track_data
            except Exception:
                pass
            
            cat_data = build_categories_payload(self.karaoke_engine.current_categories)
            try:
                self.query_one("#categories", CategoriesPanel).categories_data = cat_data
            except Exception:
                pass
            
            pipeline_data = build_pipeline_data(self.karaoke_engine, snapshot)
            try:
                self.query_one("#pipeline", PipelinePanel).pipeline_data = pipeline_data
            except Exception:
                pass
            
            # Mini OSC panel on master screen
            osc_msgs = self.karaoke_engine.osc_sender.get_recent_messages(50)
            try:
                panel = self.query_one("#osc-mini", OSCPanel)
                panel.full_view = False
                panel.messages = osc_msgs
            except Exception:
                pass
            
            # Workers panel update
            try:
                workers_list = []
                for worker in self.worker_coordinator.get_all_workers():
                    workers_list.append({
                        'name': worker.name,
                        'connected': worker.connected,
                        'state': worker.last_state,
                    })
                self.query_one("#workers", WorkersPanel).workers_data = {
                    'workers': workers_list
                }
            except Exception:
                pass
            
            # Master control status
            running_apps = sum(1 for app in self.process_manager.apps if self.process_manager.is_running(app))
            try:
                self.query_one("#master-ctrl", MasterControlPanel).status = {
                    'synesthesia': self.synesthesia_running,
                    'milksyphon': self.milksyphon_running,
                    'processing_apps': running_apps,
                    'karaoke': self.karaoke_engine is not None,
                }
            except Exception:
                pass
        
        elif screen == "osc":
            # Update OSC view only
            osc_msgs = self.karaoke_engine.osc_sender.get_recent_messages(50)
            try:
                panel = self.query_one("#osc-full", OSCPanel)
                panel.full_view = True
                panel.messages = osc_msgs
            except Exception:
                pass
        
        elif screen == "overview":
            # Update overview screen (all key metrics)
            snapshot = self._latest_snapshot
            monitor_status = snapshot.monitor_status or {}
            if snapshot.source and snapshot.source in monitor_status:
                source_connected = monitor_status[snapshot.source].get('available', False)
            else:
                source_connected = any(status.get('available', False) for status in monitor_status.values())
            track_data = build_track_data(snapshot, source_connected)
            
            try:
                self.query_one("#now-playing-overview", NowPlayingPanel).track_data = track_data
            except Exception:
                pass
            
            cat_data = build_categories_payload(self.karaoke_engine.current_categories)
            try:
                self.query_one("#categories-overview", CategoriesPanel).categories_data = cat_data
            except Exception:
                pass
            
            pipeline_data = build_pipeline_data(self.karaoke_engine, snapshot)
            try:
                self.query_one("#pipeline-overview", PipelinePanel).pipeline_data = pipeline_data
            except Exception:
                pass
            
            osc_msgs = self.karaoke_engine.osc_sender.get_recent_messages(20)
            try:
                panel = self.query_one("#osc-overview", OSCPanel)
                panel.full_view = False
                panel.messages = osc_msgs
            except Exception:
                pass
            
            # Workers overview
            try:
                workers_list = []
                for worker in self.worker_coordinator.get_all_workers():
                    workers_list.append({
                        'name': worker.name,
                        'connected': worker.connected,
                        'state': worker.last_state,
                    })
                self.query_one("#workers-overview", WorkerOverviewPanel).workers_data = {
                    'workers': workers_list
                }
            except Exception:
                pass
            
            # Services status
            running_apps = sum(1 for app in self.process_manager.apps if self.process_manager.is_running(app))
            try:
                self.query_one("#services-overview", ServicesPanel).status = {
                    'synesthesia': self.synesthesia_running,
                    'milksyphon': self.milksyphon_running,
                    'processing_apps': running_apps,
                }
            except Exception:
                pass
        
        elif screen == "ai":
            # Update AI debug screen only
            cat_data = build_categories_payload(self.karaoke_engine.current_categories)
            try:
                self.query_one("#categories-full", CategoriesPanel).categories_data = cat_data
            except Exception:
                pass
            
            pipeline_data = build_pipeline_data(self.karaoke_engine, snapshot)
            try:
                self.query_one("#pipeline-full", PipelinePanel).pipeline_data = pipeline_data
            except Exception:
                pass
        
        elif screen == "logs":
            # Update logs panel only
            try:
                self.query_one("#logs-panel", LogsPanel).logs = self._logs.copy()
            except Exception:
                pass
        
        elif screen == "audio" and AUDIO_ANALYZER_AVAILABLE:
            # Update audio panels only
            self._update_audio_panels()
        
        elif screen == "worker-spotify":
            # Update Spotify worker detail screen
            worker = self._get_worker_by_name('spotify_monitor')
            if worker:
                try:
                    self.query_one("#spotify-worker-detail", SpotifyWorkerPanel).worker_data = {
                        'connected': worker.connected,
                        'state': worker.last_state,
                    }
                except Exception:
                    pass
            
            # Also show current track
            track_data = build_track_data(self._latest_snapshot, True)
            try:
                self.query_one("#now-playing-spotify", NowPlayingPanel).track_data = track_data
            except Exception:
                pass
        
        elif screen == "worker-vdj":
            # Update VirtualDJ worker detail screen
            worker = self._get_worker_by_name('virtualdj_monitor')
            if worker:
                try:
                    self.query_one("#vdj-worker-detail", VirtualDJWorkerPanel).worker_data = {
                        'connected': worker.connected,
                        'state': worker.last_state,
                    }
                except Exception:
                    pass
            
            track_data = build_track_data(self._latest_snapshot, True)
            try:
                self.query_one("#now-playing-vdj", NowPlayingPanel).track_data = track_data
            except Exception:
                pass
        
        elif screen == "worker-lyrics":
            # Update Lyrics worker detail screen
            worker = self._get_worker_by_name('lyrics_fetcher')
            if worker:
                try:
                    self.query_one("#lyrics-worker-detail", LyricsWorkerPanel).worker_data = {
                        'connected': worker.connected,
                        'state': worker.last_state,
                    }
                except Exception:
                    pass
            
            cat_data = build_categories_payload(self.karaoke_engine.current_categories)
            try:
                self.query_one("#categories-lyrics", CategoriesPanel).categories_data = cat_data
            except Exception:
                pass
        
        elif screen == "worker-audio":
            # Update Audio worker detail screen
            worker = self._get_worker_by_name('audio_analyzer')
            if worker:
                try:
                    self.query_one("#audio-worker-detail", AudioWorkerPanel).worker_data = {
                        'connected': worker.connected,
                        'state': worker.last_state,
                    }
                except Exception:
                    pass
        
        elif screen == "worker-pm":
            # Update Process Manager detail screen
            worker = self._get_worker_by_name('process_manager')
            if worker:
                try:
                    self.query_one("#pm-detail", ProcessManagerPanel).worker_data = {
                        'connected': worker.connected,
                        'state': worker.last_state,
                    }
                except Exception:
                    pass
        
        # Send OSC status only when it changes (always, regardless of screen)
        running_apps = sum(1 for app in self.process_manager.apps if self.process_manager.is_running(app))
        current_status = {
            'karaoke_active': True,
            'synesthesia_running': self.synesthesia_running,
            'milksyphon_running': self.milksyphon_running,
            'processing_apps': running_apps
        }
        if current_status != self._last_master_status:
            self.karaoke_engine.osc_sender.send_master_status(
                karaoke_active=True, synesthesia_running=self.synesthesia_running,
                milksyphon_running=self.milksyphon_running, processing_apps=running_apps
            )
            self._last_master_status = current_status
    
    def _get_worker_by_name(self, name: str):
        """Get worker by name from coordinator."""
        for worker in self.worker_coordinator.get_all_workers():
            if worker.name == name:
                return worker
        return None

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
    
    def action_screen_overview(self) -> None:
        """Switch to overview screen."""
        self._switch_screen("overview")
    
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
    
    def action_screen_worker_spotify(self) -> None:
        """Switch to Spotify worker detail screen."""
        self._switch_screen("worker-spotify")
    
    def action_screen_worker_vdj(self) -> None:
        """Switch to VirtualDJ worker detail screen."""
        self._switch_screen("worker-vdj")
    
    def action_screen_worker_lyrics(self) -> None:
        """Switch to Lyrics worker detail screen."""
        self._switch_screen("worker-lyrics")
    
    def action_screen_worker_audio(self) -> None:
        """Switch to Audio worker detail screen."""
        self._switch_screen("worker-audio")
    
    def action_screen_worker_pm(self) -> None:
        """Switch to Process Manager detail screen."""
        self._switch_screen("worker-pm")

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

    def action_start_all_workers(self) -> None:
        """Start all workers via process manager."""
        logger.info("Starting all workers...")
        
        # List of workers to start (exclude process_manager itself)
        # Note: audio_analyzer requires audio hardware and is disabled by default
        # Note: osc_debugger is a debugging tool and is disabled by default
        workers_to_start = [
            'spotify_monitor',
            'virtualdj_monitor', 
            'lyrics_fetcher',
            # 'audio_analyzer',  # Requires audio hardware - enable if available
            # 'osc_debugger',    # Debugging tool - enable when needed
        ]
        
        for worker_name in workers_to_start:
            try:
                success = self.worker_coordinator.start_worker(worker_name)
                if success:
                    logger.info(f"Started worker: {worker_name}")
                else:
                    logger.warning(f"Failed to start worker: {worker_name}")
            except Exception as e:
                logger.error(f"Error starting {worker_name}: {e}")
        
        # Give workers time to start
        time.sleep(1)
        self.worker_coordinator.discover_workers()
        logger.info("Worker startup sequence complete")

    def action_restart_all_workers(self) -> None:
        """Restart all workers via process manager."""
        logger.info("Restarting all workers...")
        
        workers = self.worker_coordinator.get_all_workers()
        for worker in workers:
            if worker.name != 'process_manager':  # Don't restart the process manager itself
                try:
                    success = self.worker_coordinator.restart_worker(worker.name)
                    if success:
                        logger.info(f"Restarted worker: {worker.name}")
                    else:
                        logger.warning(f"Failed to restart worker: {worker.name}")
                except Exception as e:
                    logger.error(f"Error restarting {worker.name}: {e}")
        
        logger.info("Worker restart sequence complete")

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
        if self.karaoke_engine:
            self.karaoke_engine.stop()
        self.process_manager.cleanup()
        
        # Stop worker coordinator
        if self.worker_coordinator:
            self.worker_coordinator.stop()
            logger.info("Worker coordinator stopped")
        
        # Stop audio analyzer
        if AUDIO_ANALYZER_AVAILABLE and self.audio_running:
            self._stop_audio_analyzer()


def main():
    VJConsoleApp().run()


if __name__ == '__main__':
    main()
