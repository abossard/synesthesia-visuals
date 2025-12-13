#!/usr/bin/env python3
"""
Tests for DJ.Studio Monitor

Run with: python -m pytest test_djstudio_monitor.py -v
Or simply: python test_djstudio_monitor.py
"""

import sys
import unittest
import tempfile
import json
from pathlib import Path


class TestDJStudioMonitor(unittest.TestCase):
    """Tests for DJStudioMonitor class."""
    
    def test_import(self):
        """DJStudioMonitor should be importable."""
        from adapters import DJStudioMonitor
        from karaoke_engine import DJStudioMonitor as KE_DJStudioMonitor
    
    def test_initialization(self):
        """DJStudioMonitor should initialize without errors."""
        from adapters import DJStudioMonitor
        
        monitor = DJStudioMonitor()
        self.assertEqual(monitor.monitor_key, "djstudio")
        self.assertEqual(monitor.monitor_label, "DJ.Studio")
    
    def test_file_monitoring_artist_dash_title(self):
        """Should parse 'Artist - Title' from file."""
        from adapters import DJStudioMonitor
        
        with tempfile.NamedTemporaryFile(mode='w', suffix='.txt', delete=False) as f:
            f.write("Daft Punk - Get Lucky")
            f.flush()
            tmp_path = Path(f.name)
        
        try:
            monitor = DJStudioMonitor(file_path=tmp_path)
            playback = monitor.get_playback()
            
            self.assertIsNotNone(playback)
            self.assertEqual(playback['artist'], "Daft Punk")
            self.assertEqual(playback['title'], "Get Lucky")
            self.assertEqual(playback['is_playing'], True)
        finally:
            tmp_path.unlink()
    
    def test_file_monitoring_json_format(self):
        """Should parse JSON format from file."""
        from adapters import DJStudioMonitor
        
        with tempfile.NamedTemporaryFile(mode='w', suffix='.txt', delete=False) as f:
            data = {
                "artist": "Disclosure",
                "title": "Latch",
                "album": "Settle",
                "duration_ms": 252000,
                "progress_ms": 120000
            }
            f.write(json.dumps(data))
            f.flush()
            tmp_path = Path(f.name)
        
        try:
            monitor = DJStudioMonitor(file_path=tmp_path)
            playback = monitor.get_playback()
            
            self.assertIsNotNone(playback)
            self.assertEqual(playback['artist'], "Disclosure")
            self.assertEqual(playback['title'], "Latch")
            self.assertEqual(playback['album'], "Settle")
            self.assertEqual(playback['duration_ms'], 252000)
            self.assertEqual(playback['progress_ms'], 120000)
        finally:
            tmp_path.unlink()
    
    def test_no_file_returns_none(self):
        """Should return None when file doesn't exist."""
        from adapters import DJStudioMonitor
        
        monitor = DJStudioMonitor(file_path=Path("/nonexistent/file.txt"))
        playback = monitor.get_playback()
        
        self.assertIsNone(playback)
    
    def test_empty_file_returns_none(self):
        """Should return None when file is empty."""
        from adapters import DJStudioMonitor
        
        with tempfile.NamedTemporaryFile(mode='w', suffix='.txt', delete=False) as f:
            f.write("")
            f.flush()
            tmp_path = Path(f.name)
        
        try:
            monitor = DJStudioMonitor(file_path=tmp_path)
            playback = monitor.get_playback()
            
            self.assertIsNone(playback)
        finally:
            tmp_path.unlink()
    
    def test_parse_track_string(self):
        """Should correctly parse 'Artist - Title' strings."""
        from adapters import DJStudioMonitor
        
        monitor = DJStudioMonitor()
        
        artist, title = monitor._parse_track_string("Calvin Harris - Summer")
        self.assertEqual(artist, "Calvin Harris")
        self.assertEqual(title, "Summer")
        
        # Test with multiple dashes
        artist, title = monitor._parse_track_string("Swedish House Mafia - Don't You Worry Child")
        self.assertEqual(artist, "Swedish House Mafia")
        self.assertEqual(title, "Don't You Worry Child")
    
    def test_parse_window_title(self):
        """Should extract track info from window titles."""
        from adapters import DJStudioMonitor
        
        monitor = DJStudioMonitor()
        
        # Test various window title formats
        artist, title = monitor._parse_window_title("Avicii - Levels - DJ.Studio")
        self.assertEqual(artist, "Avicii")
        self.assertEqual(title, "Levels")
        
        artist, title = monitor._parse_window_title("Now Playing: Deadmau5 - Strobe")
        self.assertEqual(artist, "Deadmau5")
        self.assertEqual(title, "Strobe")
        
        artist, title = monitor._parse_window_title("DJ.Studio - Flux Pavilion - Bass Cannon")
        self.assertEqual(artist, "Flux Pavilion")
        self.assertEqual(title, "Bass Cannon")
    
    def test_config_integration(self):
        """Config should provide DJ.Studio settings."""
        from infrastructure import Config
        
        config = Config.djstudio_config()
        
        self.assertIn('enabled', config)
        self.assertIn('script_path', config)
        self.assertIn('file_path', config)
        self.assertIn('timeout', config)
        self.assertIsInstance(config['enabled'], bool)
        self.assertIsInstance(config['timeout'], float)


if __name__ == '__main__':
    unittest.main()
