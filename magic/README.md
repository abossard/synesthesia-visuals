# ISF Shader Collection — rhythmic-visions

> **206 shaders** | 89 Layers | 117 Effects
> Downloaded from [editor.isf.video/u/rhythmic-visions](https://editor.isf.video/u/rhythmic-visions)

## Table of Contents

- [Layers (89)](#layers)
- [Effects (117)](#effects)

## Layers

*Generators — produce visuals from math, noise, and algorithms*

### 24K

![24K](screenshots/24K.jpg)

**Description:** Luxurious golden plasma field with organic, flowing patterns. Creates rich metallic textures reminiscent of molten precious metals.

---

### 3d Cube

![3d Cube](screenshots/3d%20Cube.jpg)

**Description:** Generates a rotating 3D wireframe cube with customizable glow and colors. Dynamic geometric visualization with depth.

**Inputs:** `rotX` (float) [0–1], `rotY` (float) [0–1], `rotZ` (float) [0–1], `zoomAmount` (float) [-1–1], `lineThickness` (float) [0.001–0.02], `lineGlow` (float) [0–0.1], `lineColor` (color)

**🎵 Audio:** `uniformName`→bass

---

### 3d grid

![3d grid](screenshots/3d%20grid.jpg)

**Description:** A 3D perspective grid with customizable line thickness and depth effects. Creates a retro-futuristic wireframe landscape that stretches into vanishing point perspective.

**Inputs:** `posY` (float) [0–1], `persp` (float) [0.1–3], `linewidth` (float) [0.001–0.1], `scale` (float) [0.5–1], `fade` (float) [0–3], `horiz` (float) [0–1], `vert` (float) [0–1], `brightness` (float) [0–2], `color` (color)

**🎵 Audio:** `uniformName`→bass

---

### 3d Grid 2

![3d Grid 2](screenshots/3d%20Grid%202.jpg)

**Description:** Advanced 3D grid using raymarching with smooth extrusion patterns. Features camera controls and dynamic geometric formations with customizable smoothness.

**Inputs:** `xPos` (float) [-10–10], `yPos` (float) [0.1–1], `cameraX` (float) [-3.14–3.14], `cameraY` (float) [0–1.57], `cameraZ` (float) [-3.14–3.14], `extrude` (float) [0.25–1], `smoothness` (float) [0–1], `lineColor` (color)

**🎵 Audio:** `uniformName`→mid

---

### 3d Mayhem

![3d Mayhem](screenshots/3d%20Mayhem.jpg)

**Description:** Chaotic fractal geometry with intricate folding patterns. Generates complex mathematical structures through recursive transformations.

**Inputs:** `rotX` (float), `rotY` (float), `rotationSpeed` (float), `zoom` (float), `lightIntensity` (float), `foldStrength` (float)

**🎵 Audio:** `uniformName`→rotationSpeed

---

### 4D Cube

![4D Cube](screenshots/4D%20Cube.jpg)

**Description:** Hyperdimensional tesseract rotating through 4D space. Renders the shadow of a four-dimensional cube in motion.

**Inputs:** `rotX` (float), `rotZ` (float), `rotXX` (float), `rotYY` (float), `rotZZ` (float)

**🎵 Audio:** `uniformName`→rotX

---

### Alien Face

![Alien Face](screenshots/Alien%20Face.jpg)

**Description:** Retro alien invader pattern generator with pixelated, space-age aesthetic. Creates nostalgic 8-bit style alien face designs.

**Inputs:** `scale` (float) [0–3], `color` (color), `x1` (float) [0–1], `x2` (float) [0–1], `seed` (float) [11–3457]

---

### Alien Invaders

![Alien Invaders](screenshots/Alien%20Invaders.jpg)

**Description:** Space invader pixel patterns with scrolling movement. Retro arcade sprites in animated formations with ring effects.

**Inputs:** `scale` (float) [0.5–1], `rate` (float) [0.5–3], `scroll` (float) [-100–100], `R` (float) [0–1], `G` (float) [0–1], `B` (float) [0–1], `seed` (float) [11–3457]

**🎵 Audio:** `uniformName`→highHits

---

### Basic Shape

![Basic Shape](screenshots/Basic%20Shape.jpg)

**Description:** Generates fundamental geometric shapes including rectangles, triangles, circles, and diamonds. Offers precise control over positioning and repetition patterns.

**Inputs:** `color` (color), `maskShapeMode` (long), `shapeWidth` (float) [0–2], `shapeHeight` (float) [0–2], `center` (point2D) [0,0–1,1], `invertMask` (bool), `horizontalRepeat` (long), `verticalRepeat` (long)

---

### BetterBitWheel

![BetterBitWheel](screenshots/BetterBitWheel.jpg)

**Description:** Rotating circular wheel pattern with binary segments. Concentric rings of animated bits create hypnotic spinning data visualization.

**Inputs:** `scale` (float) [0.5–3], `rate` (float) [-10–10], `seed1` (float) [8–233], `seed2` (float) [1597–8999], `seed3` (float) [9859–28657], `loops` (float) [1–60], `thickness` (float) [0.5–0.99], `density` (float) [0.001–0.999], `fade` (float) [0–3]

**🎵 Audio:** `uniformName`→beatPhase

---

### Bit Streamer

![Bit Streamer](screenshots/Bit%20Streamer.jpg)

**Description:** Streaming matrix of animated binary data patterns. Digital rain effect with controllable density and RGB color channels.

**Inputs:** `grid` (point2D) [10,6–300,200], `density` (float) [-900–1800], `rate` (float) [-3–3], `seed1` (float) [8–233], `seed2` (float) [55–987], `seed3` (float) [75025–3524578], `offset1` (float) [-100–100], `offset2` (float) [-100–100]

**🎵 Audio:** `uniformName`→high

---

### Circle Oscillation

![Circle Oscillation](screenshots/Circle%20Oscillation.jpg)

**Description:** Rhythmic circular patterns with oscillating movements. Creates pulsing geometric grids that expand and contract harmoniously.

**Inputs:** `Speed` (float) [1–4], `Blur` (float) [0.1–1], `Angle` (float) [0–6.28319], `Zoom` (float) [1–30]

**🎵 Audio:** `uniformName`→Speed

---

### Coil

![Coil](screenshots/Coil.jpg)

**Description:** Animated spiral coil generator with customizable parameters and depth shading. Creates flowing helical patterns.

**Inputs:** `pos` (float), `shape1` (float), `shape2` (float), `dist` (float), `size` (float), `width` (float), `smooth` (float), `fade` (float), `color` (color)

**🎵 Audio:** `uniformName`→high

---

### ControlledChaos

![ControlledChaos](screenshots/ControlledChaos.jpg)

**Description:** Controlled randomness creates structured chaos patterns. Mathematical noise functions generate organized disorder.

**Inputs:** `pos` (point2D) [0,0–1,1], `invert` (bool), `function` (long), `speed` (float) [-2–2], `multiplier` (float) [-2–2], `grid` (float) [0.0001–20], `detail` (float) [0.0001–0.1], `contrast` (float) [0–0.5], `contrastShift` (float) [-0.5–0.5], `mode` (long)

**🎵 Audio:** `uniformName`→bpm

---

### Corner Colors

![Corner Colors](screenshots/Corner%20Colors.jpg)

**Description:** Four-corner gradient generator with rotatable color blending. Creates smooth radial color transitions from each corner of the canvas.

**Inputs:** `color1` (color), `color2` (color), `color3` (color), `color4` (color), `rotationAngle` (float) [0–1]

---

### Cos Orbit

![Cos Orbit](screenshots/Cos%20Orbit.jpg)

**Description:** Orbital wave and point pattern generator with sine/cosine visualization. Creates flowing mathematical curves with glowing points and customizable thickness.

**Inputs:** `phase` (float) [0–1], `lineThickness` (float) [0.01–1], `pointThickness` (float) [0.01–1], `pitch` (float) [0–1], `yaw` (float) [0–1], `glow` (float) [0.1–0.5], `waveScale` (float) [1–5]

**🎵 Audio:** `uniformName`→beatPhase

---

### Cosplay

![Cosplay](screenshots/Cosplay.jpg)

**Description:** Creates mesmerizing rotating particle patterns with animated dots that spiral and dance in mathematical harmony. A hypnotic display of circular forms in perpetual motion.

**Inputs:** `dotSize` (float) [0–0.1], `iteration` (float) [0–100], `xAmp` (float) [-1–1], `yAmp` (float) [-1–1], `xFactor` (float) [0–10], `yFactor` (float) [0–10], `speed` (float) [0–0.1], `rotateCanvas` (float) [-3.141592653589793–3.141592653589793], `rotateParticles` (float) [-1.5707963267948966–1.5707963267948966], `rotateMultiplier` (float) [0.01–10], `pos` (point2D) [0,0–1,1]

**🎵 Audio:** `uniformName`→beatPhase

---

### Crystals

![Crystals](screenshots/Crystals.jpg)

**Description:** Iridescent crystal facets forming complex dodecahedral structures. Features dynamic rotation and customizable coloration for prismatic effects.

**Inputs:** `rotateX` (float), `rotateY` (float), `rotateZ` (float), `colR` (float), `colG` (float), `colB` (float), `rate1` (float), `rate2` (float)

---

### Dark Tomb

![Dark Tomb](screenshots/Dark%20Tomb.jpg)

**Description:** Audio-reactive 3D spiky sphere emerging from a dark, textured tomb environment. Features dynamic needles that respond to bass frequencies creating an immersive gothic atmosphere.

**Inputs:** `iChannel0` (image), `een` (float) [0–1], `twee` (float) [0–5], `vier` (float) [0–10], `drie` (float) [0–2]

**🎵 Audio:** `uniformName`→bass

---

### DecoWaves

![DecoWaves](screenshots/DecoWaves.jpg)

**Description:** Art deco inspired wave patterns with smooth flowing curves. Rhythmic undulating forms in customizable colors.

**Inputs:** `colorInput` (color), `rate` (float) [-2–2], `rows` (float) [1–10], `wave` (float) [2–12]

**🎵 Audio:** `uniformName`→mid

---

### DiamondVision

![DiamondVision](screenshots/DiamondVision.jpg)

**Description:** Diamond tunnel vision with rotating torus geometry. Prismatic structures create infinite recursive depth and sparkle.

**Inputs:** `Speed` (float) [-1–1], `GRAT` (float), `W` (float) [-0.001–2], `R` (float) [-1–1], `Ty` (float) [-1–0], `Rot` (float), `Rat` (float) [-1–2], `Bat` (float) [0.5–1.3]

**🎵 Audio:** `uniformName`→bassHits

---

### Difference Strokes

![Difference Strokes](screenshots/Difference%20Strokes.jpg)

**Description:** Generates dynamic geometric patterns with animated shapes and strokes. Creates hypnotic visual rhythms through mathematical precision.

**Inputs:** `invert` (bool), `difference` (bool), `shape` (long), `dotSize` (float) [0–0.1], `zoom` (float) [0.25–4], `iteration` (float) [0–50], `xAmp` (float) [-0.5–0.5], `yAmp` (float) [-0.5–0.5], `xFactor` (float) [0–0.01], `yFactor` (float) [0–0.01], `speed` (float) [0–0.1], `rotateCanvas` (float) [-1–1], `rotateParticles` (float) [-1–1], `rotateMultiplier` (float) [0.01–10], `pos` (point2D) [0,0–1,1]

**🎵 Audio:** `uniformName`→beatPhase

---

### Down The Roots

![Down The Roots](screenshots/Down%20The%20Roots.jpg)

**Description:** Procedural marble texture with organic crack patterns. Generates sophisticated stone-like surfaces with controllable movement and blending.

**Inputs:** `zebra` (float), `move` (float), `zoom` (float), `blend` (float), `speed` (float) [-1–1]

---

### EightBitMatrixRain

![EightBitMatrixRain](screenshots/EightBitMatrixRain.jpg)

**Description:** Classic Matrix-style digital rain with 8-bit aesthetic. Green cascading glyphs create cyberpunk atmosphere.

**Inputs:** `scale` (float) [4–100], `rate` (float) [1–60], `seed1` (float) [3–34], `seed2` (float) [55–233], `seed3` (float) [144–610], `R` (float) [0–1], `G` (float) [0–1], `B` (float) [0–1], `gamma` (float) [0.25–3.5]

**🎵 Audio:** `uniformName`→high

---

### Flythrough

![Flythrough](screenshots/Flythrough.jpg)

**Description:** Infinite tunnel flythrough with fractal geometric structures. Navigate through twisted corridors of mathematical beauty.

**Inputs:** `c0` (float) [0–8], `c1` (float) [0–8], `c2` (float) [0–8]

**🎵 Audio:** `uniformName`→bpm

---

### Fractal Ball Fold

![Fractal Ball Fold](screenshots/Fractal%20Ball%20Fold.jpg)

**Description:** Intricate fractal geometry with ball-fold transformations creating infinite recursive patterns. Highly parametric with extensive camera and folding controls.

**Inputs:** `Ball` (float) [0–1], `RotationIntensityX` (float) [0–1], `RotationIntensityY` (float) [0–1], `RotationSpeed1` (float) [0–1], `RotationSpeed2` (float), `SizeReductionRate` (float), `RotationOffset1` (float) [0–10], `RotationOffset2` (float) [0–10], `PlaneFoldFactor1` (float), `PlaneFoldFactor2` (float), `CameraZOffset` (float) [0–15], `CameraXOffset` (float) [0–20], `CameraYOffset` (float) [0–10]

---

### Fractal Blob

![Fractal Blob](screenshots/Fractal%20Blob.jpg)

**Description:** Renders organic fractal blob formations with stereoscopic depth and fluid transformations. Morphing geometric structures create alien landscapes of mathematical art.

**Inputs:** `iMouse` (point2D), `speed` (float), `radius` (float), `falloff` (float), `divergence` (float)

**🎵 Audio:** `uniformName`→bass

---

### Fractal Dots

![Fractal Dots](screenshots/Fractal%20Dots.jpg)

**Description:** Creates infinite fractal dot patterns with recursive scaling. Self-similar geometric forms spiral into mesmerizing complexity.

**Inputs:** `iteration` (float) [0–10], `complexity` (float) [0–4], `zoom` (float) [0–200], `pattern` (float) [0–10], `spacing` (float) [0–100], `rotate1` (float) [0–1.57079632679], `rotate2` (float) [0–1.57079632679], `dotSize` (float) [0–4000], `pos` (point2D) [0,0–1,1]

**🎵 Audio:** `uniformName`→level

---

### Fractal Folding

![Fractal Folding](screenshots/Fractal%20Folding.jpg)

**Description:** Complex fractal generator using iterative folding techniques to create intricate 3D mathematical structures. Produces mesmerizing recursive geometries with deep spatial depth.

**Inputs:** `Ball` (float) [0–1], `RotationIntensityX` (float) [0–1], `RotationIntensityY` (float) [0–1], `RotationSpeed1` (float) [0–1], `RotationSpeed2` (float), `SizeReductionRate` (float), `RotationOffset1` (float) [0–10], `RotationOffset2` (float) [0–10], `PlaneFoldFactor1` (float), `PlaneFoldFactor2` (float), `CameraZOffset` (float) [0–15], `CameraXOffset` (float) [0–20], `CameraYOffset` (float) [0–10]

---

### Fractal MBox

![Fractal MBox](screenshots/Fractal%20MBox.jpg)

**Description:** Renders complex Mandelbox fractal structures with infinite recursive detail and 3D depth. Creates mind-bending geometric patterns with customizable scaling and folding.

**Inputs:** `SCALE` (float) [-3.5–-0.8], `dthresh` (float) [0–5], `fixedRad2` (float) [1.4–3], `foldingLimit` (float) [0.5–1.4], `minRad2` (float) [0–1], `dhue` (float) [0–1], `zoom` (float) [1–8], `x` (float) [-1–1], `y` (float) [-1–1], `z` (float) [-1–1]

---

### Glow Tunnel

![Glow Tunnel](screenshots/Glow%20Tunnel.jpg)

**Description:** Hypnotic tunnel effect with receding glowing rings. Creates depth illusion through layered circles fading into the distance.

**Inputs:** `line` (float) [0.01–0.1], `brightness` (float) [0.1–1], `depth` (float) [0–5], `speed` (float) [0–1], `moveX` (float) [-1–1], `moveY` (float) [-1–1], `color` (color)

---

### Gradient Generator

![Gradient Generator](screenshots/Gradient%20Generator.jpg)

**Description:** Procedural gradient generator with organic grain texture and morphing shapes. Creates paper-like backgrounds with animated color transitions.

**Inputs:** `color1` (color), `color2` (color), `color3` (color), `colorBack` (color), `softness` (float) [0–1], `intensity` (float) [0–1], `noise` (float) [0–1], `shape` (long), `speed` (float) [0–4], `scale` (float) [0.1–4]

**🎵 Audio:** `uniformName`→beatPhase

---

### Grid Matrix

![Grid Matrix](screenshots/Grid%20Matrix.jpg)

**Description:** Generates an infinite tunnel matrix with fractal patterns and deformation. Hypnotic geometric journey through digital space.

**Inputs:** `speed` (float) [0.1–5.5], `colorMod` (color)

**🎵 Audio:** `uniformName`→bass

---

### Hoop Dreams

![Hoop Dreams](screenshots/Hoop%20Dreams.jpg)

**Description:** Circular rings pulse and rotate in rhythmic motion. Concentric hoops create hypnotic orbital patterns.

**Inputs:** `invert` (bool), `zoom` (float) [0–20], `animate` (float) [-3.141592653589793–3.141592653589793], `size` (float) [0–1], `thickness` (float) [0.001–0.5], `lineEffect` (float) [0–0.2], `patternOffset` (float) [-1–1], `rSin` (float) [-5–5], `xCos` (float) [-5–5], `ySin` (float) [-5–5], `blur` (float) [0.001–0.5], `function` (long), `rotate` (float) [-1–1], `pos` (point2D) [0,0–1,1]

**🎵 Audio:** `uniformName`→beatPhase

---

### Hypnocone

![Hypnocone](screenshots/Hypnocone.jpg)

**Description:** Hypnotic concentric circles that expand and contract in mesmerizing patterns. Creates trance-inducing spiral formations with customizable movement.

**Inputs:** `invert` (bool), `zoom` (float) [0.25–10], `rings` (float) [0.01–1], `radius` (float) [0.001–2], `xAmp` (float) [-0.1–0.1], `xOffset` (float) [-1–1], `xOffsetSpeed` (float) [0–0.1], `yAmp` (float) [-0.1–0.1], `yOffset` (float) [-1–1], `yOffsetSpeed` (float) [0–0.1], `rotate` (float) [0–1], `pos` (point2D) [0,0–1,1]

**🎵 Audio:** `uniformName`→beatPhase

---

### Illustrated Equations

![Illustrated Equations](screenshots/Illustrated%20Equations.jpg)

**Description:** Mathematical curves and fractal equations rendered as animated line art. Complex geometric forms evolve through parametric mathematical functions.

**Inputs:** `FIELD` (float) [1–38], `posX` (float) [0–1], `posY` (float) [0–1]

**🎵 Audio:** `uniformName`→bass

---

### Illustrated Equations Step

![Illustrated Equations Step](screenshots/Illustrated%20Equations%20Step.jpg)

**Description:** Mathematical equation visualizer rendering complex curves and surfaces. Features multiple equation types from simple lines to elaborate torus shapes.

**Inputs:** `zoom` (float) [1–38], `equation` (float) [0–8], `posX` (float) [0–1], `posY` (float) [0–1]

---

### InnerDimensionalMatrix

![InnerDimensionalMatrix](screenshots/InnerDimensionalMatrix.jpg)

**Description:** Animated matrix of interconnected nodes with flowing energy connections. Creates a futuristic digital landscape with pulsing neural network aesthetics.

**Inputs:** `scale` (float) [0.25–2], `spin` (float) [0.1–3], `zoom` (float) [-1–1], `line` (float) [0–0.5], `color` (float) [0–1]

**🎵 Audio:** `uniformName`→bass

---

### Interstellar

![Interstellar](screenshots/Interstellar.jpg)

**Description:** Renders a dynamic starfield with depth and motion blur effects. Creates the illusion of traveling through space at high velocity.

**Inputs:** `stellar` (float) [0–1], `timePosition` (float) [0–1], `amount` (float) [0–1]

---

### IQ ColoredGridThingy

![IQ ColoredGridThingy](screenshots/IQ%20ColoredGridThingy.jpg)

**Description:** Animated grid of colored cells that shift and pulse with temporal variations. Creates rhythmic mosaic patterns with organic color cycling.

**Inputs:** `seed` (point2D) [0.01,0.01–2,2], `speed` (float) [0.5–15], `size` (float) [2–20]

---

### Iteration

![Iteration](screenshots/Iteration.jpg)

**Description:** Iterative shapes cascade outward in endless repetition. Circles or squares multiply into hypnotic sequences.

**Inputs:** `invert` (bool), `gradient` (float) [0–2], `radius` (float) [0.0001–50], `pos` (point2D) [0,0–1,1], `offsetPos` (point2D) [-0.1,-0.1–0.1,0.1], `offset` (float) [0.0001–1], `shapeSelect` (long)

**🎵 Audio:** `uniformName`→bass

---

### Kaleidic Line

![Kaleidic Line](screenshots/Kaleidic%20Line.jpg)

**Description:** Generates pulsating kaleidoscopic patterns with fractal repetition. Creates mesmerizing geometric blooms with rotating symmetries.

**Inputs:** `rotationSpeed` (float) [0–1], `patternComplexity` (float) [1–3], `speed` (float) [0.1–2]

---

### Kaleidic Line Colored

![Kaleidic Line Colored](screenshots/Kaleidic%20Line%20Colored.jpg)

**Description:** Generates mesmerizing kaleidoscopic patterns with rotating geometric lines. Pulsating fractal structures create hypnotic symmetrical displays with rich color palettes.

**Inputs:** `rotationSpeed` (float) [0–1], `patternComplexity` (float) [1–2.2], `speed` (float) [0.1–2], `intensity` (float), `colorShift` (float), `colorAdjust` (float) [0.25–2]

---

### Line World

![Line World](screenshots/Line%20World.jpg)

**Description:** Mesmerizing twisted line world with infinite depth and cellular color patterns. Creates flowing geometric tunnels with customizable aesthetics.

**Inputs:** `twist` (float) [1–5], `speed` (float), `twist2` (float) [0–20], `cork` (float) [0–4], `clip` (float) [0–1], `cellSize` (float) [0.05–1], `thickness` (float) [0.25–2.5], `clipBias` (float) [0–0.6], `gamma` (float) [0.4–1.3], `colorMode` (float) [0–2], `COLORA` (color), `COLORB` (color), `COLORC` (color)

**🎵 Audio:** `uniformName`→bass

---

### Linescape

![Linescape](screenshots/Linescape.jpg)

**Description:** Retro-styled terrain landscape with procedural noise generation. Renders flowing digital horizons and hills.

**Inputs:** `Offset_X` (float) [-20–20], `Speed` (float) [0–5]

**🎵 Audio:** `uniformName`→bass

---

### MagicLougie

![MagicLougie](screenshots/MagicLougie.jpg)

**Description:** Complex 3D fractal surface with ray-marched bumpy sphere geometry. Organic undulating forms with mathematical precision.

**Inputs:** `matrix` (point2D) [0.01,0.01–1,1], `seed1` (float) [2–7], `seed2` (float) [23–37], `seed3` (float) [11–19], `offset1` (float) [-3–3], `offset2` (float) [-3–3], `offset3` (float) [-3–3], `depth` (float) [18–216], `rate` (float) [1.1–60], `cycle` (float) [0.5–1.5], `multiplier` (float) [2–24], `scale` (float) [-3–3]

**🎵 Audio:** `uniformName`→bass

---

### Magnetic Dreams

![Magnetic Dreams](screenshots/Magnetic%20Dreams.jpg)

**Description:** Hypnotic circular pattern generator creating magnetic field-like visualizations. Produces rotating geometric formations with customizable density and movement.

**Inputs:** `invert` (bool), `zoom` (float) [1–8], `size` (float) [0–0.5], `lineEffect` (float) [0–0.037], `patternOffset` (float) [0–1], `rSin` (float) [0–0.5], `xCos` (float) [0–1], `modAll` (float) [0–1], `ySin` (float) [0–1], `blur` (float) [0.001–0.005], `function` (long), `rotate` (float) [-1–1], `pos` (point2D) [0,0–1,1]

**🎵 Audio:** `uniformName`→beatPhase

---

### Matrix Grid

![Matrix Grid](screenshots/Matrix%20Grid.jpg)

**Description:** Generates digital matrix-style grid patterns with random character placement. Cyberpunk aesthetic with customizable scale and animation speed.

**Inputs:** `invert` (bool), `zoom` (float) [0.0001–40], `grid` (float) [0.1–20], `dotSize` (float) [0–0.5], `xScale` (float) [0–0.49], `yScale` (float) [0–0.49], `xRandom` (float) [0.0001–12.9898], `yRandom` (float) [0.0001–78.233], `randomMultiplier` (float) [0.0001–43758.5453], `speed` (float) [0–40], `rotate` (float) [0–1], `pos` (point2D) [0,0–1,1]

**🎵 Audio:** `uniformName`→bassHits

---

### Mega Tunnel

![Mega Tunnel](screenshots/Mega%20Tunnel.jpg)

**Description:** Infinite tunnel with spectrum analyzer color palette. Creates endless corridor effects with audio visualization aesthetics.

**Inputs:** `Bright` (float) [0–1], `Twist` (float), `Speed` (float) [0–10], `Twist2` (float) [0–0.02]

**🎵 Audio:** `uniformName`→Speed

---

### Melter

![Melter](screenshots/Melter.jpg)

**Description:** Generates flowing rivers of chromatic noise that undulate across the screen. Creates organic color patterns reminiscent of molten metal or liquid light.

**Inputs:** `noiseIntensity` (float) [0–10], `noiseScaleX` (float) [1–10], `noiseScaleY` (float) [1–10], `redPhaseShift` (float) [0–1], `greenPhaseShift` (float) [0–1], `bluePhaseShift` (float) [0–1]

**🎵 Audio:** `uniformName`→bass

---

### MetaSevenVortex

![MetaSevenVortex](screenshots/MetaSevenVortex.jpg)

**Description:** Mesmerizing vortex tunnel with rotating mathematical forms. Creates hypnotic spiral geometries that twist through dimensional space.

**Inputs:** `center` (point2D) [-1,-1–1,1], `scale` (float) [0–30], `rate` (float) [-3–3], `fov` (float) [0.25–2], `mod1` (float) [0.25–2], `light` (float) [0.15–2]

**🎵 Audio:** `uniformName`→rate

---

### MobiusSpiral

![MobiusSpiral](screenshots/MobiusSpiral.jpg)

**Description:** Hypnotic Mobius spiral generator with reflective surfaces and complex mathematical patterns. Creates swirling, infinite geometric forms with adjustable intensity and scale.

**Inputs:** `rate` (float) [-3–3], `mx` (float) [0–1], `patternScale` (float) [1–10], `spiralIntensity` (float) [0–1], `zoomFactor` (float) [0.1–2], `colorIntensity` (float) [0.1–2], `reflectivity` (float) [0.1–1]

**🎵 Audio:** `uniformName`→bpm

---

### Multi Cube

![Multi Cube](screenshots/Multi%20Cube.jpg)

**Description:** Wireframe cube array with perspective controls and orbital motion. Generates multiple rotating cubes with customizable brightness and scaling for geometric compositions.

**Inputs:** `pitch` (float) [0–1], `yaw` (float) [0–1], `scale` (float) [0.1–0.8], `zoom` (float) [0–1], `color` (float) [0–1], `brightness` (float) [0.08–0.16], `perspective_toggle` (bool)

**🎵 Audio:** `uniformName`→level

---

### Neon Circle

![Neon Circle](screenshots/Neon%20Circle.jpg)

**Description:** Glowing neon circle outline with aspect-ratio correction. Perfect for creating clean, bright geometric elements with customizable glow intensity.

**Inputs:** `radius` (float) [0.1–2.5], `line_width` (float) [0.01–0.1], `color` (color), `brightness` (float) [0.1–1]

---

### Neon Line

![Neon Line](screenshots/Neon%20Line.jpg)

**Description:** Neon line generator creating bright, glowing linear elements. Produces electric-style lighting effects with customizable positioning and intensity.

**Inputs:** `radius` (float) [0.1–2.5], `flip` (float), `linePos` (float), `line_width` (float) [0.01–0.1], `color` (color), `brightness` (float) [0.1–1]

**🎵 Audio:** `uniformName`→level

---

### Noise Cluster

![Noise Cluster](screenshots/Noise%20Cluster.jpg)

**Description:** Creates clustered particle noise with cellular distribution patterns. Worley noise generates dynamic, constellation-like formations.

**Inputs:** `scale` (float) [1–100], `rate` (float) [0–3], `gravity` (float) [0.01–0.5], `density` (float) [0.001–0.5], `fade` (float) [2–100], `jitter` (float) [0.25–0.999], `depth` (float) [0.1–2.5], `multiply` (float) [0–1], `cells` (bool)

**🎵 Audio:** `uniformName`→mid

---

### Noise Fog

![Noise Fog](screenshots/Noise%20Fog.jpg)

**Description:** Generates volumetric fog using layered simplex noise algorithms. Creates atmospheric, drifting fog effects with customizable density.

**Inputs:** `speed` (float) [0–0.5], `twee` (float) [0–2], `drie` (float) [0–10], `vier` (float) [0–1], `vijf` (float) [0.95–1.05], `bright` (float) [0–20], `c1` (color), `c2` (color)

---

### Noise Waves

![Noise Waves](screenshots/Noise%20Waves.jpg)

**Description:** Organic noise-based wave patterns with Perlin noise generation. Creates flowing, natural-looking wave textures with rich procedural detail.

**Inputs:** `scale` (float) [0.0001–0.1], `rate` (float) [0.001–3], `seed` (float) [8–233], `freq` (float) [3–73], `freq3` (float) [1–11], `colormod` (float) [0–1], `offset` (float) [0–1], `offset1` (float) [0.1–1], `flip` (bool), `invert` (bool)

---

### ParticularBehavior

![ParticularBehavior](screenshots/ParticularBehavior.jpg)

**Description:** Generates dynamic particle systems with complex mathematical behaviors. Creates swirling cosmic formations and meteor-like light trails.

**🎵 Audio:** `uniformName`→level

---

### Perlin Noise

![Perlin Noise](screenshots/Perlin%20Noise.jpg)

**Description:** Generates smooth, organic Perlin noise patterns for natural-looking textures. Time-based animation creates flowing, cloud-like movements.

**Inputs:** `scale` (float) [0–1]

---

### PolarGradient

![PolarGradient](screenshots/PolarGradient.jpg)

**Description:** Concentric polar gradients with sinusoidal color modulation creating rippling rainbow waves. Highly customizable with independent RGB loop controls and scaling parameters.

**Inputs:** `sMin` (float) [0–450], `sMax` (float) [500–1000], `rate` (float) [-5–5], `scale` (float) [0.1–10], `brightness` (float) [0.1–0.9], `Rloops` (float) [1–6], `Gloops` (float) [1–6], `Bloops` (float) [1–6], `Rs` (float) [-1.5–2.5], `Gs` (float) [-1.5–2.5], `Bs` (float) [-1.5–2.5], `Rg` (float) [-1–1], `Gg` (float) [-1–1], `Bg` (float) [-1–1]

---

### PrimeWaves

![PrimeWaves](screenshots/PrimeWaves.jpg)

**Description:** Produces flowing wave patterns using prime number algorithms to create rhythmic undulations. Mathematical waves ripple through space with calculated precision.

**Inputs:** `center` (point2D) [-10,-10–10,10], `rate` (float) [-3–3], `zoom` (float) [-10–10], `depth` (float) [0–1], `rxy` (float) [1–17], `rxz` (float) [1–17]

**🎵 Audio:** `uniformName`→mid

---

### Radar Sweeper

![Radar Sweeper](screenshots/Radar%20Sweeper.jpg)

**Description:** Classic radar sweep visualization with circular grid overlay and rotating scan beam. Creates nostalgic military-style monitoring display aesthetics.

---

### RainbowGradientTurbo

![RainbowGradientTurbo](screenshots/RainbowGradientTurbo.jpg)

**Description:** A vibrant rainbow gradient using the sophisticated Turbo colormap. Can be oriented vertically or horizontally for versatile color transitions.

**Inputs:** `vertical` (bool)

---

### RainbowGridWave

![RainbowGridWave](screenshots/RainbowGridWave.jpg)

**Description:** A vibrant rainbow grid that undulates with wave patterns created through Perlin noise. The colorful mesh creates hypnotic flowing geometries.

**Inputs:** `gridAmount` (float) [0–100], `gridAmountX` (float) [0–100], `gridAmountY` (float) [0–100], `gridWaveAutomaticFrequency` (bool), `gridWaveFrequency` (float) [-10–50], `gridWaveFrequencySpeed` (float) [-5–5], `gridWaveExtreme` (bool)

---

### RainbowRingCubicTwist

![RainbowRingCubicTwist](screenshots/RainbowRingCubicTwist.jpg)

**Description:** Rainbow-colored rings twist through cubic space transformations. Vibrant spectral bands curve and spiral with mesmerizing motion.

**Inputs:** `scale` (float) [0.1–2], `thickness` (float) [0.5–2], `twists` (float) [1–5], `rate` (float) [-2–2], `gamma` (float) [0.25–1]

**🎵 Audio:** `uniformName`→high

---

### Ramp Sinus Gradient

![Ramp Sinus Gradient](screenshots/Ramp%20Sinus%20Gradient.jpg)

**Description:** Simple gradient ramp between two color choices. Clean linear interpolation for foundational color blending effects.

**Inputs:** `colorA` (color), `colorB` (color), `offset` (float) [0–10]

**🎵 Audio:** `uniformName`→level

---

### RedCircleMoon

![RedCircleMoon](screenshots/RedCircleMoon.jpg)

**Description:** Produces hypnotic red circular patterns with moon-like crescents. Combines trigonometric functions for rhythmic, pulsating geometric forms.

**Inputs:** `colorInput` (color), `floatInputY` (float) [0–10], `floatRadius` (float) [0.25–1], `floatCircleSpread` (float) [0–100]

**🎵 Audio:** `uniformName`→floatInputY

---

### Simplex Noise

![Simplex Noise](screenshots/Simplex%20Noise.jpg)

**Description:** Generates procedural simplex noise patterns with harmonic layering. Creates organic, flowing textures with customizable complexity.

**Inputs:** `seed` (float) [0–1], `period` (float) [0.1–10], `harmonics` (float) [1–10], `harmonicSpread` (float) [0–5], `harmonicGain` (float) [0–5], `exponent` (float) [0–10], `amplitude` (float) [0–5], `speed` (float) [0–0.5], `shift` (float) [0–1]

---

### Simplex Noise RGB

![Simplex Noise RGB](screenshots/Simplex%20Noise%20RGB.jpg)

**Description:** Multi-channel simplex noise generator producing RGB color variations. Creates vibrant, organic noise patterns across color channels.

**Inputs:** `seed` (float) [0–1], `period` (float) [0.1–10], `harmonics` (float) [1–10], `harmonicSpread` (float) [0–5], `harmonicGain` (float) [0–5], `exponent` (float) [0–10], `amplitude` (float) [0–5], `speed` (float) [0–0.5], `shift` (float) [0–1]

---

### SoftPatterns+

![SoftPatterns+](screenshots/SoftPatterns%2B.jpg)

**Description:** Generates soft interference patterns with wave-like color gradients. Creates organic, flowing patterns reminiscent of water ripples or sound waves.

**Inputs:** `zoom` (float) [0–50], `iterations` (float) [0–10], `contrast` (float) [-20–20], `offset` (float) [0–1], `pattern` (float) [0–1], `rotate` (float) [-1–1], `color1` (color), `color2` (color)

**🎵 Audio:** `uniformName`→mid

---

### SpaceSpore

![SpaceSpore](screenshots/SpaceSpore.jpg)

**Description:** Generates organic, spore-like structures floating in 3D space. Raymarched cellular forms pulse and evolve with ethereal beauty.

**Inputs:** `O` (point2D) [0.01,0.01–0.99,0.99], `C` (point2D) [0,0–1,1], `R1` (float) [0–36], `R2` (float) [0–54], `zoom` (float) [1.1–5], `rate` (float) [-3–3], `depth` (float) [24–72], `gamma` (float) [0.25–1.25]

**🎵 Audio:** `uniformName`→bass

---

### Sphered Harmonics

![Sphered Harmonics](screenshots/Sphered%20Harmonics.jpg)

**Description:** Mathematical visualization of spherical harmonic functions resembling atomic orbitals. Creates ethereal 3D forms that pulse and morph through space.

**Inputs:** `matrix` (point2D) [-10,-10–10,10], `rate` (float) [0.01–2.5], `rotation` (float) [-2–2], `colorCycle` (float) [0.1–3], `warbble` (bool)

---

### Spider Spectrum

![Spider Spectrum](screenshots/Spider%20Spectrum.jpg)

**Description:** Intricate web-like patterns with spectral coloring. Generates complex spider-web structures with vibrant spectrum hues.

**Inputs:** `twist` (float) [1–5], `speed` (float), `fade` (float) [0–50], `twist2` (float) [0–20], `cork` (float) [0–4], `opacity` (float) [0–1], `clip` (float) [0–1]

**🎵 Audio:** `uniformName`→speed

---

### SpiderSpectre

![SpiderSpectre](screenshots/SpiderSpectre.jpg)

**Description:** Generates intricate spider-web fractal patterns with organic flowing geometries. Creates mesmerizing mathematical art with adjustable density and morphing parameters.

**Inputs:** `mouse` (point2D) [-3,-3–3,3], `rate` (float) [0.5–100], `zoom` (float) [-3–3], `offset1` (float) [-100–100], `density` (float) [1–18], `width` (float) [0.0025–0.125]

---

### Stars

![Stars](screenshots/Stars.jpg)

**Description:** Generates mesmerizing kaleidoscopic star fields with animated zoom and layered depth. Creates cosmic celestial patterns with customizable color and opacity.

**Inputs:** `opacity` (float), `color` (color), `speed` (float) [-1–1]

---

### SumDotz

![SumDotz](screenshots/SumDotz.jpg)

**Description:** Creates animated dot grid patterns with customizable scale and movement. Generates mesmerizing cellular automata-like visual textures.

**Inputs:** `scale` (float) [0.01–0.1], `rate` (float) [-3–3], `seed1` (float) [13–233], `seed2` (float) [5–198], `delta` (float) [0.001–0.99]

**🎵 Audio:** `uniformName`→rate

---

### TilePattern

![TilePattern](screenshots/TilePattern.jpg)

**Description:** Rotated square tiles form structured geometric grids. Clean modernist patterns with mathematical precision.

**Inputs:** `Rotate` (float) [0–2], `Offset` (float) [0–2], `Tiles` (float) [-20–20], `pos` (point2D) [0,0–1,1]

**🎵 Audio:** `uniformName`→beatPhase

---

### Truchet Tiles

![Truchet Tiles](screenshots/Truchet%20Tiles.jpg)

**Description:** Classic Truchet tiles create seamless flowing patterns. Geometric curves connect in infinite maze-like formations.

**Inputs:** `pos` (point2D) [0,0–1,1], `scale` (float) [0–20], `rotate` (float) [0–1], `patternZoom` (float) [0–1], `scalePos` (point2D) [0,0–1,1], `tiles` (float) [0–20]

**🎵 Audio:** `uniformName`→beatPhase

---

### TurbulentShapes

![TurbulentShapes](screenshots/TurbulentShapes.jpg)

**Description:** Generates hypnotic turbulent shapes with morphing geometry and flowing movement. Creates organic, ever-changing patterns perfect for abstract backgrounds.

**Inputs:** `zoom` (float) [1–60], `scale` (float) [-4–4], `spin` (float) [0–10], `turbulanceSpeed` (float) [0–2], `turbulanceZoom` (float) [0–1], `shape` (float) [0–8], `shapeShiftSpeed` (float) [0–8], `rotateCanvas` (float) [0–1], `centerTile` (bool), `pos` (point2D) [0,0–1,1], `posOffset` (point2D) [0,0–1,1]

---

### TwistyColoredBars

![TwistyColoredBars](screenshots/TwistyColoredBars.jpg)

**Description:** Twisted colorful vertical bars with rotation and spacing controls. Geometric patterns with smooth color gradients and animation.

**Inputs:** `scale` (float) [0.25–5], `rate` (float) [-2–2], `loops` (float) [1–16], `phase` (float) [0.001–0.999], `rot` (bool), `sparse` (bool)

**🎵 Audio:** `uniformName`→bassHits

---

### Volumetric Cloud

![Volumetric Cloud](screenshots/Volumetric%20Cloud.jpg)

**Description:** Generates billowing 3D volumetric clouds with realistic lighting. Organic procedural textures create atmospheric depth and movement.

**Inputs:** `grow` (float) [0.001–10], `density` (float) [0.001–1], `density2` (float) [0.001–1], `rotation` (float) [0–2.5], `zoom` (float) [0.25–1.5], `light` (float) [0.1–1]

**🎵 Audio:** `uniformName`→level

---

### Volumetric Cloud 2

![Volumetric Cloud 2](screenshots/Volumetric%20Cloud%202.jpg)

**Description:** Enhanced volumetric cloud generator with additional density controls. Creates dramatic atmospheric effects with customizable lighting and rotation.

**Inputs:** `grow` (float) [0.001–10], `density` (float) [0.001–1], `density2` (float) [0.001–1], `rotation` (float) [0–2.5], `zoom` (float) [0.25–1.5], `mod1` (float) [0.25–1.5], `mod2` (float) [0.25–1.5], `mod3` (float) [0–1.8], `light` (float) [0.1–1], `lighteffect` (float) [0.1–1]

**🎵 Audio:** `uniformName`→bass

---

### Wave Shape Osc

![Wave Shape Osc](screenshots/Wave%20Shape%20Osc.jpg)

**Description:** Dynamic wave oscillator generating flowing, undulating patterns. Creates mesmerizing wave forms with customizable intensity and movement speed.

**Inputs:** `speed` (float) [0.1–5], `wave_intensity` (float) [0.1–2], `color` (color), `brightness` (float) [0.01–0.1], `zoom` (float) [0.5–2]

---

### Waveform 2

![Waveform 2](screenshots/Waveform%202.jpg)

**Description:** Animated waveform visualization with multiple oscillating lines. Creates flowing sine wave patterns with adjustable speed and amplitude for dynamic audio-visual sync.

**Inputs:** `baseSpeed` (float) [0–5], `baseHeight` (float) [0–10], `blur` (float) [0–1], `color1` (color), `color2` (color)

**🎵 Audio:** `uniformName`→level

---

### WaveLines

![WaveLines](screenshots/WaveLines.jpg)

**Description:** Flowing wave line patterns that undulate and twist across the screen. Generates organic, rhythmic line art with customizable amplitude and frequency.

**Inputs:** `amp` (float) [0–2], `glow` (float) [-20–-0.5], `mod1` (float) [-0.5–0.5], `mod2` (float) [-0.2–0.2], `zoom` (float) [1–16], `rotateCanvas` (float) [0–1], `scroll` (float) [0–1], `twisted` (float) [0–0.06]

**🎵 Audio:** `uniformName`→mid

---

### Wisps

![Wisps](screenshots/Wisps.jpg)

**Description:** Flowing wisps of light dance across the canvas. Ethereal wave forms twist and undulate with graceful motion.

**Inputs:** `lines` (float) [1–200], `linesStartOffset` (float) [0–1], `amp` (float) [0–1], `glow` (float) [-40–0], `mod1` (float) [0–1], `mod2` (float) [-1–1], `twisted` (float) [-0.5–0.5], `zoom` (float) [0–100], `rotateCanvas` (float) [0–1], `scroll` (float) [0–1], `pos` (point2D) [0,0–1,1]

**🎵 Audio:** `uniformName`→beatPhase

---

### z33d+

![z33d+](screenshots/z33d%2B.jpg)

**Description:** Generates complex fractal geometries with swirling 3D transformations and organic mathematical structures. Deep recursive patterns emerge from chaotic mathematical beauty.

**Inputs:** `mX` (float) [0–2], `mY` (float) [0–2], `rate` (float) [-3–3], `e` (float) [0.0005–0.1]

**🎵 Audio:** `uniformName`→bass

---

### Zebre

![Zebre](screenshots/Zebre.jpg)

**Description:** Generates dynamic zebra-like stripes with organic noise distortion. Wood-grain textures meet flowing linear patterns.

**Inputs:** `lineScale` (float) [0.0005–10], `harmonic` (float) [0–200], `lineOffsetSpeed` (float) [0–100], `brightness` (float) [0.1–10], `contrast` (float) [0–0.5], `contrastShift` (float) [-0.5–0.5], `randomMultiply` (float) [0–50000], `randomAmt` (point2D) [0,0–100,100], `origin` (point2D) [0,0–1,1], `xyStretch` (point2D) [0,0–100,100], `xyNoiseFactor` (point2D) [0,0–100,100]

**🎵 Audio:** `uniformName`→bass

---

## Effects

*Filters — modify and transform input images*

### 3d Displacement

![3d Displacement](screenshots/3d%20Displacement.jpg)

**Description:** Creates stunning 3D displacement effects by extruding input textures into volumetric space. Features interactive rotation and depth controls for immersive visual transformation.

**Inputs:** `rotationY` (float) [0–1], `rotationZ` (float) [0–1], `zoom` (float) [0–1], `depth` (float) [0.03–1], `treshold` (float) [0–1]

---

### 3d Stone

![3d Stone](screenshots/3d%20Stone.jpg)

**Description:** 3D stone relief effect using raymarching and height displacement. Transforms flat images into dimensional carved stone surfaces with realistic lighting.

**Inputs:** `treshold` (float) [0.03–0.8], `rotation` (float) [0–1], `zoom` (float) [0.03–1], `iterations` (float) [15–30]

---

### ASCII

![ASCII](screenshots/ASCII.jpg)

**Description:** Converts imagery into retro ASCII character art. Transforms visual content into nostalgic text-based representations.

**Inputs:** `size` (float) [0–1], `gamma` (float) [0.5–2], `tint` (float) [0–1], `tintColor` (color), `alphaMode` (bool)

**🎵 Audio:** `uniformName`→size

---

### BinarySubdivisionScroller

![BinarySubdivisionScroller](screenshots/BinarySubdivisionScroller.jpg)

**Description:** Binary subdivision scrolling effect that creates recursive geometric transformations. Creates mesmerizing mathematical patterns that subdivide and scroll through the image.

**Inputs:** `reverse` (bool), `rate` (float) [0.01–2.5]

**🎵 Audio:** `uniformName`→beatPhase

---

### Black & White

![Black & White](screenshots/Black%20%26%20White.jpg)

**Description:** Classic desaturation effect that converts images to black and white using luminance coefficients. Features adjustable blending amount for partial or complete monochrome conversion.

**Inputs:** `amount` (float)

---

### Bokeh Blur

![Bokeh Blur](screenshots/Bokeh%20Blur.jpg)

**Description:** Circular bokeh blur with randomized sampling for natural depth-of-field effects. Creates smooth out-of-focus areas with authentic lens-like blur quality.

**Inputs:** `AMOUNT` (float) [0–1], `MAXRADIUS` (float) [0–1], `JITTER` (bool)

---

### Boxinator

![Boxinator](screenshots/Boxinator.jpg)

**Description:** Transforms images into stylized grid-based representations with noise variations. Converts continuous imagery into geometric, pixelated art forms.

**Inputs:** `rate` (float) [0–10], `edge` (float) [0–0.01], `blend` (float) [-1–1], `randomize` (float) [0–1], `gamma` (float) [-0.5–0.2], `grid` (point2D) [1.5,1.5–900,600]

**🎵 Audio:** `uniformName`→rate

---

### Brighter

![Brighter](screenshots/Brighter.jpg)

**Description:** Simple brightness adjustment filter with additive or multiplicative modes. Clean luminosity control for exposure correction and mood enhancement.

**Inputs:** `brightness` (float) [0–1], `multiply` (bool)

---

### Bulge

![Bulge](screenshots/Bulge.jpg)

**Description:** Creates smooth bulging distortion effects with controllable radius and scale. Transforms flat surfaces into organic, bubble-like protrusions.

**Inputs:** `radius` (float) [0–1], `scale` (float) [0–1], `center` (point2D)

**🎵 Audio:** `uniformName`→scale

---

### BW to Color

![BW to Color](screenshots/BW%20to%20Color.jpg)

**Description:** Dynamic color intensity filter transitioning from grayscale to vibrant saturation. Perfect for mood-driven color grading and emotional visual shifts.

**Inputs:** `intensity` (float) [0–1]

**🎵 Audio:** `uniformName`→level

---

### Chroma Key

![Chroma Key](screenshots/Chroma%20Key.jpg)

**Description:** Professional chroma key filter for green screen removal. Precise color matching with smooth edge blending for clean compositing.

**Inputs:** `thresholdSensitivity` (float) [0–1], `smoothing` (float) [0–1], `colorToReplace` (color)

**🎵 Audio:** `uniformName`→high

---

### Circle Warp

![Circle Warp](screenshots/Circle%20Warp.jpg)

**Description:** Warps rectangular images into circular formats with radial mapping. Perfect for creating porthole effects and circular displays.

**Inputs:** `radius` (float) [0–0.5], `width` (float) [0–2], `resultRotation` (float) [0–1]

---

### Color Control

![Color Control](screenshots/Color%20Control.jpg)

**Description:** Complete color adjustment filter for brightness, contrast, hue and saturation control. Essential tool for fine-tuning the visual appearance of any input.

**Inputs:** `bright` (float) [-1–1], `contrast` (float) [-4–4], `hue` (float) [-1–1], `saturation` (float) [0–4]

---

### Color Flip

![Color Flip](screenshots/Color%20Flip.jpg)

**Description:** Inverts and shifts colors while blending complementary hues for dramatic visual impact. Creates striking color transformations with customizable saturation and intensity.

**Inputs:** `amount` (float) [0–1], `color` (float) [0–1], `saturate` (float) [0–1]

**🎵 Audio:** `uniformName`→high

---

### Contrast

![Contrast](screenshots/Contrast.jpg)

**Description:** Dynamic contrast enhancement that amplifies visual separation. Sharpens the distinction between light and dark.

**Inputs:** `contrast` (float)

**🎵 Audio:** `uniformName`→level

---

### Corner Color Tint

![Corner Color Tint](screenshots/Corner%20Color%20Tint.jpg)

**Description:** Corner color tinting filter that preserves luminance while adding gradient overlays. Applies rotatable four-corner color grading to input images.

**Inputs:** `color1` (color), `color2` (color), `color3` (color), `color4` (color), `rotationAngle` (float) [0–1]

---

### Cubic_Warp

![Cubic_Warp](screenshots/Cubic_Warp.jpg)

**Description:** Applies cubic lens distortion with adjustable intensity and center point. Warps reality with mathematical precision for surreal visual transformations.

**Inputs:** `level` (float) [0–2], `center` (point2D) [0,0–1,1]

**🎵 Audio:** `uniformName`→level

---

### Dancing Flower

![Dancing Flower](screenshots/Dancing%20Flower.jpg)

**Description:** Creates blooming, organic feedback patterns that selectively replace darker image areas. Generates flowing, flower-like visual growth with natural movement.

**Inputs:** `amount` (float), `movement` (float)

---

### Darker

![Darker](screenshots/Darker.jpg)

**Description:** A simple brightness filter that darkens input images with adjustable intensity. Clean and minimal color adjustment tool.

**Inputs:** `brightness` (float) [-1–0], `multiply` (bool)

---

### Displace

![Displace](screenshots/Displace.jpg)

**Description:** Warps and displaces input images using smooth noise patterns for liquid distortion effects. Creates flowing displacement that bends reality with organic movement.

**Inputs:** `amount` (float) [0–1], `strength` (float) [0–1], `scale` (float) [0–1], `speed` (float) [0–1]

**🎵 Audio:** `uniformName`→mid

---

### Displace From Texture

![Displace From Texture](screenshots/Displace%20From%20Texture.jpg)

**Description:** Displaces input images using luminance from a secondary texture. Creates flowing distortion effects based on displacement maps.

**Inputs:** `displaceImage` (image), `xAmount` (float) [0–1], `yAmount` (float) [0–1]

---

### Displace Glass

![Displace Glass](screenshots/Displace%20Glass.jpg)

**Description:** Glass-like displacement effect that refracts and bends input imagery. Simulates looking through rippling water or textured glass.

**Inputs:** `amount` (float) [0–1], `strength` (float) [0–1], `scale` (float) [0–1], `speed` (float) [0–1]

**🎵 Audio:** `uniformName`→bass

---

### Displace Perlin

![Displace Perlin](screenshots/Displace%20Perlin.jpg)

**Description:** Organic displacement effect using Perlin noise to warp and distort input imagery. Creates flowing, natural-looking deformations.

**Inputs:** `amount` (float) [0–1], `strength` (float) [0–1], `scale` (float) [0–1], `speed` (float) [0–1]

**🎵 Audio:** `uniformName`→bass

---

### Dither Blur

![Dither Blur](screenshots/Dither%20Blur.jpg)

**Description:** Applies a sophisticated dithered blur with organic randomization. Creates dreamy, painterly textures that breathe with subtle movement.

**Inputs:** `amount` (float) [0–1], `radius` (float) [0–1], `JITTER` (bool)

**🎵 Audio:** `uniformName`→mid

---

### Dither Floyd

![Dither Floyd](screenshots/Dither%C2%A0Floyd.jpg)

**Description:** Converts images to high-contrast dithered patterns using Floyd-Steinberg algorithm. Creates retro computer graphics aesthetic with customizable error diffusion.

**Inputs:** `errorCarry` (float) [0–1], `colorize` (float) [0–1], `lookupSize` (long)

---

### Droste Regression

![Droste Regression](screenshots/Droste%20Regression.jpg)

**Description:** Creates mind-bending infinite regression effects with recursive image spiraling. Transforms any input into a mesmerizing droste illusion.

**Inputs:** `twist` (float) [0.1–2], `amount` (float) [0–1]

---

### Duotone

![Duotone](screenshots/Duotone.jpg)

**Description:** Converts images to high-contrast two-tone aesthetics based on luminance thresholds. Customizable bright and dark colors create dramatic poster-like effects.

**Inputs:** `threshold` (float), `softness` (float) [0–1], `brightColor` (color), `darkColor` (color)

---

### Echo Trace.fs

![Echo Trace.fs](screenshots/Echo%20Trace.fs.jpg)

**Description:** Freezes bright pixels in place while allowing darker areas to update normally. Creates ghostly persistence effects where luminous elements leave trailing echoes.

**Inputs:** `thresh` (float) [0–1], `gain` (float) [0–2], `hardCutoff` (bool), `invert` (bool)

**🎵 Audio:** `uniformName`→level

---

### Edge Detection

![Edge Detection](screenshots/Edge%20Detection.jpg)

**Description:** Reveals the hidden boundaries within images through sophisticated gradient analysis. Transforms photographs into stark line drawings that emphasize structural forms.

**Inputs:** `WIDTH` (float) [0–1]

**🎵 Audio:** `uniformName`→mid

---

### Edges.fs

![Edges.fs](screenshots/Edges.fs.jpg)

**Description:** Detects and highlights edges using Sobel operators for crisp line art. Transforms images into stark, graphic silhouettes.

**Inputs:** `intensity` (float) [0–50], `threshold` (float) [0–1], `sobel` (bool), `opaque` (bool)

---

### Extrude

![Extrude](screenshots/Extrude.jpg)

**Description:** Creates a 3D extrusion effect that transforms 2D images into dimensional block structures. Dynamic mouse controls enable interactive perspective manipulation.

**Inputs:** `size` (float) [0–1], `FAR` (float) [0–1], `mX` (float) [0–1], `mY` (float) [0–1], `mZ` (float) [0–1], `mW` (float) [0–1]

---

### Extrude 2

![Extrude 2](screenshots/Extrude%202.jpg)

**Description:** Creates 3D extrusion effects from 2D images using height mapping. Transforms flat imagery into dimensional landscapes.

**Inputs:** `size` (float) [0.1–1], `zGain` (float) [0.1–4], `FAR` (float) [0.1–1], `timeSpeed` (float) [0.1–2], `rotationSpeed` (float) [0–1]

**🎵 Audio:** `uniformName`→bass

---

### Fade Side

![Fade Side](screenshots/Fade%20Side.jpg)

**Description:** Directional fade transition that progressively reveals or conceals imagery from left or right side. Smooth gradient masking with adjustable edge softness for seamless wipes.

**Inputs:** `progress` (float), `smoothing` (float), `fromLeft` (bool)

---

### False Color Flip.fs

![False Color Flip.fs](screenshots/False%20Color%20Flip.fs.jpg)

**Description:** Transforms image luminance into vibrant false color mapping. Blend bright and dark color choices to create striking thermal-like effects.

**Inputs:** `brightColor` (color), `darkColor` (color), `amount` (float)

**🎵 Audio:** `uniformName`→level

---

### Feedback Color Loop Mod

![Feedback Color Loop Mod](screenshots/Feedback%20Color%20Loop%20Mod.jpg)

**Description:** Color feedback processor with hue shifting, contrast and saturation adjustments. Transforms input imagery through chromatic mutations.

**Inputs:** `light` (float), `contrast` (float), `hueShift` (float), `saturation` (float), `biasAmount` (float)

**🎵 Audio:** `uniformName`→high

---

### Feedback Geo Loop Mod

![Feedback Geo Loop Mod](screenshots/Feedback%20Geo%20Loop%20Mod.jpg)

**Description:** Geometric feedback transformer applying rotation, scaling and translation to input imagery. Creates recursive visual loops and spatial shifts.

**Inputs:** `zoom` (float), `rotate` (float), `width` (float), `height` (float), `x` (float), `y` (float), `biasAmount` (float)

**🎵 Audio:** `uniformName`→mid

---

### Feedback Loop

![Feedback Loop](screenshots/Feedback%20Loop.jpg)

**Description:** Creates persistent feedback loops with customizable trails and color shifts. Features zoom, rotation, and selective bleedthrough for dynamic layering effects.

**Inputs:** `feedback` (float) [0–1], `hue` (float), `saturation` (float), `zoom` (float), `brightness` (float), `bleedthrough` (float), `rotation` (float)

---

### Feedback Loop Mod

![Feedback Loop Mod](screenshots/Feedback%20Loop%20Mod.jpg)

**Description:** Psychedelic feedback loop that creates swirling, color-shifting trails from input imagery. Combines rotation, zoom, and hue modulation for trippy visual transformations.

**Inputs:** `zoom` (float), `spin` (float), `huemod` (float), `saturation` (float), `brightness` (float), `random` (float)

---

### Feedback Reverb

![Feedback Reverb](screenshots/Feedback%20Reverb.jpg)

**Description:** Creates ethereal trailing effects with customizable feedback loops and blur controls. Perfect for ghostly motion persistence and dreamlike visual echoes.

**Inputs:** `feedback` (float) [0–1], `highPass` (float), `lowPass` (float), `zoom` (float), `yPos` (float) [-0.5–0.5], `darken` (float)

**🎵 Audio:** `uniformName`→feedback

---

### Film Filter

![Film Filter](screenshots/Film%20Filter.jpg)

**Description:** Comprehensive film look processor with levels, vignette and vibrance adjustments. Adds cinematic warmth and vintage character to any source material.

**Inputs:** `gamma` (float), `exposure` (float), `blackLevel` (float), `whiteLevel` (float), `contrast` (float), `vignette` (float), `vibrance` (float) [-3–4]

**🎵 Audio:** `uniformName`→bass

---

### Fisheye Bounce

![Fisheye Bounce](screenshots/Fisheye%20Bounce.jpg)

**Description:** Fisheye distortion with chromatic color separation. Applies barrel distortion while splitting colors into rainbow dispersions.

**Inputs:** `amount` (float) [0–2]

**🎵 Audio:** `uniformName`→amount

---

### Fluidity

![Fluidity](screenshots/Fluidity.jpg)

**Description:** Advanced optical flow processor creating liquid motion trails and feedback. Transforms input into flowing, organic visual streams.

**Inputs:** `flowAmount` (float) [0–1], `flowHold` (float) [0.95–0.99], `motionScale` (float) [0–10], `zoom` (float) [0.95–1.05], `spin` (float) [-0.1–0.1]

**🎵 Audio:** `uniformName`→mid

---

### Frame Diff

![Frame Diff](screenshots/Frame%20Diff.jpg)

**Description:** Analyzes motion between consecutive frames to highlight areas of movement and change. Creates ghostly difference masks revealing temporal dynamics in video.

**Inputs:** `gain` (float)

---

### Frame Diff Variable

![Frame Diff Variable](screenshots/Frame%20Diff%20Variable.jpg)

**Description:** Motion detection analyzer comparing current and previous frames. Highlights areas of movement while preserving static elements.

**Inputs:** `color` (float), `motionThreshold` (float), `sludge` (float)

**🎵 Audio:** `uniformName`→level

---

### Freeze Buffer

![Freeze Buffer](screenshots/Freeze%20Buffer.jpg)

**Description:** Captures and freezes video frames at timed intervals creating stuttering temporal effects. Perfect for creating rhythmic visual pauses and dramatic freeze moments.

**Inputs:** `delay` (float)

---

### Gamma

![Gamma](screenshots/Gamma.jpg)

**Description:** Smooth gamma correction for luminance adjustment. Brightens shadows while preserving highlight detail.

**Inputs:** `gamma` (float) [0–1]

**🎵 Audio:** `uniformName`→level

---

### Gaussian Blur

![Gaussian Blur](screenshots/Gaussian%20Blur.jpg)

**Description:** Multi-pass optimized Gaussian blur with variable intensity control. Efficiently blurs images through downsampling and intelligent upsampling techniques.

**Inputs:** `blurAmount` (float) [0–24]

---

### Glitcher

![Glitcher](screenshots/Glitcher.jpg)

**Description:** Digital glitch effect with chromatic aberration and horizontal distortions. Creates retro data corruption artifacts with adjustable intensity.

**Inputs:** `amount` (float) [0–0.5]

---

### Hue Spin Feedback

![Hue Spin Feedback](screenshots/Hue%20Spin%20Feedback.jpg)

**Description:** Generates mesmerizing feedback trails that spin and evolve based on color hue values. Creates organic, flowing patterns with persistent visual echoes.

**Inputs:** `feedback` (float), `spin` (float), `random` (float), `saturation` (float), `brightness` (float), `zoom` (float), `huemod` (float)

---

### Infinite Spiral Zoom

![Infinite Spiral Zoom](screenshots/Infinite%20Spiral%20Zoom.jpg)

**Description:** Hypnotic spiral transformation that pulls imagery into infinite recursive depths. Creates mesmerizing kaleidoscope tunnels.

**Inputs:** `SPEED` (float) [0–1], `SYMMETRY` (float) [-8–8], `SPIRALICITY` (float) [0–0.5]

**🎵 Audio:** `uniformName`→beatPhase

---

### infinite zoom

![infinite zoom](screenshots/infinite%20zoom.jpg)

**Description:** Creates an infinite zooming tunnel effect by transforming input imagery into polar coordinates. Produces mesmerizing recursive depth with customizable speed and direction controls.

**Inputs:** `t` (float) [0–10], `speed` (float) [-1–1], `Wsource` (float) [0–10000], `Hsource` (float) [0–10000], `flipH` (bool), `flipW` (bool)

---

### JPG Glitch

![JPG Glitch](screenshots/JPG%20Glitch.jpg)

**Description:** Corrupts images with digital compression artifacts and blocky noise patterns. Creates authentic JPEG-style glitch distortions that fragment and pixelate the source material.

**Inputs:** `noiseSpeed` (float) [0–1], `noiseAmount` (float) [0–1], `blockSize` (float) [0–1]

**🎵 Audio:** `uniformName`→bassHits

---

### Kaleidoscope

![Kaleidoscope](screenshots/Kaleidoscope.jpg)

**Description:** Transforms images into mesmerizing kaleidoscope patterns with configurable symmetry. Creates radial mirrored segments that can be adjusted for sides, rotation, and positioning.

**Inputs:** `sides` (float) [1–32], `angle` (float) [-1–1], `slidex` (float) [0–1], `slidey` (float) [0–1]

---

### KIFS Fractal

![KIFS Fractal](screenshots/KIFS%20Fractal.jpg)

**Description:** Kaleidoscopic fractal transformation using iterative mirroring and rotation. Transforms input images into intricate, symmetrical fractal patterns.

**Inputs:** `offset` (float) [0–1], `rotation` (float) [14.3–15.8], `zoomLevel` (float) [0.5–2]

---

### Lidar Animated

![Lidar Animated](screenshots/Lidar%20Animated.jpg)

**Description:** Creates a mesmerizing 3D point cloud visualization from input images. Animated depth mapping transforms flat surfaces into dynamic lidar-style landscapes.

**Inputs:** `DEPTH` (float) [5–100], `EXTRUSION` (float) [-1–1], `SAMPLERADIUS` (float) [0–20], `SAMPLES` (float) [16–128], `CHUNKINESS` (float) [-20–20], `WARPFACTORA` (float) [0.025–5], `WARPFACTORB` (float) [0–5], `OVERLOAD` (float) [0–1], `TIMEOFFSET` (float) [0–1], `TIMEDILATION` (float) [-1–1], `SPEED` (float) [0–50], `GAMMA` (float) [0–10]

**🎵 Audio:** `uniformName`→bpm

---

### Logo Extrude

![Logo Extrude](screenshots/Logo%20Extrude.jpg)

**Description:** Projects flat logos into three-dimensional space with dynamic perspective shifts. Creates the illusion of depth and volume from simple graphic elements.

**Inputs:** `treshold` (float) [0–1], `rotation` (float) [0–1], `zoom` (float) [0–1], `iterations` (float) [15–30]

**🎵 Audio:** `uniformName`→bass

---

### Long Zoom

![Long Zoom](screenshots/Long%20Zoom.jpg)

**Description:** Creates smooth zoom distortion effects from any center point. Generates tunnel-like perspectives and dynamic scaling transformations.

**Inputs:** `level` (float) [0.1–1.9], `center` (point2D)

**🎵 Audio:** `uniformName`→bass

---

### Luma Key

![Luma Key](screenshots/Luma%20Key.jpg)

**Description:** Removes pixels based on luminance values, creating transparency masks. Essential tool for green screen and keying workflows.

**Inputs:** `threshold` (float) [0–1], `softness` (float) [0–1]

---

### Manual Strobe

![Manual Strobe](screenshots/Manual%20Strobe.jpg)

**Description:** Manual strobe effect that blends input imagery with color overlays. Provides controlled flash effects with phase-based color mixing for dramatic lighting.

**Inputs:** `colorInput` (color), `phase` (float)

**🎵 Audio:** `uniformName`→beatPhase

---

### Matrix Rain

![Matrix Rain](screenshots/Matrix%20Rain.jpg)

**Description:** Transforms input imagery into cascading green digital rain reminiscent of The Matrix. Cyberpunk streams flow down the screen with authentic retro computer aesthetics.

**Inputs:** `rainSpeed` (float) [0.1–10], `DropSize` (float) [0–9]

**🎵 Audio:** `uniformName`→bassHits

---

### Micro Buffer.fs

![Micro Buffer.fs](screenshots/Micro%20Buffer.fs.jpg)

**Description:** Buffers multiple recent frames for sophisticated temporal glitching and delay effects. Creates complex feedback loops and temporal distortions with adjustable lag.

**Inputs:** `inputDelay` (float) [0–9], `inputRate` (float) [0–20]

---

### Mirror Edge Zoom

![Mirror Edge Zoom](screenshots/Mirror%20Edge%20Zoom.jpg)

**Description:** Kaleidoscopic mirroring with zoom scaling from customizable focal points. Creates symmetric crystalline reflections.

**Inputs:** `angle` (float) [0–1], `level` (float) [0.2–1.5], `shift` (point2D)

**🎵 Audio:** `uniformName`→bass

---

### Mirror.fs

![Mirror.fs](screenshots/Mirror.fs.jpg)

**Description:** Simple mirroring effect that reflects image content horizontally and vertically. Creates symmetrical compositions by duplicating half of the image across chosen axes.

**Inputs:** `horizontal` (bool), `vertical` (bool)

---

### Moshed

![Moshed](screenshots/Moshed.jpg)

**Description:** Optical flow glitch effect that creates datamoshing-style visual artifacts. Motion detection drives surreal image warping and temporal bleeding.

**Inputs:** `flowAmount` (float) [0–1], `flowHold` (float) [0.95–0.99], `motionScale` (float) [0–10], `zoom` (float) [0.95–1.05], `spin` (float) [-0.1–0.1]

**🎵 Audio:** `uniformName`→beatPhase

---

### Motion Distort

![Motion Distort](screenshots/Motion%20Distort.jpg)

**Description:** Motion-based distortion effect using gradient analysis for glitch aesthetics. Creates datamosh-style artifacts from motion vectors.

**Inputs:** `motionImage` (image), `feedback` (float), `amount` (float) [0–1], `sensivity` (float) [0–10]

---

### Noise

![Noise](screenshots/Noise.jpg)

**Description:** Adds organic hash-based noise texture with temporal variation. Creates film grain and analog warmth with digital precision.

**Inputs:** `noiseLevel` (float) [0–1]

**🎵 Audio:** `uniformName`→level

---

### Noisey Dirt

![Noisey Dirt](screenshots/Noisey%20Dirt.jpg)

**Description:** Film grain overlay adding organic texture and vintage character. Brings authentic analog warmth to digital imagery.

**Inputs:** `intensity` (float) [0–1], `noise` (float) [0–1], `scale` (float) [0.1–4], `speed` (float) [0–4]

**🎵 Audio:** `uniformName`→highHits

---

### One Color

![One Color](screenshots/One%20Color.jpg)

**Description:** Simple solid color overlay effect that replaces input imagery. Provides clean color fills with adjustable opacity for graphic compositions.

**Inputs:** `colorInput` (color), `alpha` (float)

**🎵 Audio:** `uniformName`→beatPhase

---

### Pinch Distort

![Pinch Distort](screenshots/Pinch%20Distort.jpg)

**Description:** Applies radial pinch distortion effects that warp and squeeze input imagery toward center points. Creates dramatic lens-like distortions with expand/contract modes.

**Inputs:** `amount` (float) [0–1], `expand` (bool)

---

### Radial Blur

![Radial Blur](screenshots/Radial%20Blur.jpg)

**Description:** Creates a mesmerizing radial blur that radiates outward from a central point. Perfect for adding motion and energy to any visual.

**Inputs:** `x` (float) [0–1], `y` (float) [0–1], `amount` (float) [0–1], `strength` (float) [0–1], `jitter` (float) [0–20]

**🎵 Audio:** `uniformName`→bass

---

### Radial Replicate

![Radial Replicate](screenshots/Radial%20Replicate.jpg)

**Description:** Replicates radial slices of input image to create kaleidoscopic symmetries. Perfect for creating mandala-like geometric transformations.

**Inputs:** `postRotateAngle` (float) [0–360], `numberOfDivisions` (float) [1–360], `preRotateAngle` (float) [-180–180], `centerRadiusStart` (float) [0–1], `centerRadiusEnd` (float) [0–2]

**🎵 Audio:** `uniformName`→beatPhase

---

### Random Freeze

![Random Freeze](screenshots/Random%20Freeze.jpg)

**Description:** Randomly freezes sections of the input image creating glitchy update patterns. Controlled chaos for digital artifacts.

**Inputs:** `maxUpdateSize` (float) [0–1], `maxBlendAmount` (float) [0–1], `resetImage` (event)

**🎵 Audio:** `uniformName`→bassHits

---

### Random Sample Color

![Random Sample Color](screenshots/Random%20Sample%20Color.jpg)

**Description:** Glitch effect that randomly samples image regions and replaces them with duotone colorization. Creates fragmented color bleeding across the original image.

**Inputs:** `maxUpdateSize` (float) [0–1], `seedShift` (float) [0–1], `brightColor` (color), `darkColor` (color), `maxBlendAmount` (float) [0–1], `manual` (bool)

---

### Random Sample Feedback

![Random Sample Feedback](screenshots/Random%20Sample%20Feedback.jpg)

**Description:** Glitch effect that randomly samples and updates rectangular regions of the image. Creates stuttering feedback loops with controllable decay and blending.

**Inputs:** `maxUpdateSize` (float) [0–1], `fadeSpeed` (float) [0–1], `seedShift` (float) [0–1], `maxBlendAmount` (float) [0–1], `manual` (bool)

---

### Refractor

![Refractor](screenshots/Refractor.jpg)

**Description:** Self-refracting distortion effect that uses the input image as its own displacement map. Creates liquid-like warping and organic distortions.

**Inputs:** `XAMOUNT` (float) [-1–1], `YAMOUNT` (float) [-1–1]

**🎵 Audio:** `uniformName`→high

---

### Repeat

![Repeat](screenshots/Repeat.jpg)

**Description:** Creates seamless repeating tiles of the input image with adjustable repetition count. Perfect for creating kaleidoscopic patterns.

**Inputs:** `repeats` (float) [1–20]

**🎵 Audio:** `uniformName`→repeats

---

### RepeatY

![RepeatY](screenshots/RepeatY.jpg)

**Description:** Vertical tiling effect that repeats the image with seamless junctions. Creates kaleidoscopic repetition patterns with adjustable crop control.

**Inputs:** `repeats` (float) [1–20], `crop` (float) [0–1]

---

### Rutt Etra Lookalike

![Rutt Etra Lookalike](screenshots/Rutt%20Etra%20Lookalike.jpg)

**Description:** Recreation of the classic Rutt Etra video synthesizer, transforming input images into distinctive line-based distortions. Converts video into sculptural wireframe visualizations.

**Inputs:** `LineNum` (float) [0–0.05], `Brightness` (float) [0–10], `Animation` (float) [0–0.1], `Depth` (float) [0–200], `LineWidth` (float) [0–5]

---

### Shake.fs

![Shake.fs](screenshots/Shake.fs.jpg)

**Description:** Simulates chaotic camera shake with randomized displacement and rotation. Adds kinetic energy and unstable motion to any footage.

**Inputs:** `magnitude` (float) [0–2], `intensity` (float) [0–10]

---

### Sharpen

![Sharpen](screenshots/Sharpen.jpg)

**Description:** Enhances image clarity by amplifying contrast between neighboring pixels. Brings crisp definition to soft or blurry content through intelligent edge enhancement.

**Inputs:** `sharpenAmount` (float) [0–20]

**🎵 Audio:** `uniformName`→high

---

### Sharpen Luminance.fs

![Sharpen Luminance.fs](screenshots/Sharpen%20Luminance.fs.jpg)

**Description:** Luminance-based sharpening filter that enhances edge definition by analyzing grayscale values. Intensifies detail contrast while preserving color information for crisp imagery.

**Inputs:** `intensity` (float) [0–2]

---

### Sharpen RGB.fs

![Sharpen RGB.fs](screenshots/Sharpen%20RGB.fs.jpg)

**Description:** RGB channel-specific sharpening with independent intensity controls per color. Advanced edge enhancement allowing fine-tuned color contrast manipulation.

**Inputs:** `intensityR` (float) [0–10], `intensityG` (float) [0–10], `intensityB` (float) [0–10]

---

### Sharpen Squared

![Sharpen Squared](screenshots/Sharpen%20Squared.jpg)

**Description:** Advanced sharpening filter enhancing edge definition and detail clarity. Operates in square-root color space for refined processing.

**Inputs:** `sharpenStrength` (float) [0–120]

**🎵 Audio:** `uniformName`→high

---

### Shift Hue

![Shift Hue](screenshots/Shift%20Hue.jpg)

**Description:** Smoothly shifts hue while preserving luminance and saturation balance. Creates fluid color transformations across the spectrum.

**Inputs:** `amount` (float)

**🎵 Audio:** `uniformName`→beatPhase

---

### Shift Position.fs

![Shift Position.fs](screenshots/Shift%20Position.fs.jpg)

**Description:** Repositions image content with seamless wrapping and optional mirroring effects. Enables precise geometric transformations while maintaining visual continuity.

**Inputs:** `slide` (float) [0–2], `shift` (float) [0–2], `mirrorHorizontal` (bool) [false–true], `mirrorVertical` (bool) [false–true]

**🎵 Audio:** `uniformName`→bpm

---

### Short Zoom

![Short Zoom](screenshots/Short%20Zoom.jpg)

**Description:** Simple zoom distortion effect that scales the image from a customizable center point. Clean geometric scaling perfect for rhythmic pulsing effects.

**Inputs:** `level` (float) [0.8–1.2], `center` (point2D)

**🎵 Audio:** `uniformName`→level

---

### Simple Feedback

![Simple Feedback](screenshots/Simple%20Feedback.jpg)

**Description:** Generates video feedback loops with zoom and decay controls. Creates trailing ghost images that build up over time for psychedelic visual persistence effects.

**Inputs:** `amount` (float) [0–1], `zoom` (float) [0–1], `darken` (float) [0–1]

---

### Sine Distortion

![Sine Distortion](screenshots/Sine%20Distortion.jpg)

**Description:** Applies sinusoidal wave distortions to create fluid, wavy transformations. Adjustable frequency and amplitude create rhythmic visual undulations.

**Inputs:** `distortion` (float) [0–5], `frequency` (float) [0–1], `period` (float) [0–1]

---

### Smear Out

![Smear Out](screenshots/Smear%20Out.jpg)

**Description:** Gradually blends current frames with previous ones to create smooth temporal smearing. Produces flowing, paint-like trails that soften motion into dreamy streaks.

**Inputs:** `amount` (float) [0–1]

**🎵 Audio:** `uniformName`→beatPhase

---

### Soft Blur

![Soft Blur](screenshots/Soft%20Blur.jpg)

**Description:** Multi-pass blur effect with adjustable softness and depth parameters. Creates smooth, dreamy blur with controllable intensity.

**Inputs:** `softness` (float) [0–1], `depth` (float) [1–10]

---

### Solar Colors

![Solar Colors](screenshots/Solar%20Colors.jpg)

**Description:** Transforms input images with vibrant solar-inspired color palettes. Creates warm, luminous color shifts based on luminance values.

**Inputs:** `colorShift` (float), `colorAdjust` (float) [0.25–2], `blacks` (float)

---

### Sort Smear

![Sort Smear](screenshots/Sort%20Smear.jpg)

**Description:** Creates glitchy pixel sorting artifacts that smear and reorganize image data. Produces digital corruption aesthetics with controllable chaos.

**Inputs:** `resetInput` (event), `adaptLevel` (float) [0–1], `sortRate` (float) [0–1], `horizontalSort` (bool), `verticalSort` (bool)

---

### Static Lidar

![Static Lidar](screenshots/Static%20Lidar.jpg)

**Description:** Static 3D point cloud effect that transforms images into lidar-style depth visualizations. Converts luminance into striking geometric depth maps.

**Inputs:** `DEPTH` (float) [5–100], `EXTRUSION` (float) [-1–1], `ZOFFSET` (float) [-1–1], `SAMPLERADIUS` (float) [0–20], `CHUNKINESS` (float) [-20–20], `WARPFACTORA` (float) [0.025–2], `WARPFACTORB` (float) [0–2], `GAMMA` (float) [0–10]

**🎵 Audio:** `uniformName`→bass

---

### Still Noise

![Still Noise](screenshots/Still%20Noise.jpg)

**Description:** Static hash-based noise generator for adding film grain textures. Produces consistent, non-temporal noise patterns with controllable intensity.

**Inputs:** `seed` (float) [0–1], `noiseLevel` (float) [0–1]

---

### strobe

![strobe](screenshots/strobe.jpg)

**Description:** Rhythmic strobing effect alternating between solid color and input image. High-impact flash sequences.

**Inputs:** `colorInput` (color), `freq` (float) [0–1]

**🎵 Audio:** `uniformName`→beatPhase

---

### Surface Blur

![Surface Blur](screenshots/Surface%20Blur.jpg)

**Description:** Advanced bilateral filter that smooths surfaces while preserving sharp edges. Creates painterly, skin-smoothing effects perfect for portrait enhancement.

**Inputs:** `amount` (float) [0–1], `sigmaSpace` (float) [1–10], `sigmaColor` (float) [1–100]

**🎵 Audio:** `uniformName`→mid

---

### Tape Blur

![Tape Blur](screenshots/Tape%20Blur.jpg)

**Description:** Vintage VHS-style chromatic aberration blur with retro tape distortion. Creates analog video glitch effects through color channel separation.

**Inputs:** `amount` (float) [0–0.75]

**🎵 Audio:** `uniformName`→bassHits

---

### Toned

![Toned](screenshots/Toned.jpg)

**Description:** Film-inspired color grading that mimics vintage technicolor processing with red and blue-green channel separation. Creates warm, nostalgic toning effects with adjustable intensity.

**Inputs:** `amount` (float) [0–1]

---

### Trace Edges

![Trace Edges](screenshots/Trace%20Edges.jpg)

**Description:** Creates dynamic edge detection that traces through the image like a moving scanner. Features colorizable edges with fade trails and adjustable intensity for stylized line art effects.

**Inputs:** `intensity` (float) [0–100], `size` (float) [0–0.5], `speed` (float) [0–16], `colorize` (float) [0–1], `fade` (float) [0–0.05], `manual` (bool), `manualPosition` (float) [0–1]

---

### Trace Edges No Fade

![Trace Edges No Fade](screenshots/Trace%20Edges%20No%20Fade.jpg)

**Description:** Edge detection filter that traces contours in high contrast. Optional technicolor treatment adds stylized cyan-red chromatic separation.

**Inputs:** `intensity` (float) [0–100], `colorize` (float) [0–1]

---

### Trace Edges Static

![Trace Edges Static](screenshots/Trace%20Edges%20Static.jpg)

**Description:** Static edge detection that highlights boundaries and creates persistent traced outlines. Offers colorization and fade controls for clean, stylized edge enhancement effects.

**Inputs:** `intensity` (float) [0–100], `colorize` (float) [0–1], `fade` (float) [0–0.05]

---

### Transitions

![Transitions](screenshots/Transitions.jpg)

**Description:** Multi-purpose transition shader with zoom, slide, rotation, and brightness effects. Smooth animated transitions between states.

**Inputs:** `amount` (float) [0–1], `type` (long)

**🎵 Audio:** `uniformName`→beatPhase

---

### Triangles.fs

![Triangles.fs](screenshots/Triangles.fs.jpg)

**Description:** Stylizes imagery into geometric triangular patterns with cellular subdivision. Creates bold, angular interpretations of source material.

**Inputs:** `cell_size` (float) [0.001–0.5], `style` (long)

---

### Tunnel Distort

![Tunnel Distort](screenshots/Tunnel%20Distort.jpg)

**Description:** Transforms flat images into cylindrical tunnel-like distortions with polar coordinate mapping. Creates immersive depth illusions through mathematical warping.

**Inputs:** `pos` (float), `mixup` (float), `mod1` (float), `mod2` (float)

---

### Tunnel with relief

![Tunnel with relief](screenshots/Tunnel%20with%20relief.jpg)

**Description:** 2D tunnel effect with fake relief shading and animated depth perception. Combines polar distortion with ambient occlusion for dimensional tunnel illusions.

**Inputs:** `movementDepth` (float) [0–2], `fadeAmount` (float) [0–1], `speedIn` (float) [0.1–5], `speedOut` (float) [0.1–5]

---

### Variable Invert

![Variable Invert](screenshots/Variable%20Invert.jpg)

**Description:** Provides variable color inversion with smooth blending between original and inverted states. Offers precise control over the inversion amount for subtle to dramatic color shifts.

**Inputs:** `invert` (float) [0–1]

---

### Vertical Glitch

![Vertical Glitch](screenshots/Vertical%20Glitch.jpg)

**Description:** Chaotic digital breakdown with horizontal displacement and tracking noise. Perfect for cyberpunk aesthetics and system failures.

**Inputs:** `glitchAmount` (float) [0–1], `trackingAmount` (float) [0–1], `trackingSize` (float) [0–1]

**🎵 Audio:** `uniformName`→bassHits

---

### VHS Blur

![VHS Blur](screenshots/VHS%20Blur.jpg)

**Description:** Simulates vintage VHS chromatic aberration and tracking errors. Adds nostalgic analog video artifacts with customizable glitch intensity.

**Inputs:** `amount` (float) [0–1], `tracking` (float) [0–1], `time` (float) [0–10]

**🎵 Audio:** `uniformName`→amount

---

### VHS Noise

![VHS Noise](screenshots/VHS%20Noise.jpg)

**Description:** VHS-style noise and static overlay with horizontal scan lines. Generates authentic analog video interference patterns.

**Inputs:** `size` (float), `amount` (float)

---

### Vibrance

![Vibrance](screenshots/Vibrance.jpg)

**Description:** Intelligently enhances color vibrancy without oversaturating. Brings images to life with natural, punchy color enhancement.

**Inputs:** `vibrancy` (float) [0–1]

**🎵 Audio:** `uniformName`→high

---

### Video Heightfield

![Video Heightfield](screenshots/Video%20Heightfield.jpg)

**Description:** Converts video into a 3D heightfield landscape using luminance as elevation data. Creates dramatic pseudo-3D terrain effects with configurable height scaling and overdrive intensity.

**Inputs:** `MAXHEIGHT` (float) [0–2], `OVERDRIVE` (float) [1–10]

---

### Video Wave

![Video Wave](screenshots/Video%20Wave.jpg)

**Description:** Analog video distortion with sinusoidal wave displacement. Evokes vintage broadcast interference and tape degradation.

**Inputs:** `distortion` (float) [0–5], `frequency` (float) [0.1–10], `speed` (float) [0–1], `lumadistortion` (bool), `mirror` (bool)

**🎵 Audio:** `uniformName`→mid

---

### Vignette Invertable

![Vignette Invertable](screenshots/Vignette%20Invertable.jpg)

**Description:** Adds classic film-style vignetting with invertible dark or light edges. Brings cinematic focus and mood to any composition.

**Inputs:** `vignette` (float) [0–1], `invert` (bool), `vignetteEdge` (float) [0–1], `vignetteMix` (float) [0–1]

**🎵 Audio:** `uniformName`→level

---

### VignetteInvertable

![VignetteInvertable](screenshots/VignetteInvertable.jpg)

**Description:** Applies classic film-style vignetting with customizable edge softness and invertible darkness. Adds cinematic depth by darkening or brightening image borders.

**Inputs:** `vignette` (float) [0–1], `invert` (bool), `vignetteEdge` (float) [0–1], `vignetteMix` (float) [0–1]

**🎵 Audio:** `uniformName`→level

---

### Wave Distort

![Wave Distort](screenshots/Wave%20Distort.jpg)

**Description:** Creates dynamic wave distortions that ripple across the input image. Multiple waves with varying frequencies and amplitudes produce organic deformation patterns.

**Inputs:** `waveCount` (float) [1–10], `waveSpeed` (float) [0.1–5], `waveAmplitude` (float) [0–1]

---

### zoom blocks

![zoom blocks](screenshots/zoom%20blocks.jpg)

**Description:** Feedback zoom with blocky sampling artifacts and temporal persistence. Creates psychedelic recursive zoom effects with randomized block disruptions.

**Inputs:** `zoom` (float) [0.95–1.05], `feedbackFade` (float) [0.8–1], `sampleSpeed` (float) [0–10], `blockSize` (float) [0.01–0.2]

---

### Zoom Transition

![Zoom Transition](screenshots/Zoom%20Transition.jpg)

**Description:** Specialized zoom transition with blur effects and directional control. Smooth scaling transitions with motion blur.

**Inputs:** `amount` (float) [0–1], `inOut` (bool)

**🎵 Audio:** `uniformName`→level

---

