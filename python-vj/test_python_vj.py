#!/usr/bin/env python3
"""
Tests for Python VJ Tools

Focused on blackbox testing of actual behavior, not implementation details.

Run with: python -m pytest test_python_vj.py -v
Or simply: python test_python_vj.py
"""

import sys
import unittest
import tempfile
import subprocess
from pathlib import Path


class TestLyricsProcessing(unittest.TestCase):
    """Tests for lyrics parsing and analysis pipeline."""
    
    def test_lrc_parsing_full_song(self):
        """Parse a realistic LRC file and verify all lyrics are extracted correctly."""
        from karaoke_engine import parse_lrc, detect_refrains, get_active_line_index
        
        lrc = """[00:05.50]Verse one line one
[00:10.00]Verse one line two
[00:15.50]Chorus: love love love
[00:20.00]Verse two line one
[00:25.50]Chorus: love love love
[00:30.00]Bridge section
[00:35.50]Chorus: love love love
[00:40.00]Outro line"""
        
        # Parse and analyze
        lines = parse_lrc(lrc)
        analyzed = detect_refrains(lines)
        
        # Verify parsing
        self.assertEqual(len(analyzed), 8)
        self.assertEqual(analyzed[0].text, "Verse one line one")
        self.assertAlmostEqual(analyzed[0].time_sec, 5.5, places=1)
        
        # Verify refrain detection (chorus appears 3 times)
        refrain_lines = [l for l in analyzed if l.is_refrain]
        self.assertEqual(len(refrain_lines), 3)
        self.assertEqual(refrain_lines[0].text, "Chorus: love love love")
        
        # Verify active line lookup at different positions
        self.assertEqual(get_active_line_index(analyzed, 0), -1)  # Before first line
        self.assertEqual(get_active_line_index(analyzed, 12), 1)  # During verse 1 line 2
        self.assertEqual(get_active_line_index(analyzed, 27), 4)  # During second chorus
        self.assertEqual(get_active_line_index(analyzed, 100), 7)  # After song ends
    
    def test_keyword_extraction_filters_meaningless_words(self):
        """Keywords should contain meaningful words, not stop words."""
        from karaoke_engine import extract_keywords
        
        # Realistic lyric line with stop words and meaningful words
        lyric = "I will always love you forever in my heart"
        keywords = extract_keywords(lyric, max_words=10)  # Get more words
        
        # Should contain meaningful words
        self.assertIn("LOVE", keywords)
        self.assertIn("FOREVER", keywords)
        self.assertIn("HEART", keywords)
        
        # Should NOT contain stop words
        keywords_lower = keywords.lower()
        self.assertNotIn(" i ", f" {keywords_lower} ")
        self.assertNotIn(" will ", f" {keywords_lower} ")
        self.assertNotIn(" you ", f" {keywords_lower} ")


class TestSettingsPersistence(unittest.TestCase):
    """Tests for settings persistence across sessions."""
    
    def test_timing_offset_persists_across_sessions(self):
        """Timing offset should be saved and restored when reopening."""
        from karaoke_engine import Settings
        
        with tempfile.TemporaryDirectory() as tmpdir:
            settings_file = Path(tmpdir) / "settings.json"
            
            # Session 1: Adjust timing
            session1 = Settings(file_path=settings_file)
            session1.adjust_timing(+500)  # 500ms early
            session1.adjust_timing(-200)  # Back to 300ms early
            
            # Session 2: Should remember the offset
            session2 = Settings(file_path=settings_file)
            self.assertEqual(session2.timing_offset_ms, 300)
            self.assertAlmostEqual(session2.timing_offset_sec, 0.3, places=2)


class TestSongCategorization(unittest.TestCase):
    """Tests for song mood/theme categorization."""
    
    def test_categorize_happy_song(self):
        """Songs with happy lyrics should score high on positive categories."""
        from karaoke_engine import SongCategorizer
        
        with tempfile.TemporaryDirectory() as tmpdir:
            categorizer = SongCategorizer(cache_dir=Path(tmpdir))
            
            happy_lyrics = """
            I'm so happy today, feeling wonderful
            Joy and happiness everywhere I go
            Smile on my face, love in my heart
            Dancing with joy, celebration time
            """
            
            result = categorizer._categorize_basic("Happy Band", "Joy Song", happy_lyrics)
            
            # Happy categories should score higher than sad ones
            self.assertGreater(result.get_category_score("happy"), result.get_category_score("sad"))
            self.assertGreater(result.get_category_score("love"), 0)
    
    def test_categorize_dark_song(self):
        """Songs with dark lyrics should score high on negative categories."""
        from karaoke_engine import SongCategorizer
        
        with tempfile.TemporaryDirectory() as tmpdir:
            categorizer = SongCategorizer(cache_dir=Path(tmpdir))
            
            dark_lyrics = """
            In the darkness of the night
            Death and shadows all around
            Fear grips my soul, demons whisper
            The dark abyss calls my name
            """
            
            result = categorizer._categorize_basic("Dark Band", "Shadow Song", dark_lyrics)
            
            # Dark categories should score higher than happy ones
            self.assertGreater(result.get_category_score("dark"), result.get_category_score("happy"))
            self.assertGreater(result.get_category_score("death"), 0)
    
    def test_categories_serialization_roundtrip(self):
        """Categories should survive serialization to dict and back."""
        from karaoke_engine import SongCategory, SongCategories
        
        original = SongCategories(
            categories=[
                SongCategory(name="love", score=0.85),
                SongCategory(name="happy", score=0.6),
                SongCategory(name="dark", score=0.1),
            ],
            primary_mood="love"
        )
        
        # Round-trip through dict
        data = original.to_dict()
        restored = SongCategories.from_dict(data)
        
        # Should preserve all data
        self.assertEqual(restored.primary_mood, "love")
        self.assertAlmostEqual(restored.get_category_score("love"), 0.85, places=2)
        self.assertAlmostEqual(restored.get_category_score("happy"), 0.6, places=2)


class TestCLITools(unittest.TestCase):
    """Tests for command-line interfaces."""
    
    def test_karaoke_engine_cli_help(self):
        """karaoke_engine.py --help should display usage information."""
        result = subprocess.run(
            [sys.executable, "karaoke_engine.py", "--help"],
            capture_output=True, text=True, timeout=10
        )
        self.assertEqual(result.returncode, 0)
        self.assertIn("--osc-port", result.stdout)
    
    def test_background_analyzer_cli_help(self):
        """background_analyzer.py --help should display usage information."""
        result = subprocess.run(
            [sys.executable, "background_analyzer.py", "--help"],
            capture_output=True, text=True, timeout=10
        )
        self.assertEqual(result.returncode, 0)
        self.assertIn("--cache-dir", result.stdout)
        self.assertIn("--stats", result.stdout)
    
    def test_audio_setup_cli_help(self):
        """audio_setup.py --help should display usage information."""
        result = subprocess.run(
            [sys.executable, "audio_setup.py", "--help"],
            capture_output=True, text=True, timeout=10
        )
        self.assertEqual(result.returncode, 0)
        self.assertIn("--fix", result.stdout)


class TestBackgroundAnalyzerIntegration(unittest.TestCase):
    """Integration tests for BackgroundSongAnalyzer with real MP3 files."""
    
    @classmethod
    def setUpClass(cls):
        """Create test MP3 files for integration tests."""
        cls.test_dir = tempfile.mkdtemp()
        cls.test_file = cls._create_test_mp3(
            cls.test_dir, 
            "test_song.mp3",
            artist="Test Artist",
            title="Test Song",
            album="Test Album",
            genre="Rock",
            year="2024",
            bpm="128",
            key="C",
            lyrics="[00:00.50]Love love love\n[00:01.50]Heart and soul\n[00:02.50]Love love love"
        )
    
    @classmethod
    def tearDownClass(cls):
        """Clean up test directory."""
        import shutil
        shutil.rmtree(cls.test_dir, ignore_errors=True)
    
    @staticmethod
    def _create_test_mp3(test_dir: str, filename: str, **tags) -> Path:
        """Create a valid MP3 file with ID3 tags."""
        from mutagen.id3 import ID3, TIT2, TPE1, TALB, TCON, TDRC, TBPM, TKEY, USLT
        
        # Create minimal valid MP3 data (~3 seconds)
        header = bytes([0xFF, 0xFB, 0x90, 0x00])
        frame = header + bytes(413)
        mp3_data = frame * 115
        
        test_file = Path(test_dir) / filename
        test_file.write_bytes(mp3_data)
        
        # Add ID3 tags
        id3_tags = ID3()
        if tags.get('title'):
            id3_tags.add(TIT2(encoding=3, text=[tags['title']]))
        if tags.get('artist'):
            id3_tags.add(TPE1(encoding=3, text=[tags['artist']]))
        if tags.get('album'):
            id3_tags.add(TALB(encoding=3, text=[tags['album']]))
        if tags.get('genre'):
            id3_tags.add(TCON(encoding=3, text=[tags['genre']]))
        if tags.get('year'):
            id3_tags.add(TDRC(encoding=3, text=[tags['year']]))
        if tags.get('bpm'):
            id3_tags.add(TBPM(encoding=3, text=[tags['bpm']]))
        if tags.get('key'):
            id3_tags.add(TKEY(encoding=3, text=[tags['key']]))
        if tags.get('lyrics'):
            id3_tags.add(USLT(encoding=3, lang="eng", desc="", text=tags['lyrics']))
        id3_tags.save(test_file)
        
        return test_file
    
    def test_full_analysis_pipeline(self):
        """Complete analysis of an MP3 file should extract all metadata and compute metrics."""
        from background_analyzer import BackgroundSongAnalyzer
        
        with tempfile.TemporaryDirectory() as cache_dir:
            analyzer = BackgroundSongAnalyzer(cache_dir=Path(cache_dir))
            result = analyzer.analyze_file(self.test_file)
            
            # Verify metadata extraction
            self.assertEqual(result.metadata.artist, "Test Artist")
            self.assertEqual(result.metadata.title, "Test Song")
            self.assertEqual(result.metadata.album, "Test Album")
            self.assertEqual(result.metadata.genre, "Rock")
            self.assertEqual(result.metadata.bpm, 128.0)
            self.assertEqual(result.metadata.key, "C")
            
            # Verify lyrics were found and analyzed
            self.assertTrue(result.lyrics_found)
            self.assertEqual(result.lyrics_source, "embedded")
            self.assertEqual(result.line_count, 3)
            self.assertGreater(result.refrain_count, 0)  # "Love love love" repeats
            
            # Verify computed metrics are valid
            self.assertGreaterEqual(result.computed_energy, 0.0)
            self.assertLessEqual(result.computed_energy, 1.0)
            self.assertGreaterEqual(result.computed_danceability, 0.0)
            self.assertLessEqual(result.computed_danceability, 1.0)
            self.assertGreaterEqual(result.computed_valence, 0.0)
            self.assertLessEqual(result.computed_valence, 1.0)
            
            # Verify keywords were extracted
            self.assertIn("love", result.keywords)
    
    def test_folder_analysis(self):
        """Analyzing a folder should process all MP3 files."""
        from background_analyzer import BackgroundSongAnalyzer
        
        with tempfile.TemporaryDirectory() as cache_dir:
            analyzer = BackgroundSongAnalyzer(cache_dir=Path(cache_dir))
            results = analyzer.analyze_folder(Path(self.test_dir))
            
            self.assertEqual(len(results), 1)
            self.assertEqual(results[0].metadata.title, "Test Song")
    
    def test_cache_avoids_reprocessing(self):
        """Second analysis should use cached results."""
        from background_analyzer import BackgroundSongAnalyzer
        import time
        
        with tempfile.TemporaryDirectory() as cache_dir:
            analyzer = BackgroundSongAnalyzer(cache_dir=Path(cache_dir))
            
            # First analysis (should do full processing)
            start1 = time.time()
            result1 = analyzer.analyze_file(self.test_file)
            time1 = time.time() - start1
            
            # Second analysis (should use cache)
            start2 = time.time()
            result2 = analyzer.analyze_file(self.test_file)
            time2 = time.time() - start2
            
            # Results should be identical
            self.assertEqual(result1.metadata.title, result2.metadata.title)
            self.assertEqual(result1.line_count, result2.line_count)
            
            # Cache lookup should be faster (or at least not slower)
            # Note: In practice, both are fast, but cache shouldn't be slower
            self.assertLessEqual(time2, time1 + 0.1)  # Allow small margin
    
    def test_statistics_reflect_analyzed_songs(self):
        """Statistics should accurately reflect analyzed songs."""
        from background_analyzer import BackgroundSongAnalyzer
        
        with tempfile.TemporaryDirectory() as cache_dir:
            analyzer = BackgroundSongAnalyzer(cache_dir=Path(cache_dir))
            
            # Before analysis
            stats_before = analyzer.get_statistics()
            self.assertEqual(stats_before['total_songs'], 0)
            
            # After analysis
            analyzer.analyze_file(self.test_file)
            stats_after = analyzer.get_statistics()
            
            self.assertEqual(stats_after['total_songs'], 1)
            self.assertEqual(stats_after['with_lyrics'], 1)
            self.assertEqual(stats_after['with_bpm'], 1)


class TestComputedMetrics(unittest.TestCase):
    """Tests for computed audio metrics (energy, danceability, valence)."""
    
    def test_energy_reflects_song_mood(self):
        """Energy should be high for energetic songs, low for calm songs."""
        from background_analyzer import compute_energy_from_categories
        from karaoke_engine import SongCategory, SongCategories
        
        # High energy song
        energetic = SongCategories(categories=[
            SongCategory(name="energetic", score=0.9),
            SongCategory(name="aggressive", score=0.7),
            SongCategory(name="intense", score=0.6),
            SongCategory(name="calm", score=0.1),
        ])
        
        # Calm song
        calm = SongCategories(categories=[
            SongCategory(name="calm", score=0.9),
            SongCategory(name="peaceful", score=0.8),
            SongCategory(name="introspective", score=0.7),
            SongCategory(name="energetic", score=0.1),
        ])
        
        energy_high = compute_energy_from_categories(energetic)
        energy_low = compute_energy_from_categories(calm)
        
        # Energetic should have higher energy
        self.assertGreater(energy_high, energy_low)
        self.assertGreater(energy_high, 0.5)
        self.assertLess(energy_low, 0.5)
    
    def test_danceability_considers_bpm(self):
        """Danceability should factor in BPM when available."""
        from background_analyzer import compute_danceability_from_categories
        from karaoke_engine import SongCategory, SongCategories
        
        danceable = SongCategories(categories=[
            SongCategory(name="danceable", score=0.8),
            SongCategory(name="energetic", score=0.6),
        ])
        
        # Optimal dance BPM (120)
        dance_optimal = compute_danceability_from_categories(danceable, bpm=120.0)
        
        # Too slow BPM (60)
        dance_slow = compute_danceability_from_categories(danceable, bpm=60.0)
        
        # Too fast BPM (200)
        dance_fast = compute_danceability_from_categories(danceable, bpm=200.0)
        
        # Optimal BPM should have highest danceability
        self.assertGreater(dance_optimal, dance_slow)
        self.assertGreater(dance_optimal, dance_fast)
    
    def test_valence_reflects_emotional_tone(self):
        """Valence should be high for happy songs, low for sad songs."""
        from background_analyzer import compute_valence_from_categories
        from karaoke_engine import SongCategory, SongCategories
        
        # Happy song
        happy = SongCategories(categories=[
            SongCategory(name="happy", score=0.9),
            SongCategory(name="uplifting", score=0.8),
            SongCategory(name="bright", score=0.7),
        ])
        
        # Sad song
        sad = SongCategories(categories=[
            SongCategory(name="sad", score=0.9),
            SongCategory(name="melancholic", score=0.8),
            SongCategory(name="dark", score=0.7),
        ])
        
        valence_happy = compute_valence_from_categories(happy)
        valence_sad = compute_valence_from_categories(sad)
        
        self.assertGreater(valence_happy, valence_sad)
        self.assertGreater(valence_happy, 0.5)
        self.assertLess(valence_sad, 0.5)


class TestOSCOutput(unittest.TestCase):
    """Tests for OSC message generation."""
    
    def test_categories_sent_via_osc(self):
        """Song categories should be sent as OSC messages."""
        from karaoke_engine import OSCSender, SongCategory, SongCategories
        
        # Create sender (won't actually send, just logs)
        sender = OSCSender(host="127.0.0.1", port=9999)
        
        categories = SongCategories(
            categories=[
                SongCategory(name="love", score=0.85),
                SongCategory(name="happy", score=0.6),
            ],
            primary_mood="love"
        )
        
        # Send categories
        sender.send_categories(categories)
        
        # Check logged messages
        messages = sender.get_recent_messages()
        addresses = [msg[1] for msg in messages]
        
        # Should have sent mood and category messages
        self.assertIn("/karaoke/categories/mood", addresses)
        self.assertIn("/karaoke/categories/love", addresses)
        self.assertIn("/karaoke/categories/happy", addresses)


if __name__ == "__main__":
    # Change to script directory for relative imports
    import os
    os.chdir(Path(__file__).parent)
    
    # Run tests
    unittest.main(verbosity=2)
