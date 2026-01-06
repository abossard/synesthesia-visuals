"""
Tests for Synesthesia OSC configuration.

Tests is_controllable, get_default_button_type, categorize_address, is_noisy_audio.
"""

import pytest
from launchpad_osc_lib.synesthesia_config import (
    is_controllable,
    is_noisy_audio,
    categorize_address,
    get_default_button_type,
    get_button_type_description,
    get_suggested_colors,
    OscAddressCategory,
    CONTROLLABLE_PREFIXES,
    NOISY_AUDIO_PREFIXES,
    BEAT_ADDRESS,
    BPM_ADDRESS,
)
from launchpad_osc_lib.model import PadMode, ButtonGroupType


class TestIsControllable:
    """Test is_controllable function."""

    @pytest.mark.parametrize("address,expected", [
        ("/scenes/Test", True),
        ("/scenes/AlienCavern", True),
        ("/presets/Cool", True),
        ("/favslots/0", True),
        ("/favslots/7", True),
        ("/playlist/next", True),
        ("/playlist/random", True),
        ("/controls/meta/hue", True),
        ("/controls/meta/saturation", True),
        ("/controls/global/strobe", True),
        ("/controls/global/mirror", True),
        ("/audio/beat/onbeat", False),
        ("/audio/bpm", False),
        ("/audio/level", False),
        ("/random/address", False),
        ("/unknown", False),
    ])
    def test_is_controllable(self, address, expected):
        """Test controllable address detection."""
        assert is_controllable(address) == expected


class TestCategorizeAddress:
    """Test categorize_address function."""

    def test_scene_category(self):
        """Scene addresses are categorized correctly."""
        assert categorize_address("/scenes/Test") == OscAddressCategory.SCENE
        assert categorize_address("/scenes/AlienCavern") == OscAddressCategory.SCENE

    def test_preset_category(self):
        """Preset addresses are categorized correctly."""
        assert categorize_address("/presets/Preset1") == OscAddressCategory.PRESET

    def test_favslot_category(self):
        """Favslot addresses are categorized correctly."""
        assert categorize_address("/favslots/0") == OscAddressCategory.FAVSLOT

    def test_playlist_category(self):
        """Playlist addresses are categorized correctly."""
        assert categorize_address("/playlist/next") == OscAddressCategory.PLAYLIST
        assert categorize_address("/playlist/random") == OscAddressCategory.PLAYLIST

    def test_meta_control_category(self):
        """Meta control addresses are categorized correctly."""
        assert categorize_address("/controls/meta/hue") == OscAddressCategory.META_CONTROL

    def test_global_control_category(self):
        """Global control addresses are categorized correctly."""
        assert categorize_address("/controls/global/strobe") == OscAddressCategory.GLOBAL_CONTROL

    def test_beat_category(self):
        """Beat addresses are categorized correctly."""
        assert categorize_address("/audio/beat/onbeat") == OscAddressCategory.BEAT

    def test_bpm_category(self):
        """BPM address is categorized correctly."""
        assert categorize_address("/audio/bpm") == OscAddressCategory.BPM

    def test_audio_level_category(self):
        """Audio level addresses are categorized correctly."""
        assert categorize_address("/audio/level") == OscAddressCategory.AUDIO_LEVEL
        assert categorize_address("/audio/level/bass") == OscAddressCategory.AUDIO_LEVEL

    def test_unknown_category(self):
        """Unknown addresses are categorized as UNKNOWN."""
        assert categorize_address("/random/path") == OscAddressCategory.UNKNOWN


class TestGetDefaultButtonType:
    """Test get_default_button_type function."""

    def test_scene_is_selector(self):
        """Scenes default to SELECTOR mode."""
        mode, group = get_default_button_type("/scenes/Test")
        assert mode == PadMode.SELECTOR
        assert group == ButtonGroupType.SCENES

    def test_preset_is_selector(self):
        """Presets default to SELECTOR mode."""
        mode, group = get_default_button_type("/presets/Preset1")
        assert mode == PadMode.SELECTOR
        assert group == ButtonGroupType.PRESETS

    def test_favslot_is_selector(self):
        """Favslots default to SELECTOR mode."""
        mode, group = get_default_button_type("/favslots/0")
        assert mode == PadMode.SELECTOR
        assert group == ButtonGroupType.PRESETS  # Shares group with presets

    def test_playlist_random_is_oneshot(self):
        """Playlist random is ONE_SHOT mode."""
        mode, group = get_default_button_type("/playlist/random")
        assert mode == PadMode.ONE_SHOT
        assert group is None

    def test_playlist_next_is_oneshot(self):
        """Playlist next is ONE_SHOT mode."""
        mode, group = get_default_button_type("/playlist/next")
        assert mode == PadMode.ONE_SHOT

    def test_global_strobe_is_toggle(self):
        """Global strobe is TOGGLE mode."""
        mode, group = get_default_button_type("/controls/global/strobe")
        assert mode == PadMode.TOGGLE
        assert group is None

    def test_global_mirror_is_toggle(self):
        """Global mirror is TOGGLE mode."""
        mode, group = get_default_button_type("/controls/global/mirror")
        assert mode == PadMode.TOGGLE

    def test_meta_hue_is_selector(self):
        """Meta hue is SELECTOR (for color palette)."""
        mode, group = get_default_button_type("/controls/meta/hue")
        assert mode == PadMode.SELECTOR
        assert group == ButtonGroupType.COLORS

    def test_unknown_defaults_to_oneshot(self):
        """Unknown addresses default to ONE_SHOT."""
        mode, group = get_default_button_type("/unknown/path")
        assert mode == PadMode.ONE_SHOT
        assert group is None


class TestGetButtonTypeDescription:
    """Test get_button_type_description function."""

    def test_scene_description(self):
        """Scene addresses have description."""
        desc = get_button_type_description("/scenes/Test")
        assert "Scene" in desc or "scene" in desc

    def test_toggle_description(self):
        """Toggle addresses have description."""
        desc = get_button_type_description("/controls/global/strobe")
        assert desc  # Has some description


class TestGetSuggestedColors:
    """Test get_suggested_colors function."""

    def test_returns_tuple(self):
        """Returns tuple of (idle_color, active_color)."""
        idle, active = get_suggested_colors("/scenes/Test")
        assert isinstance(idle, int)
        assert isinstance(active, int)

    def test_different_categories_have_different_colors(self):
        """Different categories have different suggested colors."""
        scene_colors = get_suggested_colors("/scenes/Test")
        preset_colors = get_suggested_colors("/presets/Test")
        global_colors = get_suggested_colors("/controls/global/strobe")

        # At least some should be different
        all_colors = [scene_colors, preset_colors, global_colors]
        assert len(set(all_colors)) > 1


class TestConstants:
    """Test configuration constants."""

    def test_beat_address(self):
        """Beat address constant is correct."""
        assert BEAT_ADDRESS == "/audio/beat/onbeat"

    def test_bpm_address(self):
        """BPM address constant is correct."""
        assert BPM_ADDRESS == "/audio/bpm"

    def test_controllable_prefixes_exist(self):
        """Controllable prefixes are defined."""
        assert len(CONTROLLABLE_PREFIXES) > 0
        assert "/scenes/" in CONTROLLABLE_PREFIXES
        assert "/presets/" in CONTROLLABLE_PREFIXES


class TestIsNoisyAudio:
    """Test is_noisy_audio function."""

    @pytest.mark.parametrize("address,expected", [
        # Noisy audio (high-frequency spam)
        ("/audio/level", True),
        ("/audio/level/bass", True),
        ("/audio/fft/bin0", True),
        ("/audio/fft/", True),
        ("/audio/timecode", True),
        # Non-noisy audio (sparse events)
        ("/audio/beat/onbeat", False),
        ("/audio/bpm", False),
        # Non-audio
        ("/scenes/Test", False),
        ("/presets/Cool", False),
        ("/global/strobe", False),
    ])
    def test_is_noisy_audio(self, address: str, expected: bool):
        """Test is_noisy_audio classification."""
        assert is_noisy_audio(address) == expected

    def test_noisy_prefixes_exist(self):
        """Noisy audio prefixes are defined."""
        assert len(NOISY_AUDIO_PREFIXES) > 0
        assert "/audio/level" in NOISY_AUDIO_PREFIXES


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
