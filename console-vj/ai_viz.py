"""
ai_viz — AI Visualization Module for TermVJ
=============================================
Generates visualization render functions from natural language prompts
using the GitHub Copilot SDK, with screenshot feedback for iterative refinement.
"""

import asyncio
import json
import math
import os
import threading
import time
from collections import deque
from dataclasses import dataclass, field

import numpy as np

try:
    from PIL import Image
    HAS_PIL = True
except ImportError:
    HAS_PIL = False

try:
    from copilot import CopilotClient, PermissionHandler
    HAS_COPILOT = True
except ImportError:
    HAS_COPILOT = False


# ── Error Journal — persistent log of all AI errors and fixes ──

ERROR_JOURNAL_PATH = os.path.expanduser("~/.termvj_error_journal.jsonl")


class ErrorJournal:
    """Append-only JSONL log of every AI generation attempt.

    Each entry records the prompt, generated code, error (if any),
    whether the fix succeeded, and the attempt number. This log is
    used to identify recurring failure patterns and improve the
    system prompt over time.
    """

    def __init__(self, path: str = ERROR_JOURNAL_PATH):
        self.path = path

    def log(self, *, prompt: str, code: str, error: str | None,
            attempt: int, fixed: bool, fix_code: str | None = None):
        entry = {
            "ts": time.strftime("%Y-%m-%dT%H:%M:%S"),
            "prompt": prompt[:200],
            "code_len": len(code) if code else 0,
            "code_head": (code or "")[:500],
            "error": error,
            "attempt": attempt,
            "fixed": fixed,
        }
        if fix_code:
            entry["fix_head"] = fix_code[:500]
        try:
            with open(self.path, "a") as f:
                f.write(json.dumps(entry) + "\n")
        except OSError:
            pass

    def read_recent(self, n: int = 20) -> list[dict]:
        """Read the last N journal entries."""
        try:
            with open(self.path) as f:
                lines = f.readlines()
            return [json.loads(l) for l in lines[-n:]]
        except (OSError, json.JSONDecodeError):
            return []

    def common_errors(self, n: int = 10) -> str:
        """Summarize recurring error patterns for prompt improvement."""
        entries = self.read_recent(100)
        errors = [e["error"] for e in entries if e.get("error")]
        if not errors:
            return ""
        # Count error prefixes (first 60 chars) to find patterns
        from collections import Counter
        counts = Counter(e[:60] for e in errors)
        top = counts.most_common(n)
        lines = [f"- {err} (×{count})" for err, count in top]
        return "Common errors from past generations:\n" + "\n".join(lines)


# ── Safe namespace for exec()'d code ────────────────────────

SAFE_BUILTINS = {
    "range": range, "len": len, "int": int, "float": float,
    "min": min, "max": max, "abs": abs, "round": round,
    "True": True, "False": False, "None": None,
    "enumerate": enumerate, "zip": zip, "bool": bool,
    "list": list, "tuple": tuple, "dict": dict, "set": set,
    "str": str, "print": lambda *a: None,
    "isinstance": isinstance, "type": type,
}


def make_safe_namespace():
    """Return a restricted globals dict for exec()."""
    return {"np": np, "math": math, "__builtins__": SAFE_BUILTINS}


# ── System Prompt ────────────────────────────────────────────

SYSTEM_PROMPT = """You are a visualization code generator for TermVJ — a truecolor terminal-based \
audio-reactive VJ tool rendering at ~200×100 pixels via half-block characters at 30fps.

## Output Format
Generate a SINGLE Python function. Return ONLY code in a ```python block. No explanation.

```python
def render_ai(fb, audio, frame, lut, state):
    h, w, _ = fb.shape
    # your code here — write pixels to fb
```

## Parameters

**fb** — np.ndarray (h, w, 3) uint8, the pixel framebuffer. Write directly: `fb[:] = ...`
  - Typical size: ~100 tall × 200 wide (but varies with terminal size)

**audio** — object with normalized 0-1 audio features:
  .mel_bands  — np.ndarray[40] perceptual frequency bands (0=sub-bass, 39=air)
  .spectrum   — np.ndarray[256] log-spaced FFT magnitudes
  .centroid   — float, spectral brightness (low=dark/bassy, high=bright/trebly)
  .spread     — float, spectral width/complexity
  .flux       — float, how fast the spectrum is changing (high on transients)
  .flatness   — float, 0=tonal/melodic, 1=noisy/percussive
  .rolloff    — float, frequency below which most energy sits
  .slope      — float, spectral tilt
  .kurtosis   — float, spectral peakedness
  .beat       — bool, True on detected beat (one frame only)
  .onset      — bool, True on detected onset/transient
  .onset_strength — float, onset intensity 0-1
  .bpm        — float, estimated tempo (e.g. 120.0)
  .rms        — float, overall loudness 0-1
  .pitch_hz   — float, detected fundamental frequency
  .pitch_confidence — float, 0-1 how reliable the pitch is
  .waveform   — np.ndarray[512] raw audio samples (-1 to 1)
  ## EDM-optimized features (use these for best results!):
  # Perceptual energy bands (7 bands, all 0-1):
  .band_sub_bass — 20-60Hz (808 rumble, sub drops)
  .band_kick     — 60-250Hz (kick drum body)
  .band_snare    — 250-500Hz (snare body, bass guitar)
  .band_mid      — 500-2kHz (vocals, melody, leads)
  .band_presence — 2-4kHz (attack transients, presence)
  .band_high     — 4-12kHz (hi-hats, cymbals, air)
  .band_air      — 12-20kHz (brilliance, shimmer)
  # Classified onset pulses (0-1, exponential decay envelopes):
  .kick_pulse    — fires on kick, decays slowly (heavy impact)
  .snare_pulse   — fires on snare, decays medium (accent)
  .hat_pulse     — fires on hi-hat, decays fast (sparkle)
  # Beat phase (0-1 cycling every beat, phase-locked to BPM):
  .beat_phase    — use for all periodic motion: sin(beat_phase * 2π)
  # Centroid dynamics:
  .centroid_velocity — rate of brightness change (+ = opening, - = dropping)
  # Spectral flux (split by frequency):
  .low_flux      — bass flux (kicks re-entering, drops)
  .high_flux     — treble flux (cymbals, filter sweeps)
  .tension       — 0-1, builds during calm sections, dumps on drops
  # Timbral features (MFCC-derived, 0-1):
  .mfcc_distance — how different current timbre is from average
  .timbre_hue    — spectral balance (use for color rotation speed)
  .timbre_scale  — spectral shape (use for element size)
  .timbre_bright — spectral detail (use for background brightness)
  # Phase-locked oscillators (sine waves at BPM harmonics, -1 to 1):
  .osc_half      — half-time (slow sway, color cycle)
  .osc_beat      — beat rate (global pulse, breathing)
  .osc_double    — eighth notes (rapid flicker)
  .osc_triplet   — triplet feel (polyrhythmic drift)
  .osc_sixteenth — sixteenth notes (texture scroll, shimmer)

**frame** — int, frame counter (increments each frame, ~30/sec)
**lut** — np.ndarray (256, 3) uint8, color palette. Use: `fb[:] = lut[indices]`
**state** — dict, persists between frames. ALWAYS init: `if 'key' not in state: ...`

## Critical Rules

1. Use ONLY `np` (numpy) and `math` — no other imports available
2. NEVER loop over individual pixels — use vectorized numpy operations
3. Always guard state init: `if 'buf' not in state: state['buf'] = np.zeros((h,w))`
4. Handle resize: `if state.get('h') != h: state.clear(); state['h'] = h`
5. Return value is ignored — write to fb directly

## Proven Patterns (from working visualizations)

### Coordinate grids (do once, cache in state)
```python
if 'xx' not in state or state.get('_dims') != (h, w):
    y_coords = np.linspace(-1, 1, h)
    x_coords = np.linspace(-1, 1, w)
    state['xx'], state['yy'] = np.meshgrid(x_coords, y_coords)
    state['_dims'] = (h, w)
xx, yy = state['xx'], state['yy']
```

### Palette coloring (THE standard pattern)
```python
values = np.clip(my_field, 0, 1)
indices = (values * 255).astype(int)
fb[:] = lut[indices]
```

### Sine plasma (smooth, never repeats)
```python
t = frame * 0.03
v = np.sin(xx * 3.14 * 2 + t) + np.sin(yy * 1.618 * 3 + t * 0.7)
v += np.sin(np.sqrt(xx**2 + yy**2) * 2.718 + t * 0.5)
v = (v / 3 + 1) * 0.5  # normalize to 0-1
```

### Distance field (for radial effects)
```python
dist = np.sqrt(xx**2 + yy**2)
angle = np.arctan2(yy, xx)
```

### Beat-triggered state changes
```python
if audio.beat:
    state['kick'] = 1.0
state['kick'] = state.get('kick', 0) * 0.92  # decay smoothly
```

### Persistent trail/glow (frame blending)
```python
if 'trail' not in state or state['trail'].shape != (h, w):
    state['trail'] = np.zeros((h, w), dtype=np.float64)
state['trail'] *= 0.9
state['trail'] = np.maximum(state['trail'], new_values)
```

## Audio Feature → Visual Parameter Mapping Guide

| Audio Feature | Best Visual Use | How to Apply |
|---|---|---|
| mel_bands[:10] | Bass energy, kick pulse | Scale, brightness, heat injection |
| mel_bands[15:25] | Mid/vocal energy | Shape complexity, mid-layer effects |
| mel_bands[30:] | High freq, hi-hats | Sparkle, fine detail, shimmer speed |
| centroid | Color temperature | Shift palette index: `(field + centroid*0.3) % 1` |
| spread | Visual complexity | Multiply spatial frequency or layer count |
| flux | Animation speed | Scale time or trigger transitions |
| flatness | Chaos vs order | Mix between smooth geometry and noise |
| beat | Structural events | Phase jumps, bursts, flashes, spawns |
| onset | Accent events | Smaller bursts, ripple spawns |
| rms | Overall brightness | Multiply final output |
| bpm | Animation tempo | `phase = frame * bpm / (60 * fps)` for beat-locked motion |
| waveform | Oscilloscope shapes | Plot as line or use for displacement |

## Style Guidelines
- Make it visually RICH — use the full palette range, not just one color
- SMOOTH motion — use frame persistence, EMA smoothing, spring physics
- REACT to music — every visual parameter should be driven by at least one audio feature
- QUIET = STILL — when there's no music (audio.rms ≈ 0), the visualization should nearly freeze.
  Use `activity = max(audio.rms, 0.02)` and multiply all autonomous motion by it.
  Only a tiny drift should remain so it looks alive but sleeping.
- NEVER BORING — use irrational frequency ratios (1.618, 3.14159, 2.71828)
- BEAT AWARENESS — structural changes on beat, accent on onset, continuous motion between
- Fill the screen — don't leave large black areas unless intentional"""


# ── Debug Panel ──────────────────────────────────────────────

class DebugPanel:
    """Scrollable debug log rendered at bottom-right of terminal."""

    def __init__(self, max_lines=12):
        self.lines: deque = deque(maxlen=max_lines)
        self.max_lines = max_lines

    def log(self, text, color=(180, 180, 180)):
        ts = time.strftime("%H:%M:%S")
        for line in str(text).split("\n"):
            if line.strip():
                self.lines.append((f"{ts} {line[:60]}", color))

    def render(self, term_width, term_height):
        """Return ANSI escape string for the debug panel."""
        if not self.lines:
            return ""
        panel_w = min(65, term_width // 2)
        panel_h = min(len(self.lines) + 2, self.max_lines + 2)
        x0 = term_width - panel_w
        y0 = max(0, term_height - 2 - panel_h)
        parts = []
        header = " AI Debug "
        bar = "─" * (panel_w - len(header) - 2)
        parts.append(
            f"\x1b[{y0+1};{x0+1}H"
            f"\x1b[38;2;100;200;255m\x1b[48;2;10;10;30m"
            f"┌{header}{bar}┐"
        )
        for i, (text, (r, g, b)) in enumerate(self.lines):
            row = y0 + 2 + i
            if row >= term_height - 1:
                break
            padded = text[:panel_w - 4].ljust(panel_w - 4)
            parts.append(
                f"\x1b[{row};{x0+1}H"
                f"\x1b[38;2;{r};{g};{b}m\x1b[48;2;10;10;30m"
                f"│ {padded} │"
            )
        foot_row = y0 + 2 + min(len(self.lines), panel_h - 2)
        if foot_row < term_height - 1:
            parts.append(
                f"\x1b[{foot_row};{x0+1}H"
                f"\x1b[38;2;100;200;255m\x1b[48;2;10;10;30m"
                f"└{'─' * (panel_w - 2)}┘\x1b[0m"
            )
        return "".join(parts)


# ── Code Extraction ──────────────────────────────────────────

def extract_code(text):
    """Extract Python code from a markdown-fenced response."""
    if "```python" in text:
        return text.split("```python")[1].split("```")[0].strip()
    if "```" in text:
        return text.split("```")[1].split("```")[0].strip()
    return text.strip()


def load_render_fn(code):
    """Compile and load a render_ai function from code string.

    Returns (fn, None) on success or (None, error_message) on failure.
    """
    ns = make_safe_namespace()
    try:
        exec(code, ns)
    except Exception as e:
        return None, f"exec error: {e}"
    fn = ns.get("render_ai")
    if fn is None or not callable(fn):
        return None, "no callable render_ai() found"
    return fn, None


def take_screenshot(fb, path="/tmp/termvj_screenshot.png"):
    """Save a framebuffer as PNG. Returns path on success, None on failure."""
    if not HAS_PIL:
        return None
    try:
        Image.fromarray(fb).save(path)
        return path
    except Exception:
        return None


# ── AI Visualization Manager ────────────────────────────────

class AIVizManager:
    """Manages AI-generated visualizations via Copilot SDK."""

    def __init__(self, debug_panel):
        self.debug = debug_panel
        self.client = None
        self.session = None
        self.render_fn = None
        self.iteration = 0
        self.generating = False
        self.error_msg = ""
        self.last_code = ""
        self.last_prompt = ""
        self.on_new_version = None  # callback(code, prompt, screenshot_path, description)
        self._cancelled = False
        self._journal = ErrorJournal()
        self._loop = None
        self._thread = None

    def _ensure_loop(self):
        if self._loop is None:
            self._loop = asyncio.new_event_loop()
            self._thread = threading.Thread(target=self._loop.run_forever, daemon=True)
            self._thread.start()

    def _run_async(self, coro):
        self._ensure_loop()
        return asyncio.run_coroutine_threadsafe(coro, self._loop)

    async def _start_client(self):
        if self.client is None:
            self.debug.log("Starting Copilot SDK...", (255, 200, 100))
            self.client = CopilotClient()
            await self.client.start()
            self.debug.log("Copilot SDK ready ✓", (100, 255, 100))

    async def _send_and_get_code(self, prompt, screenshot_path=None):
        """Send a prompt to the session, wait for response, return extracted code."""
        done = asyncio.Event()
        response_parts = []

        def on_event(event):
            if event.type.value == "assistant.message":
                response_parts.append(event.data.content)
                done.set()
            elif event.type.value == "session.idle":
                if not done.is_set():
                    done.set()

        # Subscribe and keep unsubscribe handle to clean up after
        unsubscribe = self.session.on(on_event)

        msg = {"prompt": prompt}
        if screenshot_path and os.path.exists(screenshot_path):
            msg["attachments"] = [{"type": "file", "path": screenshot_path}]
            self.debug.log("Attached screenshot 📷", (200, 200, 100))

        try:
            await self.session.send(msg)
            await asyncio.wait_for(done.wait(), timeout=90)
        finally:
            # Always unsubscribe to prevent listener buildup
            if callable(unsubscribe):
                unsubscribe()

        if response_parts:
            return extract_code(response_parts[-1])
        return None

    async def _generate(self, prompt, screenshot_path=None):
        """Generate a visualization, retrying until success or cancellation.

        Every attempt is logged to ~/.termvj_error_journal.jsonl.
        Past common errors are injected into the initial prompt.
        """
        self.generating = True
        self._cancelled = False
        self.error_msg = ""
        try:
            await self._start_client()

            if self.session is None:
                self.debug.log("Creating session...", (200, 200, 100))
                self.session = await self.client.create_session({
                    "model": "claude-sonnet-4.5",
                    "system_message": {"content": SYSTEM_PROMPT},
                    "on_permission_request": PermissionHandler.approve_all,
                })
                self.debug.log("Session created ✓", (100, 255, 100))

            self.debug.log(f"Prompt: {prompt[:50]}...", (100, 200, 255))

            # Inject common past errors so the AI avoids them
            common = self._journal.common_errors(5)
            initial_prompt = prompt
            if common:
                initial_prompt += (
                    f"\n\n## Avoid these known pitfalls:\n{common}\n"
                    f"Make sure your code does NOT repeat these mistakes."
                )

            code = await self._send_and_get_code(initial_prompt, screenshot_path)
            if not code:
                self.debug.log("No response received", (255, 100, 100))
                return

            error_history = []
            attempt = 0
            while not self._cancelled:
                fn, err = load_render_fn(code)
                if fn:
                    runtime_err = self._test_run(fn)
                    if runtime_err is None:
                        self.render_fn = fn
                        self.last_code = code
                        self.last_prompt = prompt
                        self.iteration += 1
                        msg = f"✅ v{self.iteration}"
                        if attempt > 0:
                            msg += f" (fixed after {attempt})"
                        self.debug.log(msg, (100, 255, 100))
                        self._journal.log(
                            prompt=prompt, code=code, error=None,
                            attempt=attempt, fixed=True)
                        if self.on_new_version:
                            desc = prompt[:60] if prompt else f"iteration {self.iteration}"
                            self.on_new_version(code, prompt, screenshot_path, desc)
                        return
                    else:
                        err = f"runtime error: {runtime_err}"

                attempt += 1
                error_history.append(f"Attempt {attempt}: {err}")
                self._journal.log(
                    prompt=prompt, code=code, error=err,
                    attempt=attempt, fixed=False)
                self.debug.log(
                    f"🔧 Fix {attempt}: {err[:50]}",
                    (255, 200, 100))

                history_block = "\n".join(error_history[-5:])
                fix_prompt = (
                    f"The code has an error. Error history:\n\n"
                    f"```\n{history_block}\n```\n\n"
                    f"Latest error:\n```\n{err}\n```\n\n"
                    f"Broken code:\n```python\n{code}\n```\n\n"
                    f"Fix it. Return the COMPLETE corrected function.\n"
                    f"Rules: named `render_ai`, only `np`+`math`, "
                    f"no pixel loops, guard state init, write to fb directly."
                )
                if attempt > 3:
                    fix_prompt += (
                        f"\n{attempt} failures. SIMPLIFY. Start with a basic "
                        f"sine plasma that works, then add features."
                    )

                code = await self._send_and_get_code(fix_prompt)
                if not code:
                    self.debug.log("No fix, fresh start...", (255, 150, 50))
                    await asyncio.sleep(1)
                    code = await self._send_and_get_code(
                        f"All {attempt} attempts failed. Start completely fresh.\n\n"
                        f"Original request: {prompt}\n\n"
                        f"Generate a SIMPLE, WORKING render_ai() function. "
                        f"Minimal — just make it compile and run.",
                        screenshot_path
                    )
                    if not code:
                        self.debug.log("No response, giving up", (255, 100, 100))
                        return

            if self._cancelled:
                self.debug.log("Cancelled by user", (255, 200, 100))

        except asyncio.TimeoutError:
            self.debug.log("Timeout waiting for Copilot", (255, 100, 100))
            self.error_msg = "Timeout"
        except Exception as e:
            self.debug.log(f"Error: {e}", (255, 100, 100))
            self.error_msg = str(e)[:50]
        finally:
            self.generating = False

    def _test_run(self, fn):
        """Test-run a render function with dummy data. Returns error string or None."""
        try:
            fb = np.zeros((20, 40, 3), dtype=np.uint8)
            lut = np.zeros((256, 3), dtype=np.uint8)
            lut[:, 0] = np.arange(256)

            class _Audio:
                mel_bands = np.zeros(40)
                spectrum = np.zeros(256)
                centroid = spread = rolloff = flatness = flux = 0.3
                slope = kurtosis = 0.2
                beat = onset = False
                onset_strength = bpm = rms = 0.0
                pitch_hz = pitch_confidence = 0.0
                waveform = np.zeros(512)
                # New algorithm features
                band_sub_bass = band_kick = band_snare = 0.0
                band_mid = band_presence = band_high = band_air = 0.0
                kick_pulse = snare_pulse = hat_pulse = 0.0
                beat_phase = 0.0
                centroid_velocity = 0.0
                low_flux = high_flux = tension = 0.0
                mfcc_distance = timbre_hue = timbre_scale = timbre_bright = 0.0
                osc_half = osc_beat = osc_double = osc_triplet = osc_sixteenth = 0.0

            state = {}
            for frame in range(3):
                fn(fb, _Audio(), frame, lut, state)
            return None
        except Exception as e:
            return str(e)

    def report_runtime_error(self, error_str):
        """Called by the main loop when a running render_ai crashes.
        Triggers auto-fix via Copilot in background."""
        self.debug.log(f"🔧 Runtime crash: {error_str[:40]}", (255, 150, 50))
        self._run_async(self._auto_fix_runtime(error_str))

    async def _auto_fix_runtime(self, error_str):
        """Send the runtime error back to Copilot for auto-fix, retrying until success."""
        if self.session is None or self.generating:
            return
        self.generating = True
        self._cancelled = False
        error_history = [f"Runtime crash: {error_str}"]
        attempt = 0
        try:
            while not self._cancelled:
                attempt += 1
                self.debug.log(f"Auto-fixing (attempt {attempt})...", (255, 200, 100))

                history_block = "\n".join(error_history[-5:])
                fix_prompt = (
                    f"The render_ai function crashed at runtime.\n\n"
                    f"Error history:\n```\n{history_block}\n```\n\n"
                )
                if self.last_code:
                    fix_prompt += f"Current code:\n```python\n{self.last_code}\n```\n\n"
                fix_prompt += (
                    f"Fix the code and return the COMPLETE corrected render_ai function. "
                    f"Use ONLY np and math. No pixel loops. Guard all state init."
                )
                if attempt > 3:
                    fix_prompt += " Simplify your approach — make it basic but working."

                code = await self._send_and_get_code(fix_prompt)
                if not code:
                    self.debug.log("No response, retrying...", (255, 150, 50))
                    await asyncio.sleep(1)
                    continue

                fn, err = load_render_fn(code)
                if fn:
                    runtime_err = self._test_run(fn)
                    if runtime_err is None:
                        self.render_fn = fn
                        self.last_code = code
                        self.last_prompt = "auto-fix"
                        self.iteration += 1
                        self.debug.log(f"✅ Auto-fixed → v{self.iteration}", (100, 255, 100))
                        self._journal.log(
                            prompt="auto-fix", code=code, error=None,
                            attempt=attempt, fixed=True, fix_code=code)
                        if self.on_new_version:
                            self.on_new_version(code, "auto-fix", None, "auto-fix")
                        return
                    else:
                        err = f"runtime error: {runtime_err}"

                error_history.append(f"Attempt {attempt}: {err}")
                self._journal.log(
                    prompt="auto-fix", code=code, error=err,
                    attempt=attempt, fixed=False)
                self.debug.log(f"⚠ Fix failed: {err[:40]}", (255, 100, 100))

        except Exception as e:
            self.debug.log(f"Auto-fix error: {e}", (255, 100, 100))
        finally:
            self.generating = False

    def generate(self, prompt, screenshot_path=None):
        """Start generation in background (non-blocking)."""
        self._cancelled = False
        self._run_async(self._generate(prompt, screenshot_path))

    def cancel(self):
        """Cancel the current generation/fix loop."""
        self._cancelled = True
        self.debug.log("Cancelling...", (255, 200, 100))

    def screenshot(self, fb):
        """Save framebuffer as PNG, return path."""
        path = take_screenshot(fb)
        if path:
            self.debug.log("Screenshot saved", (100, 200, 100))
        else:
            self.debug.log("Screenshot failed (PIL?)", (255, 100, 100))
        return path
