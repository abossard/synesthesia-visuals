# BWmoria_gears Study and Family Design Guide

## Scope
This document analyzes `BWmoria_gears` as implemented in:
- `/Users/abossard/Desktop/projects/synesthesia-visuals/swift-vj/Shaders/glsl/BWmoria_gears.txt`

It also cross-checks lineage online and translates the shader into a reusable design framework for new theme families.

## Verified Lineage (Local + Online)
- Local shader comments credit `srtuss, 2013` and describe a “cartoonish 2D” machine look.
- External mirror in `libretro/glsl-shaders` appears as `srtuss-industry.glsl` and explicitly references Shadertoy `Msf3D7`.
- The external mirror code matches the same core function stack: `hash`, `mechstep`, `voronoi`, `fan`, `gear`, `car`, `layerA`, `layerB`, and 5-layer depth composition.

References:
- [Local BWmoria_gears.txt](../../swift-vj/Shaders/glsl/BWmoria_gears.txt)
- [libretro `srtuss-industry.glsl`](https://github.com/libretro/glsl-shaders/blob/master/procedural/srtuss-industry.glsl)
- [Raw libretro source](https://raw.githubusercontent.com/libretro/glsl-shaders/master/procedural/srtuss-industry.glsl)
- [Shadertoy ID noted in mirror: `Msf3D7`](https://www.shadertoy.com/view/Msf3D7)

## What Makes This Shader Distinct
1. Binary shape compositing. Most objects are hard masks (`step` style), producing strong silhouette readability.
2. Mixed periodic and pseudo-random structure. Repeating rows are broken by seeded variation (`hash(si + seed * K)`).
3. Multi-layer faux depth. A loop stacks 5 procedural layers with scale-based depth cues and atmospheric blending.
4. Mechanical motion character. Rotation and carriage motion alternate between smooth and damped/jerky modes.
5. Minimal palette. Grayscale with depth fog does most of the visual storytelling.

## Code Anatomy

### 1) Utility + noise core
- `hash(float)` and `hash(vec2)`: deterministic pseudo-random values from trig hash.
- `voronoi(vec2)`: cell-space nearest-feature lookup over 3x3 neighbors; returns cell id + local offset vector.
- Why it matters: this creates segmented industrial wall/tile patterns and row variation without textures.

### 2) Motion personality
- `mechstep(x,f,r)`: shaped fractional stepping plus decaying sine “ringing.”
- This is the signature “back-and-forth machine inertia” feel: not purely sinusoidal, not purely linear.

### 3) Primitive motifs
- `gear(...)`: radial body + angular tooth modulation (`sin(atan*teeth + ang)`), clipped with hub hole.
- `fan(...)`: 3-blade rotor-like cutout built from polar sine + radial constraints.
- `car(...)`: tiny trolley/vehicle silhouette, two wheels + box body.

### 4) Layer functions
- `layerA(p, seed)`:
  - Background architecture lane.
  - Uses Voronoi gating + circular occluder + fan motif.
- `layerB(p, seed)`:
  - Foreground machinery lane.
  - Places moving trolley (`car`) and multiple meshing gears.
  - Randomly switches rotation profile between smooth and `mechstep` behavior.

### 5) Camera + parallax composition
- Camera drift: `cam = vec2(sin(t)*0.2, t)` gives forward conveyor travel with lateral sway.
- Global slight tilt: `rotate(p, sin(t)*0.02)` prevents static framing.
- Depth loop (`i=0..4`):
  - Alternates `layerB` and `layerA` by index.
  - Uses depth factor `f` derived from `z` to scale coordinates.
  - Blends each layer into `v` using exponential attenuation by depth.
- Final inversion `v = 1.0 - v` yields black machinery silhouettes over brighter fog bands.

## Why the Parallax Works
- Objects are not truly 3D; depth is implied by scale + blend weight + row-dependent offsets.
- Layers reuse similar rules but with different seeds, so depth feels coherent instead of random.
- The motion vectors are mostly vertical (forward travel) with slight horizontal oscillation, reading as “moving through a machine corridor.”

## Notable Differences vs External `srtuss-industry`
The local `BWmoria_gears` variant keeps the same architecture but adapts runtime conventions:
- Uses `time/resolution/gl_FragCoord` uniforms directly instead of Shadertoy wrapper inputs.
- Tiny geometry offsets in `car()` (wheel/body y offsets shifted slightly).
- “Quake” branch is present but effectively disabled (`* 0.0`).

## Family-Building Framework
Use this as a base architecture for all themed variants:

1. Keep the skeleton
- Keep `hash`, `voronoi` (or equivalent feature partition), and 4-6 layer depth loop.
- Keep alternating background/foreground layer roles.

2. Swap motif primitives
- Replace `gear/fan/car` with theme primitives (still as signed/implicit masks).
- Preserve hard mask readability for stage visuals.

3. Preserve motion dialect
- Keep one smooth oscillator and one damped/impulsive oscillator (`mechstep`-like).
- Route different primitives to different oscillators for perceived complexity.

4. Keep constrained palette logic
- Start with 1-channel value design (grayscale or two-tone), then colorize late.
- Depth tint/fog should follow layer index, not per-object random colors.

## Theme Recipes

### A) Gear Variants (industrial family)
- Motifs: gears, chains, pistons, belts, flywheels.
- Motion: meshing counter-rotation + intermittent clutch slips.
- Palette: graphite, steel, rust accent.
- Extra trick: occasional tooth skipping via phase jump to create “stress” moments.

### B) Water
- Motifs: ripple rings, foam cells, turbine vanes, bubble trails.
- Motion: low-frequency drift + high-frequency capillary shimmer.
- Palette: deep cyan to white foam, low saturation.
- Replace `gear()` with scalloped ring SDF; replace `car()` with buoy/float marker.

### C) Marine
- Motifs: propellers, hull ribs, sonar arcs, porthole circles.
- Motion: rolling sway + sonar pulse sweeps.
- Palette: navy, teal, brass highlights.
- Keep parallax lanes but make `layerA` look like bulkheads and `layerB` like moving deck machinery.

### D) Apocalypse
- Motifs: fractured plates, warning chevrons, smoke vents, broken cogs.
- Motion: jitter bursts + stalled starts + directional shake events.
- Palette: ash gray, ember orange, dirty yellow.
- Introduce mask erosion noise so silhouettes feel damaged.

### E) War
- Motifs: treads, target reticles, shell casings, radar sweeps.
- Motion: convoy-like linear travel with occasional recoil pulses.
- Palette: olive drab, gunmetal, dim red indicators.
- Add periodic scanline overlays synchronized with pulse events.

### F) Love
- Motifs: interlocking rings, petal gears, heart cams, orbiting nodes.
- Motion: breathing expansion + synchronized counter-rotation pairs.
- Palette: rose, coral, warm white, wine red.
- Convert sharp `step` edges to selective `smoothstep` for softer forms while keeping silhouette clarity.

## Reusable Parameter Set (for all descendants)
Standardize controls so one performance UI can drive the whole family:
- `uDepthLayers` (int): number of stacked layers.
- `uParallaxGain` (float): depth scale multiplier.
- `uFogFalloff` (float): depth attenuation curve.
- `uMotionSpeed` (float): global time multiplier.
- `uSwayAmount` (float): camera lateral movement.
- `uJerkAmount` (float): `mechstep` resonance strength.
- `uMotifDensity` (float): per-row motif count.
- `uDamage` (float): erosion/breakup amount (useful for apocalypse/war).
- `uRomanceSoftness` (float): edge softening (useful for love).

## Suggested First 12 Shader Names
- `BWmoria_gears_heavyforge`
- `BWmoria_gears_chainline`
- `BWmoria_gears_clutchstorm`
- `BWmoria_water_turbine`
- `BWmoria_water_undertow`
- `BWmoria_marine_bulkhead`
- `BWmoria_marine_sonarbay`
- `BWmoria_apoc_ashworks`
- `BWmoria_apoc_breakline`
- `BWmoria_war_convoygrid`
- `BWmoria_war_radarforge`
- `BWmoria_love_orbithearts`

## Online Technique References Used
- [Khronos GLSL `step`](https://registry.khronos.org/OpenGL-Refpages/gl4/html/step.xhtml)
- [Khronos GLSL `smoothstep`](https://registry.khronos.org/OpenGL-Refpages/gl4/html/smoothstep.xhtml)
- [The Book of Shaders - Shapes](https://thebookofshaders.com/07/)
- [The Book of Shaders - Noise](https://thebookofshaders.com/11/)
- [The Book of Shaders - More Noise / Cellular + Voronoi](https://thebookofshaders.com/12/)

## Practical Next Move
Implement one neutral “template descendant” first:
- Keep the exact layer loop and camera from `BWmoria_gears`.
- Expose the reusable parameter set above.
- Add one motif switch per layer (`industrial | water | marine | apoc | war | love`).

After that, each new shader is mostly motif + palette authoring, not architecture rewrites.
