# ISF to Synesthesia Migration Guide

## References

- Synesthesia Docs: GLSL Resources, SSF Standard Uniforms, SSF Audio Uniforms, JSON Configuration (app.synesthesia.live)
- Synesthesia Docs: SSF Audio Uniforms, Standard Uniforms, Functions, JSON Configuration (app.synesthesia.live)
- "How to use the Shadertoy and ISF Converters in Synesthesia" by Theron Pray (Medium, 2017)
- ISF Specification v2.0 (github.com/mrRay/ISF_Spec)
- Local reference scenes: `alien_cavern_dup.synScene` (working SSF) and `colordiffusionflow.synScene/original` (ISF source)
- Audio-reactive reference: `audio_indicators_dup.synScene` (Synesthesia stock example)

## Format at a Glance

- **ISF**
  - Single `.fs` fragment shader (optional `.vs`) with leading JSON comment describing metadata, `INPUTS`, `PASSES`, `IMPORTED` assets.
  - Built-in uniforms such as `TIME`, `TIMEDELTA`, `DATE`, `FRAMEINDEX`, `RENDERSIZE`, `isf_FragNormCoord`, `PASSINDEX`.
  - Helper macros (`IMG_PIXEL`, `IMG_NORM_PIXEL`, `IMG_SIZE`) plus auto-generated uniforms for declared inputs.
- **Synesthesia SSF**
  - `.synScene` directory containing `main.glsl`, `scene.json`, optional `script.js`, `images/`, pass targets, thumbnails.
  - Standard uniforms (e.g., `TIME`, `RENDERSIZE`, `_xy`, `_uv`, `PASSINDEX`) plus extensive audio-driven uniforms (`syn_Level`, `syn_BassTime`, `syn_BPM`, etc.).
  - Built-in helper functions (`_palette`, `_loadMedia`, `_pixelate`, `_gamma`, etc.) and JavaScript hook (`script.js`) for custom state.

### Core Uniform Mapping Cheat-Sheet

Shadertoy → SSF:

- `iResolution.xy` → `RENDERSIZE.xy`
- `iTime` / `iGlobalTime` → `TIME`
- `iFrame` → `FRAMECOUNT`
- `iMouse` → `_mouse`
- `fragCoord` → use `_xy` (pixel) or `_uv` (normalized)
- `iChannel0..3` (media/textures) → `syn_Media` or pass targets / images (import manually) / custom sampler defined in `scene.json`.
- `texture(iChannelX, uv)` when auto import fails → add to `IMAGES` or a pass target then `texture(channelName, uv)`.

ISF → SSF:

- `isf_FragNormCoord` → `_uv`
- `TIME` (same) / `DATE` (not provided; substitute `TIME` or scripted clocks)
- `PASSINDEX` (same)
- `RENDERSIZE` (same)
- `INPUTS` → `CONTROLS` (slider / xy / color / toggle / dropdown)
- `IMG_PIXEL(name, coord)` / `IMG_NORM_PIXEL(name, normCoord)` → `texture(name, coord)` (ensure coordinate normalization yourself)
- Persistent buffers → Syn `PASSES` entries with `FLOAT: true` + optionally feedback via `syn_FinalPass`.

## Import & Conversion Workflow

- Prefer Synesthesia's Import tab → ISF Converter for first-pass translation (Medium tutorial). The tool rewrites uniforms, extracts controls, and scaffolds `scene.json`.
- Conversion fails when ISF relies on unsupported features (custom vertex shaders, `audio/audioFFT/long` input types, host-specific buffers). Even failed imports yield a `.synScene` skeleton for manual fixes.
- After successful import, click "create .synScene in library" to persist the scene; use Edit Scene to tweak GLSL/JSON/JS assets.

### Manual Shadertoy Conversion (Summary)

- Start from the video tutorial (Synesthesia Docs: Shadertoy manual conversion). Use auto converter first; fall back to manual if compilation fails.
- Replace Shadertoy main signature `void mainImage(out vec4 fragColor, in vec2 fragCoord)` with SSF pattern `vec4 renderMain(){ ... }` or multipass structure.
- Swap coordinate math: `vec2 uv = fragCoord / iResolution.xy;` → `vec2 uv = _uv;`
- Convert mouse references: `iMouse.xy / iResolution.xy` → `_muv` (normalized) or use raw `_mouse.xy` for pixel.
- Handle iChannel usage:
  - If channel is used for keyboard/webcam/audio not supported, remove or gate code.
  - For textures used as buffers, define `PASSES` and sample named targets.
  - For video/image channels, prefer Syn user media (`_loadMedia()`, `_textureMedia(uv)`), or add to `IMAGES` list.
- Remove `#ifdef GL_ES` blocks (not required) & replace deprecated `texture2D` with `texture`.
- Add audio reactivity by mixing scene colors or motion with `syn_*` uniforms (Shadertoy originals lack built-in audio).
- Adjust resolution if performance drops: set `WIDTH/HEIGHT` to 768x432 or 1280x720 if shader was authored for smaller size.

### Multipass Translation Notes

- Shadertoy buffers each own code + `iChannel0..3`; Synesthesia merges everything into one `main.glsl` and switches logic with `PASSINDEX`. Declare globals/functions once and branch per pass instead of duplicating definitions.
- Every Syn pass shares the same sampler uniforms, so name collisions like "two different iChannel0" disappear. Use meaningful sampler names (`bufferA`, `feedback`) in `scene.json` `PASSES` and reference them directly inside GLSL.
- When the importer fails, manually wrap each former buffer in `if (PASSINDEX == index) { ... }` and return a `vec4`. Remember that Syn expects a value from every branch; `return;` is invalid.

#### DotCamera Workflow Example

1. Enable the built-in Scene Editor, set at least one custom library folder, and mark it `primary` so new imports land there.
2. Import the Shadertoy via the sidebar; even if compilation fails, press “create .synScene in library” to capture the converted scaffolding (pass list, textures, controls).
3. Open the scene in the editor, read the console error, and fix type issues. In DotCamera the importer left `return;` in a function that now must return `vec4`, so change it to `return O;` (or whatever color variable you accumulated) and reload. Iterate on other buffer-specific fixes until all PASSINDEX branches compile.

### Manual ISF Conversion (Additional Notes)

- Strip JSON header from top of `.fs` and transplant metadata into `scene.json` root keys.
- Merge multiple passes: ISF `PASSES` entries become `scene.json` `PASSES`. Each ISF pass `TARGET` maps directly; persistent flags become `FLOAT: true` and reuse of pass outputs.
- Vertex shader: if present and only calls `isf_vertShaderInit()`, discard; otherwise emulate transformation in fragment code using coordinate warps.
- Replace unsupported audio inputs (`audio`, `audioFFT`) with `syn_Spectrum` and `syn_LevelTrail` texture sampling or simpler level uniforms.
- Convert date/time uses of `DATE.w` to `TIME` or scripted timers in `script.js`.

### Unsupported / Gotchas

- Shadertoy VR, microphone, Soundcloud, keyboard inputs → remove or replace logic.
- ISF custom vertex + geometry passes → reimplement in fragment space (raymarch, screenspace transformations).
- Integer `long` inputs → Syn `dropdown` with `LABELS` + `VALUES`.
- Large loops or heavy `for` with dynamic indexing can exceed GPU limits at 1080p; consider reducing iterations or rendering intermediate passes at lower resolution.

## Anatomy of a Synesthesia Scene (based on `alien_cavern_dup`)

- `main.glsl`: implements `renderMain()` per pass, uses Syn uniforms (`syn_BassTime`, `_xy`, `_uvc`, `syn_FinalPass`).
- `scene.json`: defines metadata, resolution, tags, control widgets mapped to uniforms (toggles, sliders, XY pads, etc.).
- `script.js`: optional per-frame logic (BPM counters, smoothing timers) writing into `uniforms.*` names consumed by GLSL.

## Mapping ISF Concepts to SSF

- **Coordinates**: replace `isf_FragNormCoord` with `_uv`; `gl_FragCoord` equivalents `_xy`; use `_uvc` for aspect-correct math.
- **Time**: ISF `TIME` ported directly; Syn also offers `syn_Time`, `syn_BPMTwitcher`, beat clocks for richer motion.
- **Passes**: ISF `PASSES` → `scene.json` `PASSES` array; each defines `TARGET`, `WIDTH`, `HEIGHT`, `FLOAT`, `WRAP`, `FILTER`. Access buffers via named sampler uniforms inside `main.glsl`.
- **Inputs/Controls**: ISF `INPUTS` entries (float, point2D, color, event) map to Syn controls (slider, xy, color, bang). Copy default/min/max ranges to `scene.json` control objects; add `UI_GROUP` strings for layout.
- **Images & Media**: ISF `IMPORTED` assets → Syn `images/` folder plus `IMAGES` array. For dynamic media, prefer `syn_Media` texture or `_loadMedia()` helper.
- **Vertex Shaders**: Synesthesia currently ignores ISF `.vs` files. Recreate vertex-side logic in fragment code (fullscreen quad) using math/compositing instead.
- **Audio Inputs**: ISF `audio`/`audioFFT` inputs are unsupported; instead, drive behavior with SSF audio uniforms (`syn_BassLevel`, `syn_HighHits`, `syn_Spectrum`, `syn_LevelTrail`).

### Extended Uniform Mapping Table (Audio)

- Loudness Bands: `syn_Level`, `syn_BassLevel`, `syn_MidLevel`, `syn_MidHighLevel`, `syn_HighLevel` (0–1 smoothed amplitudes).
- Hits (Transients): `syn_BassHits`, `syn_MidHits`, `syn_MidHighHits`, `syn_HighHits` (single-frame spike envelopes, good for flash triggers).
- Presence (Structural energy): `syn_BassPresence`, etc. (slow-moving; use in palette shifts).
- Time Accumulators: `syn_Time`, band-specific times `syn_BassTime`… (speed up motion only when frequency band active).
- Beat Tools: `syn_OnBeat`, `syn_ToggleOnBeat`, `syn_RandomOnBeat`, `syn_BeatTime` (discrete beat events) vs BPM family `syn_BPM`, `syn_BPMTwitcher`, `syn_BPMSin`, `syn_BPMSin2/4`, `syn_BPMTri` variants.
- Spectrum Textures: `syn_Spectrum` is a **sampler1D** — use `texture(syn_Spectrum, freq)` where `freq` is a single float (0.0–1.0 across frequency bins). Channels: r=raw FFT, g=juiced FFT, b=smooth FFT, a=waveform.
- Level History Texture: `syn_LevelTrail` is a **sampler1D** — use `texture(syn_LevelTrail, x)` where `x` is time position. Channels: r=full, g=bass, b=mid, a=high.

## Manual Migration Checklist

1. **Extract Metadata**: copy ISF JSON (`TITLE`, `CREDIT`, `CATEGORIES`) into `scene.json`. Preserve licensing notes in `DESCRIPTION`.
2. **Port Controls**: translate each ISF `INPUTS` record to a Syn control:
   - `float` → `slider` (optionally `slider smooth` mirroring ISF smoothing intent).
   - `point2D` → `xy` control with `[min, max]` arrays.
   - `bool/event` → `toggle` or `bang` (use `bang smooth` to mimic envelopes).
   - `color` → `color` control with `DEF_COLOR` for defaults.
   - `long` → `dropdown` with `LABELS`/`VALUES` pairs.
3. **Normalize Uniform Names**: remove `uniform` declarations for controls—Syn auto-injects them. Replace `IMG_PIXEL`/`IMG_NORM_PIXEL` with GLSL `texture()` calls on the provided sampler.
4. **Rewrite Entry Point**: instead of `main()` assigning `gl_FragColor`, define `vec4 renderMainImage()` (or multi-pass functions) returning a color; `renderMain()` selects pass output based on `PASSINDEX`.
5. **Handle Media Inputs**: convert `inputImage`-style samplers to either Syn media textures or pass targets defined in `scene.json`.
6. **Add Audio Reactivity**: optionally augment visuals using `syn_*` uniforms (e.g., `syn_BassHits` for flashes) to leverage Syn's live music analysis.
7. **Scripted State**: if ISF used timers or host-provided toggles, recreate state machines in `script.js` (see BPM counter example in `alien_cavern_dup`). Write into `uniforms.myValue` for GLSL consumption.
8. **Testing**: load the scene in Synesthesia, enable Stats overlay, and trim `WIDTH`/`HEIGHT` in `scene.json` if performance drops below target FPS. Validate controls map to expected uniforms.

## Audio Reactivity Patterns

- **Uniform Categories**: leverage the audio uniforms documented at `app.synesthesia.live/docs/ssf/audio_uniforms.html`. Levels (`syn_BassLevel`, `syn_Level`), hits (`syn_BassHits`, `syn_HighHits`), timekeepers (`syn_BassTime`, `syn_BeatTime`, `syn_BPMTwitcher`), and presence (`syn_Presence` bands) cover most reactive cases without writing your own FFT.
- **Data Textures**: read `syn_Spectrum` (FFT/waveform) and `syn_LevelTrail` (history buffers) via `texture`/`texelFetch` for detailed analyzers, as shown in `audio_indicators_dup.synScene` slot rendering logic.
- **Script Hooks**: use `script.js` to build bespoke envelopes or trackers by sampling `inputs.syn_*` uniforms and writing smoothed values into `uniforms.*`. The `audio_indicators_dup` script demonstrates peak-tracking by mixing `inputs.syn_InputLevel` each frame.
- **Media + Audio Hybrid**: combine `_loadMedia()` layers with audio-driven masks to keep visuals tied to the song; consider gating `syn_Media` contributions with `syn_FadeInOut` or `syn_Intensity` for set transitions.
- **Best Practices**: clamp or smooth aggressive hits (e.g., `mix(val, prev, 0.9)`) to avoid flicker; expose multipliers via controls so users can retune responsiveness; document which audio uniforms drive each effect in `scene.json` descriptions.

### Advanced Audio Techniques

- **Multi-Band Blending**: weight visual layers by normalized band energies: `col = mix(baseCol, fxCol, syn_BassPresence*0.5 + syn_HighHits*0.5);`
- **Beat-Synced Easing**: use `float beatPhase = fract(syn_BPMTwitcher); float eased = smoothstep(0.0,1.0, beatPhase);` for smooth parameter ramps per beat.
- **Procedural Camera**: accumulate `camDist += (syn_BassLevel*0.6 + syn_MidHighLevel*0.3)*dt;` for organic travel tied to arrangement intensity.
- **Spectral Displacement**: sample `float band = texture(syn_Spectrum, uv.y).g; uv.x += band*0.02;` for waveform-based warps.
- **Trail-Based Fading**: `float trailMask = texture(syn_LevelTrail, uv.x).g; col *= mix(0.5,1.5, trailMask);` for evolving brightness.
- **Beat Jitter**: `uv += (syn_OnBeat)*_rotate(vec2(0.01,0.0), TIME*10.0);` subtle camera shake only on beats.
- **Palette Cycling**: `float palIdx = syn_RandomOnBeat; vec3 dynCol = _palette(palIdx, a,b,c,d);` ties random palette shift per beat.

### Scripting Patterns (`script.js`)

- **Peak Tracker**: compare current level to stored peak and decay: `peak = (cur>peak)?cur:mix(peak, cur, 0.05); uniforms.peak = peak;`
- **Logistic Smoothing**: `val = old + (target-old)*(1.0-exp(-speed*dt));` stable transitions for BPM-aligned motions.
- **Adaptive Sensitivity**: adjust sensitivity based on intensity: `sensitivity = mix(0.3,1.0,syn_Intensity); uniforms.hitScale = syn_HighHits*sensitivity;`
- **Beat Gate**: use `if (inputs.syn_OnBeat > 0.5) trigger();` to sync script-side state changes (cycling modes, toggling control families).

### Control Design for Audio

- Provide a master `audio_reactivity` slider (0–1) multiplying all audio uniform contributions (`finalCol = mix(baseCol, reactiveCol, audio_reactivity);`).
- Offer band emphasis sliders: `bass_emphasis`, `high_emphasis` weighting the respective uniforms.
- Add smoothing parameter controls for `presence_smooth` to adjust response tail lengths.

## Common Pitfalls & Fixes

- **Custom Vertex Logic**: replicate camera transforms using fragment math (raymarch camera, UV warps). Analyze original `.vs` for intent; many ISF vertex shaders only call `isf_vertShaderInit()` and can be ignored.
- **Deprecated Functions**: replace `texture2D` with `texture`, ensure final alpha channel is set (Syn compositing expects `fragColor.a = 1.0`).
- **Unsupported Inputs**: remove ISF `audio/audioFFT/long` dependencies or rewrite to use SSF audio uniforms and `scene.json` dropdowns.
- **Precision**: Match ISF persistent buffers by setting Syn pass `FLOAT: true` and `WRAP/FILTER` values. Use `_gamma()` or manual tonemapping to align color output.
- **Control Ranges**: Syn clamps slider values to `[MIN, MAX]`. Verify ISF `MIN/MAX` order—some legacy shaders swap them (converter may invert toggles).

### Performance & Optimization

- **Resolution Strategy**: Lower non-final passes (`WIDTH/HEIGHT`) to fractions (e.g., 960x540) for expensive blurs or iterative noise while keeping main output at 1080p.
- **Float Pass Use**: Use `FLOAT: true` only for passes storing high dynamic range or iterative accumulation; prefer default RGBA8 for simple color transforms.
- **Loop Bounds**: Replace `for(int i=0;i<256;i++)` with dynamic early exit or fewer samples scaled by audio activity (`int steps = int(mix(40.0,120.0,syn_Intensity));`).
- **Branch Minimization**: Precompute audio-driven masks, avoid nested `if` inside heavy loops; use mix/step functions.
- **Texture Sampling**: Prefer single `texture(syn_Spectrum, freq)` reuse across code branches; store to local variable. Note: `syn_Spectrum` and `syn_LevelTrail` are **sampler1D** — pass a single `float`, not `vec2`.
- **Smoothing vs Responsiveness**: Excess smoothing of hits reduces energy; balance by mixing raw `syn_BassHits` & smoothed `tracker` variables.
- **Gamma/Contrast**: finalize output with `_gamma()` or `_contrast()` before post-effects to minimize banding at low light.

### Troubleshooting Import Failures

- **Undeclared Identifiers**: Usually leftover Shadertoy/ISF variables (`DATE`, `iChannelX`, `IMG_PIXEL`). Replace with SSF equivalents or create controls.
- **Red Compilation Errors After Control Add**: Reload scene so engine re-reads `scene.json`; ensure control `NAME` matches shader symbol exactly.
- **Black Output**: Check alpha—set `fragColor.a = 1.0`; ensure not multiplying color by zeroed audio uniforms (add floor like `max(syn_Level,0.05)`).
- **Performance Collapse**: Profile by temporarily disabling audio branches; narrow culprit loops or multi-pass chain; reduce pass resolutions.
- **Media Sampling Distortion**: Use `_correctMediaCoords(uv)` or `_textureMedia(uv)` for aspect-correct sampling instead of raw `texture(syn_Media, uv)`.
- **Media Tiling/Repeating**: If media appears multiple times on screen, check `scene.json` `MEDIA` array — set `"WRAP": "clamp"` instead of `"repeat"` to display a single instance.

### Licensing & Attribution

- Preserve original author credit & license text at top of ported shader (`scene.json` `CREDIT`, `DESCRIPTION`).
- If license unspecified (common Shadertoy cases), treat as All Rights Reserved until you secure permission.
- Avoid removing license comments when restructuring code; add a conversion note referencing source URL and conversion date.
-- Mark modified sections with concise conversion comments only if needed (do not flood code; keep performance intact).


### Final Migration Checklist (Condensed)

1. Collect source URL & license → add metadata.
2. Run auto import (Shadertoy/ISF) → if fail, manual steps.
3. Map uniforms & coordinates using cheat-sheet.
4. Create/adjust controls; group logically; set smooth variants where beneficial.
5. Add audio reactivity core (color flash, motion) + deeper behaviors (presence shifts, BPM sync).
6. Optimize passes & loops; verify 60fps target (or acceptable performance) at intended resolution.
7. Validate alpha, color range, and dynamic range corrections.
8. Script advanced trackers if needed; expose tuning controls.
9. Document audio inputs & major controls in `scene.json` descriptions.
10. Final test across varied music (bass-heavy vs high-frequency) to ensure balanced reactivity.

## AI Guidance Notes

- Favor embedding related uniforms to minimize Syn cross-partition queries (per Cosmos best practices) when designing control hierarchies.
- When generating migrations automatically, script extraction of ISF JSON with a parser to avoid brittle regex.
- Build prompts that remind AI agents to:
  - Respect licensing comments at top of ISF files.
  - Check for unsupported ISF types early (vertex shaders, audio inputs).
  - Map every ISF input to a Syn control or drop with rationale, preventing orphaned uniforms.
  - Suggest audio reactivity hooks post-port, since ISF scenes default to silent visuals.

## Source Notes

- Synesthesia Import guidance and unsupported feature list summarized from Theron Pray's Medium article.
- Syn standard/audio uniforms, JSON schema, helper functions from app.synesthesia.live documentation.
- ISF auto-uniforms, helper macros, and format rules from ISF Specification v2.0 repository.
- Practical differences validated against provided `alien_cavern_dup.synScene` and `ColorDiffusionFlow.fs` examples.
