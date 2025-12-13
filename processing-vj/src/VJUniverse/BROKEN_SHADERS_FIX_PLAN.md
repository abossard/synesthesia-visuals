# Shader Fix Plan

Analysis of remaining broken/black GLSL shaders after mouse fix.

## ✅ FIXED: Mouse-Dependent Shaders

**Status:** RESOLVED via synthetic mouse implementation in VJUniverse.pde

- Mouse now defaults to center (0.5, 0.5) when real mouse hasn't moved
- Audio-reactive figure-8 motion provides continuous mouse movement
- ~25 previously broken shaders now work

## Remaining Issues Summary

| Issue Category | Count | Example Shaders |
|----------------|-------|-----------------|
| **Backbuffer/feedback required** | ~6 | angerlightR, christmasgel, orbitalrainbowdots |
| **Dark color defaults** | ~5 | OBgeartastic, BWsemicyclical |
| **Complex raymarchers** | ~3 | alienworks, blinkyspherescube |

---

## GLSL Shader Analysis

### Category 1: Backbuffer/Feedback Required

These shaders sample `backbuffer` or use feedback loops. Without prior frame data, output is black or wrong.

| Shader | Issue | Fix |
|--------|-------|-----|
| **angerlightR** | `mix(color, bbf(position), 0.5)` - samples empty buffer | Need PGraphics feedback loop |
| **christmasgel_animate** | `texture2D(backbuffer, uv_distorted)` | Need PGraphics feedback loop |
| **orbitalrainbowdots** | `texture2D(backbuffer, texPos)*0.9` - trail effect | Need PGraphics feedback loop |

**Fix:** Implement dual-buffer rendering for feedback shaders or mark as unsupported.

### Category 2: Dark Color Output by Design

These shaders produce very dark output due to color calculations.

| Shader | Issue | Fix |
|--------|-------|-----|
| **OBgeartastic** | `vec3 c = m1 > m2 ? vec3(0.0, 0.05, 0.2) : vec3(0.2, 0.05, 0.0)` - very dark | Multiply output by brightness factor |
| **BWsemicyclical** | Output is `vec4(color) * .3` - intentionally dim | Increase multiplier |
| **BWanxiety** | Similar dimming | Increase output brightness |
| **redtrianglearmy** | `if (d < 0.0) color.r = ...` - black outside triangles | Expected behavior |
| **blinkyspherescube_animate** | HSV coloring with `exp(-0.01*t*t)` fog | Raymarcher needs camera movement |

### Category 3: Division by Zero or Invalid Math

| Shader | Issue | Fix |
|--------|-------|-----|
| **emberdrive** | `gradient += ... / pow(length(...), 1.5)` - safe but scale issue | Works, just dark at start |
| **torch** | Works but `defaultPosition = vec2(0.5, 0.2)` flame is dim | Increase color multiplier |
| **colorsquaroid** | `pow(abs(...), 0.1)` produces large negative | Math issue with pow |

### Category 4: Complex Raymarchers (Need Time/Camera)

| Shader | Issue | Fix |
|--------|-------|-----|
| **alienworks** | Raymarching through tunnel, needs time | Wait for animation |
| **alienworksrapid** | Same as alienworks | Wait for animation |
| **octopus** | Heart shape calculation, y offset | Should work |

---

## Quick Fixes (ShaderManager.pde)

### 1. Add brightness boost for dark shaders

For shaders in Category 2, add post-processing or output multiplier:

```java
// In shader output or as uniform
uniform float brightness_boost;  // default 1.0, set higher for dark shaders
gl_FragColor.rgb *= brightness_boost;
```

### 2. Mark backbuffer shaders as needing feedback

Create a list of shaders requiring feedback and implement dual-buffer:

```java
String[] feedbackShaders = {
  "angerlightR", "christmasgel_animate", "orbitalrainbowdots"
};
```

---

## Remaining Shader Lists by Category

### Need Backbuffer (4 shaders)

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
