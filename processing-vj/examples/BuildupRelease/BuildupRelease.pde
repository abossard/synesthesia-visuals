/**
 * Buildup Release - VJ Overlay Effect
 * 
 * A visual effect designed for song buildups and drops.
 * Press pads on the Launchpad to gradually cover the screen.
 * Press multiple pads simultaneously to trigger a crack/shatter release effect
 * that reveals the full screen.
 * 
 * Requirements:
 * - Processing 4.x (Intel/x64 build for Apple Silicon)
 * - The MidiBus library
 * - Syphon library (for video output)
 * - Launchpad Mini Mk3 in Programmer mode (optional)
 * 
 * Controls:
 * - Press pads to add coverage panels (Launchpad or mouse)
 * - Press multiple pads at once (within 200ms) to trigger crack release
 * - Press 'C' to clear all panels
 * - Press 'R' to trigger release effect manually
 * - Press 'SPACE' to reset
 * 
 * Syphon Output:
 * - Broadcasts as "BuildupRelease" server at 1920x1080
 * - Use as overlay in VJ software (Synesthesia, Magic, VPT, etc.)
 */

import themidibus.*;
import codeanticode.syphon.*;

MidiBus launchpad;
SyphonServer syphon;
boolean hasLaunchpad = false;

// Grid state - tracks which pads are active
boolean[][] padActive = new boolean[8][8];
int activePadCount = 0;

// Coverage panels - rectangles that cover the screen
ArrayList<CoverPanel> panels = new ArrayList<CoverPanel>();

// Crack/shatter particles for release effect
ArrayList<ShardParticle> shards = new ArrayList<ShardParticle>();
boolean releasing = false;
int releaseStartTime = 0;
int releaseDuration = 1500;  // ms

// Multi-press detection for triggering release
int lastPressTime = 0;
int multiPressWindow = 200;  // ms - window to detect simultaneous presses
int recentPressCount = 0;
int multiPressThreshold = 3;  // Number of pads needed for release

// Visual settings
float coverageAmount = 0;  // 0-1 how much screen is covered
float targetCoverage = 0;
float coverageSmoothing = 0.08f;
float flashIntensity = 0;
color panelBaseColor;
float panelHue = 0;

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

void settings() {
  size(1920, 1080, P3D);  // Full HD for VJ output, P3D required for Syphon
}

void setup() {
  colorMode(HSB, 360, 100, 100);
  frameRate(60);
  
  // Initialize Syphon server
  syphon = new SyphonServer(this, "BuildupRelease");
  
  // Try to find and connect to Launchpad
  initMidi();
  
  // Initialize with random hue
  panelHue = random(360);
  panelBaseColor = color(panelHue, 80, 20);
  
  clearAllPads();
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
  // Transparent background for overlay use
  // Use solid black for standalone testing
  background(0);
  
  // Smooth coverage transition
  coverageAmount = lerp(coverageAmount, targetCoverage, coverageSmoothing);
  
  // Update target coverage based on active pads
  targetCoverage = activePadCount / 64.0f;
  
  // Update and draw panels
  updatePanels();
  drawPanels();
  
  // Update and draw shards during release
  if (releasing) {
    updateShards();
    drawShards();
    
    // Check if release is complete
    if (millis() - releaseStartTime > releaseDuration) {
      releasing = false;
      shards.clear();
    }
  }
  
  // Flash effect
  if (flashIntensity > 0) {
    fill(0, 0, 100, flashIntensity * 0.8f);
    noStroke();
    rect(0, 0, width, height);
    flashIntensity *= 0.9f;
  }
  
  // Draw UI overlay (optional - can be hidden for pure overlay use)
  drawUI();
  
  // Send frame to Syphon
  syphon.sendScreen();
  
  // Reset multi-press counter if window expired
  if (millis() - lastPressTime > multiPressWindow) {
    recentPressCount = 0;
  }
}

void updatePanels() {
  // Update existing panels
  for (int i = panels.size() - 1; i >= 0; i--) {
    CoverPanel p = panels.get(i);
    p.update();
    
    // Remove panels during release
    if (releasing && p.shouldRemove()) {
      panels.remove(i);
    }
  }
}

void drawPanels() {
  for (CoverPanel p : panels) {
    p.display();
  }
}

void updateShards() {
  for (int i = shards.size() - 1; i >= 0; i--) {
    ShardParticle s = shards.get(i);
    s.update();
    if (s.isDead()) {
      shards.remove(i);
    }
  }
}

void drawShards() {
  for (ShardParticle s : shards) {
    s.display();
  }
}

void drawUI() {
  // Status bar at bottom
  fill(0, 0, 100);
  textAlign(CENTER, TOP);
  textSize(24);
  text("BUILDUP RELEASE", width/2, 20);
  
  textSize(16);
  fill(hasLaunchpad ? color(120, 80, 100) : color(40, 80, 100));
  text(hasLaunchpad ? "Launchpad Connected" : "Mouse Mode (click grid below)", width/2, 50);
  
  fill(0, 0, 80);
  textSize(14);
  text("Coverage: " + nf(coverageAmount * 100, 0, 1) + "% | Pads: " + activePadCount + "/64 | Press " + multiPressThreshold + "+ pads quickly to release", width/2, height - 30);
  
  // Draw mini grid for mouse fallback
  if (!hasLaunchpad) {
    drawMiniGrid();
  }
}

void drawMiniGrid() {
  float gridSize = 200;
  float cellSize = gridSize / 8;
  float offsetX = width - gridSize - 40;
  float offsetY = height - gridSize - 60;
  
  for (int row = 0; row < 8; row++) {
    for (int col = 0; col < 8; col++) {
      float x = offsetX + col * cellSize;
      float y = offsetY + (7 - row) * cellSize;
      
      if (padActive[col][row]) {
        fill(panelHue, 70, 80);
      } else {
        fill(0, 0, 20);
      }
      stroke(0, 0, 40);
      rect(x, y, cellSize - 2, cellSize - 2, 2);
    }
  }
  
  fill(0, 0, 60);
  textAlign(CENTER, TOP);
  textSize(12);
  text("Click to toggle | R=Release", offsetX + gridSize/2, offsetY + gridSize + 5);
}

void addPanel(int col, int row) {
  if (padActive[col][row]) return;  // Already active
  
  padActive[col][row] = true;
  activePadCount++;
  
  // Create a coverage panel at this grid position
  float panelWidth = width / 8.0f;
  float panelHeight = height / 8.0f;
  float x = col * panelWidth;
  float y = (7 - row) * panelHeight;
  
  // Add some randomness to size and position for organic feel
  float randOffsetX = random(-panelWidth * 0.3f, panelWidth * 0.3f);
  float randOffsetY = random(-panelHeight * 0.3f, panelHeight * 0.3f);
  float randWidth = panelWidth * random(0.8f, 1.4f);
  float randHeight = panelHeight * random(0.8f, 1.4f);
  
  panels.add(new CoverPanel(x + randOffsetX, y + randOffsetY, randWidth, randHeight, col, row));
  
  // Update Launchpad LED
  int colorIndex = (int)map(activePadCount, 0, 64, LP_BLUE, LP_RED);
  lightPad(col, row, colorIndex);
  
  // Check for multi-press release trigger
  int now = millis();
  if (now - lastPressTime < multiPressWindow) {
    recentPressCount++;
    if (recentPressCount >= multiPressThreshold) {
      triggerRelease();
    }
  } else {
    recentPressCount = 1;
  }
  lastPressTime = now;
}

void removePanel(int col, int row) {
  if (!padActive[col][row]) return;
  
  padActive[col][row] = false;
  activePadCount--;
  
  // Remove panel for this grid position
  for (int i = panels.size() - 1; i >= 0; i--) {
    CoverPanel p = panels.get(i);
    if (p.gridCol == col && p.gridRow == row) {
      panels.remove(i);
      break;
    }
  }
  
  // Update Launchpad LED
  lightPad(col, row, LP_OFF);
}

void togglePad(int col, int row) {
  if (padActive[col][row]) {
    removePanel(col, row);
  } else {
    addPanel(col, row);
  }
}

void triggerRelease() {
  if (releasing) return;  // Already releasing
  
  releasing = true;
  releaseStartTime = millis();
  flashIntensity = 100;
  recentPressCount = 0;
  
  // Create shards from all panels
  for (CoverPanel p : panels) {
    createShardsFromPanel(p);
  }
  
  // Clear all pads
  clearGrid();
  
  // Flash Launchpad white
  if (hasLaunchpad) {
    flashLaunchpad();
  }
  
  // Shift hue for next buildup
  panelHue = (panelHue + 60) % 360;
}

void createShardsFromPanel(CoverPanel p) {
  // Create multiple shards from each panel
  int shardCount = 8 + (int)random(8);
  
  for (int i = 0; i < shardCount; i++) {
    float sx = p.x + random(p.w);
    float sy = p.y + random(p.h);
    shards.add(new ShardParticle(sx, sy, p.c));
  }
}

void flashLaunchpad() {
  if (!hasLaunchpad || launchpad == null) return;
  
  // Flash all pads white briefly
  for (int row = 0; row < 8; row++) {
    for (int col = 0; col < 8; col++) {
      lightPad(col, row, LP_WHITE);
    }
  }
}

void clearGrid() {
  for (int col = 0; col < 8; col++) {
    for (int row = 0; row < 8; row++) {
      padActive[col][row] = false;
    }
  }
  activePadCount = 0;
  panels.clear();
  clearAllPads();
}

// MIDI callbacks
void noteOn(int channel, int pitch, int velocity) {
  // Check for scene launch buttons (trigger release)
  if (pitch % 10 == 9 && pitch >= 19 && pitch <= 89) {
    triggerRelease();
    return;
  }
  
  if (!isValidPad(pitch)) return;
  
  PVector pos = noteToGrid(pitch);
  int col = (int)pos.x;
  int row = (int)pos.y;
  
  addPanel(col, row);
}

void noteOff(int channel, int pitch, int velocity) {
  // Optional: Remove panel on release for hold-based buildup
  // Uncomment for hold mode:
  // if (!isValidPad(pitch)) return;
  // PVector pos = noteToGrid(pitch);
  // removePanel((int)pos.x, (int)pos.y);
}

// Mouse fallback
void mousePressed() {
  // Check mini grid area
  float gridSize = 200;
  float cellSize = gridSize / 8;
  float offsetX = width - gridSize - 40;
  float offsetY = height - gridSize - 60;
  
  if (mouseX >= offsetX && mouseX < offsetX + gridSize &&
      mouseY >= offsetY && mouseY < offsetY + gridSize) {
    
    int col = (int)((mouseX - offsetX) / cellSize);
    int row = 7 - (int)((mouseY - offsetY) / cellSize);
    
    if (col >= 0 && col < 8 && row >= 0 && row < 8) {
      togglePad(col, row);
    }
  }
}

void keyPressed() {
  if (key == 'r' || key == 'R') {
    triggerRelease();
  } else if (key == 'c' || key == 'C') {
    clearGrid();
  } else if (key == ' ') {
    clearGrid();
    shards.clear();
    releasing = false;
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

// ============================================
// Cover Panel Class - represents a coverage area
// ============================================
class CoverPanel {
  float x, y, w, h;
  float targetX, targetY, targetW, targetH;
  color c;
  int gridCol, gridRow;
  float noiseOffset;
  float crackProgress = 0;
  boolean cracking = false;
  
  CoverPanel(float x, float y, float w, float h, int col, int row) {
    this.x = x;
    this.y = y;
    this.w = w;
    this.h = h;
    this.targetX = x;
    this.targetY = y;
    this.targetW = w;
    this.targetH = h;
    this.gridCol = col;
    this.gridRow = row;
    this.noiseOffset = random(1000);
    
    // Color based on position and current hue
    float hue = (panelHue + (col + row) * 8) % 360;
    this.c = color(hue, 70, 30);
  }
  
  void update() {
    // Gentle breathing/pulsing effect
    float pulse = sin(frameCount * 0.05f + noiseOffset) * 0.05f;
    w = targetW * (1 + pulse);
    h = targetH * (1 + pulse);
    
    // If releasing, start cracking
    if (releasing && !cracking) {
      cracking = true;
    }
    
    if (cracking) {
      crackProgress += 0.08f;
    }
  }
  
  void display() {
    if (crackProgress >= 1) return;
    
    float alpha = 1 - crackProgress;
    
    // Main panel
    noStroke();
    fill(hue(c), saturation(c), brightness(c), alpha * 100);
    rect(x, y, w, h);
    
    // Edge glow
    stroke(hue(c), saturation(c) - 20, brightness(c) + 30, alpha * 60);
    strokeWeight(2);
    noFill();
    rect(x, y, w, h);
    
    // Crack lines when releasing
    if (cracking && crackProgress < 0.5f) {
      drawCracks();
    }
  }
  
  void drawCracks() {
    stroke(0, 0, 100, (1 - crackProgress * 2) * 100);
    strokeWeight(2);
    
    // Draw random crack lines
    randomSeed((long)(noiseOffset * 1000));
    int numCracks = 5;
    for (int i = 0; i < numCracks; i++) {
      float cx = x + random(w);
      float cy = y + random(h);
      float angle = random(TWO_PI);
      float len = random(30, 80) * crackProgress * 2;
      line(cx, cy, cx + cos(angle) * len, cy + sin(angle) * len);
    }
  }
  
  boolean shouldRemove() {
    return crackProgress >= 1;
  }
}

// ============================================
// Shard Particle Class - flying shards during release
// ============================================
class ShardParticle {
  float x, y;
  float vx, vy;
  float size;
  color c;
  float rotation;
  float rotationSpeed;
  float life;
  float maxLife;
  float gravity = 0.3f;
  float drag = 0.98f;
  
  ShardParticle(float x, float y, color c) {
    this.x = x;
    this.y = y;
    this.c = c;
    
    // Explosion velocity - outward from center
    float centerX = width / 2.0f;
    float centerY = height / 2.0f;
    float angle = atan2(y - centerY, x - centerX);
    angle += random(-0.5f, 0.5f);
    float speed = random(10, 35);
    this.vx = cos(angle) * speed;
    this.vy = sin(angle) * speed;
    
    this.size = random(10, 40);
    this.rotation = random(TWO_PI);
    this.rotationSpeed = random(-0.3f, 0.3f);
    this.maxLife = random(40, 90);
    this.life = maxLife;
  }
  
  void update() {
    x += vx;
    y += vy;
    vy += gravity;
    vx *= drag;
    vy *= drag;
    rotation += rotationSpeed;
    life--;
    size *= 0.98f;
  }
  
  void display() {
    float alpha = map(life, 0, maxLife, 0, 100);
    
    pushMatrix();
    translate(x, y);
    rotate(rotation);
    
    // Glow
    noStroke();
    fill(hue(c), saturation(c), brightness(c) + 30, alpha * 0.3f);
    rect(-size * 0.8f, -size * 0.8f, size * 1.6f, size * 1.6f);
    
    // Core shard
    fill(hue(c), saturation(c), brightness(c), alpha);
    beginShape();
    vertex(-size/2, -size/3);
    vertex(size/3, -size/2);
    vertex(size/2, size/4);
    vertex(-size/4, size/2);
    endShape(CLOSE);
    
    // Bright edge
    stroke(0, 0, 100, alpha * 0.5f);
    strokeWeight(1);
    line(-size/2, -size/3, size/3, -size/2);
    
    popMatrix();
  }
  
  boolean isDead() {
    return life <= 0 || size < 2 || x < -100 || x > width + 100 || y > height + 100;
  }
}
