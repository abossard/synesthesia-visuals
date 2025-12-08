/**
 * VJUniverse - Audioreactive Visual Engine
 * 
 * A Processing sketch with:
 * - P3D renderer for generative visuals
 * - Dynamic shader loading (GLSL + ISF)
 * - OSC-driven audio analysis
 * - OSC for song metadata
 * - LM Studio LLM for shader selection (OpenAI-compatible API)
 * - Disk caching of selections
 */

import oscP5.*;
import netP5.*;
import codeanticode.syphon.*;

// ============================================
// CONFIGURATION
// ============================================
final int WINDOW_WIDTH = 1280;
final int WINDOW_HEIGHT = 720;  // HD Ready resolution
final int OSC_PORT = 9000;  // Match karaoke_engine default
final String SHADERS_PATH = "shaders";
final String SCENES_PATH = "scenes";

// ============================================
// GLOBAL STATE
// ============================================

// OSC
OscP5 oscP5;

// Shaders
ArrayList<ShaderInfo> availableShaders = new ArrayList<ShaderInfo>();
PShader activeShader;
int currentShaderIndex = 0;

// Shader hints from Python (0-1 range, for uniform modulation)
float shaderEnergyHint = 0.5;
float shaderValenceHint = 0.5;

// Multi-pass rendering
PGraphics passBuffer1;
PGraphics passBuffer2;
boolean useMultiPass = false;  // Disabled by default - single shader mode
ArrayList<PShader> activeShaderPipeline = new ArrayList<PShader>();

// State
boolean debugMode = true;
float globalTime = 0;

// Debug console
boolean consoleActive = false;
StringBuilder consoleInput = new StringBuilder();
ArrayList<String> consoleHistory = new ArrayList<String>();
final int CONSOLE_MAX_HISTORY = 20;

// Syphon output
SyphonServer syphon;

// Screenshot scheduling
float screenshotScheduledTime = -1;  // Time when screenshot should be taken (-1 = none scheduled)
String screenshotShaderName = "";    // Shader name for scheduled screenshot
final float SCREENSHOT_DELAY = 1.0;  // Seconds after shader load to take screenshot
final String SCREENSHOTS_PATH = "screenshots";  // Folder for screenshots

// Shader cycling mode (triggered by 'R')
boolean shaderCyclingActive = false;
int shaderCycleIndex = 0;
float lastShaderCycleTime = 0;
final float SHADER_CYCLE_DELAY = 2.0;  // Seconds between shader changes

// Shader rendering parameters
float shaderZoom = 1.0;  // 1.0 = normal, >1 = zoom in, <1 = zoom out
float shaderOffsetX = 0.0;  // Pan offset X (-1 to 1)
float shaderOffsetY = 0.0;  // Pan offset Y (-1 to 1)

// Offscreen buffer for shader rendering (allows zoom/pan post-process)
PGraphics shaderBuffer;

// ============================================
// SETUP
// ============================================

void settings() {
  size(WINDOW_WIDTH, WINDOW_HEIGHT, P3D);
  // Disable HiDPI scaling for sanity checks (use logical pixel grid)
  pixelDensity(1);
}

void setup() {
  frameRate(60);
  colorMode(RGB, 255);
  
  // Initialize multi-pass buffers
  passBuffer1 = createGraphics(width, height, P3D);
  passBuffer2 = createGraphics(width, height, P3D);
  
  // Initialize shader render buffer for zoom/pan support
  shaderBuffer = createGraphics(width, height, P3D);
  
  // Initialize OSC audio bridge (Synesthesia feed)
  initSynesthesiaAudio();
  
  // Initialize OSC
  initOsc();
  
  // Load shaders
  loadAllShaders();
  
  // Initialize with first shader if available
  if (availableShaders.size() > 0) {
    loadShaderByIndex(0);
  }
  
  // Initialize Syphon output
  syphon = new SyphonServer(this, "VJUniverse");
  
  println("VJUniverse initialized");
  println("Shaders found: " + availableShaders.size());
  println("OSC listening on port: " + OSC_PORT);
}

// ============================================
// MAIN DRAW LOOP
// ============================================

void draw() {
  globalTime = millis() / 1000.0;
  
  // Update audio parameters from OSC feed
  updateSynesthesiaAudio();
  
  // Check for shader file changes (auto-reload)
  reloadShadersIfChanged();
  
  // Clear background
  background(0);
  
  // TWO-STAGE RENDERING for zoom/pan support:
  // 1. Render shader to offscreen buffer at native resolution
  // 2. Draw buffer to screen with zoom/pan transformation
  
  // Stage 1: Render shader to buffer
  shaderBuffer.beginDraw();
  shaderBuffer.background(0);
  
  if (useMultiPass && activeShaderPipeline.size() > 1) {
    // Multi-pass renders to its own buffers, copy result
    drawMultiPassPipeline();
    // Note: multi-pass currently draws to main screen, would need refactor
  } else if (activeShader != null) {
    try {
      applyShaderUniformsTo(activeShader, shaderBuffer);
      shaderBuffer.shader(activeShader);
      drawQuadTo(shaderBuffer);
      shaderBuffer.resetShader();
    } catch (Exception e) {
      // Shader error - just draw plain quad
      shaderBuffer.resetShader();
      drawQuadTo(shaderBuffer);
    }
  } else {
    drawQuadTo(shaderBuffer);
  }
  shaderBuffer.endDraw();
  
  // Stage 2: Draw buffer to screen with zoom/pan transformation
  drawShaderBufferWithZoomPan();
  
  // Send frame to Syphon
  if (syphon != null && frameCount > 1) {
    syphon.sendScreen();
  }
  
  // Check for scheduled screenshot
  checkScheduledScreenshot();
  
  // Update shader cycling if active
  updateShaderCycling();
  
  // Draw audio bars (AudioManager.pde)
  drawAudioBars();
  
  // Draw debug overlay
  if (debugMode) {
    drawDebugOverlay();
  }
  
  // Draw console (always on top)
  if (consoleActive) {
    drawConsole();
  }
  
  // Device selection UI removed (OSC feed handles audio input)
}

void drawMultiPassPipeline() {
  PGraphics source = passBuffer1;
  PGraphics target = passBuffer2;
  
  // First pass: render to buffer1
  source.beginDraw();
  source.background(0);
  if (activeShaderPipeline.size() > 0) {
    PShader firstShader = activeShaderPipeline.get(0);
    applyShaderUniformsTo(firstShader, source);
    source.shader(firstShader);
  }
  drawQuadTo(source);
  source.resetShader();
  source.endDraw();
  
  // Subsequent passes: ping-pong between buffers
  for (int i = 1; i < activeShaderPipeline.size(); i++) {
    // Swap buffers
    PGraphics temp = source;
    source = target;
    target = temp;
    
    target.beginDraw();
    target.background(0);
    PShader passShader = activeShaderPipeline.get(i);
    applyShaderUniformsTo(passShader, target);
    passShader.set("prevPass", source);  // Previous pass as texture
    target.shader(passShader);
    drawQuadTo(target);
    target.resetShader();
    target.endDraw();
  }
  
  // Draw final result to screen
  image(activeShaderPipeline.size() % 2 == 1 ? source : target, 0, 0);
}

void drawQuadTo(PGraphics pg) {
  pg.noStroke();
  pg.fill(255);
  pg.beginShape(QUADS);
  pg.vertex(0, 0, 0, 0);
  pg.vertex(pg.width, 0, 1, 0);
  pg.vertex(pg.width, pg.height, 1, 1);
  pg.vertex(0, pg.height, 0, 1);
  pg.endShape();
}

void drawFullscreenQuad() {
  noStroke();
  fill(255);
  beginShape(QUADS);
  vertex(0, 0, 0, 1);
  vertex(width, 0, 1, 1);
  vertex(width, height, 1, 0);
  vertex(0, height, 0, 0);
  endShape();
}

/**
 * Draw the shader buffer to screen with zoom and pan transformation.
 * This is the key to making zoom/pan work with gl_FragCoord-based shaders.
 * 
 * Zoom > 1: image appears larger (zoomed in)
 * Zoom < 1: image appears smaller (zoomed out)
 * Offset: shifts the view (pan)
 */
void drawShaderBufferWithZoomPan() {
  // Calculate the scaled dimensions and position
  float scaledW = width * shaderZoom;
  float scaledH = height * shaderZoom;
  
  // Center the scaled image, then apply offset
  // Offset is in normalized coordinates (-1 to 1), convert to pixels
  float offsetPixelsX = shaderOffsetX * width;
  float offsetPixelsY = shaderOffsetY * height;
  
  float x = (width - scaledW) / 2 - offsetPixelsX * shaderZoom;
  float y = (height - scaledH) / 2 - offsetPixelsY * shaderZoom;
  
  // Draw the shader buffer scaled and positioned
  imageMode(CORNER);
  image(shaderBuffer, x, y, scaledW, scaledH);
}

void applyShaderUniforms() {
  if (activeShader == null) return;
  applyShaderUniformsTo(activeShader, null);
}

void applyShaderUniformsTo(PShader s, PGraphics pg) {
  if (s == null) return;
  
  // Use PIXEL dimensions, not logical dimensions!
  // On Retina/HiDPI displays, pixelWidth/pixelHeight are 2x width/height
  // gl_FragCoord operates in physical pixels, so resolution must match
  float w = pg != null ? pg.pixelWidth : pixelWidth;
  float h = pg != null ? pg.pixelHeight : pixelHeight;
  
  // Set uniforms safely - Processing warns but doesn't crash if uniform unused
  // These warnings are expected and harmless
  try {
    // Standard uniforms (most shaders use these)
    s.set("time", globalTime);
    s.set("resolution", w, h);
    
    // ISF compatibility uniforms
    s.set("TIME", globalTime);
    s.set("RENDERSIZE", w, h);
    
    // Mouse uniform (for Shadertoy-style GLSL shaders)
    // Y is flipped to match OpenGL conventions
    // Default to center (0.5, 0.5) normalized when mouse is at origin
    // Many GLSL shaders use mouse for critical calculations and fail with (0,0)
    float mx = mouseX;
    float my = mouseY;
    if (mx == 0 && my == 0) {
      // Mouse hasn't moved - default to center for shader compatibility
      mx = w * 0.5f;
      my = h * 0.5f;
    }
    s.set("mouse", mx / w, 1.0f - (my / h));  // Normalized 0-1, Y-flipped
    
    // Speed uniform: audio-reactive time scaling (0-1)
    // Key hook for GLSL shader audio reactivity
    // Uses energyFast which responds well to music dynamics
    // Adaptive tempo: ensure motion never fully stops and swells with energy + kick dynamics
    float baseSpeedFloor = 0.15f + energySlow * 0.15f;   // 0.15 – 0.30 based on long envelope
    float speedRange = max(0.0f, 1.0f - baseSpeedFloor);
    float audioSpeed = baseSpeedFloor + (energyFast * speedRange);
    audioSpeed += 0.08f * kickEnv;  // Gentle beat accent, keeps impact without spikes
    audioSpeed = constrain(audioSpeed, baseSpeedFloor, 1.0f);
    s.set("speed", audioSpeed);
    
    // Apply audio uniforms from AudioManager (includes bound uniforms)
    applyAudioUniformsToShader(s);
    
    // Apply ISF uniform defaults (for uniforms not bound to audio)
    // Only set if not already bound to audio
    for (String name : isfUniformDefaults.keySet()) {
      // Skip if this uniform is audio-bound
      if (boundUniformValues.containsKey(name)) continue;
      
      float[] val = isfUniformDefaults.get(name);
      if (val.length == 1) {
        s.set(name, val[0]);
      } else if (val.length == 2) {
        s.set(name, val[0], val[1]);
      } else if (val.length == 3) {
        s.set(name, val[0], val[1], val[2]);
      } else if (val.length == 4) {
        s.set(name, val[0], val[1], val[2], val[3]);
      }
    }
  } catch (Exception e) {
    // Silently ignore uniform errors - shader may not use all uniforms
  }
}

// ============================================
// OSC HANDLING
// ============================================

void initOsc() {
  oscP5 = new OscP5(this, OSC_PORT);
}

void oscEvent(OscMessage msg) {
  String addr = msg.addrPattern();
  
  if (handleSynesthesiaAudioMessage(msg)) {
    return;
  }
  
  // Python shader selection: /shader/load [name, energy, valence]
  if (addr.equals("/shader/load")) {
    try {
      String shaderName = msg.get(0).stringValue();
      float energy = msg.get(1).floatValue();
      float valence = msg.get(2).floatValue();
      
      consoleLog("Shader: " + shaderName + " (e=" + nf(energy,1,2) + " v=" + nf(valence,1,2) + ")");
      loadShaderByName(shaderName);
      
      // Store hints for future uniform modulation
      shaderEnergyHint = energy;
      shaderValenceHint = valence;
    } catch (Exception e) {
      println("OSC /shader/load error: " + e.getMessage());
    }
  }
  
  // Log non-spammy OSC messages
  if (!addr.startsWith("/karaoke/") && !addr.contains("/active")) {
    println("OSC: " + addr);
  }
}

// ============================================
// DEBUG CONSOLE
// ============================================

void drawConsole() {
  // Full-width console at bottom
  int consoleHeight = 200;
  int y = height - consoleHeight;
  
  // Background
  fill(0, 220);
  noStroke();
  rect(0, y, width, consoleHeight);
  
  // Border
  stroke(100);
  line(0, y, width, y);
  
  // Title
  fill(0, 255, 0);
  textSize(14);
  textAlign(LEFT, TOP);
  text("> VJUniverse Console (ENTER to submit, ESC to close)", 10, y + 5);
  
  // History
  fill(200);
  textSize(12);
  int historyY = y + 30;
  int maxLines = min(consoleHistory.size(), 10);
  int startIdx = max(0, consoleHistory.size() - maxLines);
  for (int i = startIdx; i < consoleHistory.size(); i++) {
    text(consoleHistory.get(i), 10, historyY);
    historyY += 15;
  }
  
  // Input line
  fill(255);
  textSize(14);
  String cursor = (frameCount % 30 < 15) ? "_" : "";
  text("> " + consoleInput.toString() + cursor, 10, height - 30);
  
  // Help text
  fill(100);
  textSize(11);
  textAlign(RIGHT, BOTTOM);
  text("Commands: status, clear, shaders, help", width - 10, height - 10);
  textAlign(LEFT, TOP);
}

void consoleLog(String msg) {
  consoleHistory.add(msg);
  while (consoleHistory.size() > CONSOLE_MAX_HISTORY) {
    consoleHistory.remove(0);
  }
  println("[Console] " + msg);
}

void consoleSubmit() {
  String input = consoleInput.toString().trim();
  consoleInput.setLength(0);
  
  if (input.isEmpty()) return;
  
  consoleLog("> " + input);
  
  // Handle commands
  if (input.equalsIgnoreCase("status")) {
    consoleLog("Shaders: " + availableShaders.size() + " loaded");
    consoleLog("Current: " + (availableShaders.size() > 0 ? availableShaders.get(currentShaderIndex).name : "none"));
  }
  else if (input.equalsIgnoreCase("clear")) {
    consoleHistory.clear();
    consoleLog("History cleared");
  }
  else if (input.equalsIgnoreCase("shaders")) {
    for (ShaderInfo shader : availableShaders) {
      consoleLog("  " + shader.name + " [" + shader.type + "]");
    }
  }
  else if (input.equalsIgnoreCase("help")) {
    consoleLog("Commands: status, clear, shaders, help");
    consoleLog("Keys: D=debug N/P=shader R=reload");
  }
  else {
    // Try to load shader by name
    boolean found = false;
    for (int i = 0; i < availableShaders.size(); i++) {
      if (availableShaders.get(i).name.equalsIgnoreCase(input)) {
        loadShaderByIndex(i);
        consoleLog("Loaded: " + availableShaders.get(i).name);
        found = true;
        break;
      }
    }
    if (!found) {
      consoleLog("Unknown command or shader: " + input);
    }
  }
}

// ============================================
// KEYBOARD CONTROLS
// ============================================

void keyPressed() {
  // Console input handling
  if (consoleActive) {
    if (key == ENTER || key == RETURN) {
      consoleSubmit();
    }
    else if (key == ESC) {
      key = 0;  // Prevent sketch exit
      consoleActive = false;
    }
    else if (key == BACKSPACE) {
      if (consoleInput.length() > 0) {
        consoleInput.deleteCharAt(consoleInput.length() - 1);
      }
    }
    else if (key >= 32 && key < 127) {
      consoleInput.append(key);
    }
    return;  // Don't process other keys when console is active
  }
  
  // Normal key handling
  if (key == ENTER || key == RETURN) {
    consoleActive = true;
    return;
  }
  
  switch (key) {
    case 'd':
    case 'D':
      debugMode = !debugMode;
      break;
    case 'n':
    case 'N':
      nextShader();
      break;
    case 'p':
    case 'P':
      prevShader();
      break;
    case 'r':
      loadAllShaders();
      println("Shaders reloaded: " + availableShaders.size());
      break;
    case 'R':
      startShaderCycling();
      break;
    case 't':
    case 'T':
      toggleShaderTypeFilter();  // Toggle GLSL/ISF/All
      break;
    case ' ':
      if (currentShaderIndex < getFilteredShaderList().size()) {
        loadShaderByIndex(currentShaderIndex);
      }
      break;
    case 'b':
    case 'B':
      showAudioBars = !showAudioBars;  // Toggle audio bars visibility
      break;
    case 'z':
      shaderZoom = max(0.1, shaderZoom - 0.1);  // Zoom out
      println("Shader zoom: " + nf(shaderZoom, 1, 2));
      break;
    case 'Z':
      shaderZoom = min(5.0, shaderZoom + 0.1);  // Zoom in
      println("Shader zoom: " + nf(shaderZoom, 1, 2));
      break;
    case 'x':
    case 'X':
      shaderZoom = 1.0;  // Reset zoom and offset
      shaderOffsetX = 0.0;
      shaderOffsetY = 0.0;
      println("Shader zoom/offset reset");
      break;
  }
  
  // Arrow keys for shader panning (only when not in modal dialogs)
  if (key == CODED) {
    float offsetStep = 0.05 / shaderZoom;  // Scale step by zoom for consistent feel
    switch (keyCode) {
      case LEFT:
        // LEFT arrow = pan view left = move shader content right = increase offset
        shaderOffsetX = constrain(shaderOffsetX + offsetStep, -1.0, 1.0);
        println("Pan LEFT: offset = " + nf(shaderOffsetX, 1, 3) + ", " + nf(shaderOffsetY, 1, 3));
        break;
      case RIGHT:
        // RIGHT arrow = pan view right = move shader content left = decrease offset
        shaderOffsetX = constrain(shaderOffsetX - offsetStep, -1.0, 1.0);
        println("Pan RIGHT: offset = " + nf(shaderOffsetX, 1, 3) + ", " + nf(shaderOffsetY, 1, 3));
        break;
      case UP:
        // UP arrow = pan view up = move shader content down = increase Y offset
        shaderOffsetY = constrain(shaderOffsetY + offsetStep, -1.0, 1.0);
        println("Pan UP: offset = " + nf(shaderOffsetX, 1, 3) + ", " + nf(shaderOffsetY, 1, 3));
        break;
      case DOWN:
        // DOWN arrow = pan view down = move shader content up = decrease Y offset
        shaderOffsetY = constrain(shaderOffsetY - offsetStep, -1.0, 1.0);
        println("Pan DOWN: offset = " + nf(shaderOffsetX, 1, 3) + ", " + nf(shaderOffsetY, 1, 3));
        break;
    }
  }
}

void nextShader() {
  ArrayList<ShaderInfo> list = getFilteredShaderList();
  if (list.size() == 0) return;
  currentShaderIndex = (currentShaderIndex + 1) % list.size();
  loadShaderByIndex(currentShaderIndex);
}

void prevShader() {
  ArrayList<ShaderInfo> list = getFilteredShaderList();
  if (list.size() == 0) return;
  currentShaderIndex = (currentShaderIndex - 1 + list.size()) % list.size();
  loadShaderByIndex(currentShaderIndex);
}

// ============================================
// DEBUG OVERLAY
// ============================================

void drawDebugOverlay() {
  // Semi-transparent background
  fill(0, 180);
  noStroke();
  rect(10, 10, 380, 220);
  
  // Text
  fill(255);
  textSize(14);
  textAlign(LEFT, TOP);
  
  int y = 20;
  int lineHeight = 18;
  
  text("FPS: " + nf(frameRate, 0, 1), 20, y); y += lineHeight;
  text("Time: " + nf(globalTime, 0, 2), 20, y); y += lineHeight;
  y += 5;
  
  boolean audioActive = isSynAudioActive();
  String audioStatus = audioActive ? "stream" : "wait";
  text("Audio [" + audioStatus + "]: " + synAudioSourceLabel, 20, y); y += lineHeight;
  text("  Age: " + nf(synAudioAgeSeconds(), 0, 1) + "s", 20, y); y += lineHeight;
  text("  Energy: " + nf(energyFast, 0, 2) + " (slow: " + nf(energySlow, 0, 2) + ")", 20, y); y += lineHeight;
  text("  Kick: " + nf(kickEnv, 0, 2) + " | Beat: " + beat4, 20, y); y += lineHeight;
  text("  Bindings: " + audioBindings.size(), 20, y); y += lineHeight;
  y += 5;
  
  // Shader info with type filter
  ArrayList<ShaderInfo> list = getFilteredShaderList();
  ShaderInfo current = getCurrentShaderInfo();
  String shaderName = current != null ? current.name : "none";
  String shaderType = current != null ? current.type.toString() : "";
  String filterStr = currentTypeFilter == null ? "ALL" : currentTypeFilter.toString();
  
  text("Filter: " + filterStr + " | Shader [" + (currentShaderIndex + 1) + "/" + list.size() + "]", 20, y); y += lineHeight;
  text("  " + shaderType + ": " + shaderName, 20, y); y += lineHeight;
  text("  Zoom: " + nf(shaderZoom, 1, 2) + " | Offset: " + nf(shaderOffsetX, 1, 2) + ", " + nf(shaderOffsetY, 1, 2), 20, y); y += lineHeight;
  
  // Controls hint at bottom
  fill(150);
  textSize(12);
  text("D=debug N/P=shader T=type z/Z=zoom arrows=pan X=reset r=reload B=bars", 20, height - 25);
}

// ============================================
// SCREENSHOT FUNCTIONALITY
// ============================================

void scheduleScreenshot(String shaderName) {
  // Check if screenshot already exists
  String screenshotPath = getScreenshotPath(shaderName);
  File screenshotFile = new File(dataPath(screenshotPath));
  
  if (screenshotFile.exists()) {
    println("Screenshot already exists: " + screenshotPath);
    return;
  }
  
  // Schedule screenshot for 5 seconds from now
  screenshotScheduledTime = globalTime + SCREENSHOT_DELAY;
  screenshotShaderName = shaderName;
  println("Screenshot scheduled for shader: " + shaderName + " at t=" + nf(screenshotScheduledTime, 0, 1));
}

void checkScheduledScreenshot() {
  if (screenshotScheduledTime < 0) return;  // No screenshot scheduled
  
  if (globalTime >= screenshotScheduledTime) {
    takeScreenshot(screenshotShaderName);
    screenshotScheduledTime = -1;  // Clear schedule
    screenshotShaderName = "";
  }
}

void takeScreenshot(String shaderName) {
  // Create screenshots directory if needed
  File screenshotsDir = new File(dataPath(SCREENSHOTS_PATH));
  if (!screenshotsDir.exists()) {
    screenshotsDir.mkdirs();
  }
  
  String screenshotPath = getScreenshotPath(shaderName);
  
  // Save current frame (before debug overlay)
  saveFrame(dataPath(screenshotPath));
  println("Screenshot saved: " + screenshotPath);
  consoleLog("📸 Screenshot: " + shaderName);
}

String getScreenshotPath(String shaderName) {
  // Replace path separators with underscores for flat file storage
  String safeName = shaderName.replace("/", "_").replace("\\", "_");
  return SCREENSHOTS_PATH + "/" + safeName + ".png";
}


// ============================================
// SHADER CYCLING (R key)
// ============================================

void startShaderCycling() {
  if (availableShaders.size() == 0) {
    println("No shaders to cycle through");
    return;
  }
  
  shaderCyclingActive = true;
  shaderCycleIndex = 0;
  lastShaderCycleTime = globalTime;
  
  // Load first shader
  loadShaderByIndex(shaderCycleIndex);
  println("Shader cycling started: " + availableShaders.size() + " shaders, " + SHADER_CYCLE_DELAY + "s each");
  consoleLog("🔄 Cycling " + availableShaders.size() + " shaders...");
}

void updateShaderCycling() {
  if (!shaderCyclingActive) return;
  
  // Check if it's time to advance to next shader
  if (globalTime - lastShaderCycleTime >= SHADER_CYCLE_DELAY) {
    shaderCycleIndex++;
    
    if (shaderCycleIndex >= availableShaders.size()) {
      // Done cycling
      shaderCyclingActive = false;
      println("Shader cycling complete");
      consoleLog("✓ Cycling complete");
      return;
    }
    
    // Load next shader
    loadShaderByIndex(shaderCycleIndex);
    lastShaderCycleTime = globalTime;
    println("Cycling shader " + (shaderCycleIndex + 1) + "/" + availableShaders.size() + ": " + availableShaders.get(shaderCycleIndex).name);
  }
}

