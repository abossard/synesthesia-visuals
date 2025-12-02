#!/usr/bin/env python3
"""
Tests for Python VJ Tools

Behavioral black-box tests focusing on public APIs and observable behavior.

Run with: python -m pytest test_python_vj.py -v
Or simply: python test_python_vj.py
"""

import sys
import unittest
import tempfile
from pathlib import Path


class TestServiceHealth(unittest.TestCase):
    """Tests for ServiceHealth - tracks service availability with reconnection."""
    
    def test_starts_unavailable(self):
        """A new service should start as unavailable."""
        from infrastructure import ServiceHealth
        
        health = ServiceHealth("TestService")
        self.assertFalse(health.available)
    
    def test_becomes_available_when_marked(self):
        """Service should become available after mark_available."""
        from infrastructure import ServiceHealth
        
        health = ServiceHealth("TestService")
        health.mark_available("connected")
        self.assertTrue(health.available)
    
    def test_becomes_unavailable_when_marked(self):
        """Service should become unavailable after mark_unavailable."""
        from infrastructure import ServiceHealth
        
        health = ServiceHealth("TestService")
        health.mark_available()
        health.mark_unavailable("connection lost")
        self.assertFalse(health.available)
    
    def test_status_contains_required_fields(self):
        """get_status should return dict with name, available, and error."""
        from infrastructure import ServiceHealth
        
        health = ServiceHealth("TestService")
        status = health.get_status()
        
        self.assertEqual(status['name'], "TestService")
        self.assertIn('available', status)
        self.assertIn('error', status)


class TestLRCParsing(unittest.TestCase):
    """Tests for LRC lyrics format parsing."""
    
    def test_parses_basic_lrc_format(self):
        """Should parse [mm:ss.xx]text format correctly."""
        from domain import parse_lrc
        
        lrc = "[00:05.50]Hello world\n[00:10.00]Test line"
        lines = parse_lrc(lrc)
        
        self.assertEqual(len(lines), 2)
        self.assertAlmostEqual(lines[0].time_sec, 5.5, places=2)
        self.assertEqual(lines[0].text, "Hello world")
        self.assertAlmostEqual(lines[1].time_sec, 10.0, places=2)
        self.assertEqual(lines[1].text, "Test line")
    
    def test_handles_three_digit_centiseconds(self):
        """Should handle .xxx format (treated as centiseconds / 100)."""
        from domain import parse_lrc
        
        # 500 centiseconds = 5.0 seconds
        lrc = "[01:30.500]Three digits"
        lines = parse_lrc(lrc)
        
        self.assertEqual(len(lines), 1)
        # 1:30.500 = 90 seconds + 500/100 = 95.0 seconds
        self.assertAlmostEqual(lines[0].time_sec, 95.0, places=2)
    
    def test_skips_empty_lyric_lines(self):
        """Should skip lines with empty text."""
        from domain import parse_lrc
        
        lrc = "[00:05.00]\n[00:10.00]Real line\n[00:15.00]"
        lines = parse_lrc(lrc)
        
        self.assertEqual(len(lines), 1)
        self.assertEqual(lines[0].text, "Real line")


class TestKeywordExtraction(unittest.TestCase):
    """Tests for keyword extraction from lyrics."""
    
    def test_filters_stop_words(self):
        """Should remove common stop words like I, you, the."""
        from domain import extract_keywords
        
        kw = extract_keywords("I love you forever baby")
        self.assertIn("LOVE", kw)
        self.assertIn("FOREVER", kw)
        self.assertNotIn("YOU", kw)
    
    def test_returns_empty_for_only_stop_words(self):
        """Should return empty string when all words are stop words."""
        from domain import extract_keywords
        
        self.assertEqual(extract_keywords(""), "")
        self.assertEqual(extract_keywords("the a an"), "")
    
    def test_respects_max_words_limit(self):
        """Should limit output to max_words."""
        from domain import extract_keywords
        
        kw = extract_keywords("love happiness freedom peace joy", max_words=2)
        words = kw.split()
        self.assertLessEqual(len(words), 2)


class TestRefrainDetection(unittest.TestCase):
    """Tests for detecting repeated lines (refrain/chorus)."""
    
    def test_marks_repeated_lines_as_refrain(self):
        """Lines appearing multiple times should be marked as refrain."""
        from domain import LyricLine, detect_refrains
        
        lines = [
            LyricLine(0, "Chorus line"),
            LyricLine(5, "Verse line"),
            LyricLine(10, "Chorus line"),  # repeated
            LyricLine(15, "Another verse"),
        ]
        
        result = detect_refrains(lines)
        
        self.assertTrue(result[0].is_refrain)   # "Chorus line" - repeated
        self.assertFalse(result[1].is_refrain)  # "Verse line" - unique
        self.assertTrue(result[2].is_refrain)   # "Chorus line" - repeated
        self.assertFalse(result[3].is_refrain)  # "Another verse" - unique
    
    def test_filters_refrain_lines(self):
        """get_refrain_lines should return only refrain lines."""
        from domain import LyricLine, get_refrain_lines
        
        lines = [
            LyricLine(0, "Chorus", is_refrain=True),
            LyricLine(5, "Verse", is_refrain=False),
            LyricLine(10, "Chorus", is_refrain=True),
        ]
        
        refrain = get_refrain_lines(lines)
        self.assertEqual(len(refrain), 2)
        self.assertTrue(all(l.is_refrain for l in refrain))


class TestActiveLineTracking(unittest.TestCase):
    """Tests for finding the current active lyric line based on position."""
    
    def test_finds_correct_line_for_position(self):
        """Should return the line that was most recently passed."""
        from domain import LyricLine, get_active_line_index
        
        lines = [
            LyricLine(0, "Line 0"),
            LyricLine(5, "Line 1"),
            LyricLine(10, "Line 2"),
        ]
        
        self.assertEqual(get_active_line_index(lines, -1), -1)  # before first
        self.assertEqual(get_active_line_index(lines, 0), 0)    # at first
        self.assertEqual(get_active_line_index(lines, 3), 0)    # between 0 and 1
        self.assertEqual(get_active_line_index(lines, 5), 1)    # at second
        self.assertEqual(get_active_line_index(lines, 15), 2)   # after last


class TestPlaybackState(unittest.TestCase):
    """Tests for playback state tracking."""
    
    def test_has_track_when_track_set(self):
        """has_track should be True when track is present."""
        from domain import PlaybackState, Track
        
        state = PlaybackState()
        self.assertFalse(state.has_track)
        
        state = PlaybackState(track=Track(artist="Daft Punk", title="One More Time"))
        self.assertTrue(state.has_track)


class TestSettings(unittest.TestCase):
    """Tests for persistent settings storage."""
    
    def test_default_timing_offset(self):
        """Default timing offset should show lyrics early (-500ms)."""
        from infrastructure import Settings
        
        with tempfile.TemporaryDirectory() as tmpdir:
            settings = Settings(file_path=Path(tmpdir) / "settings.json")
            self.assertEqual(settings.timing_offset_ms, -500)
    
    def test_timing_adjustment_accumulates(self):
        """adjust_timing should add/subtract from current offset."""
        from infrastructure import Settings
        
        with tempfile.TemporaryDirectory() as tmpdir:
            settings = Settings(file_path=Path(tmpdir) / "settings.json")
            initial = settings.timing_offset_ms
            
            settings.adjust_timing(200)
            self.assertEqual(settings.timing_offset_ms, initial + 200)
            
            settings.adjust_timing(-400)
            self.assertEqual(settings.timing_offset_ms, initial - 200)
    
    def test_settings_persist_across_instances(self):
        """Settings should be saved and reloaded from file."""
        from infrastructure import Settings
        
        with tempfile.TemporaryDirectory() as tmpdir:
            settings_file = Path(tmpdir) / "settings.json"
            
            # First instance sets a value
            settings1 = Settings(file_path=settings_file)
            settings1.timing_offset_ms = 400
            
            # Second instance should read the saved value
            settings2 = Settings(file_path=settings_file)
            self.assertEqual(settings2.timing_offset_ms, 400)


class TestPipelineTracker(unittest.TestCase):
    """Tests for song processing pipeline tracking."""
    
    def test_tracks_current_song(self):
        """Should track the current track being processed."""
        from infrastructure import PipelineTracker
        
        tracker = PipelineTracker()
        self.assertEqual(tracker.current_track, "")
        
        tracker.reset("Artist - Title")
        self.assertEqual(tracker.current_track, "Artist - Title")
    
    def test_display_lines_reflect_step_states(self):
        """get_display_lines should reflect step completion states."""
        from infrastructure import PipelineTracker
        
        tracker = PipelineTracker()
        tracker.reset("Test")
        
        # Complete a step
        tracker.complete("detect_playback", "spotify")
        
        lines = tracker.get_display_lines()
        self.assertTrue(len(lines) > 0)
        
        # Find the completed step - it should have a checkmark
        detect_line = [l for l in lines if "Detect" in l[0]][0]
        self.assertEqual(detect_line[1], "✓")  # status indicator
        self.assertEqual(detect_line[2], "green")  # color
    
    def test_logs_are_retrievable(self):
        """Logged messages should be retrievable via get_log_lines."""
        from infrastructure import PipelineTracker
        
        tracker = PipelineTracker()
        tracker.log("Test message 1")
        tracker.log("Test message 2")
        
        logs = tracker.get_log_lines()
        self.assertEqual(len(logs), 2)
        self.assertIn("Test message 1", logs[0])


class TestLLMAnalyzer(unittest.TestCase):
    """Tests for AI-powered lyrics analysis."""
    
    def test_provides_backend_info(self):
        """Should report which LLM backend is being used."""
        from ai_services import LLMAnalyzer
        
        with tempfile.TemporaryDirectory() as tmpdir:
            analyzer = LLMAnalyzer(cache_dir=Path(tmpdir))
            info = analyzer.backend_info
            
            self.assertIsInstance(info, str)
            self.assertTrue(len(info) > 0)
    
    def test_analyzes_lyrics_without_llm(self):
        """Should provide basic analysis even without LLM backend."""
        from ai_services import LLMAnalyzer
        
        with tempfile.TemporaryDirectory() as tmpdir:
            analyzer = LLMAnalyzer(cache_dir=Path(tmpdir))
            
            lyrics = """Hello darkness my old friend
I've come to talk with you again
Hello darkness my old friend
Because a vision softly creeping"""
            
            result = analyzer.analyze_lyrics(lyrics, "Simon & Garfunkel", "The Sound of Silence")
            
            # Should return analysis with expected structure
            self.assertIn('refrain_lines', result)
            self.assertIn('keywords', result)
            # Repeated line should be detected as refrain
            self.assertTrue(len(result['refrain_lines']) > 0)


class TestSongCategorizer(unittest.TestCase):
    """Tests for AI-powered song mood/theme classification."""
    
    def test_has_predefined_categories(self):
        """Should have standard mood/theme categories."""
        from ai_services import SongCategorizer
        
        self.assertIn('happy', SongCategorizer.CATEGORIES)
        self.assertIn('sad', SongCategorizer.CATEGORIES)
        self.assertIn('love', SongCategorizer.CATEGORIES)
        self.assertIn('dark', SongCategorizer.CATEGORIES)
    
    def test_categorizes_song_with_scores(self):
        """Should return category scores for a song."""
        from ai_services import SongCategorizer
        
        with tempfile.TemporaryDirectory() as tmpdir:
            categorizer = SongCategorizer(cache_dir=Path(tmpdir))
            
            result = categorizer.categorize(
                artist="Test Artist",
                title="Happy Love Song",
                lyrics="love love love happy joy smile"
            )
            
            # Should have scores for categories
            love_score = result.get_score("love")
            happy_score = result.get_score("happy")
            
            # Keywords should boost relevant categories
            self.assertGreater(love_score, 0)
            self.assertGreater(happy_score, 0)


class TestSongCategories(unittest.TestCase):
    """Tests for SongCategories data structure."""
    
    def test_get_top_returns_sorted_categories(self):
        """get_top should return categories sorted by score descending."""
        from domain import SongCategories
        
        cats = SongCategories(
            scores={'happy': 0.8, 'sad': 0.3, 'love': 0.9, 'dark': 0.1}
        )
        
        top2 = cats.get_top(2)
        self.assertEqual(len(top2), 2)
        self.assertEqual(top2[0].name, "love")   # highest score
        self.assertEqual(top2[1].name, "happy")  # second highest
    
    def test_get_score_returns_category_score(self):
        """get_score should return the score for a specific category."""
        from domain import SongCategories
        
        cats = SongCategories(scores={'happy': 0.8, 'sad': 0.3})
        
        self.assertAlmostEqual(cats.get_score("happy"), 0.8)
        self.assertAlmostEqual(cats.get_score("sad"), 0.3)
        self.assertAlmostEqual(cats.get_score("unknown"), 0.0)


class TestComfyUIGenerator(unittest.TestCase):
    """Tests for ComfyUI image generation."""
    
    def test_unavailable_without_comfyui(self):
        """Should be unavailable when ComfyUI is not running."""
        from ai_services import ComfyUIGenerator
        
        with tempfile.TemporaryDirectory() as tmpdir:
            gen = ComfyUIGenerator(output_dir=Path(tmpdir))
            self.assertFalse(gen.is_available)
    
    def test_checks_for_cached_images(self):
        """Should be able to check for cached images by artist/title."""
        from ai_services import ComfyUIGenerator
        
        with tempfile.TemporaryDirectory() as tmpdir:
            gen = ComfyUIGenerator(output_dir=Path(tmpdir))
            
            # No cached image for new song
            cached = gen.get_cached_image("Test Artist", "Test Song")
            self.assertIsNone(cached)


class TestVirtualDJAPI(unittest.TestCase):
    """Tests for VirtualDJ Remote API integration."""
    
    def test_deck_status_dataclass(self):
        """DeckStatus should store deck information."""
        from vdj_api import DeckStatus
        
        status = DeckStatus(
            deck=1,
            title="Test Song",
            artist="Test Artist",
            bpm=128.5,
            position=0.5,
            elapsed_ms=60000,
            length_sec=180.0
        )
        
        self.assertEqual(status.deck, 1)
        self.assertEqual(status.title, "Test Song")
        self.assertEqual(status.artist, "Test Artist")
        self.assertAlmostEqual(status.bpm, 128.5)
        self.assertAlmostEqual(status.position, 0.5)
        self.assertEqual(status.elapsed_ms, 60000)
        self.assertAlmostEqual(status.length_sec, 180.0)
    
    def test_client_uses_requests(self):
        """VirtualDJClient should use requests library."""
        from vdj_api import VirtualDJClient
        import requests
        
        # Create client (will fail to connect, but that's ok)
        client = VirtualDJClient(base_url="http://127.0.0.1:59999")
        
        # Should have a requests session
        self.assertIsInstance(client._session, requests.Session)
    
    def test_client_connection_check(self):
        """VirtualDJClient should check connection on init."""
        from vdj_api import VirtualDJClient
        
        # Connect to a port that's definitely not running VDJ
        client = VirtualDJClient(base_url="http://127.0.0.1:59999")
        
        # Should not be connected
        self.assertFalse(client.is_connected())
    
    def test_monitor_unavailable_without_vdj(self):
        """VirtualDJMonitor should be unavailable when VDJ is not running."""
        from adapters import VirtualDJMonitor
        
        # Connect to a port that's definitely not running VDJ
        monitor = VirtualDJMonitor(base_url="http://127.0.0.1:59999")
        
        # Should not be available
        self.assertFalse(monitor.is_available)
        
        # get_playback should return None gracefully
        playback = monitor.get_playback()
        self.assertIsNone(playback)


class TestConfig(unittest.TestCase):
    """Tests for application configuration."""
    
    def test_osc_defaults(self):
        """Should have default OSC host and port."""
        from infrastructure import Config
        
        self.assertEqual(Config.DEFAULT_OSC_HOST, "127.0.0.1")
        self.assertEqual(Config.DEFAULT_OSC_PORT, 9000)
    
    def test_spotify_credentials_structure(self):
        """get_spotify_credentials should return dict with required keys."""
        from infrastructure import Config
        
        creds = Config.get_spotify_credentials()
        self.assertIn('client_id', creds)
        self.assertIn('client_secret', creds)
        self.assertIn('redirect_uri', creds)


class TestAudioSetup(unittest.TestCase):
    """Tests for audio device configuration."""
    
    def test_audio_device_stores_info(self):
        """AudioDevice should store device information."""
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


class TestProcessManager(unittest.TestCase):
    """Tests for Processing app management."""
    
    def test_app_state_defaults(self):
        """AppState should have sensible defaults."""
        from process_manager import AppState
        
        state = AppState()
        
        self.assertEqual(state.selected_index, 0)
        self.assertFalse(state.daemon_mode)
        self.assertTrue(state.karaoke_enabled)
        self.assertTrue(state.running)
    
    def test_processing_app_stores_info(self):
        """ProcessingApp should store app metadata."""
        from process_manager import ProcessingApp
        
        app = ProcessingApp(
            name="TestApp",
            path=Path("/tmp/test"),
            description="A test app"
        )
        
        self.assertEqual(app.name, "TestApp")
        self.assertEqual(app.description, "A test app")
        self.assertFalse(app.enabled)


class TestCLIEntryPoints(unittest.TestCase):
    """Tests for command-line interface entry points."""
    
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
        self.assertIn("vj_console.py", result.stdout)
    
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
    import os
    os.chdir(Path(__file__).parent)
    unittest.main(verbosity=2)
