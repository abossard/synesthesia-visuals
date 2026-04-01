"""
isf_converter — Convert ISF (.fs) Shaders to Console Render Functions
=====================================================================
Uses the Copilot SDK to translate ISF/GLSL shaders into NumPy-based
render_ai() functions compatible with TermVJ's rendering pipeline.
"""

import asyncio
import json
import os
import re
import sys
import threading

try:
    from copilot import CopilotClient, PermissionHandler
    HAS_COPILOT = True
except ImportError:
    HAS_COPILOT = False

from ai_viz import extract_code, load_render_fn, SYSTEM_PROMPT


# ── ISF → Console Conversion System Prompt ───────────────────

ISF_CONVERSION_PROMPT = """You are a shader format converter. You translate ISF (Interactive Shader Format) \
GLSL fragment shaders into Python render functions for TermVJ — a terminal-based audio-reactive visualizer.

## Your Task
Given an ISF shader (JSON header + GLSL body), produce a Python `render_ai()` function that \
recreates the visual effect using NumPy operations on a pixel framebuffer.

## ISF → Console Uniform Mapping

| ISF Uniform | Console Equivalent |
|---|---|
| `TIME` | `frame * 0.033` (or use state for accumulated time) |
| `RENDERSIZE` | `(w, h)` from `fb.shape` |
| `isf_FragNormCoord` | `(xx+1)/2, (yy+1)/2` from meshgrid on [-1,1] |
| `gl_FragCoord` | pixel indices from meshgrid |
| `PASSINDEX` | Not available — flatten multipass into single pass |
| `FRAMEINDEX` | `frame` parameter |
| `sin/cos/sqrt/etc` | `np.sin/np.cos/np.sqrt` |
| `vec2/vec3/vec4` | numpy arrays or separate channels |
| `mix(a,b,t)` | `a * (1-t) + b * t` |
| `clamp(x,lo,hi)` | `np.clip(x, lo, hi)` |
| `smoothstep(e0,e1,x)` | custom: `t=np.clip((x-e0)/(e1-e0),0,1); t*t*(3-2*t)` |
| `fract(x)` | `x % 1.0` or `np.modf(x)[0]` |
| `mod(x,y)` | `x % y` |
| `dot(a,b)` | `np.sum(a*b, axis=-1)` or element-wise |
| `length(v)` | `np.sqrt(np.sum(v**2, axis=-1))` |
| `normalize(v)` | `v / np.sqrt(np.sum(v**2, axis=-1, keepdims=True))` |
| `texture2D(sampler, uv)` | Use state buffer or LUT lookup |

## ISF Audio → Console Audio Mapping

ISF shaders in this project often use custom float inputs for audio. Map them:

| ISF Input Name Pattern | Console Audio Feature |
|---|---|
| `bass`, `low_freq`, `sub` | `audio.mel_bands[:8].mean()` |
| `mid`, `mid_freq` | `audio.mel_bands[12:25].mean()` |
| `high`, `hi_freq`, `treble` | `audio.mel_bands[28:].mean()` |
| `level`, `volume`, `rms` | `audio.rms` |
| `beat`, `kick` | `audio.beat` (bool) |
| `onset`, `hit` | `audio.onset` (bool) |
| `bpm`, `tempo` | `audio.bpm` |
| `spectrum` | `audio.spectrum` (256 bins) |
| `centroid` | `audio.centroid` |
| `flux` | `audio.flux` |
| Any float slider 0-1 | Pick the most appropriate audio feature |

## Conversion Strategy

1. **Parse the ISF JSON header** to understand inputs and passes
2. **Identify the core algorithm** (plasma, fractal, particles, noise, etc.)
3. **Translate GLSL math to NumPy** — vectorized, no pixel loops
4. **Replace texture lookups** with numpy array operations or LUT
5. **Add audio reactivity** — map ISF float inputs to audio features
6. **Flatten multipass** — if the ISF has multiple passes, combine into one
7. **Use the palette LUT** for coloring: `fb[:] = lut[(values * 255).astype(int)]`

## Output Rules
""" + """
- Output ONLY a ```python block with `def render_ai(fb, audio, frame, lut, state):`
- Use ONLY `np` (numpy) and `math` — no other imports
- NEVER loop over individual pixels — vectorized numpy only
- Always guard state: `if 'key' not in state: state['key'] = ...`
- Handle resize: `if state.get('_dims') != (h, w): state.clear(); ...`
- Write pixels to fb directly: `fb[:] = lut[indices]`
- Make it FUN and PLAYFUL — terminal art should be joyful!
- Add a comment at the top describing the original ISF shader name
"""


def parse_isf_file(path: str) -> tuple[dict, str]:
    """Parse an ISF .fs file into (json_header, glsl_body).

    Returns ({}, body) if no JSON header found.
    """
    with open(path, "r") as f:
        content = f.read()

    # ISF JSON header is wrapped in /*{ ... }*/
    match = re.search(r'/\*\s*(\{.*?\})\s*\*/', content, re.DOTALL)
    if match:
        try:
            header = json.loads(match.group(1))
        except json.JSONDecodeError:
            header = {}
        glsl = content[match.end():].strip()
    else:
        header = {}
        glsl = content.strip()

    return header, glsl


def build_conversion_prompt(header: dict, glsl: str, extra_instructions: str = "") -> str:
    """Build the conversion prompt from parsed ISF data."""
    parts = ["Convert this ISF shader to a TermVJ render_ai() function.\n"]

    if header:
        parts.append("## ISF Header (JSON)\n```json")
        parts.append(json.dumps(header, indent=2))
        parts.append("```\n")

    parts.append("## GLSL Shader Code\n```glsl")
    parts.append(glsl[:8000])  # Cap length for token budget
    parts.append("```\n")

    if header.get("INPUTS"):
        parts.append("## Input Parameters to Map")
        for inp in header["INPUTS"]:
            name = inp.get("NAME", "?")
            itype = inp.get("TYPE", "?")
            default = inp.get("DEFAULT", "?")
            parts.append(f"- `{name}` ({itype}, default={default})")
        parts.append("")

    if header.get("DESCRIPTION"):
        parts.append(f"## Description\n{header['DESCRIPTION']}\n")

    if extra_instructions:
        parts.append(f"## Additional Instructions\n{extra_instructions}\n")

    parts.append(
        "Make it audio-reactive and visually exciting! "
        "Map the shader's parameters to audio features creatively."
    )

    return "\n".join(parts)


class ISFConverter:
    """Converts ISF shaders to console render functions via Copilot SDK."""

    def __init__(self):
        self.client = None
        self.session = None
        self._loop = None
        self._thread = None

    def _ensure_loop(self):
        if self._loop is None:
            self._loop = asyncio.new_event_loop()
            self._thread = threading.Thread(target=self._loop.run_forever, daemon=True)
            self._thread.start()

    async def _start_client(self):
        if self.client is None:
            self.client = CopilotClient()
            await self.client.start()

    async def _convert(self, isf_path: str, extra_instructions: str = "") -> tuple[str, str]:
        """Convert an ISF file. Returns (code, description) or raises."""
        await self._start_client()

        header, glsl = parse_isf_file(isf_path)
        prompt = build_conversion_prompt(header, glsl, extra_instructions)
        desc = header.get("DESCRIPTION", os.path.basename(isf_path))

        if self.session is None:
            self.session = await self.client.create_session({
                "model": "claude-sonnet-4.5",
                "system_message": {"content": ISF_CONVERSION_PROMPT},
                "on_permission_request": PermissionHandler.approve_all,
            })

        done = asyncio.Event()
        response_parts = []

        def on_event(event):
            if event.type.value == "assistant.message":
                response_parts.append(event.data.content)
                done.set()
            elif event.type.value == "session.idle":
                if not done.is_set():
                    done.set()

        unsubscribe = self.session.on(on_event)
        try:
            await self.session.send({"prompt": prompt})
            await asyncio.wait_for(done.wait(), timeout=120)
        finally:
            if callable(unsubscribe):
                unsubscribe()

        if not response_parts:
            raise RuntimeError("No response from Copilot")

        code = extract_code(response_parts[-1])
        fn, err = load_render_fn(code)
        if fn is None:
            raise RuntimeError(f"Generated code failed to load: {err}")

        return code, desc

    def convert(self, isf_path: str, extra_instructions: str = "") -> tuple[str, str]:
        """Synchronous wrapper. Returns (code, description)."""
        self._ensure_loop()
        future = asyncio.run_coroutine_threadsafe(
            self._convert(isf_path, extra_instructions), self._loop
        )
        return future.result(timeout=130)


# ── CLI Entry Point ──────────────────────────────────────────

def main():
    """Convert an ISF shader file to a TermVJ render function."""
    if not HAS_COPILOT:
        print("Error: github-copilot-sdk is required. Install with:")
        print("  pip install github-copilot-sdk")
        sys.exit(1)

    if len(sys.argv) < 2:
        print("Usage: python isf_converter.py <shader.fs> [output.py] [--instructions 'extra']")
        print("\nConverts an ISF shader to a TermVJ render_ai() function.")
        print("\nExamples:")
        print("  python isf_converter.py ../magic/FluidFlow.fs")
        print("  python isf_converter.py ../magic/Plasma.fs plasma_console.py")
        print("  python isf_converter.py shader.fs -i 'make it extra colorful'")
        sys.exit(0)

    isf_path = sys.argv[1]
    if not os.path.exists(isf_path):
        print(f"Error: File not found: {isf_path}")
        sys.exit(1)

    output_path = None
    extra = ""
    i = 2
    while i < len(sys.argv):
        if sys.argv[i] in ("-i", "--instructions") and i + 1 < len(sys.argv):
            extra = sys.argv[i + 1]
            i += 2
        else:
            output_path = sys.argv[i]
            i += 1

    print(f"Converting: {isf_path}")
    converter = ISFConverter()
    try:
        code, desc = converter.convert(isf_path, extra)
    except Exception as e:
        print(f"Conversion failed: {e}")
        sys.exit(1)

    if output_path:
        with open(output_path, "w") as f:
            f.write(code)
        print(f"Saved to: {output_path}")
    else:
        print("\n# --- Generated render_ai() ---\n")
        print(code)

    print(f"\nDescription: {desc}")


if __name__ == "__main__":
    main()
