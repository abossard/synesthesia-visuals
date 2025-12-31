"""
E2E tests for Playback module.

Run with: pytest tests/modules/test_playback.py -v -s
"""
import time


class TestPlaybackLifecycle:
    """Test Playback module lifecycle."""

    def test_module_starts_and_stops_cleanly(self):
        """Playback module starts and stops without errors."""
        from modules.playback import PlaybackModule, PlaybackConfig

        config = PlaybackConfig()
        playback = PlaybackModule(config)

        assert not playback.is_started
        assert playback.current_source is None

        success = playback.start()
        assert success, "Module should start successfully"
        assert playback.is_started

        status = playback.get_status()
        assert status["started"] is True
        assert "available_sources" in status

        playback.stop()
        assert not playback.is_started

        print("\nModule started and stopped cleanly")

    def test_module_can_restart(self):
        """Playback module can be stopped and restarted."""
        from modules.playback import PlaybackModule

        playback = PlaybackModule()

        playback.start()
        assert playback.is_started

        playback.stop()
        assert not playback.is_started

        playback.start()
        assert playback.is_started

        playback.stop()
        print("\nModule restart successful")


class TestPlaybackSourceSelection:
    """Test playback source selection and hot-swap."""

    def test_set_source_vdj(self):
        """Can set VDJ as playback source."""
        from modules.playback import PlaybackModule

        playback = PlaybackModule()

        success = playback.set_source("vdj_osc")
        assert success, "Should set VDJ source"
        assert playback.current_source == "vdj_osc"

        print("\nVDJ source set successfully")

    def test_set_source_spotify(self):
        """Can set Spotify as playback source."""
        from modules.playback import PlaybackModule

        playback = PlaybackModule()

        success = playback.set_source("spotify_applescript")
        assert success, "Should set Spotify source"
        assert playback.current_source == "spotify_applescript"

        print("\nSpotify source set successfully")

    def test_source_hot_swap(self, requires_vdj_running):
        """Can hot-swap playback source while running."""
        from modules.playback import PlaybackModule

        playback = PlaybackModule()
        playback.set_source("spotify_applescript")
        playback.start()

        assert playback.current_source == "spotify_applescript"

        # Hot-swap to VDJ
        success = playback.set_source("vdj_osc")
        assert success, "Should hot-swap to VDJ"
        assert playback.current_source == "vdj_osc"

        playback.stop()
        print("\nSource hot-swap successful")

    def test_invalid_source_rejected(self):
        """Invalid source is rejected."""
        from modules.playback import PlaybackModule

        playback = PlaybackModule()

        success = playback.set_source("invalid_source")
        assert not success, "Should reject invalid source"
        assert playback.current_source is None

        print("\nInvalid source rejected correctly")


class TestPlaybackVDJIntegration:
    """Test playback with VirtualDJ."""

    def test_detects_playing_track(self, requires_vdj_playing):
        """Playback module detects currently playing track from VDJ."""
        from modules.playback import PlaybackModule

        expected = requires_vdj_playing  # Cached track from fixture

        playback = PlaybackModule()
        playback.set_source("vdj_osc")
        playback.start()

        # Wait for track detection
        detected_track = None
        for _ in range(20):
            result = playback.poll_once()
            if result.get("track"):
                detected_track = result["track"]
                break
            time.sleep(0.5)

        playback.stop()

        assert detected_track is not None, "Should detect track"
        assert detected_track["artist"] == expected["artist"]
        assert detected_track["title"] == expected["title"]

        print(f"\nDetected: {detected_track['artist']} - {detected_track['title']}")

    def test_track_change_callback_fires(self, requires_vdj_playing):
        """Track change callback fires when track is detected."""
        from modules.playback import PlaybackModule

        callback_tracks = []

        def on_track(track):
            callback_tracks.append(track)

        playback = PlaybackModule()
        playback.on_track_change = on_track
        playback.set_source("vdj_osc")
        playback.start()

        # Wait for callback
        for _ in range(20):
            if callback_tracks:
                break
            time.sleep(0.5)

        playback.stop()

        assert len(callback_tracks) > 0, "Track change callback should fire"
        print(f"\nCallback received track: {callback_tracks[0]}")

    def test_position_updates_while_playing(self, requires_vdj_playing):
        """Position updates fire while track is playing."""
        from modules.playback import PlaybackModule

        positions = []

        def on_position(pos, duration):
            positions.append((pos, duration))

        playback = PlaybackModule()
        playback.on_position_update = on_position
        playback.set_source("vdj_osc")
        playback.start()

        # Wait for position updates
        time.sleep(3)

        playback.stop()

        assert len(positions) > 0, "Should receive position updates"
        print(f"\nReceived {len(positions)} position updates")
        if positions:
            last_pos, last_dur = positions[-1]
            print(f"Last position: {last_pos:.1f}s / {last_dur:.1f}s")


class TestPlaybackStandalone:
    """Test standalone CLI functionality."""

    def test_cli_module_importable(self):
        """Playback CLI can be imported."""
        from modules.playback import main, PlaybackConfig, PlaybackModule, TrackInfo

        assert callable(main)
        assert PlaybackConfig is not None
        assert PlaybackModule is not None
        assert TrackInfo is not None

        print("\nCLI module imports successfully")
