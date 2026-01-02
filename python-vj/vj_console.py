#!/usr/bin/env python3
"""
VJ Console - Modular Edition

A thin shell that composes modules for VJ control.

Screens (press 1-5 to switch):
1. Master Control - Track, pipeline status, categories
2. OSC View - Full OSC message debug view
3. All Logs - Complete application logs
4. Launchpad - Controller management
5. Shaders - Shader analysis and matching
"""

from dotenv import load_dotenv
load_dotenv(override=True, verbose=True)

from pathlib import Path
from typing import Optional, List, Dict, Any
import logging
import os
import subprocess
import threading
import time

from textual.app import App, ComposeResult
from textual.containers import Container, Horizontal, VerticalScroll
from textual.widgets import Header, Footer, Static, TabbedContent, TabPane, Button
from textual.reactive import reactive
from textual.binding import Binding

from modules import ModuleRegistry, ModuleRegistryConfig
from modules.pipeline import PipelineStep, PipelineResult
from infrastructure import Settings
from osc import osc, osc_monitor
from process_manager import ProcessManager

# UI components
from ui import (
    OSCClearRequested, PlaybackSourceChanged, VJUniverseTestRequested, VDJTestRequested,
    ShaderSearchModal,
    StartupControlPanel, OSCControlPanel, OSCPanel,
    NowPlayingPanel, PlaybackSourcePanel,
    CategoriesPanel, PipelinePanel,
    AppsListPanel, LogsPanel,
    ShaderIndexPanel, ShaderMatchPanel,
    ShaderAnalysisPanel, ShaderSearchPanel,
    ShaderActionsPanel,
)
from services import ProcessMonitor, ProcessStats

# Launchpad (optional)
try:
    from launchpad_console import (
        LaunchpadStatusPanel, LaunchpadPadsPanel,
        LaunchpadInstructionsPanel, LaunchpadOscDebugPanel,
        LaunchpadTestsPanel, LaunchpadManager,
        LAUNCHPAD_LIB_AVAILABLE,
    )
except ImportError:
    LAUNCHPAD_LIB_AVAILABLE = False
    LaunchpadStatusPanel = LaunchpadPadsPanel = None
    LaunchpadInstructionsPanel = LaunchpadOscDebugPanel = None
    LaunchpadTestsPanel = LaunchpadManager = None

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(name)s - %(levelname)s - %(message)s')
logger = logging.getLogger('vj_console')


class VJConsoleApp(App):
    """VJ Console using modular architecture."""

    CSS = """
    Screen { background: $surface; }
    TabbedContent { height: 1fr; }
    TabPane { padding: 1; }
    .panel { padding: 1; border: solid $primary; height: auto; }
    .full-height { height: 1fr; overflow-y: auto; }
    #left-col { width: 40%; }
    #right-col { width: 60%; }
    #startup-control { padding: 1; border: solid $success; margin-bottom: 1; }
    #osc-control { padding: 1; border: solid $warning; margin-bottom: 1; height: auto; }
    .startup-row { height: auto; margin: 0; padding: 0; }
    .startup-row Checkbox { margin-right: 1; }
    .startup-row Static { margin-left: 1; }
    .startup-buttons { height: auto; padding-top: 1; }
    .startup-buttons Button { margin-right: 1; }
    """

    BINDINGS = [
        Binding("q", "quit", "Quit"),
        Binding("1", "screen_master", "Master"),
        Binding("2", "screen_osc", "OSC"),
        Binding("3", "screen_logs", "Logs"),
        Binding("4", "screen_midi", "Launchpad"),
        Binding("5", "screen_shaders", "Shaders"),
        Binding("plus,equals", "timing_up", "+Timing"),
        Binding("minus", "timing_down", "-Timing"),
    ]

    synesthesia_running = reactive(False)
    lmstudio_running = reactive(False)
    vjuniverse_running = reactive(False)

    def __init__(self):
        super().__init__()

        self.settings = Settings()
        self._logs: List[str] = []

        # Module Registry - the heart of the new architecture
        config = ModuleRegistryConfig(
            playback_source=self.settings.playback_source or "vdj_osc",
        )
        self.registry = ModuleRegistry(config)

        # Process manager for Processing apps
        self.process_manager = ProcessManager()
        self.process_manager.discover_apps(self._find_project_root())

        # Process monitor for resource tracking
        self.process_monitor = ProcessMonitor([
            "Synesthesia", "LM Studio", "Magic", "java",
        ])

        # Pipeline state for UI - track all steps with status
        self._pipeline_result: Optional[PipelineResult] = None
        self._pipeline_steps: Dict[str, Dict[str, Any]] = {}  # step_name -> {status, data, time_ms}
        self._pipeline_running: bool = False

        # Launchpad (optional)
        self.launchpad_manager: Optional[Any] = None
        self._setup_launchpad()

        self._setup_log_capture()

    def _find_project_root(self) -> Path:
        for p in [Path(__file__).parent.parent, Path.cwd()]:
            if (p / "processing-vj").exists():
                return p
        return Path.cwd()

    def _setup_launchpad(self) -> None:
        if not LAUNCHPAD_LIB_AVAILABLE or LaunchpadManager is None:
            return
        try:
            self.launchpad_manager = LaunchpadManager()
            self.launchpad_manager.set_state_callback(self._on_launchpad_state_change)
            self.launchpad_manager.start()
        except Exception as e:
            logger.warning(f"Launchpad init failed: {e}")
            self.launchpad_manager = None

    def _on_launchpad_state_change(self, state) -> None:
        self.call_from_thread(self._update_launchpad_panels)

    def _setup_log_capture(self) -> None:
        class ListHandler(logging.Handler):
            def __init__(self, log_list: List[str]):
                super().__init__()
                self.log_list = log_list
                self.setFormatter(logging.Formatter('%(asctime)s - %(name)s - %(levelname)s - %(message)s'))

            def emit(self, record):
                try:
                    self.log_list.append(self.format(record))
                    if len(self.log_list) > 500:
                        self.log_list.pop(0)
                except Exception:
                    pass

        root_logger = logging.getLogger()
        root_logger.addHandler(ListHandler(self._logs))
        logging.getLogger('urllib3').setLevel(logging.WARNING)

    def compose(self) -> ComposeResult:
        yield Header(show_clock=True)

        with TabbedContent(id="screens"):
            # Tab 1: Master Control
            with TabPane("1 Master", id="master"):
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
            with TabPane("2 OSC", id="osc"):
                yield OSCControlPanel(id="osc-control")
                with VerticalScroll(classes="panel full-height"):
                    yield OSCPanel(id="osc-full")

            # Tab 3: Logs
            with TabPane("3 Logs", id="logs"):
                yield LogsPanel(id="logs-panel", classes="panel full-height")

            # Tab 4: Launchpad
            with TabPane("4 Launchpad", id="launchpad"):
                with Horizontal():
                    with VerticalScroll(id="left-col"):
                        if LAUNCHPAD_LIB_AVAILABLE and LaunchpadStatusPanel:
                            yield LaunchpadStatusPanel(id="lp-status", classes="panel")
                            yield LaunchpadPadsPanel(id="lp-pads", classes="panel")
                        else:
                            yield Static("[dim]Launchpad not available[/]", classes="panel")
                    with VerticalScroll(id="right-col"):
                        if LAUNCHPAD_LIB_AVAILABLE and LaunchpadInstructionsPanel:
                            yield LaunchpadInstructionsPanel(id="lp-instructions", classes="panel")
                            yield LaunchpadTestsPanel(id="lp-tests", classes="panel")
                            yield LaunchpadOscDebugPanel(id="lp-osc", classes="panel full-height")

            # Tab 5: Shaders
            with TabPane("5 Shaders", id="shaders"):
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
        self.title = "VJ Console (Modular)"
        self.sub_title = "Press 1-5 to switch screens"

        # Wire callbacks BEFORE starting (so first track is caught)
        self._wire_callbacks()

        # Start module registry
        logger.info("Starting module registry...")
        self.registry.start_all()

        # Init apps list
        try:
            self.query_one("#apps", AppsListPanel).apps = self.process_manager.apps
        except Exception:
            pass
        self.process_manager.start_monitoring(daemon_mode=True)

        # Background updates
        self.set_interval(0.5, self._update_ui)
        self.set_interval(30.0, self._check_services)

        logger.info("VJ Console mounted - modular architecture active")

    def _wire_callbacks(self) -> None:
        """Wire module callbacks to UI updates."""

        # Track change -> run pipeline
        def on_track_change(track):
            if track:
                logger.info(f"Track: {track.artist} - {track.title}")
                self._run_pipeline_async(track.artist, track.title, track.album)

        self.registry.playback.on_track_change = on_track_change

        # Pipeline step callbacks
        def on_step_start(step: PipelineStep):
            self._pipeline_steps[step.value] = {
                "status": "running",
                "start_time": time.time(),
                "data": {},
            }

        def on_step_complete(step: PipelineStep, data: Any):
            if step.value in self._pipeline_steps:
                step_info = self._pipeline_steps[step.value]
                step_info["status"] = "done" if "error" not in data else "error"
                step_info["data"] = data
                step_info["time_ms"] = int((time.time() - step_info.get("start_time", time.time())) * 1000)

        self.registry.pipeline.on_step_start = on_step_start
        self.registry.pipeline.on_step_complete = on_step_complete

    def _run_pipeline_async(self, artist: str, title: str, album: str = "") -> None:
        """Run pipeline in background thread."""
        logger.info(f"Starting pipeline for: {artist} - {title}")

        # Initialize all steps as pending
        self._pipeline_steps = {
            step.value: {"status": "pending", "data": {}, "time_ms": 0}
            for step in PipelineStep
        }
        self._pipeline_running = True
        self._pipeline_result = None

        def run():
            try:
                result = self.registry.pipeline.process(artist, title, album)
                self._pipeline_result = result
                self._pipeline_running = False
                # Mark skipped steps
                for step_name in result.steps_skipped:
                    if step_name in self._pipeline_steps:
                        self._pipeline_steps[step_name]["status"] = "skipped"
                logger.info(f"Pipeline complete: {result.steps_completed}")
            except Exception as e:
                self._pipeline_running = False
                logger.error(f"Pipeline error: {e}")

        threading.Thread(target=run, daemon=True).start()

    def _update_ui(self) -> None:
        """Update all UI panels."""
        # Logs
        self._safe_update("#logs-panel", "logs", list(self._logs))

        # OSC
        self._update_osc_panels()

        # Playback/Track
        self._update_playback_panels()

        # Pipeline/Categories
        self._update_pipeline_panels()

        # Launchpad
        self._update_launchpad_panels()

    def _safe_update(self, panel_id: str, attr: str, value: Any) -> None:
        try:
            setattr(self.query_one(panel_id), attr, value)
        except Exception:
            pass

    def _update_osc_panels(self) -> None:
        try:
            self._safe_update("#osc-control", "channel_status", osc.get_channel_status())
            self._safe_update("#osc-full", "osc_running", osc.is_started)

            # Only update OSC view when visible
            if self.query_one("#screens", TabbedContent).active == "osc":
                if not osc_monitor.is_started:
                    osc_monitor.start()
                self._safe_update("#osc-full", "full_view", True)
                self._safe_update("#osc-full", "stats", osc_monitor.get_stats())
                self._safe_update("#osc-full", "grouped_prefixes", osc_monitor.get_grouped_prefixes(limit=20, child_limit=20))
                self._safe_update("#osc-full", "grouped_messages", osc_monitor.get_grouped_messages(limit_per_channel=20))
            elif osc_monitor.is_started:
                osc_monitor.stop()
        except Exception:
            pass

    def _update_playback_panels(self) -> None:
        try:
            playback = self.registry.playback
            track = playback.current_track
            position = playback.current_position

            # Build track data
            if track:
                track_data = {
                    "active": True,
                    "connected": True,
                    "source": playback.current_source or "unknown",
                    "artist": track.artist,
                    "title": track.title,
                    "album": track.album,
                    "position": position,
                    "duration": track.duration_sec,
                    "has_lyrics": self._pipeline_result.lyrics_found if self._pipeline_result else False,
                }
                connection_state = "connected"
            else:
                track_data = {"active": False, "connected": False}
                connection_state = "no_playback" if playback.is_started else "idle"

            self._safe_update("#now-playing", "track_data", track_data)
            self._safe_update("#playback-source", "connection_state", connection_state)
            self._safe_update("#playback-source", "monitor_running", playback.is_started)
            self._safe_update("#playback-source", "lookup_ms", getattr(playback, '_last_lookup_ms', 0))
        except Exception as e:
            logger.debug(f"Playback update error: {e}")

    def _update_pipeline_panels(self) -> None:
        try:
            result = self._pipeline_result

            # Categories panel
            if result and result.mood:
                categories_data = {
                    "primary_mood": result.mood,
                    "energy": result.energy,
                    "valence": result.valence,
                    "scores": result.categories,
                    "ai_analyzed": result.ai_analyzed,
                }
            else:
                categories_data = {}
            self._safe_update("#categories", "categories_data", categories_data)

            # Pipeline panel - show ALL steps in order with status
            display_lines = []
            labels = {
                "lyrics": "Lyrics",
                "ai_analysis": "AI Analysis",
                "shader_match": "Shader",
                "images": "Images",
            }

            # Process all steps in order
            for step in PipelineStep:
                step_name = step.value
                step_info = self._pipeline_steps.get(step_name, {"status": "pending", "data": {}, "time_ms": 0})
                status = step_info.get("status", "pending")
                data = step_info.get("data", {})
                time_ms = step_info.get("time_ms", 0)

                label = labels.get(step_name, step_name.replace("_", " ").title())

                # Map status to display format
                if status == "running":
                    status_icon, color = "◐", "yellow"
                    message = "..."
                elif status == "done":
                    status_icon, color = "✓", "green"
                    # Build detailed message based on step type
                    if step_name == "lyrics":
                        lines = data.get("lines", 0)
                        refrains = data.get("refrains", 0)
                        if data.get("found"):
                            message = f"{lines}L {refrains}R"
                        else:
                            message = "not found"
                    elif step_name == "ai_analysis":
                        mood = data.get("mood", "")
                        energy = data.get("energy", 0)
                        valence = data.get("valence", 0)
                        kw = data.get("keywords", 0)
                        vis = data.get("visuals", 0)
                        if mood:
                            message = f"{mood} E{energy:.1f} V{valence:+.1f} {kw}kw {vis}vis"
                        else:
                            message = "no result"
                    elif step_name == "shader_match":
                        name = data.get("name", "")
                        score = data.get("score", 0)
                        message = f"{name} ({score:.2f})" if name else "no match"
                    elif step_name == "images":
                        count = data.get("count", 0)
                        cached = " cached" if data.get("cached") else ""
                        message = f"{count} imgs{cached}" if count else "none"
                    else:
                        message = "done"
                elif status == "skipped":
                    status_icon, color = "○", "dim"
                    message = "skipped"
                elif status == "error":
                    status_icon, color = "✗", "red"
                    message = data.get("error", "failed")[:30]
                else:  # pending
                    status_icon, color = "·", "dim"
                    message = ""

                # Add timing if available
                timing_str = f" [{time_ms}ms]" if time_ms > 0 else ""

                display_lines.append((label, status_icon, color, message, timing_str))

            pipeline_data = {
                "display_lines": display_lines,
                "running": self._pipeline_running,
                "result": {
                    "lyrics_found": result.lyrics_found if result else False,
                    "lyrics_lines": result.lyrics_line_count if result else 0,
                    "mood": result.mood if result else "",
                    "shader": result.shader_name if result else "",
                    "images": result.images_count if result else 0,
                    "time_ms": result.total_time_ms if result else 0,
                    "step_timings": result.step_timings if result else {},
                } if result else {},
            }
            self._safe_update("#pipeline", "pipeline_data", pipeline_data)
        except Exception as e:
            logger.debug(f"Pipeline update error: {e}")

    def _update_launchpad_panels(self) -> None:
        if not LAUNCHPAD_LIB_AVAILABLE or not self.launchpad_manager:
            return
        try:
            self._safe_update("#lp-status", "status", self.launchpad_manager.get_status())
            self._safe_update("#lp-pads", "pads_data", self.launchpad_manager.get_pads_data())
            self._safe_update("#lp-osc", "messages", self.launchpad_manager.get_osc_messages())
        except Exception:
            pass

    def _check_services(self) -> None:
        """Check external services status."""
        self.synesthesia_running = self._run_cmd(['pgrep', '-x', 'Synesthesia'])
        self.lmstudio_running = self._run_cmd(['pgrep', '-f', 'LM Studio'])
        self.vjuniverse_running = any(
            self.process_manager.is_running(app)
            for app in self.process_manager.apps
            if 'universe' in app.name.lower()
        )

        # Update startup panel with stats
        try:
            stats = self.process_monitor.get_stats()
            self._safe_update("#startup-control", "stats_data", stats)
        except Exception:
            pass

    def _run_cmd(self, cmd: List[str]) -> bool:
        try:
            return subprocess.run(cmd, capture_output=True, timeout=2).returncode == 0
        except Exception:
            return False

    # === Event Handlers ===

    def on_button_pressed(self, event: Button.Pressed) -> None:
        btn = event.button.id
        if btn == "btn-start-all":
            self._start_services()
        elif btn == "btn-stop-all":
            self._stop_services()

    def on_playback_source_changed(self, event: PlaybackSourceChanged) -> None:
        source_map = {"spotify_applescript": "Spotify", "vdj_osc": "VirtualDJ"}
        source = source_map.get(event.source_key, event.source_key)
        self.registry.set_playback_source(source)
        logger.info(f"Playback source changed to: {source}")

    def on_osc_clear_requested(self, event: OSCClearRequested) -> None:
        osc_monitor.clear()

    # === Service Control ===

    def _start_services(self) -> None:
        started = []
        if self.settings.start_synesthesia:
            subprocess.Popen(['open', '-a', 'Synesthesia'])
            started.append("Synesthesia")
        if self.settings.start_vjuniverse:
            for app in self.process_manager.apps:
                if 'universe' in app.name.lower():
                    self.process_manager.launch_app(app)
                    started.append("VJUniverse")
                    break
        if self.settings.start_lmstudio:
            subprocess.Popen(['open', '-a', 'LM Studio'])
            started.append("LM Studio")
        if started:
            self.notify(f"Started: {', '.join(started)}")

    def _stop_services(self) -> None:
        subprocess.run(['pkill', '-x', 'Synesthesia'], check=False)
        subprocess.run(['pkill', '-f', 'LM Studio'], check=False)
        for app in self.process_manager.apps:
            if 'universe' in app.name.lower() and self.process_manager.is_running(app):
                self.process_manager.stop_app(app)
        self.notify("Stopped all services")

    # === Actions ===

    def action_screen_master(self) -> None:
        self.query_one("#screens", TabbedContent).active = "master"

    def action_screen_osc(self) -> None:
        self.query_one("#screens", TabbedContent).active = "osc"

    def action_screen_logs(self) -> None:
        self.query_one("#screens", TabbedContent).active = "logs"

    def action_screen_midi(self) -> None:
        self.query_one("#screens", TabbedContent).active = "launchpad"

    def action_screen_shaders(self) -> None:
        self.query_one("#screens", TabbedContent).active = "shaders"

    def action_quit(self) -> None:
        logger.info("Quit requested")
        self._start_exit_watchdog()
        self.exit()

    def action_timing_up(self) -> None:
        # Timing adjustment (future: lyrics offset)
        pass

    def action_timing_down(self) -> None:
        pass

    def _start_exit_watchdog(self, timeout: float = 3.0) -> None:
        def force_exit():
            time.sleep(timeout)
            os._exit(0)
        threading.Thread(target=force_exit, daemon=True).start()

    def on_unmount(self) -> None:
        logger.info("Shutdown: begin")
        if osc_monitor.is_started:
            osc_monitor.stop()
        if self.launchpad_manager:
            self.launchpad_manager.stop()
        self.registry.stop_all()
        self.process_manager.cleanup()
        logger.info("Shutdown: complete")


def main():
    VJConsoleApp().run()


if __name__ == '__main__':
    main()
