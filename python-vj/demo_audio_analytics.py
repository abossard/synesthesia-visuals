#!/usr/bin/env python3
"""
Standalone demo of the Enhanced Audio Analytics UI.

This demonstrates the new Textual+Rich interface without requiring
the full VJ console or audio analyzer.
"""

import asyncio
import random
from datetime import datetime
from textual.app import App, ComposeResult
from textual.widgets import Header, Footer
from audio_analytics_screen import EnhancedAudioAnalyticsPanel


class AudioAnalyticsDemoApp(App):
    """Demo app showing the enhanced audio analytics UI."""
    
    CSS = """
    Screen {
        background: $surface;
    }
    """
    
    BINDINGS = [
        ("q", "quit", "Quit"),
        ("p", "pause", "Pause/Resume"),
        ("r", "reset", "Reset"),
    ]
    
    def compose(self) -> ComposeResult:
        yield Header()
        yield EnhancedAudioAnalyticsPanel(id="analytics")
        yield Footer()
    
    def on_mount(self) -> None:
        """Start sending simulated OSC data."""
        self.title = "Enhanced Audio Analytics - Demo Mode"
        self.sub_title = "Simulating EDM audio features"
        
        # Set connection status
        panel = self.query_one("#analytics", EnhancedAudioAnalyticsPanel)
        panel.set_connection_status("Connected")
        
        # Start sending mock data
        self.set_interval(1.0 / 60, self._send_mock_data)
        self.set_interval(1.0 / 30, self._flush_log)
        
        self.frame_count = 0
        self.beat_counter = 0
    
    def _send_mock_data(self):
        """Send simulated OSC messages."""
        panel = self.query_one("#analytics", EnhancedAudioAnalyticsPanel)
        
        self.frame_count += 1
        
        # Simulate beat every 30 frames (0.5 seconds at 60 fps = 120 BPM)
        is_beat = (self.frame_count % 30) == 0
        if is_beat:
            self.beat_counter += 1
        
        # Simulate varying energy
        energy_base = 0.5 + 0.3 * random.random()
        if is_beat:
            energy_base = min(1.0, energy_base + 0.4)  # Spike on beats
        
        # Send single-value EDM features
        panel.add_osc_message('/beat', [1.0 if is_beat else 0.0])
        panel.add_osc_message('/bpm', [128.0 + random.uniform(-2, 2)])
        panel.add_osc_message('/beat_conf', [0.85 + random.uniform(-0.1, 0.1)])
        
        panel.add_osc_message('/energy', [energy_base])
        panel.add_osc_message('/energy_smooth', [energy_base * 0.8])
        
        # Beat energies
        beat_energy = 0.7 if is_beat else 0.3 * random.random()
        panel.add_osc_message('/beat_energy', [beat_energy])
        panel.add_osc_message('/beat_energy_low', [beat_energy * 0.8])
        panel.add_osc_message('/beat_energy_high', [beat_energy * 0.4])
        
        # Spectral features
        brightness = 0.4 + 0.3 * random.random()
        noisiness = 0.2 + 0.2 * random.random()
        panel.add_osc_message('/brightness', [brightness])
        panel.add_osc_message('/noisiness', [noisiness])
        
        # Band energies (vary independently)
        bass = 0.6 + 0.3 * random.random()
        mid = 0.5 + 0.2 * random.random()
        high = 0.4 + 0.2 * random.random()
        
        if is_beat:
            bass = min(1.0, bass + 0.3)  # Bass spikes on beats
        
        panel.add_osc_message('/bass_band', [bass])
        panel.add_osc_message('/mid_band', [mid])
        panel.add_osc_message('/high_band', [high])
        
        # Complexity
        panel.add_osc_message('/dynamic_complexity', [0.05 + 0.05 * random.random()])
        
        # Legacy multi-value messages (less frequent)
        if self.frame_count % 5 == 0:
            # 8 frequency bands
            levels = [random.uniform(0.3, 0.8) for _ in range(8)]
            panel.add_osc_message('/audio/levels', levels)
            
            # 32-bin spectrum
            spectrum = [random.uniform(0.1, 0.6) for _ in range(32)]
            panel.add_osc_message('/audio/spectrum', spectrum)
            
            # Beats (5 values)
            panel.add_osc_message('/audio/beats', [
                1 if is_beat else 0,
                0.8 if is_beat else 0.1,
                bass, mid, high
            ])
            
            # BPM
            panel.add_osc_message('/audio/bpm', [128.0, 0.85])
            
            # Spectral
            panel.add_osc_message('/audio/spectral', [brightness, 4500.0, 0.3])
            
            # Structure
            is_buildup = (self.beat_counter % 16) > 12
            is_drop = (self.beat_counter % 16) == 0 and self.beat_counter > 0
            panel.add_osc_message('/audio/structure', [
                1 if is_buildup else 0,
                1 if is_drop else 0,
                0.2 if is_buildup else -0.1,
                brightness
            ])
    
    def _flush_log(self):
        """Flush batched log messages."""
        panel = self.query_one("#analytics", EnhancedAudioAnalyticsPanel)
        panel.flush_log()
    
    def action_pause(self):
        """Toggle pause."""
        panel = self.query_one("#analytics", EnhancedAudioAnalyticsPanel)
        paused = panel.toggle_pause()
        self.notify(f"{'Paused' if paused else 'Resumed'}", severity="information")
    
    def action_reset(self):
        """Reset the display."""
        # Recreate the panel
        self.query_one("#analytics").remove()
        self.mount(EnhancedAudioAnalyticsPanel(id="analytics"), before="#footer")
        panel = self.query_one("#analytics", EnhancedAudioAnalyticsPanel)
        panel.set_connection_status("Connected")
        self.frame_count = 0
        self.beat_counter = 0
        self.notify("Reset", severity="information")


if __name__ == "__main__":
    app = AudioAnalyticsDemoApp()
    app.run()
