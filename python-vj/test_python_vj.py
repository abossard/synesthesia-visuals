#!/usr/bin/env python3
"""
Tests for Python VJ Tools

Run with: python -m pytest test_python_vj.py -v
Or simply: python test_python_vj.py
"""

import sys
import unittest
from pathlib import Path


class TestKaraokeEngine(unittest.TestCase):
    """Tests for karaoke_engine module."""
    
    def test_imports(self):
        """All classes and functions should be importable."""
        from karaoke_engine import (
            LyricLine, Track, PlaybackState,
            parse_lrc, extract_keywords, detect_refrains, analyze_lyrics,
            get_active_line_index, get_refrain_lines,
            LyricsFetcher, SpotifyMonitor, VirtualDJMonitor, OSCSender, KaraokeEngine
        )
    
    def test_parse_lrc_basic(self):
        """parse_lrc should parse LRC format correctly."""
        from karaoke_engine import parse_lrc
        
        lrc = "[00:05.50]Hello world\n[00:10.00]Test line"
        lines = parse_lrc(lrc)
        
        self.assertEqual(len(lines), 2)
        self.assertAlmostEqual(lines[0].time_sec, 5.5, places=2)
        self.assertEqual(lines[0].text, "Hello world")
        self.assertAlmostEqual(lines[1].time_sec, 10.0, places=2)
        self.assertEqual(lines[1].text, "Test line")
    
    def test_parse_lrc_milliseconds(self):
        """parse_lrc should handle both .xx and .xxx formats."""
        from karaoke_engine import parse_lrc
        
        lrc = "[01:30.500]Three digits\n[02:00.50]Two digits"
        lines = parse_lrc(lrc)
        
        self.assertEqual(len(lines), 2)
        self.assertAlmostEqual(lines[0].time_sec, 90.5, places=2)
        self.assertAlmostEqual(lines[1].time_sec, 120.5, places=2)
    
    def test_parse_lrc_empty_lines(self):
        """parse_lrc should skip empty lines."""
        from karaoke_engine import parse_lrc
        
        lrc = "[00:05.00]\n[00:10.00]Real line\n[00:15.00]"
        lines = parse_lrc(lrc)
        
        self.assertEqual(len(lines), 1)
        self.assertEqual(lines[0].text, "Real line")
    
    def test_extract_keywords(self):
        """extract_keywords should filter stop words and return important words."""
        from karaoke_engine import extract_keywords
        
        kw = extract_keywords("I love you forever baby")
        self.assertIn("LOVE", kw)
        self.assertIn("FOREVER", kw)
        self.assertIn("BABY", kw)
        self.assertNotIn("YOU", kw)  # stop word
    
    def test_extract_keywords_empty(self):
        """extract_keywords should handle empty input."""
        from karaoke_engine import extract_keywords
        
        self.assertEqual(extract_keywords(""), "")
        self.assertEqual(extract_keywords("the a an"), "")  # all stop words
    
    def test_extract_keywords_max_words(self):
        """extract_keywords should respect max_words limit."""
        from karaoke_engine import extract_keywords
        
        kw = extract_keywords("love happiness freedom peace joy", max_words=2)
        words = kw.split()
        self.assertLessEqual(len(words), 2)
    
    def test_detect_refrains(self):
        """detect_refrains should mark repeated lines."""
        from karaoke_engine import LyricLine, detect_refrains
        
        lines = [
            LyricLine(0, "Chorus line"),
            LyricLine(5, "Verse line"),
            LyricLine(10, "Chorus line"),  # repeated
            LyricLine(15, "Another verse"),
        ]
        
        result = detect_refrains(lines)
        
        # "Chorus line" appears twice, should be marked as refrain
        self.assertTrue(result[0].is_refrain)
        self.assertFalse(result[1].is_refrain)
        self.assertTrue(result[2].is_refrain)
        self.assertFalse(result[3].is_refrain)
    
    def test_get_active_line_index(self):
        """get_active_line_index should find correct line for position."""
        from karaoke_engine import LyricLine, get_active_line_index
        
        lines = [
            LyricLine(0, "Line 0"),
            LyricLine(5, "Line 1"),
            LyricLine(10, "Line 2"),
        ]
        
        self.assertEqual(get_active_line_index(lines, -1), -1)
        self.assertEqual(get_active_line_index(lines, 0), 0)
        self.assertEqual(get_active_line_index(lines, 3), 0)
        self.assertEqual(get_active_line_index(lines, 5), 1)
        self.assertEqual(get_active_line_index(lines, 7), 1)
        self.assertEqual(get_active_line_index(lines, 15), 2)
    
    def test_get_refrain_lines(self):
        """get_refrain_lines should filter to only refrain lines."""
        from karaoke_engine import LyricLine, get_refrain_lines
        
        lines = [
            LyricLine(0, "Chorus", is_refrain=True),
            LyricLine(5, "Verse", is_refrain=False),
            LyricLine(10, "Chorus", is_refrain=True),
        ]
        
        refrain = get_refrain_lines(lines)
        self.assertEqual(len(refrain), 2)
        self.assertTrue(all(l.is_refrain for l in refrain))
    
    def test_playback_state_track_key(self):
        """PlaybackState.track_key should generate consistent key."""
        from karaoke_engine import PlaybackState, Track
        
        state = PlaybackState()
        self.assertEqual(state.track_key, "")
        
        state.track = Track(artist="Daft Punk", title="One More Time")
        self.assertEqual(state.track_key, "daft punk - one more time")


class TestAudioSetup(unittest.TestCase):
    """Tests for audio_setup module."""
    
    def test_imports(self):
        """All classes should be importable."""
        from audio_setup import AudioSetup, AudioDevice, print_status
    
    def test_audio_device_dataclass(self):
        """AudioDevice should store device info."""
        from audio_setup import AudioDevice
        
        dev = AudioDevice(
            name="Test Device",
            uid="test-123",
            device_id=1,
            is_input=True,
            is_output=False
        )
        
        self.assertEqual(dev.name, "Test Device")
        self.assertEqual(dev.uid, "test-123")
        self.assertTrue(dev.is_input)
        self.assertFalse(dev.is_output)
    
    def test_audio_setup_instantiation(self):
        """AudioSetup should instantiate without errors."""
        from audio_setup import AudioSetup
        
        setup = AudioSetup()
        self.assertIsNotNone(setup)


class TestVJConsole(unittest.TestCase):
    """Tests for vj_console module."""
    
    def test_imports(self):
        """All classes should be importable."""
        from vj_console import ProcessingApp, AppState, ProcessManager
    
    def test_processing_app_dataclass(self):
        """ProcessingApp should store app info."""
        from vj_console import ProcessingApp
        from pathlib import Path
        
        app = ProcessingApp(
            name="TestApp",
            path=Path("/tmp/test"),
            description="A test app"
        )
        
        self.assertEqual(app.name, "TestApp")
        self.assertEqual(str(app.path), "/tmp/test")
        self.assertEqual(app.description, "A test app")
        self.assertFalse(app.enabled)
    
    def test_app_state_defaults(self):
        """AppState should have sensible defaults."""
        from vj_console import AppState
        
        state = AppState()
        
        self.assertEqual(state.selected_index, 0)
        self.assertFalse(state.daemon_mode)
        self.assertTrue(state.karaoke_enabled)
        self.assertTrue(state.running)
    
    def test_process_manager_instantiation(self):
        """ProcessManager should instantiate without errors."""
        from vj_console import ProcessManager
        
        pm = ProcessManager()
        self.assertIsNotNone(pm)


class TestCLI(unittest.TestCase):
    """Tests for CLI entry points."""
    
    def test_karaoke_engine_help(self):
        """karaoke_engine.py --help should work."""
        import subprocess
        result = subprocess.run(
            [sys.executable, "karaoke_engine.py", "--help"],
            capture_output=True,
            text=True,
            timeout=10
        )
        self.assertEqual(result.returncode, 0)
        self.assertIn("Karaoke Engine", result.stdout)
        self.assertIn("--osc-port", result.stdout)
    
    def test_audio_setup_help(self):
        """audio_setup.py --help should work."""
        import subprocess
        result = subprocess.run(
            [sys.executable, "audio_setup.py", "--help"],
            capture_output=True,
            text=True,
            timeout=10
        )
        self.assertEqual(result.returncode, 0)
        self.assertIn("--fix", result.stdout)


if __name__ == "__main__":
    # Change to script directory for relative imports
    import os
    os.chdir(Path(__file__).parent)
    
    # Run tests
    unittest.main(verbosity=2)
