---
description: Convert Shadertoy or ISF shaders to Synesthesia format with audio reactivity
---

# Shadertoy/ISF to Synesthesia Converter

Convert shaders from Shadertoy or ISF (Interactive Shader Format) to Synesthesia's SSF (Synesthesia Scene Format) with intelligent audio reactivity.

## Input

Provide:
1. Shader source code (Shadertoy or ISF format)
2. Shader name/description (optional, for better audio mapping)

## Output

A complete `.synScene` directory with:
- `main.glsl` - Converted fragment shader with audio uniforms
- `scene.json` - Metadata, controls, and configuration
- `script.js` (optional) - Per-frame state management if needed

## Conversion Process

### 1. Analyze the Shader

First, understand the shader's:
- **Visual style**: Abstract, geometric, organic, glitch, tunnel, fractal, etc.
- **Motion characteristics**: Rotation speed, pulse frequency, zoom patterns
- **Color usage**: Monochrome, psychedelic, dark/bright, gradient-heavy
- **Complexity**: Number of iterations, raymarching steps, texture lookups

### 2. Uniform Mapping

**From Shadertoy:**
```glsl
// Shadertoy → Synesthesia
iResolution.xy → RENDERSIZE.xy
iTime / iGlobalTime → TIME
iFrame → FRAMECOUNT
iMouse → _mouse (pixel) or _muv (normalized)
fragCoord → _xy (pixel) or _uv (normalized 0-1) or _uvc (aspect-correct)
iChannel0..3 → syn_Media or custom samplers (define in IMAGES array)
```

**From ISF:**
```glsl
// ISF → Synesthesia
isf_FragNormCoord → _uv
TIME → TIME (same)
RENDERSIZE → RENDERSIZE (same)
PASSINDEX → PASSINDEX (same)
INPUTS → CONTROLS (in scene.json)
IMG_PIXEL(name, coord) → texture(name, coord)
```

### 3. Audio Reactivity - Learn from Built-in Patterns

Study these patterns from Synesthesia's built-in shaders for audio reactivity:

**Pattern 1: Bass-Driven Motion**
```glsl
// Always-moving base + bass boost
float baseTime = TIME * 0.3;
float bassTime = syn_BassTime * 0.5;  // syn_BassTime accumulates during bass hits
float t = baseTime + bassTime;

// Use t for rotation, position offsets, pattern evolution
vec2 pos = vec2(cos(t), sin(t));
```

**Pattern 2: Beat-Triggered Effects**
```glsl
// Threshold-based beat detection
float bassActive = smoothstep(0.6, 0.7, syn_BassHits);  // 0.6-0.7 = threshold range
float midActive = smoothstep(0.5, 0.6, syn_MidHits);

// Apply to scale, brightness, or effect intensity
float scale = 1.0 + bassActive * 0.3;  // 30% scale boost on bass
vec3 color = baseColor * (1.0 + midActive * 0.5);  // 50% brightness boost on mid
```

**Pattern 3: Multi-Band Reactivity**
```glsl
// Per-band energy levels (smoothed)
float bass = syn_BassLevel;   // 0-1, low frequencies
float mid = syn_MidLevel;     // 0-1, mid frequencies  
float high = syn_HighLevel;   // 0-1, high frequencies
float overall = syn_Level;    // 0-1, overall energy

// Use for different visual elements
float rotation = TIME + bass * 2.0;           // Bass controls rotation
vec3 hue = vec3(bass, mid, high);             // RGB from frequency bands
float brightness = 0.5 + overall * 0.5;       // Overall energy to brightness
```

**Pattern 4: Spectrum-Based Effects**
```glsl
// Access frequency spectrum (sampler1D, 512 bins)
float freq = texture(syn_Spectrum, uv.x).r;   // Sample across width
vec3 color = vec3(freq) * baseColor;

// Level trail (history of syn_Level over time)
float trail = texture(syn_LevelTrail, uv.x).r;  // Past energy levels
```

**Pattern 5: BPM Sync**
```glsl
// Sync to detected BPM
float beat = syn_BeatTime;  // Accumulates each beat
float bpm = syn_BPM;        // Detected BPM (e.g., 128.0)

// Create pulsing on beat
float pulse = fract(beat);  // 0-1 sawtooth per beat
float smooth_pulse = smoothstep(0.0, 0.1, pulse) * smoothstep(0.3, 0.1, pulse);

// Use pulse for scale, color, etc.
float scale = 1.0 + smooth_pulse * 0.2;
```

**Pattern 6: Configurable Audio Bindings**
```glsl
// Create user controls for audio sensitivity
uniform float bass_amount;     // How much bass affects motion (0-1)
uniform float bpm_sync;         // BPM sync strength (0-1)
uniform float bass_threshold;   // Minimum bass level to trigger (0-1)

// Apply in shader
float motion = TIME + syn_BassTime * bass_amount;
float trigger = smoothstep(bass_threshold, bass_threshold + 0.1, syn_BassHits);
```

### 4. Add Configurable Controls

Extract magic numbers and add to `scene.json` as controls:

**scene.json CONTROLS array:**
```json
{
  "CONTROLS": [
    {
      "NAME": "speed",
      "TYPE": "slider",
      "DEFAULT": 0.5,
      "MIN": 0.0,
      "MAX": 2.0,
      "UI_GROUP": "Motion"
    },
    {
      "NAME": "bass_amount",
      "TYPE": "slider",
      "DEFAULT": 0.5,
      "MIN": 0.0,
      "MAX": 1.0,
      "UI_GROUP": "Audio"
    },
    {
      "NAME": "color_palette",
      "TYPE": "dropdown",
      "DEFAULT": 0,
      "LABELS": ["Rainbow", "Monochrome", "Fire", "Ice"],
      "VALUES": [0, 1, 2, 3],
      "UI_GROUP": "Appearance"
    },
    {
      "NAME": "enable_bass_trigger",
      "TYPE": "toggle",
      "DEFAULT": true,
      "UI_GROUP": "Audio"
    },
    {
      "NAME": "warp_center",
      "TYPE": "xy",
      "DEFAULT": [0.5, 0.5],
      "UI_GROUP": "Effects"
    },
    {
      "NAME": "primary_color",
      "TYPE": "color",
      "DEFAULT": [1.0, 0.5, 0.0, 1.0],
      "UI_GROUP": "Appearance"
    }
  ]
}
```

These become `uniform float speed;`, `uniform bool enable_bass_trigger;`, etc. in GLSL.

### 5. Entry Point Conversion

**Convert main function:**

Shadertoy:
```glsl
void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;
    // ... shader code ...
    fragColor = finalColor;
}
```

Synesthesia:
```glsl
vec4 renderMain() {
    vec2 uv = _uv;  // Already normalized
    // ... shader code ...
    return finalColor;
}
```

### 6. Choose Audio Reactivity Strategy

Based on shader analysis, pick the best audio mapping:

**For tunnel/zoom shaders:**
- Bass → speed/zoom rate
- Mid → color cycling
- High → detail/noise intensity

**For particle/fractal shaders:**
- Bass → particle count/size
- BassHits → explosion triggers
- BPM → pattern repetition

**For warp/distortion shaders:**
- Bass → distortion amount
- Mid → warp frequency
- Overall level → effect intensity

**For color-based shaders:**
- Spectrum → rainbow/gradient mapping
- Bass/Mid/High → RGB channels
- BPM → hue cycling speed

### 7. scene.json Template

```json
{
  "NAME": "ShaderName",
  "DESCRIPTION": "Converted from Shadertoy/ISF with audio reactivity",
  "CREDIT": "Original author name, converted to Synesthesia",
  "WIDTH": 1920,
  "HEIGHT": 1080,
  "TAGS": ["tunnel", "psychedelic", "bass-reactive"],
  "CONTROLS": [
    {
      "NAME": "speed",
      "TYPE": "slider",
      "DEFAULT": 0.5,
      "MIN": 0.0,
      "MAX": 2.0,
      "UI_GROUP": "Motion"
    },
    {
      "NAME": "bass_amount",
      "TYPE": "slider", 
      "DEFAULT": 0.8,
      "MIN": 0.0,
      "MAX": 1.0,
      "UI_GROUP": "Audio Reactivity"
    },
    {
      "NAME": "bass_threshold",
      "TYPE": "slider",
      "DEFAULT": 0.6,
      "MIN": 0.0,
      "MAX": 1.0,
      "UI_GROUP": "Audio Reactivity"
    }
  ],
  "PASSES": [],
  "IMAGES": []
}
```

### 8. Advanced: script.js for State Management

If shader needs smoothing or custom timing:

```javascript
// script.js - runs each frame before shader
export function setup() {
  // Initialize state
  uniforms.smoothBass = 0;
  uniforms.beatCount = 0;
}

export function update(dt) {
  // Smooth bass transitions (0.9 = heavy smoothing)
  uniforms.smoothBass = uniforms.smoothBass * 0.9 + syn_BassLevel * 0.1;
  
  // Count beats
  if (syn_BassHits > 0.7) {
    if (!uniforms.beatTriggered) {
      uniforms.beatCount++;
      uniforms.beatTriggered = true;
    }
  } else {
    uniforms.beatTriggered = false;
  }
  
  // Custom timing
  uniforms.customTime = TIME * uniforms.speed;
}
```

## Example Conversion

**Input (Shadertoy tunnel):**
```glsl
void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = (fragCoord - iResolution.xy * 0.5) / iResolution.y;
    float t = iTime * 0.5;
    float d = length(uv) - t;
    vec3 col = 0.5 + 0.5 * cos(d * 6.28 + vec3(0, 2, 4));
    fragColor = vec4(col, 1.0);
}
```

**Output (Synesthesia with audio):**

**main.glsl:**
```glsl
uniform float speed;
uniform float bass_amount;
uniform float bass_threshold;

vec4 renderMain() {
    vec2 uv = (_xy - RENDERSIZE.xy * 0.5) / RENDERSIZE.y;  // Aspect-correct
    
    // Always-moving base + bass-driven boost
    float baseTime = TIME * speed;
    float bassTime = syn_BassTime * bass_amount;
    float t = baseTime + bassTime;
    
    // Distance field with motion
    float d = length(uv) - t;
    
    // Bass-triggered brightness boost
    float bassActive = smoothstep(bass_threshold, bass_threshold + 0.1, syn_BassHits);
    float brightness = 1.0 + bassActive * 0.5;
    
    // Color with spectrum influence
    vec3 baseColor = 0.5 + 0.5 * cos(d * 6.28 + vec3(0, 2, 4));
    float spectrumSample = texture(syn_Spectrum, abs(uv.x)).r;
    vec3 col = baseColor * brightness * (0.8 + spectrumSample * 0.2);
    
    return vec4(col, 1.0);
}
```

**scene.json:**
```json
{
  "NAME": "Audio Reactive Tunnel",
  "DESCRIPTION": "Tunnel shader with bass-driven motion and spectrum coloring",
  "CREDIT": "Converted from Shadertoy",
  "WIDTH": 1920,
  "HEIGHT": 1080,
  "TAGS": ["tunnel", "geometric", "bass-reactive"],
  "CONTROLS": [
    {
      "NAME": "speed",
      "TYPE": "slider",
      "DEFAULT": 0.5,
      "MIN": 0.0,
      "MAX": 2.0,
      "UI_GROUP": "Motion"
    },
    {
      "NAME": "bass_amount",
      "TYPE": "slider",
      "DEFAULT": 0.8,
      "MIN": 0.0,
      "MAX": 1.0,
      "UI_GROUP": "Audio"
    },
    {
      "NAME": "bass_threshold",
      "TYPE": "slider",
      "DEFAULT": 0.6,
      "MIN": 0.0,
      "MAX": 1.0,
      "UI_GROUP": "Audio"
    }
  ]
}
```

## Best Practices

1. **Always maintain motion without audio**: Shader should look good even in silence
2. **Audio enhances, not replaces**: Audio reactivity boosts existing movement, doesn't create it from scratch
3. **Use smoothstep for thresholds**: Prevents harsh on/off transitions
4. **Offer user control**: Let users adjust audio sensitivity via controls
5. **Test with different music**: EDM vs ambient vs rock should all work well
6. **Performance**: Keep shader efficient (target 60 FPS at 1920x1080)
7. **Use _uv instead of manual normalization**: Synesthesia provides optimized coordinates
8. **Prefer syn_BassTime over direct TIME multiplication**: More musical results

## Common Pitfalls

- ❌ Audio-only motion (boring in silence)
- ❌ Hard thresholds (use smoothstep instead)
- ❌ Overreacting to every audio change (too chaotic)
- ❌ Forgetting to handle PASSINDEX for multi-pass shaders
- ❌ Using deprecated texture2D (use texture instead)
- ❌ Not normalizing coordinates correctly
- ❌ Excessive uniform declarations (only declare what you use)

## References

- Full conversion guide: `docs/reference/isf-to-synesthesia-migration.md`
- Synesthesia docs: app.synesthesia.live
- ISF Spec: github.com/mrRay/ISF_Spec
- Built-in examples: Synesthesia app → custom library folder → stock scenes

## Output Format

When converting, provide:
1. Commented explanation of audio mapping choices
2. Complete `main.glsl` with all uniforms declared
3. Complete `scene.json` with controls
4. Optional `script.js` if needed
5. Testing notes (what to listen for, expected behavior)
