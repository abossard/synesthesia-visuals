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

import java.io.File;
import java.util.*;
import codeanticode.syphon.*;

// ============================================
// CORE COMPONENTS
// ============================================

// Syphon output
SyphonServer syphon;

// Framebuffer
PGraphics canvas;

// Audio simulation (for testing without Synesthesia)
AudioEnvelope audio;

// Levels
ArrayList<Level> levels = new ArrayList<Level>();
Level activeLevel;
int currentLevelIndex = 0;

// Timing
int lastFrameTime;
float time = 0;
long levelChangeTimeMs;
long nextLevelAtMs;
int levelDurationMs = 30000; // 30s per level

// Screenshots
String screenshotDir;
int screenshotDelayMs = 10000; // 10s after level load
int screenshotCounter = 0;
boolean levelScreenshotTaken = false;
String screenshotSessionId;

// ============================================
// SETTINGS
// ============================================

void settings() {
  pixelDensity(1);
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
  audio = new AudioEnvelope();
  audio.manualMode = true;
  audio.falloffPerSecond = 2.4;

  // Levels
  initLevels();
  switchLevel(0);

  // Screenshots
  screenshotDir = sketchPath("screenshots");
  ensureScreenshotDir();
  screenshotSessionId = nf(year(), 4) + nf(month(), 2) + nf(day(), 2) + "-" + nf(hour(), 2) + nf(minute(), 2) + nf(second(), 2);
  
  println("VJSims initialized (non-interactive mode)");
  println("  Syphon server: VJSims");
  println("  Resolution: " + width + "x" + height);
  println("  Audio: Synesthesia OSC (TODO: implement OSC listener)");
  println("  Mode: Auto-running visual simulations (" + levels.size() + " level(s))");
  println("  Level duration: " + levelDurationMs + "ms");
  
  lastFrameTime = millis();
  levelChangeTimeMs = millis();
  nextLevelAtMs = levelChangeTimeMs + levelDurationMs;
  levelScreenshotTaken = false;
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

  simulateAudio(dt);
  audio.update(dt);

  if (activeLevel != null) {
    activeLevel.update(dt, time, audio);
    
    // Render to framebuffer
    canvas.beginDraw();
    activeLevel.render(canvas);
    canvas.endDraw();
  }
  
  // Display on screen
  image(canvas, 0, 0);
  
  // Send to Syphon
  syphon.sendImage(canvas);

  // Periodic screenshots
  captureScreenshotIfNeeded();

  // Auto-rotate levels
  long now = millis();
  if (now < levelChangeTimeMs) { // handle millis wrap
    levelChangeTimeMs = now;
    nextLevelAtMs = now + levelDurationMs;
  }
  if (frameCount % 300 == 0) {
    println("Timer debug now=" + now + " target=" + nextLevelAtMs);
  }
  if (now >= nextLevelAtMs) {
    println("Auto-rotate trigger now=" + now + " target=" + nextLevelAtMs);
    nextLevel();
  }
}

// ============================================
// LEVEL MANAGEMENT
// ============================================

void initLevels() {
  levels.clear();
  // New audio-reactive P3D simulations
  levels.add(new BreathingPlanetLevel());
  levels.add(new BoidsFlockLevel());
  levels.add(new GalaxySpiralLevel());
  levels.add(new DNAHelixLevel());
  levels.add(new ToroidalFlowLevel());
  levels.add(new MetaballsLevel());
  levels.add(new Fireworks3DLevel());
  levels.add(new FFTMountainsLevel());
  levels.add(new ForceGraphLevel());
  levels.add(new LSystemTreesLevel());
  levels.add(new StarfieldWarpLevel());
  levels.add(new MeshMorphLevel());
  levels.add(new VoronoiCrystalLevel());
  levels.add(new VortexTunnelLevel());
  levels.add(new SpectrumBars3DLevel());
  levels.add(new VolumetricFireLevel());
  levels.add(new KaleidoscopeGeometryLevel());
  levels.add(new TentacleRibbonLevel());
  levels.add(new GeodesicExplosionLevel());
  levels.add(new ReactionDiffusionSurfaceLevel());

  // Existing / legacy levels
  levels.add(new GravityWellsLevel());
  levels.add(new JellyBlobsLevel());
  levels.add(new AgentTrailsLevel());
  levels.add(new ReactionDiffusionLevel());
  levels.add(new RecursiveCityLevel());
  levels.add(new LiquidFloorLevel());
  levels.add(new CellularAutomataLevel());
  levels.add(new PortalRaymarcherLevel());
  levels.add(new RopeSimulationLevel());
  levels.add(new LogoWindTunnelLevel());
  levels.add(new SwarmCamerasLevel());
  levels.add(new TimeSmearLevel());
  levels.add(new MirrorRoomsLevel());
  levels.add(new TextEngineLevel());
  // Extra stylized levels
  levels.add(new NoisyBlobLevel());
  levels.add(new WireframeTunnelLevel());
  levels.add(new FloatingTerrainLevel());
  levels.add(new ParticleGalaxyLevel());
  levels.add(new RibbonHelixLevel());
  levels.add(new RetroShipLevel());
  levels.add(new RetroFreighterLevel());
  levels.add(new ClassicPulseLevel());
}

void switchLevel(int index) {
  if (levels.size() == 0) {
    activeLevel = null;
    return;
  }
  currentLevelIndex = ((index % levels.size()) + levels.size()) % levels.size();
  activeLevel = levels.get(currentLevelIndex);
  if (activeLevel != null) {
    activeLevel.reset();
    levelChangeTimeMs = millis();
    nextLevelAtMs = levelChangeTimeMs + levelDurationMs;
    levelScreenshotTaken = false;
    println("Switched to level: " + activeLevel.getName());
  }
}

void nextLevel() {
  switchLevel(currentLevelIndex + 1);
}

void previousLevel() {
  switchLevel(currentLevelIndex - 1);
}

// ============================================
// SHUTDOWN
// ============================================

void exit() {
  println("VJSims shutting down...");
  super.exit();
}

// ============================================
// INPUTS
// ============================================

void keyPressed() {
  if (key == ']' || keyCode == RIGHT) {
    nextLevel();
  } else if (key == '[' || keyCode == LEFT) {
    previousLevel();
  }
}

// ============================================
// HELPERS
// ============================================

void simulateAudio(float dt) {
  // Auto-trigger audio simulation (simulates beats at ~120 BPM)
  if (frameCount % 30 == 0) {  // Every 0.5 seconds at 60fps
    audio.hitBass(1.0);
  }
  if (frameCount % 15 == 0) {  // Every 0.25 seconds
    audio.hitMid(0.85);
  }
  if (frameCount % 7 == 0) {   // Faster
    audio.hitHigh(0.65);
  }
}

void ensureScreenshotDir() {
  File dir = new File(screenshotDir);
  if (!dir.exists()) {
    dir.mkdirs();
  }
}

void captureScreenshotIfNeeded() {
  int now = millis();
  if (canvas == null || levelScreenshotTaken) {
    return;
  }
  if (now - levelChangeTimeMs < screenshotDelayMs) {
    return;
  }
  String levelName = activeLevel != null ? activeLevel.getName() : "vjsims";
  String safeName = levelName.toLowerCase().replaceAll("[^a-z0-9]+", "-");
  String filename = screenshotDir + "/" + screenshotSessionId + "-" + safeName + "-" + nf(screenshotCounter, 4) + ".png";
  canvas.save(filename);
  println("Saved screenshot: " + filename);
  screenshotCounter++;
  levelScreenshotTaken = true;
}
