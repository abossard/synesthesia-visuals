/**
 * AudioManager.pde - Audio-reactive processing for VJUniverse
 * 
 * Features:
 * - Audio device selection UI (arrow keys + enter)
 * - FFT analysis with multiple bands
 * - Audio parameter visualization (bars)
 * - OSC audio binding configuration
 * - BlackHole default device
 * 
 * Audio Sources (from MMV pipeline):
 *   bass: 20-120 Hz (kick/sub)
 *   lowMid: 120-350 Hz (drum body)
 *   highs: 2000-6000 Hz (hats/cymbals)
 *   kickEnv: 40-120 Hz envelope (attack detection)
 *   kickPulse: binary 0/1 on kick hits
 *   beat4: 4-step counter (0,1,2,3)
 *   energyFast: weighted band mix
 *   energySlow: 4s averaged energy
 *   level: overall loudness
 */

import processing.sound.*;

// ============================================
// AUDIO DEVICE SELECTION
// ============================================

String[] audioDevices;
int selectedDeviceIndex = 0;
boolean deviceSelectionActive = false;
boolean audioInitialized = false;
String currentDeviceName = "none";

// Retry mechanism
int audioRetryCount = 0;
final int MAX_AUDIO_RETRIES = 5;
final int RETRY_DELAY_MS = 2000;  // 2 seconds between retries
float lastRetryTime = 0;
boolean audioRetryPending = false;
int pendingDeviceIndex = -1;

// Preferences file for device persistence
final String AUDIO_PREFS_FILE = "audio_device.txt";

// ============================================
// AUDIO ANALYSIS STATE
// ============================================

// Raw FFT data
float[] rawSpectrum;

// Processed audio bands (0-1 range, smoothed)
float audioBass = 0;          // 20-120 Hz
float audioLowMid = 0;        // 120-350 Hz  
float audioMid = 0;           // 350-2000 Hz
float audioHighs = 0;         // 2000-6000 Hz
float audioLevel = 0;         // Overall loudness

// Smoothed versions (for shaders)
float smoothAudioBass = 0;
float smoothAudioLowMid = 0;
float smoothAudioMid = 0;
float smoothAudioHighs = 0;
float smoothAudioLevel = 0;

// Kick detection
float kickRaw = 0;
float kickEnvSlow = 0;
float kickEnvFast = 0;
float kickEnv = 0;            // Final kick envelope
int kickPulse = 0;            // Binary kick trigger
float lastKickTime = 0;
float kickThreshold = 0.3;  // Lower threshold since values are boosted

// Beat tracking
int beat4 = 0;                // 4-step counter
float beatPhaseAudio = 0;     // Continuous phase 0-1

// Energy tracking
float energyFast = 0;         // Real-time weighted mix
float energySlow = 0;         // 4s averaged
float songStyle = 0.5;        // 0=bass-focused, 1=highs-focused (from OSC)

// History for averaging
float[] energyHistory;
int energyHistoryIndex = 0;
int energyHistorySize = 240;  // ~4 seconds at 60fps

// ============================================
// AUDIO BINDING CONFIGURATION (from OSC)
// ============================================

ArrayList<AudioBinding> audioBindings = new ArrayList<AudioBinding>();

// Computed values for bound uniforms (name -> computed value)
HashMap<String, Float> boundUniformValues = new HashMap<String, Float>();

// ============================================
// VISUALIZATION
// ============================================

boolean showAudioBars = false;
int barHeight = 150;
int barWidth = 30;
int barSpacing = 5;

// ============================================
// CONSTANTS
// ============================================

final float AUDIO_SMOOTHING = 0.85;       // Default smoothing (higher = smoother)
final float KICK_SMOOTHING_SLOW = 0.95;   // Slow kick envelope
final float KICK_SMOOTHING_FAST = 0.7;    // Fast kick envelope
final float ENERGY_SMOOTHING = 0.92;      // Energy tracking smoothing
final float KICK_COOLDOWN_MS = 200;       // Min time between kicks


// ============================================
// INITIALIZATION
// ============================================

void initAudioManager() {
  // Get available audio devices
  audioDevices = Sound.list();
  if (audioDevices == null) {
    audioDevices = new String[0];
  }
  
  println("[Audio] Found " + audioDevices.length + " devices");
  for (int i = 0; i < audioDevices.length; i++) {
    println("  [" + i + "] " + audioDevices[i]);
  }
  
  // Initialize spectrum array
  rawSpectrum = new float[fftBands];
  
  // Initialize energy history
  energyHistory = new float[energyHistorySize];
  
  // Try to load saved device preference
  int savedIndex = loadSavedDeviceIndex();
  
  if (savedIndex >= 0 && savedIndex < audioDevices.length) {
    println("[Audio] Restoring saved device: " + audioDevices[savedIndex]);
    selectedDeviceIndex = savedIndex;
    selectAudioDevice(savedIndex);
  } else {
    // Find BlackHole by default
    int blackholeIndex = findDeviceByName("blackhole");
    
    if (blackholeIndex >= 0) {
      println("[Audio] Using BlackHole device");
      selectedDeviceIndex = blackholeIndex;
      selectAudioDevice(blackholeIndex);
    } else if (audioDevices.length > 0) {
      println("[Audio] Using first available device");
      selectedDeviceIndex = 0;
      selectAudioDevice(0);
    } else {
      println("[Audio] Warning: No audio devices found!");
    }
  }
  
  println("[Audio] Manager initialized");
}

int findDeviceByName(String namePart) {
  String lower = namePart.toLowerCase();
  for (int i = 0; i < audioDevices.length; i++) {
    if (audioDevices[i].toLowerCase().contains(lower)) {
      return i;
    }
  }
  return -1;
}

void selectAudioDevice(int index) {
  if (audioDevices == null || index < 0 || index >= audioDevices.length) {
    println("[Audio] Invalid device index: " + index);
    return;
  }
  
  println("[Audio] Selecting device " + index + ": " + audioDevices[index]);
  
  try {
    // Stop existing audio input safely
    if (audioIn != null) {
      try {
        audioIn.stop();
      } catch (Exception e) {
        // Ignore stop errors
      }
      audioIn = null;
    }
    
    // Set input device (static method)
    Sound.inputDevice(index);
    
    // Reinitialize audio input with new device
    audioIn = new AudioIn(this, 0);
    audioIn.start();
    
    // Reinitialize FFT
    fft = new FFT(this, fftBands);
    fft.input(audioIn);
    
    currentDeviceName = audioDevices[index];
    selectedDeviceIndex = index;
    audioInitialized = true;
    audioRetryPending = false;
    audioRetryCount = 0;
    
    // Save preference
    saveDeviceIndex(index);
    
    println("[Audio] Device active: " + currentDeviceName);
    
  } catch (Exception e) {
    println("[Audio] Failed to initialize device: " + e.getMessage());
    audioInitialized = false;
    scheduleRetry(index);
  }
}

void scheduleRetry(int deviceIndex) {
  if (audioRetryCount >= MAX_AUDIO_RETRIES) {
    println("[Audio] Max retries reached, giving up on device " + deviceIndex);
    audioRetryPending = false;
    return;
  }
  
  audioRetryCount++;
  audioRetryPending = true;
  pendingDeviceIndex = deviceIndex;
  lastRetryTime = millis();
  println("[Audio] Retry " + audioRetryCount + "/" + MAX_AUDIO_RETRIES + " scheduled in " + (RETRY_DELAY_MS/1000) + "s");
}

void checkAudioRetry() {
  if (!audioRetryPending) return;
  
  if (millis() - lastRetryTime >= RETRY_DELAY_MS) {
    println("[Audio] Retrying device selection...");
    audioRetryPending = false;
    selectAudioDevice(pendingDeviceIndex);
  }
}

// ============================================
// DEVICE PREFERENCE PERSISTENCE
// ============================================

void saveDeviceIndex(int index) {
  if (index < 0 || index >= audioDevices.length) return;
  
  try {
    String[] lines = { audioDevices[index] };
    saveStrings(dataPath(AUDIO_PREFS_FILE), lines);
  } catch (Exception e) {
    // Silent fail - preference saving is not critical
  }
}

int loadSavedDeviceIndex() {
  try {
    File f = new File(dataPath(AUDIO_PREFS_FILE));
    if (!f.exists()) return -1;
    
    String[] lines = loadStrings(dataPath(AUDIO_PREFS_FILE));
    if (lines == null || lines.length == 0) return -1;
    
    String savedName = lines[0].trim();
    for (int i = 0; i < audioDevices.length; i++) {
      if (audioDevices[i].equals(savedName)) {
        return i;
      }
    }
  } catch (Exception e) {
    // Silent fail
  }
  return -1;
}


// ============================================
// AUDIO ANALYSIS UPDATE (call every frame)
// ============================================

void updateAudioAnalysis() {
  // Check for pending retries
  checkAudioRetry();
  
  if (!audioInitialized || fft == null) return;
  
  try {
    // Get raw FFT spectrum
    fft.analyze(rawSpectrum);
  
  // Calculate frequency bands
  // FFT bin to Hz: bin * sampleRate / fftSize
  // At 44100 Hz with 512 bands: each bin ≈ 86 Hz
  // bass (20-120): bins 0-1
  // lowMid (120-350): bins 1-4
  // mid (350-2000): bins 4-23
  // highs (2000-6000): bins 23-70
  
  float newBass = calculateBandEnergy(0, 2);       // ~0-172 Hz
  float newLowMid = calculateBandEnergy(2, 5);    // ~172-430 Hz
  float newMid = calculateBandEnergy(5, 25);      // ~430-2150 Hz
  float newHighs = calculateBandEnergy(25, 70);   // ~2150-6020 Hz
  float newLevel = calculateBandEnergy(0, 256);   // Full spectrum
  
  // Raw values (unsmoothed)
  audioBass = newBass;
  audioLowMid = newLowMid;
  audioMid = newMid;
  audioHighs = newHighs;
  audioLevel = newLevel;
  
  // Smoothed values
  smoothAudioBass = lerp(smoothAudioBass, newBass, 1 - AUDIO_SMOOTHING);
  smoothAudioLowMid = lerp(smoothAudioLowMid, newLowMid, 1 - AUDIO_SMOOTHING);
  smoothAudioMid = lerp(smoothAudioMid, newMid, 1 - AUDIO_SMOOTHING);
  smoothAudioHighs = lerp(smoothAudioHighs, newHighs, 1 - AUDIO_SMOOTHING);
  smoothAudioLevel = lerp(smoothAudioLevel, newLevel, 1 - AUDIO_SMOOTHING);
  
  // Kick detection
  updateKickDetection();
  
  // Energy tracking
  updateEnergyTracking();
  
  // Update bound uniform values
  updateBoundUniforms();
  
  } catch (Exception e) {
    // Audio analysis failed - schedule retry
    println("[Audio] Analysis error: " + e.getMessage());
    audioInitialized = false;
    scheduleRetry(selectedDeviceIndex);
  }
}

float calculateBandEnergy(int startBin, int endBin) {
  float sum = 0;
  int count = min(endBin, fftBands) - startBin;
  for (int i = startBin; i < min(endBin, fftBands); i++) {
    sum += rawSpectrum[i];
  }
  // FFT values are tiny (0.0-0.1), boost heavily for 0-1 output
  // Using 50x gain - adjust if still too quiet/loud
  return count > 0 ? constrain(sum / count * 50.0, 0, 1) : 0;
}

void updateKickDetection() {
  // Kick raw: tight bass band with extra boost for punch detection
  kickRaw = calculateBandEnergy(0, 2) * 3;  // Additional 3x for transient detection
  
  // Dual envelope (from MMV guide)
  kickEnvSlow = lerp(kickEnvSlow, kickRaw, 1 - KICK_SMOOTHING_SLOW);
  kickEnvFast = lerp(kickEnvFast, kickRaw, 1 - KICK_SMOOTHING_FAST);
  
  // Blend based on songStyle: 0=slow, 1=fast
  kickEnv = kickEnvSlow * (1 - songStyle) + kickEnvFast * songStyle;
  
  // Kick pulse: detect transients
  float timeSinceKick = millis() - lastKickTime;
  if (kickRaw > kickThreshold && timeSinceKick > KICK_COOLDOWN_MS) {
    kickPulse = 1;
    lastKickTime = millis();
    
    // Advance beat counter
    beat4 = (beat4 + 1) % 4;
  } else {
    kickPulse = 0;
  }
  
  // Continuous beat phase (decays between kicks)
  beatPhaseAudio *= 0.95;
  if (kickPulse == 1) beatPhaseAudio = 1.0;
}

void updateEnergyTracking() {
  // Energy fast: weighted band mix (adapts to songStyle)
  // songStyle 0: bass-heavy (0.6 bass, 0.2 mid, 0.2 high)
  // songStyle 1: highs-heavy (0.2 bass, 0.4 mid, 0.4 high)
  float bassWeight = 0.6 - 0.4 * songStyle;
  float midWeight = 0.2 + 0.2 * songStyle;
  float highWeight = 0.2 + 0.2 * songStyle;
  
  energyFast = smoothAudioBass * bassWeight + 
               smoothAudioMid * midWeight + 
               smoothAudioHighs * highWeight;
  energyFast = constrain(energyFast, 0, 1);
  
  // Energy slow: rolling average over ~4 seconds
  energyHistory[energyHistoryIndex] = energyFast;
  energyHistoryIndex = (energyHistoryIndex + 1) % energyHistorySize;
  
  float sum = 0;
  for (int i = 0; i < energyHistorySize; i++) {
    sum += energyHistory[i];
  }
  energySlow = sum / energyHistorySize;
}


// ============================================
// AUDIO BINDINGS (from OSC)
// ============================================

class AudioBinding {
  String uniformName;
  String audioSource;      // bass, lowMid, highs, kickEnv, etc.
  String modulationType;   // add, multiply, replace, threshold
  float multiplier;
  float smoothing;
  float baseValue;
  float minValue;
  float maxValue;
  
  // Internal state
  float smoothedValue = 0;
  
  AudioBinding(String uniform, String source, String modType, 
               float mult, float smooth, float base, float minV, float maxV) {
    this.uniformName = uniform;
    this.audioSource = source;
    this.modulationType = modType;
    this.multiplier = mult;
    this.smoothing = smooth;
    this.baseValue = base;
    this.minValue = minV;
    this.maxValue = maxV;
  }
  
  float getAudioValue() {
    // Map audio source name to actual value
    switch (audioSource) {
      case "bass": return smoothAudioBass;
      case "lowMid": return smoothAudioLowMid;
      case "mid": return smoothAudioMid;
      case "highs": return smoothAudioHighs;
      case "treble": return smoothAudioHighs;  // Alias
      case "kickEnv": return kickEnv;
      case "kickPulse": return (float)kickPulse;
      case "beat4": return beat4 / 3.0;  // Normalize to 0-1
      case "energyFast": return energyFast;
      case "energySlow": return energySlow;
      case "level": return smoothAudioLevel;
      case "beatPhase": return beatPhaseAudio;
      default: return smoothAudioLevel;
    }
  }
  
  float compute() {
    float audio = getAudioValue();
    
    // Apply smoothing
    smoothedValue = lerp(smoothedValue, audio, 1 - smoothing);
    
    // Apply modulation
    float result;
    switch (modulationType) {
      case "add":
        result = baseValue + (smoothedValue * multiplier);
        break;
      case "multiply":
        result = baseValue * (1 + smoothedValue * multiplier);
        break;
      case "replace":
        result = smoothedValue * multiplier;
        break;
      case "threshold":
        result = smoothedValue > multiplier ? 1.0 : 0.0;
        break;
      default:
        result = baseValue + smoothedValue * multiplier;
    }
    
    return constrain(result, minValue, maxValue);
  }
}

void clearAudioBindings() {
  audioBindings.clear();
  boundUniformValues.clear();
  println("[Audio] Bindings cleared");
}

/**
 * Setup default audio bindings based on ISF uniform names.
 * Called when a shader loads and no OSC bindings were configured.
 * Maps common uniform name patterns to appropriate audio sources.
 */
void setupDefaultAudioBindings() {
  audioBindings.clear();
  boundUniformValues.clear();
  
  // Common ISF uniform patterns and their audio mappings
  // Format: addAudioBinding(uniform, source, modType, mult, smooth, base, min, max)
  
  for (String name : isfUniformDefaults.keySet()) {
    String lower = name.toLowerCase();
    float[] defaults = isfUniformDefaults.get(name);
    float baseVal = defaults.length > 0 ? defaults[0] : 0.5;
    
    // Skip uniforms that are clearly not audio targets
    if (lower.equals("time") || lower.equals("resolution") || lower.contains("size") ||
        lower.contains("color") || lower.contains("colour") || lower.contains("position")) {
      continue;
    }
    
    // Speed/rate uniforms → energyFast (music tempo drives animation speed)
    if (lower.contains("speed") || lower.contains("rate") || lower.contains("velocity")) {
      addAudioBinding(name, "energyFast", "multiply", 2.0, 0.8, baseVal, 0.1, baseVal * 3);
      continue;
    }
    
    // Scale/zoom uniforms → bass (bass makes things grow/pulse)
    if (lower.contains("scale") || lower.contains("zoom") || lower.contains("size")) {
      addAudioBinding(name, "bass", "add", 0.5, 0.7, baseVal, baseVal * 0.5, baseVal * 2);
      continue;
    }
    
    // Intensity/brightness/amount → level (overall loudness)
    if (lower.contains("intensity") || lower.contains("brightness") || lower.contains("amount") ||
        lower.contains("strength") || lower.contains("power")) {
      addAudioBinding(name, "level", "multiply", 1.5, 0.6, baseVal, 0.0, 1.0);
      continue;
    }
    
    // Distortion/warp/noise → kickEnv (punch on beats)
    if (lower.contains("distort") || lower.contains("warp") || lower.contains("noise") ||
        lower.contains("glitch") || lower.contains("chaos")) {
      addAudioBinding(name, "kickEnv", "add", 0.8, 0.5, baseVal * 0.3, 0.0, 1.0);
      continue;
    }
    
    // Rotation/angle → mid (melodic content drives rotation)
    if (lower.contains("rotat") || lower.contains("angle") || lower.contains("spin")) {
      addAudioBinding(name, "mid", "add", 0.5, 0.75, baseVal, baseVal - 0.5, baseVal + 0.5);
      continue;
    }
    
    // Offset/shift/displacement → highs (high frequencies add detail movement)
    if (lower.contains("offset") || lower.contains("shift") || lower.contains("displace")) {
      addAudioBinding(name, "highs", "add", 0.3, 0.6, baseVal, baseVal - 0.3, baseVal + 0.3);
      continue;
    }
    
    // Frequency/wave → bass (bass pulses drive wave frequency)
    if (lower.contains("freq") || lower.contains("wave")) {
      addAudioBinding(name, "bass", "multiply", 1.5, 0.7, baseVal, baseVal * 0.5, baseVal * 2);
      continue;
    }
    
    // Blend/mix/fade → energySlow (slow envelope for smooth transitions)
    if (lower.contains("blend") || lower.contains("mix") || lower.contains("fade") ||
        lower.contains("alpha") || lower.contains("opacity")) {
      addAudioBinding(name, "energySlow", "replace", 1.0, 0.9, 0.5, 0.0, 1.0);
      continue;
    }
    
    // Iteration/steps/detail → level (more detail when loud)
    if (lower.contains("iter") || lower.contains("step") || lower.contains("detail") ||
        lower.contains("octave")) {
      addAudioBinding(name, "level", "multiply", 1.0, 0.8, baseVal, baseVal * 0.5, baseVal * 1.5);
      continue;
    }
  }
  
  int bindCount = audioBindings.size();
  if (bindCount > 0) {
    println("[Audio] Auto-wired " + bindCount + " default bindings");
  } else {
    println("[Audio] No uniforms matched for auto-binding");
  }
}

void addAudioBinding(String uniform, String source, String modType,
                     float mult, float smooth, float base, float minV, float maxV) {
  AudioBinding binding = new AudioBinding(uniform, source, modType, mult, smooth, base, minV, maxV);
  audioBindings.add(binding);
  println("[Audio] Binding: " + uniform + " <- " + source + " (" + modType + ")");
}

void updateBoundUniforms() {
  for (AudioBinding binding : audioBindings) {
    float value = binding.compute();
    boundUniformValues.put(binding.uniformName, value);
  }
}

float getBoundUniformValue(String uniformName, float defaultValue) {
  Float val = boundUniformValues.get(uniformName);
  return val != null ? val : defaultValue;
}


// ============================================
// OSC HANDLERS FOR AUDIO CONFIG
// ============================================

void handleAudioOSC(OscMessage msg) {
  String addr = msg.addrPattern();
  
  // /audio/device [index]
  if (addr.equals("/audio/device")) {
    int index = msg.get(0).intValue();
    selectAudioDevice(index);
  }
  
  // /audio/song_style [0-1]
  else if (addr.equals("/audio/song_style")) {
    songStyle = constrain(msg.get(0).floatValue(), 0, 1);
  }
  
  // /audio/kick_threshold [0-1]
  else if (addr.equals("/audio/kick_threshold")) {
    kickThreshold = constrain(msg.get(0).floatValue(), 0.1, 1);
  }
  
  // /audio/binding/clear
  else if (addr.equals("/audio/binding/clear")) {
    clearAudioBindings();
  }
  
  // /audio/binding/add [uniform, source, modType, mult, smooth, base, min, max]
  else if (addr.equals("/audio/binding/add")) {
    try {
      String uniform = msg.get(0).stringValue();
      String source = msg.get(1).stringValue();
      String modType = msg.get(2).stringValue();
      float mult = msg.get(3).floatValue();
      float smooth = msg.get(4).floatValue();
      float base = msg.get(5).floatValue();
      float minV = msg.get(6).floatValue();
      float maxV = msg.get(7).floatValue();
      addAudioBinding(uniform, source, modType, mult, smooth, base, minV, maxV);
    } catch (Exception e) {
      println("[Audio] OSC binding parse error: " + e.getMessage());
    }
  }
  
  // /audio/show_bars [0|1]
  else if (addr.equals("/audio/show_bars")) {
    showAudioBars = msg.get(0).intValue() == 1;
  }
}


// ============================================
// DEVICE SELECTION UI
// ============================================

void toggleDeviceSelection() {
  deviceSelectionActive = !deviceSelectionActive;
}

void handleDeviceSelectionKey(int keyCode, char k) {
  if (!deviceSelectionActive) return;
  
  if (keyCode == UP) {
    selectedDeviceIndex = max(0, selectedDeviceIndex - 1);
  } else if (keyCode == DOWN) {
    selectedDeviceIndex = min(audioDevices.length - 1, selectedDeviceIndex + 1);
  } else if (k == ENTER || k == RETURN) {
    selectAudioDevice(selectedDeviceIndex);
    deviceSelectionActive = false;
  } else if (k == ESC || k == 'a' || k == 'A') {
    deviceSelectionActive = false;
  }
}

void drawDeviceSelectionUI() {
  if (!deviceSelectionActive) return;
  
  // Overlay background
  fill(0, 230);
  noStroke();
  rect(0, 0, width, height);
  
  // Title
  fill(255);
  textSize(24);
  textAlign(CENTER, TOP);
  text("SELECT AUDIO DEVICE", width/2, 50);
  
  // Instructions
  fill(150);
  textSize(14);
  text("↑↓ to navigate, ENTER to select, ESC to cancel", width/2, 85);
  
  // Device list
  textSize(18);
  textAlign(LEFT, TOP);
  int y = 130;
  int itemHeight = 35;
  
  for (int i = 0; i < audioDevices.length; i++) {
    // Highlight selected
    if (i == selectedDeviceIndex) {
      fill(50, 150, 255, 100);
      rect(width/4, y - 5, width/2, itemHeight);
      fill(50, 200, 255);
    } else {
      fill(200);
    }
    
    // Current device marker
    String marker = audioDevices[i].equals(currentDeviceName) ? " ✓" : "";
    text("[" + i + "] " + audioDevices[i] + marker, width/4 + 10, y);
    y += itemHeight;
  }
  
  // Current device info
  fill(100, 255, 100);
  textSize(14);
  textAlign(CENTER, BOTTOM);
  String statusText = "Current: " + currentDeviceName;
  if (audioRetryPending) {
    statusText += " (retry " + audioRetryCount + "/" + MAX_AUDIO_RETRIES + ")";
    fill(255, 200, 100);
  } else if (!audioInitialized) {
    statusText += " (not initialized)";
    fill(255, 100, 100);
  }
  text(statusText, width/2, height - 30);
}


// ============================================
// AUDIO VISUALIZATION
// ============================================

void drawAudioBars() {
  if (!showAudioBars && !debugMode) return;
  
  // Position in top-right corner (when debug overlay is on left)
  int startX = width - 300;
  int startY = 20;
  
  // Background
  fill(0, 180);
  noStroke();
  rect(startX - 10, startY - 10, 290, barHeight + 60);
  
  // Draw bars for each audio band
  drawBar(startX, startY, "BASS", smoothAudioBass, color(255, 50, 50));
  drawBar(startX + (barWidth + barSpacing), startY, "LO-M", smoothAudioLowMid, color(255, 150, 50));
  drawBar(startX + 2*(barWidth + barSpacing), startY, "MID", smoothAudioMid, color(255, 255, 50));
  drawBar(startX + 3*(barWidth + barSpacing), startY, "HIGH", smoothAudioHighs, color(50, 255, 50));
  drawBar(startX + 4*(barWidth + barSpacing), startY, "LVL", smoothAudioLevel, color(50, 150, 255));
  drawBar(startX + 5*(barWidth + barSpacing), startY, "KICK", kickEnv, color(255, 50, 255));
  drawBar(startX + 6*(barWidth + barSpacing), startY, "E-F", energyFast, color(255, 200, 100));
  drawBar(startX + 7*(barWidth + barSpacing), startY, "E-S", energySlow, color(100, 200, 255));
  
  // Beat indicator
  int beatX = startX;
  int beatY = startY + barHeight + 20;
  fill(kickPulse == 1 ? color(255, 0, 0) : color(50));
  ellipse(beatX + 15, beatY + 10, 20, 20);
  fill(200);
  textSize(10);
  textAlign(LEFT, CENTER);
  text("BEAT:" + beat4, beatX + 35, beatY + 10);
  
  // Song style indicator
  fill(150);
  text("STYLE:" + nf(songStyle, 0, 2), beatX + 100, beatY + 10);
  
  // Bindings count
  text("BIND:" + audioBindings.size(), beatX + 180, beatY + 10);
}

void drawBar(int x, int y, String label, float value, color c) {
  // Background
  fill(40);
  rect(x, y, barWidth, barHeight);
  
  // Value bar
  float h = value * barHeight;
  fill(c);
  rect(x, y + barHeight - h, barWidth, h);
  
  // Label
  fill(200);
  textSize(9);
  textAlign(CENTER, TOP);
  text(label, x + barWidth/2, y + barHeight + 3);
  
  // Value
  textSize(8);
  text(nf(value, 0, 2), x + barWidth/2, y + barHeight + 15);
}


// ============================================
// APPLY AUDIO TO SHADER UNIFORMS
// ============================================

void applyAudioUniformsToShader(PShader s) {
  if (s == null) return;
  
  try {
    // Standard audio uniforms (always available)
    s.set("bass", smoothAudioBass);
    s.set("lowMid", smoothAudioLowMid);
    s.set("mid", smoothAudioMid);
    s.set("highs", smoothAudioHighs);
    s.set("treble", smoothAudioHighs);  // Alias
    s.set("level", smoothAudioLevel);
    s.set("kickEnv", kickEnv);
    s.set("kickPulse", (float)kickPulse);
    s.set("beat", beatPhaseAudio);
    s.set("beat4", beat4 / 3.0f);
    s.set("energyFast", energyFast);
    s.set("energySlow", energySlow);
    
    // Apply bound uniforms (from audio config)
    for (String uniform : boundUniformValues.keySet()) {
      float val = boundUniformValues.get(uniform);
      s.set(uniform, val);
    }
  } catch (Exception e) {
    // Silently ignore - shader may not use all uniforms
  }
}
