/**
 * VJSims — Processing VJ Simulation Framework
 * 
 * A highly interactive simulation framework for VJ performances.
 * Supports Launchpad control and Synesthesia Audio OSC input.
 * Outputs via Syphon for compositing in Magic/Synesthesia.
 * 
 * Requirements:
 * - Processing 4.x (Intel/x64 build on Apple Silicon for Syphon)
 * - The MidiBus library
 * - Syphon library
 * - oscP5 library (for Synesthesia Audio OSC)
 * - Launchpad Mini Mk3 in Programmer mode (optional)
 * 
 * Audio Reactivity:
 * - Synesthesia Audio OSC: Receive real-time audio analysis from Synesthesia
 *   (bass, mid, high levels, BPM, spectrum, etc.)
 * - Keyboard fallback: Simulate audio hits for testing without Synesthesia
 */

import codeanticode.syphon.*;
import themidibus.*;

// ============================================
// CORE COMPONENTS
// ============================================

// Shared context (framebuffer, syphon, audio, config)
SharedContext ctx;

// Level management
LevelManager levelManager;

// MIDI modules
MidiIO midi;
LaunchpadGrid grid;
LaunchpadHUD hud;

// Input collection
Inputs inputs;

// Timing
int lastFrameTime;

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
  lastFrameTime = millis();
  
  // Initialize shared context (creates framebuffer, syphon, audio, config)
  ctx = new SharedContext(this);
  
  // Initialize MIDI modules
  midi = new MidiIO(this);
  grid = new LaunchpadGrid(midi);
  hud = new LaunchpadHUD(grid);
  
  // Wire MIDI to shared context
  ctx.setMidi(grid, hud);
  
  // Initialize inputs collector
  inputs = new Inputs();
  
  // Initialize level manager
  levelManager = new LevelManager(ctx);
  levelManager.setHUD(hud);
  
  // Register levels
  registerLevels();
  
  // Set up MIDI listener
  midi.setListener(new MidiListener() {
    void onNote(int channel, int pitch, int velocity, boolean isOn) {
      handleMidiNote(pitch, velocity, isOn);
    }
    void onCC(int channel, int number, int value) {
      handleMidiCC(number, value);
    }
  });
  
  // Clear Launchpad LEDs
  hud.clearAll();
  
  // Start first level
  levelManager.start();

  println("VJSims initialized");
  println("  Syphon server: VJSims");
  println("  Resolution: " + width + "x" + height);
  println("  Launchpad: " + (midi.isConnected() ? midi.getDeviceName() : "not found (keyboard mode)"));
  println("  Levels: " + levelManager.getLevelCount());
  println("  Audio: Synesthesia OSC (TODO: implement OSC listener)");

  // Show keyboard controls if Launchpad not found
  if (!midi.isConnected()) {
    println();
    println("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
    println("  KEYBOARD CONTROLS (Launchpad Emulation)");
    println("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
    println("  Level Selection:");
    println("    1-8          Switch to level 1-8");
    println("    ← →          Previous/Next level");
    println();
    println("  Level Control:");
    println("    S            Start level");
    println("    R            Reset level");
    println("    P            Pause/Resume");
    println();
    println("  Audio Simulation:");
    println("    SPACE        Trigger beat (all bands)");
    println("    B            Bass hit");
    println("    M            Mid hit");
    println("    H            High hit");
    println("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
    println();
  }
}

/**
 * Register all levels with the level manager
 */
void registerLevels() {
  // Add empty placeholder levels for testing
  // Replace with actual level implementations later
  levelManager.addLevel(new EmptyLevel());
  
  // TODO: Add all 14 levels
  // levelManager.addLevel(new GravityWellsLevel());
  // levelManager.addLevel(new JellyBlobsLevel());
  // etc.
}

// ============================================
// MAIN LOOP
// ============================================

void draw() {
  // Calculate delta time
  int now = millis();
  float dt = (now - lastFrameTime) / 1000.0;
  lastFrameTime = now;
  
  // Collect inputs for this frame
  inputs.dt = dt;
  inputs.frameNum = frameCount;
  ctx.audio.copyTo(inputs);
  
  // Update audio envelope
  ctx.audio.update(dt);
  
  // Update level manager (processes pad events, updates active level)
  levelManager.update(dt, inputs);
  
  // Draw active level to framebuffer
  levelManager.draw(ctx.framebuffer);
  
  // Clear pad events for next frame
  inputs.clear();
  
  // Display framebuffer to window (for performer preview)
  image(ctx.framebuffer, 0, 0);
  
  // Send to Syphon
  ctx.sendToSyphon();
  
  // Debug overlay (first 3 seconds only)
  if (frameCount < 180) {
    drawDebugOverlay();
  }
}

void drawDebugOverlay() {
  fill(255);
  textAlign(LEFT, TOP);
  textSize(14);
  
  Level active = levelManager.getActiveLevel();
  String levelName = active != null ? active.getName() : "none";
  String fsmState = active != null ? active.getFSM().getState().toString() : "-";
  
  text("VJSims", 20, 20);
  text("Level: " + levelManager.getActiveIndex() + " - " + levelName, 20, 40);
  text("State: " + fsmState, 20, 60);
  text("FPS: " + nf(frameRate, 0, 1), 20, 80);
  text("Launchpad: " + (midi.isConnected() ? "connected" : "keyboard mode"), 20, 100);
}

// ============================================
// MIDI HANDLING
// ============================================

void handleMidiNote(int pitch, int velocity, boolean isOn) {
  // Check if it's a scene button
  if (grid.isSceneButton(pitch)) {
    int sceneIndex = grid.getSceneIndex(pitch);
    if (isOn) {
      levelManager.handleSceneButton(sceneIndex, velocity);
    }
    return;
  }
  
  // Check if it's a valid pad
  PVector cell = grid.noteToCell(pitch);
  if (cell != null) {
    int col = (int) cell.x;
    int row = (int) cell.y;
    int vel = isOn ? velocity : 0;
    
    // Add to inputs for level manager to process
    inputs.addPadEvent(col, row, vel);
    
    // Visual feedback for non-top-row pads
    if (row != 7) {
      if (isOn) {
        hud.setPad(col, row, LP_GREEN);
      } else {
        hud.clearPad(col, row);
      }
    }
  }
}

void handleMidiCC(int number, int value) {
  // CC messages could be used for audio simulation or parameter control
  // Map CC to audio bands for manual testing
  // CC 1 = bass, CC 2 = mid, CC 3 = high
  float normalized = value / 127.0;
  
  if (number == 1) {
    ctx.audio.setBass(normalized);
  } else if (number == 2) {
    ctx.audio.setMid(normalized);
  } else if (number == 3) {
    ctx.audio.setHigh(normalized);
  }
}

// ============================================
// KEYBOARD FALLBACK
// ============================================

void keyPressed() {
  // Number keys 1-8 simulate top row pads (level selection)
  if (key >= '1' && key <= '8') {
    int level = key - '1';
    if (level < levelManager.getLevelCount()) {
      levelManager.switchTo(level);
    }
  }
  
  // Arrow keys for next/prev level
  if (keyCode == RIGHT) {
    levelManager.nextLevel();
  }
  if (keyCode == LEFT) {
    levelManager.prevLevel();
  }
  
  // Space = simulate beat / audio hit
  if (key == ' ') {
    ctx.audio.hitBass(1.0);
    ctx.audio.hitMid(0.7);
    ctx.audio.hitHigh(0.5);
  }
  
  // B/M/H = individual audio band triggers
  if (key == 'b' || key == 'B') ctx.audio.hitBass(1.0);
  if (key == 'm' || key == 'M') ctx.audio.hitMid(1.0);
  if (key == 'h' || key == 'H') ctx.audio.hitHigh(1.0);
  
  // R = reset current level
  if (key == 'r' || key == 'R') {
    Level active = levelManager.getActiveLevel();
    if (active != null) {
      active.getFSM().trigger(FSMEvent.RESTART);
    }
  }
  
  // S = start current level
  if (key == 's' || key == 'S') {
    Level active = levelManager.getActiveLevel();
    if (active != null) {
      active.getFSM().trigger(FSMEvent.START);
    }
  }
  
  // P = pause/resume
  if (key == 'p' || key == 'P') {
    Level active = levelManager.getActiveLevel();
    if (active != null) {
      LevelFSM fsm = active.getFSM();
      if (fsm.isState(State.PAUSED)) {
        fsm.trigger(FSMEvent.RESUME);
      } else if (fsm.isPlaying()) {
        fsm.trigger(FSMEvent.PAUSE);
      }
    }
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
  // Dispose all levels
  if (levelManager != null) {
    levelManager.dispose();
  }
  
  // Clear Launchpad LEDs
  if (hud != null) {
    hud.clearAll();
  }
  
  super.exit();
}
