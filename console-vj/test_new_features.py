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
