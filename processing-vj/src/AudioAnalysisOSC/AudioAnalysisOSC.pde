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
final float SMOOTHING = 0.35f;
final float NOISE_FLOOR = 0.0005f;             // Ignore extremely low values
final int SWITCH_PAUSE_MS = 250;               // Brief pause when switching devices

AudioIn audioIn;
FFT fft;
Amplitude amplitude;
float[] fftSpectrum = new float[FFT_BANDS];
float[] smoothedSpectrum = new float[FFT_BANDS];
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
  freqBands = new FrequencyBands(FFT_BANDS);
  beatDetector = new BeatDetector(FFT_BANDS);
  bandDetector = new MultiBandBeatDetector();
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
}

void reloadConfig() {
  config = loadAnalyzerConfig("audio_analysis_config.json");
  applyConfig();
}

void draw() {
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
    
    audioIn = new AudioIn(this);
    audioIn.start();
    fft = new FFT(this, FFT_BANDS);
    fft.input(audioIn);
    amplitude = new Amplitude(this);
    amplitude.input(audioIn);
  } catch (Exception e) {
    println("Failed to init audio input: " + e.getMessage());
    audioIn = null;
  }
}

// === Audio analysis ===

void analyzeAudio() {
  if (fft == null || amplitude == null) return;
  fft.analyze(fftSpectrum);
  for (int i = 0; i < FFT_BANDS; i++) {
    float raw = max(fftSpectrum[i] - NOISE_FLOOR, 0);
    smoothedSpectrum[i] = lerp(smoothedSpectrum[i], raw, 1.0f - SMOOTHING);
  }

  freqBands.update(smoothedSpectrum);
  subBass = freqBands.getSubBass();
  bass = freqBands.getBass();
  lowMid = freqBands.getLowMid();
  mid = freqBands.getMidrange();
  highMid = freqBands.getHighMid();
  presence = freqBands.getPresence();
  air = freqBands.getAir();

  beatDetector.update(smoothedSpectrum);
  bandDetector.update(bass, mid, presence);
  if (beatDetector.isBeat()) {
    autoBpm.recordBeat();
  }

  bassHitPulse = bandDetector.getBassPulse();
  midHitPulse = bandDetector.getMidPulse();
  highHitPulse = bandDetector.getHighPulse();
  overallLevel = amplitude.analyze();
  downsampleSpectrum();
}

void downsampleSpectrum() {
  int binsPerGroup = max(1, FFT_BANDS / spectrumBins);
  for (int i = 0; i < spectrumBins; i++) {
    float sum = 0;
    for (int j = 0; j < binsPerGroup; j++) {
      int idx = i * binsPerGroup + j;
      sum += smoothedSpectrum[idx];
    }
    spectrumPayload[i] = sum / binsPerGroup;
  }
}

// === OSC ===

void sendOsc() {
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

  OscMessage bpmMsg = new OscMessage("/audio/bpm");
  bpmMsg.add(autoBpm.getBpm());
  bpmMsg.add(autoBpm.getConfidence());
  sendToTarget(bpmMsg);

  OscMessage spectrum = new OscMessage("/audio/spectrum");
  for (int i = 0; i < spectrumBins; i++) {
    spectrum.add(spectrumPayload[i]);
  }
  sendToTarget(spectrum);
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
  float y = 24;
  text("AudioAnalysisOSC", 24, y);
  y += 26;
  String deviceName = (currentDeviceIndex >= 0 && currentDeviceIndex < devices.length)
    ? devices[currentDeviceIndex]
    : "(no device)";
  if (switchInProgress) {
    deviceName = "Switching → " + devices[pendingDeviceIndex];
  }
  text("Input: " + deviceName, 24, y);
  y += 20;
  String bpmStr = autoBpm.getBpm() > 0 ? String.format("%.1f", autoBpm.getBpm()) : "---";
  text(String.format("Level: %.3f  |  BPM: %s  |  Analyzer: %.2f ms", overallLevel, bpmStr, analysisLatencyMs), 24, y);
  y += 30;

  text("Devices (Up/Down to select, Enter to activate, R to rescan):", 24, y);
  y += 20;
  for (int i = 0; i < devices.length; i++) {
    String prefix = "  ";
    if (i == currentDeviceIndex && !switchInProgress) {
      fill(0, 200, 0);  // active device = green
      prefix = "> ";
    } else if (switchInProgress && i == pendingDeviceIndex) {
      fill(200, 200, 0);  // switching to = yellow
      prefix = "* ";
    } else if (i == selectedDeviceIndex) {
      fill(100, 150, 255);  // selected but not active = blue
      prefix = "[ ";
    } else {
      fill(180);
    }
    text(prefix + devices[i], 24, y);
    y += 18;
  }

  y += 12;
  fill(120);
  text("OSC → " + oscSummary() + " (/audio/*)", 24, y);
  
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
  
  // Use logarithmic frequency mapping for better distribution
  for (int i = 0; i < numBars; i++) {
    // Log scale: map bar index to FFT bin with logarithmic distribution
    float logMin = log(1);
    float logMax = log(FFT_BANDS);
    float logVal = map(i, 0, numBars, logMin, logMax);
    int binIdx = constrain(int(exp(logVal)), 0, FFT_BANDS - 1);
    
    // Get value from smoothed spectrum
    float val = smoothedSpectrum[binIdx];
    
    // Apply different scaling per frequency range (bass needs less boost)
    float boost = map(i, 0, numBars, 3, 12);  // Less boost for bass, more for highs
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
  text("Spectrum (log scale)", x, y - 6);
  textAlign(LEFT, TOP);
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
    
    // Level bar (scaled, values are typically 0-0.5 range)
    float level = constrain(values[i] * 4, 0, 1);  // scale up for visibility
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
  }
}

// === Helper classes ===

class FrequencyBands {
  int fftSize;
  int sampleRate = 44100;
  float[] spectrumRef;

  FrequencyBands(int fftSize) {
    this.fftSize = fftSize;
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
    return sum / max(1, end - start);
  }

  int freqToBin(float freq) {
    return int(freq * fftSize / (float)sampleRate);
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
  int size = 43;
  int index = 0;
  float threshold = 1.35f;
  boolean beat;
  float pulse;

  BeatDetector(int fftSize) {
    history = new float[size];
  }

  void update(float[] spectrum) {
    float energy = 0;
    for (float v : spectrum) {
      energy += v * v;
    }
    float avg = 0;
    for (float h : history) avg += h;
    avg /= size;
    beat = energy > avg * threshold;
    history[index] = energy;
    index = (index + 1) % size;
    if (beat) {
      pulse = 1;
    }
    pulse *= 0.92f;
  }

  boolean isBeat() { return beat; }
  float getPulse() { return pulse; }
}

class MultiBandBeatDetector {
  float bassPulse, midPulse, highPulse;
  float decay = 0.85f;
  
  // History for adaptive thresholds
  float[] bassHistory = new float[30];
  float[] midHistory = new float[30];
  float[] highHistory = new float[30];
  int histIdx = 0;
  float sensitivity = 1.4f;  // multiplier above average to trigger

  void update(float bassEnergy, float midEnergy, float highEnergy) {
    // Store in history
    bassHistory[histIdx] = bassEnergy;
    midHistory[histIdx] = midEnergy;
    highHistory[histIdx] = highEnergy;
    histIdx = (histIdx + 1) % 30;
    
    // Calculate adaptive thresholds
    float bassAvg = arrayAvg(bassHistory);
    float midAvg = arrayAvg(midHistory);
    float highAvg = arrayAvg(highHistory);
    
    // Detect beats when current > average * sensitivity
    boolean bassBeat = bassEnergy > bassAvg * sensitivity && bassEnergy > 0.005;
    boolean midBeat = midEnergy > midAvg * sensitivity && midEnergy > 0.003;
    boolean highBeat = highEnergy > highAvg * sensitivity && highEnergy > 0.002;
    
    // Update pulses
    if (bassBeat) bassPulse = 1.0;
    else bassPulse *= decay;
    
    if (midBeat) midPulse = 1.0;
    else midPulse *= decay;
    
    if (highBeat) highPulse = 1.0;
    else highPulse *= decay;
  }
  
  float arrayAvg(float[] arr) {
    float sum = 0;
    for (float v : arr) sum += v;
    return sum / arr.length;
  }

  float getBassPulse() { return bassPulse; }
  float getMidPulse() { return midPulse; }
  float getHighPulse() { return highPulse; }
}

class AutoBPM {
  ArrayList<Long> beatTimes = new ArrayList<Long>();
  float bpm = 0;  // Start at 0 (unknown)
  float confidence = 0;
  long lastBeatTime = 0;
  int minIntervalMs = 250;  // Max 240 BPM
  int maxIntervalMs = 1500; // Min 40 BPM

  void recordBeat() {
    long now = millis();
    
    // Debounce: ignore beats too close together
    if (now - lastBeatTime < minIntervalMs) {
      return;
    }
    lastBeatTime = now;
    
    beatTimes.add(now);
    
    // Keep only recent beats (last 8 seconds)
    while (beatTimes.size() > 0 && now - beatTimes.get(0) > 8000) {
      beatTimes.remove(0);
    }
    
    // Limit size
    if (beatTimes.size() > 16) {
      beatTimes.remove(0);
    }
    
    // Need at least 4 beats for BPM calculation
    if (beatTimes.size() >= 4) {
      float avgInterval = medianInterval();
      if (avgInterval >= minIntervalMs && avgInterval <= maxIntervalMs) {
        float newBpm = 60000.0f / avgInterval;
        // Smooth BPM changes
        if (bpm == 0) {
          bpm = newBpm;
        } else {
          bpm = lerp(bpm, newBpm, 0.3f);
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
  } catch (Exception e) {
    println("Config load error (" + fileName + "): " + e.getMessage());
  }
  return cfg;
}
