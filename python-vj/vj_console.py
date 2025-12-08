#!/usr/bin/env python3
"""
VJ Console - Textual Edition with Multi-Screen Support

Screens (press 1-7 to switch):
1. Master Control - Main dashboard with all controls
2. OSC View - Full OSC message debug view  
3. Song AI Debug - Song categorization and pipeline details
4. All Logs - Complete application logs
5. MIDI Router - Toggle management and MIDI traffic debug
6. Audio Analysis - Real-time audio analysis and OSC emission
7. Shader Index - Shader analysis status and matching
"""

from dotenv import load_dotenv
load_dotenv(override=True, verbose=True)

from pathlib import Path
from typing import Optional, List, Dict, Tuple, Any
import logging
import subprocess
import time

from textual.app import App, ComposeResult
from textual.containers import Container, Horizontal, VerticalScroll, Vertical
from textual.widgets import Header, Footer, Static, TabbedContent, TabPane, Input, Button, Label
from textual.reactive import reactive
from textual.binding import Binding
from textual.screen import ModalScreen
from rich.text import Text

from process_manager import ProcessManager, ProcessingApp
from karaoke_engine import KaraokeEngine, Config as KaraokeConfig, SongCategories, get_active_line_index
from domain import PlaybackSnapshot, PlaybackState
from midi_console import MidiTogglesPanel, MidiActionsPanel, MidiDebugPanel, MidiStatusPanel, ControllerSelectionModal
from midi_router import MidiRouter, ConfigManager
from midi_domain import RouterConfig, DeviceConfig
from midi_infrastructure import list_controllers

# Shader matching
try:
    from shader_matcher import ShaderIndexer, ShaderSelector
    SHADER_MATCHER_AVAILABLE = True
except ImportError as e:
    SHADER_MATCHER_AVAILABLE = False
    import sys
    print(f"Warning: Shader matcher not available - {e}", file=sys.stderr)

# Audio analysis (imported conditionally to handle missing dependencies)
try:
    from audio_analyzer import (
        AudioConfig, DeviceConfig as AudioDeviceConfig, DeviceManager, 
        AudioAnalyzer, AudioAnalyzerWatchdog, LatencyTester
    )
    from audio_analytics_screen import EnhancedAudioAnalyticsPanel
    AUDIO_ANALYZER_AVAILABLE = True
except ImportError as e:
    AUDIO_ANALYZER_AVAILABLE = False
    # Logger might not be initialized yet at module level, so use print as fallback
    import sys
    print(f"Warning: Audio analyzer not available - {e}", file=sys.stderr)
    print("Install dependencies: pip install sounddevice numpy essentia", file=sys.stderr)

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
        'connected': source_available,
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
    analysis = engine.last_llm_result or {}
    if analysis:
        pipeline_data['analysis_summary'] = {
            'summary': analysis.get('summary') or analysis.get('lyric_summary') or analysis.get('mood'),
            'keywords': [str(k) for k in (analysis.get('keywords') or []) if str(k).strip()][:6],
            'themes': [str(t) for t in (analysis.get('themes') or []) if str(t).strip()][:4],
            'refrain_lines': [str(r) for r in (analysis.get('refrain_lines') or []) if str(r).strip()][:2],
            'visuals': [str(v) for v in (analysis.get('visual_adjectives') or []) if str(v).strip()][:4],
            'tempo': analysis.get('tempo')
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

        summary = self.pipeline_data.get('analysis_summary')
        if summary:
            lines.append("\n[bold cyan]AI Insights[/]")
            if summary.get('summary'):
                lines.append(f"[cyan]{truncate(str(summary['summary']), 180)}[/]")
            if summary.get('keywords'):
                lines.append(f"[yellow]Keywords:[/] {', '.join(summary['keywords'])}")
            if summary.get('themes'):
                lines.append(f"[green]Themes:[/] {', '.join(summary['themes'])}")
            if summary.get('visuals'):
                lines.append(f"[magenta]Visuals:[/] {', '.join(summary['visuals'])}")
            if summary.get('refrain_lines'):
                lines.append(f"[dim]Hooks:[/] | {' | '.join(summary['refrain_lines'])}")
            if summary.get('tempo'):
                lines.append(f"[dim]Tempo:[/] {summary['tempo']}")
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
        lines.append(svc(s.get('lmstudio'), "LM Studio", s.get('lmstudio_model', '') or "Not running"))
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


class AudioAnalyzerStatusPanel(ReactivePanel):
    """Audio analyzer status and controls."""
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
        
        lines = [self.render_section("Audio Analyzer", "═")]
        
        if not AUDIO_ANALYZER_AVAILABLE:
            lines.append("[yellow]Audio analyzer not available[/]")
            lines.append("[dim]Install: pip install sounddevice numpy essentia[/]")
        else:
            running = self.status.get('running', False)
            audio_alive = self.status.get('audio_alive', False)
            
            status_icon = format_status_icon(running, "● RUNNING", "○ stopped")
            audio_icon = format_status_icon(audio_alive, "● ACTIVE", "○ no signal")
            
            lines.append(f"  Status:        {status_icon}")
            lines.append(f"  Audio Input:   {audio_icon}")
            lines.append(f"  Device:        {self.status.get('device_name', 'default')}")
            lines.append(f"  Frames/sec:    {self.status.get('fps', 0):.1f}")
            lines.append(f"  Errors:        {self.status.get('error_count', 0)}")
            lines.append("")
            lines.append("[dim]Use [ ] to change audio device[/]")
        
        self.update("\n".join(lines))


class AudioFeaturesPanel(ReactivePanel):
    """Audio features visualization."""
    features = reactive({})
    
    def on_mount(self) -> None:
        """Initialize content when mounted."""
        self._safe_render()
    
    def watch_features(self, data: dict) -> None:
        self._safe_render()
    
    def _safe_render(self) -> None:
        """Render only if mounted."""
        if not self.is_mounted:
            return
        
        lines = [self.render_section("Audio Features", "═")]
        
        if not self.features:
            lines.append("[dim](waiting for audio...)[/dim]")
        else:
            # Beat and BPM
            beat = self.features.get('beat', 0)
            beat_icon = "◉" if beat else "○"
            bpm = self.features.get('bpm', 0)
            bpm_conf = self.features.get('bpm_confidence', 0)
            
            lines.append(f"  Beat:          {beat_icon} [{'green' if beat else 'dim'}]{beat_icon}[/]")
            lines.append(f"  BPM:           {bpm:.1f} [dim](conf: {bpm_conf:.2f})[/]")
            
            # Energy levels
            bass = self.features.get('bass_level', 0)
            mid = self.features.get('mid_level', 0)
            high = self.features.get('high_level', 0)
            
            lines.append("")
            lines.append(f"  Bass:          {format_bar(bass)} {bass:.2f}")
            lines.append(f"  Mids:          {format_bar(mid)} {mid:.2f}")
            lines.append(f"  Highs:         {format_bar(high)} {high:.2f}")
            
            # Spectral features
            brightness = self.features.get('brightness', 0)
            lines.append(f"  Brightness:    {format_bar(brightness)} {brightness:.2f}")
            
            # Structure detection
            buildup = self.features.get('buildup', False)
            drop = self.features.get('drop', False)
            trend = self.features.get('energy_trend', 0)
            
            lines.append("")
            if buildup:
                lines.append("  [yellow]▲ BUILD-UP DETECTED[/]")
            if drop:
                lines.append("  [red]▼ DROP DETECTED[/]")
            if not buildup and not drop:
                lines.append(f"  Energy Trend:  {'↗' if trend > 0 else '↘'} {trend:.3f}")
            
            # Pitch (if available)
            pitch_hz = self.features.get('pitch_hz', 0)
            pitch_conf = self.features.get('pitch_conf', 0)
            if pitch_hz > 0:
                lines.append(f"  Pitch:         {pitch_hz:.1f} Hz [dim](conf: {pitch_conf:.2f})[/]")
        
        self.update("\n".join(lines))


class AudioDevicesPanel(ReactivePanel):
    """Available audio input devices."""
    devices = reactive([])
    selected_index = reactive(0)
    
    def on_mount(self) -> None:
        """Initialize content when mounted."""
        self._safe_render()
    
    def watch_devices(self, data: list) -> None:
        self._safe_render()
    
    def watch_selected_index(self, idx: int) -> None:
        self._safe_render()
    
    def _safe_render(self) -> None:
        """Render only if mounted."""
        if not self.is_mounted:
            return
        
        lines = [self.render_section("Audio Devices", "═")]
        
        if not AUDIO_ANALYZER_AVAILABLE:
            lines.append("[dim]Audio analyzer not available[/]")
        elif not self.devices:
            lines.append("[dim](no devices found)[/dim]")
        else:
            for dev in self.devices:
                idx = dev.get('index', -1)
                name = dev.get('name', 'Unknown')
                channels = dev.get('channels', 0)
                sample_rate = dev.get('sample_rate', 0)
                
                is_selected = idx == self.selected_index
                prefix = " ▸ " if is_selected else "   "
                
                line = f"{prefix}{name} ({channels}ch @ {sample_rate}Hz)"
                
                if is_selected:
                    lines.append(f"[black on cyan]{line}[/]")
                else:
                    lines.append(line)
        
        self.update("\n".join(lines))


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


class AudioActionsPanel(Static):
    """Action buttons for Audio Analyzer screen."""
    
    analyzer_running = reactive(False)
    
    def compose(self) -> ComposeResult:
        with Horizontal(classes="action-buttons"):
            yield Button("▶ Start Analyzer", variant="primary", id="audio-start-stop")
            yield Button("◀ Prev Device", id="audio-prev-device")
            yield Button("Next Device ▶", id="audio-next-device")
    
    def watch_analyzer_running(self, running: bool) -> None:
        """Update button label based on analyzer state."""
        try:
            btn = self.query_one("#audio-start-stop", Button)
            btn.label = "■ Stop Analyzer" if running else "▶ Start Analyzer"
            btn.variant = "error" if running else "primary"
        except Exception:
            pass


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


class ShaderSearchModal(ModalScreen):
    """Modal for text-based shader search."""
    
    BINDINGS = [
        Binding("escape", "dismiss", "Cancel"),
    ]
    
    def __init__(self):
        super().__init__()
        self.search_query = ""
    
    def compose(self) -> ComposeResult:
        with Vertical(id="shader-search-modal"):
            yield Label("[bold cyan]🔍 Search Shaders[/]")
            yield Label("[dim]Search by: name, mood, colors, effects, description, geometry, objects, inputNames[/]\n")
            yield Label("Examples: love, colorful, psychedelic, distortion, bloom, waves, particles")
            yield Input(placeholder="Enter search term...", id="search-input")
            with Horizontal(id="modal-buttons"):
                yield Button("Search", variant="primary", id="search-btn")
                yield Button("Cancel", variant="default", id="cancel-btn")
    
    def on_mount(self) -> None:
        """Focus the input when modal opens."""
        self.query_one("#search-input", Input).focus()
    
    def on_input_submitted(self, event: Input.Submitted) -> None:
        """Handle enter key in input."""
        self.search_query = event.value.strip()
        if self.search_query:
            self.dismiss(self.search_query)
    
    def on_button_pressed(self, event: Button.Pressed) -> None:
        """Handle button press."""
        if event.button.id == "search-btn":
            inp = self.query_one("#search-input", Input)
            self.search_query = inp.value.strip()
            if self.search_query:
                self.dismiss(self.search_query)
        elif event.button.id == "cancel-btn":
            self.dismiss(None)


# ============================================================================
# SHADER ANALYSIS WORKER - Background thread for LLM analysis
# ============================================================================

import threading

class ShaderAnalysisWorker:
    """
    Background worker that analyzes unanalyzed shaders using LLM.
    
    Scans once on start, then processes the queue. Does NOT continuously re-scan.
    Call rescan() to refresh the queue if new shaders are added.
    """
    
    MAX_RECENT = 10  # Keep last N analyses for display
    
    def __init__(self, indexer, llm_analyzer):
        self.indexer = indexer
        self.llm = llm_analyzer
        self._thread: Optional[threading.Thread] = None
        self._running = False
        self._paused = True  # Start paused, user must press 'p' to begin
        self._lock = threading.Lock()
        self._queue: List[str] = []  # Queue of shader names to analyze
        self._scanned = False
        self._recent: List[dict] = []  # Recent analysis results for UI
        
        # Status for UI
        self.status = {
            'running': False,
            'paused': True,
            'current_shader': '',
            'progress': 0,
            'total': 0,
            'analyzed': 0,
            'errors': 0,
            'last_error': '',
            'queue': [],
            'recent': []
        }
    
    def start(self):
        """Start the analysis worker thread."""
        if self._thread and self._thread.is_alive():
            return
        
        self._running = True
        self._thread = threading.Thread(target=self._run, daemon=True, name="ShaderAnalysis")
        self._thread.start()
        logger.info("Shader analysis worker started")
    
    def stop(self):
        """Stop the worker thread."""
        self._running = False
        if self._thread:
            self._thread.join(timeout=2.0)
        logger.info("Shader analysis worker stopped")
    
    def toggle_pause(self):
        """Toggle pause state."""
        with self._lock:
            self._paused = not self._paused
            self.status['paused'] = self._paused
            logger.info(f"Shader analysis {'paused' if self._paused else 'resumed'}")
    
    def rescan(self):
        """Rescan for unanalyzed shaders and rebuild queue."""
        with self._lock:
            self._queue = self.indexer.get_unanalyzed()
            self.status['total'] = len(self._queue) + self.status['analyzed']
            self.status['queue'] = self._queue[:5]
            logger.info(f"Rescanned: {len(self._queue)} shaders in queue")
    
    def is_paused(self) -> bool:
        return self._paused
    
    def _run(self):
        """Main worker loop - scans once, then processes queue."""
        # Initial scan (once)
        if not self._scanned:
            with self._lock:
                self._queue = self.indexer.get_unanalyzed()
                self.status['total'] = len(self._queue)
                self.status['queue'] = self._queue[:5]
                self._scanned = True
                logger.info(f"Initial scan: {len(self._queue)} unanalyzed shaders")
        
        while self._running:
            # Check if paused
            if self._paused:
                self.status['running'] = False
                time.sleep(0.5)
                continue
            
            # Check if queue is empty
            with self._lock:
                if not self._queue:
                    self.status['running'] = False
                    self.status['current_shader'] = ''
                    # Don't rescan - just wait. User can press 'r' to rescan.
                    time.sleep(1.0)
                    continue
                
                # Get next shader from queue
                shader_name = self._queue[0]
            
            self.status['running'] = True
            self.status['current_shader'] = shader_name
            self.status['queue'] = self._queue[:5]
            
            try:
                # Get shader source
                source = self.indexer.get_shader_source(shader_name)
                if not source:
                    logger.warning(f"Could not read shader: {shader_name}")
                    self.status['errors'] += 1
                    self.status['last_error'] = f"Could not read {shader_name}"
                    # Remove from queue even on error
                    with self._lock:
                        if shader_name in self._queue:
                            self._queue.remove(shader_name)
                    continue
                
                # Check for screenshot (most significant for analysis)
                screenshot_path = self.indexer.get_screenshot_path(shader_name)
                screenshot_str = str(screenshot_path) if screenshot_path else None
                
                # Analyze with LLM (includes screenshot if available)
                if screenshot_path:
                    logger.info(f"Analyzing shader with screenshot: {shader_name}")
                else:
                    logger.info(f"Analyzing shader (no screenshot): {shader_name}")
                
                result = self.llm.analyze_shader(shader_name, source, screenshot_path=screenshot_str)
                
                if result and 'error' not in result:
                    # Parse ISF inputs
                    inputs = self.indexer.parse_isf_inputs(source)
                    
                    # Extract features
                    features = result.get('features', {})
                    
                    # Extract audio mapping
                    audio_mapping = result.get('audioMapping', {})
                    
                    # Build metadata dict
                    metadata = {
                        'mood': result.get('mood', 'unknown'),
                        'colors': result.get('colors', []),
                        'effects': result.get('effects', []),
                        'description': result.get('description', ''),
                        'geometry': result.get('geometry', []),
                        'objects': result.get('objects', []),
                        'energy': result.get('energy', 'medium'),
                        'complexity': result.get('complexity', 'medium'),
                        'audioMapping': audio_mapping,
                        'has_screenshot': result.get('has_screenshot', False)
                    }
                    
                    # Include screenshot analysis data if present
                    if 'screenshot' in result:
                        metadata['screenshot'] = result['screenshot']
                    
                    # Save analysis
                    success = self.indexer.save_analysis(
                        shader_name,
                        features,
                        inputs,
                        metadata
                    )
                    
                    if success:
                        self.status['analyzed'] += 1
                        self.status['progress'] = self.status['analyzed']
                        
                        # Track recent analysis for UI
                        with self._lock:
                            self._recent.insert(0, {
                                'name': shader_name,
                                'mood': result.get('mood', '?'),
                                'energy': result.get('energy', '?'),
                                'colors': result.get('colors', [])[:2],
                                'features': features,
                                'has_screenshot': result.get('has_screenshot', False)
                            })
                            self._recent = self._recent[:self.MAX_RECENT]
                            self.status['recent'] = self._recent.copy()
                        
                        # Sync to ChromaDB
                        self.indexer.sync()
                        logger.info(f"Analyzed and saved: {shader_name}")
                    else:
                        self.status['errors'] += 1
                        self.status['last_error'] = f"Failed to save {shader_name}"
                else:
                    # Save error file
                    error_msg = result.get('error', 'Unknown error') if result else 'No result'
                    self.indexer.save_error(shader_name, error_msg, {'result': result})
                    self.status['errors'] += 1
                    self.status['last_error'] = f"{shader_name}: {error_msg[:50]}"
                    logger.warning(f"Analysis failed for {shader_name}: {error_msg}")
                    
            except Exception as e:
                error_msg = str(e)
                self.indexer.save_error(shader_name, error_msg)
                self.status['errors'] += 1
                self.status['last_error'] = f"{shader_name}: {error_msg[:50]}"
                logger.exception(f"Error analyzing {shader_name}: {e}")
            
            # Remove processed shader from queue
            with self._lock:
                if shader_name in self._queue:
                    self._queue.remove(shader_name)
            
            # Small delay between analyses to avoid overwhelming LLM
            time.sleep(1.0)
        
        self.status['running'] = False
    
    def get_status(self) -> dict:
        """Get current status for UI."""
        # Return cached status - don't call indexer.get_stats() which rescans
        return {
            **self.status,
            'queue_size': len(self._queue),
        }


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
    
    /* Action button panels */
    .action-buttons {
        height: auto;
        padding: 1;
    }
    
    .action-buttons Button {
        margin: 0 1 1 0;
        min-width: 16;
    }
    
    /* Controller selection modal */
    #controller-modal {
        width: 80;
        height: auto;
        background: $surface;
        border: thick $primary;
        padding: 2;
    }
    
    /* Shader search modal */
    #shader-search-modal {
        width: 70;
        height: auto;
        background: $surface;
        border: thick $success;
        padding: 2;
    }
    
    #shader-search-modal Input {
        margin: 1 0;
    }
    
    #modal-buttons {
        align: center middle;
        height: auto;
        padding-top: 1;
    }
    
    #modal-buttons Button {
        margin: 0 1;
    }
    
    ListView {
        height: auto;
        max-height: 15;
        border: solid $accent;
        padding: 1;
    }
    
    ListItem {
        height: 1;
    }
    """

    BINDINGS = [
        Binding("q", "quit", "Quit"),
        Binding("1", "screen_master", "Master"),
        Binding("2", "screen_osc", "OSC"),
        Binding("3", "screen_ai", "AI Debug"),
        Binding("4", "screen_logs", "Logs"),
        Binding("5", "screen_audio", "Audio"),
        Binding("6", "screen_midi", "MIDI"),
        Binding("7", "screen_shaders", "Shaders"),
        Binding("s", "toggle_synesthesia", "Synesthesia"),
        Binding("m", "toggle_milksyphon", "MilkSyphon"),
        Binding("a", "toggle_audio_analyzer", "Audio Analyzer"),
        Binding("k,up", "nav_up", "Up"),
        Binding("j,down", "nav_down", "Down"),
        Binding("enter", "select_app", "Select"),
        Binding("plus,equals", "timing_up", "+Timing"),
        Binding("minus", "timing_down", "-Timing"),
        Binding("left_square_bracket", "audio_device_prev", "Prev Device", show=False),
        Binding("right_square_bracket", "audio_device_next", "Next Device", show=False),
        Binding("l", "midi_learn", "Learn", show=False),
        Binding("c", "midi_select_controller", "Controller", show=False),
        Binding("r", "midi_rename", "Rename", show=False),
        Binding("d", "midi_delete", "Delete", show=False),
        Binding("space", "midi_test_toggle", "Toggle", show=False),
        # Shader analysis bindings (active on shaders tab)
        Binding("p", "shader_toggle_analysis", "Pause/Resume Analysis", show=False),
        Binding("slash", "shader_search_mood", "Search by Mood", show=False),
        Binding("e", "shader_search_energy", "Search by Energy", show=False),
        Binding("R", "shader_rescan", "Rescan Shaders", show=False),
    ]

    current_tab = reactive("master")
    synesthesia_running = reactive(False)
    milksyphon_running = reactive(False)
    midi_selected_toggle = reactive(0)
    audio_selected_device = reactive(0)

    def __init__(self):
        super().__init__()
        self.process_manager = ProcessManager()
        self.process_manager.discover_apps(self._find_project_root())
        self.karaoke_engine: Optional[KaraokeEngine] = None
        self._logs: List[str] = []
        self._last_master_status: Optional[Dict[str, Any]] = None
        self._latest_snapshot: Optional[PlaybackSnapshot] = None
        
        # MIDI Router
        self.midi_router: Optional[MidiRouter] = None
        self.midi_messages: List[Tuple[float, str, Any]] = []  # (timestamp, direction, message)
        self._setup_midi_router()
        
        # Audio Analyzer
        self.audio_analyzer: Optional[Any] = None  # AudioAnalyzer when available
        self.audio_device_manager: Optional[Any] = None  # DeviceManager when available
        self.audio_watchdog: Optional[Any] = None  # AudioAnalyzerWatchdog when available
        self._setup_audio_analyzer()
        
        # Shader Indexer
        self.shader_indexer: Optional[Any] = None  # ShaderIndexer when available
        self.shader_selector: Optional[Any] = None  # ShaderSelector when available  
        self.shader_analysis_worker: Optional[ShaderAnalysisWorker] = None
        self._current_shader_match: Dict[str, Any] = {}
        self._shader_search_results: Dict[str, Any] = {}
        self._setup_shader_indexer()
        
        self._setup_log_capture()

    def _find_project_root(self) -> Path:
        for p in [Path(__file__).parent.parent, Path.cwd()]:
            if (p / "processing-vj").exists():
                return p
        return Path.cwd()
    
    def _setup_midi_router(self) -> None:
        """Initialize MIDI router."""
        try:
            # Try to load existing config or create default
            config_path = Path.home() / '.midi_router' / 'config.json'
            config_manager = ConfigManager(config_path)
            
            config = config_manager.load()
            if not config:
                # Create default config
                logger.info("Creating default MIDI router config")
                config = RouterConfig(
                    controller=DeviceConfig(name_pattern="Launchpad"),
                    virtual_output=DeviceConfig(name_pattern="MagicBus"),
                    toggles={}
                )
                config_manager.save(config)
            
            # Create router
            self.midi_router = MidiRouter(config_manager)
            
            # Try to start (will fail gracefully if no MIDI devices)
            if self.midi_router.start(config):
                logger.info("MIDI router started successfully")
            else:
                logger.warning("MIDI router failed to start (no devices?)")
                
        except Exception as e:
            logger.warning(f"MIDI router initialization failed: {e}")
            self.midi_router = None
    
    def _setup_audio_analyzer(self) -> None:
        """Initialize audio analyzer."""
        if not AUDIO_ANALYZER_AVAILABLE:
            logger.warning("Audio analyzer not available - skipping initialization")
            return
        
        try:
            # Create device manager
            self.audio_device_manager = DeviceManager()
            
            # Create audio config
            audio_config = AudioConfig(
                sample_rate=44100,
                block_size=512,
                enable_logging=True,
                log_level=logging.INFO,
            )
            
            # Create OSC callback that integrates with karaoke engine AND new audio panel
            def osc_callback(address: str, args: List):
                """Send audio features via OSC and to UI."""
                try:
                    # Send via network OSC
                    if self.karaoke_engine and self.karaoke_engine.osc_sender:
                        self.karaoke_engine.osc_sender.send(address, args)
                    
                    # Send to enhanced audio analytics panel
                    try:
                        panel = self.query_one("#enhanced-audio-analytics", EnhancedAudioAnalyticsPanel)
                        panel.add_osc_message(address, args)
                    except Exception:
                        pass  # Panel might not be mounted yet
                        
                except Exception as e:
                    logger.debug(f"OSC send error: {e}")
            
            # Create analyzer
            self.audio_analyzer = AudioAnalyzer(
                audio_config,
                self.audio_device_manager,
                osc_callback=osc_callback
            )
            
            # Create watchdog for self-healing
            self.audio_watchdog = AudioAnalyzerWatchdog(self.audio_analyzer)
            
            logger.info("Audio analyzer initialized")
            
        except Exception as e:
            logger.exception(f"Audio analyzer initialization failed: {e}")
            self.audio_analyzer = None
            self.audio_device_manager = None
            self.audio_watchdog = None
    
    def _setup_shader_indexer(self) -> None:
        """Initialize shader indexer and analysis worker."""
        if not SHADER_MATCHER_AVAILABLE:
            logger.warning("Shader matcher not available - skipping initialization")
            return
        
        try:
            self.shader_indexer = ShaderIndexer()
            
            # Sync from JSON files on startup
            stats = self.shader_indexer.sync()
            logger.info(f"Shader indexer synced: {stats}")
            
            # Create selector with loaded shaders (tracks usage)
            self.shader_selector = ShaderSelector(self.shader_indexer)
            
            # Create LLM analyzer for shader analysis
            from ai_services import LLMAnalyzer
            llm = LLMAnalyzer()
            
            # Create and start the analysis worker (starts paused)
            self.shader_analysis_worker = ShaderAnalysisWorker(self.shader_indexer, llm)
            self.shader_analysis_worker.start()
            
            logger.info("Shader indexer and analysis worker initialized")
            
        except Exception as e:
            logger.exception(f"Shader indexer initialization failed: {e}")
            self.shader_indexer = None
            self.shader_selector = None
            self.shader_analysis_worker = None
    
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
            
            # Tab 5: Audio Analyzer (Enhanced)
            with TabPane("5️⃣ Audio Analyzer", id="audio"):
                if AUDIO_ANALYZER_AVAILABLE:
                    yield EnhancedAudioAnalyticsPanel(id="enhanced-audio-analytics")
                else:
                    yield Label("[yellow]Audio analyzer not available[/]\n[dim]Install: pip install sounddevice numpy essentia[/]")
            
            # Tab 6: MIDI Router
            with TabPane("6️⃣ MIDI Router", id="midi"):
                with Horizontal():
                    with VerticalScroll(id="left-col"):
                        yield MidiActionsPanel(id="midi-actions", classes="panel")
                        yield MidiStatusPanel(id="midi-status", classes="panel")
                    with VerticalScroll(id="right-col"):
                        yield MidiTogglesPanel(id="midi-toggles", classes="panel")
                        yield MidiDebugPanel(id="midi-debug", classes="panel full-height")
            
            # Tab 7: Shader Indexer
            with TabPane("7️⃣ Shaders", id="shaders"):
                yield ShaderActionsPanel(id="shader-actions")
                with Horizontal():
                    with VerticalScroll(id="left-col"):
                        yield ShaderIndexPanel(id="shader-index", classes="panel")
                        yield ShaderAnalysisPanel(id="shader-analysis", classes="panel")
                    with VerticalScroll(id="right-col"):
                        yield ShaderSearchPanel(id="shader-search", classes="panel")
                        yield ShaderMatchPanel(id="shader-match", classes="panel full-height")

        yield Footer()

    def on_mount(self) -> None:
        self.title = "🎛 VJ Console"
        self.sub_title = "Press 1-7 to switch screens"
        
        # Initialize
        self.query_one("#apps", AppsListPanel).apps = self.process_manager.apps
        self.process_manager.start_monitoring(daemon_mode=True)
        self._start_karaoke()
        # Audio analyzer starts on 'a' keypress, not automatically
        
        # Background updates
        self.set_interval(0.5, self._update_data)
        self.set_interval(2.0, self._check_apps)
        
        # Flush audio analytics log batches at 30 FPS
        self.set_interval(1.0 / 30, self._flush_audio_log)
    
    def _flush_audio_log(self) -> None:
        """Flush batched messages in audio analytics log."""
        try:
            panel = self.query_one("#enhanced-audio-analytics", EnhancedAudioAnalyticsPanel)
            panel.flush_log()
        except Exception:
            pass  # Panel might not exist

    def on_button_pressed(self, event: Button.Pressed) -> None:
        """Route button clicks to actions."""
        button_id = event.button.id
        
        # Audio buttons
        if button_id == "audio-start-stop":
            self.action_toggle_audio_analyzer()
        elif button_id == "audio-prev-device":
            self.action_audio_device_prev()
        elif button_id == "audio-next-device":
            self.action_audio_device_next()
        
        # Shader buttons
        elif button_id == "shader-pause-resume":
            self.action_shader_toggle_analysis()
        elif button_id == "shader-search-mood":
            self.action_shader_search_mood()
        elif button_id == "shader-search-energy":
            self.action_shader_search_energy()
        elif button_id == "shader-search-text":
            self.action_shader_search_text()
        elif button_id == "shader-rescan":
            self.action_shader_rescan()

    # === Actions (impure, side effects) ===
    
    def _start_karaoke(self) -> None:
        try:
            self.karaoke_engine = KaraokeEngine()
            self.karaoke_engine.start()
        except Exception as e:
            logger.exception(f"Karaoke start error: {e}")
    
    def _start_audio_analyzer(self) -> None:
        """Start the audio analyzer thread."""
        if not AUDIO_ANALYZER_AVAILABLE or not self.audio_analyzer:
            return
        
        try:
            # Start analyzer thread
            self.audio_analyzer.start()
            logger.info("Audio analyzer started")
            
            # Update enhanced panel status
            try:
                panel = self.query_one("#enhanced-audio-analytics", EnhancedAudioAnalyticsPanel)
                panel.set_connection_status("Connected")
            except Exception:
                pass
            
            # Update devices list
            self._update_audio_devices()
            
        except Exception as e:
            logger.exception(f"Audio analyzer start error: {e}")
    
    def _update_audio_devices(self) -> None:
        """Update available audio devices list."""
        if not AUDIO_ANALYZER_AVAILABLE or not self.audio_device_manager:
            return
        
        try:
            devices = self.audio_device_manager.list_devices()
            current_device_index = self.audio_device_manager.get_device_index()
            
            # Update panel
            try:
                panel = self.query_one("#audio-devices", AudioDevicesPanel)
                panel.devices = devices
                if current_device_index is not None:
                    panel.selected_index = current_device_index
                    self.audio_selected_device = current_device_index
            except Exception:
                pass
        except Exception as e:
            logger.debug(f"Failed to update audio devices: {e}")

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
        lmstudio_ok, lmstudio_model, comfyui_ok = False, '', False
        
        try:
            import requests
            # Single request to LM Studio - reuse response
            lmstudio_resp = requests.get("http://localhost:1234/v1/models", timeout=1)
            if lmstudio_resp.status_code == 200:
                lmstudio_ok = True
                models = lmstudio_resp.json().get('data', [])
                lmstudio_model = models[0].get('id', 'loaded') if models else 'no model'
            
            comfyui_ok = requests.get("http://127.0.0.1:8188/system_stats", timeout=1).status_code == 200
        except Exception:
            pass

        vdj_path = KaraokeConfig.find_vdj_path()
        
        try:
            self.query_one("#services", ServicesPanel).services = {
                'spotify': KaraokeConfig.has_spotify_credentials(),
                'virtualdj': bool(vdj_path),
                'vdj_file': vdj_path.name if vdj_path else '',
                'lmstudio': lmstudio_ok,
                'lmstudio_model': lmstudio_model,
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
        """Update all panels with current data."""
        if not self.karaoke_engine:
            return
        snapshot = self.karaoke_engine.get_snapshot()
        self._latest_snapshot = snapshot
        monitor_status = snapshot.monitor_status or {}
        if snapshot.source and snapshot.source in monitor_status:
            source_connected = monitor_status[snapshot.source].get('available', False)
        else:
            source_connected = any(status.get('available', False) for status in monitor_status.values())
        track_data = build_track_data(snapshot, source_connected)
        try:
            now_playing = self.query_one("#now-playing", NowPlayingPanel)
            now_playing.track_data = track_data
            now_playing.shader_name = self.karaoke_engine.current_shader
        except Exception:
            pass

        cat_data = build_categories_payload(self.karaoke_engine.current_categories)
        
        # Update categories panels
        for panel_id in ["categories", "categories-full"]:
            try:
                self.query_one(f"#{panel_id}", CategoriesPanel).categories_data = cat_data
            except Exception:
                pass

        # Update pipeline
        pipeline_data = build_pipeline_data(self.karaoke_engine, snapshot)
        for panel_id in ["pipeline", "pipeline-full"]:
            try:
                self.query_one(f"#{panel_id}", PipelinePanel).pipeline_data = pipeline_data
            except Exception:
                pass

        # Update OSC panels
        osc_msgs = self.karaoke_engine.osc_sender.get_recent_messages(50)
        for panel_id in ["osc-mini", "osc-full"]:
            try:
                panel = self.query_one(f"#{panel_id}", OSCPanel)
                panel.full_view = panel_id == "osc-full"
                panel.messages = osc_msgs
            except Exception:
                pass

        # Update master control
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

        # Send OSC status only when it changes
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
        
        # Update logs panel
        try:
            self.query_one("#logs-panel", LogsPanel).logs = self._logs.copy()
        except Exception:
            pass
        
        # Update MIDI panels
        self._update_midi_panels()
        
        # Update audio analyzer panels
        self._update_audio_panels()
        
        # Update shader panels
        self._update_shader_panels()

    def _update_audio_panels(self) -> None:
        """Update audio analyzer panels."""
        if not AUDIO_ANALYZER_AVAILABLE or not self.audio_analyzer:
            return
        
        try:
            # Update watchdog for self-healing (only if analyzer was started)
            if self.audio_watchdog and self.audio_analyzer.is_alive():
                self.audio_watchdog.update()
            
            # Get analyzer stats
            stats = self.audio_analyzer.get_stats()
            
            # Update status panel
            try:
                status_panel = self.query_one("#audio-status", AudioAnalyzerStatusPanel)
                status_panel.status = stats
            except Exception:
                pass
            
            # Get latest features
            features = self.audio_analyzer.latest_features.copy()
            
            # Update features panel
            try:
                features_panel = self.query_one("#audio-features", AudioFeaturesPanel)
                features_panel.features = features
            except Exception:
                pass
            
            # Update action panel button labels
            try:
                actions_panel = self.query_one("#audio-actions", AudioActionsPanel)
                actions_panel.analyzer_running = self.audio_analyzer.is_alive()
            except Exception:
                pass
            
        except Exception as e:
            logger.debug(f"Failed to update audio panels: {e}")
    
    def _update_shader_panels(self) -> None:
        """Update shader indexer/matcher panels."""
        if not SHADER_MATCHER_AVAILABLE or not self.shader_indexer:
            return
        
        try:
            # Update index status
            stats = self.shader_indexer.get_stats()
            try:
                index_panel = self.query_one("#shader-index", ShaderIndexPanel)
                index_panel.status = stats
            except Exception:
                pass
            
            # Update analysis progress panel
            if self.shader_analysis_worker:
                try:
                    analysis_panel = self.query_one("#shader-analysis", ShaderAnalysisPanel)
                    analysis_panel.analysis_status = self.shader_analysis_worker.get_status()
                except Exception:
                    pass
                
                # Update action panel button labels
                try:
                    actions_panel = self.query_one("#shader-actions", ShaderActionsPanel)
                    actions_panel.analysis_running = not self.shader_analysis_worker.is_paused()
                except Exception:
                    pass
            
            # Update search results panel
            try:
                search_panel = self.query_one("#shader-search", ShaderSearchPanel)
                search_panel.search_results = self._shader_search_results
            except Exception:
                pass
            
            # Update match panel
            try:
                match_panel = self.query_one("#shader-match", ShaderMatchPanel)
                match_panel.match_result = self._current_shader_match
            except Exception:
                pass
            
        except Exception as e:
            logger.debug(f"Failed to update shader panels: {e}")
    
    def _update_midi_panels(self) -> None:
        """Update MIDI router panels."""
        if not self.midi_router:
            return
        
        try:
            # Update toggles list
            toggles = self.midi_router.get_toggle_list()
            toggles_panel = self.query_one("#midi-toggles", MidiTogglesPanel)
            toggles_panel.toggles = toggles
            toggles_panel.selected = self.midi_selected_toggle
            
            # Update actions panel
            actions_panel = self.query_one("#midi-actions", MidiActionsPanel)
            actions_panel.learn_mode = self.midi_router.is_learn_mode
            actions_panel.router_running = self.midi_router.is_running
            
            # Build device info
            if self.midi_router.config:
                controller = self.midi_router.config.controller.name_pattern
                virtual = self.midi_router.config.virtual_output.name_pattern
                actions_panel.device_info = f"Controller: {controller} → {virtual}"
            
            # Update status panel
            status_panel = self.query_one("#midi-status", MidiStatusPanel)
            if self.midi_router.config:
                config_path = Path.home() / '.midi_router' / 'config.json'
                
                # Show actual port name if available, otherwise pattern
                controller_name = self.midi_router.config.controller.input_port
                if not controller_name:
                    controller_name = f"{self.midi_router.config.controller.name_pattern} (pattern)"
                
                virtual_name = self.midi_router.config.virtual_output.name_pattern
                
                status_panel.config_info = {
                    'controller': controller_name,
                    'virtual_port': virtual_name,
                    'toggle_count': len(self.midi_router.config.toggles),
                    'config_file': str(config_path),
                }
            
            # Update debug panel
            debug_panel = self.query_one("#midi-debug", MidiDebugPanel)
            debug_panel.messages = self.midi_messages.copy()
            
        except Exception as e:
            logger.debug(f"Failed to update MIDI panels: {e}")

    # === Screen switching ===
    
    def action_screen_master(self) -> None:
        self.query_one("#screens", TabbedContent).active = "master"
    
    def action_screen_osc(self) -> None:
        self.query_one("#screens", TabbedContent).active = "osc"
    
    def action_screen_ai(self) -> None:
        self.query_one("#screens", TabbedContent).active = "ai"
    
    def action_screen_logs(self) -> None:
        self.query_one("#screens", TabbedContent).active = "logs"
    
    def action_screen_audio(self) -> None:
        self.query_one("#screens", TabbedContent).active = "audio"
    
    def action_screen_midi(self) -> None:
        self.query_one("#screens", TabbedContent).active = "midi"
    
    def action_screen_shaders(self) -> None:
        self.query_one("#screens", TabbedContent).active = "shaders"

    # === App control ===
    
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
    
    def action_toggle_audio_analyzer(self) -> None:
        """Toggle audio analyzer on/off (a key)."""
        if not AUDIO_ANALYZER_AVAILABLE or not self.audio_analyzer:
            self.notify("Audio analyzer not available", severity="warning")
            return
        
        if self.audio_analyzer.is_alive():
            self._stop_audio_analyzer()
            self.notify("Audio analyzer stopped", severity="information")
        else:
            self._start_audio_analyzer()
            self.notify("Audio analyzer started", severity="information")
    
    def _stop_audio_analyzer(self) -> None:
        """Stop the audio analyzer thread."""
        if not AUDIO_ANALYZER_AVAILABLE or not self.audio_analyzer:
            return
        
        try:
            self.audio_analyzer.stop()
            logger.info("Audio analyzer stopped")
            
            # Update enhanced panel status
            try:
                panel = self.query_one("#enhanced-audio-analytics", EnhancedAudioAnalyticsPanel)
                panel.set_connection_status("Disconnected")
            except Exception:
                pass
                
        except Exception as e:
            logger.exception(f"Audio analyzer stop error: {e}")
    
    # === Shader analysis actions ===
    
    def action_shader_toggle_analysis(self) -> None:
        """Toggle shader analysis pause/resume (p key)."""
        if not self.shader_analysis_worker:
            self.notify("Shader analysis worker not available", severity="warning")
            return
        
        self.shader_analysis_worker.toggle_pause()
        if self.shader_analysis_worker.is_paused():
            self.notify("Shader analysis paused", severity="information")
        else:
            self.notify("Shader analysis resumed", severity="information")
    
    def action_shader_search_mood(self) -> None:
        """Search shaders by mood (/ key)."""
        if not SHADER_MATCHER_AVAILABLE or not self.shader_selector:
            self.notify("Shader selector not available", severity="warning")
            return
        
        # Cycle through common moods
        moods = ['energetic', 'calm', 'dark', 'bright', 'psychedelic', 'mysterious', 'chaotic', 'peaceful']
        current = self._shader_search_results.get('query', '')
        
        try:
            idx = moods.index(current)
            next_mood = moods[(idx + 1) % len(moods)]
        except ValueError:
            next_mood = moods[0]
        
        # Perform search using selector (tracks usage for variety)
        results = []
        for _ in range(8):
            match = self.shader_selector.select_by_mood(next_mood, energy=0.5, top_k=10)
            if match and match.name not in [r['name'] for r in results]:
                results.append({
                    'name': match.name,
                    'score': match.score,
                    'features': {
                        'energy_score': match.features.energy_score,
                        'mood_valence': match.features.mood_valence,
                        'motion_speed': match.features.motion_speed,
                    }
                })
        
        # Reset usage to not pollute actual session tracking
        self.shader_selector.reset_usage()
        
        self._shader_search_results = {
            'type': 'mood',
            'query': next_mood,
            'results': results
        }
    
    def action_shader_search_energy(self) -> None:
        """Search shaders by energy level (e key)."""
        if not SHADER_MATCHER_AVAILABLE or not self.shader_selector:
            self.notify("Shader selector not available", severity="warning")
            return
        
        # Cycle through energy levels
        levels = [0.2, 0.4, 0.6, 0.8, 1.0]
        current_query = self._shader_search_results.get('query', '')
        
        try:
            current_energy = float(current_query)
            idx = min(range(len(levels)), key=lambda i: abs(levels[i] - current_energy))
            next_energy = levels[(idx + 1) % len(levels)]
        except (ValueError, TypeError):
            next_energy = levels[0]
        
        # Perform search using feature vector via indexer
        target_vector = [next_energy, 0.0, 0.5, next_energy, 0.5, 0.5]  # energy-focused search
        
        if self.shader_indexer and self.shader_indexer._use_chromadb:
            # Use ChromaDB
            similar = self.shader_indexer.query_similar(target_vector, top_k=8)
            results = []
            for name, dist in similar:
                # Find shader features in indexer
                shader = self.shader_indexer.shaders.get(name)
                if shader:
                    results.append({
                        'name': name,
                        'score': dist,
                        'features': {
                            'energy_score': shader.energy_score,
                            'mood_valence': shader.mood_valence,
                            'motion_speed': shader.motion_speed,
                        }
                    })
                else:
                    # Shader found in ChromaDB but not in memory - still show it
                    results.append({
                        'name': name,
                        'score': dist,
                        'features': {}
                    })
        else:
            # Fallback to mood search with energy via selector
            results = []
            for _ in range(8):
                match = self.shader_selector.select_by_mood(
                    'energetic' if next_energy > 0.5 else 'calm',
                    energy=next_energy,
                    top_k=10
                )
                if match and match.name not in [r['name'] for r in results]:
                    results.append({
                        'name': match.name,
                        'score': match.score,
                        'features': {
                            'energy_score': match.features.energy_score,
                            'mood_valence': match.features.mood_valence,
                            'motion_speed': match.features.motion_speed,
                        }
                    })
            # Reset usage to not pollute actual session tracking
            self.shader_selector.reset_usage()
        
        self._shader_search_results = {
            'type': 'energy',
            'query': f'{next_energy:.1f}',
            'results': results
        }
    
    def action_shader_search_text(self) -> None:
        """Open text search modal for shaders."""
        if not SHADER_MATCHER_AVAILABLE or not self.shader_indexer:
            self.notify("Shader indexer not available", severity="warning")
            return
        
        def handle_search_result(query: str | None) -> None:
            if not query:
                return
            
            # Perform text search
            results = self.shader_indexer.text_search(query, top_k=10)
            
            formatted_results = []
            for name, score, features in results:
                formatted_results.append({
                    'name': name,
                    'score': score,
                    'features': features
                })
            
            self._shader_search_results = {
                'type': 'text',
                'query': query,
                'results': formatted_results
            }
            
            self.notify(f"Found {len(results)} shaders matching '{query}'", severity="information")
        
        self.push_screen(ShaderSearchModal(), handle_search_result)
    
    def action_shader_rescan(self) -> None:
        """Rescan for unanalyzed shaders (R key)."""
        if self.shader_analysis_worker:
            self.shader_analysis_worker.rescan()
            self.notify("Rescanning for unanalyzed shaders...", severity="information")
        else:
            self.notify("Shader analysis worker not available", severity="warning")
    
    def action_audio_device_prev(self) -> None:
        """Switch to previous audio device ([ key)."""
        if not AUDIO_ANALYZER_AVAILABLE or not self.audio_device_manager:
            return
        
        try:
            devices = self.audio_device_manager.list_devices()
            if not devices:
                return
            
            # Get current device index
            current_idx = self.audio_selected_device
            
            # Find current device in list
            current_pos = -1
            for i, dev in enumerate(devices):
                if dev.get('index') == current_idx:
                    current_pos = i
                    break
            
            # Select previous device (wrap around)
            if current_pos >= 0:
                new_pos = (current_pos - 1) % len(devices)
            else:
                new_pos = len(devices) - 1
            
            new_device_idx = devices[new_pos].get('index')
            self._switch_audio_device(new_device_idx)
            
        except Exception as e:
            logger.error(f"Failed to switch to previous audio device: {e}")
    
    def action_audio_device_next(self) -> None:
        """Switch to next audio device (] key)."""
        if not AUDIO_ANALYZER_AVAILABLE or not self.audio_device_manager:
            return
        
        try:
            devices = self.audio_device_manager.list_devices()
            if not devices:
                return
            
            # Get current device index
            current_idx = self.audio_selected_device
            
            # Find current device in list
            current_pos = -1
            for i, dev in enumerate(devices):
                if dev.get('index') == current_idx:
                    current_pos = i
                    break
            
            # Select next device (wrap around)
            if current_pos >= 0:
                new_pos = (current_pos + 1) % len(devices)
            else:
                new_pos = 0
            
            new_device_idx = devices[new_pos].get('index')
            self._switch_audio_device(new_device_idx)
            
        except Exception as e:
            logger.error(f"Failed to switch to next audio device: {e}")
    
    def _switch_audio_device(self, device_index: int):
        """
        Switch audio analyzer to a different device.
        
        Args:
            device_index: Index of the device to switch to
        """
        if not AUDIO_ANALYZER_AVAILABLE or not self.audio_analyzer or not self.audio_device_manager:
            return
        
        try:
            # Set device in device manager
            self.audio_device_manager.set_device(device_index)
            
            # Restart audio analyzer with new device
            if self.audio_analyzer.running:
                self.audio_analyzer.stop_stream()
                time.sleep(0.2)  # Brief pause for cleanup
                self.audio_analyzer.start_stream()
            
            # Update selected device
            self.audio_selected_device = device_index
            
            # Update devices panel
            self._update_audio_devices()
            
            logger.info(f"Switched to audio device: {device_index}")
            
        except Exception as e:
            logger.error(f"Failed to switch audio device: {e}")

    def action_nav_up(self) -> None:
        current_screen = self.query_one("#screens", TabbedContent).active
        
        if current_screen == "master":
            panel = self.query_one("#apps", AppsListPanel)
            if panel.selected > 0:
                panel.selected -= 1
        elif current_screen == "midi":
            if self.midi_router and self.midi_selected_toggle > 0:
                self.midi_selected_toggle -= 1

    def action_nav_down(self) -> None:
        current_screen = self.query_one("#screens", TabbedContent).active
        
        if current_screen == "master":
            panel = self.query_one("#apps", AppsListPanel)
            if panel.selected < len(self.process_manager.apps) - 1:
                panel.selected += 1
        elif current_screen == "midi":
            if self.midi_router:
                toggles = self.midi_router.get_toggle_list()
                if self.midi_selected_toggle < len(toggles) - 1:
                    self.midi_selected_toggle += 1

    def action_select_app(self) -> None:
        current_screen = self.query_one("#screens", TabbedContent).active
        
        if current_screen == "master":
            panel = self.query_one("#apps", AppsListPanel)
            if 0 <= panel.selected < len(self.process_manager.apps):
                app = self.process_manager.apps[panel.selected]
                if self.process_manager.is_running(app):
                    self.process_manager.stop_app(app)
                else:
                    self.process_manager.launch_app(app)
    
    def action_midi_test_toggle(self) -> None:
        """Test toggle selected MIDI toggle (space key on MIDI screen only)."""
        current_screen = self.query_one("#screens", TabbedContent).active
        if current_screen == "midi":
            self._midi_test_toggle()

    def action_timing_up(self) -> None:
        if self.karaoke_engine:
            self.karaoke_engine.adjust_timing(+200)

    def action_timing_down(self) -> None:
        if self.karaoke_engine:
            self.karaoke_engine.adjust_timing(-200)
    
    # === MIDI Router Actions ===
    
    def action_midi_learn(self) -> None:
        """Enter MIDI learn mode."""
        if not self.midi_router:
            logger.warning("MIDI router not available")
            return
        
        def on_learned(note: int, name: str):
            logger.info(f"Learned toggle: {name} (note {note})")
            self._log(f"MIDI: Learned toggle {name} (note {note})")
        
        self.midi_router.enter_learn_mode(callback=on_learned)
        logger.info("Entered MIDI learn mode - press a pad")
    
    def action_midi_rename(self) -> None:
        """Rename selected MIDI toggle."""
        if not self.midi_router:
            return
        
        toggles = self.midi_router.get_toggle_list()
        if not toggles or self.midi_selected_toggle >= len(toggles):
            return
        
        note, old_name, _ = toggles[self.midi_selected_toggle]
        
        # For now, just log - in future could show input dialog
        logger.info(f"Rename toggle {note} ({old_name}) - use CLI for now")
        self._log(f"MIDI: To rename, use CLI: r {note} <new_name>")
    
    def action_midi_delete(self) -> None:
        """Delete selected MIDI toggle."""
        if not self.midi_router:
            return
        
        toggles = self.midi_router.get_toggle_list()
        if not toggles or self.midi_selected_toggle >= len(toggles):
            return
        
        note, name, _ = toggles[self.midi_selected_toggle]
        
        if self.midi_router.remove_toggle(note):
            logger.info(f"Deleted toggle {name} (note {note})")
            self._log(f"MIDI: Deleted toggle {name}")
            # Adjust selection if needed
            if self.midi_selected_toggle >= len(toggles) - 1:
                self.midi_selected_toggle = max(0, len(toggles) - 2)
    
    async def action_midi_select_controller(self) -> None:
        """Show controller selection dialog."""
        if not self.midi_router:
            logger.warning("MIDI router not available")
            return
        
        # Get list of available controllers
        controllers = list_controllers()
        
        # Get current controller from config
        current_controller = None
        if self.midi_router.config:
            # Try to get the actual port name being used
            current_controller = self.midi_router.config.controller.input_port
            if not current_controller:
                # Fall back to pattern
                from midi_infrastructure import find_port_by_pattern, list_available_ports
                input_ports, _ = list_available_ports()
                current_controller = find_port_by_pattern(
                    input_ports, 
                    self.midi_router.config.controller.name_pattern
                )
        
        # Show modal
        result = await self.push_screen(ControllerSelectionModal(controllers, current_controller), wait_for_dismiss=True)
        
        if result:
            # Update config with selected controller
            logger.info(f"Selected controller: {result}")
            self._update_midi_controller(result)
    
    def _update_midi_controller(self, controller_name: str) -> None:
        """
        Update MIDI router to use selected controller.
        
        Args:
            controller_name: Full name of the controller port
        """
        if not self.midi_router:
            return
        
        try:
            # Stop current router
            if self.midi_router.is_running:
                self.midi_router.stop()
            
            # Update config with explicit port name
            old_config = self.midi_router.config
            if not old_config:
                # Create new config
                config = RouterConfig(
                    controller=DeviceConfig(
                        name_pattern="",  # Will use explicit port
                        input_port=controller_name,
                        output_port=controller_name
                    ),
                    virtual_output=DeviceConfig(name_pattern="MagicBus"),
                    toggles={}
                )
            else:
                # Update existing config
                config = RouterConfig(
                    controller=DeviceConfig(
                        name_pattern="",  # Clear pattern, use explicit port
                        input_port=controller_name,
                        output_port=controller_name
                    ),
                    virtual_output=old_config.virtual_output,
                    toggles=old_config.toggles
                )
            
            # Save config
            config_path = Path.home() / '.midi_router' / 'config.json'
            config_manager = ConfigManager(config_path)
            config_manager.save(config)
            
            # Restart router with new config
            if self.midi_router.start(config):
                logger.info(f"MIDI router restarted with controller: {controller_name}")
                self._log(f"MIDI: Switched to controller: {controller_name}")
            else:
                logger.error(f"Failed to start MIDI router with controller: {controller_name}")
                self._log(f"MIDI: Failed to switch controller")
        
        except Exception as e:
            logger.error(f"Error updating MIDI controller: {e}")
            self._log(f"MIDI: Error switching controller: {e}")
    
    def _midi_test_toggle(self) -> None:
        """Test toggle selected MIDI toggle (for testing without hardware)."""
        if not self.midi_router:
            return
        
        toggles = self.midi_router.get_toggle_list()
        if not toggles or self.midi_selected_toggle >= len(toggles):
            return
        
        note, name, state = toggles[self.midi_selected_toggle]
        logger.info(f"Test toggle {name}: {state} → {not state}")
    
    def _log(self, message: str):
        """Add a message to logs."""
        self._logs.append(f"{time.strftime('%Y-%m-%d %H:%M:%S')} - vj_console - INFO - {message}")
        if len(self._logs) > 500:
            self._logs.pop(0)

    def on_unmount(self) -> None:
        if self.karaoke_engine:
            self.karaoke_engine.stop()
        if self.midi_router:
            self.midi_router.stop()
        if self.audio_analyzer and AUDIO_ANALYZER_AVAILABLE and self.audio_analyzer.is_alive():
            self.audio_analyzer.stop()
        self.process_manager.cleanup()


def main():
    VJConsoleApp().run()


if __name__ == '__main__':
    main()
