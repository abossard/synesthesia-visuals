# Shader Centering Investigation (Dec 6, 2025)

## Problem Summary
- Circular GLSL shaders rendered through **VJUniverse** appear offset toward the bottom-left corner instead of being centered on screen.
- Issue persists even after implementing zoom and pan controls for shader navigation.
- Panning with arrow keys initially moved content in unexpected directions.
- Behavior occurs across multiple GLSL scenes; ISF scenes appear correctly centered.

## Observed Symptoms
1. Circular shaders render with their focal point anchored bottom-left.
2. Zoom and pan logic affect overall view, but offset bias remains.
3. Retained logs show numerous warnings about uniforms (normal for unused uniforms) alongside a persistent message: `The pixels array is null.`
4. When running on macOS Retina display, Processing warns `pixelDensity(2)` is active by default.

## Investigation Timeline
### 1. Initial Zoom/Pan Implementation
- Implemented `drawFullscreenQuad()` UV remap (now replaced) to account for zoom.
- Added `shaderZoom`, `shaderOffsetX`, and `shaderOffsetY` with keyboard controls.
- Result: zoom worked but centering still off; arrow pan direction felt reversed.

### 2. Offscreen Buffer Strategy
- Switched to two-stage render pipeline:
  - Render shader into `shaderBuffer` at native resolution.
  - Draw buffer with zoom/pan via `image(shaderBuffer, x, y, scaledW, scaledH)`.
- Added `shaderBuffer` initialization in `setup()` and `drawShaderBufferWithZoomPan()` helper.
- Result: Visuals respected zoom/pan transforms but core offset persisted.

### 3. Arrow Key Direction Fix
- Adjusted arrow key logic to interpret panning from the **viewer** perspective:
  - LEFT key increases `shaderOffsetX` (view pans left, content shifts right).
  - RIGHT key decreases offset, etc.
- Added console diagnostics to verify numeric offsets.

### 4. gl_FragCoord Macro Attempt (Rolled Back)
- Temporarily injected `#define gl_FragCoord _vj_flippedFragCoord()` in GLSL conversion to flip Y-axis.
- Determined approach unreliable: built-in variables shouldn’t be redefined; removed change.

### 5. Pixel Density Hypothesis
- Observed `pixelDensity(2)` warning; suspected mismatch between logical size (`width/height`) and physical pixels (`pixelWidth/pixelHeight`).
- Updated `applyShaderUniformsTo()` to pass physical dimensions via `pixelWidth/pixelHeight` (and `.pixelWidth/.pixelHeight` when rendering to PGraphics buffer).
- Despite change, offset persisted—suggesting additional state or coordinate mismatch still unresolved.

## External Research
- **Processing Reference** – [pixelWidth](https://processing.org/reference/pixelWidth.html) & [pixelDensity()](https://processing.org/reference/pixelDensity_.html)
  - Confirms hi-DPI displays double pixel count while logical `width/height` remain unchanged.
  - Recommends using `pixelWidth/pixelHeight` for pixel-based operations.
- No official documentation found indicating `gl_FragCoord` should be redefined; standard practice is to adjust uniforms or post-processing rather than macro substitution.

## Current State
- Project code now:
  - Renders through `shaderBuffer` with zoom/pan support.
  - Sends physical resolution (`pixelWidth`, `pixelHeight`) to shaders.
  - Provides correct pan direction via arrow keys.
- **Still unresolved**: primary focal point of many GLSL shaders remains offset bottom-left despite resolution adjustments.

## Potential Next Steps
1. **Inspect individual shader coordinate math**
   - Many Shadertoy ports compute `vec2 uv = (gl_FragCoord.xy / resolution.xy);` and then remap `uv = uv * 2.0 - 1.0;`
   - Verify if import pipeline wraps code with additional transforms (e.g., mixing `_uv`, `_xy`).

2. **Verify shaderBuffer pixel density**
   - Confirm PGraphics inherits main sketch density.
   - Consider explicitly setting `shaderBuffer.pixelDensity(displayDensity());` after creation.

3. **Check OpenGL matrix state**
   - Ensure no scaling/translation remains on PGraphics when drawing quads.
   - Validate `textureMode(NORMAL);` and `imageMode(CORNER);` usages.

4. **Debug by overlaying reference grid**
   - Render debug crosshair or coordinate markers via shader uniforms to inspect how coordinates map across the screen.

5. **Profile with simpler shader**
   - Craft minimal shader that outputs `gl_FragCoord / resolution` as colors (R=X, G=Y) to observe mapping visually.

## Files Modified During Investigation
- `processing-vj/src/VJUniverse/VJUniverse.pde`
  - Added shader buffer pipeline, zoom/pan helpers, arrow key fixes, and resolution uniform adjustments.
- `processing-vj/src/VJUniverse/ShaderManager.pde`
  - Temporary macro injection (removed) and general GLSL conversion tweaks.

## Open Questions
- Does `shaderBuffer` require explicit `beginDraw()`/`endDraw()` around zoom stage to synchronize hi-DPI pixels?
- Are certain GLSL scenes using previously cached conversions ignoring updated uniforms?
- Does `glslSource` already include coordinate flips that interact with our buffer transformations, causing compounded offsets?

## Summary
Despite multiple refinements—buffer-based zoom/pan, arrow key corrections, and aligning shader resolution with physical pixel density—the circular GLSL shaders continue to render off-center. Evidence suggests a deeper mismatch between shader coordinate math and Processing’s hi-DPI rendering pipeline. Further debugging (coordinate visualizations, shader-by-shader analysis, verifying PGraphics density) is recommended to isolate the root cause.

---

## Planned HiDPI Fix (for future implementation)

**Goal:** Render GLSL shaders that rely on `gl_FragCoord` perfectly centered on Retina/HiDPI displays while keeping the original shader code untouched. The fix hinges on giving every render surface the same pixel density and sending physical pixel dimensions (`pixelWidth`, `pixelHeight`) through the `resolution` uniform.

### 1. Configure density once
- After `size(...)`, call `pixelDensity(displayDensity())` so the main sketch uses the display’s physical pixel grid.
- When creating offscreen buffers (e.g. `shaderBuffer = createGraphics(width, height, P2D);`) immediately set `shaderBuffer.pixelDensity(displayDensity());` so its pixel grid matches the main canvas.

### 2. Pass physical resolution to shaders
- When setting uniforms, derive `(pw, ph)` from the surface actually running the shader:
  - Main sketch: `pw = pixelWidth`, `ph = pixelHeight`.
  - Offscreen buffer: `pw = pg.pixelWidth`, `ph = pg.pixelHeight`.
- Send `resolution = vec2(pw, ph)` to every shader that uses pixel coordinates. Scale mouse input similarly if the shader expects pixel space.

### 3. Render pipeline with zoom/pan
1. Render the shader into the hi-DPI `shaderBuffer` inside `beginDraw()/endDraw()`, drawing a fullscreen rect while the shader is active.
2. Draw the buffer back to the main sketch via `image(shaderBuffer, x, y, scaledW, scaledH)` (your existing zoom/pan stage). Because pixel densities now match, no extra adjustments are needed here.

### 4. Shader code stays untouched
- Leave `gl_FragCoord` as-is; the key is that `resolution` reflects the correct physical size.
- Distance checks such as `length(center - gl_FragCoord.xy)` will now map correctly as long as centers are computed from the same `resolution`.

### 5. Implementation checklist
1. Call `pixelDensity(displayDensity())` in `setup()` or `settings()`.
2. After `createGraphics`, call `.pixelDensity(displayDensity())` on the buffer.
3. Use `(pixelWidth, pixelHeight)` or `(pg.pixelWidth, pg.pixelHeight)` for the `resolution` uniform.
4. Do **not** redefine `gl_FragCoord`; let the shader use the native coordinates.
5. Always wrap buffer drawing in `beginDraw()/endDraw()` before presenting via `image()`.

With these adjustments in place, all `gl_FragCoord`-based shaders should center correctly on Retina displays while preserving your original GLSL code.
