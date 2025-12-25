# ISF Shaders from bareimage/ISF Repository

This collection contains 62 high-quality Interactive Shader Format (ISF) shaders from Igor Molochevski's [bareimage/ISF](https://github.com/bareimage/ISF) repository, organized into 5 release folders.

## 📋 Attribution

**Repository**: https://github.com/bareimage/ISF  
**Author**: Igor Molochevski (@dot2dot / @bareimage)  
**Primary Converter**: @dot2dot (bareimage) - ISF 2.0 conversions with persistent buffer enhancements  
**Testing Platform**: macOS M1 MacBook Pro with VDMX

## ⚖️ Licensing

These shaders are covered by **two different licenses**:

### Creative Commons Attribution-NonCommercial-ShareAlike 3.0 (CC-BY-NC-SA 3.0)
- **Most shaders** in this collection use this license
- ✅ **Can be used for**: Personal projects, non-commercial VJ performances, educational purposes
- ❌ **Cannot be used for**: Commercial productions or paid gigs
- 📄 **License details**: http://creativecommons.org/licenses/by-nc-sa/3.0/
- **Requirements**:
  - Attribution: Credit original authors
  - ShareAlike: Derivatives must use the same license
  - NonCommercial: No commercial use without permission

### MIT License
- **Select shaders** are MIT licensed (noted in shader comments)
- ✅ **Can be used for**: Any purpose including commercial productions
- 📄 **License details**: Open source permissive license

**⚠️ Important**: Check the license in each shader file's header comments before using in commercial projects. Contact original authors if you need commercial rights for CC-BY-NC-SA licensed shaders.

## 🎨 What are ISF Shaders?

**ISF (Interactive Shader Format)** is a standardized file format built on GLSL that enables hardware-accelerated visual effects to run across desktop, mobile, and WebGL platforms. ISF extends GLSL by providing:

- Standardized metadata for adjustable properties
- Support for multiple rendering passes
- **Persistent buffers** for frame-to-frame memory
- Compatibility across VJ software (VDMX, CoGe, MadMapper, Smode, etc.)

## 🔑 Key Features of This Collection

### Persistent Buffer Technology
Unlike traditional shaders that "reincarnate" each frame, these shaders use **persistent buffers** to:
- Create smooth parameter transitions independent of animation speed
- Build up effects over time
- Maintain state between frames
- Enable sophisticated feedback effects

### Enhanced Controls
All shaders feature:
- ⏱️ **Smoothed speed transitions** - Adjust animation speed without affecting position
- 🎛️ **Dampened parameter controls** - Smooth transitions when changing settings
- 🎨 **Multiple color palettes** - Many shaders include 15-25+ color schemes
- 🎵 **Audio reactivity** - Some shaders support audio input (VDMX compatible)

## 📁 Repository Structure

```
ISF-bareimage/
├── Release.1/    (10 shaders) - Initial release with waves, fractals, and cosmic effects
├── Release.2/    (12 shaders) - Raymarchers, tunnels, portals, and Truchet patterns
├── Release.3/    (11 shaders) - Advanced fractals with symmetry and turbulence
├── Release.4/    (19 shaders) - Twigl conversions, volumetric effects, audio-reactive
└── Release.5/    (10 shaders) - Metaballs, voxel cubes, and kaleidoscope effects
```

---

## 📖 Shader Catalog by Release

### Release.1 (10 Shaders) - Waves, Fractals & Cosmic Effects

#### IM-EthernalWaves-Star.fs
**Description**: Ethereal waves with smooth parameter transitions  
**Credit**: Original by @iapafoto, converted to ISF by dot2dot  
**License**: CC-BY-NC-SA 3.0  
**Features**: Wave amplitude/frequency control, fractal detail, color intensity

#### IM-ForkTruchet-Final.fs
**Description**: Truchet Pattern Generator with smooth transitions  
**Credit**: Converted to ISF 2.0 by dot2dot, original by @liu7d7 (Shadertoy)  
**License**: CC-BY-NC-SA 3.0  
**Features**: Procedural tile patterns, kaleidoscope effects

#### IM-FractalSpeedSmooth.fs
**Description**: Raymarched fractal sphere deformation with adjustable, smoothed speed using virtual time  
**Credit**: Original logic from isf.video (various authors), ISF conversion by @dot2dot  
**License**: CC-BY-NC-SA 3.0  
**Features**: Virtual time system, independent speed control

#### IM-FractalTorusv2.fs
**Description**: Fractal Torus with Neon Colors and Rotation Controls  
**Credit**: Converted from isf.video by @dot2dot  
**Features**: 3D rotation controls, neon color schemes

#### IM-KBMARCHER-DAMPENING.fs
**Description**: Converted Shadertoy shader with smoothed speed, rotation transitions, and zoom controls  
**Credit**: Converted to ISF 2.0 by dot2dot, original code by @ufffd (Shadertoy)  
**License**: CC-BY-NC-SA 3.0  
**Features**: Raymarching, dampened controls

#### IM-PlatonicSolidsFinal.fs
**Description**: Self Reflection with dampened manual rotations only  
**Credit**: Converted to ISF 2.0 by dot2dot, original by @mrange (Shadertoy)  
**License**: CC-BY-NC-SA 3.0  
**Features**: Platonic solid geometry, reflection effects

#### IM-SWIRL-SmoothTransition.fs
**Description**: Converted Shadertoy shader with smoothed speed and rotation transitions  
**Credit**: Converted to ISF 2.0 by dot2dot, original by SnoopethDuckDuck (Shadertoy)  
**License**: CC-BY-NC-SA 3.0  
**Note**: Must be rendered in desktop app

#### IM-SunsetXorDev.fs
**Description**: Sunset effect with smooth parameter transitions  
**Credit**: Original by @XorDev, converted to ISF by dot2dot  
**License**: CC-BY-NC-SA 3.0  
**Features**: Atmospheric rendering, color gradients

#### IM-WEIRD_BLOB1.fs
**Description**: 3D Fractal Hourglass with Random Blobs  
**Credit**: Created by dot2dot  
**License**: CC-BY-NC-SA 3.0  
**Features**: Experimental blob rendering

#### IM-XOR-Circle-Advance.fs
**Description**: Cosmic shader with true circular discs, full 3D rotation, and smooth parameter transitions  
**Credit**: Original by @XorDev, converted to ISF 2.0 by dot2dot  
**License**: CC-BY-NC-SA 3.0  
**Features**: Circular geometry, 3D rotation

---

### Release.2 (12 Shaders) - Raymarchers, Tunnels & Portals

#### IM-CosmicRayMarcher.fs
**Description**: Cosmic Ray Marcher with smooth transitions  
**Credit**: Code by @XorDev, ISF 2.0 Version by @dot2dot  
**License**: CC-BY-NC-SA 3.0  
**Features**: Advanced raymarching techniques

#### IM-EsherPortal.fs
**Description**: Portal Terrain Effect with Escher-like distortions and smooth parameter transitions  
**Credit**: Original Shadertoy by @tmst, ISF 2.0 Version by @dot2dot  
**License**: CC-BY-NC-SA 3.0  
**Features**: Droste effect, terrain noise, camera orbit control

#### IM-Flowers.fs
**Description**: Organic 3D Pattern (taste of noise 7) with smooth parameter transitions and temporal feedback  
**Credit**: Original by @leon_denise, ISF 2.0 Version by @dot2dot  
**License**: CC-BY-NC-SA 3.0  
**Features**: Organic patterns, noise-based generation

#### IM-GLowHeart.fs
**Description**: Animated heart with smooth transitions  
**Credit**: Original code by @arlo (Shadertoy), ISF 2.0 by @dot2dot  
**License**: CC-BY-NC-SA 3.0  
**Features**: Heart shape animation, glow effects

#### IM-GlassFractalFlightTwist.fs
**Description**: Abstract fractal patterns with smoothed speed, rotation, and parameter transitions  
**Credit**: Based on code by @diatribes (Shadertoy), ISF 2.0 by @dot2dot  
**License**: CC-BY-NC-SA 3.0  
**Features**: Glass-like effects, twist perturbation, brightness protection

#### IM-RayLab.fs
**Description**: 3D Tunnel Effect with Smooth Parameter Transitions  
**Credit**: ISF 2.0 by @dot2dot, Original by @zguerrero (Shadertoy)  
**License**: CC-BY-NC-SA 3.0  
**Features**: Tunnel raymarching

#### IM-RayTunnel-Metal.fs
**Description**: 3D Tunnel Effect with Smooth Parameter Transitions and Radial Blur (VDMX-Compatible)  
**Credit**: Original by @zguerrero, ISF 2.0 adaptation & Metal conversion by @dot2dot  
**License**: CC-BY-NC-SA 3.0  
**Features**: Metal shader optimizations, radial blur

#### IM-RhodiumLquidCarbon.fs
**Description**: Alcatraz / Rhodium liquid carbon effect with parameter smoothing and DoF  
**Credit**: Original ShaderToy by Jochen 'Virgill' Feldkötter, ISF by @dot2dot  
**License**: CC-BY-NC-SA 3.0  
**Features**: Liquid metal effects, depth of field

#### IM-TRUNCHAN-tran-Voroni-FINAL-RELEASE.fs
**Description**: Truchet + Kaleidoscope effect with smooth transitions  
**Credit**: Original concept by @Mrange, pattern generation and ISF 2.0 by @dot2dot, materials by @mAlk  
**License**: CC-BY-NC-SA 3.0  
**Features**: Voronoi patterns, kaleidoscope, advanced materials

#### IM-_Filter-PrecalculatedVoronoiHeightmap.fs
**Description**: Precalculated Voronoi Heightmap Raymarch with parameter smoothing  
**Credit**: Original by InigoQuilez (@iq), @Nimitz, @Fabrice, @Coyote; ISF by @dot2dot  
**License**: CC-BY-NC-SA 3.0  
**Features**: Voronoi heightmaps, raymarching

#### IM_XORCORIDOR337.fs
**Description**: Corridor Raymarcher - ISF port with smoothed controls  
**Credit**: Original by @XorDev, ISF conversion by @dot2dot  
**License**: CC-BY-NC-SA 3.0  
**Features**: Corridor geometry, raymarching

#### RhodiumTunnel.fs
**Description**: Tunnel effect from Rhodium 4k Intro, converted to ISF 2.0  
**Credit**: Original by Jochen 'Virgill' Feldkötter, ISF 2.0 by @dot2dot  
**License**: CC-BY-NC-SA 3.0  
**Features**: Demo scene tunnel effect

---

### Release.3 (11 Shaders) - Advanced Fractals & Symmetry

#### IM-Ascend.fs
**Description**: Ascend algorithm with time accumulation and horizontal offset control  
**Credit**: Ascend Algorithm by @XorDev, ISF by @dot2dot  
**License**: CC-BY-NC-SA 3.0  
**Features**: Custom ascend algorithm, offset controls

#### IM-ELCOSMO-FINAL-OPT.fs
**Description**: Refactored Shadertoy shader with smoothed controls (zoom, distortion, roll) - OPTIMIZED VERSION  
**Credit**: Original by @diatribes (ShaderToy), ISF by @dot2dot  
**License**: CC-BY-NC-SA 3.0  
**Features**: Performance optimizations, unified speed/parameter smoothing

#### IM-ELCOSMO-FINAL.fs
**Description**: Refactored Shadertoy shader with smoothed controls (zoom, distortion, roll)  
**Credit**: Original by @diatribes (ShaderToy), ISF by @dot2dot  
**License**: CC-BY-NC-SA 3.0  
**Features**: Full-featured version with all controls

#### IM-FRACTAL-MAGE-FINAL-CORRECTION-LIC(MIT).fs
**Description**: A kaleidoscopic DMT trip - Tunnel effect with smoothed controls, kaleidoscope, distortion, and fadeout  
**Credit**: Original shader by @dot2dot  
**License**: MIT ✅ **Commercial use allowed**  
**Features**: Kaleidoscope, distortion, fade effects

#### IM-FRACTALMAXE-FINAL.fs
**Description**: ISF 2.0 Version 'GENERATORS REDUX' by Kali with smoothed speed, vibration intensity, and camera orientation  
**Credit**: Original Shadertoy by @Kali, ISF 2.0 by @dot2dot  
**License**: CC-BY-NC-SA 3.0  
**Features**: Independent vibration frequency, pitch/yaw/roll controls

#### IM-FractalSymetry.fs
**Description**: Raymarched fractal with smoothed zoom, dynamic multi-origin symmetry, and blurred transitions  
**Credit**: Original ShaderToy by @fractal, ISF by @dot2dot  
**License**: CC-BY-NC-SA 3.0  
**Features**: Two-point symmetry plus center, buffered transitions

#### IM-FractalTorbulance-FINAL.fs
**Description**: Fractal turbulence landscape with raymarching and smooth parameter transitions  
**Credit**: Original by @iapafoto, @diatribes; ISF by @dot2dot  
**License**: CC-BY-NC-SA 3.0  
**Features**: Highlight clamping, performance optimizations

#### IM-FractalTorbulanceDOUBLE-FINAL.fs
**Description**: Fractal turbulence with dual planes and raymarching  
**Credit**: Original ShaderToy by @diatribes, ISF by @dot2dot  
**License**: CC-BY-NC-SA 3.0  
**Features**: Dual-plane rendering

#### IM-GFractlBlobl.fs
**Description**: 3D Fractal Blob Effect with Gaussian Blur and Smooth Parameter Transitions  
**Credit**: Original by @philip.bertani@gmail.com, ISF by @dot2dot  
**License**: CC-BY-NC-SA 3.0  
**Features**: Gaussian blur, optimized 2-buffer system

#### IM-ROOT-COLOR-FINAL.fs
**Description**: Abstract Iterative Fractal Explorer with Dampened Controls and Multiple Colors  
**Credit**: Original by ShaderToy, ISF by @dot2dot  
**License**: CC-BY-NC-SA 3.0  
**Features**: Optimized ray calculation, reduced buffer complexity

#### IM-Volt.fs
**Description**: ISF implementation of the 'Volt' algorithm with perspective-like projection  
**Credit**: Volt Algorithm by @XorDev, ISF by @dot2dot  
**License**: CC-BY-NC-SA 3.0  
**Features**: Y-symmetry fix for spherical appearance, XYZ rotation, vignette

---

### Release.4 (19 Shaders) - Twigl Conversions & Volumetrics

#### IM-Circle.fs
**Description**: ISF conversion of a 3D raymarched fractal torus with looping orbital camera  
**Credit**: Original twigl.app by @YoheiNishitsuji, ISF V2.0 by @dot2dot  
**License**: CC-BY-NC-SA 3.0  
**Features**: Orbital camera, customizable fractal parameters

#### IM-FRACTAL1.fs
**Description**: Fractal tetrahedral structure with animated camera and smooth speed transitions  
**Credit**: @Butadiene (original), ISF by @dot2dot  
**License**: CC-BY-NC-SA 3.0  
**Features**: Tetrahedral geometry, camera animation

#### IM-FractalDemon2.fs
**Description**: 3D folding fractal converted from twigl.app with smoothed animation speed  
**Credit**: Original by @YoheiNishitsuji (twigl.app), ISF 2.0 by dot2dot  
**License**: CC-BY-NC-SA 3.0  
**Features**: Folding fractal algorithm, intensity control

#### IM-FractalMountain-optimized.fs
**Description**: Optimized hypnotic, rotating fractal tunnel (reduced iterations for performance)  
**Credit**: Original GLSL by @YoheiNishitsuji, ISF 2.0 by @dot2dot  
**License**: CC-BY-NC-SA 3.0  
**Features**: Performance optimizations

#### IM-FractalMountain-resourceheavy.fs
**Description**: Full-quality hypnotic, rotating fractal tunnel with smoothed parameter transitions  
**Credit**: Original GLSL by @YoheiNishitsuji (twigl.app), ISF 2.0 by @dot2dot  
**License**: CC-BY-NC-SA 3.0  
**Note**: High resource usage - use optimized version if performance is an issue

#### IM-LOPYFrac.fs
**Description**: Complex pulsating fractal structure with raymarching and smoothed speed transitions  
**Credit**: @YoheiNishitsuji (twigl.app), ISF 2.0 by dot2dot  
**License**: CC-BY-NC-SA 3.0  
**Features**: Pulsating animation, complex structures

#### IM-LOPYFrac3D-Ortho.fs
**Description**: Complex pulsating fractal with raymarching, smoothed speed/rotation, controllable camera  
**Credit**: @YoheiNishitsuji (twigl.app), ISF 2.0 by dot2dot  
**License**: CC-BY-NC-SA 3.0  
**Features**: Manual camera control

#### IM-LOPYFrac3D-OrthoFractal-Evolution.fs
**Description**: User-controllable fractal with manual evolution control to isolate specific visual states  
**Credit**: Original algorithm by @YoheiNishitsuji, re-architected by @dot2dot  
**License**: CC-BY-NC-SA 3.0  
**Features**: Evolution control, volumetric depth  
**Note**: "Very fun shader, I encourage you to play around with it" - @dot2dot

#### IM-MrBlob.fs
**Description**: Volumetric Fluorescent Effect with smoothed speed, movement, pattern focus, and color control  
**Credit**: Based on 'Fluorescent' by @XorDev, enhanced by @dot2dot  
**License**: CC-BY-NC-SA 3.0  
**Features**: Volumetric rendering, fluorescent effects

#### IM-NoiseTextureLandscape-FractalClouds.fs
**Description**: Optimized raymarched terrain with clouds, consolidated buffers, seed control  
**Credit**: Based on Shadertoy by @ztri, ISF 2.0 by @dot2dot  
**License**: CC-BY-NC-SA 3.0  
**Features**: Internal seeded noise function, psychedelic sky  
**Note**: Rebuilt to have internal noise (original relied on external channel)

#### IM-OrigamiFinal-correctopacity.fs
**Description**: Complex feedback shader from twigl.app with smoothed animation speed and rotation  
**Credit**: Original algorithm by @XorDev (twigl.app), ISF 2.0 by dot2dot  
**License**: CC-BY-NC-SA 3.0  
**Features**: Feedback effects, opacity corrections

#### IM-RelentlessStruss.fs
**Description**: Raytraced geometric scene with customizable colors and independent animation controls  
**Credit**: Shadertoy by @srtuss (2013), converted to ISF 2.0 by dot2dot  
**License**: CC-BY-NC-SA 3.0  
**Features**: Gate rotation, gate animation/scaling, stream speed control

#### IM-SQR.fs
**Description**: Optical illusion with pulsating red and orange diamonds connected by static green dots  
**Credit**: Created by @dot2dot  
**License**: CC-BY-NC-SA 3.0  
**Features**: Motion illusion, warping effects

#### IM-SnowShade1.fs
**Description**: Complex fractal shader with dampened controls for 3D rotation, scale, colors, and detail  
**Credit**: Concept by @YoheiNishitsuji, converted to ISF 2.0 by @dot2dot  
**License**: CC-BY-NC-SA 3.0  
**Features**: Multiple color controls

#### IM-SpikedBall.fs
**Description**: Spherized raymarched tunnels with smoothed speed and panning controls  
**Credit**: @nimitz (Shadertoy), ISF 2.0 by @dot2dot  
**License**: CC-BY-NC-SA 3.0  
**Features**: Spherical tunnel geometry

#### IM-TheWeaveChronosXor-Final1.fs
**Description**: Converted ShaderToy 'The Weave' exploring volume tracing turbulently distorted SDFs  
**Credit**: Original by chronos (ShaderToy), ISF 2.0 by @dot2dot  
**License**: CC-BY-NC-SA 3.0  
**Features**: Volume tracing, SDF distortion

#### IM-YONIM-TunnelFix-multipath-audioreactive-FINAL.fs
**Description**: Audio-reactive fractal tunnel with smoothed speed, shape, zoom, and modulation  
**Credit**: Based on Twigl shader by @zozuar, redesigned and ISF 2.0 by @dot2dot  
**License**: CC-BY-NC-SA 3.0  
**Features**: Audio reactivity (requires VDMX audio signal)  
**Note**: Will not work in Milumin as it can't feed AudioSignal

#### IM-Zozuar-YONANZOOM.fs
**Description**: Hypnotic fractal tunnel with logarithmic polar coordinates and temporal feedback  
**Credit**: ISF translation of twigl shader by @zozuar, converted by @dot2dot  
**License**: CC-BY-NC-SA 3.0  
**Features**: Speed smoothing, color control

#### im-KailedoFrac.fs
**Description**: Advanced fractal tetrahedral structure with smoothed camera zoom/rotation and kaleidoscopic symmetry  
**Credit**: Butadiene (original), ISF by @dot2dot  
**License**: CC-BY-NC-SA 3.0  
**Features**: Multi-segment kaleidoscope, buffered transitions, organic motion

---

### Release.5 (10 Shaders) - Metaballs, Voxels & Kaleidoscopes

#### IM-3MetaBallProblem.fs
**Description**: 3D metaball shader with dynamic background, 25 animated color palettes  
**Credit**: Original and ISF 2.0 by @dot2dot  
**License**: CC-BY-NC-SA 3.0  
**Features**: 25 color palettes, smooth time-independent parameter transitions  
**Fun Fact**: "I always misread metaballs as meatballs. Imagine my surprise when someone corrected me after 15+ years!" - @dot2dot

#### IM-AteraField-Candid1.fs
**Description**: Flowing 2.5D layers displaying animated 2D cross-sections of a 3D icosahedron field  
**Credit**: Original and ISF 2.0 by @dot2dot  
**License**: CC-BY-NC-SA 3.0  
**Features**: Object properties from 'Stellated Dodecahedron', automatic rotation, radial blur

#### IM-EmoCube-Complex+.fs
**Description**: Tumbling voxel cube with 17 generative color palettes and advanced animation controls (WITH XYZ ROTATIONS + MATERIAL TWISTING)  
**Credit**: Original and ISF 2.0 by @dot2dot  
**License**: CC-BY-NC-SA 3.0  
**Features**: 17 color palettes, dedicated damping controls, XYZ independent rotations, material twisting, customizable voxel arrays  
**Note**: "I am very proud of this shader... got bored with original code and decided to spice things up by adding XYZ independent rotations and MATERIAL TWISTING" - @dot2dot

#### IM-EmoCube-Complex.fs
**Description**: Tumbling voxel cube with 17 generative color palettes and advanced animation controls  
**Credit**: Original and ISF 2.0 by @dot2dot  
**License**: CC-BY-NC-SA 3.0  
**Features**: 17 color palettes, customizable voxel arrays, color template engine, dedicated damping controls  
**Note**: "I am very proud of this shader, each side is defined by an array that can be modified to create unlimited voxel designs" - @dot2dot

#### IM-EmoCube1.fs
**Description**: Original EmoCube - tumbling cube with different carved emotion on each face  
**Credit**: Original by @dot2dot, rendering pipeline by @mrange  
**License**: CC-BY-NC-SA 3.0  
**Features**: Smoothed time-independent animation, advanced materials  
**Note**: "Not very engaging, but I wanted to include it for reference" - @dot2dot

#### IM-Fold-V3-Final.fs
**Description**: Standard folding cube with fun glitchy halo effect  
**Credit**: ShaderToy and ISF 2.0 by @dot2dot  
**License**: CC-BY-NC-SA 3.0  
**Features**: Shared color templates with other Release.5 shaders

#### IM-Fold-V3-Serpinski-Final.fs
**Description**: 3D 'folding' fractal with tetrahedral symmetry and 17 advanced color palettes  
**Credit**: Original and ISF 2.0 by @dot2dot (based on work by nimitz)  
**License**: CC-BY-NC-SA 3.0  
**Features**: 17 color palettes, expanded controls

#### IM-KaleidoKnot.fs
**Description**: Seamless, warping kaleidoscope effect with generative color palettes  
**Credit**: Original and ISF 2.0 by @dot2dot  
**License**: CC-BY-NC-SA 3.0  
**Features**: Independent smoothed animation controls for geometry and color

#### IM-PixelTunnel.fs
**Description**: Twisting voxel face tunnel that wanders with fluid, physics-based motion  
**Credit**: Original and ISF 2.0 by @dot2dot  
**License**: CC-BY-NC-SA 3.0  
**Features**: Procedurally generated patterns, fine-grained parameter control

#### Im-VohelHead-Icosahedron.fs
**Description**: Raymarched icosahedron containing animated voxel cube with Voronoi-patterned floor  
**Credit**: Original and ISF 2.0 by @dot2dot  
**License**: CC-BY-NC-SA 3.0  
**Features**: Controllable position and rotation  
**Tool**: Use [VoxelArrayBuilder.html](https://github.com/bareimage/ISF/blob/main/Misc/VoxelArrayBuilder.html) for array setup

---

## 🚀 Usage

### Compatible Software
These ISF 2.0 shaders work with:
- **VDMX** (tested and optimized)
- **CoGe**
- **MadMapper**
- **Smode**
- **Videosync**
- **Apple Motion / Final Cut Pro** (via plugins)
- Most VJ software supporting ISF 2.0

### Installation
1. Copy desired `.fs` files to your ISF shader directory:
   - **macOS global**: `/Library/Graphics/ISF/`
   - **macOS user**: `~/Library/Graphics/ISF/`
   - **Application-specific**: Check your VJ software documentation

2. Restart your VJ application or refresh the shader library

### Performance Notes
- Tested on **M1 MacBook Pro** - excellent performance even at 4K
- Some shaders have optimized versions (e.g., `IM-FractalMountain-optimized.fs`)
- Audio-reactive shaders may require specific audio routing
- Metal-optimized versions included for macOS

## 🔗 Resources

### ISF Learning Resources
- **Official ISF Specification**: https://github.com/mrRay/ISF_Spec
- **ISF Editor**: https://isf.video/
- **ISF Examples**: https://editor.isf.video/
- **VDMX ISF Tutorial**: https://docs.vidvox.net/vdmx_video_generators_isf.html
- **Book of Shaders**: https://thebookofshaders.com/

### Original Authors to Follow
- **@XorDev** - Algorithm creator (Ascend, Volt, etc.)
- **@YoheiNishitsuji** - Twigl.app shader artist
- **@iapafoto** - Shadertoy creator
- **@mrange** - Shadertoy artist
- **@nimitz** - Shadertoy artist
- **@InigoQuilez (@iq)** - Legendary shader developer
- **@dot2dot (@bareimage)** - ISF converter and enhancer

### bareimage/ISF Repository
- **GitHub**: https://github.com/bareimage/ISF
- **Author**: Igor Molochevski
- **Focus**: High-quality ISF shaders with persistent buffers for smooth, stable animations

---

## 📝 Technical Details

### Persistent Buffer Implementation
These shaders use ISF 2.0's persistent buffer feature to maintain state:
```glsl
"PASSES": [
  {
    "TARGET": "bufferName",
    "PERSISTENT": true,
    "FLOAT": true  // 32-bit buffer for accurate storage
  }
]
```

This enables:
- **Speed-independent animation** - Change speed without affecting position
- **Smooth parameter transitions** - Dampened control changes
- **Temporal effects** - Build up effects over multiple frames
- **Feedback loops** - Reference previous frame data

### Virtual Time System
Many shaders implement a "virtual time" system:
- Real time (`TIME`) advances continuously
- Virtual time accumulates based on speed parameter
- Allows speed=0 to pause animation
- Parameter changes smoothly transition via persistent buffers

---

## ⚠️ Important Notes

1. **License Verification**: Always check individual shader file headers for specific licensing
2. **Commercial Use**: Most shaders are CC-BY-NC-SA 3.0 - contact original authors for commercial rights
3. **Audio Reactivity**: Some shaders require proper audio signal routing (may not work in all VJ software)
4. **Performance**: Start with optimized versions if experiencing performance issues
5. **Metal Compatibility**: Metal-optimized versions included for macOS users

---

## 🙏 Acknowledgments

Massive thanks to:
- **Igor Molochevski (@dot2dot / @bareimage)** for creating and curating this amazing collection
- **All original Shadertoy and twigl.app creators** for their groundbreaking work
- **The ISF community** for developing the standard
- **VDMX developers** for robust ISF 2.0 support

---

**Last Updated**: December 2024  
**Collection Version**: Releases 1-5 (62 shaders total)  
**Repository**: https://github.com/bareimage/ISF
