/**
 * VJSystem — Processing VJ Visual System
 * 
 * Main sketch file for the Launchpad-controlled VJ system.
 * Outputs via Syphon for compositing in Magic/Synesthesia.
 * 
 * Requirements:
 * - Processing 4.x (Intel/x64 build on Apple Silicon for Syphon)
 * - The MidiBus library
 * - Syphon library
 * - Launchpad Mini Mk3 in Programmer mode (optional)
 */

import codeanticode.syphon.*;
import themidibus.*;

// ============================================
// CORE COMPONENTS
// ============================================

SyphonServer syphon;

// MIDI modules
MidiIO midi;
LaunchpadGrid grid;
LaunchpadHUD hud;

// ============================================
// SETTINGS
// ============================================

void settings() {
  size(1920, 1080, P3D);  // Full HD, P3D required for Syphon + 3D effects
}

// ============================================
// SETUP
// ============================================

void setup() {
  frameRate(60);
  
  // Initialize Syphon output
  syphon = new SyphonServer(this, "VJSystem");
  
  // Initialize MIDI modules
  midi = new MidiIO(this);
  grid = new LaunchpadGrid(midi);
  hud = new LaunchpadHUD(grid);
  
  // Set up MIDI listener
  midi.setListener(new MidiListener() {
    void onNote(int channel, int pitch, int velocity, boolean isOn) {
      handleMidiNote(pitch, velocity, isOn);
    }
    void onCC(int channel, int number, int value) {
      // Handle CC if needed
    }
  });
  
  // Clear Launchpad LEDs and show initial state
  hud.clearAll();
  hud.showLevelRow(0, -1, 8);  // Level 0 active, none queued, 8 available
  
  println("VJSystem initialized");
  println("  Syphon server: VJSystem");
  println("  Launchpad: " + (midi.isConnected() ? midi.getDeviceName() : "not found (keyboard mode)"));
}

// ============================================
// MAIN LOOP
// ============================================

void draw() {
  // Clear background (black = transparent in additive blend)
  background(0);
  
  // TODO: Update and draw active level
  // levelManager.update(dt, inputs);
  // levelManager.draw(g);
  
  // Placeholder visual (remove when levels are implemented)
  drawPlaceholder();
  
  // Send frame via Syphon
  syphon.sendScreen();
}

void drawPlaceholder() {
  // Simple animated visual to verify output
  pushMatrix();
  translate(width/2, height/2);
  rotate(frameCount * 0.01);
  
  stroke(255);
  strokeWeight(2);
  noFill();
  
  for (int i = 0; i < 8; i++) {
    float angle = TWO_PI / 8 * i;
    float r = 200 + sin(frameCount * 0.05 + i) * 50;
    float x = cos(angle) * r;
    float y = sin(angle) * r;
    line(0, 0, x, y);
    ellipse(x, y, 20, 20);
  }
  
  popMatrix();
  
  // Show status (debug only, remove for performance)
  if (frameCount < 180) {
    fill(255);
    textAlign(LEFT, TOP);
    textSize(14);
    text("VJSystem running", 20, 20);
    text("Syphon: VJSystem", 20, 40);
    text("Launchpad: " + (midi.isConnected() ? midi.getDeviceName() : "keyboard mode"), 20, 60);
    text("FPS: " + nf(frameRate, 0, 1), 20, 80);
  }
}

// ============================================
// MIDI HANDLING
// ============================================

void handleMidiNote(int pitch, int velocity, boolean isOn) {
  // Check if it's a scene button
  if (grid.isSceneButton(pitch)) {
    int sceneIndex = grid.getSceneIndex(pitch);
    if (isOn) {
      println("Scene button pressed: " + sceneIndex);
      // TODO: Handle scene button (arm exit, shift modifier, etc.)
    }
    return;
  }
  
  // Check if it's a valid pad
  PVector cell = grid.noteToCell(pitch);
  if (cell != null) {
    int col = (int) cell.x;
    int row = (int) cell.y;
    
    if (isOn) {
      handlePadPress(col, row, velocity);
    } else {
      handlePadRelease(col, row);
    }
  }
}

void handlePadPress(int col, int row, int velocity) {
  println("Pad pressed: col=" + col + " row=" + row + " vel=" + velocity);
  
  // Top row (row 7) = level selection
  if (row == 7) {
    println("  → Select level " + col);
    hud.showLevelRow(col, -1, 8);
    // TODO: levelManager.selectLevel(col);
    return;
  }
  
  // Echo LED for other pads
  hud.setPad(col, row, LP_GREEN);
  
  // TODO: Route to LevelManager
  // levelManager.handlePad(col, row, velocity);
}

void handlePadRelease(int col, int row) {
  // Don't clear top row (level indicators)
  if (row == 7) return;
  
  // Clear LED on release
  hud.clearPad(col, row);
}

// ============================================
// KEYBOARD FALLBACK
// ============================================

void keyPressed() {
  // Number keys 1-8 simulate top row pads (level selection)
  if (key >= '1' && key <= '8') {
    int level = key - '1';
    println("Keyboard: select level " + level);
    hud.showLevelRow(level, -1, 8);
    // TODO: levelManager.selectLevel(level);
  }
  
  // Space = simulate beat
  if (key == ' ') {
    println("Keyboard: beat trigger");
    // TODO: audioEnv.triggerBeat();
  }
  
  // R = reset
  if (key == 'r' || key == 'R') {
    println("Keyboard: reset");
    hud.clearAll();
    hud.showLevelRow(0, -1, 8);
    // TODO: levelManager.reset();
  }
}

// ============================================
// MIDI CALLBACKS (route to MidiIO)
// ============================================

void noteOn(int channel, int pitch, int velocity) {
  midi.onNoteOn(channel, pitch, velocity);
}

void noteOff(int channel, int pitch, int velocity) {
  midi.onNoteOff(channel, pitch, velocity);
}

void controllerChange(int channel, int number, int value) {
  midi.onCC(channel, number, value);
}

// ============================================
// CLEANUP
// ============================================

void exit() {
  hud.clearAll();
  super.exit();
}
