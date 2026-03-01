# AI Agent Rules — Magic Music Visuals Subtree

> Overrides and extends the repository-wide `AGENTS.md` for all work under `magic/`.

## Scope
- Applies to all files in `magic/` and subdirectories.
- Primary file types: `.fs` (ISF fragment shaders), `.magic` (project files), `.xml` (decoded project files).

## 1) GLSL Target: OpenGL 2.1 / GLSL 1.20

Magic Music Visuals compiles ISF shaders against a **GLSL 1.20-era profile**. Many GLSL 1.30+ features silently fail or produce compile errors. These rules are **mandatory**.

### Forbidden Constructs
| Construct | Why | Fix |
|-----------|-----|-----|
| `max(int, int)`, `min(int, int)`, `clamp(int, int, int)`, `abs(int)` | Integer overloads not available | Cast to float: `max(float(x), 1.0)` |
| `tanh()` | Not a GLSL 1.20 built-in | Add polyfill (see §2) |
| `uint`, `uvec2`, `uvec3`, `uvec4` | Unsigned types not available | Use `int`, `ivec*`, or `float` |
| `&`, `\|`, `^`, `<<`, `>>` (bitwise) | Not available | Use `fract(sin(dot(...)))` for hashing |
| `round()` | Not a GLSL 1.20 built-in | Use `floor(x + 0.5)` |
| `%` (integer modulo) | Not available in some GLSL 1.20 runtimes | Use `mod(float(a), float(b))` |
| `2.0f`, `1.5f` (C-style float suffix) | Not valid GLSL syntax | Remove `f`: `2.0` |
| `precision highp float;` | Desktop GLSL, not needed | Remove entirely |
| `#version` directive | ISF host manages this | Remove entirely |
| `texture()` | GLSL 1.30+ | Use `texture2D()` or ISF macros |
| `isnan()`, `isinf()` | Not in GLSL 1.20 | `(x != x)` for NaN, `(abs(x) > 1e37)` for Inf |
| `ivec2` in ISF macros | `IMG_PIXEL` expects `vec2` | Use `vec2(0.0)` not `ivec2(0)` |
| `int < float` in for-loops | Type mismatch | Cast float to int: `int(floatVar)` |
| `float[N](...)` array constructor | GLSL 1.30+ syntax | Use init-in-function pattern; see `_fix_arrays.py` |
| `#ifdef GL_ES` blocks | Desktop-only host | Remove |

### Required Patterns
| Pattern | Rule |
|---------|------|
| Final output alpha | Always set `gl_FragColor.a = 1.0` |
| Loop bounds | Must be compile-time integer constants |
| Dynamic early exit | `if (i > dynamicLimit) break;` inside fixed-bound loops |
| Safe division | `value / max(divisor, 0.001)` |
| Float literals | Always use `.0` suffix: `1.0` not `1` in float context |

## 2) tanh Polyfill Convention

When a shader uses `tanh()`, add the appropriate polyfill(s) **before `void main()`** (or before the first function that calls tanh). Use `_tanh` as the name to avoid future conflicts.

```glsl
// tanh polyfill for GLSL 1.20 (not built-in before GLSL 1.30)
float _tanh(float x) {
    float e2x = exp(2.0 * clamp(x, -20.0, 20.0));
    return (e2x - 1.0) / (e2x + 1.0);
}
vec3 _tanh(vec3 x) {
    vec3 e2x = exp(2.0 * clamp(x, -20.0, 20.0));
    return (e2x - 1.0) / (e2x + 1.0);
}
vec4 _tanh(vec4 x) {
    vec4 e2x = exp(2.0 * clamp(x, -20.0, 20.0));
    return (e2x - 1.0) / (e2x + 1.0);
}
```

Then replace all `tanh(...)` calls with `_tanh(...)`.

> Some shaders already have `tanh_custom()` or `tanh_safe()` — those are acceptable alternatives.

## 3) ISF 2.0 Format Rules

### JSON Header
- Must be the **first thing** in the file: `/*{ ... }*/`
- Must parse as valid JSON
- Required keys: `ISFVSN` (use `"2.0"`), `INPUTS` array
- Recommended: `DESCRIPTION`, `CREDIT`, `CATEGORIES`

### Auto-declared Uniforms (NEVER redeclare)
`TIME`, `TIMEDELTA`, `RENDERSIZE`, `PASSINDEX`, `FRAMEINDEX`, `DATE`, `isf_FragNormCoord`

### ISF Macros (NEVER redefine)
`IMG_PIXEL(sampler, pixelCoord)`, `IMG_NORM_PIXEL(sampler, normCoord)`, `IMG_SIZE(sampler)`

### Input NAME ↔ GLSL Variable
The `NAME` field in each INPUTS entry becomes the GLSL uniform variable name. They **must match exactly** — no leading `uniform` keyword needed.

## 4) Persistent Buffer Pattern

For smooth parameter transitions (the bareimage signature technique):

```json
"PASSES": [
  {"TARGET": "timeBuffer", "PERSISTENT": true, "FLOAT": true, "WIDTH": 1, "HEIGHT": 1},
  {"TARGET": "paramBuffer", "PERSISTENT": true, "FLOAT": true, "WIDTH": 1, "HEIGHT": 1},
  {}
]
```

```glsl
if (PASSINDEX == 0) {
    vec4 prev = IMG_NORM_PIXEL(timeBuffer, vec2(0.5));
    float smoothed = (FRAMEINDEX == 0)
        ? targetValue
        : mix(prev.r, targetValue, min(1.0, TIMEDELTA * transitionSpeed));
    gl_FragColor = vec4(smoothed, 0.0, 0.0, 1.0);
    return;
}
```

- Use `FRAMEINDEX == 0` guard for initialization
- Use `TIMEDELTA * transitionSpeed` for frame-rate-independent smoothing
- `FLOAT: true` only for passes that store HDR or accumulated values

## 5) Performance Rules (Live VJ Context)

- Target: **60 fps at 1280×720** minimum on M1 MacBook Pro
- Raymarching: max **64–128 iterations** for live use
- Lower non-final pass resolution: `"WIDTH": 960, "HEIGHT": 540`
- Cache repeated `texture2D()` calls in local variables
- Add early-exit in distance marching: `if (d < 0.001) break;`
- Avoid nested `if` inside heavy loops — use `mix`/`step`/`smoothstep`

## 6) Licensing Compliance

- **Check each shader's header** for CC-BY-NC-SA 3.0 vs MIT
- **Preserve** `CREDIT` and license comments when editing
- bareimage/ISF collection: mostly CC-BY-NC-SA 3.0 (non-commercial only)
- When creating new shaders, add `CREDIT` with author and date

## 7) File Organization

| Path | Contents | Status |
|------|----------|--------|
| `ISF-bareimage/Release.1-5/` | 52 bareimage shaders | Production |
| `AI-SLOP/` | AI-generated experimental shaders | Experimental |
| `IDFGEN/` | Procedural ISF generators | Active |
| `TiltShift.fs` | Tilt-shift blur filter | Production |
| `*.magic` | Project files (binary) | Active |
| `magic-codec.sh` | Decode/encode .magic ↔ XML | Utility |

## 8) Common Error Diagnosis

| Error Message | Cause | Fix |
|---|---|---|
| "'f' : syntax error" | C-style `f` suffix on float literals (`2.0f`) | Remove `f`: `2.0f` → `2.0` |
| "'precision' : syntax error: syntax error" | Desktop GLSL has no precision qualifiers | Remove/comment out `precision highp float;` |
| \"Initializer not allowed\" | `const` with function calls (e.g. `cos()`, `normalize()`) | Use `#define`, precompute literal values, or remove `const` |
| "Invalid call of undeclared identifier 'texture'" | `texture()` is GLSL 1.30+ | Use `texture2D()` |
| "Invalid call of undeclared identifier 'round'" | `round()` not in GLSL 1.20 | Use `floor(x + 0.5)` |
| "'%' does not operate on 'int' and 'int'" | Integer modulo not available | Use `mod(float(a), float(b))` |
| "No matching function for call to max(int, int)" | Integer overload | Cast to float |
| "Invalid call of undeclared identifier 'tanh'" | GLSL 1.20 missing tanh | Add `_tanh` polyfill |
| "Use of undeclared identifier 'X'" | Cascading from earlier error OR redeclared uniform | Fix earlier error first; remove `uniform` declarations for ISF-managed vars |
| "No matching function for call to clamp(int, int, int)" | Integer overload | Cast to float |
| "Invalid call of undeclared identifier 'isnan'" / 'isinf' | Not in GLSL 1.20 | `(x != x)` for NaN, `(abs(x) > 1e37)` for Inf |
| "'/' does not operate on 'ivec2' and 'vec2'" | `IMG_PIXEL` expects vec2, not ivec2 | Use `vec2(0.0)` instead of `ivec2(0)` |
| "'<' does not operate on 'int' and 'float'" | int loop counter vs float uniform | Cast: `int(floatUniform)` |
| "Array size must appear after variable name" | `float[N](...)` array constructor (GLSL 1.30+) | Use init-in-function; run `_fix_arrays.py` |
| "Regular non-array variable 'X' may not be redeclared" | Buffer name in both IMPORTED and PASSES TARGET | Remove the `IMPORTED` block from JSON header |
| Black screen | Alpha = 0 or gated by dead uniforms | Set `gl_FragColor.a = 1.0`; add `max(value, 0.05)` floors |

## 9) Testing Workflow

1. Save `.fs` file
2. In Magic: right-click shader node → Reload (or remove and re-add)
3. If error dialog appears: note line number and error type
4. GLSL error line numbers correspond to the raw `.fs` file lines (JSON header is stripped)
5. Fix using the patterns in this document
6. Repeat until clean

## Anti-Patterns (Do Not Introduce)

- `texture()` instead of `texture2D()` or ISF macros
- Integer math functions (`max`, `min`, `clamp`, `abs`) with `int` arguments
- `tanh()`, `sinh()`, `cosh()` without polyfills
- `uniform` declarations for ISF auto-managed variables
- `precision` qualifiers or `#version` directives
- Bitwise operations or unsigned integer types
- Hard-coded resolution values instead of `RENDERSIZE`
