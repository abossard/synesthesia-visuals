#!/usr/bin/env python3
"""
VJ Console - Terminal UI for managing VJ applications

A console application that:
- Lists and manages Processing apps from the project
- Runs apps in daemon mode with auto-restart on crash
- Monitors Spotify/VirtualDJ via the Karaoke Engine

Requirements:
    pip install blessed psutil

Usage:
    python vj_console.py

Controls:
    Up/Down arrows: Navigate menu
    Enter: Select/toggle option
    q: Quit
    d: Toggle daemon mode
    r: Restart selected app
"""

import os
import sys
import time
import signal
import subprocess
import logging
from pathlib import Path
from threading import Thread, Event
from dataclasses import dataclass, field
from typing import List, Optional, Dict
import shutil

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

# Import karaoke engine
from karaoke_engine import KaraokeEngine

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[logging.FileHandler('vj_console.log'), logging.StreamHandler()]
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
    """Main VJ Console application with terminal UI."""
    
    def __init__(self, project_root: Optional[Path] = None):
        if not BLESSED_AVAILABLE:
            raise RuntimeError("blessed library required. Install with: pip install blessed")
        
        self.term = Terminal()
        self.project_root = project_root or self._find_project_root()
        
        self.process_manager = ProcessManager()
        self.process_manager.discover_apps(self.project_root)
        
        self.karaoke_engine: Optional[KaraokeEngine] = None
        self.state = AppState()
        
        # Menu items: apps + special options
        self.menu_items = [
            ("─── Processing Apps ───", None),  # Header
        ] + [
            (app.name, app) for app in self.process_manager.apps
        ] + [
            ("─── Services ───", None),  # Header
            ("Karaoke Engine", "karaoke"),
            ("─── Actions ───", None),  # Header
            ("Toggle Daemon Mode", "daemon"),
            ("Stop All Apps", "stop_all"),
            ("Quit", "quit"),
        ]
    
    def _find_project_root(self) -> Path:
        """Find the project root directory."""
        # Start from current script location
        current = Path(__file__).parent.parent
        
        # Look for processing-vj directory
        if (current / "processing-vj").exists():
            return current
        
        # Try current working directory
        cwd = Path.cwd()
        if (cwd / "processing-vj").exists():
            return cwd
        
        # Go up from script location
        for _ in range(3):
            current = current.parent
            if (current / "processing-vj").exists():
                return current
        
        return Path.cwd()
    
    def start_karaoke(self):
        """Start the karaoke engine."""
        if self.karaoke_engine and self.karaoke_engine.running:
            return
        
        self.karaoke_engine = KaraokeEngine()
        self.karaoke_engine.start()
        self.state.karaoke_enabled = True
        self.set_message("Karaoke Engine started")
    
    def stop_karaoke(self):
        """Stop the karaoke engine."""
        if self.karaoke_engine:
            self.karaoke_engine.stop()
            self.karaoke_engine = None
        self.state.karaoke_enabled = False
        self.set_message("Karaoke Engine stopped")
    
    def set_message(self, msg: str):
        """Set a temporary status message."""
        self.state.message = msg
        self.state.message_time = time.time()
    
    def handle_selection(self):
        """Handle menu item selection."""
        if self.state.selected_index >= len(self.menu_items):
            return
        
        label, item = self.menu_items[self.state.selected_index]
        
        if item is None:
            # Header - skip
            return
        
        if isinstance(item, ProcessingApp):
            # Toggle app running state
            if self.process_manager.is_running(item):
                self.process_manager.stop_app(item)
                self.set_message(f"Stopped {item.name}")
            else:
                if self.process_manager.launch_app(item):
                    self.set_message(f"Launched {item.name}")
                else:
                    self.set_message(f"Failed to launch {item.name}")
        
        elif item == "karaoke":
            if self.state.karaoke_enabled:
                self.stop_karaoke()
            else:
                self.start_karaoke()
        
        elif item == "daemon":
            self.state.daemon_mode = not self.state.daemon_mode
            status = "enabled" if self.state.daemon_mode else "disabled"
            self.set_message(f"Daemon mode {status}")
            if self.state.daemon_mode:
                self.process_manager.start_monitoring(daemon_mode=True)
            else:
                self.process_manager.stop_monitoring()
        
        elif item == "stop_all":
            for app in self.process_manager.apps:
                if self.process_manager.is_running(app):
                    self.process_manager.stop_app(app)
            self.set_message("Stopped all apps")
        
        elif item == "quit":
            self.state.running = False
    
    def navigate(self, direction: int):
        """Navigate menu up or down."""
        new_index = self.state.selected_index + direction
        
        # Skip headers
        while 0 <= new_index < len(self.menu_items):
            if self.menu_items[new_index][1] is not None:
                self.state.selected_index = new_index
                break
            new_index += direction
            if new_index < 0:
                new_index = len(self.menu_items) - 1
            elif new_index >= len(self.menu_items):
                new_index = 0
    
    def draw(self):
        """Draw the terminal UI."""
        # Clear screen
        print(self.term.home + self.term.clear)
        
        # Header
        header = " VJ Console - Synesthesia Visuals "
        print(self.term.center(self.term.bold_white_on_blue(header)))
        print()
        
        # Status bar
        daemon_status = self.term.green("●") if self.state.daemon_mode else self.term.red("○")
        karaoke_status = self.term.green("●") if self.state.karaoke_enabled else self.term.red("○")
        
        status_line = f"  Daemon: {daemon_status}  Karaoke: {karaoke_status}"
        print(status_line)
        print()
        
        # Menu items
        for i, (label, item) in enumerate(self.menu_items):
            if item is None:
                # Header
                print(self.term.bold(f"  {label}"))
                continue
            
            # Selection indicator
            if i == self.state.selected_index:
                prefix = self.term.bold_white_on_blue(" ▶ ")
            else:
                prefix = "   "
            
            # Status indicator
            status = ""
            if isinstance(item, ProcessingApp):
                if self.process_manager.is_running(item):
                    status = self.term.green(" [running]")
                elif item.enabled:
                    status = self.term.yellow(" [starting]")
            elif item == "karaoke" and self.state.karaoke_enabled:
                status = self.term.green(" [running]")
            elif item == "daemon" and self.state.daemon_mode:
                status = self.term.green(" [enabled]")
            
            # Description
            desc = ""
            if isinstance(item, ProcessingApp) and item.description:
                desc = self.term.dim(f" - {item.description}")
            
            line = f"{prefix}{label}{status}{desc}"
            print(line)
        
        print()
        
        # Karaoke status
        if self.karaoke_engine and self.karaoke_engine.state.active:
            track_info = f"  🎵 {self.karaoke_engine.state.artist} - {self.karaoke_engine.state.title}"
            print(self.term.cyan(track_info))
            if self.karaoke_engine.state.has_synced_lyrics:
                active_line = self.karaoke_engine.compute_active_line()
                if 0 <= active_line < len(self.karaoke_engine.state.lines):
                    lyric = self.karaoke_engine.state.lines[active_line].text
                    print(self.term.white(f"     {lyric}"))
            print()
        
        # Message
        if self.state.message and time.time() - self.state.message_time < 3:
            print(self.term.yellow(f"  {self.state.message}"))
        
        # Help
        print()
        print(self.term.dim("  ↑↓: Navigate  Enter: Select  d: Daemon  q: Quit"))
    
    def run(self):
        """Main run loop."""
        # Find first non-header item
        for i, (_, item) in enumerate(self.menu_items):
            if item is not None:
                self.state.selected_index = i
                break
        
        with self.term.fullscreen(), self.term.cbreak(), self.term.hidden_cursor():
            while self.state.running:
                self.draw()
                
                # Handle input with timeout for refresh
                key = self.term.inkey(timeout=0.5)
                
                if key:
                    if key.name == 'KEY_UP' or key == 'k':
                        self.navigate(-1)
                    elif key.name == 'KEY_DOWN' or key == 'j':
                        self.navigate(1)
                    elif key.name == 'KEY_ENTER' or key == '\n':
                        self.handle_selection()
                    elif key == 'd':
                        # Quick toggle daemon mode
                        self.state.daemon_mode = not self.state.daemon_mode
                        status = "enabled" if self.state.daemon_mode else "disabled"
                        self.set_message(f"Daemon mode {status}")
                    elif key == 'r':
                        # Restart selected app
                        _, item = self.menu_items[self.state.selected_index]
                        if isinstance(item, ProcessingApp):
                            self.process_manager.stop_app(item)
                            time.sleep(0.5)
                            self.process_manager.launch_app(item)
                            self.set_message(f"Restarted {item.name}")
                    elif key == 'q' or key.name == 'KEY_ESCAPE':
                        self.state.running = False
        
        # Cleanup
        self.stop_karaoke()
        self.process_manager.cleanup()
        print("VJ Console closed.")


def main():
    """Main entry point."""
    if not BLESSED_AVAILABLE:
        print("Error: blessed library required.")
        print("Install with: pip install blessed")
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
