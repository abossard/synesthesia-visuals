# Fluid Simulations - Reaction-Diffusion & Flow Fields

## Overview

Fluid simulations create organic, living visuals perfect for VJ performances. This guide covers Reaction-Diffusion (Gray-Scott), flow fields, and PixelFlow GPU-accelerated fluid dynamics.

## Table of Contents

1. [Perlin Flow Fields](#perlin-flow-fields)
2. [Reaction-Diffusion (Gray-Scott)](#reaction-diffusion-gray-scott)
3. [PixelFlow Fluid Dynamics](#pixelflow-fluid-dynamics)
4. [Smoke and Fire Effects](#smoke-and-fire-effects)

---

## Perlin Flow Fields

```java
class FlowField {
  PVector[][] field;
  int cols, rows;
  float resolution = 20;
  float noiseScale = 0.05f;
  float zOffset = 0;
  
  FlowField(int w, int h) {
    cols = w / (int)resolution + 1;
    rows = h / (int)resolution + 1;
    field = new PVector[cols][rows];
    generate();
  }
  
  void generate() {
    float angleScale = TWO_PI * 2;  // Scale factor for angle variation
    for (int x = 0; x < cols; x++) {
      for (int y = 0; y < rows; y++) {
        float angle = noise(x * noiseScale, y * noiseScale, zOffset) * angleScale;
        field[x][y] = PVector.fromAngle(angle);
      }
    }
  }
  
  void update(float dt) {
    zOffset += dt * 0.1f;
    generate();
  }
  
  PVector lookup(PVector pos) {
    int x = constrain((int)(pos.x / resolution), 0, cols - 1);
    int y = constrain((int)(pos.y / resolution), 0, rows - 1);
    return field[x][y].copy();
  }
}
```

---

## Reaction-Diffusion (Gray-Scott)

The Gray-Scott model creates organic patterns through chemical reaction simulation.

### Formula

```
dA/dt = D_A × ∇²A - AB² + f(1-A)
dB/dt = D_B × ∇²B + AB² - (k+f)B
```

Where:
- A, B = chemical concentrations
- D_A, D_B = diffusion rates
- f = feed rate
- k = kill rate

### Shader Implementation (GLSL)

```glsl
// reaction_diffusion.glsl
uniform sampler2D state;
uniform vec2 resolution;
uniform float dA;  // Diffusion rate A
uniform float dB;  // Diffusion rate B
uniform float feed;
uniform float kill;
uniform float dt;

void main() {
  vec2 uv = gl_FragCoord.xy / resolution;
  vec2 pixel = 1.0 / resolution;
  
  // Sample current state
  vec2 AB = texture2D(state, uv).xy;
  float A = AB.x;
  float B = AB.y;
  
  // Laplacian (discrete convolution)
  vec2 L = vec2(0.0);
  L += texture2D(state, uv + vec2(-pixel.x, 0.0)).xy * 0.2;
  L += texture2D(state, uv + vec2( pixel.x, 0.0)).xy * 0.2;
  L += texture2D(state, uv + vec2(0.0, -pixel.y)).xy * 0.2;
  L += texture2D(state, uv + vec2(0.0,  pixel.y)).xy * 0.2;
  L += texture2D(state, uv + vec2(-pixel.x, -pixel.y)).xy * 0.05;
  L += texture2D(state, uv + vec2( pixel.x, -pixel.y)).xy * 0.05;
  L += texture2D(state, uv + vec2(-pixel.x,  pixel.y)).xy * 0.05;
  L += texture2D(state, uv + vec2( pixel.x,  pixel.y)).xy * 0.05;
  L -= AB;
  
  // Gray-Scott reaction
  float reaction = A * B * B;
  float dA_dt = dA * L.x - reaction + feed * (1.0 - A);
  float dB_dt = dB * L.y + reaction - (kill + feed) * B;
  
  A += dA_dt * dt;
  B += dB_dt * dt;
  
  // Clamp to [0,1]
  A = clamp(A, 0.0, 1.0);
  B = clamp(B, 0.0, 1.0);
  
  gl_FragColor = vec4(A, B, 0.0, 1.0);
}
```

### Processing Implementation

```java
class ReactionDiffusion {
  PGraphics current, next;
  PShader rdShader;
  float dA = 1.0f;
  float dB = 0.5f;
  float feed = 0.055f;
  float kill = 0.062f;
  
  ReactionDiffusion(int w, int h) {
    current = createGraphics(w, h, P2D);
    next = createGraphics(w, h, P2D);
    rdShader = loadShader("reaction_diffusion.glsl");
    
    // Initialize with random seed
    current.beginDraw();
    current.background(255);
    for (int i = 0; i < 1000; i++) {
      float x = random(w);
      float y = random(h);
      current.fill(0);
      current.noStroke();
      current.ellipse(x, y, 5, 5);
    }
    current.endDraw();
  }
  
  void update(float dt) {
    rdShader.set("state", current);
    rdShader.set("resolution", (float)current.width, (float)current.height);
    rdShader.set("dA", dA);
    rdShader.set("dB", dB);
    rdShader.set("feed", feed);
    rdShader.set("kill", kill);
    rdShader.set("dt", dt);
    
    next.beginDraw();
    next.shader(rdShader);
    next.rect(0, 0, next.width, next.height);
    next.endDraw();
    
    // Swap buffers
    PGraphics temp = current;
    current = next;
    next = temp;
  }
  
  PImage getImage() {
    return current;
  }
}

// Usage
ReactionDiffusion rd;

void setup() {
  size(1920, 1080, P2D);
  rd = new ReactionDiffusion(width, height);
}

void draw() {
  rd.update(1.0f / 60.0f);
  image(rd.getImage(), 0, 0);
}

// Interactive: Click to seed
void mousePressed() {
  rd.current.beginDraw();
  rd.current.fill(0);
  rd.current.noStroke();
  rd.current.ellipse(mouseX, mouseY, 50, 50);
  rd.current.endDraw();
}
```

### Preset Parameters

| Pattern | Feed | Kill | Description |
|---------|------|------|-------------|
| Coral | 0.062 | 0.061 | Branching coral structures |
| Spots | 0.035 | 0.065 | Scattered dots |
| Worms | 0.078 | 0.061 | Worm-like tendrils |
| Waves | 0.014 | 0.054 | Moving wave patterns |
| Maze | 0.029 | 0.057 | Labyrinth structures |

---

## PixelFlow Fluid Dynamics

### Basic Fluid Setup

```java
import com.thomasdiewald.pixelflow.java.DwPixelFlow;
import com.thomasdiewald.pixelflow.java.fluid.DwFluid2D;

DwPixelFlow context;
DwFluid2D fluid;

void setup() {
  size(1920, 1080, P2D);
  
  context = new DwPixelFlow(this);
  fluid = new DwFluid2D(context, width, height, 1);
  
  // Fluid parameters
  fluid.param.dissipation_density     = 0.99f;  // How fast color fades
  fluid.param.dissipation_velocity    = 0.95f;  // How fast motion decays
  fluid.param.dissipation_temperature = 0.80f;
  fluid.param.vorticity               = 0.20f;  // Swirl strength
  fluid.param.timestep                = 0.25f;
  fluid.param.gridscale               = 1.0f;
}

void draw() {
  fluid.update();
  
  // Render fluid
  background(0);
  fluid.renderFluidTextures(g, 0);  // 0 = density, 1 = velocity, 2 = temperature
}

void addFluid(float x, float y, float vx, float vy) {
  float radius = 50;
  float r = random(1);
  float g = random(1);
  float b = random(1);
  
  fluid.addDensity (x, y, radius, r, g, b, 1.0f);
  fluid.addVelocity(x, y, radius, vx, vy);
}

void mouseDragged() {
  float vx = (mouseX - pmouseX) * 5;
  float vy = (mouseY - pmouseY) * 5;
  addFluid(mouseX, mouseY, vx, vy);
}
```

### Audio-Reactive Fluid

```java
AudioAnalyzer audio;

void draw() {
  audio.update();
  fluid.update();
  
  // Bass → central vortex
  if (audio.getBass() > 0.5f) {
    float x = width/2;
    float y = height/2;
    float strength = audio.getBass() * 100;
    
    // Circular motion
    float angle = frameCount * 0.1f;
    float vx = cos(angle) * strength;
    float vy = sin(angle) * strength;
    
    float hue = (frameCount % 360);
    float r = sin(radians(hue)) * 0.5f + 0.5f;
    float g = sin(radians(hue + 120)) * 0.5f + 0.5f;
    float b = sin(radians(hue + 240)) * 0.5f + 0.5f;
    
    fluid.addDensity(x, y, 200, r, g, b, 1.0f);
    fluid.addVelocity(x, y, 100, vx, vy);
  }
  
  // High frequencies → sparkle
  if (audio.getHigh() > 0.6f) {
    float x = random(width);
    float y = random(height);
    fluid.addDensity(x, y, 20, 1, 1, 1, 1);
  }
  
  fluid.renderFluidTextures(g, 0);
}
```

---

## Smoke and Fire Effects

### Smoke Simulation

```java
class SmokeParticle {
  PVector pos, vel;
  float life, maxLife;
  float size, expansion;
  float opacity;
  
  SmokeParticle(float x, float y) {
    pos = new PVector(x, y);
    vel = new PVector(random(-1, 1), random(-3, -1));  // Rise upward
    life = 1.0f;
    maxLife = random(2, 4);
    size = random(10, 30);
    expansion = random(1.01f, 1.05f);
    opacity = 255;
  }
  
  void update(float dt) {
    vel.y -= dt * 5;  // Buoyancy
    vel.x += (noise(pos.y * 0.01f, frameCount * 0.01f) - 0.5f) * 2;  // Turbulence
    
    pos.add(PVector.mult(vel, dt * 60));
    size *= expansion;
    life -= dt / maxLife;
    opacity = life * 150;
  }
  
  void display(PGraphics g) {
    g.fill(200, 200, 200, opacity);
    g.noStroke();
    g.ellipse(pos.x, pos.y, size, size);
  }
  
  boolean isDead() {
    return life <= 0;
  }
}
```

### Fire Effect

```java
class FireParticle {
  PVector pos, vel;
  float life;
  float hue;
  
  FireParticle(float x, float y) {
    pos = new PVector(x, y);
    vel = new PVector(random(-1, 1), random(-5, -2));
    life = 1.0f;
    hue = random(0, 60);  // Red to yellow
  }
  
  void update(float dt) {
    vel.x *= 0.95f;  // Drag
    pos.add(PVector.mult(vel, dt * 60));
    life -= dt * 2;
    
    // Color shift: red → orange → yellow → fade
    hue = map(life, 1, 0, 0, 60);
  }
  
  void display(PGraphics g) {
    float brightness = life * 100;
    float saturation = 80;
    float alpha = life * 200;
    
    g.fill(hue, saturation, brightness, alpha);
    g.noStroke();
    
    // Glow effect
    for (int i = 3; i > 0; i--) {
      float size = 10 * i;
      float a = alpha / (i * i);
      g.fill(hue, saturation/i, brightness, a);
      g.ellipse(pos.x, pos.y, size, size);
    }
  }
  
  boolean isDead() {
    return life <= 0;
  }
}

// Usage: Continuous fire emitter
void emitFire(float x, float y, int count) {
  for (int i = 0; i < count; i++) {
    fireParticles.add(new FireParticle(x, y));
  }
}

void draw() {
  background(0, 20);  // Dark with trails
  
  // Emit fire at bottom
  emitFire(width/2, height - 50, 10);
  
  for (int i = fireParticles.size() - 1; i >= 0; i--) {
    FireParticle p = fireParticles.get(i);
    p.update(1.0f / frameRate);
    p.display(g);
    
    if (p.isDead()) {
      fireParticles.remove(i);
    }
  }
}
```

---

## Summary

### Performance Comparison

| Technique | CPU Usage | GPU Usage | Particle Count |
|-----------|-----------|-----------|----------------|
| Flow Field | Low | None | N/A |
| Reaction-Diffusion (shader) | Low | High | N/A |
| PixelFlow Fluid | Low | Very High | 100,000+ |
| CPU Smoke/Fire | Medium | None | 1,000-5,000 |

### Best Practices

- **Flow fields**: Perfect for guiding particles with minimal CPU cost
- **Reaction-Diffusion**: Use shaders for real-time HD performance
- **PixelFlow**: Requires P2D renderer, not compatible with P3D
- **Ping-pong buffers**: Always swap two PGraphics for simulation
- **Shader parameters**: Expose feed/kill rates for live performance control
- **Audio reactivity**: Map bass to vorticity, mid to color, high to spawns

---

**Next**: [05-3d-rendering.md](05-3d-rendering.md) - P3D optimization and camera systems

**Previous**: [03-particle-systems.md](03-particle-systems.md) - Particle physics
