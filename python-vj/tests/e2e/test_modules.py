"""
End-to-end tests for python-vj module structure.

Tests that all modules can be imported and basic functionality works.
Run with: pytest tests/e2e/test_modules.py -v
"""

import pytest
import sys
from pathlib import Path

# Ensure python-vj is in path
sys.path.insert(0, str(Path(__file__).parent.parent.parent))


class TestOSCModule:
    """Test the osc/ module."""

    def test_import_from_osc(self):
        """Can import from osc module."""
        from osc import osc, osc_monitor, Channel, OSCHub, ChannelConfig
        assert osc is not None
        assert osc_monitor is not None

    def test_import_backwards_compat(self):
        """Can import from osc_hub for backwards compatibility."""
        from osc_hub import osc, osc_monitor
        assert osc is not None

    def test_osc_hub_not_started_by_default(self):
        """OSC hub should not be started by default."""
        from osc import osc
        # Don't actually start it in tests
        assert not osc.is_started

    def test_channel_config(self):
        """Channel configs are properly defined."""
        from osc import VDJ, SYNESTHESIA, KARAOKE
        assert VDJ.send_port == 9009
        assert VDJ.recv_port == 9008
        assert SYNESTHESIA.send_port == 7777
        assert SYNESTHESIA.recv_port == 9999
        assert KARAOKE.send_port == 9000
        assert KARAOKE.recv_port is None

    def test_channel_status(self):
        """Can get channel status without starting."""
        from osc import osc
        status = osc.get_channel_status()
        assert "vdj" in status
        assert "synesthesia" in status
        assert "karaoke" in status
        assert status["vdj"]["active"] is False


class TestShadersModule:
    """Test the shaders/ module."""

    def test_import_types(self):
        """Can import shader types."""
        from shaders import (
            ShaderFeatures,
            ShaderInputs,
            SongFeatures,
            ShaderMatch,
            AudioSource,
            ModulationType,
        )
        assert ShaderFeatures is not None
        assert AudioSource.BASS == "bass"
        assert ModulationType.ADD == "add"

    def test_import_classes(self):
        """Can import main classes."""
        from shaders import ShaderIndexer, ShaderMatcher, ShaderSelector
        assert ShaderIndexer is not None
        assert ShaderMatcher is not None
        assert ShaderSelector is not None

    def test_shader_features_vector(self):
        """ShaderFeatures produces correct vector."""
        from shaders import ShaderFeatures
        features = ShaderFeatures(
            name="test",
            path="/test",
            energy_score=0.8,
            mood_valence=0.5,
            color_warmth=0.3,
            motion_speed=0.7,
            geometric_score=0.4,
            visual_density=0.6,
        )
        vector = features.to_vector()
        assert len(vector) == 6
        assert vector[0] == 0.8  # energy
        assert vector[1] == 0.5  # mood

    def test_song_features_to_shader_target(self):
        """SongFeatures converts to shader target vector."""
        from shaders import SongFeatures
        song = SongFeatures(
            title="Test Song",
            artist="Test Artist",
            energy=0.9,
            valence=0.7,
        )
        target = song.to_shader_target()
        assert len(target) == 6
        assert target[0] == 0.9  # energy maps to energy_score


class TestMusicModule:
    """Test the music/ module."""

    def test_import_engine(self):
        """Can import KaraokeEngine."""
        from music import KaraokeEngine
        assert KaraokeEngine is not None

    def test_import_categories(self):
        """Can import song categories."""
        from music import SongCategories, SongCategory
        assert SongCategories is not None
        assert SongCategory is not None

    def test_import_playback(self):
        """Can import playback types."""
        from music import PlaybackState, Track, PLAYBACK_SOURCES
        assert PlaybackState is not None
        assert Track is not None
        assert PLAYBACK_SOURCES is not None

    def test_import_lyrics(self):
        """Can import lyrics utilities."""
        from music import parse_lrc, LyricLine, detect_refrains
        assert parse_lrc is not None
        assert LyricLine is not None

    def test_playback_sources_defined(self):
        """Playback sources are properly defined."""
        from music import PLAYBACK_SOURCES
        assert isinstance(PLAYBACK_SOURCES, dict)
        # Should have at least VDJ
        assert len(PLAYBACK_SOURCES) > 0


class TestAIModule:
    """Test the ai/ module."""

    def test_import_llm(self):
        """Can import LLMAnalyzer."""
        from ai import LLMAnalyzer
        assert LLMAnalyzer is not None

    def test_import_categorizer(self):
        """Can import SongCategorizer."""
        from ai import SongCategorizer
        assert SongCategorizer is not None


class TestDomainModule:
    """Test the domain/ module."""

    def test_import_types(self):
        """Can import domain types."""
        from domain import PlaybackSnapshot, PlaybackState
        assert PlaybackSnapshot is not None
        assert PlaybackState is not None

    def test_backwards_compat(self):
        """Can import from domain_types directly."""
        from domain_types import PlaybackSnapshot
        assert PlaybackSnapshot is not None


class TestInfrastructureModule:
    """Test the infrastructure/ module."""

    def test_import_settings(self):
        """Can import Settings."""
        from infrastructure import Settings
        assert Settings is not None

    def test_import_process_manager(self):
        """Can import ProcessManager."""
        from infrastructure import ProcessManager
        assert ProcessManager is not None

    def test_backwards_compat(self):
        """Can import from infra directly."""
        from infra import Settings
        assert Settings is not None


class TestLaunchpadModule:
    """Test the launchpad_osc_lib module integration."""

    def test_import_core(self):
        """Can import core launchpad types."""
        from launchpad_osc_lib import (
            ControllerState,
            ButtonId,
            handle_pad_press,
            SendOscEffect,
            LedEffect,
        )
        assert ControllerState is not None
        assert ButtonId is not None

    def test_import_fsm_functions(self):
        """Can import FSM functions."""
        from launchpad_osc_lib import (
            handle_pad_press,
            handle_pad_release,
            handle_osc_event,
            enter_learn_mode,
        )
        assert handle_pad_press is not None

    def test_controller_state_default(self):
        """ControllerState has sensible defaults."""
        from launchpad_osc_lib import ControllerState, LearnPhase
        state = ControllerState()
        assert state.learn_state.phase == LearnPhase.IDLE
        assert len(state.pads) == 0

    def test_button_id_creation(self):
        """ButtonId can be created."""
        from launchpad_osc_lib import ButtonId
        btn = ButtonId(0, 0)
        assert btn.x == 0
        assert btn.y == 0


class TestIntegration:
    """Integration tests across modules."""

    def test_osc_and_launchpad(self):
        """Launchpad can use OSC hub."""
        from osc import osc
        from launchpad_osc_lib import SendOscEffect, OscCommand

        # Create an effect (don't actually send)
        effect = SendOscEffect(command=OscCommand("/test", [1, 2, 3]))
        assert effect.command.address == "/test"
        assert effect.command.args == [1, 2, 3]

    def test_shaders_and_music(self):
        """Shader matching works with music features."""
        from shaders import SongFeatures, ShaderFeatures

        song = SongFeatures(
            title="Energetic Track",
            artist="DJ Test",
            energy=0.9,
            valence=0.8,
        )

        shader = ShaderFeatures(
            name="laser",
            path="/shaders/laser.fs",
            energy_score=0.85,
            mood_valence=0.7,
        )

        # Both produce compatible vectors
        song_target = song.to_shader_target()
        shader_vector = shader.to_vector()
        assert len(song_target) == len(shader_vector)

    def test_all_modules_import(self):
        """All modules can be imported together without conflicts."""
        from osc import osc
        from shaders import ShaderIndexer
        from music import KaraokeEngine
        from ai import LLMAnalyzer
        from domain import PlaybackSnapshot
        from infrastructure import Settings
        from launchpad_osc_lib import ControllerState

        # All imports succeeded
        assert osc is not None
        assert ShaderIndexer is not None
        assert KaraokeEngine is not None
        assert LLMAnalyzer is not None
        assert PlaybackSnapshot is not None
        assert Settings is not None
        assert ControllerState is not None


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
