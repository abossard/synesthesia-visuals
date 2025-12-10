"""
Tests for configuration persistence module.

These tests verify YAML serialization/deserialization works correctly.
"""

import pytest
import tempfile
from pathlib import Path

from launchpad_synesthesia_control.app.io.config import (
    ConfigManager, get_default_config_path,
    pad_id_to_str, str_to_pad_id,
    serialize_pad_behavior, deserialize_pad_behavior
)
from launchpad_osc_lib import (
    ButtonId, PadMode, PadGroupName, PadBehavior, OscCommand, ControllerState,
    PadRuntimeState
)


# =============================================================================
# ButtonId Serialization Tests
# =============================================================================

class TestButtonIdSerialization:
    """Test ButtonId string conversion."""

    def test_pad_id_to_str(self):
        """ButtonId converts to comma-separated string."""
        assert pad_id_to_str(ButtonId(0, 0)) == "0,0"
        assert pad_id_to_str(ButtonId(3, 5)) == "3,5"
        assert pad_id_to_str(ButtonId(8, 7)) == "8,7"
        assert pad_id_to_str(ButtonId(2, -1)) == "2,-1"

    def test_str_to_pad_id(self):
        """String converts back to ButtonId."""
        assert str_to_pad_id("0,0") == ButtonId(0, 0)
        assert str_to_pad_id("3,5") == ButtonId(3, 5)
        assert str_to_pad_id("8,7") == ButtonId(8, 7)
        assert str_to_pad_id("2,-1") == ButtonId(2, -1)

    def test_roundtrip(self):
        """ButtonId survives roundtrip conversion."""
        pads = [ButtonId(0, 0), ButtonId(7, 7), ButtonId(8, 3), ButtonId(5, -1)]
        for pad in pads:
            assert str_to_pad_id(pad_id_to_str(pad)) == pad


# =============================================================================
# PadBehavior Serialization Tests
# =============================================================================

class TestPadBehaviorSerialization:
    """Test PadBehavior serialization."""

    def test_serialize_selector(self):
        """Selector behavior serializes correctly."""
        behavior = PadBehavior(
            pad_id=ButtonId(0, 0),
            mode=PadMode.SELECTOR,
            group=PadGroupName.SCENES,
            idle_color=0,
            active_color=21,
            label="Test Scene",
            osc_action=OscCommand("/scenes/Test")
        )

        data = serialize_pad_behavior(behavior)

        assert data["mode"] == "SELECTOR"
        assert data["group"] == "scenes"
        assert data["idle_color"] == 0
        assert data["active_color"] == 21
        assert data["label"] == "Test Scene"
        assert data["osc_action"]["address"] == "/scenes/Test"

    def test_serialize_toggle(self):
        """Toggle behavior serializes correctly."""
        behavior = PadBehavior(
            pad_id=ButtonId(1, 1),
            mode=PadMode.TOGGLE,
            idle_color=0,
            active_color=5,
            label="My Toggle",
            osc_on=OscCommand("/toggle/on", [1]),
            osc_off=OscCommand("/toggle/off", [0])
        )

        data = serialize_pad_behavior(behavior)

        assert data["mode"] == "TOGGLE"
        assert "group" not in data
        assert data["osc_on"]["address"] == "/toggle/on"
        assert data["osc_on"]["args"] == [1]
        assert data["osc_off"]["address"] == "/toggle/off"
        assert data["osc_off"]["args"] == [0]

    def test_serialize_one_shot(self):
        """One-shot behavior serializes correctly."""
        behavior = PadBehavior(
            pad_id=ButtonId(2, 2),
            mode=PadMode.ONE_SHOT,
            idle_color=0,
            active_color=9,
            label="Next",
            osc_action=OscCommand("/playlist/next")
        )

        data = serialize_pad_behavior(behavior)

        assert data["mode"] == "ONE_SHOT"
        assert data["osc_action"]["address"] == "/playlist/next"

    def test_deserialize_selector(self):
        """Selector behavior deserializes correctly."""
        data = {
            "mode": "SELECTOR",
            "group": "scenes",
            "idle_color": 0,
            "active_color": 21,
            "label": "Test Scene",
            "osc_action": {"address": "/scenes/Test", "args": []}
        }

        behavior = deserialize_pad_behavior(ButtonId(0, 0), data)

        assert behavior.mode == PadMode.SELECTOR
        assert behavior.group == PadGroupName.SCENES
        assert behavior.osc_action.address == "/scenes/Test"

    def test_deserialize_toggle(self):
        """Toggle behavior deserializes correctly."""
        data = {
            "mode": "TOGGLE",
            "idle_color": 0,
            "active_color": 5,
            "label": "Toggle",
            "osc_on": {"address": "/on"},
            "osc_off": {"address": "/off"}
        }

        behavior = deserialize_pad_behavior(ButtonId(1, 1), data)

        assert behavior.mode == PadMode.TOGGLE
        assert behavior.osc_on.address == "/on"
        assert behavior.osc_off.address == "/off"

    def test_roundtrip_selector(self):
        """Selector survives serialization roundtrip."""
        original = PadBehavior(
            pad_id=ButtonId(0, 0),
            mode=PadMode.SELECTOR,
            group=PadGroupName.PRESETS,
            idle_color=1,
            active_color=45,
            label="Cool Preset",
            osc_action=OscCommand("/presets/Cool", [1, 2, 3])
        )

        data = serialize_pad_behavior(original)
        restored = deserialize_pad_behavior(ButtonId(0, 0), data)

        assert restored.mode == original.mode
        assert restored.group == original.group
        assert restored.idle_color == original.idle_color
        assert restored.active_color == original.active_color
        assert restored.label == original.label
        assert restored.osc_action.address == original.osc_action.address
        assert restored.osc_action.args == original.osc_action.args


# =============================================================================
# ConfigManager Tests
# =============================================================================

class TestConfigManager:
    """Test ConfigManager for full state persistence."""

    @pytest.fixture
    def temp_config_path(self):
        """Create a temporary config file path."""
        with tempfile.TemporaryDirectory() as tmpdir:
            yield Path(tmpdir) / "test_config.yaml"

    @pytest.fixture
    def sample_state(self):
        """Create a sample state with configured pads."""
        pad1 = ButtonId(0, 0)
        pad2 = ButtonId(1, 1)
        pad3 = ButtonId(2, 2)

        behavior1 = PadBehavior(
            pad_id=pad1, mode=PadMode.SELECTOR, group=PadGroupName.SCENES,
            osc_action=OscCommand("/scenes/Test"), label="Scene1",
            idle_color=0, active_color=21
        )
        behavior2 = PadBehavior(
            pad_id=pad2, mode=PadMode.TOGGLE,
            osc_on=OscCommand("/toggle/on"), osc_off=OscCommand("/toggle/off"),
            label="Toggle1", idle_color=0, active_color=5
        )
        behavior3 = PadBehavior(
            pad_id=pad3, mode=PadMode.ONE_SHOT,
            osc_action=OscCommand("/playlist/next"), label="Next",
            idle_color=0, active_color=9
        )

        return ControllerState(
            pads={pad1: behavior1, pad2: behavior2, pad3: behavior3},
            pad_runtime={
                pad1: PadRuntimeState(current_color=0),
                pad2: PadRuntimeState(current_color=0),
                pad3: PadRuntimeState(current_color=0)
            }
        )

    def test_save_and_load(self, temp_config_path, sample_state):
        """State can be saved and loaded."""
        manager = ConfigManager(temp_config_path)

        # Save
        manager.save(sample_state)
        assert temp_config_path.exists()

        # Load
        loaded = manager.load()
        assert loaded is not None
        assert len(loaded.pads) == 3

    def test_loaded_state_matches_saved(self, temp_config_path, sample_state):
        """Loaded state matches saved state."""
        manager = ConfigManager(temp_config_path)
        manager.save(sample_state)
        loaded = manager.load()

        # Check all pads present
        assert set(loaded.pads.keys()) == set(sample_state.pads.keys())

        # Check each pad's configuration
        for pad_id in sample_state.pads:
            original = sample_state.pads[pad_id]
            restored = loaded.pads[pad_id]

            assert restored.mode == original.mode
            assert restored.group == original.group
            assert restored.label == original.label
            assert restored.idle_color == original.idle_color
            assert restored.active_color == original.active_color

    def test_load_nonexistent_returns_none(self, temp_config_path):
        """Loading nonexistent config returns None."""
        manager = ConfigManager(temp_config_path)
        result = manager.load()
        assert result is None

    def test_load_empty_file_returns_none(self, temp_config_path):
        """Loading empty file returns None."""
        temp_config_path.parent.mkdir(parents=True, exist_ok=True)
        temp_config_path.write_text("")

        manager = ConfigManager(temp_config_path)
        result = manager.load()
        assert result is None

    def test_atomic_write(self, temp_config_path, sample_state):
        """Save uses atomic write (temp file then move)."""
        manager = ConfigManager(temp_config_path)
        manager.save(sample_state)

        # Temp file should not exist after save
        temp_path = temp_config_path.with_suffix('.tmp')
        assert not temp_path.exists()

        # Main file should exist
        assert temp_config_path.exists()

    def test_creates_parent_directory(self, temp_config_path, sample_state):
        """ConfigManager creates parent directories if needed."""
        deep_path = temp_config_path.parent / "deep" / "nested" / "config.yaml"
        manager = ConfigManager(deep_path)
        manager.save(sample_state)

        assert deep_path.exists()


# =============================================================================
# Default Config Path Tests
# =============================================================================

class TestDefaultConfigPath:
    """Test default config path function."""

    def test_returns_path_object(self):
        """Returns a Path object."""
        path = get_default_config_path()
        assert isinstance(path, Path)

    def test_path_in_config_directory(self):
        """Path is in .config directory."""
        path = get_default_config_path()
        assert ".config" in str(path) or "config" in str(path).lower()

    def test_path_ends_with_yaml(self):
        """Path ends with .yaml."""
        path = get_default_config_path()
        assert path.suffix == ".yaml"


# =============================================================================
# Edge Cases
# =============================================================================

class TestConfigEdgeCases:
    """Test edge cases and error handling."""

    @pytest.fixture
    def temp_config_path(self):
        """Create a temporary config file path."""
        with tempfile.TemporaryDirectory() as tmpdir:
            yield Path(tmpdir) / "test_config.yaml"

    def test_save_empty_state(self, temp_config_path):
        """Empty state can be saved and loaded."""
        manager = ConfigManager(temp_config_path)
        empty_state = ControllerState()

        manager.save(empty_state)
        loaded = manager.load()

        assert loaded is not None
        assert len(loaded.pads) == 0

    def test_load_corrupted_yaml(self, temp_config_path):
        """Corrupted YAML returns None and doesn't crash."""
        temp_config_path.parent.mkdir(parents=True, exist_ok=True)
        temp_config_path.write_text("not: valid: yaml: {{{}}}]]]")

        manager = ConfigManager(temp_config_path)
        result = manager.load()

        # Should return None, not raise exception
        assert result is None

    def test_special_characters_in_label(self, temp_config_path):
        """Labels with special characters are preserved."""
        pad_id = ButtonId(0, 0)
        behavior = PadBehavior(
            pad_id=pad_id, mode=PadMode.ONE_SHOT,
            osc_action=OscCommand("/test"),
            label="Test: Special & Characters <>"
        )

        state = ControllerState(
            pads={pad_id: behavior},
            pad_runtime={pad_id: PadRuntimeState()}
        )

        manager = ConfigManager(temp_config_path)
        manager.save(state)
        loaded = manager.load()

        assert loaded.pads[pad_id].label == "Test: Special & Characters <>"

    def test_osc_command_with_float_args(self, temp_config_path):
        """OSC commands with float args are preserved."""
        pad_id = ButtonId(0, 0)
        behavior = PadBehavior(
            pad_id=pad_id, mode=PadMode.SELECTOR,
            group=PadGroupName.COLORS,
            osc_action=OscCommand("/controls/meta/hue", [0.123456])
        )

        state = ControllerState(
            pads={pad_id: behavior},
            pad_runtime={pad_id: PadRuntimeState()}
        )

        manager = ConfigManager(temp_config_path)
        manager.save(state)
        loaded = manager.load()

        assert loaded.pads[pad_id].osc_action.args[0] == pytest.approx(0.123456)
