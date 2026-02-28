---
applyTo: 'magic/**/*.fs'
---
# Magic Music Visuals ISF Shader Rules

## Format
- ISF 2.0 (Interactive Shader Format): GLSL fragment shader with leading `/*{ JSON }*/` metadata block
- Spec: https://github.com/mrRay/ISF_Spec / https://docs.isf.video/

## GLSL Compatibility (CRITICAL)
Magic Music Visuals uses **GLSL 1.20-style** (OpenGL 2.1 / legacy profile). These rules prevent compilation errors:

### Type-safe built-in functions
- `max()`, `min()`, `clamp()`, `abs()`, `sign()` — **ONLY float overloads are guaranteed**
- **NEVER**: `max(int, int)`, `clamp(int, int, int)`, `abs(int)`
- **ALWAYS**: `max(float, float)`, `clamp(float, float, float)`, cast with `float()`
- Example fix: `max(numSamples, 1)` → `max(float(numSamples), 1.0)`

### No uint / bitwise operations
- Avoid `uint`, `uvec2`, `uvec3`, `uvec4`
- Avoid `&`, `|`, `^`, `<<`, `>>` bitwise operators
- Use `fract(sin(dot(...)))` for hashing instead of XOR tricks

### No tanh / sinh / cosh
- `tanh()`, `sinh()`, `cosh()` are **not built-in** before GLSL 1.30
- Add polyfill named `_tanh` before first usage:
  ```glsl
  float _tanh(float x) { float e2x = exp(2.0 * clamp(x, -20.0, 20.0)); return (e2x - 1.0) / (e2x + 1.0); }
  vec3 _tanh(vec3 x) { vec3 e2x = exp(2.0 * clamp(x, -20.0, 20.0)); return (e2x - 1.0) / (e2x + 1.0); }
  vec4 _tanh(vec4 x) { vec4 e2x = exp(2.0 * clamp(x, -20.0, 20.0)); return (e2x - 1.0) / (e2x + 1.0); }
  ```
- Replace `tanh(...)` → `_tanh(...)`; only include overloads actually used

### Texture sampling
- Use `texture2D()` (not `texture()`) for GLSL 1.20 hosts
- Or define a wrapper: `vec4 tex2D(sampler2D s, vec2 uv) { return texture2D(s, uv); }`
- Use `IMG_PIXEL()` / `IMG_NORM_PIXEL()` for ISF image inputs

### Precision qualifiers
- Do NOT use `precision highp float;` — not needed on desktop GLSL and causes errors on some hosts
- Remove any `#ifdef GL_ES` blocks

### Other pitfalls
- `gl_FragColor` is the output (not `fragColor` or return value)
- `isf_FragNormCoord` = normalized 0-1 coordinates
- No `#version` directive — ISF host manages this
- Integer loop bounds must be compile-time constants: `for(int i=0; i<64; i++)` ✓
- Dynamic early exit inside fixed-bound loops: `if(i > dynamicLimit) break;` ✓

## ISF Auto-declared Uniforms (DO NOT redeclare)
```glsl
uniform float TIME;           // seconds since start
uniform float TIMEDELTA;      // seconds since last frame
uniform vec2  RENDERSIZE;     // output resolution
uniform int   PASSINDEX;      // current rendering pass (0-based)
uniform int   FRAMEINDEX;     // frame counter (0 = first)
uniform vec4  DATE;            // year, month, day, seconds-in-day
uniform vec2  isf_FragNormCoord; // normalized frag coords
```

## ISF Macros (DO NOT redefine)
```glsl
IMG_PIXEL(samplerName, pixelCoord)       // texture lookup by pixel
IMG_NORM_PIXEL(samplerName, normCoord)   // texture lookup by normalized coord
IMG_SIZE(samplerName)                    // vec2 texture dimensions
```

## JSON Header Structure
```json
{
  "ISFVSN": "2.0",
  "DESCRIPTION": "Human-readable description",
  "CREDIT": "Original author. ISF conversion by @converter",
  "CATEGORIES": ["GENERATOR", "3D"],
  "INPUTS": [
    {"NAME": "speed", "TYPE": "float", "DEFAULT": 1.0, "MIN": 0.0, "MAX": 5.0, "LABEL": "Speed"},
    {"NAME": "color1", "TYPE": "color", "DEFAULT": [1, 0, 0, 1], "LABEL": "Color"},
    {"NAME": "mode", "TYPE": "long", "DEFAULT": 0, "VALUES": [0,1,2], "LABELS": ["A","B","C"]},
    {"NAME": "inputImage", "TYPE": "image", "LABEL": "Input"},
    {"NAME": "enabled", "TYPE": "bool", "DEFAULT": true}
  ],
  "PASSES": [
    {"TARGET": "bufferA", "PERSISTENT": true, "FLOAT": true, "WIDTH": 1, "HEIGHT": 1},
    {}
  ]
}
```

## Persistent Buffer Pattern (for smooth parameter transitions)
```glsl
if (PASSINDEX == 0) {
    vec4 prev = IMG_NORM_PIXEL(bufferA, vec2(0.5));
    float smoothed = (FRAMEINDEX == 0) ? targetValue
        : mix(prev.r, targetValue, min(1.0, TIMEDELTA * transitionSpeed));
    gl_FragColor = vec4(smoothed, 0.0, 0.0, 1.0);
    return;
}
```

## Numeric Stability
```glsl
// Prevent exp() overflow
vec4 exp2x = exp(2.0 * clamp(x, -20.0, 20.0));
return (exp2x - 1.0) / (exp2x + 1.0);

// Safe division
float result = value / max(divisor, 0.001);
```

## Licensing
- Check shader header for CC-BY-NC-SA 3.0 vs MIT
- Preserve CREDIT and license in JSON header
- bareimage/ISF collection: mostly CC-BY-NC-SA 3.0 (non-commercial only)
