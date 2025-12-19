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
import os
import subprocess
import threading
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
from osc import osc, osc_monitor

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

# Import UI components and utilities from refactored modules
from ui import (
    OSCClearRequested, PlaybackSourceChanged,
    ShaderSearchModal,
    StartupControlPanel, OSCControlPanel, OSCPanel,
    NowPlayingPanel, PlaybackSourcePanel,
    CategoriesPanel, PipelinePanel,
    AppsListPanel, LogsPanel,
    ShaderIndexPanel, ShaderMatchPanel,
    ShaderAnalysisPanel, ShaderSearchPanel,
    ShaderActionsPanel,
)
from data.builders import build_track_data, build_pipeline_data, build_categories_payload
from services import ProcessMonitor, ShaderAnalysisWorker

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
        Binding("3", "screen_logs", "Logs"),
        Binding("4", "screen_midi", "MIDI"),
        Binding("5", "screen_shaders", "Shaders"),
        Binding("s", "toggle_synesthesia", "Synesthesia"),
        Binding("k,up", "nav_up", "Up"),
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
        
        # Suppress noisy HTTP library logs
        logging.getLogger('urllib3').setLevel(logging.WARNING)
        logging.getLogger('requests').setLevel(logging.WARNING)
        logging.getLogger('urllib3.connectionpool').setLevel(logging.WARNING)
        
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
                        yield AppsListPanel(id="apps", classes="panel")
                    with VerticalScroll(id="right-col"):
                        yield NowPlayingPanel(id="now-playing", classes="panel")
                        yield CategoriesPanel(id="categories", classes="panel")
                        yield PipelinePanel(id="pipeline", classes="panel")

            # Tab 2: OSC View
            with TabPane("2️⃣ OSC View", id="osc"):
                yield OSCControlPanel(id="osc-control")
                with VerticalScroll(id="osc-scroll", classes="panel full-height"):
                    yield OSCPanel(id="osc-full")

            # Tab 3: All Logs
            with TabPane("3️⃣ All Logs", id="logs"):
                yield LogsPanel(id="logs-panel", classes="panel full-height")
            
            # Tab 4: Launchpad Controller
            with TabPane("4️⃣ Launchpad", id="launchpad"):
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
            
            # Tab 5: Shader Indexer
            with TabPane("5️⃣ Shaders", id="shaders"):
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
        self.sub_title = "Press 1-5 to switch screens"

        # OSC hub runs continuously for the lifetime of the console
        if osc.start():
            logger.info("OSC Hub started (always-on)")
        else:
            logger.error("OSC Hub failed to start")

        # Initialize apps list
        self.query_one("#apps", AppsListPanel).apps = self.process_manager.apps
        self.process_manager.start_monitoring(daemon_mode=True)

        # Always start KaraokeEngine - it polls slowly (10s) when no source connected
        self._start_karaoke()

        # NOTE: Other services controlled via StartupControlPanel
        # Services are started only when "Start All" button is pressed
        # or when auto-restart is enabled and service is not running

        # Background updates - stagger intervals to reduce CPU spikes
        self.set_interval(0.5, self._update_data)
        self.set_interval(30.0, self._check_apps_and_autorestart)  # Check every 30s

        # Fix keyboard focus: ensure TabbedContent has focus for key bindings to work
        # Use call_after_refresh to ensure UI is fully rendered before setting focus
        self.call_after_refresh(self._set_initial_focus)

        # Log startup to verify logging is working
        logger.info("VJ Console mounted and ready")
        logger.info(f"Logs are being captured to panel (current count: {len(self._logs)})")

    def _set_initial_focus(self) -> None:
        """Set initial focus after UI is rendered."""
        try:
            tabs = self.query_one("#screens", TabbedContent)
            tabs.focus()
        except Exception as e:
            logger.warning(f"Could not set initial focus: {e}")

    def _safe_update_panel(self, panel_id: str, attribute: str, value: Any) -> None:
        """Safely update a panel attribute without crashing on errors."""
        try:
            panel = self.query_one(panel_id)
            setattr(panel, attribute, value)
        except Exception:
            # Silently ignore - panel might not be mounted yet
            pass

    def on_osc_clear_requested(self, message: OSCClearRequested) -> None:
        """Handle OSC clear request from OSCControlPanel."""
        osc_monitor.clear()
        logger.info("OSC message log cleared")

    def _update_osc_control_panel(self) -> None:
        """Update the OSC control panel with current status."""
        try:
            panel = self.query_one("#osc-control", OSCControlPanel)
            panel.channel_status = osc.get_channel_status()
        except Exception:
            pass

    def _is_osc_view_active(self) -> bool:
        try:
            return self.query_one("#screens", TabbedContent).active == "osc"
        except Exception:
            return False

    def _sync_osc_monitor_visibility(self) -> None:
        osc_view_active = self._is_osc_view_active()
        if osc_view_active and osc.is_started and not osc_monitor.is_started:
            osc_monitor.start()
            return
        if osc_monitor.is_started and (not osc_view_active or not osc.is_started):
            osc_monitor.stop()

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
        """Check LM Studio API and model status."""
        try:
            resp = requests.get("http://localhost:1234/v1/models", timeout=1)
            if resp.status_code == 200:
                models = resp.json().get('data', [])
                if models:
                    model_id = models[0].get('id', 'unknown')
                    return {'available': True, 'model': model_id, 'warning': ''}
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
        
        if self.settings.autorestart_magic and not self.magic_running:
            logger.info("Auto-restarting Magic")
            self._start_magic()

    def _update_data(self) -> None:
        """Update all panels with current data."""
        # Always update logs panel
        self._safe_update_panel("#logs-panel", "logs", list(self._logs))

        # Always update OSC panels
        self._update_osc_control_panel()
        self._sync_osc_monitor_visibility()
        self._safe_update_panel("#osc-full", "osc_running", osc.is_started)
        if self._is_osc_view_active() and osc.is_started and osc_monitor.is_started:
            try:
                control_panel = self.query_one("#osc-control", OSCControlPanel)
                filter_text = control_panel.filter_text
            except Exception:
                filter_text = ""
            self._safe_update_panel("#osc-full", "full_view", True)
            self._safe_update_panel("#osc-full", "filter_text", filter_text)
            self._safe_update_panel("#osc-full", "stats", osc_monitor.get_stats())
            self._safe_update_panel(
                "#osc-full",
                "grouped_prefixes",
                osc_monitor.get_grouped_prefixes(
                    filter_text=filter_text,
                    limit=20,
                    child_limit=20,
                ),
            )
            self._safe_update_panel(
                "#osc-full",
                "grouped_messages",
                osc_monitor.get_grouped_messages(
                    filter_text=filter_text,
                    limit_per_channel=20,
                ),
            )

        # If no karaoke engine, clear panels and return
        if not self.karaoke_engine:
            self._safe_update_panel("#now-playing", "track_data", {})
            self._safe_update_panel("#playback-source", "monitor_running", False)
            self._safe_update_panel("#playback-source", "lookup_ms", 0.0)
            self._safe_update_panel("#playback-source", "connection_state", "idle")
            return

        # Get snapshot and build data
        snapshot = self.karaoke_engine.get_snapshot()
        self._latest_snapshot = snapshot
        monitor_status = snapshot.monitor_status or {}
        source_connected = (
            monitor_status.get(snapshot.source, {}).get('available', False)
            if snapshot.source in monitor_status
            else any(s.get('available', False) for s in monitor_status.values())
        )

        # Update now playing
        track_data = build_track_data(snapshot, source_connected)
        self._safe_update_panel("#now-playing", "track_data", track_data)
        self._safe_update_panel("#now-playing", "shader_name", self.karaoke_engine.current_shader)

        # Update playback source panel with connection state
        self._safe_update_panel("#playback-source", "lookup_ms", self.karaoke_engine.last_lookup_ms)
        self._safe_update_panel("#playback-source", "monitor_running", bool(self.karaoke_engine.playback_source))
        
        # Determine connection state for visual feedback
        state = snapshot.state
        if not self.karaoke_engine.playback_source:
            connection_state = "idle"
            current_track = ""
        elif snapshot.error:
            connection_state = "connecting"
            current_track = ""
        elif state.has_track and state.is_playing:
            connection_state = "connected"
            current_track = f"{state.track.artist} - {state.track.title}" if state.track else ""
        elif state.has_track:
            connection_state = "connected"  # Has track but paused
            current_track = f"{state.track.artist} - {state.track.title} (paused)" if state.track else ""
        else:
            connection_state = "no_playback"
            current_track = ""
        
        self._safe_update_panel("#playback-source", "connection_state", connection_state)
        self._safe_update_panel("#playback-source", "current_track", current_track)

        # Update categories panel
        cat_data = build_categories_payload(self.karaoke_engine.current_categories)
        self._safe_update_panel("#categories", "categories_data", cat_data)

        # Update pipeline panel
        pipeline_data = build_pipeline_data(self.karaoke_engine, snapshot)
        self._safe_update_panel("#pipeline", "pipeline_data", pipeline_data)

        # Update Launchpad panels
        self._update_launchpad_panels()
        
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
    
    def action_screen_logs(self) -> None:
        self.query_one("#screens", TabbedContent).active = "logs"
    
    def action_screen_midi(self) -> None:
        """Switch to Launchpad screen."""
        self.query_one("#screens", TabbedContent).active = "launchpad"
    
    def action_screen_shaders(self) -> None:
        self.query_one("#screens", TabbedContent).active = "shaders"

    # === App control ===

    def action_quit(self) -> None:
        logger.info("Quit requested")
        self._start_force_exit_watchdog()
        self.exit()
    
    def action_toggle_synesthesia(self) -> None:
        if self.synesthesia_running:
            self._run_process(['pkill', '-x', 'Synesthesia'])
        else:
            subprocess.Popen(['open', '-a', 'Synesthesia'])
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

    def _start_force_exit_watchdog(self, timeout: float = 3.0) -> None:
        if getattr(self, "_force_exit_thread", None):
            return

        def _force_exit() -> None:
            time.sleep(timeout)
            logger.warning("Force exit after shutdown timeout")
            os._exit(0)

        self._force_exit_thread = threading.Thread(
            target=_force_exit,
            name="ForceExitWatchdog",
            daemon=True,
        )
        self._force_exit_thread.start()

    def on_unmount(self) -> None:
        logger.info("Shutdown: begin")
        if osc_monitor.is_started:
            logger.info("Shutdown: stopping osc_monitor")
            osc_monitor.stop()
            logger.info("Shutdown: osc_monitor stopped")
        if self.shader_analysis_worker:
            logger.info("Shutdown: stopping shader_analysis_worker")
            self.shader_analysis_worker.stop()
            logger.info("Shutdown: shader_analysis_worker stopped")
        if self.karaoke_engine:
            logger.info("Shutdown: stopping karaoke_engine")
            self.karaoke_engine.stop()
            logger.info("Shutdown: karaoke_engine stopped")
        if self.launchpad_manager:
            logger.info("Shutdown: stopping launchpad_manager")
            self.launchpad_manager.stop()
            logger.info("Shutdown: launchpad_manager stopped")
        logger.info("Shutdown: process_manager.cleanup")
        self.process_manager.cleanup()
        logger.info("Shutdown: complete")


def main():
    VJConsoleApp().run()


if __name__ == '__main__':
    main()
