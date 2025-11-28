/**
 * Whack-a-Mole Game
 * 
 * A simple reaction game for Launchpad Mini Mk3.
 * Pads light up and players must hit them quickly to score points.
 * 
 * Requirements:
 * - Processing 4.x
 * - The MidiBus library
 * - Launchpad Mini Mk3 in Programmer mode
 * 
 * Controls:
 * - Hit lit pads to score
 * - Game speeds up as score increases
 */

import themidibus.*;

MidiBus launchpad;
int targetCol = -1, targetRow = -1;
int score = 0;
int lastSpawnTime = 0;
int spawnInterval = 1000; // ms

// Color constants
final int COLOR_OFF = 0;
final int COLOR_TARGET = 21; // Green
final int COLOR_HIT = 5;     // Red
final int COLOR_MISS = 9;    // Orange

void setup() {
  size(800, 800);
  textSize(48);
  textAlign(CENTER, CENTER);
  
  // List MIDI devices
  MidiBus.list();
  
  // Connect to Launchpad (use MIDI 2 port for Programmer mode)
  // Adjust the device name to match your system
  launchpad = new MidiBus(this, "Launchpad Mini MK3 MIDI 2", "Launchpad Mini MK3 MIDI 2");
  
  clearAllPads();
  spawnTarget();
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
  textSize(48);
  
  // Draw grid representation
  drawGrid();
  
  // Spawn new target periodically
  if (millis() - lastSpawnTime > spawnInterval) {
    clearTarget();
    spawnTarget();
  }
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
  
  if (col == targetCol && row == targetRow) {
    // Hit!
    score++;
    lightPad(col, row, COLOR_HIT); // Flash red
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
  int note = gridToNote(col, row);
  launchpad.sendNoteOn(0, note, colorIndex);
}

void clearPad(int col, int row) {
  lightPad(col, row, COLOR_OFF);
}

void clearAllPads() {
  for (int row = 0; row < 8; row++) {
    for (int col = 0; col < 8; col++) {
      clearPad(col, row);
    }
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
