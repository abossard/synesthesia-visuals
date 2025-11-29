/**
 * Whack-a-Mole Game
 * 
 * A simple reaction game for Launchpad Mini Mk3.
 * Pads light up and players must hit them quickly to score points.
 * 
 * Requirements:
 * - Processing 4.x (Intel/x64 build for Apple Silicon)
 * - The MidiBus library
 * - Syphon library (for video output)
 * - Launchpad Mini Mk3 in Programmer mode (optional)
 * 
 * Controls:
 * - Hit lit pads to score (Launchpad)
 * - Click grid cells with mouse (fallback)
 * - Press 'R' to reset game
 * - Game speeds up as score increases
 * 
 * VJ Output:
 * - 1920x1080 Full HD via Syphon
 * - Black background for overlay compositing
 * - No visible UI - pure particle visuals
 */

import themidibus.*;
import codeanticode.syphon.*;
import java.util.ArrayList;

MidiBus launchpad;
SyphonServer syphon;
boolean hasLaunchpad = false;

int targetCol = -1, targetRow = -1;
int score = 0;
int lastSpawnTime = 0;
int spawnInterval = 1000; // ms

// Particle system for visual feedback
ArrayList<Particle> particles = new ArrayList<Particle>();
ArrayList<Ripple> ripples = new ArrayList<Ripple>();

// Color constants
final int COLOR_OFF = 0;
final int COLOR_TARGET = 21; // Green
final int COLOR_HIT = 5;     // Red
final int COLOR_MISS = 9;    // Orange

void settings() {
  size(1920, 1080, P3D);  // Full HD, P3D required for Syphon
}

void setup() {
  colorMode(HSB, 360, 100, 100);
  
  // Initialize Syphon server
  syphon = new SyphonServer(this, "WhackAMole");
  
  // Try to find and connect to Launchpad
  initMidi();
  
  clearAllPads();
  spawnTarget();
}

void initMidi() {
  MidiBus.list();
  
  String[] inputs = MidiBus.availableInputs();
  String[] outputs = MidiBus.availableOutputs();
  
  String launchpadIn = null;
  String launchpadOut = null;
  
  // Scan for Launchpad device
  for (String dev : inputs) {
    if (dev != null && dev.toLowerCase().contains("launchpad")) {
      launchpadIn = dev;
      break;
    }
  }
  for (String dev : outputs) {
    if (dev != null && dev.toLowerCase().contains("launchpad")) {
      launchpadOut = dev;
      break;
    }
  }
  
  // Connect if found
  if (launchpadIn != null && launchpadOut != null) {
    try {
      launchpad = new MidiBus(this, launchpadIn, launchpadOut);
      hasLaunchpad = true;
      println("Launchpad connected: " + launchpadIn);
    } catch (Exception e) {
      println("Failed to connect to Launchpad: " + e.getMessage());
      hasLaunchpad = false;
    }
  } else {
    println("No Launchpad found - using mouse/keyboard controls");
    hasLaunchpad = false;
  }
}

void draw() {
  // Semi-transparent background for trail effect
  fill(0, 30);
  noStroke();
  rect(0, 0, width, height);
  
  // Update and draw particles
  updateParticles();
  
  // Update and draw ripples
  updateRipples();
  
  // Draw target glow
  drawTargetGlow();
  
  // Spawn new target periodically
  if (millis() - lastSpawnTime > spawnInterval) {
    clearTarget();
    spawnTarget();
  }
  
  // Send frame to Syphon
  syphon.sendScreen();
}

void drawTargetGlow() {
  if (targetCol < 0 || targetRow < 0) return;
  
  float cellSize = min(width, height) * 0.8f / 8;
  float offsetX = (width - cellSize * 8) / 2;
  float offsetY = (height - cellSize * 8) / 2;
  
  float x = offsetX + targetCol * cellSize + cellSize/2;
  float y = offsetY + (7 - targetRow) * cellSize + cellSize/2;
  
  // Pulsing glow effect
  float pulse = sin(frameCount * 0.15f) * 0.3f + 0.7f;
  
  // Outer glow layers
  noStroke();
  for (int i = 5; i > 0; i--) {
    float glowSize = cellSize * (0.8f + i * 0.3f) * pulse;
    fill(120, 80, 100, 15);
    ellipse(x, y, glowSize, glowSize);
  }
  
  // Core glow
  fill(120, 70, 100, 80 * pulse);
  ellipse(x, y, cellSize * 0.6f, cellSize * 0.6f);
  
  // Bright center
  fill(120, 50, 100);
  ellipse(x, y, cellSize * 0.3f, cellSize * 0.3f);
}

void updateParticles() {
  for (int i = particles.size() - 1; i >= 0; i--) {
    Particle p = particles.get(i);
    p.update();
    p.display();
    if (p.isDead()) {
      particles.remove(i);
    }
  }
}

void updateRipples() {
  for (int i = ripples.size() - 1; i >= 0; i--) {
    Ripple r = ripples.get(i);
    r.update();
    r.display();
    if (r.isDead()) {
      ripples.remove(i);
    }
  }
}

void spawnHitEffect(float x, float y, boolean isHit) {
  // Create particle explosion
  int numParticles = isHit ? 100 : 30;
  float hue = isHit ? 120 : 30;  // Green for hit, orange for miss
  
  for (int i = 0; i < numParticles; i++) {
    particles.add(new Particle(x, y, hue, isHit ? 15 : 8));
  }
  
  // Create ripple
  ripples.add(new Ripple(x, y, isHit ? 300 : 150, hue));
}

void spawnTarget() {
  targetCol = (int)random(8);
  targetRow = (int)random(8);
  lightPad(targetCol, targetRow, COLOR_TARGET);
  lastSpawnTime = millis();
}

void clearTarget() {
  if (targetCol >= 0 && targetRow >= 0) {
    clearPad(targetCol, targetRow);
  }
}

// MIDI callbacks
void noteOn(int channel, int pitch, int velocity) {
  if (!isValidPad(pitch)) return;
  
  PVector pos = noteToGrid(pitch);
  int col = (int)pos.x;
  int row = (int)pos.y;
  
  handlePadHit(col, row);
}

void noteOff(int channel, int pitch, int velocity) {
  // Not used in this game
}

// Utility functions
PVector noteToGrid(int note) {
  int col = (note % 10) - 1;
  int row = (note / 10) - 1;
  return new PVector(col, row);
}

int gridToNote(int col, int row) {
  return (row + 1) * 10 + (col + 1);
}

boolean isValidPad(int note) {
  int col = note % 10;
  int row = note / 10;
  return col >= 1 && col <= 8 && row >= 1 && row <= 8;
}

void lightPad(int col, int row, int colorIndex) {
  if (!hasLaunchpad || launchpad == null) return;
  int note = gridToNote(col, row);
  launchpad.sendNoteOn(0, note, colorIndex);
}

void clearPad(int col, int row) {
  lightPad(col, row, COLOR_OFF);
}

void clearAllPads() {
  if (!hasLaunchpad || launchpad == null) return;
  for (int row = 0; row < 8; row++) {
    for (int col = 0; col < 8; col++) {
      clearPad(col, row);
    }
  }
}

// Mouse fallback for when no Launchpad is available
void mousePressed() {
  float cellSize = min(width, height) * 0.8f / 8;
  float offsetX = (width - cellSize * 8) / 2;
  float offsetY = (height - cellSize * 8) / 2;
  
  // Check if click is within grid
  if (mouseX >= offsetX && mouseX < offsetX + cellSize * 8 &&
      mouseY >= offsetY && mouseY < offsetY + cellSize * 8) {
    
    int col = (int)((mouseX - offsetX) / cellSize);
    int row = 7 - (int)((mouseY - offsetY) / cellSize);  // Flip Y
    
    handlePadHit(col, row);
  }
}

// Shared hit logic for both MIDI and mouse
void handlePadHit(int col, int row) {
  float cellSize = min(width, height) * 0.8f / 8;
  float offsetX = (width - cellSize * 8) / 2;
  float offsetY = (height - cellSize * 8) / 2;
  
  float x = offsetX + col * cellSize + cellSize/2;
  float y = offsetY + (7 - row) * cellSize + cellSize/2;
  
  if (col == targetCol && row == targetRow) {
    // Hit!
    score++;
    lightPad(col, row, COLOR_HIT);
    spawnHitEffect(x, y, true);
    // Note: LED flash is brief - particle effects provide main feedback
    clearPad(col, row);
    spawnTarget();
    
    // Speed up as score increases
    spawnInterval = max(300, 1000 - score * 50);
  } else {
    // Miss - flash orange (brief LED flash, particle effect is main feedback)
    lightPad(col, row, COLOR_MISS);
    spawnHitEffect(x, y, false);
    clearPad(col, row);
  }
}

// Keyboard fallback
void keyPressed() {
  if (key == 'r' || key == 'R') {
    score = 0;
    spawnInterval = 1000;
    clearAllPads();
    spawnTarget();
  }
}

// Cleanup on exit
void exit() {
  clearAllPads();
  super.exit();
}

// Particle class for explosion effects
class Particle {
  float x, y;
  float vx, vy;
  float size;
  float hue;
  float life;
  float maxLife;
  float gravity = 0.15f;
  float drag = 0.98f;
  
  Particle(float x, float y, float hue, float maxSpeed) {
    this.x = x;
    this.y = y;
    this.hue = hue + random(-20, 20);
    
    // Random explosion velocity
    float angle = random(TWO_PI);
    float speed = random(2, maxSpeed);
    this.vx = cos(angle) * speed;
    this.vy = sin(angle) * speed - random(2, 8);  // Bias upward
    
    this.size = random(3, 12);
    this.maxLife = random(40, 80);
    this.life = maxLife;
  }
  
  void update() {
    x += vx;
    y += vy;
    vy += gravity;
    vx *= drag;
    vy *= drag;
    life--;
    size *= 0.97f;
  }
  
  void display() {
    float alpha = map(life, 0, maxLife, 0, 100);
    
    // Glow
    noStroke();
    fill(hue, 70, 100, alpha * 0.4f);
    ellipse(x, y, size * 2.5f, size * 2.5f);
    
    // Core
    fill(hue, 60, 100, alpha);
    ellipse(x, y, size, size);
    
    // Bright center
    fill(hue, 30, 100, alpha);
    ellipse(x, y, size * 0.4f, size * 0.4f);
  }
  
  boolean isDead() {
    return life <= 0 || size < 0.5f;
  }
}

// Ripple class for expanding ring effects
class Ripple {
  float x, y;
  float radius;
  float maxRadius;
  float hue;
  float life;
  float maxLife;
  
  Ripple(float x, float y, float maxRadius, float hue) {
    this.x = x;
    this.y = y;
    this.radius = 0;
    this.maxRadius = maxRadius;
    this.hue = hue;
    this.maxLife = 40;
    this.life = maxLife;
  }
  
  void update() {
    radius += (maxRadius - radius) * 0.15f;
    life--;
  }
  
  void display() {
    float alpha = map(life, 0, maxLife, 0, 80);
    
    noFill();
    strokeWeight(3);
    stroke(hue, 70, 100, alpha);
    ellipse(x, y, radius * 2, radius * 2);
    
    strokeWeight(1);
    stroke(hue, 50, 100, alpha * 0.5f);
    ellipse(x, y, radius * 2.5f, radius * 2.5f);
  }
  
  boolean isDead() {
    return life <= 0;
  }
}
