#!/usr/bin/env python3
"""
VJ Console - Main entry point for the VJ Control System

A terminal UI application that:
- Lists and manages Processing apps from the project
- Runs apps in daemon mode with auto-restart on crash
- Monitors Spotify/VirtualDJ via the Karaoke Engine
- Shows live OSC status and messages

Smart defaults for macOS:
- Auto-loads .env file for Spotify credentials
- Auto-detects VirtualDJ folder
- Uses standard OSC port 9000

Usage:
    python vj_console.py              # Launch terminal UI
    python vj_console.py --karaoke    # Run karaoke engine only
    python vj_console.py --audio      # Check audio setup
    python vj_console.py --help       # Show all options

Controls (in terminal UI):
    Up/Down arrows or j/k: Navigate menu
    Enter: Select/toggle option
    q: Quit
    d: Toggle daemon mode
    K: Toggle karaoke engine
    r: Restart selected app
"""

import os
import sys
import time
import signal
import subprocess
import logging
import argparse
from pathlib import Path
from threading import Thread, Event
from dataclasses import dataclass, field
from typing import List, Optional, Dict
import shutil

# Load .env file if present (before other imports)
try:
    from dotenv import load_dotenv
    env_locations = [
        Path.cwd() / '.env',
        Path(__file__).parent / '.env',
        Path.home() / '.env',
    ]
    for env_path in env_locations:
        if env_path.exists():
            load_dotenv(env_path)
            break
except ImportError:
    pass

# Terminal UI
try:
    from blessed import Terminal
    BLESSED_AVAILABLE = True
except ImportError:
    BLESSED_AVAILABLE = False

# Process management
try:
    import psutil
    PSUTIL_AVAILABLE = True
except ImportError:
    PSUTIL_AVAILABLE = False

# Import karaoke engine module
from karaoke_engine import KaraokeEngine, Config as KaraokeConfig, Settings

# Import audio setup module (for --audio command)
try:
    from audio_setup import AudioSetup, print_status as print_audio_status
    AUDIO_SETUP_AVAILABLE = True
except ImportError:
    AUDIO_SETUP_AVAILABLE = False

# Configure logging to file only (not to stderr which messes up terminal UI)
log_file = Path(__file__).parent / 'vj_console.log'
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[logging.FileHandler(log_file)]
)
logger = logging.getLogger('vj_console')


@dataclass
class ProcessingApp:
    """Represents a Processing sketch that can be launched."""
    name: str
    path: Path
    description: str = ""
    process: Optional[subprocess.Popen] = None
    restart_count: int = 0
    last_restart: float = 0
    enabled: bool = False


@dataclass
class AppState:
    """Current state of the VJ Console."""
    selected_index: int = 0
    daemon_mode: bool = False
    karaoke_enabled: bool = True
    running: bool = True
    message: str = ""
    message_time: float = 0


class ProcessManager:
    """Manages Processing app processes with auto-restart."""
    
    def __init__(self, processing_path: Optional[str] = None):
        self.apps: List[ProcessingApp] = []
        self.monitor_thread: Optional[Thread] = None
        self.stop_event = Event()
        
        # Find Processing executable
        self.processing_cmd = self._find_processing(processing_path)
        if self.processing_cmd:
            logger.info(f"Processing found: {self.processing_cmd}")
        else:
            logger.warning("Processing not found in PATH. Apps must be run manually.")
    
    def _find_processing(self, custom_path: Optional[str] = None) -> Optional[str]:
        """Find the Processing executable."""
        if custom_path and Path(custom_path).exists():
            return custom_path
        
        # Common locations
        candidates = [
            "processing-java",  # Linux/CLI
            "/Applications/Processing.app/Contents/MacOS/Processing",  # macOS
            Path.home() / "Applications" / "Processing.app" / "Contents" / "MacOS" / "Processing",
        ]
        
        # Check PATH first
        processing_java = shutil.which("processing-java")
        if processing_java:
            return processing_java
        
        for candidate in candidates:
            if isinstance(candidate, str):
                if shutil.which(candidate):
                    return candidate
            elif candidate.exists():
                return str(candidate)
        
        return None
    
    def discover_apps(self, project_root: Path) -> List[ProcessingApp]:
        """Discover Processing sketches in the project."""
        self.apps = []
        
        # Look for .pde files in processing-vj/examples
        examples_dir = project_root / "processing-vj" / "examples"
        if not examples_dir.exists():
            logger.warning(f"Examples directory not found: {examples_dir}")
            return self.apps
        
        for sketch_dir in examples_dir.iterdir():
            if sketch_dir.is_dir():
                pde_files = list(sketch_dir.glob("*.pde"))
                if pde_files:
                    # Use main .pde file that matches directory name
                    main_file = sketch_dir / f"{sketch_dir.name}.pde"
                    if not main_file.exists() and pde_files:
                        main_file = pde_files[0]
                    
                    description = self._extract_description(main_file)
                    
                    self.apps.append(ProcessingApp(
                        name=sketch_dir.name,
                        path=sketch_dir,
                        description=description
                    ))
        
        self.apps.sort(key=lambda a: a.name)
        logger.info(f"Discovered {len(self.apps)} Processing apps")
        return self.apps
    
    def _extract_description(self, pde_file: Path) -> str:
        """Extract description from Processing sketch comments."""
        try:
            content = pde_file.read_text()
            # Look for first line comment or docstring
            lines = content.split('\n')
            for line in lines[:20]:  # Check first 20 lines
                line = line.strip()
                if line.startswith('/**') or line.startswith('/*'):
                    continue
                if line.startswith('*') and len(line) > 2:
                    desc = line.lstrip('* ').strip()
                    if desc and not desc.startswith('@'):
                        return desc[:60]  # Truncate
                if line.startswith('//'):
                    desc = line.lstrip('/ ').strip()
                    if desc:
                        return desc[:60]
        except Exception:
            pass
        return ""
    
    def launch_app(self, app: ProcessingApp) -> bool:
        """Launch a Processing app."""
        if app.process and app.process.poll() is None:
            logger.warning(f"{app.name} is already running")
            return False
        
        if not self.processing_cmd:
            logger.error("Processing not found. Cannot launch apps.")
            return False
        
        try:
            # Use processing-java to run the sketch
            cmd = [
                self.processing_cmd,
                "--sketch=" + str(app.path),
                "--run"
            ]
            
            # Start in new process group for proper cleanup
            app.process = subprocess.Popen(
                cmd,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                start_new_session=True
            )
            app.enabled = True
            app.last_restart = time.time()
            logger.info(f"Launched {app.name} (PID: {app.process.pid})")
            return True
            
        except Exception as e:
            logger.error(f"Failed to launch {app.name}: {e}")
            return False
    
    def stop_app(self, app: ProcessingApp):
        """Stop a running Processing app."""
        if app.process:
            try:
                # Try graceful termination first
                app.process.terminate()
                try:
                    app.process.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    app.process.kill()
                logger.info(f"Stopped {app.name}")
            except Exception as e:
                logger.error(f"Error stopping {app.name}: {e}")
            finally:
                app.process = None
        app.enabled = False
    
    def is_running(self, app: ProcessingApp) -> bool:
        """Check if an app is currently running."""
        if app.process is None:
            return False
        return app.process.poll() is None
    
    def start_monitoring(self, daemon_mode: bool = True):
        """Start background thread to monitor and restart crashed apps."""
        self.stop_event.clear()
        self.monitor_thread = Thread(target=self._monitor_loop, args=(daemon_mode,), daemon=True)
        self.monitor_thread.start()
    
    def stop_monitoring(self):
        """Stop the monitoring thread."""
        self.stop_event.set()
        if self.monitor_thread:
            self.monitor_thread.join(timeout=2)
    
    def _monitor_loop(self, daemon_mode: bool):
        """Monitor running apps and restart if crashed (daemon mode)."""
        while not self.stop_event.is_set():
            for app in self.apps:
                if app.enabled and not self.is_running(app):
                    if daemon_mode:
                        # App crashed - restart it
                        cooldown = min(30, 5 * (app.restart_count + 1))
                        if time.time() - app.last_restart > cooldown:
                            logger.warning(f"{app.name} crashed. Restarting...")
                            app.restart_count += 1
                            self.launch_app(app)
                    else:
                        logger.info(f"{app.name} exited")
                        app.enabled = False
            
            time.sleep(2)
    
    def cleanup(self):
        """Stop all running apps and monitoring."""
        self.stop_monitoring()
        for app in self.apps:
            if self.is_running(app):
                self.stop_app(app)


class VJConsole:
    """
    Main VJ Console application with colorful terminal UI.
    
    Features:
    - Arrow key navigation
    - Color-coded status indicators
    - Live OSC status display
    - Auto-refresh display
    """
    
    def __init__(self, project_root: Optional[Path] = None):
        self.term = Terminal() if BLESSED_AVAILABLE else None
        self.project_root = project_root or self._find_project_root()
        
        self.process_manager = ProcessManager()
        self.process_manager.discover_apps(self.project_root)
        
        self.karaoke_engine: Optional[KaraokeEngine] = None
        self.state = AppState()
        
        # Build menu with item types
        self._build_menu()
    
    def _build_menu(self):
        """Build the menu items list with types."""
        self.menu_items = []
        
        # Processing Apps section
        self.menu_items.append(("═══ Processing Apps ═══", None, "header"))
        if self.process_manager.apps:
            for app in self.process_manager.apps:
                self.menu_items.append((app.name, app, "app"))
        else:
            self.menu_items.append(("  (no apps found)", None, "disabled"))
        
        # Services section
        self.menu_items.append(("═══ Services ═══", None, "header"))
        self.menu_items.append(("🎤 Karaoke Engine", "karaoke", "service"))
        
        # Settings section
        self.menu_items.append(("═══ Settings ═══", None, "header"))
        self.menu_items.append(("⚡ Daemon Mode (auto-restart)", "daemon", "toggle"))
        
        # Actions section
        self.menu_items.append(("═══ Actions ═══", None, "header"))
        self.menu_items.append(("⏹  Stop All Apps", "stop_all", "action"))
        self.menu_items.append(("❌ Quit", "quit", "action"))
    
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
    
    def start_karaoke(self):
        """Start the karaoke engine."""
        if self.karaoke_engine:
            return
        
        try:
            self.karaoke_engine = KaraokeEngine()
            self.karaoke_engine.start()
            self.state.karaoke_enabled = True
            self.set_message("✓ Karaoke Engine started", "success")
        except Exception as e:
            self.set_message(f"✗ Karaoke error: {e}", "error")
            logger.exception("Karaoke start error")
        
    def stop_karaoke(self):
        """Stop the karaoke engine."""
        if self.karaoke_engine:
            self.karaoke_engine.stop()
            self.karaoke_engine = None
        self.state.karaoke_enabled = False
        self.set_message("✓ Karaoke Engine stopped", "info")
    
    def set_message(self, msg: str, msg_type: str = "info"):
        """Set a temporary status message with type."""
        self.state.message = msg
        self.state.message_type = msg_type
        self.state.message_time = time.time()
    
    def handle_selection(self):
        """Handle menu item selection."""
        if self.state.selected_index >= len(self.menu_items):
            return
        
        label, item, item_type = self.menu_items[self.state.selected_index]
        
        if item is None or item_type in ("header", "disabled"):
            return
        
        if isinstance(item, ProcessingApp):
            if self.process_manager.is_running(item):
                self.process_manager.stop_app(item)
                self.set_message(f"⏹ Stopped {item.name}", "info")
            else:
                if self.process_manager.launch_app(item):
                    self.set_message(f"▶ Launched {item.name}", "success")
                else:
                    self.set_message(f"✗ Failed to launch {item.name}", "error")
        
        elif item == "karaoke":
            if self.state.karaoke_enabled:
                self.stop_karaoke()
            else:
                self.start_karaoke()
        
        elif item == "daemon":
            self.state.daemon_mode = not self.state.daemon_mode
            if self.state.daemon_mode:
                self.process_manager.start_monitoring(daemon_mode=True)
                self.set_message("⚡ Daemon mode enabled", "success")
            else:
                self.process_manager.stop_monitoring()
                self.set_message("⚡ Daemon mode disabled", "info")
        
        elif item == "stop_all":
            count = 0
            for app in self.process_manager.apps:
                if self.process_manager.is_running(app):
                    self.process_manager.stop_app(app)
                    count += 1
            self.set_message(f"⏹ Stopped {count} apps", "info")
        
        elif item == "quit":
            self.state.running = False
    
    def navigate(self, direction: int):
        """Navigate menu up or down, skipping headers."""
        new_index = self.state.selected_index + direction
        attempts = 0
        max_attempts = len(self.menu_items)
        
        while attempts < max_attempts:
            if new_index < 0:
                new_index = len(self.menu_items) - 1
            elif new_index >= len(self.menu_items):
                new_index = 0
            
            _, item, item_type = self.menu_items[new_index]
            if item is not None and item_type not in ("header", "disabled"):
                self.state.selected_index = new_index
                break
            
            new_index += direction
            attempts += 1
    
    def draw(self):
        """Draw the colorful terminal UI with OSC panel."""
        t = self.term
        
        # Clear screen
        print(t.home + t.clear)
        
        # Header bar
        header = " 🎛  VJ Console - Synesthesia Visuals "
        padding = (t.width - len(header) + 4) // 2
        print(t.white_on_blue(" " * t.width))
        print(t.white_on_blue(" " * padding + t.bold(header) + " " * (t.width - padding - len(header) + 2)))
        print(t.white_on_blue(" " * t.width))
        print()
        
        # Status indicators
        daemon_icon = t.bold_green("● ON ") if self.state.daemon_mode else t.dim("○ OFF")
        karaoke_icon = t.bold_green("● ON ") if self.state.karaoke_enabled else t.dim("○ OFF")
        
        print(f"  {t.bold('Daemon:')} {daemon_icon}    {t.bold('Karaoke:')} {karaoke_icon}")
        print()
        
        # Menu items
        for i, (label, item, item_type) in enumerate(self.menu_items):
            if item_type == "header":
                print()
                print(t.bold_magenta(f"  {label}"))
                continue
            
            if item_type == "disabled":
                print(t.dim(f"    {label}"))
                continue
            
            # Selection highlighting
            is_selected = i == self.state.selected_index
            if is_selected:
                prefix = t.bold_black_on_cyan(" ▸ ")
            else:
                prefix = "   "
            
            # Status indicator
            status = ""
            status_color = t.dim
            
            if isinstance(item, ProcessingApp):
                if self.process_manager.is_running(item):
                    status = " [running]"
                    status_color = t.bold_green
                elif item.enabled:
                    status = " [starting...]"
                    status_color = t.yellow
            elif item == "karaoke":
                if self.state.karaoke_enabled:
                    status = " [running]"
                    status_color = t.bold_green
            elif item == "daemon":
                if self.state.daemon_mode:
                    status = " [enabled]"
                    status_color = t.bold_green
            
            # Build line
            if is_selected:
                text = f"{prefix}{label}{status}"
                padding = " " * max(0, 50 - len(label) - len(status))
                print(t.black_on_cyan(text + padding))
            else:
                print(f"{prefix}{label}{status_color(status)}")
        
        print()
        
        # Services panel (show detected services)
        self._draw_services_panel(t)
        
        # OSC Info Panel
        self._draw_osc_panel(t)
        
        # Status message
        if self.state.message and time.time() - self.state.message_time < 4:
            msg_type = getattr(self.state, 'message_type', 'info')
            if msg_type == "success":
                print(t.bold_green(f"  {self.state.message}"))
            elif msg_type == "error":
                print(t.bold_red(f"  {self.state.message}"))
            elif msg_type == "warning":
                print(t.bold_yellow(f"  {self.state.message}"))
            else:
                print(t.cyan(f"  {self.state.message}"))
        
        # Help footer
        print()
        print(t.dim("─" * min(t.width, 80)))
        help_text = "  ↑↓: Navigate   +/-: Timing   Enter: Select   d: Daemon   K: Karaoke   q: Quit"
        print(t.dim(help_text))
    
    def _draw_osc_panel(self, t):
        """Draw OSC connection info, pipeline status, and logs."""
        host = KaraokeConfig.DEFAULT_OSC_HOST
        port = KaraokeConfig.DEFAULT_OSC_PORT
        
        if self.state.karaoke_enabled and self.karaoke_engine:
            # Show timing offset
            offset_ms = self.karaoke_engine.timing_offset_ms
            offset_str = f"{offset_ms:+d}ms" if offset_ms != 0 else "0ms"
            print(t.bold_yellow("  ═══ OSC Status ═══"))
            print(t.green(f"    📡 Sending to {host}:{port}  ⏱ Offset: {offset_str}"))
            
            state = self.karaoke_engine._state
            if state.active and state.track:
                print(t.bold_cyan(f"    🎵 {state.track.artist} - {state.track.title}"))
                
                # Show pipeline status
                pipeline = self.karaoke_engine.pipeline
                print()
                print(t.bold_magenta("  ═══ Processing Pipeline ═══"))
                
                for color, text in pipeline.get_display_lines():
                    if color == "green":
                        print(t.green(text))
                    elif color == "yellow":
                        print(t.yellow(text))
                    elif color == "red":
                        print(t.red(text))
                    else:
                        print(t.dim(text))
                
                # Show image prompt if available
                if pipeline.image_prompt:
                    print()
                    print(t.bold_cyan("  ═══ Image Prompt ═══"))
                    # Word wrap the prompt
                    prompt = pipeline.image_prompt[:200] + "..." if len(pipeline.image_prompt) > 200 else pipeline.image_prompt
                    print(t.cyan(f"    {prompt}"))
                
                # Show recent logs
                logs = pipeline.get_log_lines(5)
                if logs:
                    print()
                    print(t.bold_yellow("  ═══ Logs ═══"))
                    for log in logs:
                        print(t.dim(f"    {log}"))
                
                # Show current lyrics info
                if state.lines:
                    from karaoke_engine import get_active_line_index
                    adjusted_pos = state.position_sec + (offset_ms / 1000.0)
                    idx = get_active_line_index(state.lines, adjusted_pos)
                    
                    if 0 <= idx < len(state.lines):
                        line = state.lines[idx]
                        print()
                        print(t.bold_white(f"    ♪ {line.text}"))
                        if line.keywords:
                            print(t.yellow(f"      Keywords: {line.keywords}"))
                        if line.is_refrain:
                            print(t.magenta(f"      [REFRAIN]"))
            else:
                print(t.dim(f"    (waiting for playback...)"))
        else:
            print(t.bold_yellow("  ═══ OSC Status ═══"))
            print(t.dim(f"    ○ OSC inactive"))
            print(t.dim(f"    Target: {host}:{port}"))
        
        print()
    
    def _draw_services_panel(self, t):
        """Draw detected services status."""
        print(t.bold_blue("  ═══ Services ═══"))
        
        # Check Spotify
        if KaraokeConfig.has_spotify_credentials():
            print(t.green("    ✓ Spotify API      Credentials configured"))
        else:
            print(t.dim("    ○ Spotify API      Set SPOTIPY_* env vars or .env"))
        
        # Check VirtualDJ
        vdj_path = KaraokeConfig.find_vdj_path()
        if vdj_path and vdj_path.exists():
            print(t.green(f"    ✓ VirtualDJ        {vdj_path.name}"))
        elif vdj_path:
            print(t.yellow(f"    ◐ VirtualDJ        Monitoring {vdj_path.name}"))
        else:
            print(t.dim("    ○ VirtualDJ        Folder not found"))
        
        # Check Ollama
        try:
            import requests
            resp = requests.get("http://localhost:11434/api/tags", timeout=1)
            if resp.status_code == 200:
                models = resp.json().get('models', [])
                if models:
                    names = [m.get('name', '').split(':')[0] for m in models[:3]]
                    print(t.green(f"    ✓ Ollama LLM       {', '.join(names)}"))
                else:
                    print(t.yellow("    ◐ Ollama LLM       Running (no models)"))
            else:
                print(t.dim("    ○ Ollama LLM       Not responding"))
        except:
            print(t.dim("    ○ Ollama LLM       Not running (ollama serve)"))
        
        # Check ComfyUI
        try:
            import requests
            resp = requests.get("http://127.0.0.1:8188/system_stats", timeout=1)
            if resp.status_code == 200:
                print(t.green("    ✓ ComfyUI          http://127.0.0.1:8188"))
            else:
                print(t.dim("    ○ ComfyUI          Not responding"))
        except:
            print(t.dim("    ○ ComfyUI          Not running (port 8188)"))
        
        # Check OpenAI
        import os
        if os.environ.get('OPENAI_API_KEY'):
            print(t.green("    ✓ OpenAI API       Key configured"))
        else:
            print(t.dim("    ○ OpenAI API       OPENAI_API_KEY not set"))
        
        print()
    
    def run(self):
        """Main run loop with robust error handling."""
        if not self.term:
            print("Error: Terminal not available")
            return
        
        # Find first selectable item
        for i, (_, item, item_type) in enumerate(self.menu_items):
            if item is not None and item_type not in ("header", "disabled"):
                self.state.selected_index = i
                break
        
        try:
            with self.term.fullscreen(), self.term.cbreak(), self.term.hidden_cursor():
                while self.state.running:
                    try:
                        self.draw()
                        
                        key = self.term.inkey(timeout=0.5)
                        
                        if key:
                            if key.name == 'KEY_UP' or key == 'k':
                                self.navigate(-1)
                            elif key.name == 'KEY_DOWN' or key == 'j':
                                self.navigate(1)
                            elif key.name == 'KEY_ENTER' or key == '\n':
                                self.handle_selection()
                            elif key == 'd':
                                self._toggle_daemon()
                            elif key == 'K':
                                if self.state.karaoke_enabled:
                                    self.stop_karaoke()
                                else:
                                    self.start_karaoke()
                            elif key == 'r':
                                self._restart_selected()
                            elif key == '+' or key == '=':
                                self._adjust_timing(+200)
                            elif key == '-' or key == '_':
                                self._adjust_timing(-200)
                            elif key == 'q' or key.name == 'KEY_ESCAPE':
                                self.state.running = False
                    except Exception as e:
                        logger.exception("Draw error")
                        self.set_message(f"Error: {e}", "error")
                        time.sleep(0.5)
        except Exception as e:
            logger.exception("Fatal UI error")
            print(f"\nUI Error: {e}")
        finally:
            self.stop_karaoke()
            self.process_manager.cleanup()
            print("\n  VJ Console closed. Goodbye! 👋\n")
    
    def _toggle_daemon(self):
        """Toggle daemon mode."""
        self.state.daemon_mode = not self.state.daemon_mode
        if self.state.daemon_mode:
            self.process_manager.start_monitoring(daemon_mode=True)
            self.set_message("⚡ Daemon mode enabled", "success")
        else:
            self.process_manager.stop_monitoring()
            self.set_message("⚡ Daemon mode disabled", "info")
    
    def _restart_selected(self):
        """Restart the selected app."""
        if self.state.selected_index >= len(self.menu_items):
            return
        _, item, _ = self.menu_items[self.state.selected_index]
        if isinstance(item, ProcessingApp):
            self.process_manager.stop_app(item)
            time.sleep(0.5)
            self.process_manager.launch_app(item)
            self.set_message(f"🔄 Restarted {item.name}", "success")
    
    def _adjust_timing(self, delta_ms: int):
        """Adjust karaoke timing offset by delta milliseconds."""
        if self.karaoke_engine:
            new_offset = self.karaoke_engine.adjust_timing(delta_ms)
            sign = "+" if new_offset >= 0 else ""
            self.set_message(f"⏱ Timing: {sign}{new_offset}ms", "info")
        else:
            # Adjust settings even without engine running
            settings = Settings()
            new_offset = settings.adjust_timing(delta_ms)
            sign = "+" if new_offset >= 0 else ""
            self.set_message(f"⏱ Timing: {sign}{new_offset}ms (saved)", "info")


# =============================================================================
# STANDALONE MODES
# =============================================================================

def run_karaoke_only():
    """Run karaoke engine in standalone mode."""
    print("\n" + "="*50)
    print("  🎤 Karaoke Engine - Standalone Mode")
    print("="*50)
    
    vdj_path = KaraokeConfig.find_vdj_path()
    print(f"\n  OSC: localhost:{KaraokeConfig.DEFAULT_OSC_PORT}")
    print(f"  VirtualDJ: {vdj_path or 'not found'}")
    print(f"  Spotify: {'configured' if KaraokeConfig.has_spotify_credentials() else 'not configured'}")
    print("\n  Press Ctrl+C to stop\n")
    
    engine = KaraokeEngine()
    try:
        engine.run()
    except KeyboardInterrupt:
        print("\n  Goodbye! 👋")


def run_audio_check(fix: bool = False):
    """Run audio setup check."""
    if sys.platform != 'darwin':
        print("Audio setup check is designed for macOS only.")
        print("On macOS, it verifies BlackHole and Multi-Output Device configuration.")
        return
    
    if not AUDIO_SETUP_AVAILABLE:
        print("Error: audio_setup module not available")
        return
    
    audio = AudioSetup()
    results = audio.check_system()
    print_audio_status(results)
    
    if fix:
        print("Attempting to fix audio setup...")
        if audio.fix_audio_setup():
            print("✅ Successfully updated default audio output!")
            results = audio.check_system()
            print_audio_status(results)
        else:
            print("❌ Could not automatically fix audio setup.")
            print("Please configure manually in System Settings → Sound")


def main():
    """Main entry point with multiple modes."""
    parser = argparse.ArgumentParser(
        description='VJ Console - Control center for VJ performances',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Modes:
  (default)     Launch terminal UI
  --karaoke     Run karaoke engine only (no UI)
  --audio       Check macOS audio setup
  --audio --fix Attempt to fix audio routing

Examples:
  python vj_console.py              # Full terminal UI
  python vj_console.py --karaoke    # Karaoke engine only
  python vj_console.py --audio      # Check audio
"""
    )
    parser.add_argument('--karaoke', action='store_true',
                        help='Run karaoke engine in standalone mode')
    parser.add_argument('--audio', action='store_true',
                        help='Check macOS audio setup (BlackHole, Multi-Output)')
    parser.add_argument('--fix', action='store_true',
                        help='Attempt to fix audio routing (use with --audio)')
    parser.add_argument('-v', '--verbose', action='store_true',
                        help='Enable verbose logging')
    
    args = parser.parse_args()
    
    if args.verbose:
        logging.getLogger().setLevel(logging.DEBUG)
        console_handler = logging.StreamHandler()
        console_handler.setLevel(logging.DEBUG)
        logging.getLogger().addHandler(console_handler)
    
    # Mode: Audio check
    if args.audio:
        run_audio_check(fix=args.fix)
        return
    
    # Mode: Karaoke only
    if args.karaoke:
        run_karaoke_only()
        return
    
    # Mode: Full terminal UI (default)
    if not BLESSED_AVAILABLE:
        print("Error: blessed library required for terminal UI.")
        print("Install with: pip install blessed")
        print("\nAlternatively, run in standalone mode:")
        print("  python vj_console.py --karaoke")
        sys.exit(1)
    
    try:
        console = VJConsole()
        console.run()
    except KeyboardInterrupt:
        print("\nInterrupted.")
    except Exception as e:
        logger.exception("Fatal error")
        print(f"Error: {e}")
        sys.exit(1)


if __name__ == '__main__':
    main()
