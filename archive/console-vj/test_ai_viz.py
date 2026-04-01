"""Tests for ai_viz module — code extraction, loading, safety, debug panel."""

import math
import os
import numpy as np
import pytest

from ai_viz import (
    extract_code,
    load_render_fn,
    make_safe_namespace,
    take_screenshot,
    DebugPanel,
    SAFE_BUILTINS,
    HAS_PIL,
)

if HAS_PIL:
    from PIL import Image


# ── extract_code ─────────────────────────────────────────────

class TestExtractCode:
    def test_python_fenced(self):
        text = "Here is the code:\n```python\ndef render_ai(fb, audio, frame, lut, state):\n    pass\n```\nDone."
        assert "def render_ai" in extract_code(text)
        assert "```" not in extract_code(text)

    def test_generic_fenced(self):
        text = "```\ndef render_ai(fb, audio, frame, lut, state):\n    fb[:] = 0\n```"
        code = extract_code(text)
        assert "def render_ai" in code
        assert "fb[:] = 0" in code

    def test_no_fence(self):
        text = "def render_ai(fb, audio, frame, lut, state):\n    pass"
        assert extract_code(text) == text.strip()

    def test_multiple_blocks_takes_first(self):
        text = "```python\ndef render_ai(fb, a, f, l, s):\n    pass\n```\nAlso:\n```python\nprint('hi')\n```"
        code = extract_code(text)
        assert "render_ai" in code

    def test_strips_whitespace(self):
        text = "```python\n\n  def render_ai(fb, a, f, l, s):\n      pass\n\n```"
        code = extract_code(text)
        assert code.startswith("def render_ai")


# ── load_render_fn ───────────────────────────────────────────

class TestLoadRenderFn:
    def test_valid_function(self):
        code = "def render_ai(fb, audio, frame, lut, state):\n    fb[:] = 0"
        fn, err = load_render_fn(code)
        assert fn is not None
        assert err is None
        assert callable(fn)

    def test_function_runs(self):
        code = (
            "def render_ai(fb, audio, frame, lut, state):\n"
            "    h, w, _ = fb.shape\n"
            "    fb[:] = 128\n"
        )
        fn, err = load_render_fn(code)
        assert fn is not None
        fb = np.zeros((10, 20, 3), dtype=np.uint8)
        fn(fb, None, 0, None, {})
        assert np.all(fb == 128)

    def test_numpy_available(self):
        code = (
            "def render_ai(fb, audio, frame, lut, state):\n"
            "    h, w, _ = fb.shape\n"
            "    vals = np.linspace(0, 1, w)\n"
            "    fb[:, :, 0] = (vals * 255).astype(np.uint8)\n"
        )
        fn, err = load_render_fn(code)
        assert fn is not None
        fb = np.zeros((4, 10, 3), dtype=np.uint8)
        fn(fb, None, 0, None, {})
        assert fb[0, -1, 0] > 200  # last column should be ~255

    def test_math_available(self):
        code = (
            "def render_ai(fb, audio, frame, lut, state):\n"
            "    val = int(math.pi * 10)\n"
            "    fb[:] = val\n"
        )
        fn, err = load_render_fn(code)
        assert fn is not None
        fb = np.zeros((2, 2, 3), dtype=np.uint8)
        fn(fb, None, 0, None, {})
        assert fb[0, 0, 0] == 31  # int(3.14159 * 10)

    def test_no_render_ai_function(self):
        code = "def something_else():\n    pass"
        fn, err = load_render_fn(code)
        assert fn is None
        assert "render_ai" in err

    def test_syntax_error(self):
        code = "def render_ai(:\n    broken syntax here!!"
        fn, err = load_render_fn(code)
        assert fn is None
        assert "exec error" in err

    def test_state_persistence(self):
        code = (
            "def render_ai(fb, audio, frame, lut, state):\n"
            "    if 'count' not in state:\n"
            "        state['count'] = 0\n"
            "    state['count'] += 1\n"
            "    fb[:] = state['count']\n"
        )
        fn, _ = load_render_fn(code)
        fb = np.zeros((2, 2, 3), dtype=np.uint8)
        state = {}
        fn(fb, None, 0, None, state)
        assert state["count"] == 1
        assert fb[0, 0, 0] == 1
        fn(fb, None, 1, None, state)
        assert state["count"] == 2
        assert fb[0, 0, 0] == 2

    def test_lut_palette_mapping(self):
        code = (
            "def render_ai(fb, audio, frame, lut, state):\n"
            "    h, w, _ = fb.shape\n"
            "    vals = np.linspace(0, 1, h * w).reshape(h, w)\n"
            "    indices = (vals * 255).astype(int)\n"
            "    fb[:] = lut[indices]\n"
        )
        fn, _ = load_render_fn(code)
        fb = np.zeros((4, 8, 3), dtype=np.uint8)
        lut = np.zeros((256, 3), dtype=np.uint8)
        lut[:, 0] = np.arange(256)  # red gradient
        fn(fb, None, 0, lut, {})
        assert fb[0, 0, 0] == 0
        assert fb[-1, -1, 0] == 255


# ── Safety / sandboxing ──────────────────────────────────────

class TestSafety:
    def test_no_os_access(self):
        code = "def render_ai(fb, a, f, l, s):\n    import os\n    os.system('echo pwned')"
        fn, err = load_render_fn(code)
        # Either fails at exec time or at runtime
        if fn is not None:
            with pytest.raises(Exception):
                fn(np.zeros((2, 2, 3), dtype=np.uint8), None, 0, None, {})

    def test_no_open(self):
        code = "def render_ai(fb, a, f, l, s):\n    f = open('/etc/passwd')"
        fn, err = load_render_fn(code)
        if fn is not None:
            with pytest.raises(Exception):
                fn(np.zeros((2, 2, 3), dtype=np.uint8), None, 0, None, {})

    def test_no_subprocess(self):
        code = "def render_ai(fb, a, f, l, s):\n    import subprocess\n    subprocess.run(['ls'])"
        fn, err = load_render_fn(code)
        if fn is not None:
            with pytest.raises(Exception):
                fn(np.zeros((2, 2, 3), dtype=np.uint8), None, 0, None, {})

    def test_safe_builtins_available(self):
        ns = make_safe_namespace()
        builtins = ns["__builtins__"]
        assert builtins["range"] is range
        assert builtins["len"] is len
        assert builtins["min"] is min
        assert builtins["max"] is max
        assert builtins["int"] is int
        assert builtins["float"] is float
        assert builtins["True"] is True
        assert builtins["False"] is False
        assert builtins["None"] is None

    def test_print_is_noop(self):
        ns = make_safe_namespace()
        # print should do nothing, not crash
        ns["__builtins__"]["print"]("should be silent")


# ── DebugPanel ───────────────────────────────────────────────

class TestDebugPanel:
    def test_log_and_lines(self):
        panel = DebugPanel(max_lines=5)
        panel.log("Hello")
        assert len(panel.lines) == 1
        assert "Hello" in panel.lines[0][0]

    def test_max_lines(self):
        panel = DebugPanel(max_lines=3)
        for i in range(10):
            panel.log(f"Line {i}")
        assert len(panel.lines) == 3
        assert "Line 9" in panel.lines[-1][0]

    def test_multiline_split(self):
        panel = DebugPanel()
        panel.log("line1\nline2\nline3")
        assert len(panel.lines) == 3

    def test_color_stored(self):
        panel = DebugPanel()
        panel.log("test", (255, 0, 0))
        assert panel.lines[0][1] == (255, 0, 0)

    def test_render_empty(self):
        panel = DebugPanel()
        assert panel.render(80, 24) == ""

    def test_render_non_empty(self):
        panel = DebugPanel()
        panel.log("test message")
        output = panel.render(120, 40)
        assert "AI Debug" in output
        assert "test message" in output
        assert "\x1b[" in output  # has ANSI codes

    def test_truncates_long_text(self):
        panel = DebugPanel()
        panel.log("x" * 200)
        # Should be truncated to 60 chars in stored line
        assert len(panel.lines[0][0]) <= 70  # timestamp + 60 chars


# ── Screenshot ───────────────────────────────────────────────

class TestScreenshot:
    @pytest.mark.skipif(not HAS_PIL, reason="Pillow not installed")
    def test_take_screenshot(self, tmp_path):
        fb = np.zeros((10, 20, 3), dtype=np.uint8)
        fb[:, :, 1] = 128  # green
        path = str(tmp_path / "test.png")
        result = take_screenshot(fb, path=path)
        assert result == path
        assert os.path.exists(path)
        # Verify it's a valid image
        img = Image.open(path)
        assert img.size == (20, 10)

    @pytest.mark.skipif(not HAS_PIL, reason="Pillow not installed")
    def test_screenshot_preserves_pixels(self, tmp_path):
        fb = np.zeros((4, 4, 3), dtype=np.uint8)
        fb[0, 0] = (255, 0, 0)
        fb[3, 3] = (0, 0, 255)
        path = str(tmp_path / "test.png")
        take_screenshot(fb, path=path)
        img = np.array(Image.open(path))
        assert tuple(img[0, 0]) == (255, 0, 0)
        assert tuple(img[3, 3]) == (0, 0, 255)


# ── Integration: end-to-end extract+load+run ─────────────────

class TestIntegration:
    def test_extract_and_run_plasma(self):
        """Simulate what happens when Copilot returns a plasma visualization."""
        response = '''Here's a plasma visualization:

```python
def render_ai(fb, audio, frame, lut, state):
    h, w, _ = fb.shape
    if 'xx' not in state or state.get('_dims') != (h, w):
        y_coords = np.linspace(-1, 1, h)
        x_coords = np.linspace(-1, 1, w)
        state['xx'], state['yy'] = np.meshgrid(x_coords, y_coords)
        state['_dims'] = (h, w)
    xx, yy = state['xx'], state['yy']
    t = frame * 0.03
    v = np.sin(xx * 3.14 * 2 + t) + np.sin(yy * 1.618 * 3 + t * 0.7)
    v = (v / 2 + 1) * 0.5
    indices = (np.clip(v, 0, 1) * 255).astype(int)
    fb[:] = lut[indices]
```

This creates a smooth plasma effect.'''

        code = extract_code(response)
        fn, err = load_render_fn(code)
        assert fn is not None, f"Failed: {err}"

        # Create test data
        fb = np.zeros((20, 40, 3), dtype=np.uint8)
        lut = np.zeros((256, 3), dtype=np.uint8)
        lut[:, 0] = np.arange(256)
        state = {}

        # Run for multiple frames — should not crash
        for frame in range(10):
            fn(fb, None, frame, lut, state)

        # Should have written non-zero pixels
        assert fb.sum() > 0
        # State should be populated
        assert 'xx' in state
        assert '_dims' in state

    def test_extract_and_run_with_audio(self):
        """Test a visualization that uses audio features."""
        response = '''```python
def render_ai(fb, audio, frame, lut, state):
    h, w, _ = fb.shape
    if audio.beat:
        state['flash'] = 1.0
    flash = state.get('flash', 0.0)
    state['flash'] = flash * 0.9
    brightness = int(flash * 255 + audio.rms * 100)
    fb[:] = min(brightness, 255)
```'''

        code = extract_code(response)
        fn, err = load_render_fn(code)
        assert fn is not None, f"Failed: {err}"

        # Create mock audio
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

        fb = np.zeros((10, 20, 3), dtype=np.uint8)
        audio = MockAudio()
        state = {}

        # Normal frame
        fn(fb, audio, 0, None, state)
        base_val = fb[0, 0, 0]

        # Beat frame — should be brighter
        audio.beat = True
        fn(fb, audio, 1, None, state)
        beat_val = fb[0, 0, 0]
        assert beat_val > base_val

        # After beat, should decay
        audio.beat = False
        for i in range(5):
            fn(fb, audio, 2 + i, None, state)
        assert state['flash'] < 0.6  # should have decayed from 1.0


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
