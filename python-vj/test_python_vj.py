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
    """Tests for vj_console module."""
    
    def test_imports(self):
        """All classes should be importable from vj_console_blessed."""
        from vj_console_blessed import ProcessingApp, AppState, ProcessManager
    
    def test_processing_app_dataclass(self):
        """ProcessingApp should store app info."""
        from vj_console_blessed import ProcessingApp
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
        from vj_console_blessed import AppState
        
        state = AppState()
        
        self.assertEqual(state.selected_index, 0)
        self.assertFalse(state.daemon_mode)
        self.assertTrue(state.karaoke_enabled)
        self.assertTrue(state.running)
    
    def test_process_manager_instantiation(self):
        """ProcessManager should instantiate without errors."""
        from vj_console_blessed import ProcessManager
        
        pm = ProcessManager()
        self.assertIsNotNone(pm)


class TestCLI(unittest.TestCase):
    """Tests for CLI entry points."""
    
    def test_vj_console_blessed_help(self):
        """vj_console_blessed.py --help should work (main entry point)."""
        import subprocess
        result = subprocess.run(
            [sys.executable, "vj_console_blessed.py", "--help"],
            capture_output=True,
            text=True,
            timeout=10
        )
        self.assertEqual(result.returncode, 0)
        self.assertIn("VJ Console", result.stdout)
        self.assertIn("--karaoke", result.stdout)
        self.assertIn("--audio", result.stdout)
    
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
            # Should have a backend (none, openai, or ollama)
            self.assertIn(analyzer._backend, ["none", "openai", "ollama"])
    
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
        self.assertEqual(tracker.steps["fetch_lyrics"].status, "done")
        
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
        # Each line is (color, text) tuple
        self.assertEqual(len(lines[0]), 2)


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
    
    def test_vj_prompt_enhancement(self):
        """get_vj_prompt() should add VJ-specific requirements."""
        from karaoke_engine import ComfyUIGenerator
        
        with tempfile.TemporaryDirectory() as tmpdir:
            gen = ComfyUIGenerator(output_dir=Path(tmpdir))
            
            base_prompt = "A beautiful sunset"
            vj_prompt = gen.get_vj_prompt(base_prompt)
            
            self.assertIn("black background", vj_prompt.lower())
            self.assertIn("A beautiful sunset", vj_prompt)
    
    def test_image_path_generation(self):
        """_get_image_path() should return safe file paths."""
        from karaoke_engine import ComfyUIGenerator
        
        with tempfile.TemporaryDirectory() as tmpdir:
            gen = ComfyUIGenerator(output_dir=Path(tmpdir))
            
            path = gen._get_image_path("Test Artist", "Song/Title:Special")
            
            # Should be a PNG file
            self.assertTrue(str(path).endswith(".png"))
            # Should not contain special characters
            self.assertNotIn("/", path.name)
            self.assertNotIn(":", path.name)
    
    def test_cached_count(self):
        """get_cached_count() should return 0 for empty cache."""
        from karaoke_engine import ComfyUIGenerator
        
        with tempfile.TemporaryDirectory() as tmpdir:
            gen = ComfyUIGenerator(output_dir=Path(tmpdir))
            self.assertEqual(gen.get_cached_count(), 0)
    
    def test_available_workflows_list(self):
        """available_workflows should return list of loaded workflow names."""
        from karaoke_engine import ComfyUIGenerator
        
        with tempfile.TemporaryDirectory() as tmpdir:
            gen = ComfyUIGenerator(output_dir=Path(tmpdir))
            workflows = gen.available_workflows
            self.assertIsInstance(workflows, list)
    
    def test_set_workflow(self):
        """set_workflow() should return False for non-existent workflow."""
        from karaoke_engine import ComfyUIGenerator
        
        with tempfile.TemporaryDirectory() as tmpdir:
            gen = ComfyUIGenerator(output_dir=Path(tmpdir))
            result = gen.set_workflow("nonexistent_workflow")
            self.assertFalse(result)
    
    def test_active_workflow_default(self):
        """active_workflow should be None by default."""
        from karaoke_engine import ComfyUIGenerator
        
        with tempfile.TemporaryDirectory() as tmpdir:
            gen = ComfyUIGenerator(output_dir=Path(tmpdir))
            self.assertIsNone(gen.active_workflow)
    
    def test_get_status_info(self):
        """get_status_info() should return complete status dict."""
        from karaoke_engine import ComfyUIGenerator
        
        with tempfile.TemporaryDirectory() as tmpdir:
            gen = ComfyUIGenerator(output_dir=Path(tmpdir))
            status = gen.get_status_info()
            
            self.assertIn('available', status)
            self.assertIn('models', status)
            self.assertIn('workflows', status)
            self.assertIn('active_workflow', status)
            self.assertIn('cached_images', status)
            self.assertIn('url', status)


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
        
        cats = SongCategories(categories=[
            SongCategory(name="happy", score=0.8),
            SongCategory(name="sad", score=0.3),
            SongCategory(name="love", score=0.9),
            SongCategory(name="dark", score=0.1),
        ])
        
        top2 = cats.get_top(2)
        self.assertEqual(len(top2), 2)
        self.assertEqual(top2[0].name, "love")
        self.assertEqual(top2[1].name, "happy")
    
    def test_song_categories_get_category_score(self):
        """SongCategories.get_category_score should return score for category."""
        from karaoke_engine import SongCategory, SongCategories
        
        cats = SongCategories(categories=[
            SongCategory(name="happy", score=0.8),
            SongCategory(name="sad", score=0.3),
        ])
        
        self.assertAlmostEqual(cats.get_category_score("happy"), 0.8)
        self.assertAlmostEqual(cats.get_category_score("sad"), 0.3)
        self.assertAlmostEqual(cats.get_category_score("unknown"), 0.0)
    
    def test_song_categories_to_dict(self):
        """SongCategories.to_dict should return serializable dict."""
        from karaoke_engine import SongCategory, SongCategories
        
        cats = SongCategories(
            categories=[SongCategory(name="happy", score=0.8)],
            primary_mood="happy"
        )
        
        d = cats.to_dict()
        self.assertIn('categories', d)
        self.assertIn('primary_mood', d)
        self.assertEqual(d['primary_mood'], "happy")
        self.assertIn('happy', d['categories'])
    
    def test_song_categories_from_dict(self):
        """SongCategories.from_dict should recreate from dict."""
        from karaoke_engine import SongCategories
        
        data = {
            'categories': {'happy': 0.8, 'sad': 0.2},
            'primary_mood': 'happy'
        }
        
        cats = SongCategories.from_dict(data)
        self.assertEqual(cats.primary_mood, "happy")
        self.assertTrue(cats.cached)
        self.assertEqual(len(cats.categories), 2)
    
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
            self.assertGreater(len(result.categories), 0)
            # "love" and "happy" keywords should boost those scores
            love_score = result.get_category_score("love")
            happy_score = result.get_category_score("happy")
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
    
    def test_osc_sender_send_categories(self):
        """OSCSender.send_categories should work with SongCategories."""
        from karaoke_engine import OSCSender, SongCategory, SongCategories
        
        sender = OSCSender(host="127.0.0.1", port=9999)
        
        cats = SongCategories(
            categories=[
                SongCategory(name="happy", score=0.8),
                SongCategory(name="love", score=0.6),
            ],
            primary_mood="happy"
        )
        
        # Should not raise any errors
        sender.send_categories(cats)
        
        # Should have logged messages
        messages = sender.get_recent_messages()
        self.assertGreater(len(messages), 0)


if __name__ == "__main__":
    # Change to script directory for relative imports
    import os
    os.chdir(Path(__file__).parent)
    
    # Run tests
    unittest.main(verbosity=2)
