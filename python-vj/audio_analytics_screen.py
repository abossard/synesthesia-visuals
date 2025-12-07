#!/usr/bin/env python3
"""
Enhanced Audio Analytics Screen for VJ Console

Uses Textual + Rich for a beautiful, high-performance OSC message monitor
optimized for EDM audio features.

Layout:
- Left: Feature groups tree/table
- Center: RichLog for streaming OSC messages  
- Right: Numeric gauges and meters
- Bottom: Status bar with connection, FPS, dropped messages

Color scheme:
- Rhythm features (beat, BPM): cyan
- Energy features: yellow  
- Spectral features: magenta
- Band energies: colors per band
- System messages: dim gray

Performance optimizations:
- Batched log writes (accumulate messages per render cycle)
- Throttled UI updates (20-30 FPS max)
- Limited log history (2000 lines max)
- Minimal Rich rendering in hot path
"""

from typing import Dict, List, Optional, Tuple, Any, Deque
from collections import deque
from datetime import datetime
import time

from textual.app import ComposeResult
from textual.containers import Container, Horizontal, Vertical, VerticalScroll
from textual.widgets import Static, RichLog, DataTable, Label
from textual.reactive import reactive
from rich.text import Text
from rich.table import Table
from rich.panel import Panel
from rich.bar import Bar
from rich.style import Style

# Feature categorization for color coding
FEATURE_CATEGORIES = {
    # Rhythm (cyan)
    '/beat': 'rhythm',
    '/bpm': 'rhythm',
    '/beat_conf': 'rhythm',
    '/audio/beats': 'rhythm',
    '/audio/bpm': 'rhythm',
    
    # Energy (yellow)
    '/energy': 'energy',
    '/energy_smooth': 'energy',
    '/beat_energy': 'energy',
    '/beat_energy_low': 'energy',
    '/beat_energy_high': 'energy',
    
    # Spectral (magenta)
    '/brightness': 'spectral',
    '/noisiness': 'spectral',
    '/audio/spectral': 'spectral',
    
    # Band energies (color per band)
    '/bass_band': 'band_bass',
    '/mid_band': 'band_mid',
    '/high_band': 'band_high',
    '/audio/levels': 'bands',
    '/audio/spectrum': 'spectrum',
    
    # Structure (green)
    '/audio/structure': 'structure',
    
    # Pitch (blue)
    '/audio/pitch': 'pitch',
    
    # Complexity (white)
    '/dynamic_complexity': 'complexity',
}

CATEGORY_COLORS = {
    'rhythm': 'cyan',
    'energy': 'yellow',
    'spectral': 'magenta',
    'band_bass': 'red',
    'band_mid': 'green',
    'band_high': 'blue',
    'bands': 'white',
    'spectrum': 'bright_white',
    'structure': 'bright_green',
    'pitch': 'bright_blue',
    'complexity': 'white',
    'system': 'dim',
}


class OSCMessageLog(RichLog):
    """
    High-performance OSC message log with batching and throttling.
    """
    
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.message_batch: List[Text] = []
        self.last_flush_time = time.time()
        self.flush_interval = 1.0 / 30  # 30 FPS max
        self.max_lines = 2000
        self.paused = False
        self.filter_text = ""
    
    def add_osc_message(self, address: str, values: List[Any], timestamp: Optional[datetime] = None):
        """Add an OSC message to the batch (will be flushed periodically)."""
        if self.paused:
            return
        
        # Apply filter if set
        if self.filter_text and self.filter_text not in address:
            return
        
        if timestamp is None:
            timestamp = datetime.now()
        
        # Format timestamp
        ts_str = timestamp.strftime("%H:%M:%S.%f")[:-3]
        
        # Get category and color
        category = FEATURE_CATEGORIES.get(address, 'system')
        color = CATEGORY_COLORS.get(category, 'white')
        
        # Format message
        msg = Text()
        msg.append(f"{ts_str} ", style="dim")
        msg.append(f"[{address}]", style=f"bold {color}")
        msg.append(" ", style="")
        
        # Format values based on type
        if isinstance(values, list):
            if len(values) == 1:
                msg.append(f"{values[0]:.3f}" if isinstance(values[0], float) else str(values[0]), style=color)
            else:
                # For multi-value messages, show compact format
                if len(values) <= 5:
                    val_str = " ".join(f"{v:.2f}" if isinstance(v, float) else str(v) for v in values)
                else:
                    # Truncate long arrays
                    val_str = " ".join(f"{v:.2f}" if isinstance(v, float) else str(v) for v in values[:5])
                    val_str += f" ... ({len(values)} values)"
                msg.append(val_str, style=color)
        else:
            msg.append(str(values), style=color)
        
        self.message_batch.append(msg)
    
    def flush_if_needed(self):
        """Flush batched messages if interval has passed."""
        current_time = time.time()
        if current_time - self.last_flush_time >= self.flush_interval:
            self._flush_batch()
            self.last_flush_time = current_time
    
    def _flush_batch(self):
        """Write all batched messages at once."""
        if not self.message_batch:
            return
        
        # Write all messages
        for msg in self.message_batch:
            self.write(msg)
        
        self.message_batch.clear()
    
    def toggle_pause(self):
        """Toggle pause state."""
        self.paused = not self.paused
        return self.paused
    
    def set_filter(self, filter_text: str):
        """Set filter text for messages."""
        self.filter_text = filter_text.lower()


class FeatureGroupsPanel(Static):
    """
    Left panel showing feature groups and categories.
    """
    
    message_counts = reactive({})
    
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.counts_by_category: Dict[str, int] = {}
    
    def compose(self) -> ComposeResult:
        yield Label("OSC Feature Groups", id="feature-groups-title")
        yield DataTable(id="feature-groups-table")
    
    def on_mount(self) -> None:
        """Set up the data table."""
        table = self.query_one("#feature-groups-table", DataTable)
        table.add_columns("Category", "Count", "Rate")
        table.cursor_type = "row"
        
        # Add rows for each category
        categories = [
            ("Rhythm", "rhythm", "cyan"),
            ("Energy", "energy", "yellow"),
            ("Spectral", "spectral", "magenta"),
            ("Bass Band", "band_bass", "red"),
            ("Mid Band", "band_mid", "green"),
            ("High Band", "band_high", "blue"),
            ("Bands (8)", "bands", "white"),
            ("Spectrum (32)", "spectrum", "bright_white"),
            ("Structure", "structure", "bright_green"),
            ("Pitch", "pitch", "bright_blue"),
            ("Complexity", "complexity", "white"),
        ]
        
        for name, cat_key, color in categories:
            table.add_row(name, "0", "0 Hz", key=cat_key)
            self.counts_by_category[cat_key] = 0
    
    def watch_message_counts(self, counts: Dict[str, int]):
        """Update message counts in table."""
        table = self.query_one("#feature-groups-table", DataTable)
        
        # Aggregate counts by category
        category_totals = {}
        for address, count in counts.items():
            category = FEATURE_CATEGORIES.get(address, 'system')
            category_totals[category] = category_totals.get(category, 0) + count
        
        # Update table rows
        for cat_key, count in category_totals.items():
            if cat_key in self.counts_by_category:
                prev_count = self.counts_by_category[cat_key]
                # Simple rate calculation (messages per second since last update)
                rate = max(0, count - prev_count)
                self.counts_by_category[cat_key] = count
                
                try:
                    table.update_cell(cat_key, "Count", str(count))
                    table.update_cell(cat_key, "Rate", f"{rate} Hz")
                except Exception:
                    pass  # Row might not exist


class MetricsPanel(Static):
    """
    Right panel showing numeric gauges and current values.
    """
    
    features = reactive({})
    
    def on_mount(self) -> None:
        """Initialize the metrics display."""
        self.update_display()
    
    def watch_features(self, data: Dict[str, Any]):
        """Update when features change."""
        self.update_display()
    
    def update_display(self):
        """Render the metrics panel."""
        if not self.features:
            self.update("[dim](waiting for audio features...)[/]")
            return
        
        # Build Rich table for metrics
        table = Table.grid(padding=(0, 1))
        table.add_column("Label", style="dim")
        table.add_column("Value")
        table.add_column("Bar")
        
        # Beat indicator
        beat = self.features.get('beat', 0) or self.features.get('/beat', 0)
        beat_icon = "◉" if beat else "○"
        table.add_row("Beat", f"[cyan bold]{beat_icon}[/]", "")
        
        # BPM
        bpm = self.features.get('bpm', 0) or self.features.get('/bpm', 0)
        bpm_conf = self.features.get('bpm_confidence', 0) or self.features.get('/beat_conf', 0)
        table.add_row("BPM", f"[cyan]{bpm:.1f}[/]", f"[dim]conf:{bpm_conf:.2f}[/]")
        
        table.add_row("", "", "")  # Spacer
        
        # Energy
        energy = self.features.get('/energy', 0)
        energy_smooth = self.features.get('/energy_smooth', 0)
        if energy_smooth:
            bar = self._make_bar(energy_smooth, 'yellow')
            table.add_row("Energy", f"[yellow]{energy_smooth:.3f}[/]", bar)
        
        # Beat energies
        beat_energy = self.features.get('/beat_energy', 0)
        if beat_energy:
            bar = self._make_bar(beat_energy, 'yellow')
            table.add_row("Beat Energy", f"[yellow]{beat_energy:.3f}[/]", bar)
        
        beat_energy_low = self.features.get('/beat_energy_low', 0)
        if beat_energy_low:
            bar = self._make_bar(beat_energy_low, 'red')
            table.add_row("  Low", f"[red]{beat_energy_low:.3f}[/]", bar)
        
        beat_energy_high = self.features.get('/beat_energy_high', 0)
        if beat_energy_high:
            bar = self._make_bar(beat_energy_high, 'blue')
            table.add_row("  High", f"[blue]{beat_energy_high:.3f}[/]", bar)
        
        table.add_row("", "", "")  # Spacer
        
        # Band energies
        bass_band = self.features.get('/bass_band', 0)
        mid_band = self.features.get('/mid_band', 0)
        high_band = self.features.get('/high_band', 0)
        
        if bass_band:
            bar = self._make_bar(bass_band, 'red')
            table.add_row("Bass Band", f"[red]{bass_band:.3f}[/]", bar)
        
        if mid_band:
            bar = self._make_bar(mid_band, 'green')
            table.add_row("Mid Band", f"[green]{mid_band:.3f}[/]", bar)
        
        if high_band:
            bar = self._make_bar(high_band, 'blue')
            table.add_row("High Band", f"[blue]{high_band:.3f}[/]", bar)
        
        table.add_row("", "", "")  # Spacer
        
        # Spectral features
        brightness = self.features.get('/brightness', 0)
        if brightness:
            bar = self._make_bar(brightness, 'magenta')
            table.add_row("Brightness", f"[magenta]{brightness:.3f}[/]", bar)
        
        noisiness = self.features.get('/noisiness', 0)
        if noisiness:
            bar = self._make_bar(noisiness, 'magenta')
            table.add_row("Noisiness", f"[magenta]{noisiness:.3f}[/]", bar)
        
        # Structure
        buildup = self.features.get('buildup', False)
        drop = self.features.get('drop', False)
        
        if buildup:
            table.add_row("", "[yellow]▲ BUILD-UP[/]", "")
        if drop:
            table.add_row("", "[red]▼ DROP[/]", "")
        
        # Render as panel
        panel = Panel(table, title="[bold]Audio Metrics[/]", border_style="bright_blue")
        self.update(panel)
    
    def _make_bar(self, value: float, color: str, width: int = 15) -> str:
        """Create a visual bar."""
        filled = int(value * width)
        filled = max(0, min(width, filled))
        return f"[{color}]{'█' * filled}[/][dim]{'░' * (width - filled)}[/]"


class StatusBar(Static):
    """
    Bottom status bar showing connection, FPS, dropped messages.
    """
    
    connection_status = reactive("Disconnected")
    fps = reactive(0.0)
    messages_received = reactive(0)
    messages_dropped = reactive(0)
    
    def compose(self) -> ComposeResult:
        yield Label("", id="status-bar-content")
    
    def on_mount(self) -> None:
        self.update_status()
    
    def watch_connection_status(self, status: str):
        self.update_status()
    
    def watch_fps(self, fps: float):
        self.update_status()
    
    def watch_messages_received(self, count: int):
        self.update_status()
    
    def watch_messages_dropped(self, count: int):
        self.update_status()
    
    def update_status(self):
        """Update the status bar display."""
        # Connection indicator
        if self.connection_status == "Connected":
            conn_text = "[green]● Connected[/]"
        elif self.connection_status == "Connecting":
            conn_text = "[yellow]◐ Connecting[/]"
        else:
            conn_text = "[red]○ Disconnected[/]"
        
        # FPS
        fps_color = "green" if self.fps >= 50 else "yellow" if self.fps >= 30 else "red"
        fps_text = f"[{fps_color}]{self.fps:.1f} fps[/]"
        
        # Messages
        msg_text = f"[cyan]{self.messages_received}[/] msgs"
        
        # Dropped messages (warning if any)
        if self.messages_dropped > 0:
            drop_text = f"[red on black]{self.messages_dropped} dropped[/]"
        else:
            drop_text = "[dim]0 dropped[/]"
        
        # Keyboard hints
        hints = "[dim]f=filter p=pause arrows=scroll[/]"
        
        status_text = f"{conn_text} │ {fps_text} │ {msg_text} │ {drop_text} │ {hints}"
        
        label = self.query_one("#status-bar-content", Label)
        label.update(status_text)


class EnhancedAudioAnalyticsPanel(Container):
    """
    Main container for the enhanced audio analytics UI.
    
    Layout:
    - Left: Feature groups (20% width)
    - Center: OSC message log (50% width)
    - Right: Metrics panel (30% width)
    - Bottom: Status bar (full width)
    """
    
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.message_counts: Dict[str, int] = {}
        self.current_features: Dict[str, Any] = {}
        self.last_update_time = time.time()
        self.frame_times: Deque[float] = deque(maxlen=60)
    
    def compose(self) -> ComposeResult:
        with Horizontal():
            # Left: Feature groups
            with Vertical(id="feature-groups-container"):
                yield FeatureGroupsPanel(id="feature-groups")
            
            # Center: Message log
            with Vertical(id="message-log-container"):
                yield Label("[bold]OSC Message Stream[/]", id="message-log-title")
                yield OSCMessageLog(id="osc-message-log", wrap=False, highlight=True, markup=True)
            
            # Right: Metrics
            with Vertical(id="metrics-container"):
                yield MetricsPanel(id="metrics-panel")
        
        # Bottom: Status bar
        yield StatusBar(id="status-bar")
    
    def on_mount(self) -> None:
        """Set up the panel when mounted."""
        # Set initial sizes via CSS if needed
        pass
    
    def add_osc_message(self, address: str, values: List[Any]):
        """
        Add an OSC message to the log and update metrics.
        
        This is the main entry point for OSC data.
        """
        # Update message counts
        self.message_counts[address] = self.message_counts.get(address, 0) + 1
        
        # Update feature groups panel
        feature_groups = self.query_one("#feature-groups", FeatureGroupsPanel)
        feature_groups.message_counts = self.message_counts.copy()
        
        # Add to message log
        message_log = self.query_one("#osc-message-log", OSCMessageLog)
        message_log.add_osc_message(address, values)
        
        # Update current features for metrics panel
        if isinstance(values, list) and len(values) == 1:
            self.current_features[address] = values[0]
        else:
            self.current_features[address] = values
        
        # Also store by feature name (for legacy compatibility)
        if address == '/audio/beats' and len(values) >= 5:
            self.current_features['beat'] = values[0]
        elif address == '/audio/bpm' and len(values) >= 2:
            self.current_features['bpm'] = values[0]
            self.current_features['bpm_confidence'] = values[1]
        elif address == '/audio/structure' and len(values) >= 4:
            self.current_features['buildup'] = values[0] == 1
            self.current_features['drop'] = values[1] == 1
        
        # Update metrics panel
        metrics_panel = self.query_one("#metrics-panel", MetricsPanel)
        metrics_panel.features = self.current_features.copy()
        
        # Update FPS calculation
        current_time = time.time()
        self.frame_times.append(current_time)
        
        if len(self.frame_times) > 1:
            time_span = self.frame_times[-1] - self.frame_times[0]
            if time_span > 0:
                fps = len(self.frame_times) / time_span
                status_bar = self.query_one("#status-bar", StatusBar)
                status_bar.fps = fps
                status_bar.messages_received = sum(self.message_counts.values())
    
    def flush_log(self):
        """Flush batched messages in the log."""
        message_log = self.query_one("#osc-message-log", OSCMessageLog)
        message_log.flush_if_needed()
    
    def set_connection_status(self, status: str):
        """Update connection status."""
        status_bar = self.query_one("#status-bar", StatusBar)
        status_bar.connection_status = status
    
    def toggle_pause(self) -> bool:
        """Toggle pause state of message log."""
        message_log = self.query_one("#osc-message-log", OSCMessageLog)
        return message_log.toggle_pause()
    
    def set_filter(self, filter_text: str):
        """Set filter for message log."""
        message_log = self.query_one("#osc-message-log", OSCMessageLog)
        message_log.set_filter(filter_text)
