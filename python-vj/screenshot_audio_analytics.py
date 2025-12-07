#!/usr/bin/env python3
"""
Take a screenshot of the Enhanced Audio Analytics UI using Textual's screenshot feature.
"""

import asyncio
import random
from datetime import datetime
from textual.app import App, ComposeResult
from textual.widgets import Header, Footer
from audio_analytics_screen import EnhancedAudioAnalyticsPanel


class AudioAnalyticsScreenshotApp(App):
    """App for taking a screenshot."""
    
    CSS = """
    Screen {
        background: $surface;
    }
    """
    
    def compose(self) -> ComposeResult:
        yield Header()
        yield EnhancedAudioAnalyticsPanel(id="analytics")
        yield Footer()
    
    def on_mount(self) -> None:
        """Set up and take screenshot after data is populated."""
        self.title = "Enhanced Audio Analytics - EDM Monitor"
        self.sub_title = "Real-time OSC Feature Visualization"
        
        # Set connection status
        panel = self.query_one("#analytics", EnhancedAudioAnalyticsPanel)
        panel.set_connection_status("Connected")
        
        # Populate with data
        self._populate_data()
        
        # Take screenshot after a short delay
        self.set_timer(2.0, self._take_screenshot)
    
    def _populate_data(self):
        """Populate with realistic data."""
        panel = self.query_one("#analytics", EnhancedAudioAnalyticsPanel)
        
        # Send several frames of data to fill the log
        for i in range(100):
            is_beat = (i % 30) == 0
            
            # Single-value EDM features
            panel.add_osc_message('/beat', [1.0 if is_beat else 0.0])
            panel.add_osc_message('/bpm', [128.5])
            panel.add_osc_message('/beat_conf', [0.87])
            
            energy = 0.7 if is_beat else 0.5
            panel.add_osc_message('/energy', [energy])
            panel.add_osc_message('/energy_smooth', [0.65])
            
            panel.add_osc_message('/beat_energy', [0.8 if is_beat else 0.2])
            panel.add_osc_message('/beat_energy_low', [0.75 if is_beat else 0.15])
            panel.add_osc_message('/beat_energy_high', [0.45 if is_beat else 0.1])
            
            panel.add_osc_message('/brightness', [0.62])
            panel.add_osc_message('/noisiness', [0.25])
            
            panel.add_osc_message('/bass_band', [0.78])
            panel.add_osc_message('/mid_band', [0.55])
            panel.add_osc_message('/high_band', [0.42])
            
            panel.add_osc_message('/dynamic_complexity', [0.07])
            
            # Multi-value messages
            if i % 5 == 0:
                levels = [0.3, 0.7, 0.6, 0.5, 0.4, 0.3, 0.2, 0.6]
                panel.add_osc_message('/audio/levels', levels)
                
                spectrum = [random.uniform(0.2, 0.6) for _ in range(32)]
                panel.add_osc_message('/audio/spectrum', spectrum)
                
                panel.add_osc_message('/audio/beats', [1 if is_beat else 0, 0.8, 0.7, 0.5, 0.4])
                panel.add_osc_message('/audio/bpm', [128.5, 0.87])
                panel.add_osc_message('/audio/spectral', [0.62, 4200.0, 0.31])
                panel.add_osc_message('/audio/structure', [0, 0, 0.15, 0.62])
        
        # Flush to display
        panel.flush_log()
    
    async def _take_screenshot(self):
        """Take a screenshot."""
        path = "/tmp/audio_analytics_screenshot.svg"
        self.save_screenshot(path)
        print(f"Screenshot saved to: {path}")
        self.exit()


if __name__ == "__main__":
    app = AudioAnalyticsScreenshotApp()
    app.run()
