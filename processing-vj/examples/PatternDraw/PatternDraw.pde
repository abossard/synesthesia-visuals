/**
 * Pattern Draw - Drawing Explosion Game
 * 
 * Draw patterns on the Launchpad grid, then watch them explode!
 * Fill cells to create patterns, press a scene button to trigger explosion.
 * 
 * Requirements:
 * - Processing 4.x (Intel/x64 build for Apple Silicon)
 * - The MidiBus library
 * - Syphon library (for video output)
 * - Launchpad Mini Mk3 in Programmer mode (optional)
 * 
 * Controls:
 * - Tap pads to draw/toggle cells (Launchpad or mouse)
 * - Scene buttons (right column) or SPACE to trigger explosion
 * - Press 'C' to clear canvas
 * - Press 'R' to randomize colors
 * 
 * Syphon Output:
 * - Broadcasts as "PatternDraw" server at 1920x1080
 * - Receivable in Synesthesia, Magic, VPT, etc.
 */

import themidibus.*;
import codeanticode.syphon.*;

MidiBus launchpad;
SyphonServer syphon;
boolean hasLaunchpad = false;

// Grid state
boolean[][] grid = new boolean[8][8];
color[][] gridColors = new color[8][8];

// Explosion particles
ArrayList<Particle> particles = new ArrayList<Particle>();
boolean exploding = false;
int explosionStartTime = 0;
int explosionDuration = 2000;  // ms

// Visual settings
float flashIntensity = 0;
float currentHue = 0;

// Launchpad color palette
final int LP_OFF = 0;
final int LP_RED = 5;
final int LP_ORANGE = 9;
final int LP_YELLOW = 13;
final int LP_GREEN = 21;
final int LP_CYAN = 37;
final int LP_BLUE = 45;
final int LP_PURPLE = 53;
final int LP_PINK = 57;
final int LP_WHITE = 3;

int[] lpPalette = {LP_RED, LP_ORANGE, LP_YELLOW, LP_GREEN, LP_CYAN, LP_BLUE, LP_PURPLE, LP_PINK};

void settings() {
  size(1280, 720, P3D);  // 720p (16:9), P3D required for Syphon
}

void setup() {
  colorMode(HSB, 360, 100, 100);
  
  // Initialize Syphon server
  syphon = new SyphonServer(this, "PatternDraw");
  
  // Try to find and connect to Launchpad
  initMidi();
  
  // Initialize grid with random colors
  randomizeColors();
  clearGrid();
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
  // Flash effect background
  if (flashIntensity > 0) {
    background(0, 0, flashIntensity);
    flashIntensity *= 0.9;
  } else {
    background(0);
  }
  
  // Draw grid
  drawGrid();
  
  // Update and draw particles
  updateParticles();
  
  // Check explosion timer
  if (exploding && millis() - explosionStartTime > explosionDuration) {
    exploding = false;
    clearGrid();
    randomizeColors();
  }
  
  // Draw UI
  drawUI();
  
  // Send frame to Syphon
  syphon.sendScreen();
}

void drawGrid() {
  float cellSize = min(width, height) * 0.8 / 8;
  float offsetX = (width - cellSize * 8) / 2;
  float offsetY = (height - cellSize * 8) / 2;
  
  noStroke();
  
  for (int row = 0; row < 8; row++) {
    for (int col = 0; col < 8; col++) {
      float x = offsetX + col * cellSize;
      float y = offsetY + (7 - row) * cellSize;  // Flip Y to match Launchpad
      
      if (grid[col][row]) {
        // Filled cell - pulsing glow
        float pulse = sin(frameCount * 0.1 + col + row) * 0.2 + 0.8;
        fill(gridColors[col][row], pulse * 255);
        
        // Glow effect
        for (int g = 3; g > 0; g--) {
          fill(gridColors[col][row], 50 / g);
          rect(x - g*3, y - g*3, cellSize - 4 + g*6, cellSize - 4 + g*6, 8);
        }
        
        fill(gridColors[col][row]);
        rect(x, y, cellSize - 4, cellSize - 4, 5);
      } else {
        // Empty cell
        fill(30);
        rect(x, y, cellSize - 4, cellSize - 4, 5);
      }
    }
  }
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

void drawUI() {
  fill(255);
  textAlign(CENTER, TOP);
  textSize(32);
  text("PATTERN DRAW", width/2, 20);
  
  textSize(18);
  fill(hasLaunchpad ? color(120, 80, 100) : color(40, 80, 100));
  text(hasLaunchpad ? "Launchpad Connected" : "Mouse Mode (click grid)", width/2, 60);
  
  fill(200);
  textSize(16);
  text("Draw a pattern, then press SPACE to explode!", width/2, height - 40);
  
  // Count filled cells
  int filledCount = 0;
  for (int c = 0; c < 8; c++) {
    for (int r = 0; r < 8; r++) {
      if (grid[c][r]) filledCount++;
    }
  }
  text("Cells: " + filledCount + "/64", width/2, height - 60);
}

void triggerExplosion() {
  exploding = true;
  explosionStartTime = millis();
  flashIntensity = 100;
  
  float cellSize = min(width, height) * 0.8 / 8;
  float offsetX = (width - cellSize * 8) / 2;
  float offsetY = (height - cellSize * 8) / 2;
  
  // Create particles from filled cells
  for (int col = 0; col < 8; col++) {
    for (int row = 0; row < 8; row++) {
      if (grid[col][row]) {
        float x = offsetX + col * cellSize + cellSize/2;
        float y = offsetY + (7 - row) * cellSize + cellSize/2;
        
        // Create multiple particles per cell
        for (int i = 0; i < 20; i++) {
          particles.add(new Particle(x, y, gridColors[col][row]));
        }
      }
    }
  }
  
  // Clear Launchpad with flash effect
  if (hasLaunchpad) {
    flashLaunchpad();
  }
}

void flashLaunchpad() {
  if (!hasLaunchpad || launchpad == null) return;
  
  // Flash all pads white
  for (int row = 0; row < 8; row++) {
    for (int col = 0; col < 8; col++) {
      lightPad(col, row, LP_WHITE);
    }
  }
}

void toggleCell(int col, int row) {
  if (col < 0 || col >= 8 || row < 0 || row >= 8) return;
  if (exploding) return;
  
  grid[col][row] = !grid[col][row];
  
  // Update Launchpad LED
  if (grid[col][row]) {
    int lpColor = lpPalette[(col + row) % lpPalette.length];
    lightPad(col, row, lpColor);
  } else {
    lightPad(col, row, LP_OFF);
  }
}

void clearGrid() {
  for (int c = 0; c < 8; c++) {
    for (int r = 0; r < 8; r++) {
      grid[c][r] = false;
    }
  }
  clearAllPads();
}

void randomizeColors() {
  currentHue = random(360);
  for (int c = 0; c < 8; c++) {
    for (int r = 0; r < 8; r++) {
      float hue = (currentHue + (c + r) * 15) % 360;
      gridColors[c][r] = color(hue, 80, 100);
    }
  }
}

// MIDI callbacks
void noteOn(int channel, int pitch, int velocity) {
  // Check for scene launch buttons (trigger explosion)
  if (pitch % 10 == 9 && pitch >= 19 && pitch <= 89) {
    triggerExplosion();
    return;
  }
  
  if (!isValidPad(pitch)) return;
  
  PVector pos = noteToGrid(pitch);
  int col = (int)pos.x;
  int row = (int)pos.y;
  
  toggleCell(col, row);
}

void noteOff(int channel, int pitch, int velocity) {
  // Not used
}

// Mouse fallback
void mousePressed() {
  float cellSize = min(width, height) * 0.8 / 8;
  float offsetX = (width - cellSize * 8) / 2;
  float offsetY = (height - cellSize * 8) / 2;
  
  if (mouseX >= offsetX && mouseX < offsetX + cellSize * 8 &&
      mouseY >= offsetY && mouseY < offsetY + cellSize * 8) {
    
    int col = (int)((mouseX - offsetX) / cellSize);
    int row = 7 - (int)((mouseY - offsetY) / cellSize);
    
    toggleCell(col, row);
  }
}

void keyPressed() {
  if (key == ' ') {
    triggerExplosion();
  } else if (key == 'c' || key == 'C') {
    clearGrid();
  } else if (key == 'r' || key == 'R') {
    randomizeColors();
  }
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
  lightPad(col, row, LP_OFF);
}

void clearAllPads() {
  if (!hasLaunchpad || launchpad == null) return;
  for (int row = 0; row < 8; row++) {
    for (int col = 0; col < 8; col++) {
      clearPad(col, row);
    }
  }
}

void exit() {
  clearAllPads();
  super.exit();
}

// Particle class for explosion effect
class Particle {
  float x, y;
  float vx, vy;
  float size;
  color c;
  float life;
  float maxLife;
  float gravity = 0.2;
  float drag = 0.98;
  
  Particle(float x, float y, color c) {
    this.x = x;
    this.y = y;
    this.c = c;
    
    // Random explosion velocity
    float angle = random(TWO_PI);
    float speed = random(5, 25);
    this.vx = cos(angle) * speed;
    this.vy = sin(angle) * speed - random(5, 15);  // Bias upward
    
    this.size = random(5, 20);
    this.maxLife = random(60, 120);
    this.life = maxLife;
  }
  
  void update() {
    x += vx;
    y += vy;
    vy += gravity;
    vx *= drag;
    vy *= drag;
    life--;
    size *= 0.98;
  }
  
  void display() {
    float alpha = map(life, 0, maxLife, 0, 100);
    
    // Glow
    noStroke();
    fill(hue(c), saturation(c), brightness(c), alpha * 0.3f);
    ellipse(x, y, size * 2, size * 2);
    
    // Core
    fill(hue(c), saturation(c), brightness(c), alpha);
    ellipse(x, y, size, size);
  }
  
  boolean isDead() {
    return life <= 0 || size < 1 || y > height + 50;
  }
}
