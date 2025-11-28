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
 * Syphon Output:
 * - Broadcasts as "WhackAMole" server
 * - Receivable in Synesthesia, Magic, VPT, etc.
 */

import themidibus.*;
import codeanticode.syphon.*;

MidiBus launchpad;
SyphonServer syphon;
boolean hasLaunchpad = false;

int targetCol = -1, targetRow = -1;
int score = 0;
int lastSpawnTime = 0;
int spawnInterval = 1000; // ms

// Color constants
final int COLOR_OFF = 0;
final int COLOR_TARGET = 21; // Green
final int COLOR_HIT = 5;     // Red
final int COLOR_MISS = 9;    // Orange

void settings() {
  size(800, 800, P3D);  // P3D required for Syphon
}

void setup() {
  textSize(48);
  textAlign(CENTER, CENTER);
  
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
  background(0);
  
  // Draw score
  fill(255);
  text("WHACK-A-MOLE", width/2, 40);
  text("Score: " + score, width/2, 100);
  
  // Draw speed indicator
  textSize(24);
  fill(150);
  text("Speed: " + (1000 - spawnInterval + 300) / 10 + "%", width/2, 150);
  
  // Show controller status
  fill(hasLaunchpad ? color(0, 255, 0) : color(255, 200, 0));
  text(hasLaunchpad ? "Launchpad Connected" : "Mouse Mode (click grid)", width/2, height - 30);
  textSize(48);
  
  // Draw grid representation
  drawGrid();
  
  // Spawn new target periodically
  if (millis() - lastSpawnTime > spawnInterval) {
    clearTarget();
    spawnTarget();
  }
  
  // Send frame to Syphon
  syphon.sendScreen();
}

void drawGrid() {
  float cellSize = 80;
  float offsetX = (width - cellSize * 8) / 2;
  float offsetY = 200;
  
  for (int row = 0; row < 8; row++) {
    for (int col = 0; col < 8; col++) {
      float x = offsetX + col * cellSize;
      float y = offsetY + (7 - row) * cellSize; // Flip Y to match Launchpad
      
      if (col == targetCol && row == targetRow) {
        fill(0, 255, 0);
      } else {
        fill(50);
      }
      stroke(100);
      rect(x, y, cellSize - 2, cellSize - 2);
    }
  }
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
  float cellSize = 80;
  float offsetX = (width - cellSize * 8) / 2;
  float offsetY = 200;
  
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
  if (col == targetCol && row == targetRow) {
    // Hit!
    score++;
    lightPad(col, row, COLOR_HIT);
    delay(100);
    clearPad(col, row);
    spawnTarget();
    
    // Speed up as score increases
    spawnInterval = max(300, 1000 - score * 50);
  } else {
    // Miss - flash orange
    lightPad(col, row, COLOR_MISS);
    delay(50);
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
