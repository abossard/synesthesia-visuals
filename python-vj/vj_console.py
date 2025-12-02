#!/usr/bin/env python3
"""
VJ Console - Textual Edition with Multi-Screen Support

Screens (press 1-5 to switch):
1. Master Control - Main dashboard with all controls
2. OSC View - Full OSC message debug view  
3. Song AI Debug - Song categorization and pipeline details
4. All Logs - Complete application logs
5. MIDI Router - Toggle management and MIDI traffic debug
"""

from dotenv import load_dotenv
load_dotenv(override=True, verbose=True) 

from pathlib import Path
from typing import Optional, List, Dict, Tuple, Any
import logging
import subprocess
import time

from textual.app import App, ComposeResult
from textual.containers import Container, Horizontal, VerticalScroll
from textual.widgets import Header, Footer, Static, TabbedContent, TabPane, Input
from textual.reactive import reactive
from textual.binding import Binding
from textual.screen import ModalScreen
from rich.text import Text

from process_manager import ProcessManager, ProcessingApp
from karaoke_engine import KaraokeEngine, Config as KaraokeConfig, SongCategories, get_active_line_index
from midi_console import MidiTogglesPanel, MidiActionsPanel, MidiDebugPanel, MidiStatusPanel
from midi_router import MidiRouter, ConfigManager
from midi_domain import RouterConfig, DeviceConfig

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
    if score >= 0.7: return "green"
    if score >= 0.4: return "yellow"
    return "dim"

def color_by_level(text: str) -> str:
    """Get color based on log level in text."""
    if "ERROR" in text or "EXCEPTION" in text: return "red"
    if "WARNING" in text: return "yellow"
    if "INFO" in text: return "green"
    return "dim"

def color_by_osc_channel(address: str) -> str:
    """Get color based on OSC address channel."""
    if "/karaoke/categories" in address: return "yellow"
    if "/vj/" in address: return "cyan"
    if "/karaoke/" in address: return "green"
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
        if not data.get('artist'):
            self.update("[dim]Waiting for playback...[/dim]")
            return
        
        conn = format_status_icon(data.get('connected', False), "● Connected", "◐ Connecting...")
        time_str = format_duration(data.get('position', 0), data.get('duration', 0))
        icon = "🎵" if data.get('source') == "spotify" else "🎧"
        
        self.update(
            f"Spotify: {conn}\n"
            f"[bold]Now Playing:[/] [cyan]{data.get('artist', '')}[/] — {data.get('title', '')}\n"
            f"{icon} {data.get('source', '').title()}  │  [dim]{time_str}[/]"
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
        syn = format_status_icon(self.status.get('synesthesia'), "● RUNNING", "○ stopped")
        pms = format_status_icon(self.status.get('milksyphon'), "● RUNNING", "○ stopped")
        kar = format_status_icon(self.status.get('karaoke'), "● ACTIVE", "○ inactive")
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
        Binding("5", "screen_midi", "MIDI"),
        Binding("s", "toggle_synesthesia", "Synesthesia"),
        Binding("m", "toggle_milksyphon", "MilkSyphon"),
        Binding("k,up", "nav_up", "Up"),
        Binding("j,down", "nav_down", "Down"),
        Binding("enter,space", "select_app", "Select"),
        Binding("plus,equals", "timing_up", "+Timing"),
        Binding("minus", "timing_down", "-Timing"),
        Binding("l", "midi_learn", "Learn", show=False),
        Binding("r", "midi_rename", "Rename", show=False),
        Binding("d", "midi_delete", "Delete", show=False),
    ]

    current_tab = reactive("master")
    synesthesia_running = reactive(False)
    milksyphon_running = reactive(False)
    midi_selected_toggle = reactive(0)

    def __init__(self):
        super().__init__()
        self.process_manager = ProcessManager()
        self.process_manager.discover_apps(self._find_project_root())
        self.karaoke_engine: Optional[KaraokeEngine] = None
        self._logs: List[str] = []
        self._last_master_status: Optional[Dict[str, Any]] = None
        
        # MIDI Router
        self.midi_router: Optional[MidiRouter] = None
        self.midi_messages: List[Tuple[float, str, Any]] = []  # (timestamp, direction, message)
        self._setup_midi_router()
        
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
    
    def _on_midi_message_callback(self, msg, direction: str):
        """Callback for MIDI message logging."""
        self.midi_messages.append((time.time(), direction, msg))
        # Keep only last 100 messages
        if len(self.midi_messages) > 100:
            self.midi_messages.pop(0)
    
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
            
            # Tab 5: MIDI Router
            with TabPane("5️⃣ MIDI Router", id="midi"):
                with Horizontal():
                    with VerticalScroll(id="left-col"):
                        yield MidiActionsPanel(id="midi-actions", classes="panel")
                        yield MidiStatusPanel(id="midi-status", classes="panel")
                    with VerticalScroll(id="right-col"):
                        yield MidiTogglesPanel(id="midi-toggles", classes="panel")
                        yield MidiDebugPanel(id="midi-debug", classes="panel full-height")

        yield Footer()

    def on_mount(self) -> None:
        self.title = "🎛 VJ Console"
        self.sub_title = "Press 1-5 to switch screens"
        
        # Initialize
        self.query_one("#apps", AppsListPanel).apps = self.process_manager.apps
        self.process_manager.start_monitoring(daemon_mode=True)
        self._start_karaoke()
        
        # Background updates
        self.set_interval(0.5, self._update_data)
        self.set_interval(2.0, self._check_apps)

    # === Actions (impure, side effects) ===
    
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
            }
        except Exception:
            pass

    def _update_data(self) -> None:
        """Update all panels with current data."""
        if not self.karaoke_engine:
            return
            
        state = self.karaoke_engine._state
        
        # Build track data
        track_data = {}
        if state.has_track:
            t = state.track
            is_connected = bool(
                self.karaoke_engine._spotify and 
                getattr(self.karaoke_engine._spotify, '_sp', None)
            )
            # Determine source from which monitor is active
            source = 'spotify' if is_connected else 'virtualdj'
            track_data = {
                'artist': t.artist, 
                'title': t.title, 
                'source': source,
                'position': state.position, 
                'duration': t.duration,
                'connected': is_connected
            }
        
        # Update now playing panel
        try:
            self.query_one("#now-playing", NowPlayingPanel).track_data = track_data
        except Exception:
            pass

        # Build categories data
        cats = self.karaoke_engine.current_categories
        cat_data = {}
        if cats:
            cat_data = {
                'primary_mood': cats.primary_mood, 
                'categories': [{'name': c.name, 'score': c.score} for c in cats.get_top(10)]
            }
        
        # Update categories panels
        for panel_id in ["categories", "categories-full"]:
            try:
                self.query_one(f"#{panel_id}", CategoriesPanel).categories_data = cat_data
            except Exception:
                pass

        # Update pipeline
        pipeline_data = {
            'display_lines': self.karaoke_engine.pipeline.get_display_lines(),
            'image_prompt': self.karaoke_engine.pipeline.image_prompt,
        }
        lines = self.karaoke_engine.current_lines
        if lines:
            offset_ms = self.karaoke_engine.timing_offset_ms
            idx = get_active_line_index(lines, state.position + offset_ms / 1000.0)
            if 0 <= idx < len(lines):
                line = lines[idx]
                pipeline_data['current_lyric'] = {'text': line.text, 'keywords': line.keywords, 'is_refrain': line.is_refrain}
        
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
                status_panel.config_info = {
                    'controller': self.midi_router.config.controller.name_pattern,
                    'virtual_port': self.midi_router.config.virtual_output.name_pattern,
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
    
    def action_screen_midi(self) -> None:
        self.query_one("#screens", TabbedContent).active = "midi"

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
        elif current_screen == "midi":
            # Toggle the selected MIDI toggle (for testing)
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
        self.process_manager.cleanup()


def main():
    VJConsoleApp().run()


if __name__ == '__main__':
    main()
