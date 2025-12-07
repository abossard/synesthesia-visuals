# Shader Fix Plan

Analysis of **57 broken/black shaders** and proposed fixes.

## Summary of Issues

| Issue Category | Count | Example Shaders |
|----------------|-------|---------|
| **Mouse-dependent (mouse=0,0)** | ~25 | AMPwaves, faerieblobs, kaleidoblast, RBrectomatic, redbricks |
| **Backbuffer/feedback required** | ~6 | angerlightR, christmasgel, orbitalrainbowdots |
| **Resolution-dependent positioning** | ~8 | LBgraphpaperdots, lifeessence, heartbeat |
| **Dark color defaults** | ~5 | OBgeartastic, BWsemicyclical |
| **Vertex Shader + varyings (ISF)** | 5 | Life, Hoop Dreams, WaveLines-2, Wisps-2, WorkinOnTheBlockChainGang |
| **PASSES (persistent buffers)** | 1 | Life |
| **Coordinate/math issues (ISF)** | 4 | Cosplay, Discspin, VoronoiSimplexTriTap, Fractal Cartoon |
| **Default values cause black (ISF)** | 2 | Triangle, Heart |
| **Long/dropdown type (ISF)** | 1 | Noise |

---

## GLSL Shader Analysis (New)

### Category 1: Mouse-Dependent Shaders (BLACK when mouse=0,0)

These shaders use `mouse` uniform for critical calculations. When mouse defaults to (0,0), output is black.

| Shader | Issue | Fix |
|--------|-------|-----|
| **AMPwaves_animate** | `sin(...) * 0.15 * mouse.y` - multiplied by 0 | Default mouse to (0.5, 0.5) |
| **BWanxiety2** | `perspective(mouse)` - polar transform at origin | Default mouse to (0.5, 0.5) |
| **RBrectomatic_animate** | `vec2 c = mouse` in fractal iteration | Default mouse to (0.5, 0.5) |
| **faerieblobs** | `makePoint() / mouse.x` - division by 0! | Default mouse to (0.5, 0.5) |
| **kaleidoblast_animate** | `makeSymmetry()` adds mouse offset | Default mouse to (0.5, 0.5) |
| **flyingthroughspace** | `position - mouse` centers at origin | Default mouse to (0.5, 0.5) |
| **redbricks** | `mouse*resolution` for light position | Default mouse to (0.5, 0.5) |
| **Ginsanity_animate** | `light_pos = resolution*mouse` | Default mouse to (0.5, 0.5) |
| **globetag3D** | Camera controlled by mouse | Default mouse to (0.5, 0.5) |
| **fractalreact_animate** | Julia set `c = -(mouse - 0.5) * 1.2` | Default mouse to (0.5, 0.5) |
| **discolights** | `mouse / 4.0` in UV calculation | Default mouse to (0.5, 0.5) |
| **polarcolorswirls** | Complex effect depends on mouse | Default mouse to (0.5, 0.5) |

**Global Fix:** In ShaderManager, set `mouse` default to `vec2(0.5, 0.5)` instead of `vec2(0, 0)`.

### Category 2: Backbuffer/Feedback Required

These shaders sample `backbuffer` or use feedback loops. Without prior frame data, output is black or wrong.

| Shader | Issue | Fix |
|--------|-------|-----|
| **angerlightR** | `mix(color, bbf(position), 0.5)` - samples empty buffer | Need PGraphics feedback loop |
| **christmasgel_animate** | `texture2D(backbuffer, uv_distorted)` | Need PGraphics feedback loop |
| **orbitalrainbowdots** | `texture2D(backbuffer, texPos)*0.9` - trail effect | Need PGraphics feedback loop |

**Fix:** Implement dual-buffer rendering for feedback shaders or mark as unsupported.

### Category 3: Resolution-Dependent Pixel Positioning

These shaders use hardcoded pixel values that don't scale with resolution.

| Shader | Issue | Fix |
|--------|-------|-----|
| **LBgraphpaperdots** | `pos(move, fps)` returns `s * resolution` | Should work, but dot radius=50px may be too small |
| **lifeessence** | `mb[i] = vec2(187,293)...` hardcoded pixel coords | Scale by resolution ratio |
| **heartbeat** | `gl_FragCoord.xy-resolution` calculation | Should work, needs time to animate |

### Category 4: Dark Color Output by Design

These shaders produce very dark output due to color calculations.

| Shader | Issue | Fix |
|--------|-------|-----|
| **OBgeartastic** | `vec3 c = m1 > m2 ? vec3(0.0, 0.05, 0.2) : vec3(0.2, 0.05, 0.0)` - very dark | Multiply output by brightness factor |
| **BWsemicyclical** | Output is `vec4(color) * .3` - intentionally dim | Increase multiplier |
| **BWanxiety** | Similar dimming | Increase output brightness |
| **redtrianglearmy** | `if (d < 0.0) color.r = ...` - black outside triangles | Expected behavior |
| **blinkyspherescube_animate** | HSV coloring with `exp(-0.01*t*t)` fog | Raymarcher needs camera movement |

### Category 5: Division by Zero or Invalid Math

| Shader | Issue | Fix |
|--------|-------|-----|
| **emberdrive** | `gradient += ... / pow(length(...), 1.5)` - safe but scale issue | Works, just dark at start |
| **torch** | Works but `defaultPosition = vec2(0.5, 0.2)` flame is dim | Increase color multiplier |
| **colorsquaroid** | `pow(abs(...), 0.1)` produces large negative | Math issue with pow |

### Category 6: Complex Raymarchers (Need Time/Camera)

| Shader | Issue | Fix |
|--------|-------|-----|
| **alienworks** | Raymarching through tunnel, needs time | Wait for animation |
| **alienworksrapid** | Same as alienworks | Wait for animation |
| **octopus** | Heart shape calculation, y offset | Should work |

---

## Quick Fixes (ShaderManager.pde)

### 1. Default mouse to center (HIGHEST IMPACT)

```java
// In setupShaderUniforms() or similar
shader.set("mouse", 0.5f, 0.5f);  // Center instead of (0,0)
```

This single fix should restore ~25 shaders!

### 2. Add brightness boost for dark shaders

For shaders in Category 4, add post-processing or output multiplier:

```java
// In shader output or as uniform
uniform float brightness_boost;  // default 1.0, set higher for dark shaders
gl_FragColor.rgb *= brightness_boost;
```

### 3. Mark backbuffer shaders as needing feedback

Create a list of shaders requiring feedback and implement dual-buffer:

```java
String[] feedbackShaders = {
  "angerlightR", "christmasgel_animate", "orbitalrainbowdots"
};
```

---

## Full Shader List by Category

### Working After Mouse Fix (~25 shaders)
- AMPwaves_animate
- BWanxiety2  
- BWconcentriccirleparts
- BWshaketunnel_animate
- Ginsanity_animate
- RBrectomatic_animate
- RGBfractalreactor_animate
- discolights
- emberdrive
- faerieblobs
- flyingthroughspace
- fractalreact_animate
- globetag3D
- kaleidoblast_animate
- pinkmistmorning
- polarcolorswirls
- rainbowripples
- redbricks
- retina2

### Need Backbuffer (6 shaders)
- angerlightR
- christmasgel_animate
- orbitalrainbowdots
- badvideo (uses distortion but ok without)

### Intentionally Dark / Need Brightness (5 shaders)
- OBgeartastic
- BWsemicyclical
- BWanxiety
- redtrianglearmy
- smogmonster

### Complex / May Work with Time (8 shaders)
- alienworks
- alienworksrapid
- blinkyspherescube_animate
- torch
- octopus
- heartbeat
- lifeessence
- colorsquaroid

---

## ISF Shader Analysis (Original)

**Problem:** Uses ISF PASSES for persistent buffer + vertex shader varyings
```glsl
"PASSES": [{ "TARGET":"lastData", "PERSISTENT": true }]

// Uses varyings from vertex shader:
varying vec2 left_coord;
varying vec2 right_coord;
// ... 8 total neighbor coordinates
```

**Solution:**
1. **Implement multi-pass rendering** - Already have framework, need persistent pass targets
2. **Replace varyings with direct calculation:**
```glsl
// Instead of vertex shader varyings:
vec2 left_coord = gl_FragCoord.xy + vec2(-1.0, 0.0);
vec2 right_coord = gl_FragCoord.xy + vec2(1.0, 0.0);
// etc.
```
3. **Implement IMG_PIXEL function:**
```glsl
#define IMG_PIXEL(tex, coord) texture2D(tex, coord / resolution)
```

**Difficulty:** High (needs multi-pass architecture changes)
**Priority:** Medium

---

### 3. Cosplay

**Problem:** Uses `gl_FragCoord` but our Y-flip may not work with the specific math
```glsl
vec2 uv = gl_FragCoord.xy/RENDERSIZE;
uv -= vec2(pos);
// Loop creates dots at sin/cos positions
```
The shader creates white dots on black background - if dots are positioned outside visible area or very small, appears black.

**Solution:**
1. Check `pos` default is `[0.5, 0.5]` - should center correctly
2. Issue is likely `iteration` default of 100 but loop limit is 100 - should work
3. **Debug:** Add `color = vec3(1.0)` before return to verify shader runs

**Likely Fix:** The `dotSize` default is 0.01 which is tiny. Combined with Y-flip, dots may be off-screen.
```glsl
// Try: ensure pos subtracts correctly with flipped Y
uv -= vec2(pos.x, 1.0 - pos.y);
```

**Difficulty:** Easy
**Priority:** High

---

### 4. Discspin

**Problem:** Similar coordinate system issue
```glsl
vec2 uv = gl_FragCoord.xy / RENDERSIZE.xy;
uv -= vec2(pos - 0.5);  // Note: subtracts (pos - 0.5)
```

**Solution:** The `pos - 0.5` adjustment expects ISF's coordinate system. With our Y-flip:
```glsl
// Original: uv -= vec2(pos - 0.5);
// Fixed for Processing:
uv -= vec2(pos.x - 0.5, 0.5 - pos.y);
```

**Difficulty:** Easy
**Priority:** High

---

### 5. Hoop Dreams / WaveLines-2 / Wisps-2

**Problem:** Have vertex shader files (`.vs`) with varyings but we don't load vertex shaders
```glsl
// These shaders expect vertex shader to be loaded
// We only load the .fs file
```

**Solution Options:**
1. **Ignore vertex shader** (most ISF vertex shaders just call `isf_vertShaderInit()` and calculate texture coords)
2. **Check if varyings are used** - these shaders don't seem to use varyings directly in fragment
3. **Same coordinate fix as Cosplay/Discspin**

For these specific shaders, the vertex shader likely doesn't contribute - the issue is the same coordinate math problem.

**Difficulty:** Easy (just coordinate fix)
**Priority:** High

---

### 6. VoronoiSimplexTriTap

**Problem:** Computes position as:
```glsl
vec2 pos = (gl_FragCoord.xy - RENDERSIZE.xy*.5)/RENDERSIZE.y;
```
This centers origin at screen center. Should work with Y-flip.

**Likely Issue:** The `sqrt(max(col, 0.0)-0.2+gamma)` with `gamma=0.1` default produces very dark output. Combined with dark `C1`/`C2` defaults:
```glsl
"C1": [0.6, 0.2, 0.4, 1.0],  // dim magenta
"C2": [0.15, 0.05, 0.5, 1.0]  // very dark purple
```

**Solution:** 
1. Increase `gamma` default to 0.2 or 0.3
2. Or brighten color defaults

**Difficulty:** Easy (tweak defaults in ISF JSON or override in binding)
**Priority:** Medium

---

### 7. WorkinOnTheBlockChainGang

**Problem:** Has vertex shader but fragment shader uses:
```glsl
void main( void ) {
  vec3 color;  // Not initialized!
  if (inSize(gl_FragCoord.xy)) color += getColor(gl_FragCoord.xy);
  gl_FragColor = vec4( color, 1.0 );
}
```
`color` is uninitialized, defaults to `vec3(0.0)`. If `inSize()` returns false for all pixels, output is black.

**Debug:** The `inSize()` function uses `sizeX=300, sizeY=10` defaults with `triangleWave(TIME*rate)` animation.

**Solution:**
1. Initialize color: `vec3 color = vec3(0.0);` (already implied but explicit)
2. Check `sizeX/sizeY` defaults vs screen resolution
3. The logic checks if pixel is within animated blocks - may need resolution scaling

**Difficulty:** Medium (needs logic analysis)
**Priority:** Medium

---

### 8. Fractal Cartoon

**Problem:** Complex raymarching shader with Shadertoy conventions
```glsl
vec3 iResolution = vec3(RENDERSIZE, 1.0);
float iGlobalTime = TIME;
vec4 iMouse = vec4(mouse, 0.0, 1.0);
```
Uses `mouse` input which defaults to `[0,0]` - camera control.

**Issue:** `if (iMouse.z<1.) mouse=vec2(0.,-0.05);` 
The `iMouse.z` is always 0 (we don't track mouse button), so uses default position.

**Solution:**
1. This shader may just need time to run - it's a flythrough
2. Add small offset to default mouse position
3. Check if our coordinate flip breaks the raymarching

**Difficulty:** Medium (raymarching is sensitive to coordinates)
**Priority:** Low (complex shader)

---

### 9. Triangle

**Problem:** Uses `pt1=[0,0], pt2=[0.5,1], pt3=[1,0]` but divides by RENDERSIZE:
```glsl
vec2 point1 = pt1 / RENDERSIZE;  // This makes points tiny!
```
With RENDERSIZE ~1920x1080, points become sub-pixel coordinates.

**Solution:** The inputs should be in normalized 0-1 space, not pixel space. Remove division:
```glsl
vec2 point1 = pt1;  // Already normalized
vec2 point2 = pt2;
vec2 point3 = pt3;
```

**Difficulty:** Easy
**Priority:** High

---

### 10. Heart

**Problem:** Default `size=0.25` may be too small with our coordinate system
```glsl
bool inHeart (vec2 p, vec2 center, float size) {
  if (size == 0.0) return false;
  vec2 o = (p-center)/(1.6*size);  // Division by size scales heart
  return pow(o.x*o.x+o.y*o.y-0.3, 3.0) < o.x*o.x*pow(o.y, 3.0);
}
```

**Solution:** With Y-flip, the heart may be upside-down or off-center. Center is `[0.5, 0.4]` in ISF coords.
```glsl
// In Processing coords, Y is flipped:
// center should be [0.5, 0.6] to appear at same visual position
```

**Difficulty:** Easy
**Priority:** High

---

### 11. Noise

**Problem:** Uses ISF `long` type for `color_mode`:
```glsl
"TYPE": "long",
"VALUES": [0, 1, 2, 3],
"LABELS": ["B&W", "Alpha", "RGB", "RGBA"],
"DEFAULT": 2
```

**Solution:** We should convert `long` to `int` uniform. Currently may not be handled.

Check if `color_mode` is declared as `uniform int color_mode;`

**Difficulty:** Easy (add long→int type mapping)
**Priority:** Medium

---

## Prioritized Fix List

### High Priority (Easy Fixes - Coordinate Issues)
1. **Cosplay** - Flip Y in position subtraction
2. **Discspin** - Flip Y in position subtraction  
3. **Hoop Dreams** - Same coordinate fix
4. **WaveLines-2** - Same coordinate fix
5. **Wisps-2** - Same coordinate fix
6. **Triangle** - Remove `/ RENDERSIZE` division
7. **Heart** - Adjust center Y coordinate for flip

### Medium Priority (Logic/Default Fixes)
8. **VoronoiSimplexTriTap** - Increase gamma default
9. **WorkinOnTheBlockChainGang** - Debug size calculations
10. **Noise** - Add `long` → `int` type mapping
11. **Fractal Cartoon** - Check mouse defaults

### Low Priority (Architecture Changes)
12. **Life** - Needs persistent passes + IMG_PIXEL

---

## Recommended Code Changes

### 1. Fix Y-flip in position uniforms (ShaderManager.pde)

Add post-processing for point2D defaults that adjust center positions:
```java
// In storeIsfDefault() for point2D type
if (name.toLowerCase().contains("pos") || name.toLowerCase().contains("center")) {
  // Flip Y coordinate for Processing's top-left origin
  y = 1.0 - y;
}
```

### 2. Fix Triangle division bug

Detect when point2D is divided by RENDERSIZE in shader code and remove it:
```java
// In convertIsfToGlsl(), add replacement:
glslBody = glslBody.replaceAll("(pt[123]) / RENDERSIZE", "$1");
```

### 3. Add long type support

```java
// In isfTypeToGlsl()
case "long":
  return "int";
```

### 4. Create generic Y-flip fix for gl_FragCoord math

Many shaders do: `uv = gl_FragCoord.xy / RENDERSIZE; uv -= pos;`

Add option to flip the pos subtraction:
```java
// Detect pattern and fix:
glslBody = glslBody.replaceAll(
  "uv\\s*-=\\s*vec2\\(pos\\)",
  "uv -= vec2(pos.x, 1.0 - pos.y)"
);
```

---

## Testing Checklist

After fixes, verify each shader:
- [ ] Cosplay - White dots on black, animated
- [ ] Discspin - Spinning disc pattern
- [ ] Hoop Dreams - Animated circles
- [ ] WaveLines-2 - Wavy line pattern
- [ ] Wisps-2 - Glowing wave lines
- [ ] Triangle - White triangle on black
- [ ] Heart - Red heart shape
- [ ] VoronoiSimplexTriTap - Voronoi cells, visible colors
- [ ] WorkinOnTheBlockChainGang - Animated color blocks
- [ ] Noise - Random colored pixels
- [ ] Fractal Cartoon - 3D flythrough animation
- [ ] Life - Game of Life (needs passes)
