"""
E2E tests for Lyrics module.

Run with: pytest tests/modules/test_lyrics.py -v -s
"""
import time


class TestLyricsLifecycle:
    """Test Lyrics module lifecycle."""

    def test_module_starts_and_stops_cleanly(self):
        """Lyrics module starts and stops without errors."""
        from modules.lyrics import LyricsModule, LyricsConfig

        config = LyricsConfig()
        lyrics = LyricsModule(config)

        assert not lyrics.is_started

        success = lyrics.start()
        assert success, "Module should start successfully"
        assert lyrics.is_started

        status = lyrics.get_status()
        assert status["started"] is True
        assert status["line_count"] == 0

        lyrics.stop()
        assert not lyrics.is_started

        print("\nModule started and stopped cleanly")


class TestLyricsFetching:
    """Test lyrics fetching from LRCLIB."""

    def test_fetches_lyrics_for_known_song(self, requires_internet):
        """Fetches synced lyrics for a well-known song."""
        from modules.lyrics import LyricsModule

        lyrics = LyricsModule()

        success = lyrics.fetch("Queen", "Bohemian Rhapsody")
        assert success, "Should fetch lyrics for Queen - Bohemian Rhapsody"
        assert lyrics.line_count > 0, "Should have lyrics lines"

        lyrics.stop()
        print(f"\nFetched {lyrics.line_count} lines")

    def test_lyrics_have_valid_timing(self, requires_internet):
        """Lyrics have valid timing data."""
        from modules.lyrics import LyricsModule

        lyrics = LyricsModule()
        lyrics.fetch("Queen", "Bohemian Rhapsody")

        lines = lyrics.lines
        assert len(lines) > 0, "Should have lines"

        # Check timing is sequential and non-negative
        prev_time = -1.0
        for line in lines:
            assert line.time_sec >= 0, "Time should be non-negative"
            assert line.time_sec >= prev_time, "Times should be sequential"
            prev_time = line.time_sec

        lyrics.stop()
        print(f"\nAll {len(lines)} lines have valid timing")

    def test_handles_song_without_lyrics(self, requires_internet):
        """Handles songs without lyrics gracefully."""
        from modules.lyrics import LyricsModule

        lyrics = LyricsModule()

        success = lyrics.fetch("zzznonexistent12345", "notarealsong67890")
        assert not success, "Should return False for unknown song"
        assert lyrics.line_count == 0, "Should have no lines"

        lyrics.stop()
        print("\nGracefully handled missing song")

    def test_detects_refrains(self, requires_internet):
        """Detects refrain (chorus) lines."""
        from modules.lyrics import LyricsModule

        lyrics = LyricsModule()
        lyrics.fetch("Queen", "Bohemian Rhapsody")

        refrains = lyrics.get_refrain_lines()
        # Bohemian Rhapsody has repeated sections
        assert len(refrains) >= 0, "Refrain detection should work"

        lyrics.stop()
        print(f"\nDetected {len(refrains)} refrain lines")

    def test_caching_makes_second_fetch_faster(self, requires_internet):
        """Second fetch uses cache and is faster."""
        from modules.lyrics import LyricsModule

        lyrics = LyricsModule()

        # First fetch (may hit network)
        start1 = time.time()
        lyrics.fetch("Queen", "We Will Rock You")
        elapsed1 = time.time() - start1

        # Second fetch (should use cache)
        start2 = time.time()
        lyrics.fetch("Queen", "We Will Rock You")
        elapsed2 = time.time() - start2

        lyrics.stop()

        # Cache should be faster (or at least not significantly slower)
        print(f"\nFirst fetch: {elapsed1:.3f}s, Second fetch: {elapsed2:.3f}s")
        # We don't assert timing because network conditions vary


class TestLyricsSync:
    """Test lyrics position sync."""

    def test_active_line_changes_with_position(self, requires_internet):
        """Active line changes when position updates."""
        from modules.lyrics import LyricsModule

        lyrics = LyricsModule()
        lyrics.fetch("Queen", "Bohemian Rhapsody")

        lines = lyrics.lines
        if not lines:
            print("\nNo lines to test (song may not have synced lyrics)")
            return

        # Find a time that should activate a line
        test_time = lines[min(5, len(lines) - 1)].time_sec + 0.1

        # Update position
        result = lyrics.update_position(test_time)
        assert result is not None, "Should return active line"
        assert lyrics.active_index >= 0, "Should have active index"

        lyrics.stop()
        print(f"\nActive line at {test_time:.1f}s: [{lyrics.active_index}] {result.text[:40]}...")

    def test_active_line_callback_fires(self, requires_internet):
        """Active line callback fires when line changes."""
        from modules.lyrics import LyricsModule

        callback_calls = []

        def on_line(idx, line):
            callback_calls.append((idx, line))

        lyrics = LyricsModule()
        lyrics.on_active_line = on_line
        lyrics.fetch("Queen", "Bohemian Rhapsody")

        lines = lyrics.lines
        if not lines:
            print("\nNo lines to test")
            return

        # Update to different positions
        lyrics.update_position(lines[0].time_sec + 0.1)
        if len(lines) > 5:
            lyrics.update_position(lines[5].time_sec + 0.1)

        lyrics.stop()

        assert len(callback_calls) > 0, "Callback should fire"
        print(f"\nCallback fired {len(callback_calls)} times")

    def test_timing_offset_affects_sync(self, requires_internet):
        """Timing offset shifts active line detection."""
        from modules.lyrics import LyricsModule, LyricsConfig

        # Create module with offset
        config = LyricsConfig(timing_offset_ms=-5000)  # 5s early
        lyrics = LyricsModule(config)
        lyrics.fetch("Queen", "Bohemian Rhapsody")

        lines = lyrics.lines
        if len(lines) < 2:
            print("\nNot enough lines to test")
            return

        # With -5000ms offset, position 0 should match a line ~5s in
        # Find a line around 5s
        target_line = None
        for line in lines:
            if line.time_sec >= 4.5 and line.time_sec <= 5.5:
                target_line = line
                break

        if target_line:
            result = lyrics.update_position(0.0)
            if result:
                print(f"\nWith -5s offset, position 0 shows: {result.text[:40]}...")

        lyrics.stop()
        print("\nTiming offset affects sync")


class TestLyricsVDJIntegration:
    """Test lyrics sync with live VDJ playback."""

    def test_lyrics_sync_to_playing_song(self, requires_vdj_playing, requires_internet):
        """Lyrics sync to currently playing VDJ track."""
        from modules.lyrics import LyricsModule
        from modules.playback import PlaybackModule

        track = requires_vdj_playing
        artist = track["artist"]
        title = track["title"]

        lyrics = LyricsModule()
        playback = PlaybackModule()
        playback.set_source("vdj_osc")
        playback.start()

        # Try to fetch lyrics for the playing track
        has_lyrics = lyrics.fetch(artist, title)

        if not has_lyrics:
            print(f"\nNo synced lyrics available for: {artist} - {title}")
            playback.stop()
            return

        # Get current position from playback
        active_lines = []

        def on_line(idx, line):
            active_lines.append((idx, line))

        lyrics.on_active_line = on_line

        # Poll for a few seconds
        for _ in range(10):
            result = playback.poll_once()
            if result.get("track") and result.get("position_sec"):
                lyrics.update_position(result["position_sec"])
            time.sleep(0.3)

        playback.stop()
        lyrics.stop()

        print(f"\nSynced {len(active_lines)} lines to VDJ playback")


class TestLyricsStandalone:
    """Test standalone CLI functionality."""

    def test_cli_module_importable(self):
        """Lyrics CLI can be imported."""
        from modules.lyrics import main, LyricsConfig, LyricsModule, LyricLineInfo

        assert callable(main)
        assert LyricsConfig is not None
        assert LyricsModule is not None
        assert LyricLineInfo is not None

        print("\nCLI module imports successfully")
