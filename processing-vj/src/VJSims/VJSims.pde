/**
 * VJSims — Processing VJ Simulation Framework
 * 
 * Framework for interactive VJ simulations with Synesthesia Audio OSC support.
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
 * - Keyboard fallback: Simulate audio hits for testing without Synesthesia
 */

import codeanticode.syphon.*;

// ============================================
// CORE COMPONENTS
// ============================================

// Shared context (framebuffer, syphon, audio, config)
SharedContext ctx;

// Level management
LevelManager levelManager;

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
  
  // Initialize shared context
  ctx = new SharedContext(this);
  
  // Initialize inputs collector
  inputs = new Inputs();
  
  // Initialize level manager
  levelManager = new LevelManager(ctx);
  
  // Register levels
  registerLevels();
  
  // Start first level
  levelManager.start();

  println("VJSims initialized");
  println("  Syphon server: VJSims");
  println("  Resolution: " + width + "x" + height);
  println("  Levels: " + levelManager.getLevelCount());
  println("  Audio: Synesthesia OSC (TODO: implement OSC listener)");
  println();
  println("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
  println("  KEYBOARD CONTROLS");
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
  println();
  println("  System:");
  println("    ESC          Quit");
  println("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
  println();
  
  lastFrameTime = millis();
}

// ============================================
// LEVEL REGISTRATION
// ============================================

void registerLevels() {
  // Add simulation levels here
  // levelManager.addLevel(new MyCustomLevel());
  
  // Default empty level
  levelManager.addLevel(new EmptyLevel());
}

// ============================================
// MAIN LOOP
// ============================================

void draw() {
  // Calculate delta time
  int currentTime = millis();
  float dt = (currentTime - lastFrameTime) / 1000.0;
  lastFrameTime = currentTime;
  
  // Begin framebuffer
  ctx.canvas.beginDraw();
  
  // Update level manager
  levelManager.update(dt);
  
  // Render active level
  levelManager.render();
  
  // End framebuffer
  ctx.canvas.endDraw();
  
  // Display on screen
  image(ctx.canvas, 0, 0);
  
  // Send to Syphon
  ctx.syphon.sendImage(ctx.canvas);
  
  // Optional: Display info overlay
  if (ctx.showInfo) {
    fill(255);
    textAlign(LEFT, TOP);
    text("FPS: " + int(frameRate), 20, 20);
    text("Level: " + levelManager.getCurrentLevelName(), 20, 40);
    text("Audio: Synesthesia OSC (TODO)", 20, 60);
  }
}

// ============================================
// KEYBOARD HANDLING
// ============================================

void keyPressed() {
  // Level selection (1-8)
  if (key >= '1' && key <= '8') {
    int levelIndex = key - '1';
    levelManager.switchToLevel(levelIndex);
    return;
  }
  
  // Level navigation
  if (keyCode == LEFT) {
    levelManager.previousLevel();
    return;
  }
  if (keyCode == RIGHT) {
    levelManager.nextLevel();
    return;
  }
  
  // Level control
  if (key == 's' || key == 'S') {
    levelManager.start();
    return;
  }
  if (key == 'r' || key == 'R') {
    levelManager.reset();
    return;
  }
  if (key == 'p' || key == 'P') {
    levelManager.togglePause();
    return;
  }
  
  // Audio simulation (for testing without Synesthesia)
  if (key == ' ') {
    // Trigger all bands
    ctx.audio.triggerBeat();
    ctx.audio.bass.trigger();
    ctx.audio.mid.trigger();
    ctx.audio.high.trigger();
    return;
  }
  if (key == 'b' || key == 'B') {
    ctx.audio.bass.trigger();
    return;
  }
  if (key == 'm' || key == 'M') {
    ctx.audio.mid.trigger();
    return;
  }
  if (key == 'h' || key == 'H') {
    ctx.audio.high.trigger();
    return;
  }
  
  // System
  if (key == 'i' || key == 'I') {
    ctx.showInfo = !ctx.showInfo;
    return;
  }
}

// ============================================
// SHUTDOWN
// ============================================

void exit() {
  println("VJSims shutting down...");
  super.exit();
}
