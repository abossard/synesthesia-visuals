#!/usr/bin/env python3
"""
Tests for Python VJ Tools

Run with: python -m pytest test_python_vj.py -v
Or simply: python test_python_vj.py
"""

import sys
import unittest
import tempfile
import time
from pathlib import Path


class TestServiceHealth(unittest.TestCase):
    """Tests for ServiceHealth class (live event resilience)."""
    
    def test_imports(self):
        """ServiceHealth should be importable."""
        from karaoke_engine import ServiceHealth
    
    def test_initial_state(self):
        """ServiceHealth should start unavailable."""
        from karaoke_engine import ServiceHealth
        
        health = ServiceHealth("TestService")
        self.assertFalse(health.available)
        self.assertEqual(health.name, "TestService")
    
    def test_mark_available(self):
        """mark_available should set available to True."""
        from karaoke_engine import ServiceHealth
        
        health = ServiceHealth("TestService")
        health.mark_available("connected")
        self.assertTrue(health.available)
    
    def test_mark_unavailable(self):
        """mark_unavailable should set available to False."""
        from karaoke_engine import ServiceHealth
        
        health = ServiceHealth("TestService")
        health.mark_available()
        health.mark_unavailable("connection lost")
        self.assertFalse(health.available)
    
    def test_get_status(self):
        """get_status should return status dict."""
        from karaoke_engine import ServiceHealth
        
        health = ServiceHealth("TestService")
        status = health.get_status()
        
        self.assertIn('name', status)
        self.assertIn('available', status)
        self.assertIn('error', status)
        self.assertEqual(status['name'], "TestService")


class TestKaraokeEngine(unittest.TestCase):
    """Tests for karaoke_engine module."""
    
    def test_imports(self):
        """All classes and functions should be importable."""
        from karaoke_engine import (
            LyricLine, Track, PlaybackState, Settings,
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


class TestSettings(unittest.TestCase):
    """Tests for Settings class (persistent timing offset)."""
    
    def test_settings_default_offset(self):
        """Settings should have 0ms offset by default."""
        from karaoke_engine import Settings
        
        with tempfile.TemporaryDirectory() as tmpdir:
            settings_file = Path(tmpdir) / "settings.json"
            settings = Settings(file_path=settings_file)
            
            self.assertEqual(settings.timing_offset_ms, 0)
            self.assertAlmostEqual(settings.timing_offset_sec, 0.0)
    
    def test_settings_adjust_timing(self):
        """Settings.adjust_timing should increment/decrement offset."""
        from karaoke_engine import Settings
        
        with tempfile.TemporaryDirectory() as tmpdir:
            settings_file = Path(tmpdir) / "settings.json"
            settings = Settings(file_path=settings_file)
            
            # Adjust forward
            new_offset = settings.adjust_timing(200)
            self.assertEqual(new_offset, 200)
            self.assertEqual(settings.timing_offset_ms, 200)
            
            # Adjust forward again
            new_offset = settings.adjust_timing(200)
            self.assertEqual(new_offset, 400)
            
            # Adjust backward
            new_offset = settings.adjust_timing(-600)
            self.assertEqual(new_offset, -200)
    
    def test_settings_persistence(self):
        """Settings should persist to file and reload."""
        from karaoke_engine import Settings
        
        with tempfile.TemporaryDirectory() as tmpdir:
            settings_file = Path(tmpdir) / "settings.json"
            
            # Create settings and adjust
            settings1 = Settings(file_path=settings_file)
            settings1.adjust_timing(400)
            
            # Create new settings instance (should reload)
            settings2 = Settings(file_path=settings_file)
            self.assertEqual(settings2.timing_offset_ms, 400)
    
    def test_settings_timing_offset_sec(self):
        """Settings.timing_offset_sec should convert ms to seconds."""
        from karaoke_engine import Settings
        
        with tempfile.TemporaryDirectory() as tmpdir:
            settings_file = Path(tmpdir) / "settings.json"
            settings = Settings(file_path=settings_file)
            
            settings.timing_offset_ms = 500
            self.assertAlmostEqual(settings.timing_offset_sec, 0.5)
            
            settings.timing_offset_ms = -300
            self.assertAlmostEqual(settings.timing_offset_sec, -0.3)


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
    """Tests for process_manager module."""
    
    def test_imports(self):
        """All classes should be importable from process_manager."""
        from process_manager import ProcessingApp, AppState, ProcessManager
    
    def test_processing_app_dataclass(self):
        """ProcessingApp should store app info."""
        from process_manager import ProcessingApp
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
        from process_manager import AppState
        
        state = AppState()
        
        self.assertEqual(state.selected_index, 0)
        self.assertFalse(state.daemon_mode)
        self.assertTrue(state.karaoke_enabled)
        self.assertTrue(state.running)
    
    def test_process_manager_instantiation(self):
        """ProcessManager should instantiate without errors."""
        from process_manager import ProcessManager
        
        pm = ProcessManager()
        self.assertIsNotNone(pm)


class TestCLI(unittest.TestCase):
    """Tests for CLI entry points."""
    
    def test_karaoke_engine_help(self):
        """karaoke_engine.py --help should work (module)."""
        import subprocess
        result = subprocess.run(
            [sys.executable, "karaoke_engine.py", "--help"],
            capture_output=True,
            text=True,
            timeout=10
        )
        self.assertEqual(result.returncode, 0)
        self.assertIn("vj_console.py", result.stdout)  # Should recommend main script
    
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


class TestConfig(unittest.TestCase):
    """Tests for Config class."""
    
    def test_config_defaults(self):
        """Config should have OSC defaults."""
        from karaoke_engine import Config
        
        self.assertEqual(Config.DEFAULT_OSC_HOST, "127.0.0.1")
        self.assertEqual(Config.DEFAULT_OSC_PORT, 9000)
    
    def test_config_spotify_credentials(self):
        """Config should check for Spotify credentials."""
        from karaoke_engine import Config
        
        creds = Config.get_spotify_credentials()
        self.assertIn('client_id', creds)
        self.assertIn('client_secret', creds)
        self.assertIn('redirect_uri', creds)


class TestLLMAnalyzer(unittest.TestCase):
    """Tests for LLMAnalyzer class."""
    
    def test_imports(self):
        """LLMAnalyzer should be importable."""
        from karaoke_engine import LLMAnalyzer
    
    def test_instantiation(self):
        """LLMAnalyzer should instantiate without errors."""
        from karaoke_engine import LLMAnalyzer
        
        with tempfile.TemporaryDirectory() as tmpdir:
            analyzer = LLMAnalyzer(cache_dir=Path(tmpdir))
            self.assertIsNotNone(analyzer)
            # Should have a backend (none, openai, or lmstudio)
            self.assertIn(analyzer._backend, ["none", "openai", "lmstudio"])
    
    def test_backend_info(self):
        """backend_info should return a readable string."""
        from karaoke_engine import LLMAnalyzer
        
        with tempfile.TemporaryDirectory() as tmpdir:
            analyzer = LLMAnalyzer(cache_dir=Path(tmpdir))
            info = analyzer.backend_info
            self.assertIsInstance(info, str)
            self.assertTrue(len(info) > 0)
    
    def test_basic_analysis(self):
        """Basic analysis should work without LLM."""
        from karaoke_engine import LLMAnalyzer
        
        with tempfile.TemporaryDirectory() as tmpdir:
            analyzer = LLMAnalyzer(cache_dir=Path(tmpdir))
            
            lyrics = """Hello darkness my old friend
I've come to talk with you again
Hello darkness my old friend
Because a vision softly creeping"""
            
            result = analyzer._basic_analysis(lyrics)
            
            self.assertIn('refrain_lines', result)
            self.assertIn('keywords', result)
            self.assertIn('themes', result)
            # "Hello darkness my old friend" appears twice, should be detected
            self.assertTrue(len(result['refrain_lines']) > 0)
    
    def test_preferred_models(self):
        """PREFERRED_MODELS should have llama3.2 first."""
        from karaoke_engine import LLMAnalyzer
        
        self.assertEqual(LLMAnalyzer.PREFERRED_MODELS[0], 'llama3.2')
        self.assertIn('mistral', LLMAnalyzer.PREFERRED_MODELS)


class TestPipelineTracker(unittest.TestCase):
    """Tests for PipelineTracker class."""
    
    def test_imports(self):
        """PipelineTracker should be importable."""
        from karaoke_engine import PipelineTracker, PipelineStep
    
    def test_instantiation(self):
        """PipelineTracker should instantiate with default state."""
        from karaoke_engine import PipelineTracker
        
        tracker = PipelineTracker()
        self.assertEqual(tracker.current_track, "")
        self.assertEqual(tracker.image_prompt, "")
        self.assertEqual(tracker.generated_image_path, "")
    
    def test_reset(self):
        """reset() should initialize all steps as pending."""
        from karaoke_engine import PipelineTracker
        
        tracker = PipelineTracker()
        tracker.reset("Artist - Title")
        
        self.assertEqual(tracker.current_track, "Artist - Title")
        for step in tracker.steps.values():
            self.assertEqual(step.status, "pending")
    
    def test_step_lifecycle(self):
        """Steps should transition through start/complete/error states."""
        from karaoke_engine import PipelineTracker
        
        tracker = PipelineTracker()
        tracker.reset("Test Track")
        
        # Start a step
        tracker.start("fetch_lyrics", "Checking cache...")
        self.assertEqual(tracker.steps["fetch_lyrics"].status, "running")
        
        # Complete the step
        tracker.complete("fetch_lyrics", "Found 50 lines")
        self.assertEqual(tracker.steps["fetch_lyrics"].status, "complete")
        
        # Error on another step
        tracker.start("llm_analysis", "Calling API...")
        tracker.error("llm_analysis", "Connection timeout")
        self.assertEqual(tracker.steps["llm_analysis"].status, "error")
    
    def test_skip_step(self):
        """skip() should mark step as skipped."""
        from karaoke_engine import PipelineTracker
        
        tracker = PipelineTracker()
        tracker.reset("Test Track")
        
        tracker.skip("comfyui_generate", "Not available")
        self.assertEqual(tracker.steps["comfyui_generate"].status, "skipped")
    
    def test_log_entries(self):
        """log() should add timestamped entries."""
        from karaoke_engine import PipelineTracker
        
        tracker = PipelineTracker()
        tracker.log("Test message")
        
        self.assertEqual(len(tracker.logs), 1)
        self.assertIn("Test message", tracker.logs[0])
    
    def test_get_display_lines(self):
        """get_display_lines() should return formatted output."""
        from karaoke_engine import PipelineTracker
        
        tracker = PipelineTracker()
        tracker.reset("Test")
        tracker.complete("detect_playback", "spotify")
        
        lines = tracker.get_display_lines()
        self.assertTrue(len(lines) > 0)
        # Each line is (label, status, color, message) tuple
        self.assertEqual(len(lines[0]), 4)


class TestComfyUIGenerator(unittest.TestCase):
    """Tests for ComfyUIGenerator class."""
    
    def test_imports(self):
        """ComfyUIGenerator should be importable."""
        from karaoke_engine import ComfyUIGenerator
    
    def test_instantiation(self):
        """ComfyUIGenerator should instantiate without errors."""
        from karaoke_engine import ComfyUIGenerator
        
        with tempfile.TemporaryDirectory() as tmpdir:
            gen = ComfyUIGenerator(output_dir=Path(tmpdir))
            self.assertIsNotNone(gen)
            # Will be False since ComfyUI isn't running
            self.assertFalse(gen.is_available)
    
    @unittest.skip("ComfyUIGenerator API has changed - methods removed")
    def test_vj_prompt_enhancement(self):
        pass
    
    @unittest.skip("ComfyUIGenerator API has changed - methods removed")
    def test_image_path_generation(self):
        pass
    
    @unittest.skip("ComfyUIGenerator API has changed - methods removed")
    def test_cached_count(self):
        pass
    
    @unittest.skip("ComfyUIGenerator API has changed - methods removed")
    def test_available_workflows_list(self):
        pass
    
    @unittest.skip("ComfyUIGenerator API has changed - methods removed")
    def test_set_workflow(self):
        pass
    
    @unittest.skip("ComfyUIGenerator API has changed - methods removed")
    def test_active_workflow_default(self):
        pass
    
    @unittest.skip("ComfyUIGenerator API has changed - methods removed")
    def test_get_status_info(self):
        pass


class TestSongCategorizer(unittest.TestCase):
    """Tests for SongCategorizer class."""
    
    def test_imports(self):
        """SongCategorizer should be importable."""
        from karaoke_engine import SongCategorizer, SongCategories, SongCategory
    
    def test_song_category_dataclass(self):
        """SongCategory should store name and score."""
        from karaoke_engine import SongCategory
        
        cat = SongCategory(name="happy", score=0.75)
        self.assertEqual(cat.name, "happy")
        self.assertAlmostEqual(cat.score, 0.75)
    
    def test_song_categories_get_top(self):
        """SongCategories.get_top should return top N categories."""
        from karaoke_engine import SongCategory, SongCategories
        
        cats = SongCategories(scores={
            "happy": 0.8,
            "sad": 0.3,
            "love": 0.9,
            "dark": 0.1,
        })
        
        top2 = cats.get_top(2)
        self.assertEqual(len(top2), 2)
        self.assertEqual(top2[0].name, "love")
        self.assertEqual(top2[1].name, "happy")
    
    def test_song_categories_get_category_score(self):
        """SongCategories.get_category_score should return score for category."""
        from karaoke_engine import SongCategory, SongCategories
        
        cats = SongCategories(scores={
            "happy": 0.8,
            "sad": 0.3,
        })
        
        self.assertAlmostEqual(cats.get_score("happy"), 0.8)
        self.assertAlmostEqual(cats.get_score("sad"), 0.3)
        self.assertAlmostEqual(cats.get_score("unknown"), 0.0)
    
    def test_song_categories_to_dict(self):
        """SongCategories.get_dict should return serializable dict."""
        from karaoke_engine import SongCategory, SongCategories
        
        cats = SongCategories(
            scores={"happy": 0.8},
            primary_mood="happy"
        )
        
        d = cats.get_dict()
        self.assertIn('happy', d)
        self.assertAlmostEqual(d['happy'], 0.8)
    
    def test_song_categories_from_dict(self):
        """SongCategories should be creatable from dict."""
        from karaoke_engine import SongCategories
        
        cats = SongCategories(
            scores={'happy': 0.8, 'sad': 0.2},
            primary_mood='happy'
        )
        
        self.assertEqual(cats.primary_mood, "happy")
        self.assertEqual(len(cats.scores), 2)
        self.assertAlmostEqual(cats.get_score('happy'), 0.8)
    
    def test_categorizer_instantiation(self):
        """SongCategorizer should instantiate without errors."""
        from karaoke_engine import SongCategorizer
        
        with tempfile.TemporaryDirectory() as tmpdir:
            categorizer = SongCategorizer(cache_dir=Path(tmpdir))
            self.assertIsNotNone(categorizer)
    
    def test_categorizer_basic_analysis(self):
        """SongCategorizer should work with basic (no LLM) analysis."""
        from karaoke_engine import SongCategorizer
        
        with tempfile.TemporaryDirectory() as tmpdir:
            categorizer = SongCategorizer(cache_dir=Path(tmpdir))
            
            # Test with lyrics containing keywords
            result = categorizer._categorize_basic(
                artist="Test Artist",
                title="Happy Love Song",
                lyrics="love love love happy joy smile"
            )
            
            self.assertIsNotNone(result)
            self.assertGreater(len(result.scores), 0)
            # "love" and "happy" keywords should boost those scores
            love_score = result.get_score("love")
            happy_score = result.get_score("happy")
            self.assertGreater(love_score, 0)
            self.assertGreater(happy_score, 0)
    
    def test_categorizer_categories_list(self):
        """SongCategorizer should have predefined categories."""
        from karaoke_engine import SongCategorizer
        
        self.assertIn('happy', SongCategorizer.CATEGORIES)
        self.assertIn('sad', SongCategorizer.CATEGORIES)
        self.assertIn('love', SongCategorizer.CATEGORIES)
        self.assertIn('dark', SongCategorizer.CATEGORIES)
        self.assertIn('death', SongCategorizer.CATEGORIES)
        self.assertIn('energetic', SongCategorizer.CATEGORIES)


class TestOSCSender(unittest.TestCase):
    """Tests for OSCSender class additions."""
    
    def test_osc_sender_message_log(self):
        """OSCSender should log messages for debug panel."""
        from karaoke_engine import OSCSender, SongCategory, SongCategories
        
        sender = OSCSender(host="127.0.0.1", port=9999)
        
        # Initial log should be empty
        messages = sender.get_recent_messages()
        self.assertEqual(len(messages), 0)
    
    @unittest.skip("OSCSender API has changed - send_categories removed")
    def test_osc_sender_send_categories(self):
        """OSCSender API has changed - skipping old test."""
        pass


class TestAudioAnalyzer(unittest.TestCase):
    """Tests for audio analyzer module."""
    
    def test_imports(self):
        """Audio analyzer should be importable (if dependencies available)."""
        try:
            from audio_analyzer import (
                AudioConfig, DeviceConfig, DeviceManager,
                AudioAnalyzer, AudioAnalyzerWatchdog,
                compress_value, calculate_rms, calculate_spectral_centroid,
                extract_band_energy, smooth_value, estimate_bpm_from_intervals,
                detect_buildup_drop, downsample_spectrum
            )
        except ImportError as e:
            self.skipTest(f"Audio analyzer dependencies not available: {e}")
    
    def test_audio_config_immutable(self):
        """AudioConfig should be immutable."""
        try:
            from audio_analyzer import AudioConfig
        except ImportError:
            self.skipTest("Audio analyzer not available")
        
        config = AudioConfig()
        
        # Should not be able to modify
        with self.assertRaises(Exception):  # FrozenInstanceError
            config.sample_rate = 48000
    
    def test_device_config_serialization(self):
        """DeviceConfig should serialize to/from dict."""
        try:
            from audio_analyzer import DeviceConfig
        except ImportError:
            self.skipTest("Audio analyzer not available")
        
        config = DeviceConfig(device_index=1, device_name="Test Device")
        
        # Convert to dict
        data = config.to_dict()
        self.assertEqual(data['device_index'], 1)
        self.assertEqual(data['device_name'], "Test Device")
        
        # Restore from dict
        restored = DeviceConfig.from_dict(data)
        self.assertEqual(restored.device_index, 1)
        self.assertEqual(restored.device_name, "Test Device")
    
    def test_compress_value(self):
        """compress_value should compress values using tanh."""
        try:
            from audio_analyzer import compress_value
        except ImportError:
            self.skipTest("Audio analyzer not available")
        
        # Test compression
        self.assertAlmostEqual(compress_value(0.0), 0.0, places=5)
        self.assertGreater(compress_value(1.0), 0.9)  # Should be close to 1
        self.assertLess(compress_value(1.0), 1.0)  # But less than 1
    
    def test_calculate_rms(self):
        """calculate_rms should calculate root mean square."""
        try:
            from audio_analyzer import calculate_rms
            import numpy as np
        except ImportError:
            self.skipTest("Audio analyzer not available")
        
        # Sine wave with amplitude 1 should have RMS ~0.707
        t = np.linspace(0, 1, 1000)
        signal = np.sin(2 * np.pi * 440 * t)
        rms = calculate_rms(signal)
        
        self.assertAlmostEqual(rms, 0.707, places=2)
    
    def test_smooth_value(self):
        """smooth_value should apply exponential moving average."""
        try:
            from audio_analyzer import smooth_value
        except ImportError:
            self.skipTest("Audio analyzer not available")
        
        # No smoothing (factor=0)
        result = smooth_value(0.0, 1.0, 0.0)
        self.assertAlmostEqual(result, 1.0, places=5)
        
        # Full smoothing (factor=1)
        result = smooth_value(0.5, 1.0, 1.0)
        self.assertAlmostEqual(result, 0.5, places=5)
        
        # Partial smoothing
        result = smooth_value(0.0, 1.0, 0.5)
        self.assertAlmostEqual(result, 0.5, places=5)
    
    def test_estimate_bpm_from_intervals(self):
        """estimate_bpm_from_intervals should calculate BPM and confidence."""
        try:
            from audio_analyzer import estimate_bpm_from_intervals
        except ImportError:
            self.skipTest("Audio analyzer not available")
        
        # 120 BPM = 0.5 second intervals
        intervals = [0.5, 0.5, 0.5, 0.5, 0.5]
        bpm, confidence = estimate_bpm_from_intervals(intervals)
        
        self.assertAlmostEqual(bpm, 120.0, places=0)
        self.assertGreater(confidence, 0.5)  # Should have decent confidence
        
        # Empty intervals
        bpm, confidence = estimate_bpm_from_intervals([])
        self.assertEqual(bpm, 0.0)
        self.assertEqual(confidence, 0.0)
    
    def test_downsample_spectrum(self):
        """downsample_spectrum should reduce spectrum to target bins."""
        try:
            from audio_analyzer import downsample_spectrum
            import numpy as np
        except ImportError:
            self.skipTest("Audio analyzer not available")
        
        # Create a spectrum with 512 bins
        spectrum = np.random.rand(512)
        
        # Downsample to 32 bins
        downsampled = downsample_spectrum(spectrum, 32)
        
        self.assertEqual(len(downsampled), 32)
        self.assertLessEqual(np.max(downsampled), 1.0)  # Should be normalized
    
    def test_device_manager_config_persistence(self):
        """DeviceManager should persist configuration."""
        try:
            from audio_analyzer import DeviceManager
        except ImportError:
            self.skipTest("Audio analyzer not available")
        
        with tempfile.TemporaryDirectory() as tmpdir:
            # Mock config file location
            import audio_analyzer
            original_config_file = audio_analyzer.DeviceManager.CONFIG_FILE
            
            try:
                test_config_file = Path(tmpdir) / 'test_config.json'
                audio_analyzer.DeviceManager.CONFIG_FILE = test_config_file
                
                # Create manager and set device
                manager = DeviceManager()
                manager.config.device_index = 5
                manager.config.device_name = "Test Device"
                manager.save_config()
                
                # Create new manager - should load saved config
                manager2 = DeviceManager()
                self.assertEqual(manager2.config.device_index, 5)
                self.assertEqual(manager2.config.device_name, "Test Device")
                
            finally:
                # Restore original config file location
                audio_analyzer.DeviceManager.CONFIG_FILE = original_config_file
    
    def test_audio_analyzer_initialization(self):
        """AudioAnalyzer should initialize without errors."""
        try:
            from audio_analyzer import AudioConfig, DeviceManager, AudioAnalyzer
        except ImportError:
            self.skipTest("Audio analyzer not available")
        
        config = AudioConfig()
        device_manager = DeviceManager()
        
        # Should initialize without crashing
        analyzer = AudioAnalyzer(config, device_manager, osc_callback=None)
        
        # Check initial state
        self.assertFalse(analyzer.running)
        self.assertEqual(analyzer.frames_processed, 0)
        self.assertEqual(len(analyzer.smoothed_bands), len(config.bands))
    
    def test_watchdog_health_check(self):
        """AudioAnalyzerWatchdog should detect unhealthy state."""
        try:
            from audio_analyzer import AudioConfig, DeviceManager, AudioAnalyzer, AudioAnalyzerWatchdog
        except ImportError:
            self.skipTest("Audio analyzer not available")
        
        config = AudioConfig()
        device_manager = DeviceManager()
        analyzer = AudioAnalyzer(config, device_manager, osc_callback=None)
        
        watchdog = AudioAnalyzerWatchdog(analyzer)
        
        # Analyzer not running should be unhealthy
        healthy, message = watchdog.check_health()
        self.assertFalse(healthy)
        self.assertIn("not running", message.lower())
    
    def test_latency_benchmark_structure(self):
        """LatencyBenchmark should have expected fields."""
        try:
            from audio_analyzer import LatencyBenchmark
        except ImportError:
            self.skipTest("Audio analyzer not available")
        
        benchmark = LatencyBenchmark(
            total_frames=600,
            duration_sec=10.0,
            avg_fps=60.0,
            avg_latency_ms=15.5
        )
        
        self.assertEqual(benchmark.total_frames, 600)
        self.assertAlmostEqual(benchmark.duration_sec, 10.0)
        self.assertAlmostEqual(benchmark.avg_fps, 60.0)
        self.assertAlmostEqual(benchmark.avg_latency_ms, 15.5)
        
        # Should convert to dict
        data = benchmark.to_dict()
        self.assertIn('total_frames', data)
        self.assertIn('avg_fps', data)
        self.assertIn('avg_latency_ms', data)


if __name__ == "__main__":
    # Change to script directory for relative imports
    import os
    os.chdir(Path(__file__).parent)
    
    # Run tests
    unittest.main(verbosity=2)
