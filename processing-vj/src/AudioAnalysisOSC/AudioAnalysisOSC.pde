/**
 * AudioAnalysisOSC - Dedicated low-latency audio analyzer + OSC broadcaster
 *
 * Requirements:
 * - Processing 4.x (Intel build on Apple Silicon when using Syphon elsewhere)
 * - processing.sound library (built-in) for FFT/AudioIn
 * - oscP5 + netP5 libraries for OSC output
 *
 * Features:
 * - Enumerates all available audio input devices (AudioIn.list())
 * - Defaults to the BlackHole 2ch virtual device when available
 * - Streams FFT, multi-band energies, beat pulses, and BPM estimates to OSC
 * - Designed to feed Magic Music Visuals (default port 16666)
 * - Provides a black HUD listing current + available devices
 * - Up/Down arrows switch devices without restarting the sketch; audio stream is
 *   paused, re-configured, and resumed automatically for low latency
 */

import processing.sound.*;
import processing.data.JSONObject;
import oscP5.*;
import netP5.*;
import java.util.ArrayList;

// === Config ===
AnalyzerConfig config;
NetAddress oscTarget;
int spectrumBins = 32;

OscP5 osc;

// === Audio analysis configuration ===
final int FFT_BANDS = 512;
final int SWITCH_PAUSE_MS = 250;               // Brief pause when switching devices

// Tunable parameters (loaded from config, adjustable in HUD)
float smoothing = 0.8f;           // 0 = no smoothing, 0.9 = heavy smoothing
float noiseFloor = 0.0f;          // Start at 0; FFT values are small
float noiseFloorStep = 0.0005f;   // Step size for [7]/[8] adjustment
float beatSensitivity = 1.4f;     // Multiplier above average to trigger beat
float pulseDecay = 0.88f;         // How fast pulses fade (0.8-0.95)

// Runtime state (not persisted)
boolean showRawSpectrum = false;  // Toggle raw vs smoothed display
int detectedSampleRate = 48000;   // Default to 48kHz (BlackHole default)
boolean adaptiveThreshold = true; // Auto-tune beat sensitivity based on energy variance
float adaptedSensitivity = 1.4f;  // Current adapted beat sensitivity

AudioIn audioIn;
FFT fft;
Amplitude amplitude;
float[] fftSpectrum = new float[FFT_BANDS];
float[] smoothedSpectrum = new float[FFT_BANDS];
float[] prevSpectrum = new float[FFT_BANDS];   // For spectral flux calculation
boolean prevSpectrumInitialized = false;
float spectralFlux = 0;                         // Current onset energy
FrequencyBands freqBands;
BeatDetector beatDetector;
MultiBandBeatDetector bandDetector;
AutoBPM autoBpm;

// === Device management ===
String[] devices = new String[0];
int currentDeviceIndex = -1;
int selectedDeviceIndex = 0;  // UI selection (not yet confirmed)
int pendingDeviceIndex = -1;
boolean switchInProgress = false;
long switchStartTime = 0;
final String PREFS_FILE = "device_prefs.json";

// === Metrics ===
float subBass, bass, lowMid, mid, highMid, presence, air;
float bassHitPulse, midHitPulse, highHitPulse;
float overallLevel;
float analysisLatencyMs = 0;
float[] spectrumPayload;

// === Throttling ===
int frameCounter = 0;
int hudThrottleFrames = 2;       // Draw HUD every N frames (unused now)
int spectrumOscThrottleFrames = 3;  // Send spectrum OSC every N frames
int bpmOscThrottleFrames = 45;      // Send BPM OSC every N frames (~2/sec at 90fps)

// === UI ===
PFont hudFont;

void settings() {
  size(960, 540);
}

void setup() {
  config = loadAnalyzerConfig("audio_analysis_config.json");
  applyConfig();
  surface.setTitle(config.windowTitle);
  hudFont = createFont("IBM Plex Mono", 16, true);
  textFont(hudFont);
  osc = new OscP5(this, 0);  // no inbound port needed
  freqBands = new FrequencyBands(FFT_BANDS, detectedSampleRate);
  beatDetector = new BeatDetector();
  bandDetector = new MultiBandBeatDetector(beatSensitivity, pulseDecay);
  autoBpm = new AutoBPM();
  reloadDevices();
}

void applyConfig() {
  if (config == null) {
    config = new AnalyzerConfig();
  }
  int targetFrameRate = max(30, config.frameRate);
  frameRate(targetFrameRate);
  spectrumBins = max(4, config.spectrumBins);
  spectrumPayload = new float[spectrumBins];
  oscTarget = new NetAddress(config.oscHost, config.oscPort);
  
  // Apply tuning parameters from config
  smoothing = config.smoothing;
  noiseFloor = config.noiseFloor;
  beatSensitivity = config.beatSensitivity;
  pulseDecay = config.pulseDecay;
  detectedSampleRate = config.sampleRate;
  
  // Update components if they exist
  if (freqBands != null) freqBands.setSampleRate(detectedSampleRate);
  if (bandDetector != null) {
    bandDetector.sensitivity = beatSensitivity;
    bandDetector.decay = pulseDecay;
  }
}

void reloadConfig() {
  config = loadAnalyzerConfig("audio_analysis_config.json");
  applyConfig();
}

void draw() {
  frameCounter++;
  background(0);
  long analysisStart = System.nanoTime();

  if (switchInProgress && millis() - switchStartTime >= SWITCH_PAUSE_MS) {
    finalizeDeviceSwitch();
  }

  if (audioIn != null && !switchInProgress) {
    analyzeAudio();
    sendOsc();
  } else {
    overallLevel = 0;
  }

  analysisLatencyMs = (System.nanoTime() - analysisStart) / 1_000_000.0f;
  
  // Draw HUD every frame (no throttling - was causing flicker)
  drawHud();
}

// === Audio device management ===

void reloadDevices() {
  String[] listed = Sound.list();
  if (listed == null || listed.length == 0) {
    devices = new String[] { "Default Input" };
  } else {
    devices = listed;
  }

  // Try to restore saved device, else use default
  int savedIdx = loadSavedDeviceIndex();
  int defaultIdx = findDefaultDevice();
  int idx = savedIdx >= 0 ? savedIdx : (defaultIdx >= 0 ? defaultIdx : 0);
  selectedDeviceIndex = idx;
  activateDevice(idx);
}

int findDefaultDevice() {
  for (int i = 0; i < devices.length; i++) {
    if (devices[i] != null && devices[i].toLowerCase().contains("blackhole 2ch")) {
      return i;
    }
  }
  return -1;
}

void moveSelection(int delta) {
  if (devices.length == 0) return;
  selectedDeviceIndex = (selectedDeviceIndex + delta + devices.length) % devices.length;
}

void activateDevice(int index) {
  if (devices.length == 0) return;
  index = constrain(index, 0, devices.length - 1);
  if (index == currentDeviceIndex && audioIn != null) return;
  pendingDeviceIndex = index;
  saveDevicePreference(devices[index]);
  beginDeviceSwitch();
}

void saveDevicePreference(String deviceName) {
  JSONObject prefs = new JSONObject();
  prefs.setString("device_name", deviceName);
  saveJSONObject(prefs, "data/" + PREFS_FILE);
}

int loadSavedDeviceIndex() {
  try {
    JSONObject prefs = loadJSONObject(PREFS_FILE);
    if (prefs != null && prefs.hasKey("device_name")) {
      String savedName = prefs.getString("device_name");
      for (int i = 0; i < devices.length; i++) {
        if (devices[i] != null && devices[i].equals(savedName)) {
          return i;
        }
      }
    }
  } catch (Exception e) {
    // No saved prefs or error loading
  }
  return -1;
}

void beginDeviceSwitch() {
  switchInProgress = true;
  switchStartTime = millis();
  teardownAudio();
}

void finalizeDeviceSwitch() {
  switchInProgress = false;
  currentDeviceIndex = pendingDeviceIndex;
  initAudio();
}

void teardownAudio() {
  if (audioIn != null) {
    try {
      audioIn.stop();
    } catch (Exception ignored) {}
    audioIn = null;
  }
  fft = null;
  amplitude = null;
}

void initAudio() {
  if (devices.length == 0) return;
  try {
    // Configure input device globally before creating AudioIn
    Sound s = new Sound(this);
    s.inputDevice(currentDeviceIndex);
    
    // Try to detect sample rate from Sound object
    // Processing Sound library uses 44100 by default, but we can check
    // Note: Processing Sound doesn't expose sample rate directly,
    // so we use the config value or default 44100
    if (config != null && config.sampleRate > 0) {
      detectedSampleRate = config.sampleRate;
    }
    if (freqBands != null) freqBands.setSampleRate(detectedSampleRate);
    
    audioIn = new AudioIn(this);
    audioIn.start();
    fft = new FFT(this, FFT_BANDS);
    fft.input(audioIn);
    amplitude = new Amplitude(this);
    amplitude.input(audioIn);
    
    // Reset spectral flux state on device change
    prevSpectrumInitialized = false;
    java.util.Arrays.fill(prevSpectrum, 0);
  } catch (Exception e) {
    println("Failed to init audio input: " + e.getMessage());
    audioIn = null;
  }
}

// === Audio analysis ===

void analyzeAudio() {
  if (fft == null || amplitude == null) return;
  fft.analyze(fftSpectrum);
  
  // Apply noise floor and smoothing (fixed: smoothed = old*S + new*(1-S))
  for (int i = 0; i < FFT_BANDS; i++) {
    float raw = max(fftSpectrum[i] - noiseFloor, 0);
    smoothedSpectrum[i] = lerp(raw, smoothedSpectrum[i], smoothing);
  }
  
  // Compute spectral flux (positive changes only) for beat detection
  spectralFlux = 0;
  if (prevSpectrumInitialized) {
    for (int i = 0; i < FFT_BANDS; i++) {
      float diff = smoothedSpectrum[i] - prevSpectrum[i];
      if (diff > 0) spectralFlux += diff;
    }
  } else {
    prevSpectrumInitialized = true;
  }
  arrayCopy(smoothedSpectrum, prevSpectrum);

  freqBands.update(smoothedSpectrum);
  subBass = freqBands.getSubBass();
  bass = freqBands.getBass();
  lowMid = freqBands.getLowMid();
  mid = freqBands.getMidrange();
  highMid = freqBands.getHighMid();
  presence = freqBands.getPresence();
  air = freqBands.getAir();

  // Beat detector now uses spectral flux (onset energy) instead of raw spectrum
  beatDetector.update(spectralFlux);
  
  // Multi-band beat detection with better frequency separation:
  // - Bass: subBass + bass (20-250Hz) - kick drums, bass synths
  // - Mid: lowMid + mid (250-2000Hz) - snares, vocals, most instruments  
  // - High: highMid + presence + air (2000-20000Hz) - hi-hats, cymbals, sibilance
  // Note: No scaling here - the adaptive threshold in MultiBandBeatDetector
  // normalizes each band independently, so scaling would cancel out
  float bassForBeat = subBass + bass;
  float midForBeat = lowMid + mid;
  float highForBeat = highMid + presence + air;
  bandDetector.update(bassForBeat, midForBeat, highForBeat);
  
  if (beatDetector.isBeat()) {
    autoBpm.recordBeat();
  }

  bassHitPulse = bandDetector.getBassPulse();
  midHitPulse = bandDetector.getMidPulse();
  highHitPulse = bandDetector.getHighPulse();
  overallLevel = amplitude.analyze();
  downsampleSpectrum();
  
  // Debug: print values every 30 frames to verify real numbers
  if (frameCounter % 30 == 0) {
    println("Bands:",
      "sub", nf(subBass, 0, 4),
      "bass", nf(bass, 0, 4),
      "mid", nf(mid, 0, 4),
      "high", nf(highMid, 0, 4),
      "overall", nf(overallLevel, 0, 4),
      "flux", nf(spectralFlux, 0, 4));
  }
}

void downsampleSpectrum() {
  int binsPerGroup = max(1, FFT_BANDS / spectrumBins);
  float[] sourceSpectrum = showRawSpectrum ? fftSpectrum : smoothedSpectrum;
  
  for (int i = 0; i < spectrumBins; i++) {
    float sum = 0;
    for (int j = 0; j < binsPerGroup; j++) {
      int idx = i * binsPerGroup + j;
      if (idx < FFT_BANDS) sum += sourceSpectrum[idx];
    }
    float avg = sum / binsPerGroup;
    
    // Apply frequency compensation: boost higher frequencies progressively
    // to counteract natural bass dominance in music
    float weight = 1.0f + (float)i / spectrumBins * 0.5f;
    spectrumPayload[i] = avg * weight;
  }
}

// === OSC ===

void sendOsc() {
  // Levels and beats are sent every frame for responsiveness
  OscMessage levels = new OscMessage("/audio/levels");
  levels.add(subBass);
  levels.add(bass);
  levels.add(lowMid);
  levels.add(mid);
  levels.add(highMid);
  levels.add(presence);
  levels.add(air);
  levels.add(overallLevel);
  sendToTarget(levels);

  OscMessage beats = new OscMessage("/audio/beats");
  beats.add(beatDetector.isBeat() ? 1 : 0);
  beats.add(beatDetector.getPulse());
  beats.add(bassHitPulse);
  beats.add(midHitPulse);
  beats.add(highHitPulse);
  sendToTarget(beats);

  // BPM is throttled - only changes slowly, no need every frame
  if (frameCounter % bpmOscThrottleFrames == 0) {
    OscMessage bpmMsg = new OscMessage("/audio/bpm");
    bpmMsg.add(autoBpm.getBpm());
    bpmMsg.add(autoBpm.getConfidence());
    sendToTarget(bpmMsg);
  }

  // Spectrum is throttled - sent every N frames to reduce network load
  if (frameCounter % spectrumOscThrottleFrames == 0) {
    OscMessage spectrum = new OscMessage("/audio/spectrum");
    for (int i = 0; i < spectrumBins; i++) {
      spectrum.add(spectrumPayload[i]);
    }
    sendToTarget(spectrum);
  }
}

void sendToTarget(OscMessage msg) {
  if (oscTarget != null) {
    osc.send(msg, oscTarget);
  }
}

String oscSummary() {
  if (oscTarget == null) {
    return "(no target)";
  }
  return oscTarget.address() + ":" + oscTarget.port();
}

// === HUD ===

void drawHud() {
  fill(255);
  textAlign(LEFT, TOP);
  float y = 16;
  
  // === Header row ===
  text("AudioAnalysisOSC", 24, y);
  fill(120);
  text("OSC → " + oscSummary(), 200, y);
  y += 22;
  
  // === Current device ===
  String deviceName = (currentDeviceIndex >= 0 && currentDeviceIndex < devices.length)
    ? devices[currentDeviceIndex]
    : "(no device)";
  if (switchInProgress) {
    fill(200, 200, 0);
    deviceName = "Switching → " + devices[pendingDeviceIndex];
  } else {
    fill(0, 200, 0);
  }
  text("Input: " + deviceName, 24, y);
  y += 20;
  
  // === Stats row ===
  fill(180);
  String bpmStr = autoBpm.getBpm() > 0 ? String.format("%.1f", autoBpm.getBpm()) : "---";
  text(String.format("Level: %.3f  |  BPM: %s  |  %.1f ms  |  %d Hz  |  HUD:%d Spec:%d", 
    overallLevel, bpmStr, analysisLatencyMs, detectedSampleRate, 
    hudThrottleFrames, spectrumOscThrottleFrames), 24, y);
  y += 26;
  
  // === Tuning panel (prominent, always visible) ===
  fill(20);
  stroke(60);
  rect(20, y - 4, 500, 88, 4);
  noStroke();
  
  y += 4;
  fill(255, 220, 100);
  text("TUNING (auto-saves)", 28, y);
  y += 20;
  
  // Row 1
  fill(showRawSpectrum ? color(255, 200, 100) : 140);
  text("[W] Raw: " + (showRawSpectrum ? "ON" : "off"), 28, y);
  fill(180);
  text(String.format("[1/2] Smooth: %.2f", smoothing), 150, y);
  text(String.format("[3/4] Sens: %.1f", beatSensitivity), 300, y);
  y += 18;
  
  // Row 2
  fill(180);
  text(String.format("[5/6] Decay: %.2f", pulseDecay), 28, y);
  fill(adaptiveThreshold ? color(100, 255, 150) : 140);
  text("[A] Adaptive: " + (adaptiveThreshold ? String.format("ON (%.2f)", adaptedSensitivity) : "off"), 180, y);
  y += 18;
  
  // Row 3
  fill(180);
  text(String.format("[7/8] NoiseFloor: %.5f", noiseFloor), 28, y);
  fill(120);
  text("[C] Reload   [R] Rescan", 250, y);
  y += 30;
  
  // === Device list (compact, scrollable view showing max 5) ===
  fill(100);
  text("Devices [↑/↓ Enter]:", 24, y);
  y += 16;
  
  // Show only nearby devices (selected ± 2)
  int maxVisible = 5;
  int startIdx = max(0, selectedDeviceIndex - 2);
  int endIdx = min(devices.length, startIdx + maxVisible);
  if (endIdx - startIdx < maxVisible && startIdx > 0) {
    startIdx = max(0, endIdx - maxVisible);
  }
  
  for (int i = startIdx; i < endIdx; i++) {
    String prefix = "  ";
    if (i == currentDeviceIndex && !switchInProgress) {
      fill(0, 200, 0);
      prefix = "> ";
    } else if (switchInProgress && i == pendingDeviceIndex) {
      fill(200, 200, 0);
      prefix = "* ";
    } else if (i == selectedDeviceIndex) {
      fill(100, 150, 255);
      prefix = "[ ";
    } else {
      fill(120);
    }
    // Truncate long device names
    String dname = devices[i];
    if (dname.length() > 35) dname = dname.substring(0, 32) + "...";
    text(prefix + dname, 24, y);
    y += 16;
  }
  
  // Show scroll indicator if more devices
  if (devices.length > maxVisible) {
    fill(80);
    text(String.format("(%d/%d devices)", selectedDeviceIndex + 1, devices.length), 24, y);
  }
  
  // === Audio level visualization (right side) ===
  drawLevelBars(width - 200, 24);
  
  // === Spectrum visualizer (bottom) ===
  drawSpectrumBars(24, height - 120, width - 48, 100);
  
  // === Beat/BPM panel (middle right) ===
  drawBeatPanel(width - 200, 180);
}

void drawSpectrumBars(float x, float y, float w, float h) {
  // Background panel
  fill(20);
  stroke(60);
  rect(x - 4, y - 4, w + 8, h + 8, 4);
  
  noStroke();
  int numBars = 48;  // More bars for better resolution
  float barW = w / numBars;
  float nyquist = detectedSampleRate / 2.0f;
  
  // Use logarithmic frequency mapping for better distribution
  for (int i = 0; i < numBars; i++) {
    // Log scale: map bar index to FFT bin with logarithmic distribution
    float logMin = log(1);
    float logMax = log(FFT_BANDS);
    float logVal = map(i, 0, numBars, logMin, logMax);
    int binIdx = constrain(int(exp(logVal)), 0, FFT_BANDS - 1);
    
    // Calculate the frequency this bin represents
    float freq = (float)binIdx / FFT_BANDS * nyquist;
    
    // Get value from smoothed spectrum
    float val = smoothedSpectrum[binIdx];
    
    // Apply A-weighting inspired boost curve based on frequency
    // This compensates for both:
    // 1. Natural bass dominance in music
    // 2. Human ear sensitivity (Fletcher-Munson curves)
    float boost = getAWeightingBoost(freq);
    val = constrain(val * boost, 0, 1);
    float barH = val * h;
    
    // Color gradient from red (low) to blue (high)
    float hue = map(i, 0, numBars, 0, 0.7);  // red to blue
    colorMode(HSB, 1);
    fill(hue, 0.8, 0.9);
    colorMode(RGB, 255);
    
    rect(x + i * barW, y + h - barH, barW - 1, barH);
  }
  
  // Frequency labels
  fill(100);
  textAlign(LEFT, TOP);
  textSize(10);
  text("Bass", x, y + h + 2);
  textAlign(CENTER, TOP);
  text("Mid", x + w/2, y + h + 2);
  textAlign(RIGHT, TOP);
  text("High", x + w, y + h + 2);
  textSize(16);
  
  // Label
  fill(150);
  textAlign(LEFT, BOTTOM);
  text("Spectrum (A-weighted)", x, y - 6);
  textAlign(LEFT, TOP);
}

// Inverse A-weighting: bass loud in music, boost progressively toward highs
// No boost on bass, exponential increase toward air frequencies
float getAWeightingBoost(float freq) {
  if (freq < 60) {
    return 1;          // Sub-bass: no boost
  } else if (freq < 250) {
    return 1;          // Bass: no boost - kicks are loud
  } else if (freq < 500) {
    return 2;          // Low-mid: slight
  } else if (freq < 1000) {
    return 4;          // Mid: moderate
  } else if (freq < 2000) {
    return 6;          // Upper-mid: more
  } else if (freq < 4000) {
    return 10;         // High-mid: significant
  } else if (freq < 8000) {
    return 20;         // Presence: large
  } else {
    return 40;         // Air: massive boost for quiet content
  }
}

void drawBeatPanel(float x, float y) {
  // Background panel
  fill(20);
  stroke(60);
  rect(x - 4, y - 4, 180, 140, 4);
  noStroke();
  
  float panelX = x;
  float py = y;
  
  // Title
  fill(200);
  text("Beat Detection", panelX, py);
  py += 22;
  
  // BPM display (large)
  fill(255, 220, 100);
  textSize(28);
  float currentBpm = autoBpm.getBpm();
  if (currentBpm > 0) {
    text(String.format("%.0f", currentBpm), panelX, py);
  } else {
    fill(100);
    text("---", panelX, py);
  }
  textSize(16);
  fill(150);
  text(" BPM", panelX + 50, py + 8);
  py += 36;
  
  // Confidence bar
  fill(100);
  text("Confidence", panelX, py);
  py += 18;
  fill(40);
  rect(panelX, py, 160, 10);
  float conf = autoBpm.getConfidence();
  fill(100, 255, 150);
  rect(panelX, py, 160 * conf, 10);
  py += 20;
  
  // Beat indicators
  fill(100);
  text("Pulses", panelX, py);
  py += 20;
  
  // Bass pulse circle
  float circleSize = 30;
  float cx = panelX + 25;
  fill(40);
  ellipse(cx, py + 15, circleSize, circleSize);
  if (bassHitPulse > 0.05) {
    fill(255, 100, 50, 100 + bassHitPulse * 155);
    ellipse(cx, py + 15, circleSize * (0.5 + bassHitPulse * 0.5), circleSize * (0.5 + bassHitPulse * 0.5));
  }
  fill(180);
  textAlign(CENTER, TOP);
  text("Bass", cx, py + 32);
  
  // Mid pulse circle
  cx += 55;
  fill(40);
  ellipse(cx, py + 15, circleSize, circleSize);
  if (midHitPulse > 0.05) {
    fill(100, 255, 100, 100 + midHitPulse * 155);
    ellipse(cx, py + 15, circleSize * (0.5 + midHitPulse * 0.5), circleSize * (0.5 + midHitPulse * 0.5));
  }
  fill(180);
  text("Mid", cx, py + 32);
  
  // High pulse circle
  cx += 55;
  fill(40);
  ellipse(cx, py + 15, circleSize, circleSize);
  if (highHitPulse > 0.05) {
    fill(150, 100, 255, 100 + highHitPulse * 155);
    ellipse(cx, py + 15, circleSize * (0.5 + highHitPulse * 0.5), circleSize * (0.5 + highHitPulse * 0.5));
  }
  fill(180);
  text("High", cx, py + 32);
  
  textAlign(LEFT, TOP);
  textFont(hudFont);  // reset font size
}

void drawLevelBars(float x, float y) {
  float barWidth = 80;
  float barHeight = 12;
  float spacing = 4;
  
  String[] labels = {"SubBass", "Bass", "LowMid", "Mid", "HighMid", "Presence", "Air", "Overall"};
  float[] values = {subBass, bass, lowMid, mid, highMid, presence, air, overallLevel};
  
  // Re-tuned for sum-based band values (not averaged)
  // These are much smaller multipliers since sums are larger than averages
  float[] scales = {
    0.8f,   // SubBass: now using sum, scale down
    0.3f,   // Bass: slight - already strong in most music
    0.5f,   // LowMid: moderate
    0.8f,   // Mid: snares/vocals
    1.2f,   // HighMid: cymbals need visibility
    1.5f,   // Presence: more boost for detail
    2.0f,   // Air: boost - very quiet in most sources
    3.0f    // Overall: uses amplitude.analyze() (unchanged)
  };
  color[] colors = {
    color(255, 50, 50),    // SubBass - red
    color(255, 100, 50),   // Bass - orange
    color(255, 200, 50),   // LowMid - yellow
    color(100, 255, 100),  // Mid - green
    color(50, 200, 255),   // HighMid - cyan
    color(100, 100, 255),  // Presence - blue
    color(200, 100, 255),  // Air - purple
    color(255, 255, 255)   // Overall - white
  };
  
  textAlign(RIGHT, TOP);
  for (int i = 0; i < labels.length; i++) {
    float ly = y + i * (barHeight + spacing);
    
    // Label
    fill(180);
    text(labels[i], x + 60, ly);
    
    // Background bar
    fill(40);
    noStroke();
    rect(x + 65, ly, barWidth, barHeight);
    
    // Level bar with per-band scaling for visibility
    float level = constrain(values[i] * scales[i], 0, 1);
    if (level > 0.01) {
      fill(colors[i]);
      rect(x + 65, ly, barWidth * level, barHeight);
    }
    
    // Beat pulse indicator for bass/mid/high
    if (i == 1 && bassHitPulse > 0.1) {
      fill(255, 100, 50, bassHitPulse * 255);
      ellipse(x + 65 + barWidth + 15, ly + barHeight/2, 10, 10);
    } else if (i == 3 && midHitPulse > 0.1) {
      fill(100, 255, 100, midHitPulse * 255);
      ellipse(x + 65 + barWidth + 15, ly + barHeight/2, 10, 10);
    } else if (i == 5 && highHitPulse > 0.1) {
      fill(100, 100, 255, highHitPulse * 255);
      ellipse(x + 65 + barWidth + 15, ly + barHeight/2, 10, 10);
    }
  }
  textAlign(LEFT, TOP);  // reset
}

// === Input handling ===

void keyPressed() {
  if (keyCode == UP) {
    moveSelection(-1);
  } else if (keyCode == DOWN) {
    moveSelection(1);
  } else if (keyCode == ENTER || keyCode == RETURN) {
    activateDevice(selectedDeviceIndex);
  } else if (key == 'r' || key == 'R') {
    reloadDevices();
  } else if (key == 'c' || key == 'C') {
    reloadConfig();
  } else if (key == 'w' || key == 'W') {
    // Toggle raw spectrum view (not saved - runtime only)
    showRawSpectrum = !showRawSpectrum;
  } else if (key == 'a' || key == 'A') {
    // Toggle adaptive threshold (not saved - runtime only)
    adaptiveThreshold = !adaptiveThreshold;
  } else if (key == '1') {
    // Decrease smoothing
    smoothing = constrain(smoothing - 0.05f, 0, 0.95f);
    saveCurrentConfig();
  } else if (key == '2') {
    // Increase smoothing
    smoothing = constrain(smoothing + 0.05f, 0, 0.95f);
    saveCurrentConfig();
  } else if (key == '3') {
    // Decrease beat sensitivity
    beatSensitivity = constrain(beatSensitivity - 0.1f, 1.0f, 3.0f);
    if (bandDetector != null) bandDetector.sensitivity = beatSensitivity;
    saveCurrentConfig();
  } else if (key == '4') {
    // Increase beat sensitivity
    beatSensitivity = constrain(beatSensitivity + 0.1f, 1.0f, 3.0f);
    if (bandDetector != null) bandDetector.sensitivity = beatSensitivity;
    saveCurrentConfig();
  } else if (key == '5') {
    // Decrease pulse decay (faster fade)
    pulseDecay = constrain(pulseDecay - 0.02f, 0.7f, 0.95f);
    if (bandDetector != null) bandDetector.decay = pulseDecay;
    saveCurrentConfig();
  } else if (key == '6') {
    // Increase pulse decay (slower fade)
    pulseDecay = constrain(pulseDecay + 0.02f, 0.7f, 0.95f);
    if (bandDetector != null) bandDetector.decay = pulseDecay;
    saveCurrentConfig();
  } else if (key == '7') {
    // Decrease noise floor
    noiseFloor = max(0, noiseFloor - noiseFloorStep);
    saveCurrentConfig();
  } else if (key == '8') {
    // Increase noise floor
    noiseFloor += noiseFloorStep;
    saveCurrentConfig();
  }
}

void saveCurrentConfig() {
  config.smoothing = smoothing;
  config.noiseFloor = noiseFloor;
  config.beatSensitivity = beatSensitivity;
  config.pulseDecay = pulseDecay;
  config.sampleRate = detectedSampleRate;
  
  JSONObject json = new JSONObject();
  json.setString("window_title", config.windowTitle);
  json.setString("osc_host", config.oscHost);
  json.setInt("osc_port", config.oscPort);
  json.setInt("spectrum_bins", config.spectrumBins);
  json.setInt("frame_rate", config.frameRate);
  json.setFloat("smoothing", config.smoothing);
  json.setFloat("noise_floor", config.noiseFloor);
  json.setFloat("beat_sensitivity", config.beatSensitivity);
  json.setFloat("pulse_decay", config.pulseDecay);
  json.setInt("sample_rate", config.sampleRate);
  
  saveJSONObject(json, "data/audio_analysis_config.json");
  println("Config saved!");
}

// === Helper classes ===

class FrequencyBands {
  int fftSize;
  int sampleRate = 44100;
  float[] spectrumRef;

  FrequencyBands(int fftSize, int sampleRate) {
    this.fftSize = fftSize;
    this.sampleRate = sampleRate;
  }
  
  void setSampleRate(int sr) {
    this.sampleRate = sr;
  }

  void update(float[] spectrum) {
    spectrumRef = spectrum;
  }

  float range(float minHz, float maxHz) {
    if (spectrumRef == null) return 0;
    int start = freqToBin(minHz);
    int end = freqToBin(maxHz);
    start = constrain(start, 0, fftSize - 1);
    end = constrain(end, start + 1, fftSize);
    float sum = 0;
    for (int i = start; i < end; i++) {
      sum += spectrumRef[i];
    }
    return sum;  // Use sum, not average - better dynamics
  }

  // FIXED: Map against Nyquist frequency (sampleRate/2), not full sampleRate
  // FFT bins cover 0 to Nyquist, so freq 20kHz at 44.1kHz = bin near end
  int freqToBin(float freq) {
    float nyquist = sampleRate / 2.0f;
    float norm = freq / nyquist;  // 0..1 range
    return int(constrain(norm * (fftSize - 1), 0, fftSize - 1));
  }

  float getSubBass() { return range(20, 60); }
  float getBass() { return range(60, 250); }
  float getLowMid() { return range(250, 500); }
  float getMidrange() { return range(500, 2000); }
  float getHighMid() { return range(2000, 4000); }
  float getPresence() { return range(4000, 6000); }
  float getAir() { return range(6000, 20000); }
}

class BeatDetector {
  float[] history;
  int size = 43;          // ~0.7s at 60fps
  int index = 0;
  float thresholdFactor = 1.4f;
  boolean beat;
  float pulse;

  BeatDetector() {
    history = new float[size];
  }

  // Now takes scalar onset energy (spectral flux) instead of spectrum array
  void update(float onsetEnergy) {
    float avg = 0;
    for (float h : history) avg += h;
    avg /= size;
    
    // Beat when onset energy exceeds average by threshold factor
    beat = onsetEnergy > avg * thresholdFactor && onsetEnergy > 0.001f;
    
    history[index] = onsetEnergy;
    index = (index + 1) % size;
    
    if (beat) pulse = 1;
    pulse *= 0.92f;
  }

  boolean isBeat() { return beat; }
  float getPulse() { return pulse; }
}

class MultiBandBeatDetector {
  float bassPulse, midPulse, highPulse;
  float decay = 0.88f;
  float sensitivity = 1.4f;
  
  // Running averages for adaptive thresholds (more efficient than arrays)
  float bassAvg = 0, midAvg = 0, highAvg = 0;
  float alpha = 0.05f;  // Running average smoothing
  
  // Adaptive threshold: variance tracking for auto-sensitivity
  float energyVariance = 0;
  float energyMean = 0;
  float varianceAlpha = 0.02f;  // Slow adaptation for variance
  
  MultiBandBeatDetector(float sensitivity, float decay) {
    this.sensitivity = sensitivity;
    this.decay = decay;
  }

  void update(float bassEnergy, float midEnergy, float highEnergy) {
    // Update running averages (exponential moving average)
    bassAvg = lerp(bassEnergy, bassAvg, 1 - alpha);
    midAvg = lerp(midEnergy, midAvg, 1 - alpha);
    highAvg = lerp(highEnergy, highAvg, 1 - alpha);
    
    // Track total energy for adaptive threshold
    float totalEnergy = bassEnergy + midEnergy + highEnergy;
    float oldMean = energyMean;
    energyMean = lerp(totalEnergy, energyMean, 1 - varianceAlpha);
    float diff = totalEnergy - energyMean;
    energyVariance = lerp(diff * diff, energyVariance, 1 - varianceAlpha);
    
    // Adaptive sensitivity: adjust based on signal variance
    // High variance (dynamic music) = use base sensitivity
    // Low variance (quiet/steady) = increase sensitivity to catch subtle beats
    float effectiveSensitivity = sensitivity;
    if (adaptiveThreshold) {
      float stdDev = sqrt(max(energyVariance, 0.0001f));
      float varianceRatio = stdDev / max(energyMean, 0.0001f);  // Coefficient of variation
      // When variance is low (<0.3), boost sensitivity; when high (>0.6), reduce slightly
      float sensMultiplier = map(constrain(varianceRatio, 0.1f, 0.8f), 0.1f, 0.8f, 1.3f, 0.9f);
      effectiveSensitivity = sensitivity * sensMultiplier;
      adaptedSensitivity = effectiveSensitivity;  // Expose for HUD display
    }
    
    // Adaptive thresholds based on running average
    float bassThr = bassAvg * effectiveSensitivity;
    float midThr = midAvg * effectiveSensitivity;
    float highThr = highAvg * effectiveSensitivity;
    
    // Detect beats when current > adaptive threshold
    // No fixed minimums - let the adaptive threshold handle quiet passages
    boolean bassBeat = bassEnergy > bassThr && bassAvg > 0.0001f;
    boolean midBeat = midEnergy > midThr && midAvg > 0.0001f;
    boolean highBeat = highEnergy > highThr && highAvg > 0.0001f;
    
    // Update pulses
    if (bassBeat) bassPulse = 1.0f;
    else bassPulse *= decay;
    
    if (midBeat) midPulse = 1.0f;
    else midPulse *= decay;
    
    if (highBeat) highPulse = 1.0f;
    else highPulse *= decay;
  }
  
  float getEnergyVariance() { return energyVariance; }
  float getEnergyMean() { return energyMean; }

  float getBassPulse() { return bassPulse; }
  float getMidPulse() { return midPulse; }
  float getHighPulse() { return highPulse; }
}

class AutoBPM {
  ArrayList<Long> beatTimes = new ArrayList<Long>();
  float bpm = 0;  // Start at 0 (unknown)
  float confidence = 0;
  long lastBeatTime = 0;
  int minIntervalMs = 250;   // Max 240 BPM
  int maxIntervalMs = 2000;  // Min 30 BPM (extended range)

  void recordBeat() {
    long now = millis();
    
    // Debounce: ignore beats too close together
    if (now - lastBeatTime < minIntervalMs) {
      return;
    }
    
    // Also filter out obviously bogus intervals (too long)
    if (lastBeatTime > 0 && now - lastBeatTime > maxIntervalMs) {
      // Gap too large - don't use for BPM but update lastBeatTime
      lastBeatTime = now;
      return;
    }
    lastBeatTime = now;
    
    beatTimes.add(now);
    
    // Keep only recent beats (last 8 seconds)
    while (beatTimes.size() > 0 && now - beatTimes.get(0) > 8000) {
      beatTimes.remove(0);
    }
    
    // Limit size to 12 for tighter average
    if (beatTimes.size() > 12) {
      beatTimes.remove(0);
    }
    
    // Need at least 4 beats for BPM calculation
    if (beatTimes.size() >= 4) {
      float avgInterval = medianInterval();
      if (avgInterval >= minIntervalMs && avgInterval <= maxIntervalMs) {
        float newBpm = constrain(60000.0f / avgInterval, 60, 200);
        // Increased smoothing for stability (0.6 keeps more of old value)
        if (bpm == 0) {
          bpm = newBpm;
        } else {
          bpm = lerp(newBpm, bpm, 0.6f);
        }
        confidence = calcConfidence();
      }
    }
  }

  float medianInterval() {
    if (beatTimes.size() < 2) return 0;
    ArrayList<Long> intervals = new ArrayList<Long>();
    for (int i = 1; i < beatTimes.size(); i++) {
      long interval = beatTimes.get(i) - beatTimes.get(i - 1);
      if (interval >= minIntervalMs && interval <= maxIntervalMs) {
        intervals.add(interval);
      }
    }
    if (intervals.size() == 0) return 0;
    java.util.Collections.sort(intervals);
    return intervals.get(intervals.size() / 2);
  }
  
  float calcConfidence() {
    if (beatTimes.size() < 4) return 0;
    // Confidence based on consistency of intervals
    float median = medianInterval();
    if (median == 0) return 0;
    
    int consistent = 0;
    for (int i = 1; i < beatTimes.size(); i++) {
      long interval = beatTimes.get(i) - beatTimes.get(i - 1);
      if (abs(interval - median) < median * 0.15) {  // Within 15% of median
        consistent++;
      }
    }
    return constrain((float)consistent / (beatTimes.size() - 1), 0, 1);
  }
  
  void reset() {
    beatTimes.clear();
    bpm = 0;
    confidence = 0;
    lastBeatTime = 0;
  }

  float getBpm() { return bpm; }
  float getConfidence() { return confidence; }
}

class AnalyzerConfig {
  String windowTitle = "AudioAnalysisOSC";
  String oscHost = "127.0.0.1";
  int oscPort = 16666;
  int spectrumBins = 32;
  int frameRate = 90;
  
  // Tuning parameters (can be adjusted in HUD and saved)
  float smoothing = 0.8f;
  float noiseFloor = 0.0f;
  float beatSensitivity = 1.4f;
  float pulseDecay = 0.88f;
  int sampleRate = 48000;  // Default to 48kHz (BlackHole default)
}

AnalyzerConfig loadAnalyzerConfig(String fileName) {
  AnalyzerConfig cfg = new AnalyzerConfig();
  try {
    JSONObject json = loadJSONObject(fileName);
    if (json == null) return cfg;

    if (json.hasKey("window_title")) {
      cfg.windowTitle = json.getString("window_title");
    }
    if (json.hasKey("osc_host")) {
      cfg.oscHost = json.getString("osc_host");
    }
    if (json.hasKey("osc_port")) {
      cfg.oscPort = json.getInt("osc_port");
    }
    if (json.hasKey("spectrum_bins")) {
      cfg.spectrumBins = max(4, json.getInt("spectrum_bins"));
    }
    if (json.hasKey("frame_rate")) {
      cfg.frameRate = max(30, json.getInt("frame_rate"));
    }
    // Tuning parameters
    if (json.hasKey("smoothing")) {
      cfg.smoothing = constrain(json.getFloat("smoothing"), 0, 0.95f);
    }
    if (json.hasKey("noise_floor")) {
      cfg.noiseFloor = max(0, json.getFloat("noise_floor"));
    }
    if (json.hasKey("beat_sensitivity")) {
      cfg.beatSensitivity = constrain(json.getFloat("beat_sensitivity"), 1.0f, 3.0f);
    }
    if (json.hasKey("pulse_decay")) {
      cfg.pulseDecay = constrain(json.getFloat("pulse_decay"), 0.7f, 0.95f);
    }
    if (json.hasKey("sample_rate")) {
      cfg.sampleRate = max(22050, json.getInt("sample_rate"));
    }
  } catch (Exception e) {
    println("Config load error (" + fileName + "): " + e.getMessage());
  }
  return cfg;
}
