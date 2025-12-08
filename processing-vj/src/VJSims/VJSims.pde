/**
 * VJSims — Processing VJ Simulation Framework
 * 
 * Non-interactive visual framework with Synesthesia Audio OSC support.
 * Outputs via Syphon for compositing in Magic/Synesthesia.
 * 
 * Requirements:
 * - Processing 4.x (Intel/x64 build on Apple Silicon for Syphon)
 * - Syphon library
 * - oscP5 library (for Synesthesia Audio OSC - TODO)
 * 
 * Audio Reactivity:
 * - Synesthesia Audio OSC: Receive real-time audio analysis from Synesthesia
 *   (bass, mid, high levels, BPM, spectrum, etc.)
 * - Auto-running visual simulation driven by audio
 */

import codeanticode.syphon.*;

// ============================================
// CORE COMPONENTS
// ============================================

// Syphon output
SyphonServer syphon;

// Framebuffer
PGraphics canvas;

// Audio simulation (for testing without Synesthesia)
AudioEnvelope bassEnv, midEnv, highEnv;

// Timing
int lastFrameTime;
float time = 0;

// ============================================
// SETTINGS
// ============================================

void settings() {
  size(1280, 720, P3D);  // HD Ready, P3D required for Syphon + 3D effects
}

// ============================================
// SETUP
// ============================================

void setup() {
  frameRate(60);
  
  // Initialize framebuffer
  canvas = createGraphics(width, height, P3D);
  
  // Initialize Syphon
  syphon = new SyphonServer(this, "VJSims");
  
  // Initialize audio envelopes for simulation
  bassEnv = new AudioEnvelope(0.1, 0.3);  // Fast attack, medium decay
  midEnv = new AudioEnvelope(0.15, 0.4);
  highEnv = new AudioEnvelope(0.05, 0.2); // Very fast
  
  println("VJSims initialized (non-interactive mode)");
  println("  Syphon server: VJSims");
  println("  Resolution: " + width + "x" + height);
  println("  Audio: Synesthesia OSC (TODO: implement OSC listener)");
  println("  Mode: Auto-running visual simulation");
  
  lastFrameTime = millis();
}

// ============================================
// MAIN LOOP
// ============================================

void draw() {
  // Calculate delta time
  int currentTime = millis();
  float dt = (currentTime - lastFrameTime) / 1000.0;
  lastFrameTime = currentTime;
  time += dt;
  
  // Update audio envelopes
  bassEnv.update(dt);
  midEnv.update(dt);
  highEnv.update(dt);
  
  // Auto-trigger audio simulation (simulates beats at ~120 BPM)
  if (frameCount % 30 == 0) {  // Every 0.5 seconds at 60fps
    bassEnv.trigger();
  }
  if (frameCount % 15 == 0) {  // Every 0.25 seconds
    midEnv.trigger();
  }
  if (frameCount % 7 == 0) {   // Faster
    highEnv.trigger();
  }
  
  // Render to framebuffer
  canvas.beginDraw();
  renderSimulation(canvas, dt);
  canvas.endDraw();
  
  // Display on screen
  image(canvas, 0, 0);
  
  // Send to Syphon
  syphon.sendImage(canvas);
}

// ============================================
// RENDERING
// ============================================

void renderSimulation(PGraphics pg, float dt) {
  // Simple audio-reactive visual
  pg.background(0);
  
  // Audio-reactive colors
  float bassLevel = bassEnv.getLevel();
  float midLevel = midEnv.getLevel();
  float highLevel = highEnv.getLevel();
  
  // Draw audio-reactive gradient
  pg.noStroke();
  for (int y = 0; y < pg.height; y++) {
    float t = map(y, 0, pg.height, 0, 1);
    pg.fill(
      bassLevel * 255 * (1 - t),
      midLevel * 255 * t,
      highLevel * 255
    );
    pg.rect(0, y, pg.width, 1);
  }
  
  // Draw pulsing circles
  pg.pushMatrix();
  pg.translate(pg.width/2, pg.height/2);
  
  // Bass circle
  float bassSize = 100 + bassLevel * 200;
  pg.noFill();
  pg.strokeWeight(3);
  pg.stroke(255, 100, 100, 200);
  pg.ellipse(0, 0, bassSize, bassSize);
  
  // Mid circle
  float midSize = 150 + midLevel * 150;
  pg.stroke(100, 255, 100, 200);
  pg.ellipse(0, 0, midSize, midSize);
  
  // High circle
  float highSize = 200 + highLevel * 100;
  pg.stroke(100, 100, 255, 200);
  pg.ellipse(0, 0, highSize, highSize);
  
  pg.popMatrix();
  
  // Rotating elements driven by time
  pg.pushMatrix();
  pg.translate(pg.width/2, pg.height/2);
  pg.rotate(time * 0.5);
  pg.stroke(255, 150);
  pg.strokeWeight(2);
  pg.noFill();
  pg.rect(-100, -100, 200, 200);
  pg.popMatrix();
}

// ============================================
// SHUTDOWN
// ============================================

void exit() {
  println("VJSims shutting down...");
  super.exit();
}
