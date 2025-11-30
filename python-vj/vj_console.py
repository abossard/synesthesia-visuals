#!/usr/bin/env python3
"""
VJ Console - Textual Edition
Modern reactive terminal UI for controlling VJ Processing apps and Karaoke Engine.

Master control center for:
- Starting/stopping Synesthesia and ProjectMilkSyphon
- Song categorization (mood/theme) based on AI analysis
- OSC output monitoring for VJ layer control
- Processing app management
"""

from pathlib import Path
from typing import Optional, List, Dict
import logging
import subprocess
import time

from textual.app import App, ComposeResult
from textual.containers import Container, Horizontal, Vertical, VerticalScroll
from textual.widgets import Header, Footer, Static, Button
from textual.reactive import reactive
from textual.binding import Binding
from textual import work
from rich.text import Text

# Import existing VJ console components
from vj_console_blessed import ProcessManager, ProcessingApp
from karaoke_engine import KaraokeEngine, Config as KaraokeConfig, SongCategories

logger = logging.getLogger('vj_console')


class NowPlaying(Static):
    """Widget displaying current track info."""

    track_artist = reactive("")
    track_title = reactive("")
    track_source = reactive("")
    position_sec = reactive(0.0)
    duration_sec = reactive(0.0)
    is_connected = reactive(False)
    is_playing = reactive(False)

    def watch_track_artist(self, artist: str) -> None:
        """Update display when track changes."""
        self.update_display()

    def watch_track_title(self, title: str) -> None:
        """Update display when track changes."""
        self.update_display()

    def watch_position_sec(self, position: float) -> None:
        """Update display when position changes."""
        self.update_display()

    def update_display(self) -> None:
        """Render the now playing widget."""
        try:
            if not self.track_artist:
                self.update("[dim]Waiting for playback...[/dim]")
                return

            # Format playback time safely
            try:
                mins = int(self.position_sec // 60)
                secs = int(self.position_sec % 60)
                dur_mins = int(self.duration_sec // 60)
                dur_secs = int(self.duration_sec % 60)
                time_str = f"{mins}:{secs:02d} / {dur_mins}:{dur_secs:02d}"
            except (ValueError, TypeError):
                time_str = "0:00 / 0:00"

            # Source icon
            source_icon = "🎵" if self.track_source == "spotify" else "🎧"

            # Connection status
            conn_status = "[bold green]● Connected[/]" if self.is_connected else "[yellow]◐ Connecting...[/]"

            # Build display text
            text = Text()
            text.append(f"Spotify: {conn_status}\n")
            text.append("Now Playing: ", style="bold")
            text.append(f"{self.track_artist}", style="cyan")
            text.append(" — ", style="dim")
            text.append(f"{self.track_title}\n", style="white")
            text.append(f"{source_icon} {self.track_source.title()}  │  {time_str}", style="dim")

            self.update(text)

        except Exception as e:
            logger.exception(f"Error updating now playing display: {e}")
            self.update(f"[red]Error displaying track info[/]\n[dim]{str(e)}[/dim]")


class PipelineStatus(Static):
    """Widget displaying lyrics processing pipeline."""

    pipeline_data = reactive({})

    def watch_pipeline_data(self, data: dict) -> None:
        """Update display when pipeline changes."""
        try:
            if not data:
                self.update("[dim]No pipeline active[/dim]")
                return

            lines = []
            lines.append("[bold magenta]═══ Processing Pipeline ═══[/]\n")

            # Display pipeline steps
            for color, text in data.get('display_lines', []):
                if color == "green":
                    lines.append(f"[green]{text}[/]")
                elif color == "yellow":
                    lines.append(f"[yellow]{text}[/]")
                elif color == "red":
                    lines.append(f"[red]{text}[/]")
                else:
                    lines.append(f"[dim]{text}[/]")

            # Image prompt - handle both dict and string formats
            image_prompt = data.get('image_prompt')
            if image_prompt:
                lines.append("\n[bold cyan]═══ Image Prompt ═══[/]")

                # Handle dict format (from LLM with structure)
                if isinstance(image_prompt, dict):
                    prompt_text = image_prompt.get('description', str(image_prompt))
                # Handle string format (direct prompt)
                elif isinstance(image_prompt, str):
                    prompt_text = image_prompt
                else:
                    prompt_text = str(image_prompt)

                # Truncate if too long
                if len(prompt_text) > 200:
                    prompt_text = prompt_text[:200] + "..."

                lines.append(f"[cyan]{prompt_text}[/]")

            # Logs
            logs = data.get('logs', [])
            if logs:
                lines.append("\n[bold yellow]═══ Logs ═══[/]")
                for log in logs:
                    if isinstance(log, str):
                        lines.append(f"[dim]{log}[/]")

            # Current lyric
            current_lyric = data.get('current_lyric')
            if current_lyric and isinstance(current_lyric, dict):
                lyric_text = current_lyric.get('text', '')
                if lyric_text:
                    lines.append(f"\n[bold white]♪ {lyric_text}[/]")

                    keywords = current_lyric.get('keywords')
                    if keywords:
                        lines.append(f"[yellow]  Keywords: {keywords}[/]")

                    if current_lyric.get('is_refrain'):
                        lines.append("[magenta]  [REFRAIN][/]")

            self.update("\n".join(lines))

        except Exception as e:
            # Fallback to safe error message
            logger.exception(f"Error updating pipeline display: {e}")
            self.update(f"[red]Error displaying pipeline data[/]\n[dim]{str(e)}[/dim]")


class ProcessingAppsList(Static):
    """Widget displaying Processing apps."""

    apps = reactive([])
    selected_index = reactive(0)

    def watch_apps(self, apps: list) -> None:
        """Update display when apps change."""
        self.update_display()

    def watch_selected_index(self, index: int) -> None:
        """Update display when selection changes."""
        self.update_display()

    def update_display(self) -> None:
        """Render the apps list."""
        try:
            if not self.apps:
                self.update("[dim](no apps found)[/dim]")
                return

            lines = []
            lines.append("[bold magenta]═══ Processing Apps ═══[/]\n")

            for i, app in enumerate(self.apps):
                try:
                    is_selected = i == self.selected_index
                    is_running = hasattr(app, 'process') and app.process and app.process.poll() is None

                    prefix = " ▸ " if is_selected else "   "
                    status = " [bold green][running][/]" if is_running else ""

                    app_name = getattr(app, 'name', 'Unknown')

                    if is_selected:
                        lines.append(f"[black on cyan]{prefix}{app_name}{status}[/]")
                    else:
                        lines.append(f"{prefix}{app_name}{status}")
                except Exception as e:
                    logger.debug(f"Error rendering app {i}: {e}")
                    continue

            self.update("\n".join(lines))

        except Exception as e:
            logger.exception(f"Error updating apps list: {e}")
            self.update(f"[red]Error displaying apps[/]\n[dim]{str(e)}[/dim]")


class ServicesPanel(Static):
    """Widget displaying service status."""

    services_status = reactive({})

    def watch_services_status(self, status: dict) -> None:
        """Update display when service status changes."""
        try:
            lines = []
            lines.append("[bold blue]═══ Services ═══[/]\n")

            # Spotify
            if status.get('spotify_configured'):
                lines.append("[green]✓ Spotify API      Credentials configured[/]")
            else:
                lines.append("[dim]○ Spotify API      Set SPOTIPY_CLIENT_ID/SECRET in .env[/]")

            # VirtualDJ
            if status.get('virtualdj_found'):
                vdj_file = status.get('vdj_file', 'found')
                lines.append(f"[green]✓ VirtualDJ        {vdj_file}[/]")
            else:
                lines.append("[dim]○ VirtualDJ        Folder not found[/]")

            # Ollama
            ollama_models = status.get('ollama_models', [])
            if ollama_models:
                models = ', '.join(str(m) for m in ollama_models[:3])
                lines.append(f"[green]✓ Ollama LLM       {models}[/]")
            elif status.get('ollama_running'):
                lines.append("[yellow]◐ Ollama LLM       Running (no models)[/]")
            else:
                lines.append("[dim]○ Ollama LLM       Not running (ollama serve)[/]")

            # ComfyUI
            if status.get('comfyui_running'):
                lines.append("[green]✓ ComfyUI          http://127.0.0.1:8188[/]")
            else:
                lines.append("[dim]○ ComfyUI          Not running (port 8188)[/]")

            # OpenAI
            if status.get('openai_configured'):
                lines.append("[green]✓ OpenAI API       Key configured[/]")
            else:
                lines.append("[dim]○ OpenAI API       OPENAI_API_KEY not set[/]")

            # Synesthesia
            if status.get('synesthesia_running'):
                lines.append("[green]✓ Synesthesia      VJ app running[/]")
            elif status.get('synesthesia_installed'):
                lines.append("[yellow]○ Synesthesia      Installed (not running)[/]")
            else:
                lines.append("[dim]○ Synesthesia      Not installed[/]")

            self.update("\n".join(lines))

        except Exception as e:
            logger.exception(f"Error updating services panel: {e}")
            self.update(f"[red]Error displaying services[/]\n[dim]{str(e)}[/dim]")


class SongCategoriesPanel(Static):
    """Widget displaying song mood/theme categories."""

    categories_data = reactive({})

    def watch_categories_data(self, data: dict) -> None:
        """Update display when categories change."""
        try:
            lines = []
            lines.append("[bold yellow]═══ Song Categories ═══[/]\n")

            if not data or not data.get('categories'):
                lines.append("[dim](waiting for song analysis...)[/dim]")
                self.update("\n".join(lines))
                return

            # Primary mood
            primary = data.get('primary_mood', '')
            if primary:
                lines.append(f"[bold cyan]Primary Mood:[/] [bold]{primary.upper()}[/]")
                lines.append("")

            # Category bars
            categories = data.get('categories', [])
            for cat in categories[:10]:  # Top 10
                name = cat.get('name', '')
                score = cat.get('score', 0.0)
                
                # Create visual bar
                bar_width = 15
                filled = int(score * bar_width)
                bar = "█" * filled + "░" * (bar_width - filled)
                
                # Color based on score
                if score >= 0.7:
                    color = "green"
                elif score >= 0.4:
                    color = "yellow"
                else:
                    color = "dim"
                
                lines.append(f"  [{color}]{name:15s} {bar} {score:.2f}[/]")

            self.update("\n".join(lines))

        except Exception as e:
            logger.exception(f"Error updating categories panel: {e}")
            self.update(f"[red]Error displaying categories[/]\n[dim]{str(e)}[/dim]")


class OSCDebugPanel(Static):
    """Widget displaying recent OSC messages for debugging."""

    osc_messages = reactive([])

    def watch_osc_messages(self, messages: list) -> None:
        """Update display when OSC messages change."""
        try:
            lines = []
            lines.append("[bold magenta]═══ OSC Debug ═══[/]\n")

            if not messages:
                lines.append("[dim](no OSC messages yet)[/dim]")
                self.update("\n".join(lines))
                return

            # Show recent messages (newest first)
            for msg in reversed(messages[-15:]):
                try:
                    ts, address, args = msg
                    # Format timestamp
                    time_str = time.strftime("%H:%M:%S", time.localtime(ts))
                    # Truncate args if too long
                    args_str = str(args)
                    if len(args_str) > 40:
                        args_str = args_str[:37] + "..."
                    
                    # Color by channel
                    if "/karaoke/categories" in address:
                        color = "yellow"
                    elif "/vj/" in address:
                        color = "cyan"
                    elif "/karaoke/" in address:
                        color = "green"
                    else:
                        color = "white"
                    
                    lines.append(f"[dim]{time_str}[/] [{color}]{address}[/] {args_str}")
                except (ValueError, TypeError):
                    continue

            self.update("\n".join(lines))

        except Exception as e:
            logger.exception(f"Error updating OSC debug panel: {e}")
            self.update(f"[red]Error displaying OSC messages[/]\n[dim]{str(e)}[/dim]")


class MasterControlPanel(Static):
    """Widget for master control of VJ apps (Synesthesia, ProjectMilkSyphon, etc.)."""

    status_data = reactive({})

    def watch_status_data(self, data: dict) -> None:
        """Update display when status changes."""
        try:
            lines = []
            lines.append("[bold blue]═══ Master Control ═══[/]\n")

            # Synesthesia
            syn_running = data.get('synesthesia_running', False)
            syn_icon = "[green]● RUNNING[/]" if syn_running else "[dim]○ stopped[/]"
            lines.append(f"  [S] Synesthesia     {syn_icon}")

            # ProjectMilkSyphon
            pms_running = data.get('milksyphon_running', False)
            pms_icon = "[green]● RUNNING[/]" if pms_running else "[dim]○ stopped[/]"
            lines.append(f"  [M] ProjMilkSyphon  {pms_icon}")

            # Processing apps count
            proc_count = data.get('processing_apps', 0)
            lines.append(f"  [P] Processing Apps {proc_count} running")

            # Karaoke engine
            karaoke_active = data.get('karaoke_active', False)
            kar_icon = "[green]● ACTIVE[/]" if karaoke_active else "[dim]○ inactive[/]"
            lines.append(f"  [K] Karaoke Engine  {kar_icon}")

            lines.append("")
            lines.append("[dim]Press letter key to toggle app[/dim]")

            self.update("\n".join(lines))

        except Exception as e:
            logger.exception(f"Error updating master control panel: {e}")
            self.update(f"[red]Error displaying master control[/]\n[dim]{str(e)}[/dim]")


class VJConsoleApp(App):
    """Modern VJ Console with Textual."""

    CSS = """
    Screen {
        background: $surface;
    }

    #header-container {
        background: $primary;
        color: $text;
        height: 3;
        content-align: center middle;
    }

    #main-container {
        layout: vertical;
        height: 1fr;
    }

    #status-bar {
        height: 1;
        background: $panel;
    }

    #content-container {
        layout: horizontal;
        height: 1fr;
    }

    #left-panel {
        width: 40%;
        border: solid $primary;
    }

    #right-panel {
        width: 60%;
        border: solid $accent;
    }

    NowPlaying {
        height: auto;
        padding: 1;
        border: solid $accent;
    }

    PipelineStatus {
        height: 1fr;
        padding: 1;
        overflow-y: auto;
    }

    ProcessingAppsList {
        height: auto;
        padding: 1;
    }

    ServicesPanel {
        height: auto;
        padding: 1;
    }

    SongCategoriesPanel {
        height: auto;
        padding: 1;
        border: solid yellow;
    }

    OSCDebugPanel {
        height: auto;
        max-height: 15;
        padding: 1;
        border: solid magenta;
        overflow-y: auto;
    }

    MasterControlPanel {
        height: auto;
        padding: 1;
        border: solid blue;
    }
    """

    BINDINGS = [
        Binding("q", "quit", "Quit"),
        Binding("k,up", "navigate_up", "Up"),
        Binding("j,down", "navigate_down", "Down"),
        Binding("enter", "select", "Select"),
        Binding("shift+k", "toggle_karaoke", "Karaoke"),
        Binding("plus,equals", "timing_up", "Timing +"),
        Binding("minus,underscore", "timing_down", "Timing -"),
        Binding("s", "toggle_synesthesia", "Synesthesia"),
        Binding("m", "toggle_milksyphon", "MilkSyphon"),
        Binding("o", "toggle_osc_debug", "OSC Debug"),
    ]

    # Reactive state
    daemon_mode = reactive(True)  # Always on for live reliability
    karaoke_enabled = reactive(True)
    synesthesia_running = reactive(False)
    milksyphon_running = reactive(False)
    show_osc_debug = reactive(True)

    def __init__(self, project_root: Optional[Path] = None):
        super().__init__()
        self.project_root = project_root or self._find_project_root()
        self.process_manager = ProcessManager()
        self.process_manager.discover_apps(self.project_root)
        self.karaoke_engine: Optional[KaraokeEngine] = None
        self.selected_app_index = 0

    def _find_project_root(self) -> Path:
        """Find the project root directory."""
        current = Path(__file__).parent.parent

        if (current / "processing-vj").exists():
            return current

        cwd = Path.cwd()
        if (cwd / "processing-vj").exists():
            return cwd

        for _ in range(3):
            current = current.parent
            if (current / "processing-vj").exists():
                return current

        return Path.cwd()

    def compose(self) -> ComposeResult:
        """Create the UI layout."""
        yield Header(show_clock=True)

        with Container(id="main-container"):
            # Status bar
            with Horizontal(id="status-bar"):
                yield Static("[bold]Daemon:[/] [green]● ALWAYS ON[/] (auto-restart)")
                yield Static(f"[bold]Karaoke:[/] {'[green]● ON[/]' if self.karaoke_enabled else '[dim]○ OFF[/]'}")
                yield Static(f"[bold]Synesthesia:[/] {'[green]● Running[/]' if self.synesthesia_running else '[dim]○ Stopped[/]'}")

            # Main content
            with Horizontal(id="content-container"):
                # Left panel - Processing apps, master control, and services
                with VerticalScroll(id="left-panel"):
                    yield MasterControlPanel(id="master-control")
                    yield ProcessingAppsList(id="apps-list")
                    yield ServicesPanel(id="services")

                # Right panel - Now playing, categories, pipeline, and OSC debug
                with VerticalScroll(id="right-panel"):
                    yield NowPlaying(id="now-playing")
                    yield SongCategoriesPanel(id="categories")
                    yield PipelineStatus(id="pipeline")
                    yield OSCDebugPanel(id="osc-debug")

        yield Footer()

    def on_mount(self) -> None:
        """Initialize after UI is mounted."""
        self.title = "🎛  VJ Console - Synesthesia Visuals"
        self.sub_title = "Master Control Center"

        # Update apps list
        apps_widget = self.query_one("#apps-list", ProcessingAppsList)
        apps_widget.apps = self.process_manager.apps

        # Start daemon mode (always on for live reliability)
        self.process_manager.start_monitoring(daemon_mode=True)

        # Start karaoke engine
        self.start_karaoke()

        # Start Synesthesia
        self.start_synesthesia()

        # Check for ProjectMilkSyphon
        self.check_milksyphon()

        # Start background update worker
        self.set_interval(0.5, self.update_data)
        self.set_interval(2.0, self.check_apps_status)

        # Update services status
        self.update_services()

    def start_karaoke(self) -> None:
        """Start the karaoke engine."""
        if self.karaoke_engine:
            return

        try:
            self.karaoke_engine = KaraokeEngine()
            self.karaoke_engine.start()
            self.karaoke_enabled = True
            logger.info("Karaoke Engine started")
        except Exception as e:
            logger.exception(f"Karaoke start error: {e}")

    def stop_karaoke(self) -> None:
        """Stop the karaoke engine."""
        if self.karaoke_engine:
            self.karaoke_engine.stop()
            self.karaoke_engine = None
        self.karaoke_enabled = False

    def start_synesthesia(self) -> None:
        """Start Synesthesia if not already running."""
        import subprocess
        from pathlib import Path

        # Check if already running
        try:
            result = subprocess.run(['pgrep', '-x', 'Synesthesia'], capture_output=True, timeout=1)
            if result.returncode == 0:
                logger.info("Synesthesia already running")
                self.synesthesia_running = True
                return
        except Exception as e:
            logger.debug(f"pgrep check failed: {e}")

        # Launch Synesthesia
        synesthesia_path = Path("/Applications/Synesthesia.app")
        if not synesthesia_path.exists():
            logger.warning("Synesthesia not found at /Applications/Synesthesia.app")
            return

        try:
            subprocess.Popen(['open', '-a', 'Synesthesia'])
            logger.info("Synesthesia launched")
            self.synesthesia_running = True
        except Exception as e:
            logger.exception(f"Failed to launch Synesthesia: {e}")

    def update_data(self) -> None:
        """Update all reactive data (called every 0.5s)."""
        # Update now playing
        if self.karaoke_engine:
            state = self.karaoke_engine._state
            now_playing = self.query_one("#now-playing", NowPlaying)

            # Update connection status
            if self.karaoke_engine._spotify and hasattr(self.karaoke_engine._spotify, '_sp'):
                now_playing.is_connected = bool(self.karaoke_engine._spotify._sp)

            # Update track info
            if state.active and state.track:
                track = state.track
                now_playing.track_artist = track.artist
                now_playing.track_title = track.title
                now_playing.track_source = track.source
                now_playing.position_sec = state.position_sec
                now_playing.duration_sec = track.duration_sec
                now_playing.is_playing = state.active

                # Update pipeline
                pipeline_widget = self.query_one("#pipeline", PipelineStatus)
                pipeline_data = {
                    'display_lines': self.karaoke_engine.pipeline.get_display_lines(),
                    'image_prompt': self.karaoke_engine.pipeline.image_prompt,
                    'logs': self.karaoke_engine.pipeline.get_log_lines(5),
                }

                # Current lyric
                if state.lines:
                    from karaoke_engine import get_active_line_index
                    offset_ms = self.karaoke_engine.timing_offset_ms
                    adjusted_pos = state.position_sec + (offset_ms / 1000.0)
                    idx = get_active_line_index(state.lines, adjusted_pos)

                    if 0 <= idx < len(state.lines):
                        line = state.lines[idx]
                        pipeline_data['current_lyric'] = {
                            'text': line.text,
                            'keywords': line.keywords,
                            'is_refrain': line.is_refrain,
                        }

                pipeline_widget.pipeline_data = pipeline_data

                # Update song categories panel
                categories_widget = self.query_one("#categories", SongCategoriesPanel)
                categories = self.karaoke_engine.current_categories
                if categories:
                    cat_data = {
                        'primary_mood': categories.primary_mood,
                        'categories': [
                            {'name': c.name, 'score': c.score}
                            for c in categories.get_top(10)
                        ]
                    }
                    categories_widget.categories_data = cat_data

                # Update OSC debug panel
                osc_debug_widget = self.query_one("#osc-debug", OSCDebugPanel)
                osc_messages = self.karaoke_engine.osc_sender.get_recent_messages(20)
                osc_debug_widget.osc_messages = osc_messages

        # Update master control panel
        self.update_master_control()

    def update_master_control(self) -> None:
        """Update the master control panel status."""
        master_widget = self.query_one("#master-control", MasterControlPanel)
        
        # Count running Processing apps
        running_apps = sum(1 for app in self.process_manager.apps 
                         if self.process_manager.is_running(app))
        
        master_widget.status_data = {
            'synesthesia_running': self.synesthesia_running,
            'milksyphon_running': self.milksyphon_running,
            'processing_apps': running_apps,
            'karaoke_active': self.karaoke_enabled and self.karaoke_engine is not None,
        }
        
        # Send master status via OSC
        if self.karaoke_engine:
            self.karaoke_engine.osc_sender.send_master_status(
                karaoke_active=self.karaoke_enabled,
                synesthesia_running=self.synesthesia_running,
                milksyphon_running=self.milksyphon_running,
                processing_apps=running_apps
            )

    def check_apps_status(self) -> None:
        """Check status of all managed apps (called every 2s)."""
        self.check_synesthesia()
        self.check_milksyphon()
        self.update_services()

    def check_synesthesia(self) -> None:
        """Check if Synesthesia is running."""
        try:
            result = subprocess.run(
                ['pgrep', '-x', 'Synesthesia'],
                capture_output=True,
                text=True,
                timeout=1
            )
            was_running = self.synesthesia_running
            self.synesthesia_running = result.returncode == 0
            
            # Send status via OSC if changed
            if was_running != self.synesthesia_running and self.karaoke_engine:
                self.karaoke_engine.osc_sender.send_synesthesia_status(self.synesthesia_running)
        except Exception as e:
            logger.debug(f"Error checking Synesthesia: {e}")
            self.synesthesia_running = False

    def check_milksyphon(self) -> None:
        """Check if ProjectMilkSyphon is running."""
        try:
            result = subprocess.run(
                ['pgrep', '-f', 'projectMilkSyphon'],
                capture_output=True,
                text=True,
                timeout=1
            )
            was_running = self.milksyphon_running
            self.milksyphon_running = result.returncode == 0
            
            # Send status via OSC if changed
            if was_running != self.milksyphon_running and self.karaoke_engine:
                self.karaoke_engine.osc_sender.send_milksyphon_status(self.milksyphon_running)
        except Exception as e:
            logger.debug(f"Error checking ProjectMilkSyphon: {e}")
            self.milksyphon_running = False

    def stop_synesthesia(self) -> None:
        """Stop Synesthesia."""
        try:
            subprocess.run(['pkill', '-x', 'Synesthesia'], timeout=2)
            logger.info("Synesthesia stopped")
            self.synesthesia_running = False
        except Exception as e:
            logger.exception(f"Failed to stop Synesthesia: {e}")

    def start_milksyphon(self) -> None:
        """Start ProjectMilkSyphon if not already running."""
        # Check if already running
        try:
            result = subprocess.run(['pgrep', '-f', 'projectMilkSyphon'], capture_output=True, timeout=1)
            if result.returncode == 0:
                logger.info("ProjectMilkSyphon already running")
                self.milksyphon_running = True
                return
        except Exception as e:
            logger.debug(f"pgrep check failed: {e}")

        # Common locations for ProjectMilkSyphon
        milksyphon_paths = [
            Path("/Applications/projectMilkSyphon.app"),
            Path.home() / "Applications" / "projectMilkSyphon.app",
        ]
        
        for path in milksyphon_paths:
            if path.exists():
                try:
                    subprocess.Popen(['open', '-a', str(path)])
                    logger.info("ProjectMilkSyphon launched")
                    self.milksyphon_running = True
                    return
                except Exception as e:
                    logger.exception(f"Failed to launch ProjectMilkSyphon: {e}")
        
        logger.warning("ProjectMilkSyphon not found")

    def stop_milksyphon(self) -> None:
        """Stop ProjectMilkSyphon."""
        try:
            subprocess.run(['pkill', '-f', 'projectMilkSyphon'], timeout=2)
            logger.info("ProjectMilkSyphon stopped")
            self.milksyphon_running = False
        except Exception as e:
            logger.exception(f"Failed to stop ProjectMilkSyphon: {e}")

    def update_services(self) -> None:
        """Update services status."""
        services = self.query_one("#services", ServicesPanel)

        status = {
            'spotify_configured': KaraokeConfig.has_spotify_credentials(),
            'virtualdj_found': False,
            'ollama_running': False,
            'ollama_models': [],
            'comfyui_running': False,
            'openai_configured': bool(__import__('os').environ.get('OPENAI_API_KEY')),
        }

        # Check VirtualDJ
        vdj_path = KaraokeConfig.find_vdj_path()
        if vdj_path:
            status['virtualdj_found'] = True
            status['vdj_file'] = vdj_path.name

        # Check Ollama
        try:
            import requests
            resp = requests.get("http://localhost:11434/api/tags", timeout=1)
            if resp.status_code == 200:
                models = resp.json().get('models', [])
                status['ollama_running'] = True
                status['ollama_models'] = [m.get('name', '').split(':')[0] for m in models[:3]]
        except Exception:
            pass

        # Check ComfyUI
        try:
            import requests
            resp = requests.get("http://127.0.0.1:8188/system_stats", timeout=1)
            status['comfyui_running'] = resp.status_code == 200
        except Exception:
            pass

        # Check Synesthesia
        status['synesthesia_installed'] = Path('/Applications/Synesthesia.app').exists()
        status['synesthesia_running'] = self.synesthesia_running

        services.services_status = status

    # Actions
    def action_navigate_up(self) -> None:
        """Navigate up in apps list."""
        apps_widget = self.query_one("#apps-list", ProcessingAppsList)
        if apps_widget.selected_index > 0:
            apps_widget.selected_index -= 1

    def action_navigate_down(self) -> None:
        """Navigate down in apps list."""
        apps_widget = self.query_one("#apps-list", ProcessingAppsList)
        if apps_widget.selected_index < len(self.process_manager.apps) - 1:
            apps_widget.selected_index += 1

    def action_select(self) -> None:
        """Select/toggle current app."""
        apps_widget = self.query_one("#apps-list", ProcessingAppsList)
        if 0 <= apps_widget.selected_index < len(self.process_manager.apps):
            app = self.process_manager.apps[apps_widget.selected_index]

            if self.process_manager.is_running(app):
                self.process_manager.stop_app(app)
            else:
                self.process_manager.launch_app(app)

    def action_toggle_karaoke(self) -> None:
        """Toggle karaoke engine."""
        if self.karaoke_enabled:
            self.stop_karaoke()
        else:
            self.start_karaoke()

    def action_toggle_synesthesia(self) -> None:
        """Toggle Synesthesia."""
        if self.synesthesia_running:
            self.stop_synesthesia()
        else:
            self.start_synesthesia()

    def action_toggle_milksyphon(self) -> None:
        """Toggle ProjectMilkSyphon."""
        if self.milksyphon_running:
            self.stop_milksyphon()
        else:
            self.start_milksyphon()

    def action_toggle_osc_debug(self) -> None:
        """Toggle OSC debug panel visibility."""
        self.show_osc_debug = not self.show_osc_debug
        osc_panel = self.query_one("#osc-debug", OSCDebugPanel)
        osc_panel.display = self.show_osc_debug

    def action_timing_up(self) -> None:
        """Increase timing offset."""
        if self.karaoke_engine:
            self.karaoke_engine.adjust_timing(+200)

    def action_timing_down(self) -> None:
        """Decrease timing offset."""
        if self.karaoke_engine:
            self.karaoke_engine.adjust_timing(-200)

    def on_unmount(self) -> None:
        """Cleanup when app closes."""
        self.stop_karaoke()
        self.process_manager.cleanup()


def main():
    """Run the VJ Console app."""
    app = VJConsoleApp()
    app.run()


if __name__ == '__main__':
    main()
