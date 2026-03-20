"""Tests for shader_versions, fractal shader, and ISF converter."""

import json
import os
import numpy as np
import pytest

from shader_versions import ShaderVersion, ShaderVersionStore


# ── ShaderVersion ────────────────────────────────────────────

class TestShaderVersion:
    def test_create(self):
        v = ShaderVersion.create(code="def render_ai(): pass", prompt="test", description="desc")
        assert len(v.id) == 8
        assert v.code == "def render_ai(): pass"
        assert v.prompt == "test"
        assert v.description == "desc"
        assert v.parent_id is None
        assert v.timestamp > 0

    def test_immutable(self):
        v = ShaderVersion.create(code="x", prompt="y")
        with pytest.raises(AttributeError):
            v.code = "z"

    def test_with_parent(self):
        v1 = ShaderVersion.create(code="a", prompt="p1")
        v2 = ShaderVersion.create(code="b", prompt="p2", parent_id=v1.id)
        assert v2.parent_id == v1.id


# ── ShaderVersionStore ───────────────────────────────────────

class TestShaderVersionStore:
    def test_empty_store(self):
        store = ShaderVersionStore()
        assert store.count == 0
        assert store.current is None
        assert store.cursor == -1

    def test_add_and_current(self):
        store = ShaderVersionStore()
        v = ShaderVersion.create(code="a", prompt="p")
        store.add(v)
        assert store.count == 1
        assert store.current == v
        assert store.cursor == 0

    def test_navigation(self):
        store = ShaderVersionStore()
        v1 = ShaderVersion.create(code="a", prompt="p1")
        v2 = ShaderVersion.create(code="b", prompt="p2")
        v3 = ShaderVersion.create(code="c", prompt="p3")
        store.add(v1)
        store.add(v2)
        store.add(v3)

        assert store.cursor == 2
        assert store.current == v3

        # Go back
        result = store.go_prev()
        assert result == v2
        assert store.cursor == 1

        result = store.go_prev()
        assert result == v1
        assert store.cursor == 0

        # At start, go_prev returns None
        result = store.go_prev()
        assert result is None
        assert store.cursor == 0

        # Go forward
        result = store.go_next()
        assert result == v2

        result = store.go_next()
        assert result == v3

        # At end, go_next returns None
        result = store.go_next()
        assert result is None
        assert store.cursor == 2

    def test_go_to(self):
        store = ShaderVersionStore()
        for i in range(5):
            store.add(ShaderVersion.create(code=f"v{i}", prompt=f"p{i}"))
        
        result = store.go_to(2)
        assert result.code == "v2"
        assert store.cursor == 2

        # Out of range
        assert store.go_to(-1) is None
        assert store.go_to(99) is None

    def test_save_and_load(self, tmp_path):
        store = ShaderVersionStore()
        v1 = ShaderVersion.create(code="code1", prompt="prompt1", description="first")
        v2 = ShaderVersion.create(code="code2", prompt="prompt2", parent_id=v1.id)
        store.add(v1)
        store.add(v2)
        store.go_prev()

        path = str(tmp_path / "versions.json")
        store.save(path)

        loaded = ShaderVersionStore.load(path)
        assert loaded.count == 2
        assert loaded.cursor == 0
        assert loaded.current.code == "code1"
        assert loaded.versions[1].parent_id == v1.id

    def test_load_missing_file(self, tmp_path):
        store = ShaderVersionStore.load(str(tmp_path / "nonexistent.json"))
        assert store.count == 0

    def test_load_corrupt_file(self, tmp_path):
        path = str(tmp_path / "bad.json")
        with open(path, "w") as f:
            f.write("not valid json{{{")
        store = ShaderVersionStore.load(path)
        assert store.count == 0

    def test_to_dict_roundtrip(self):
        store = ShaderVersionStore()
        store.add(ShaderVersion.create(code="x", prompt="y", description="z"))
        data = store.to_dict()
        restored = ShaderVersionStore.from_dict(data)
        assert restored.count == 1
        assert restored.current.code == "x"
        assert restored.current.description == "z"

    def test_delete_current(self):
        store = ShaderVersionStore()
        v1 = ShaderVersion.create(code="a", prompt="p1")
        v2 = ShaderVersion.create(code="b", prompt="p2")
        v3 = ShaderVersion.create(code="c", prompt="p3")
        store.add(v1)
        store.add(v2)
        store.add(v3)
        # Delete middle (cursor at end, go back to middle)
        store.go_to(1)
        result = store.delete_current()
        assert store.count == 2
        assert result.code == "c"  # Cursor moves to next
        assert store.cursor == 1

    def test_delete_last_remaining(self):
        store = ShaderVersionStore()
        store.add(ShaderVersion.create(code="x", prompt="p"))
        result = store.delete_current()
        assert result is None
        assert store.count == 0
        assert store.cursor == -1

    def test_delete_empty(self):
        store = ShaderVersionStore()
        assert store.delete_current() is None


# ── Fractal Shader ───────────────────────────────────────────

class TestFractalShader:
    @pytest.fixture
    def audio(self):
        class MockAudio:
            mel_bands = np.zeros(40)
            spectrum = np.zeros(256)
            centroid = 0.5
            spread = 0.3
            flux = 0.1
            flatness = 0.2
            rolloff = 0.6
            slope = 0.1
            kurtosis = 0.3
            beat = False
            onset = False
            onset_strength = 0.0
            bpm = 120.0
            rms = 0.3
            pitch_hz = 440.0
            pitch_confidence = 0.8
            waveform = np.zeros(512)
            is_quiet = False
            mfcc = np.zeros(13)
            pitch_midi = 69.0
            # Algorithm features
            band_sub_bass = band_kick = band_snare = 0.2
            band_mid = band_presence = band_high = band_air = 0.2
            kick_pulse = snare_pulse = hat_pulse = 0.0
            beat_phase = 0.0
            centroid_velocity = 0.0
            low_flux = high_flux = 0.1
            tension = 0.0
            mfcc_distance = 0.5
            timbre_hue = timbre_scale = timbre_bright = 0.3
            osc_half = osc_beat = osc_double = osc_triplet = osc_sixteenth = 0.0
        return MockAudio()

    def test_fractal_runs_without_crash(self, audio):
        from termvj import render_fractal
        fb = np.zeros((40, 80, 3), dtype=np.uint8)
        lut = np.zeros((256, 3), dtype=np.uint8)
        lut[:, 0] = np.arange(256)
        state = {}
        for frame in range(5):
            render_fractal(fb, audio, frame, lut, state)
        assert fb.sum() > 0  # Not all black

    def test_fractal_produces_varied_output(self, audio):
        from termvj import render_fractal
        fb = np.zeros((40, 80, 3), dtype=np.uint8)
        lut = np.zeros((256, 3), dtype=np.uint8)
        for i in range(256):
            lut[i] = [i, 255 - i, (i * 3) % 256]
        state = {}
        render_fractal(fb, audio, 0, lut, state)
        # Check that we have at least 10 distinct colors (not a flat fill)
        unique_colors = len(np.unique(fb.reshape(-1, 3), axis=0))
        assert unique_colors > 10

    def test_fractal_beat_toggles_julia(self, audio):
        from termvj import render_fractal
        fb = np.zeros((20, 40, 3), dtype=np.uint8)
        lut = np.zeros((256, 3), dtype=np.uint8)
        lut[:, 0] = np.arange(256)
        state = {}
        render_fractal(fb, audio, 0, lut, state)
        assert state["julia_mode"] is False
        audio.beat = True
        render_fractal(fb, audio, 1, lut, state)
        assert state["julia_mode"] is True

    def test_fractal_handles_resize(self, audio):
        from termvj import render_fractal
        lut = np.zeros((256, 3), dtype=np.uint8)
        lut[:, 0] = np.arange(256)
        state = {}
        # First size
        fb1 = np.zeros((20, 40, 3), dtype=np.uint8)
        render_fractal(fb1, audio, 0, lut, state)
        # Different size — should not crash
        fb2 = np.zeros((30, 60, 3), dtype=np.uint8)
        render_fractal(fb2, audio, 1, lut, state)
        assert fb2.sum() > 0


# ── Algorithm Visualization Modes ────────────────────────────

class TestAlgorithmVisualizations:
    """Test the 3 new diagnostic visualization modes."""

    @pytest.fixture
    def audio(self):
        class MockAudio:
            mel_bands = np.zeros(40)
            spectrum = np.zeros(256)
            centroid = 0.5
            spread = 0.3
            flux = 0.1
            flatness = 0.2
            rolloff = 0.6
            slope = 0.1
            kurtosis = 0.3
            beat = False
            onset = False
            onset_strength = 0.0
            bpm = 120.0
            rms = 0.3
            pitch_hz = 440.0
            pitch_confidence = 0.8
            waveform = np.zeros(512)
            is_quiet = False
            mfcc = np.zeros(13)
            pitch_midi = 69.0
            band_sub_bass = 0.6
            band_kick = 0.8
            band_snare = 0.3
            band_mid = 0.5
            band_presence = 0.4
            band_high = 0.7
            band_air = 0.2
            kick_pulse = 0.9
            snare_pulse = 0.4
            hat_pulse = 0.6
            beat_phase = 0.25
            centroid_velocity = 0.05
            low_flux = 0.3
            high_flux = 0.5
            tension = 0.4
            mfcc_distance = 2.5
            timbre_hue = 0.6
            timbre_scale = 0.4
            timbre_bright = 0.5
            osc_half = 0.7
            osc_beat = -0.3
            osc_double = 0.9
            osc_triplet = -0.5
            osc_sixteenth = 0.1
        return MockAudio()

    @pytest.fixture
    def lut(self):
        lut = np.zeros((256, 3), dtype=np.uint8)
        for i in range(256):
            lut[i] = [i, 255 - i, (i * 3) % 256]
        return lut

    def test_band_pulses_runs(self, audio, lut):
        from termvj import render_band_pulses
        fb = np.zeros((60, 120, 3), dtype=np.uint8)
        state = {}
        render_band_pulses(fb, audio, 0, lut, state)
        assert fb.sum() > 0
        assert 'overlays' in state
        assert len(state['overlays']) > 5

    def test_band_pulses_shows_kick(self, audio, lut):
        from termvj import render_band_pulses
        fb = np.zeros((60, 120, 3), dtype=np.uint8)
        state = {}
        audio.kick_pulse = 1.0
        render_band_pulses(fb, audio, 0, lut, state)
        # Should have red-ish pixels from kick circle
        assert fb[:, :, 0].max() > 200

    def test_oscillators_runs(self, audio, lut):
        from termvj import render_oscillators
        fb = np.zeros((60, 120, 3), dtype=np.uint8)
        state = {}
        for frame in range(3):
            render_oscillators(fb, audio, frame, lut, state)
        assert fb.sum() > 0
        assert 'osc_history' in state
        assert state['osc_history'].shape == (5, 120)

    def test_oscillators_history_shifts(self, audio, lut):
        from termvj import render_oscillators
        fb = np.zeros((60, 120, 3), dtype=np.uint8)
        state = {}
        audio.osc_beat = 0.8
        render_oscillators(fb, audio, 0, lut, state)
        assert state['osc_history'][1, -1] == 0.8

    def test_tension_timbre_runs(self, audio, lut):
        from termvj import render_tension_timbre
        fb = np.zeros((80, 120, 3), dtype=np.uint8)
        state = {}
        for frame in range(3):
            render_tension_timbre(fb, audio, frame, lut, state)
        assert fb.sum() > 0
        assert 'tension_hist' in state

    def test_tension_timbre_shows_tension(self, audio, lut):
        from termvj import render_tension_timbre
        fb = np.zeros((80, 120, 3), dtype=np.uint8)
        state = {}
        audio.tension = 0.9
        render_tension_timbre(fb, audio, 0, lut, state)
        # High tension should produce warm-colored bar pixels
        assert fb[:, :, 0].max() > 150


# ── ISF Converter (parsing only, no SDK) ─────────────────────

class TestISFConverter:
    def test_parse_isf_with_header(self, tmp_path):
        from isf_converter import parse_isf_file
        content = '''/*{
    "DESCRIPTION": "A test shader",
    "INPUTS": [
        {"NAME": "rate", "TYPE": "float", "DEFAULT": 1.0}
    ]
}*/

void main() {
    gl_FragColor = vec4(1.0);
}'''
        path = tmp_path / "test.fs"
        path.write_text(content)
        header, glsl = parse_isf_file(str(path))
        assert header["DESCRIPTION"] == "A test shader"
        assert len(header["INPUTS"]) == 1
        assert "gl_FragColor" in glsl

    def test_parse_isf_without_header(self, tmp_path):
        from isf_converter import parse_isf_file
        content = "void main() { gl_FragColor = vec4(0.0); }"
        path = tmp_path / "bare.fs"
        path.write_text(content)
        header, glsl = parse_isf_file(str(path))
        assert header == {}
        assert "gl_FragColor" in glsl

    def test_build_conversion_prompt(self):
        from isf_converter import build_conversion_prompt
        header = {
            "DESCRIPTION": "Cool shader",
            "INPUTS": [
                {"NAME": "speed", "TYPE": "float", "DEFAULT": 1.0}
            ]
        }
        glsl = "void main() { gl_FragColor = vec4(1.0); }"
        prompt = build_conversion_prompt(header, glsl, "make it red")
        assert "Cool shader" in prompt
        assert "speed" in prompt
        assert "make it red" in prompt
        assert "gl_FragColor" in prompt


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
