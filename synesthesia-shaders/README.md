# Synesthesia Shaders

This folder contains Synesthesia scene files (`.synScene`) and extracted shaders for VJ performances.

## Contents

### Scene Files
- `base_warp.synScene` - Base warp effect
- `colordiffusionflow.synScene` - Color diffusion flow
- `comicrun.synScene` - Comic run effect
- `fluid_1.synScene` - Fluid simulation
- `fluid_noise_pixel.synScene` - Fluid noise pixel effect
- `global_win.synScene` - Global win effect
- `moon.synScene` - Moon scene
- `oceanic.synScene` - Oceanic effect
- `simple_greeble.synScene` - Simple greeble
- `voxel.synScene` - Voxel effect

### Extracted Shaders
The `shaders_extracted/` folder contains shaders exported from various sources.

### Utilities
- `extract_shaders.sh` - Script to extract shaders from scenes
- `store_shadertoy.sh` - Script to store Shadertoy shaders

## Usage

1. Copy `.synScene` folders to your Synesthesia library folder
2. Open Synesthesia and enable the custom library
3. Find scenes in the library browser

## Creating New Scenes

See [ISF to Synesthesia Migration Guide](../docs/isf-to-synesthesia-migration.md) for converting shaders from ISF or Shadertoy formats.

## Audio Reactivity

All scenes can use Synesthesia's built-in audio uniforms:
- `syn_BassLevel`, `syn_MidLevel`, `syn_HighLevel` - Frequency band levels
- `syn_BassHits`, `syn_MidHits`, `syn_HighHits` - Transient detection
- `syn_BPM`, `syn_BeatTime` - Beat synchronization

See the migration guide for full audio uniform documentation.
