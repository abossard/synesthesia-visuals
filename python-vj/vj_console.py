#!/usr/bin/env python3
"""
VJ Console - Textual Edition with Multi-Screen Support

Screens (press 1-6 to switch):
1. Master Control - Main dashboard with all controls
2. OSC View - Full OSC message debug view  
3. Song AI Debug - Song categorization and pipeline details
4. All Logs - Complete application logs
5. MIDI Router - Toggle management and MIDI traffic debug
6. Shader Index - Shader analysis status and matching

(Audio Analysis removed - use Synesthesia instead)
"""

from dotenv import load_dotenv
load_dotenv(override=True, verbose=True)

from pathlib import Path
from typing import Optional, List, Dict, Tuple, Any
from dataclasses import dataclass
import logging
import subprocess
import time
import asyncio

import psutil
import requests

from textual.app import App, ComposeResult
from textual.containers import Container, Horizontal, VerticalScroll, Vertical
from textual.widgets import Header, Footer, Static, TabbedContent, TabPane, Input, Button, Label, Checkbox, RadioButton, RadioSet
from textual.message import Message
from textual.reactive import reactive
from textual.binding import Binding
from textual.screen import ModalScreen
from rich.text import Text

from process_manager import ProcessManager, ProcessingApp
from karaoke_engine import KaraokeEngine, Config as KaraokeConfig, SongCategories, get_active_line_index, PLAYBACK_SOURCES
from domain import PlaybackSnapshot, PlaybackState
from infrastructure import Settings
from osc_hub import osc, osc_monitor

# Launchpad control (replaces MIDI Router)
try:
    from launchpad_console import (
        LaunchpadStatusPanel, LaunchpadPadsPanel, 
        LaunchpadInstructionsPanel, LaunchpadOscDebugPanel,
        LaunchpadTestsPanel, LaunchpadManager,
        LAUNCHPAD_LIB_AVAILABLE,
    )
except ImportError:
    LAUNCHPAD_LIB_AVAILABLE = False
    LaunchpadStatusPanel = None
    LaunchpadPadsPanel = None
    LaunchpadInstructionsPanel = None
    LaunchpadOscDebugPanel = None
    LaunchpadTestsPanel = None
    LaunchpadManager = None

# Shader matching
try:
    from shader_matcher import ShaderIndexer, ShaderSelector
    SHADER_MATCHER_AVAILABLE = True
except ImportError as e:
    SHADER_MATCHER_AVAILABLE = False
    import sys
    print(f"Warning: Shader matcher not available - {e}", file=sys.stderr)

# Audio analyzer removed - Synesthesia is the primary audio engine
AUDIO_ANALYZER_AVAILABLE = False

# Configure logging to capture INFO level messages for the log panel
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(name)s - %(levelname)s - %(message)s')
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
    """Render a single OSC message with full args (legacy format)."""
    ts, address, args = msg
    time_str = time.strftime("%H:%M:%S", time.localtime(ts))
    args_str = str(args)
    color = color_by_osc_channel(address)
    return f"[dim]{time_str}[/] [{color}]{address}[/] {args_str}"

def render_aggregated_osc(msg) -> str:
    """Render aggregated OSC message: channel, address, value, count."""
    time_str = time.strftime("%H:%M:%S", time.localtime(msg.last_time))
    
    # Channel color
    if msg.channel.startswith("→"):
        ch_color = "cyan"
        ch_label = msg.channel
    elif msg.channel == "syn":
        ch_color = "magenta"
        ch_label = "syn"
    elif msg.channel == "vdj":
        ch_color = "blue"
        ch_label = "vdj"
    else:
        ch_color = "white"
        ch_label = msg.channel
    
    # Format args compactly
    args_str = str(msg.last_args) if msg.last_args else ""
    if len(args_str) > 40:
        args_str = args_str[:37] + "..."
    
    # Count indicator
    count_str = f" [dim]×{msg.count}[/]" if msg.count > 1 else ""
    
    color = color_by_osc_channel(msg.address)
    return f"[dim]{time_str}[/] [{ch_color}]{ch_label:>4}[/] [{color}]{msg.address}[/] {args_str}{count_str}"

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
            'keywords': [str(k) for k in (analysis.get('keywords') or []) if str(k).strip()][:8],
            'themes': [str(t) for t in (analysis.get('themes') or []) if str(t).strip()][:4],
            'refrain_lines': [str(r) for r in (analysis.get('refrain_lines') or []) if str(r).strip()][:3],
            'visuals': [str(v) for v in (analysis.get('visual_adjectives') or []) if str(v).strip()][:5],
            'tempo': analysis.get('tempo'),
            'emotions': [str(e) for e in (analysis.get('emotions') or []) if str(e).strip()][:3]
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
# PROCESS MONITOR - Lightweight CPU/memory tracking with cached handles
# ============================================================================

@dataclass
class ProcessStats:
    """Statistics for a single process."""
    pid: int
    name: str
    cpu_percent: float
    memory_mb: float
    running: bool = True


class ProcessMonitor:
    """
    Efficient process monitor that caches Process handles.
    Call get_stats() periodically (e.g., every 5 seconds) for low overhead.
    Uses non-blocking cpu_percent(interval=None) which compares to last call.
    """
    
    def __init__(self, process_names: List[str]):
        self.targets = {n.lower(): n for n in process_names}
        self._cache: Dict[str, psutil.Process] = {}
    
    def _find_process(self, target_key: str) -> Optional[psutil.Process]:
        """Find or return cached process handle."""
        # Check cache first
        if target_key in self._cache:
            try:
                proc = self._cache[target_key]
                if proc.is_running():
                    return proc
            except (psutil.NoSuchProcess, psutil.AccessDenied):
                pass
            del self._cache[target_key]
        
        # Search for process by name
        for proc in psutil.process_iter(['pid', 'name']):
            try:
                pname = proc.info['name'].lower()
                if target_key in pname or pname in target_key:
                    self._cache[target_key] = proc
                    # Initialize CPU tracking (first call always returns 0)
                    try:
                        proc.cpu_percent()
                    except (psutil.NoSuchProcess, psutil.AccessDenied):
                        pass
                    return proc
            except (psutil.NoSuchProcess, psutil.AccessDenied):
                continue
        return None
    
    def get_stats(self) -> Dict[str, Optional[ProcessStats]]:
        """
        Get stats for all tracked processes.
        Returns dict mapping original name -> ProcessStats or None if not running.
        """
        results = {}
        for target_key, original_name in self.targets.items():
            proc = self._find_process(target_key)
            if proc:
                try:
                    stats = ProcessStats(
                        pid=proc.pid,
                        name=proc.name(),
                        cpu_percent=proc.cpu_percent(interval=None),  # Non-blocking
                        memory_mb=proc.memory_info().rss / (1024 * 1024),
                        running=True
                    )
                    results[original_name] = stats
                except (psutil.NoSuchProcess, psutil.AccessDenied):
                    results[original_name] = None
            else:
                results[original_name] = None
        return results


# ============================================================================
# STARTUP CONTROL PANEL - Configurable auto-start with resource display
# ============================================================================

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
            yield Checkbox("KaraokeOverlay", self.settings.start_karaoke_overlay, id="chk-karaoke-overlay")
            yield Checkbox("Auto-restart", self.settings.autorestart_karaoke_overlay, id="chk-ar-karaoke-overlay")
            yield Static("", id="stat-karaoke-overlay", classes="stat-label")
        
        with Horizontal(classes="startup-row"):
            yield Checkbox("LM Studio", self.settings.start_lmstudio, id="chk-lmstudio")
            yield Checkbox("Auto-restart", self.settings.autorestart_lmstudio, id="chk-ar-lmstudio")
            yield Static("", id="stat-lmstudio", classes="stat-label")
        
        with Horizontal(classes="startup-row"):
            yield Checkbox("Music Monitor", self.settings.start_music_monitor, id="chk-music-monitor")
            yield Checkbox("Auto-restart", self.settings.autorestart_music_monitor, id="chk-ar-music-monitor")
            yield Static("", id="stat-music-monitor", classes="stat-label")
        
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
            "chk-karaoke-overlay": "start_karaoke_overlay",
            "chk-lmstudio": "start_lmstudio",
            "chk-music-monitor": "start_music_monitor",
            "chk-magic": "start_magic",
            "chk-ar-synesthesia": "autorestart_synesthesia",
            "chk-ar-karaoke-overlay": "autorestart_karaoke_overlay",
            "chk-ar-lmstudio": "autorestart_lmstudio",
            "chk-ar-music-monitor": "autorestart_music_monitor",
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
        
        # KaraokeOverlay stats (Processing/Java)
        try:
            label = self.query_one("#stat-karaoke-overlay", Static)
            ko_stats = stats.get("java") or stats.get("Java")
            if ko_stats and ko_stats.running:
                label.update(f"[green]● {ko_stats.cpu_percent:.0f}% / {ko_stats.memory_mb:.0f}MB[/]")
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
        
        # Music Monitor stats
        try:
            label = self.query_one("#stat-music-monitor", Static)
            # Music Monitor runs in the same process, check if karaoke_engine exists
            app = self.app if hasattr(self, 'app') else None
            if app and hasattr(app, 'karaoke_engine') and app.karaoke_engine is not None:
                label.update("[green]● Running[/]")
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


OSC_AUTO_STOP_SECONDS = 60  # Auto-stop OSC after 1 minute


class OSCControlPanel(Static):
    """
    Panel for controlling OSC hub - start/stop and status display.
    
    Shows channel configuration and allows user to start/stop OSC services.
    Auto-stops after 1 minute to save resources.
    """
    
    # Reactive state
    osc_running = reactive(False)
    channel_status = reactive({})
    time_remaining = reactive(0)  # Seconds until auto-stop
    
    def compose(self) -> ComposeResult:
        yield Static("[bold]OSC Hub Control[/bold]", classes="section-title")
        with Horizontal(classes="startup-buttons"):
            yield Button("▶ Start OSC", id="btn-osc-start", variant="success")
            yield Button("■ Stop OSC", id="btn-osc-stop", variant="error")
            yield Button("⟳ Clear Log", id="btn-osc-clear", variant="default")
        yield Static("", id="osc-status-label")
        yield Static("", id="osc-channels-label")
    
    def on_mount(self) -> None:
        self._update_display()
    
    def watch_osc_running(self, running: bool) -> None:
        self._update_display()
    
    def watch_channel_status(self, status: dict) -> None:
        self._update_display()
    
    def watch_time_remaining(self, seconds: int) -> None:
        self._update_display()
    
    def _update_display(self) -> None:
        if not self.is_mounted:
            return
        
        # Status label with countdown
        try:
            status_label = self.query_one("#osc-status-label", Static)
            if self.osc_running:
                if self.time_remaining > 0:
                    status_label.update(f"[green]● OSC Hub Running[/green] [dim](auto-stop in {self.time_remaining}s)[/dim]")
                else:
                    status_label.update("[green]● OSC Hub Running[/green]")
            else:
                status_label.update("[dim]○ OSC Hub Stopped[/dim]")
        except Exception:
            pass
        
        # Channel details
        try:
            channels_label = self.query_one("#osc-channels-label", Static)
            if self.channel_status:
                lines = ["\n[bold]Channels:[/bold]"]
                for key, ch in self.channel_status.items():
                    active = "[green]●[/]" if ch.get("active") else "[dim]○[/]"
                    recv = f", recv={ch.get('recv_port')}" if ch.get('recv_port') else ""
                    lines.append(f"  {active} {ch.get('name', key)}: send={ch.get('send_port')}{recv}")
                channels_label.update("\n".join(lines))
            else:
                channels_label.update("\n[dim]Configure and start OSC to see channels[/dim]")
        except Exception:
            pass
    
    def on_button_pressed(self, event: Button.Pressed) -> None:
        if event.button.id == "btn-osc-start":
            self.post_message(OSCStartRequested())
        elif event.button.id == "btn-osc-stop":
            self.post_message(OSCStopRequested())
        elif event.button.id == "btn-osc-clear":
            self.post_message(OSCClearRequested())


class OSCStartRequested(Message):
    """Message posted when user requests to start OSC."""
    pass


class OSCStopRequested(Message):
    """Message posted when user requests to stop OSC."""
    pass


class OSCClearRequested(Message):
    """Message posted when user requests to clear OSC log."""
    pass


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
    
class PlaybackSourceChanged(Message):
    """Message posted when playback source is changed."""
    def __init__(self, source_key: str):
        super().__init__()
        self.source_key = source_key


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
    
    /* Startup control panel */
    #startup-control {
        padding: 1;
        border: solid $success;
        margin-bottom: 1;
    }
    
    /* OSC control panel */
    #osc-control {
        padding: 1;
        border: solid $warning;
        margin-bottom: 1;
        height: auto;
    }
    
    #osc-control .startup-buttons {
        height: auto;
        padding: 0;
        margin-bottom: 1;
    }
    
    #osc-control Button {
        margin-right: 1;
    }
    
    .startup-row {
        height: auto;
        padding: 0;
        margin: 0 0 1 0;
    }
    
    .startup-row Checkbox {
        width: auto;
        margin-right: 2;
    }
    
    .stat-label {
        width: 1fr;
        text-align: right;
    }
    
    .startup-buttons {
        height: auto;
        padding-top: 1;
    }
    
    .startup-buttons Button {
        margin-right: 1;
    }
    
    .section-title {
        margin-bottom: 1;
    }
    
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
        Binding("6", "screen_midi", "MIDI"),
        Binding("7", "screen_shaders", "Shaders"),
        Binding("s", "toggle_synesthesia", "Synesthesia"),
        Binding("m", "toggle_milksyphon", "MilkSyphon"),        Binding("k,up", "nav_up", "Up"),
        Binding("j,down", "nav_down", "Down"),
        Binding("enter", "select_app", "Select"),
        Binding("plus,equals", "timing_up", "+Timing"),
        Binding("minus", "timing_down", "-Timing"),
        # Shader analysis bindings (active on shaders tab)
        Binding("p", "shader_toggle_analysis", "Pause/Resume Analysis", show=False),
        Binding("slash", "shader_search_mood", "Search by Mood", show=False),
        Binding("e", "shader_search_energy", "Search by Energy", show=False),
        Binding("R", "shader_rescan", "Rescan Shaders", show=False),
    ]

    current_tab = reactive("master")
    synesthesia_running = reactive(False)
    milksyphon_running = reactive(False)
    lmstudio_running = reactive(False)
    karaoke_overlay_running = reactive(False)

    def __init__(self):
        super().__init__()
        
        # Persistent settings (includes startup preferences)
        self.settings = Settings()
        
        # Process manager for Processing apps
        self.process_manager = ProcessManager()
        self.process_manager.discover_apps(self._find_project_root())
        
        # Process monitor for CPU/memory tracking
        self.process_monitor = ProcessMonitor([
            "Synesthesia",
            "LM Studio",
            "Magic",
            "java",  # Processing apps run as Java
        ])
        
        self.karaoke_engine: Optional[KaraokeEngine] = None
        self._logs: List[str] = []
        self._last_master_status: Optional[Dict[str, Any]] = None
        self._latest_snapshot: Optional[PlaybackSnapshot] = None
        self._lmstudio_status: Dict[str, Any] = {}  # Tracks model availability
        
        # Launchpad controller (replaces MIDI Router)
        self.launchpad_manager: Optional['LaunchpadManager'] = None
        self._setup_launchpad()
        
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
    
    def _setup_launchpad(self) -> None:
        """Initialize Launchpad controller."""
        if not LAUNCHPAD_LIB_AVAILABLE or LaunchpadManager is None:
            logger.info("Launchpad library not available - skipping")
            return
        
        try:
            self.launchpad_manager = LaunchpadManager(
                osc_send_port=7777,
                osc_receive_port=9999,
            )
            # Set callback for state changes (will be called from background thread)
            self.launchpad_manager.set_state_callback(self._on_launchpad_state_change)
            
            # Start the manager (non-blocking - runs in background thread)
            if self.launchpad_manager.start():
                logger.info("Launchpad manager started")
            else:
                logger.warning("Launchpad manager start failed")
                
        except Exception as e:
            logger.warning(f"Launchpad initialization failed: {e}")
            self.launchpad_manager = None
    
    def _on_launchpad_state_change(self, state) -> None:
        """Handle Launchpad state change (called from background thread)."""
        # Use call_from_thread to safely update UI from background thread
        self.call_from_thread(self._update_launchpad_panels)
    
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
                self.setLevel(logging.DEBUG)  # Capture all levels
            
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
        root_logger = logging.getLogger()
        root_logger.setLevel(logging.DEBUG)  # Ensure root accepts all levels
        root_logger.addHandler(handler)
        
        # Log startup message to verify capture works
        logger.info("VJ Console started - logging active")

    def compose(self) -> ComposeResult:
        yield Header(show_clock=True)
        
        with TabbedContent(id="screens"):
            # Tab 1: Master Control
            with TabPane("1️⃣ Master Control", id="master"):
                with Horizontal():
                    with VerticalScroll(id="left-col"):
                        yield StartupControlPanel(self.settings, id="startup-control")
                        yield PlaybackSourcePanel(self.settings, id="playback-source", classes="panel")
                        yield MasterControlPanel(id="master-ctrl", classes="panel")
                        yield AppsListPanel(id="apps", classes="panel")
                        yield ServicesPanel(id="services", classes="panel")
                    with VerticalScroll(id="right-col"):
                        yield NowPlayingPanel(id="now-playing", classes="panel")
                        yield CategoriesPanel(id="categories", classes="panel")
                        yield PipelinePanel(id="pipeline", classes="panel")

            # Tab 2: OSC View
            with TabPane("2️⃣ OSC View", id="osc"):
                yield OSCControlPanel(id="osc-control")
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
            
            # Tab 5: Launchpad Controller
            with TabPane("5️⃣ Launchpad", id="launchpad"):
                with Horizontal():
                    with VerticalScroll(id="left-col"):
                        if LAUNCHPAD_LIB_AVAILABLE and LaunchpadStatusPanel:
                            yield LaunchpadStatusPanel(id="lp-status", classes="panel")
                            yield LaunchpadPadsPanel(id="lp-pads", classes="panel")
                        else:
                            yield Static("[dim]launchpad_osc_lib not available[/]", classes="panel")
                    with VerticalScroll(id="right-col"):
                        if LAUNCHPAD_LIB_AVAILABLE and LaunchpadInstructionsPanel:
                            yield LaunchpadInstructionsPanel(id="lp-instructions", classes="panel")
                            yield LaunchpadTestsPanel(id="lp-tests", classes="panel")
                            yield LaunchpadOscDebugPanel(id="lp-osc", classes="panel full-height")
                        else:
                            yield Static("[dim]Connect Launchpad and restart[/]", classes="panel")
            
            # Tab 6: Shader Indexer
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
        
        # NOTE: OSC is NOT started by default - user controls via OSC View tab
        # Use the OSC Control panel to start/stop OSC services
        
        # Initialize apps list
        self.query_one("#apps", AppsListPanel).apps = self.process_manager.apps
        self.process_manager.start_monitoring(daemon_mode=True)
        
        # NOTE: No auto-start by default - user controls via StartupControlPanel
        # Services are started only when "Start All" button is pressed
        # or when auto-restart is enabled and service is not running
        
        # Background updates - stagger intervals to reduce CPU spikes
        self.set_interval(0.5, self._update_data)
        self.set_interval(1.0, self._tick_osc_auto_stop)  # OSC auto-stop countdown
        self.set_interval(5.0, self._check_apps_and_autorestart)  # Combined check + restart
        
        # Initialize OSC auto-stop timer
        self._osc_auto_stop_remaining = 0

    def on_osc_start_requested(self, message: OSCStartRequested) -> None:
        """Handle OSC start request from OSCControlPanel."""
        if not osc.is_started:
            osc.start()
            osc_monitor.start()
            # Log the port bindings for visibility
            status = osc.get_channel_status()
            for key, ch in status.items():
                recv_info = f", recv={ch.get('recv_port')}" if ch.get('recv_port') else ""
                logger.info(f"OSC {ch.get('name', key)}: send={ch.get('send_port')}{recv_info}")
            logger.info(f"OSC Hub started (auto-stop in {OSC_AUTO_STOP_SECONDS}s)")
        # Reset auto-stop timer
        self._osc_auto_stop_remaining = OSC_AUTO_STOP_SECONDS
        self._update_osc_control_panel()
    
    def on_osc_stop_requested(self, message: OSCStopRequested) -> None:
        """Handle OSC stop request from OSCControlPanel."""
        self._osc_auto_stop_remaining = 0
        if osc_monitor.is_started:
            osc_monitor.stop()
        if osc.is_started:
            osc.stop()
            logger.info("OSC Hub stopped by user")
        self._update_osc_control_panel()
    
    def on_osc_clear_requested(self, message: OSCClearRequested) -> None:
        """Handle OSC clear request from OSCControlPanel."""
        osc_monitor.clear()
        logger.info("OSC message log cleared")
    
    def _update_osc_control_panel(self) -> None:
        """Update the OSC control panel with current status."""
        try:
            panel = self.query_one("#osc-control", OSCControlPanel)
            panel.osc_running = osc.is_started
            panel.channel_status = osc.get_channel_status() if osc.is_started else {}
            panel.time_remaining = getattr(self, '_osc_auto_stop_remaining', 0)
        except Exception:
            pass
    
    def _tick_osc_auto_stop(self) -> None:
        """Called every second to decrement OSC auto-stop timer."""
        if not hasattr(self, '_osc_auto_stop_remaining'):
            self._osc_auto_stop_remaining = 0
        
        if self._osc_auto_stop_remaining > 0 and osc.is_started:
            self._osc_auto_stop_remaining -= 1
            self._update_osc_control_panel()
            
            if self._osc_auto_stop_remaining <= 0:
                # Auto-stop triggered
                if osc_monitor.is_started:
                    osc_monitor.stop()
                if osc.is_started:
                    osc.stop()
                    logger.info("OSC Hub auto-stopped after 60s")
                self._update_osc_control_panel()

    def on_button_pressed(self, event: Button.Pressed) -> None:
        """Route button clicks to actions."""
        button_id = event.button.id
        
        # Startup control buttons
        if button_id == "btn-start-all":
            self._start_selected_services()
            return
        
        if button_id == "btn-stop-all":
            self._stop_all_services()
            return
        
        # Launchpad test buttons
        if button_id and button_id.startswith("test-"):
            test_name = button_id.replace("test-", "")
            if self.launchpad_manager:
                result = self.launchpad_manager.run_test(test_name)
                try:
                    tests_panel = self.query_one("#lp-tests", LaunchpadTestsPanel)
                    tests_panel.test_status = {'result': result}
                except Exception:
                    pass
            return
        
        # Shader buttons
        if button_id == "shader-pause-resume":
            self.action_shader_toggle_analysis()
        elif button_id == "shader-search-mood":
            self.action_shader_search_mood()
        elif button_id == "shader-search-energy":
            self.action_shader_search_energy()
        elif button_id == "shader-search-text":
            self.action_shader_search_text()
        elif button_id == "shader-rescan":
            self.action_shader_rescan()

    def on_playback_source_changed(self, event: PlaybackSourceChanged) -> None:
        """Handle playback source change from radio buttons."""
        if self.karaoke_engine:
            self.karaoke_engine.set_playback_source(event.source_key)
            self._logs.append(f"Switched playback source to: {event.source_key}")

    # === Actions (impure, side effects) ===
    
    def _start_karaoke(self) -> None:
        """Start the karaoke engine."""
        if self.karaoke_engine is not None:
            return  # Already running
        try:
            self.karaoke_engine = KaraokeEngine()
            # Activate the selected playback source if one is configured
            source = self.settings.playback_source
            if source:
                self.karaoke_engine.set_playback_source(source)
            self.karaoke_engine.start()
            logger.info("Karaoke engine started")
        except Exception as e:
            logger.exception(f"Karaoke start error: {e}")
    
    def _run_process(self, cmd: List[str], timeout: int = 2) -> bool:
        """Run a subprocess, return True if successful."""
        try:
            result = subprocess.run(cmd, capture_output=True, timeout=timeout)
            return result.returncode == 0
        except Exception:
            return False

    # =========================================================================
    # SERVICE DETECTION METHODS
    # =========================================================================
    
    def _is_synesthesia_running(self) -> bool:
        """Check if Synesthesia is running."""
        return self._run_process(['pgrep', '-x', 'Synesthesia'], 1)
    
    def _is_karaoke_overlay_running(self) -> bool:
        """Check if KaraokeOverlay Processing app is running."""
        for app in self.process_manager.apps:
            if 'karaoke' in app.name.lower():
                if self.process_manager.is_running(app):
                    return True
        return False
    
    def _is_lmstudio_running(self) -> bool:
        """Check if LM Studio process is running."""
        return self._run_process(['pgrep', '-f', 'LM Studio'], 1)
    
    def _check_lmstudio_model(self) -> Dict[str, Any]:
        """Check LM Studio API and model status. Returns status dict."""
        try:
            resp = requests.get("http://localhost:1234/v1/models", timeout=1)
            if resp.status_code == 200:
                models = resp.json().get('data', [])
                if models:
                    model_id = models[0].get('id', 'unknown')
                    return {'available': True, 'model': model_id, 'warning': ''}
                else:
                    return {'available': False, 'model': '', 'warning': 'No model loaded'}
        except Exception:
            pass
        return {'available': False, 'model': '', 'warning': ''}
    
    def _is_music_monitor_running(self) -> bool:
        """Check if Music Monitor (Karaoke Engine) is running."""
        return self.karaoke_engine is not None
    
    def _is_magic_running(self) -> bool:
        """Check if Magic Music Visuals is running."""
        return self._run_process(['pgrep', '-x', 'Magic'], 1)
    
    # =========================================================================
    # SERVICE LAUNCHER METHODS
    # =========================================================================
    
    def _start_synesthesia(self) -> bool:
        """Start Synesthesia app. Returns True if launched."""
        if self._is_synesthesia_running():
            logger.debug("Synesthesia already running")
            return True
        try:
            subprocess.Popen(['open', '-a', 'Synesthesia'])
            logger.info("Started Synesthesia")
            return True
        except Exception as e:
            logger.error(f"Failed to start Synesthesia: {e}")
            return False
    
    def _start_karaoke_overlay(self) -> bool:
        """Start KaraokeOverlay Processing app. Returns True if launched."""
        if self._is_karaoke_overlay_running():
            logger.debug("KaraokeOverlay already running")
            return True
        
        # Validate processing-java is available
        if not self._run_process(['which', 'processing-java'], 2):
            logger.error("processing-java not found in PATH. Install Processing and add to PATH.")
            self.notify("processing-java not found! Install Processing and add to PATH.", severity="error")
            return False
        
        # Find and launch KaraokeOverlay
        for app in self.process_manager.apps:
            if 'karaoke' in app.name.lower():
                if self.process_manager.launch_app(app):
                    logger.info(f"Started {app.name}")
                    return True
                else:
                    logger.error(f"Failed to launch {app.name}")
                    return False
        
        logger.error("KaraokeOverlay app not found in processing-vj/src/")
        return False
    
    def _start_lmstudio(self) -> bool:
        """Start LM Studio app. Returns True if launched."""
        if self._is_lmstudio_running():
            logger.debug("LM Studio already running")
            return True
        try:
            subprocess.Popen(['open', '-a', 'LM Studio'])
            logger.info("Started LM Studio (user must load a model)")
            self.notify("LM Studio started - please load a model manually", severity="information")
            return True
        except Exception as e:
            logger.error(f"Failed to start LM Studio: {e}")
            return False
    
    def _start_magic(self) -> bool:
        """Start Magic Music Visuals app. Returns True if launched."""
        if self._is_magic_running():
            logger.debug("Magic already running")
            return True
        
        try:
            # Check if a specific .magic file should be loaded
            magic_file = self.settings.magic_file_path
            if magic_file and Path(magic_file).exists():
                # Open Magic with specific file
                subprocess.Popen(['open', '-a', 'Magic', magic_file])
                logger.info(f"Started Magic with file: {magic_file}")
                self.notify(f"Magic started with {Path(magic_file).name}", severity="information")
            else:
                # Open Magic without file
                subprocess.Popen(['open', '-a', 'Magic'])
                logger.info("Started Magic Music Visuals")
            return True
        except Exception as e:
            logger.error(f"Failed to start Magic: {e}")
            return False
    
    def _start_selected_services(self) -> None:
        """Start all services that have checkboxes enabled."""
        started = []
        
        if self.settings.start_synesthesia:
            if self._start_synesthesia():
                started.append("Synesthesia")
        
        if self.settings.start_karaoke_overlay:
            if self._start_karaoke_overlay():
                started.append("KaraokeOverlay")
        
        if self.settings.start_lmstudio:
            if self._start_lmstudio():
                started.append("LM Studio")
        
        if self.settings.start_music_monitor:
            self._start_karaoke()
            if self.karaoke_engine:
                started.append("Music Monitor")
        
        if self.settings.start_magic:
            if self._start_magic():
                started.append("Magic")
        
        if started:
            self.notify(f"Started: {', '.join(started)}", severity="information")
        else:
            self.notify("No services selected to start", severity="warning")
        
        # Refresh status immediately
        self._check_apps_and_autorestart()
    
    def _stop_all_services(self) -> None:
        """Stop all running services."""
        stopped = []
        
        # Stop Synesthesia
        if self._is_synesthesia_running():
            try:
                subprocess.run(['pkill', '-x', 'Synesthesia'], check=False)
                stopped.append("Synesthesia")
            except Exception as e:
                logger.error(f"Failed to stop Synesthesia: {e}")
        
        # Stop KaraokeOverlay (Processing java apps)
        if self._is_karaoke_overlay_running():
            try:
                # Stop via ProcessManager
                for app in self.process_manager.apps:
                    if 'karaoke' in app.name.lower() and self.process_manager.is_running(app):
                        self.process_manager.stop_app(app)
                        stopped.append("KaraokeOverlay")
                        break
            except Exception as e:
                logger.error(f"Failed to stop KaraokeOverlay: {e}")
        
        # Stop LM Studio
        if self._is_lmstudio_running():
            try:
                subprocess.run(['pkill', '-f', 'LM Studio'], check=False)
                stopped.append("LM Studio")
            except Exception as e:
                logger.error(f"Failed to stop LM Studio: {e}")
        
        # Stop Music Monitor (Karaoke Engine)
        if self.karaoke_engine:
            try:
                self.karaoke_engine.stop()
                self.karaoke_engine = None
                stopped.append("Music Monitor")
            except Exception as e:
                logger.error(f"Failed to stop Music Monitor: {e}")
        
        # Stop Magic Music Visuals
        if self._is_magic_running():
            try:
                subprocess.run(['pkill', '-x', 'Magic'], check=False)
                stopped.append("Magic")
            except Exception as e:
                logger.error(f"Failed to stop Magic: {e}")
        
        if stopped:
            self.notify(f"Stopped: {', '.join(stopped)}", severity="information")
        else:
            self.notify("No services were running", severity="warning")
        
        # Clear process monitor cache
        self.process_monitor = ProcessMonitor([
            "Synesthesia",
            "LM Studio",
            "Magic",
            "java",  # Processing apps run as Java
        ])
        
        # Refresh status immediately
        self._check_apps_and_autorestart()

    # =========================================================================
    # COMBINED CHECK AND AUTO-RESTART
    # =========================================================================
    
    def _check_apps_and_autorestart(self) -> None:
        """Check running status of external apps and auto-restart if enabled."""
        # Update running status
        self.synesthesia_running = self._is_synesthesia_running()
        self.milksyphon_running = self._run_process(['pgrep', '-f', 'projectMilkSyphon'], 1)
        self.lmstudio_running = self._is_lmstudio_running()
        self.karaoke_overlay_running = self._is_karaoke_overlay_running()
        self.magic_running = self._is_magic_running()
        
        # Check LM Studio model status
        self._lmstudio_status = self._check_lmstudio_model()
        
        # Get process stats for resource monitoring
        process_stats = self.process_monitor.get_stats()
        
        # Add KaraokeEngine stats (self process)
        try:
            self_proc = psutil.Process()
            process_stats["KaraokeEngine"] = ProcessStats(
                pid=self_proc.pid,
                name="KaraokeEngine",
                cpu_percent=self_proc.cpu_percent(interval=None),
                memory_mb=self_proc.memory_info().rss / (1024 * 1024),
                running=self.karaoke_engine is not None
            )
        except Exception:
            pass
        
        # Update startup panel with stats
        try:
            startup_panel = self.query_one("#startup-control", StartupControlPanel)
            startup_panel.stats_data = process_stats
            startup_panel.lmstudio_status = self._lmstudio_status
        except Exception:
            pass
        
        # Auto-restart logic
        if self.settings.autorestart_synesthesia and not self.synesthesia_running:
            logger.info("Auto-restarting Synesthesia")
            self._start_synesthesia()
        
        if self.settings.autorestart_karaoke_overlay and not self.karaoke_overlay_running:
            logger.info("Auto-restarting KaraokeOverlay")
            self._start_karaoke_overlay()
        
        if self.settings.autorestart_lmstudio and not self.lmstudio_running:
            logger.info("Auto-restarting LM Studio")
            self._start_lmstudio()
        
        if self.settings.autorestart_music_monitor and not self._is_music_monitor_running():
            logger.info("Auto-restarting Music Monitor")
            self._start_karaoke()
        
        if self.settings.autorestart_magic and not self.magic_running:
            logger.info("Auto-restarting Magic")
            self._start_magic()
        
        # Update services panel
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
        # Always update logs panel (even without karaoke engine)
        try:
            self.query_one("#logs-panel", LogsPanel).logs = list(self._logs)
        except Exception:
            pass
        
        # Always update OSC panels (even without karaoke engine)
        self._update_osc_control_panel()
        try:
            panel = self.query_one("#osc-full", OSCPanel)
            panel.osc_running = osc.is_started
            panel.full_view = True
            if osc_monitor.is_started:
                panel.messages = osc_monitor.get_aggregated(50)
        except Exception:
            pass
        
        # Update master control even if karaoke engine is not running
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
        
        # If no karaoke engine, show waiting message and return
        if not self.karaoke_engine:
            try:
                self.query_one("#now-playing", NowPlayingPanel).track_data = {}
            except Exception:
                pass
            # Update playback source panel to show not running
            try:
                source_panel = self.query_one("#playback-source", PlaybackSourcePanel)
                source_panel.monitor_running = False
                source_panel.lookup_ms = 0.0
            except Exception:
                pass
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
        
        # Update playback source panel with lookup time and running state
        try:
            source_panel = self.query_one("#playback-source", PlaybackSourcePanel)
            source_panel.lookup_ms = self.karaoke_engine.last_lookup_ms
            # Monitor is running if karaoke engine exists and has a source
            source_panel.monitor_running = bool(self.karaoke_engine.playback_source)
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

        # Send OSC status only when it changes (only if OSC is running and karaoke engine exists)
        if self.karaoke_engine:
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
        
        # Update Launchpad panels
        self._update_launchpad_panels()
        
        # Update audio analyzer panels
        
        # Update shader panels
        self._update_shader_panels()

    def _update_shader_panels(self) -> None:
        """Update shader indexer/matcher panels."""
        if not SHADER_MATCHER_AVAILABLE or not self.shader_indexer:
            return
        
        try:
            # Use cached stats (fast) - only rescan when explicitly requested
            stats = self.shader_indexer.get_stats(use_cache=True)
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
    
    def _update_launchpad_panels(self) -> None:
        """Update Launchpad controller panels."""
        if not LAUNCHPAD_LIB_AVAILABLE or not self.launchpad_manager:
            return
        
        try:
            # Update status panel
            try:
                status_panel = self.query_one("#lp-status", LaunchpadStatusPanel)
                status_panel.status = self.launchpad_manager.get_status()
            except Exception:
                pass
            
            # Update pads panel
            try:
                pads_panel = self.query_one("#lp-pads", LaunchpadPadsPanel)
                pads_panel.pads_data = self.launchpad_manager.get_pads_data()
            except Exception:
                pass
            
            # Update instructions panel (based on current phase)
            try:
                status = self.launchpad_manager.get_status()
                instructions_panel = self.query_one("#lp-instructions", LaunchpadInstructionsPanel)
                instructions_panel.phase = status.get('phase', 'IDLE')
            except Exception:
                pass
            
            # Update OSC debug panel
            try:
                osc_panel = self.query_one("#lp-osc", LaunchpadOscDebugPanel)
                osc_panel.messages = self.launchpad_manager.get_osc_messages()
            except Exception:
                pass
            
        except Exception as e:
            logger.debug(f"Failed to update Launchpad panels: {e}")

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
        """Switch to Launchpad screen (kept as 'midi' for key binding compat)."""
        self.query_one("#screens", TabbedContent).active = "launchpad"
    
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
            # Invalidate stats cache to force fresh directory scan
            if self.shader_indexer:
                self.shader_indexer.invalidate_stats_cache()
            self.notify("Rescanning for unanalyzed shaders...", severity="information")
        else:
            self.notify("Shader analysis worker not available", severity="warning")
    
    def action_nav_up(self) -> None:
        current_screen = self.query_one("#screens", TabbedContent).active
        
        if current_screen == "master":
            panel = self.query_one("#apps", AppsListPanel)
            if panel.selected > 0:
                panel.selected -= 1

    def action_nav_down(self) -> None:
        current_screen = self.query_one("#screens", TabbedContent).active
        
        if current_screen == "master":
            panel = self.query_one("#apps", AppsListPanel)
            if panel.selected < len(self.process_manager.apps) - 1:
                panel.selected += 1

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

    def action_timing_up(self) -> None:
        if self.karaoke_engine:
            self.karaoke_engine.adjust_timing(+200)

    def action_timing_down(self) -> None:
        if self.karaoke_engine:
            self.karaoke_engine.adjust_timing(-200)
    
    def _log(self, message: str):
        """Add a message to logs."""
        self._logs.append(f"{time.strftime('%Y-%m-%d %H:%M:%S')} - vj_console - INFO - {message}")
        if len(self._logs) > 500:
            self._logs.pop(0)

    def on_unmount(self) -> None:
        if self.karaoke_engine:
            self.karaoke_engine.stop()
        if self.launchpad_manager:
            self.launchpad_manager.stop()
        self.process_manager.cleanup()


def main():
    VJConsoleApp().run()


if __name__ == '__main__':
    main()
