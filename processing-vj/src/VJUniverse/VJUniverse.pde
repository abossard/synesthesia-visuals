/**
 * VJUniverse - Audioreactive Visual Engine
 * 
 * A Processing sketch with:
 * - P3D renderer for generative visuals
 * - Dynamic shader loading (GLSL + ISF)
 * - FFT audio analysis
 * - OSC for song metadata
 * - LM Studio LLM for shader selection (OpenAI-compatible API)
 * - Disk caching of selections
 */

import processing.sound.*;
import oscP5.*;
import netP5.*;
import codeanticode.syphon.*;

// ============================================
// CONFIGURATION
// ============================================
final int WINDOW_WIDTH = 1280;
final int WINDOW_HEIGHT = 720;  // HD Ready resolution
final int OSC_PORT = 9000;  // Match karaoke_engine default
final String LLM_URL = "http://localhost:1234";  // LM Studio default
final String LLM_MODEL = "local-model";  // LM Studio uses whatever model is loaded
final String SHADERS_PATH = "shaders";
final String SCENES_PATH = "scenes";

// ============================================
// GLOBAL STATE
// ============================================

// Audio
AudioIn audioIn;
FFT fft;
int fftBands = 512;
float[] spectrum = new float[fftBands];
float bass, mid, treble, level;
float smoothBass, smoothMid, smoothTreble;
float beatThreshold = 0.15;
float lastBeatTime = 0;
float beatPhase = 0;

// OSC
OscP5 oscP5;
SongMetadata currentSong;
StringBuilder lyricsAccumulator = new StringBuilder();  // For chunked lyrics

// Shaders
ArrayList<ShaderInfo> availableShaders = new ArrayList<ShaderInfo>();
ShaderSelection currentSelection;
PShader activeShader;
int currentShaderIndex = 0;

// Multi-pass rendering
PGraphics passBuffer1;
PGraphics passBuffer2;
boolean useMultiPass = false;  // Disabled by default - single shader mode
ArrayList<PShader> activeShaderPipeline = new ArrayList<PShader>();

// State
boolean debugMode = true;
boolean llmAvailable = false;
float globalTime = 0;

// LLM retry state
long lastLlmCheck = 0;
final int LLM_RETRY_INTERVAL = 10000;  // 10 seconds
String llmStatus = "checking...";
boolean llmQueryInProgress = false;

// Debug console
boolean consoleActive = false;
StringBuilder consoleInput = new StringBuilder();
ArrayList<String> consoleHistory = new ArrayList<String>();
final int CONSOLE_MAX_HISTORY = 20;

// Syphon output
SyphonServer syphon;

// ============================================
// SETUP
// ============================================

void settings() {
  size(WINDOW_WIDTH, WINDOW_HEIGHT, P3D);
}

void setup() {
  frameRate(60);
  colorMode(RGB, 255);
  
  // Initialize multi-pass buffers
  passBuffer1 = createGraphics(width, height, P3D);
  passBuffer2 = createGraphics(width, height, P3D);
  
  // Initialize audio
  initAudio();
  
  // Initialize OSC
  initOsc();
  
  // Check LLM availability BEFORE loading shaders (needed for analysis)
  llmAvailable = checkLlmAvailable();
  llmStatus = llmAvailable ? "connected" : "offline";
  println("LLM available: " + llmAvailable);
  
  // Load shaders (will trigger analysis if LLM available)
  loadAllShaders();
  
  // Initialize with first shader if available
  if (availableShaders.size() > 0) {
    loadShaderByIndex(0);
  }
  
  // Initialize empty song
  currentSong = new SongMetadata("", "", "", "");
  
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
  
  // Update audio analysis
  updateAudio();
  
  // Check for shader file changes (auto-reload)
  reloadShadersIfChanged();
  
  // Periodically retry LLM if not available
  checkLlmRetry();
  
  // Clear background
  background(0);
  
  // Apply shader pipeline (multi-pass or single)
  if (useMultiPass && activeShaderPipeline.size() > 1) {
    drawMultiPassPipeline();
  } else if (activeShader != null) {
    try {
      applyShaderUniforms();
      shader(activeShader);
      drawFullscreenQuad();
      resetShader();
    } catch (Exception e) {
      // Shader error - reset and continue
      resetShader();
      drawFullscreenQuad();
    }
  } else {
    drawFullscreenQuad();
  }
  
  // Send frame to Syphon (guard against early frames)
  if (syphon != null && frameCount > 1) {
    try {
      syphon.sendScreen();
    } catch (Exception e) {
      // Silently ignore Syphon errors (e.g., pixels not ready)
    }
  }
  
  // Draw debug overlay
  if (debugMode) {
    drawDebugOverlay();
  }
  
  // Draw console (always on top)
  if (consoleActive) {
    drawConsole();
  }
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
  vertex(0, 0, 0, 0);
  vertex(width, 0, 1, 0);
  vertex(width, height, 1, 1);
  vertex(0, height, 0, 1);
  endShape();
}

void applyShaderUniforms() {
  if (activeShader == null) return;
  applyShaderUniformsTo(activeShader, null);
}

void applyShaderUniformsTo(PShader s, PGraphics pg) {
  if (s == null) return;
  
  float w = pg != null ? pg.width : width;
  float h = pg != null ? pg.height : height;
  
  // Set uniforms safely - Processing warns but doesn't crash if uniform unused
  // These warnings are expected and harmless
  try {
    // Standard uniforms (most shaders use these)
    s.set("time", globalTime);
    s.set("resolution", w, h);
    
    // Audio uniforms
    s.set("bass", smoothBass);
    s.set("mid", smoothMid);
    s.set("treble", smoothTreble);
    s.set("level", level);
    s.set("beat", beatPhase);
    
    // ISF compatibility uniforms
    s.set("TIME", globalTime);
    s.set("RENDERSIZE", w, h);
    
    // Apply ISF uniform defaults (critical for animation!)
    // These are the values from the shader's INPUTS DEFAULT fields
    for (String name : isfUniformDefaults.keySet()) {
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
// AUDIO ANALYSIS
// ============================================

void initAudio() {
  audioIn = new AudioIn(this, 0);
  audioIn.start();
  
  fft = new FFT(this, fftBands);
  fft.input(audioIn);
}

void updateAudio() {
  fft.analyze(spectrum);
  
  // Calculate band levels
  bass = calculateBandLevel(0, 10);
  mid = calculateBandLevel(10, 100);
  treble = calculateBandLevel(100, fftBands);
  level = calculateBandLevel(0, fftBands);
  
  // Smooth values
  float smoothing = 0.85;
  smoothBass = lerp(smoothBass, bass, 1 - smoothing);
  smoothMid = lerp(smoothMid, mid, 1 - smoothing);
  smoothTreble = lerp(smoothTreble, treble, 1 - smoothing);
  
  // Simple beat detection
  if (bass > beatThreshold && millis() - lastBeatTime > 200) {
    lastBeatTime = millis();
    beatPhase = 1.0;
  }
  beatPhase *= 0.95;
}

float calculateBandLevel(int startBand, int endBand) {
  float sum = 0;
  int count = min(endBand, fftBands) - startBand;
  for (int i = startBand; i < min(endBand, fftBands); i++) {
    sum += spectrum[i];
  }
  return count > 0 ? sum / count : 0;
}

// ============================================
// OSC HANDLING
// ============================================

void initOsc() {
  oscP5 = new OscP5(this, OSC_PORT);
}

void oscEvent(OscMessage msg) {
  String addr = msg.addrPattern();
  
  // Karaoke Engine format: /karaoke/track [active, source, artist, title, album, duration, has_lyrics]
  if (addr.equals("/karaoke/track")) {
    try {
      int active = msg.get(0).intValue();
      if (active == 1) {
        // Parse track info: [active, source, artist, title, album, duration, has_lyrics]
        String artist = msg.get(2).stringValue();
        String title = msg.get(3).stringValue();
        
        // Update song with artist + title only (ignore lyrics for LLM)
        currentSong = new SongMetadata("", title, artist, "");
        
        consoleLog("Track: " + artist + " - " + title);
        onNewSong();
      }
    } catch (Exception e) {
      println("OSC /karaoke/track parse error: " + e.getMessage());
    }
  }
  // Legacy format support (README spec)
  else if (addr.equals("/song/title") && msg.checkTypetag("s")) {
    currentSong = currentSong.withTitle(msg.get(0).stringValue());
  }
  else if (addr.equals("/song/artist") && msg.checkTypetag("s")) {
    currentSong = currentSong.withArtist(msg.get(0).stringValue());
  }
  else if (addr.equals("/song/lyrics") && msg.checkTypetag("s")) {
    lyricsAccumulator.append(msg.get(0).stringValue());
    currentSong = currentSong.withLyrics(lyricsAccumulator.toString());
  }
  else if (addr.equals("/song/lyrics/clear")) {
    lyricsAccumulator.setLength(0);
    currentSong = currentSong.withLyrics("");
  }
  else if (addr.equals("/song/id") && msg.checkTypetag("s")) {
    lyricsAccumulator.setLength(0);
    currentSong = currentSong.withId(msg.get(0).stringValue());
  }
  else if (addr.equals("/song/new")) {
    onNewSong();
  }
  
  // Debug log (only show non-spammy messages)
  if (!addr.contains("/pos") && !addr.contains("/active")) {
    println("OSC: " + addr);
  }
}

void onNewSong() {
  println("New song received: " + currentSong.title + " by " + currentSong.artist);
  
  // Try to load cached selection first
  String songId = currentSong.getId();
  ShaderSelection cached = loadCachedSelection(songId);
  
  if (cached != null) {
    println("Using cached selection for: " + songId);
    currentSelection = cached;
    applySelection();
  } else if (llmAvailable) {
    // Query LLM for new selection
    println("Querying LLM for shader selection...");
    thread("queryLlmForSelection");
  } else {
    // Random selection fallback
    println("LLM unavailable, using random selection");
    selectRandomShaders();
  }
}

// ============================================
// LLM RETRY LOGIC
// ============================================

void checkLlmRetry() {
  if (llmAvailable || llmQueryInProgress) return;
  
  long now = millis();
  if (now - lastLlmCheck > LLM_RETRY_INTERVAL) {
    lastLlmCheck = now;
    thread("retryLlmConnection");
  }
}

void retryLlmConnection() {
  llmStatus = "checking...";
  boolean available = checkLlmAvailable();
  llmAvailable = available;
  llmStatus = available ? "connected" : "offline (retrying)";
  
  if (available) {
    consoleLog("LM Studio connected!");
  }
}

// ============================================
// DEBUG CONSOLE
// ============================================

void drawConsole() {
  // Full-width console at bottom
  int consoleHeight = 250;
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
  int maxLines = min(consoleHistory.size(), 12);
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
  text("Type song title + ENTER to lookup shaders | 'status' = show status | 'clear' = clear history", width - 10, height - 10);
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
    consoleLog("LLM: " + llmStatus);
    consoleLog("Shaders: " + availableShaders.size() + " loaded");
    consoleLog("Analyzed: " + shaderAnalyses.size() + " / " + availableShaders.size());
    consoleLog("Song: " + (currentSong.title.isEmpty() ? "(none)" : currentSong.title));
    consoleLog("Selection: " + (currentSelection != null ? currentSelection.mood : "(none)"));
    if (analysisInProgress) {
      consoleLog("Analysis: in progress (" + shadersToAnalyze.size() + " remaining)");
    }
  }
  else if (input.equalsIgnoreCase("clear")) {
    consoleHistory.clear();
    consoleLog("History cleared");
  }
  else if (input.equalsIgnoreCase("retry")) {
    thread("retryLlmConnection");
    consoleLog("Retrying LM Studio connection...");
  }
  else if (input.equalsIgnoreCase("random")) {
    selectRandomShaders();
    consoleLog("Random shaders selected");
  }
  else if (input.equalsIgnoreCase("analyze")) {
    if (analysisInProgress) {
      consoleLog("Analysis already in progress");
    } else if (!llmAvailable) {
      consoleLog("LLM not available");
    } else {
      consoleLog("Re-analyzing all shaders...");
      thread("reanalyzeAllShaders");
    }
  }
  else if (input.equalsIgnoreCase("shaders")) {
    // List all shaders with their analysis
    for (ShaderInfo shader : availableShaders) {
      ShaderAnalysis a = shaderAnalyses.get(shader.name);
      if (a != null) {
        consoleLog(shader.name + ": " + a.mood + ", " + a.energy);
      } else {
        consoleLog(shader.name + ": (not analyzed)");
      }
    }
  }
  else if (input.equalsIgnoreCase("help")) {
    consoleLog("Commands: status, clear, retry, random, analyze, shaders, help");
    consoleLog("Or enter a song title to find matching shaders");
  }
  else {
    // Treat as song title
    consoleLog("Looking up: \"" + input + "\"");
    currentSong = new SongMetadata("", input, "", "");
    lyricsAccumulator.setLength(0);
    
    // Try cache first
    String songId = currentSong.getId();
    ShaderSelection cached = loadCachedSelection(songId);
    
    if (cached != null) {
      consoleLog("Found cached selection: " + cached.mood);
      currentSelection = cached;
      applySelection();
    } else if (llmAvailable && !llmQueryInProgress) {
      consoleLog("Querying LLM...");
      thread("queryLlmForSelectionWithLog");
    } else if (!llmAvailable) {
      consoleLog("LLM offline, using random selection");
      selectRandomShaders();
    } else {
      consoleLog("LLM query in progress, please wait...");
    }
  }
}

void queryLlmForSelectionWithLog() {
  llmQueryInProgress = true;
  llmStatus = "querying...";
  
  try {
    String prompt = buildShaderSelectionPrompt(currentSong, availableShaders);
    String response = callLlm(prompt);
    
    if (response == null) {
      consoleLog("LLM call failed");
      selectRandomShaders();
      llmStatus = "error";
      return;
    }
    
    ShaderSelection selection = parseShaderSelectionResponse(currentSong.getId(), response);
    
    if (selection == null) {
      consoleLog("Could not parse LLM response");
      selectRandomShaders();
      llmStatus = "parse error";
      return;
    }
    
    consoleLog("LLM mood: " + selection.mood);
    consoleLog("Shaders: " + String.join(", ", selection.shaderIds));
    
    currentSelection = selection;
    saveCachedSelection(selection);
    applySelection();
    llmStatus = "connected";
    
  } finally {
    llmQueryInProgress = false;
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
    case 'R':
      loadAllShaders();
      println("Shaders reloaded: " + availableShaders.size());
      break;
    case ' ':
      if (currentShaderIndex < availableShaders.size()) {
        loadShaderByIndex(currentShaderIndex);
      }
      break;
    case 'l':
    case 'L':
      // Force LLM query
      if (currentSong != null && !currentSong.title.isEmpty()) {
        thread("queryLlmForSelection");
      }
      break;
  }
}

void nextShader() {
  if (availableShaders.size() == 0) return;
  currentShaderIndex = (currentShaderIndex + 1) % availableShaders.size();
  loadShaderByIndex(currentShaderIndex);
}

void prevShader() {
  if (availableShaders.size() == 0) return;
  currentShaderIndex = (currentShaderIndex - 1 + availableShaders.size()) % availableShaders.size();
  loadShaderByIndex(currentShaderIndex);
}

// ============================================
// DEBUG OVERLAY
// ============================================

void drawDebugOverlay() {
  // Semi-transparent background
  fill(0, 180);
  noStroke();
  rect(10, 10, 400, 280);
  
  // Text
  fill(255);
  textSize(14);
  textAlign(LEFT, TOP);
  
  int y = 20;
  int lineHeight = 18;
  
  text("FPS: " + nf(frameRate, 0, 1), 20, y); y += lineHeight;
  text("Time: " + nf(globalTime, 0, 2), 20, y); y += lineHeight;
  y += 5;
  
  // LLM status with color indicator
  fill(llmAvailable ? color(0, 255, 100) : color(255, 100, 100));
  text("LLM: " + llmStatus, 20, y); y += lineHeight;
  fill(255);
  
  // Shader analysis status
  if (analysisInProgress) {
    fill(255, 200, 50);  // Yellow for in-progress
    text("Analysis: IN PROGRESS (" + shadersToAnalyze.size() + " remaining)", 20, y); y += lineHeight;
    // Show which shader is being analyzed
    if (currentAnalyzingShader != null && !currentAnalyzingShader.isEmpty()) {
      text("  Analyzing: " + currentAnalyzingShader, 20, y); y += lineHeight;
    }
  } else {
    fill(100, 255, 100);  // Green for done
    text("Analyzed: " + shaderAnalyses.size() + "/" + availableShaders.size() + " shaders", 20, y); y += lineHeight;
  }
  fill(255);
  y += 5;
  
  text("Audio:", 20, y); y += lineHeight;
  text("  Bass:   " + nf(smoothBass, 0, 3), 20, y); y += lineHeight;
  text("  Mid:    " + nf(smoothMid, 0, 3), 20, y); y += lineHeight;
  text("  Treble: " + nf(smoothTreble, 0, 3), 20, y); y += lineHeight;
  y += 5;
  
  String shaderName = availableShaders.size() > 0 ? 
    availableShaders.get(currentShaderIndex).name : "none";
  text("Shader [" + (currentShaderIndex + 1) + "/" + availableShaders.size() + "]: " + shaderName, 20, y); y += lineHeight;
  
  // Show shader analysis info if available
  if (availableShaders.size() > 0) {
    ShaderAnalysis analysis = shaderAnalyses.get(shaderName);
    if (analysis != null) {
      fill(180, 180, 255);
      text("  Mood: " + analysis.mood + " | Energy: " + analysis.energy, 20, y); y += lineHeight;
      if (analysis.colors.length > 0) {
        text("  Colors: " + String.join(", ", analysis.colors), 20, y); y += lineHeight;
      }
    } else {
      fill(150);
      text("  (not analyzed yet)", 20, y); y += lineHeight;
    }
  }
  fill(255);
  y += 5;
  
  text("Song: " + (currentSong.title.isEmpty() ? "(none)" : currentSong.title), 20, y); y += lineHeight;
  text("Artist: " + (currentSong.artist.isEmpty() ? "(none)" : currentSong.artist), 20, y); y += lineHeight;
  
  // Controls hint at bottom
  fill(150);
  textSize(12);
  text("D=debug  N/P=shader  R=reload  ENTER=console", 20, height - 25);
}
