# Resources - Libraries, Tools & Examples

## Overview

Comprehensive reference of libraries, tools, examples, and learning resources for Processing VJ development.

---

## Essential Libraries

### Audio Analysis

#### Processing Sound (Built-in)
```java
import processing.sound.*;
```
- **Features**: FFT, Amplitude, Oscillators, Filters
- **Best for**: Simple audio reactivity, built-in beat detection
- **Install**: Included with Processing 4
- **Docs**: [processing.org/reference/libraries/sound](https://processing.org/reference/libraries/sound/)

#### Minim
```java
import ddf.minim.*;
import ddf.minim.analysis.*;
```
- **Features**: Advanced FFT, beat detection (kick/snare/hat), audio file loading
- **Best for**: Detailed frequency analysis, music playback
- **Install**: Sketch → Import Library → Add Library → "Minim"
- **Docs**: [code.compartmental.net/minim](https://code.compartmental.net/minim/)

### GPU Acceleration

#### PixelFlow
```java
import com.thomasdiewald.pixelflow.java.*;
```
- **Features**: Fluid simulation, optical flow, particle systems, image processing
- **Best for**: 100,000+ particles, real-time fluid dynamics
- **Install**: Download from [diwi.github.io/PixelFlow](https://diwi.github.io/PixelFlow/)
- **Note**: Requires P2D renderer, not compatible with P3D
- **Examples**: [github.com/diwi/PixelFlow/tree/master/examples](https://github.com/diwi/PixelFlow/tree/master/examples)

### MIDI Control

#### The MidiBus
```java
import themidibus.*;
```
- **Features**: MIDI I/O, device auto-detection
- **Best for**: Launchpad, MIDI controllers
- **Install**: Sketch → Import Library → Add Library → "The MidiBus"
- **Docs**: [smallbutdigital.com/projects/themidibus](http://www.smallbutdigital.com/projects/themidibus/)

### Video Output

#### Syphon (macOS only)
```java
import codeanticode.syphon.*;
```
- **Features**: Zero-latency frame sharing between apps
- **Best for**: VJ pipeline integration (Magic, Resolume, etc.)
- **Install**: Download from [syphon.github.io](https://syphon.github.io/)
- **Note**: **Use Intel/x64 Processing on Apple Silicon** (Syphon not ARM-native)
- **Alternatives (Windows)**: Spout

#### NDI (Cross-platform)
- **Library**: [ndi-processing](https://github.com/IDArnhem/ndi-processing)
- **Features**: Network video streaming
- **Best for**: Remote VJ setups, multi-machine pipelines

### OSC (Network Communication)

#### oscP5
```java
import oscP5.*;
import netP5.*;
```
- **Features**: OSC send/receive
- **Best for**: TouchOSC, control from other apps
- **Install**: Sketch → Import Library → Add Library → "oscP5"

---

## Development Tools

### Processing IDE
- **Download**: [processing.org/download](https://processing.org/download)
- **Apple Silicon**: Use Intel/x64 build for Syphon compatibility
- **Versions**: Processing 4.3+ recommended

### Command-Line Tools

#### processing-java
Test sketches without GUI:
```bash
# Build sketch
processing-java --sketch=/path/to/MySketch --build

# Run sketch
processing-java --sketch=/path/to/MySketch --run

# Export application
processing-java --sketch=/path/to/MySketch --export
```

#### BlackHole (Audio Routing - macOS)
```bash
# Install virtual audio device
brew install blackhole-2ch

# For multi-channel
brew install blackhole-16ch
```

### Shader Editors

- **VSCode + GLSL Extensions**: Best IDE for shader development
- **ShaderToy**: [shadertoy.com](https://www.shadertoy.com/) - Prototype shaders, convert to Processing
- **ISF Editor**: [isf.video/editor](https://isf.video/editor/) - Interactive Shader Format

---

## Example Projects & Galleries

### Official Processing Examples
- [processing.org/examples](https://processing.org/examples) - Built-in examples
- [openprocessing.org](https://openprocessing.org/) - Community sketches

### VJ-Specific Examples

#### Audio-Reactive Particles
- [github.com/santiperez/Processing-Reactive-Sound-Examples](https://github.com/santiperez/Processing-Reactive-Sound-Examples)
- [audioreactivevisuals.com](https://audioreactivevisuals.com/) - Tutorials and techniques

#### PixelFlow Demos
- [diwi.github.io/PixelFlow](https://diwi.github.io/PixelFlow/) - Official gallery
- [github.com/lewisgoing/audioreactive-gpgpu-particle-demo](https://github.com/lewisgoing/audioreactive-gpgpu-particle-demo)

#### Reaction-Diffusion
- [karlsims.com/rd.html](https://www.karlsims.com/rd.html) - Original implementation
- [pmneila.github.io/jsexp/grayscott](http://pmneila.github.io/jsexp/grayscott/) - Interactive demo

### Shader Libraries

#### ISF (Interactive Shader Format)
- [isf.video/shaders](https://isf.video/shaders) - 100+ free shaders
- Compatible with Magic Music Visuals, VDMX, Resolume

#### Shadertoy Conversions
- [shadertoy.com/browse](https://www.shadertoy.com/browse) - Thousands of shaders
- Convert using: [magicmusicvisuals.com/forums/viewtopic.php?t=495](https://magicmusicvisuals.com/forums/viewtopic.php?t=495)

---

## Learning Resources

### Books

#### "A Philosophy of Software Design" by John Ousterhout
- **Focus**: Deep, narrow modules; information hiding
- **Relevance**: Architecting modular VJ systems
- **Link**: [amazon.com/Philosophy-Software-Design](https://www.amazon.com/Philosophy-Software-Design-John-Ousterhout/dp/1732102201)

#### "Grokking Simplicity" by Eric Normand
- **Focus**: Functional programming, pure functions
- **Relevance**: Separating state from effects in simulations
- **Link**: [manning.com/books/grokking-simplicity](https://www.manning.com/books/grokking-simplicity)

#### "The Nature of Code" by Daniel Shiffman
- **Focus**: Physics, particle systems, cellular automata
- **Relevance**: Core algorithms for simulations
- **Free online**: [natureofcode.com](https://natureofcode.com/)
- **Processing examples**: [github.com/nature-of-code](https://github.com/nature-of-code/noc-examples-processing)

### Video Tutorials

#### The Coding Train (Daniel Shiffman)
- **YouTube**: [youtube.com/thecodingtrain](https://www.youtube.com/thecodingtrain)
- **Topics**: Particle systems, flow fields, fractals, cellular automata
- **Processing playlist**: [youtube.com/playlist?list=PLRqwX-V7Uu6ZiZxtDDRCi6uhfTH4FilpH](https://www.youtube.com/playlist?list=PLRqwX-V7Uu6ZiZxtDDRCi6uhfTH4FilpH)

#### Magic Music Visuals Tutorials
- **YouTube**: [youtube.com/playlist?list=PLGfsa0Oh5SVD_lHKqWT2rGChi_pkXGw7x](https://www.youtube.com/playlist?list=PLGfsa0Oh5SVD_lHKqWT2rGChi_pkXGw7x)
- **Topics**: VJ workflow, ISF shaders, live performance

### Online Courses

#### Creative Coding with Processing (Kadenze)
- **Platform**: [kadenze.com](https://www.kadenze.com/)
- **Instructor**: Daniel Shiffman
- **Topics**: Fundamentals, generative art, interaction

---

## Technical References

### FFT and Audio Analysis

- **FFT Explained**: [betterexplained.com/articles/an-interactive-guide-to-the-fourier-transform](https://betterexplained.com/articles/an-interactive-guide-to-the-fourier-transform/)
- **Beat Detection Algorithms**: [gamedev.net/articles/programming/general-and-gameplay-programming/beat-detection-algorithms-r1952](https://archive.gamedev.net/archive/reference/programming/features/beatdetection/page2.html)
- **Minim BeatDetect**: [code.compartmental.net/minim/javadoc/ddf/minim/analysis/BeatDetect.html](https://code.compartmental.net/minim/javadoc/ddf/minim/analysis/BeatDetect.html)

### Particle Systems

- **GPU Particles on the Web**: [github.com/lewisgoing/audioreactive-gpgpu-particle-demo](https://github.com/lewisgoing/audioreactive-gpgpu-particle-demo)
- **Real-Time Particle Systems**: [cse.chalmers.se](https://www.cse.chalmers.se/edu/year/2011/course/TDA361/Advanced%20Computer%20Graphics/Real-Time%20Particle%20Systems%20on%20the%20GPU%20in%20Dynamic%20Environments.pdf)

### Fluid Dynamics

- **PixelFlow Documentation**: [diwi.github.io/PixelFlow](https://diwi.github.io/PixelFlow/)
- **Fluid Simulation for Dummies**: [mikeash.com/pyblog/fluid-simulation-for-dummies.html](https://mikeash.com/pyblog/fluid-simulation-for-dummies.html)
- **Jos Stam's Stable Fluids**: [dgp.toronto.edu/public_user/stam/reality/Research/pdf/GDC03.pdf](http://www.dgp.toronto.edu/people/stam/reality/Research/pdf/GDC03.pdf)

### Reaction-Diffusion

- **Karl Sims Tutorial**: [karlsims.com/rd.html](https://www.karlsims.com/rd.html)
- **Gray-Scott Model**: [mrob.com/pub/comp/xmorphia](http://www.mrob.com/pub/comp/xmorphia/)
- **Interactive Simulation**: [pmneila.github.io/jsexp/grayscott](http://pmneila.github.io/jsexp/grayscott/)

### GLSL Shaders

- **The Book of Shaders**: [thebookofshaders.com](https://thebookofshaders.com/) - Interactive GLSL tutorial
- **Shadertoy**: [shadertoy.com](https://www.shadertoy.com/) - 100,000+ shader examples
- **GLSL Reference**: [khronos.org/opengl/wiki/OpenGL_Shading_Language](https://www.khronos.org/opengl/wiki/OpenGL_Shading_Language)

---

## VJ Software Ecosystem

### Compatible VJ Applications

#### Magic Music Visuals (macOS)
- **Website**: [magicmusicvisuals.com](https://magicmusicvisuals.com/)
- **Input**: Syphon, ISF shaders, NDI
- **Best for**: Modular audio-reactive visuals
- **Docs**: [magicmusicvisuals.com/documentation](https://magicmusicvisuals.com/documentation)

#### Resolume (Windows/macOS)
- **Website**: [resolume.com](https://resolume.com/)
- **Input**: Syphon, Spout, NDI
- **Best for**: Live video mixing, projection mapping

#### VDMX (macOS)
- **Website**: [vidvox.net](https://vidvox.net/)
- **Input**: Syphon, ISF, Quartz Composer
- **Best for**: Pro VJ performances

#### Synesthesia (macOS/Windows)
- **Website**: [synesthesia.live](https://synesthesia.live/)
- **Input**: Custom SSF shaders
- **Best for**: Audio-reactive shader performances

---

## Hardware Setup

### Recommended MIDI Controllers

| Controller | Price | Features | Best For |
|------------|-------|----------|----------|
| Launchpad Mini Mk3 | $100 | 8×8 RGB pads | Interactive games, grid controls |
| Akai MIDImix | $100 | 8 faders, 24 knobs | Parameter control, mixing |
| TouchOSC (iOS/Android) | $20 | Custom layouts | Wireless control, tablets |

### Audio Interface (macOS)

1. **BlackHole** (free) - Virtual audio routing
2. **Loopback** ($99) - Professional audio routing with UI
3. **Soundflower** (deprecated) - Legacy virtual audio

### Display & Projection

- **HDMI/DisplayPort** output for projectors
- **Syphon** for routing to VJ software (zero-latency)
- **NDI** for network streaming to remote displays

---

## Community & Support

### Forums

- **Processing Forum**: [discourse.processing.org](https://discourse.processing.org/)
- **r/processing**: [reddit.com/r/processing](https://www.reddit.com/r/processing/)
- **Magic Music Visuals Forum**: [magicmusicvisuals.com/forums](https://magicmusicvisuals.com/forums/)

### Discord Servers

- **Processing Foundation**: Community chat and support
- **Creative Coding**: General creative coding community
- **VJ Galaxy**: VJ-specific discussions

### GitHub Repositories

- **Processing**: [github.com/processing](https://github.com/processing)
- **PixelFlow**: [github.com/diwi/PixelFlow](https://github.com/diwi/PixelFlow)
- **This repo**: [github.com/abossard/synesthesia-visuals](https://github.com/abossard/synesthesia-visuals)

---

## Quick Reference Cards

### Library Install Commands

```bash
# Processing IDE
Sketch → Import Library → Manage Libraries → Search & Install

# Manual install
mv Library.zip ~/Documents/Processing/libraries/
unzip ~/Documents/Processing/libraries/Library.zip
# Restart Processing
```

### Common Package Imports

```java
// Audio
import processing.sound.*;           // Built-in
import ddf.minim.*;                  // Minim
import ddf.minim.analysis.*;

// Video
import codeanticode.syphon.*;        // Syphon (macOS)

// MIDI
import themidibus.*;                 // MidiBus

// GPU
import com.thomasdiewald.pixelflow.java.*;  // PixelFlow

// OSC
import oscP5.*;
import netP5.*;
```

---

## Next Steps

1. **Start with basics**: Clone examples from [openprocessing.org](https://openprocessing.org/)
2. **Follow The Coding Train**: Learn particle systems and flow fields
3. **Read "The Nature of Code"**: Understand physics and simulations
4. **Experiment with PixelFlow**: Build GPU-accelerated visuals
5. **Join community**: Ask questions on Processing Forum

---

**Previous**: [07-performance-optimization.md](07-performance-optimization.md) - Performance tuning

**Home**: [00-overview.md](00-overview.md) - Guide overview
