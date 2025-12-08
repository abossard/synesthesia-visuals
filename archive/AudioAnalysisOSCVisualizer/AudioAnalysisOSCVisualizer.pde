/**
 * AudioAnalysisOSCVisualizer - OSC-based audio visualization display
 *
 * This sketch receives OSC messages from the Python Essentia audio analyzer
 * and visualizes them. It does NOT perform any audio analysis itself.
 *
 * Requirements:
 * - Processing 4.x (Intel build on Apple Silicon when using Syphon)
 * - oscP5 library for OSC input
 * - Syphon library for frame output (macOS only)
 *
 * Features:
 * - Receives all audio features via OSC from Python analyzer
 * - Visualizes: levels, spectrum, beats, BPM, pitch, spectral features, structure
 * - Outputs via Syphon for VJ software integration
 * - Provides a visual HUD showing all incoming data
 *
 * OSC Setup:
 * - Default receive port: 9000
 * - Expected sender: python-vj/audio_analyzer.py
 * - All OSC addresses match the AudioAnalysisOSC format
 */

import oscP5.*;
import netP5.*;
import codeanticode.syphon.*;

// === OSC Configuration ===
OscP5 osc;
int oscPort = 9000;

// === Syphon Output ===
SyphonServer syphon;

// === Audio Features (received via OSC) ===
// Frequency bands (8 values)
float subBass, bass, lowMid, mid, highMid, presence, air, overallLevel;

// Spectrum (32 bins)
int spectrumBins = 32;
float[] spectrum = new float[spectrumBins];

// Beat/onset (single stream)
int isBeat = 0;
float beatPulse = 0.0f;  // Spectral flux-based pulse
long lastBeatMillis = 0;  // Time of last onset
ArrayList<Float> beatHistory = new ArrayList<Float>();
int beatHistorySize = 120;

// BPM
float bpm = 0.0f;
float bpmConfidence = 0.0f;

// Pitch
float pitchHz = 0.0f;
float pitchConf = 0.0f;

// Spectral features
float spectralCentroid = 0.0f;
float spectralRolloff = 0.0f;
float spectralFlux = 0.0f;

// Structure
int isBuildup = 0;
int isDrop = 0;
float energyTrend = 0.0f;
float brightness = 0.0f;

// === EDM Features (14 new descriptors) ===
float beat = 0.0f;  // Beat impulse (0 or 1)
float beatConf = 0.0f;  // Beat confidence
float energy = 0.0f;  // Raw energy
float energySmooth = 0.0f;  // EMA-smoothed energy (normalized)
float beatEnergyGlobal = 0.0f;  // Global beat loudness
float beatEnergyLow = 0.0f;  // Low-band beat loudness
float beatEnergyHigh = 0.0f;  // High-band beat loudness
float brightnessNorm = 0.0f;  // Normalized brightness (0=dark, 1=bright)
float noisiness = 0.0f;  // Spectral flatness (0=tonal, 1=noise)
float bassBand = 0.0f;  // Low band energy (normalized)
float midBand = 0.0f;  // Mid band energy (normalized)
float highBand = 0.0f;  // High band energy (normalized)
float dynamicComplexity = 0.0f;  // Loudness variance

// Slow envelopes / macro controls
float energySlow = 0.0f;
float brightnessSlow = 0.0f;
float noisinessSlow = 0.0f;
float bassSlow = 0.0f;
float midSlow = 0.0f;
float highSlow = 0.0f;
float intensitySlow = 0.0f;

// === Connection Status ===
long lastOscTime = 0;
boolean oscConnected = false;

// === UI ===
PFont hudFont;
int frameCounter = 0;

void settings() {
  size(1280, 720, P3D);  // Larger layout for clear panels
}

void setup() {
  surface.setTitle("Audio Analysis OSC Visualizer");
  
  // Use Processing's default monospace font for cross-platform compatibility
  // Falls back gracefully if IBM Plex Mono not available
  try {
    hudFont = createFont("IBM Plex Mono", 16, true);
  } catch (Exception e) {
    hudFont = createFont("Courier", 16, true);
  }
  textFont(hudFont);
  
  // Initialize OSC receiver
  osc = new OscP5(this, oscPort);
  println("Listening for OSC on port " + oscPort);
  println("Start Python audio analyzer: cd python-vj && python vj_console.py");
  
  // Initialize Syphon output
  syphon = new SyphonServer(this, "AudioOSCVisualizer");
  
  // Initialize arrays
  for (int i = 0; i < spectrumBins; i++) {
    spectrum[i] = 0.0f;
  }
  
  frameRate(60);
}

void draw() {
  frameCounter++;
  background(0);

  // Decay beat pulse so the circle fades quickly between onsets
  beatPulse *= 0.80f;
  if (beatHistory.size() >= beatHistorySize) {
    beatHistory.remove(0);
  }
  beatHistory.add(beatPulse);
  
  // Check connection status
  long now = millis();
  oscConnected = (now - lastOscTime) < 2000;  // 2 second timeout
  
  if (!oscConnected) {
    drawConnectionStatus();
  } else {
    // Draw all visualizations (three-column layout)
    drawSlowPanel(40, 80);
    drawEDMPanel(560, 80);
    drawLevelBars(width - 220, 80);
    drawBeatPanel(width - 220, 260);
    drawSpectralPanel(40, 360);
    drawStructurePanel(560, 360);
    drawSpectrumBars(40, height - 160, width - 80, 140);
  }
  
  // Always draw HUD
  drawHud();
  
  // Send to Syphon
  syphon.sendScreen();
}

// === OSC Event Handler ===

// Expected OSC type tags for validation
final String LEVELS_TYPE_TAG = "ffffffff";  // 8 floats
final String BPM_TYPE_TAG = "ff";            // 2 floats
final String PITCH_TYPE_TAG = "ff";          // 2 floats
final String SPECTRAL_TYPE_TAG = "fff";      // 3 floats

void oscEvent(OscMessage msg) {
  lastOscTime = millis();
  
  String addr = msg.addrPattern();
  
  if (addr.equals("/audio/levels")) {
    // [sub_bass, bass, low_mid, mid, high_mid, presence, air, overall_rms]
    if (msg.checkTypetag(LEVELS_TYPE_TAG)) {
      subBass = msg.get(0).floatValue();
      bass = msg.get(1).floatValue();
      lowMid = msg.get(2).floatValue();
      mid = msg.get(3).floatValue();
      highMid = msg.get(4).floatValue();
      presence = msg.get(5).floatValue();
      air = msg.get(6).floatValue();
      overallLevel = msg.get(7).floatValue();
    }
  }
  else if (addr.equals("/audio/spectrum")) {
    // Array of 32 floats
    int count = min(msg.typetag().length(), spectrumBins);
    for (int i = 0; i < count; i++) {
      spectrum[i] = msg.get(i).floatValue();
    }
  }
  else if (addr.equals("/audio/beat")) {
      // [is_onset, spectral_flux]
      if (msg.typetag().length() >= 2) {
        isBeat = msg.get(0).intValue();
        float flux = msg.get(1).floatValue();
        beatPulse = constrain(flux, 0, 1);
        spectralFlux = flux;  // Keep flux visible in spectral panel
        if (isBeat == 1) {
          lastBeatMillis = lastOscTime;
        }
      }
    }
  else if (addr.equals("/audio/bpm")) {
    // [bpm, confidence]
    if (msg.checkTypetag(BPM_TYPE_TAG)) {
      bpm = msg.get(0).floatValue();
      bpmConfidence = msg.get(1).floatValue();
    }
  }
    else if (addr.equals("/bpm")) {
      // Single-value BPM (EDM features)
      bpm = msg.get(0).floatValue();
    }
  else if (addr.equals("/audio/pitch")) {
    // [frequency_hz, confidence]
    if (msg.checkTypetag(PITCH_TYPE_TAG)) {
      pitchHz = msg.get(0).floatValue();
      pitchConf = msg.get(1).floatValue();
    }
  }
  else if (addr.equals("/audio/spectral")) {
    // [centroid_norm, rolloff_hz, flux]
    if (msg.checkTypetag(SPECTRAL_TYPE_TAG)) {
      spectralCentroid = msg.get(0).floatValue();
      spectralRolloff = msg.get(1).floatValue();
      spectralFlux = msg.get(2).floatValue();
    }
  }
  else if (addr.equals("/audio/structure")) {
    // [is_buildup, is_drop, energy_trend, brightness]
    if (msg.typetag().length() >= 4) {
      isBuildup = msg.get(0).intValue();
      isDrop = msg.get(1).intValue();
      energyTrend = msg.get(2).floatValue();
      brightness = msg.get(3).floatValue();
    }
  }
  // === EDM Features (14 new descriptors) ===
  else if (addr.equals("/beat")) {
    beat = msg.get(0).floatValue();
  }
  else if (addr.equals("/beat_conf")) {
    beatConf = msg.get(0).floatValue();
  }
  else if (addr.equals("/energy")) {
    energy = msg.get(0).floatValue();
  }
  else if (addr.equals("/energy_smooth")) {
    energySmooth = msg.get(0).floatValue();
  }
  else if (addr.equals("/energy_slow")) {
    energySlow = msg.get(0).floatValue();
  }
  else if (addr.equals("/beat_energy")) {
    beatEnergyGlobal = msg.get(0).floatValue();
  }
  else if (addr.equals("/beat_energy_low")) {
    beatEnergyLow = msg.get(0).floatValue();
  }
  else if (addr.equals("/beat_energy_high")) {
    beatEnergyHigh = msg.get(0).floatValue();
  }
  else if (addr.equals("/brightness")) {
    brightnessNorm = msg.get(0).floatValue();
  }
  else if (addr.equals("/brightness_slow")) {
    brightnessSlow = msg.get(0).floatValue();
  }
  else if (addr.equals("/noisiness")) {
    noisiness = msg.get(0).floatValue();
  }
  else if (addr.equals("/noisiness_slow")) {
    noisinessSlow = msg.get(0).floatValue();
  }
  else if (addr.equals("/bass_band")) {
    bassBand = msg.get(0).floatValue();
  }
  else if (addr.equals("/bass_band_slow")) {
    bassSlow = msg.get(0).floatValue();
  }
  else if (addr.equals("/mid_band")) {
    midBand = msg.get(0).floatValue();
  }
  else if (addr.equals("/mid_band_slow")) {
    midSlow = msg.get(0).floatValue();
  }
  else if (addr.equals("/high_band")) {
    highBand = msg.get(0).floatValue();
  }
  else if (addr.equals("/high_band_slow")) {
    highSlow = msg.get(0).floatValue();
  }
  else if (addr.equals("/intensity")) {
    intensitySlow = msg.get(0).floatValue();
  }
  else if (addr.equals("/dynamic_complexity")) {
    dynamicComplexity = msg.get(0).floatValue();
  }
}

// === Drawing Functions ===

void drawSlowPanel(float x, float y) {
  float w = 480;
  float h = 220;
  fill(20);
  stroke(60);
  rect(x - 4, y - 4, w + 8, h + 8, 4);
  noStroke();

  float py = y;
  fill(200);
  text("Slow Envelopes", x, py);
  py += 20;

  // Intensity headline
  fill(255, 220, 100);
  textSize(28);
  text(String.format("%.2f", intensitySlow), x, py);
  textSize(16);
  fill(180);
  text("Intensity", x + 90, py + 6);
  py += 30;
  
  // Intensity bar
  fill(40);
  rect(x, py, w, 10);
  fill(100, 255, 150);
  rect(x, py, w * constrain(intensitySlow, 0, 1), 10);
  py += 18;
  
  // Energy / brightness / noise
  fill(180);
  text("Energy", x, py);
  fill(255, 220, 100);
  text(String.format("%.2f", energySlow), x + 70, py);
  py += 16;
  fill(40);
  rect(x, py, w, 8);
  fill(100, 255, 150);
  rect(x, py, w * constrain(energySlow, 0, 1), 8);
  py += 14;
  
  fill(180);
  text("Brightness", x, py);
  fill(255, 220, 100);
  text(String.format("%.2f", brightnessSlow), x + 90, py);
  py += 16;
  fill(40);
  rect(x, py, w, 8);
  fill(100, 200, 255);
  rect(x, py, w * constrain(brightnessSlow, 0, 1), 8);
  py += 14;
  
  fill(180);
  text("Noise", x, py);
  fill(noisinessSlow > 0.5f ? color(255, 100, 100) : color(100, 255, 100));
  text(String.format("%.2f", noisinessSlow), x + 60, py);
  py += 16;
  fill(40);
  rect(x, py, w, 8);
  fill(200, 150, 255);
  rect(x, py, w * constrain(noisinessSlow, 0, 1), 8);
  py += 18;
  
  // Bands
  fill(180);
  text("Bands", x, py);
  py += 16;
  float col1 = x;
  float col2 = x + 100;
  float col3 = x + 200;
  fill(120);
  textSize(10);
  text("Bass", col1, py);
  text("Mid", col2, py);
  text("High", col3, py);
  textSize(16);
  py += 14;
  
  fill(255, 100, 50);
  text(String.format("%.2f", bassSlow), col1, py);
  fill(100, 255, 100);
  text(String.format("%.2f", midSlow), col2, py);
  fill(100, 100, 255);
  text(String.format("%.2f", highSlow), col3, py);
  py += 12;
  
  float barW = 80;
  fill(40);
  rect(col1, py, barW, 6);
  rect(col2, py, barW, 6);
  rect(col3, py, barW, 6);
  fill(255, 100, 50);
  rect(col1, py, barW * constrain(bassSlow, 0, 1), 6);
  fill(100, 255, 100);
  rect(col2, py, barW * constrain(midSlow, 0, 1), 6);
  fill(100, 100, 255);
  rect(col3, py, barW * constrain(highSlow, 0, 1), 6);
  
  textSize(16);
}

void drawConnectionStatus() {
  fill(200, 50, 50);
  textAlign(CENTER, CENTER);
  textSize(24);
  text("Waiting for OSC data...", width/2, height/2 - 40);
  
  fill(150);
  textSize(16);
  text("Port: " + oscPort, width/2, height/2);
  text("Run: cd python-vj && python vj_console.py", width/2, height/2 + 30);
  text("Press 'A' to start audio analyzer", width/2, height/2 + 50);
  
  textAlign(LEFT, TOP);
}

void drawHud() {
  fill(255);
  textAlign(LEFT, TOP);
  textSize(16);
  float y = 16;
  
  // Header
  text("Audio Analysis OSC Visualizer", 24, y);
  y += 22;
  
  // Connection status
  if (oscConnected) {
    fill(0, 200, 0);
    text("OSC Connected (port " + oscPort + ")", 24, y);
  } else {
    fill(200, 50, 50);
    text("OSC Disconnected", 24, y);
  }
  y += 20;
  
  // Stats
  fill(180);
  text(String.format("BPM: %.1f (%.0f%%)  |  Overall: %.3f  |  %d fps", 
    bpm, bpmConfidence * 100, overallLevel, int(frameRate)), 24, y);
}

void drawSpectrumBars(float x, float y, float w, float h) {
  // Background panel
  fill(20);
  stroke(60);
  rect(x - 4, y - 4, w + 8, h + 8, 4);
  noStroke();
  
  // Draw spectrum bars
  float barW = w / spectrumBins;
  for (int i = 0; i < spectrumBins; i++) {
    float val = constrain(spectrum[i], 0, 1);
    float barH = val * h;
    
    // Color gradient from red (low) to blue (high)
    float hue = map(i, 0, spectrumBins, 0, 0.7f);  // red to blue
    colorMode(HSB, 1);
    fill(hue, 0.8f, 0.9f);
    colorMode(RGB, 255);
    
    rect(x + i * barW, y + h - barH, barW - 1, barH);
  }
  
  // Labels
  fill(150);
  textAlign(LEFT, BOTTOM);
  textSize(12);
  text("Spectrum (32 bins)", x, y - 6);
  textSize(16);
  textAlign(LEFT, TOP);
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
    
    // Level bar
    float level = constrain(values[i], 0, 1);
    if (level > 0.01f) {
      fill(colors[i]);
      rect(x + 65, ly, barWidth * level, barHeight);
    }
    
  }
  textAlign(LEFT, TOP);
}

void drawBeatPanel(float x, float y) {
  // Background panel
  fill(20);
  stroke(60);
  rect(x - 4, y - 4, 180, 140, 4);
  noStroke();
  
  float py = y;
  
  // Title
  fill(200);
  text("Beat Detection", x, py);
  py += 22;
  
  // BPM display (large)
  fill(255, 220, 100);
  textSize(28);
  if (bpm > 0) {
    text(String.format("%.0f", bpm), x, py);
  } else {
    fill(100);
    text("---", x, py);
  }
  textSize(16);
  fill(150);
  text(" BPM", x + 50, py + 8);
  py += 36;
  
  // Confidence bar
  fill(100);
  text("Confidence", x, py);
  py += 18;
  fill(40);
  rect(x, py, 160, 10);
  fill(100, 255, 150);
  rect(x, py, 160 * bpmConfidence, 10);
  py += 20;
  
  // Beat indicators
  fill(100);
  text("Pulses", x, py);
  py += 20;
  
  float pulse = constrain(beatPulse, 0, 1);
  pulse = min(pulse, 0.6f);
  boolean beatActive = (millis() - lastBeatMillis) < 120;
  float cx = x + 10;
  float graphWidth = 140;
  float graphHeight = 50;
  
  // Graph background
  fill(25);
  rect(cx, py - 14, graphWidth, graphHeight, 4);
  stroke(60);
  line(cx, py + graphHeight / 2, cx + graphWidth, py + graphHeight / 2);
  
  // Draw heartbeat-like waveform
  noFill();
  stroke(255, 180, 80);
  strokeWeight(2);
  beginShape();
  int count = beatHistory.size();
  for (int i = 0; i < count; i++) {
    float t = map(i, 0, beatHistorySize - 1, 0, graphWidth);
    float val = beatHistory.get(i);
    float yOffset = map(val, 0, 0.6f, graphHeight * 0.7f, graphHeight * 0.3f);
    vertex(cx + t, py + yOffset);
  }
  endShape();
  strokeWeight(1);
  
  // Current pulse indicator (vertical line)
  if (beatActive || pulse > 0.05f) {
    float markerX = cx + graphWidth - 2;
    stroke(255, 220, 100);
    line(markerX, py + graphHeight * 0.3f, markerX, py + graphHeight * 0.7f);
  }
  noStroke();
  fill(180);
  textAlign(LEFT, TOP);
  text("Pulse History", cx, py + graphHeight + 6);
}

void drawSpectralPanel(float x, float y) {
  // Background panel
  fill(20);
  stroke(60);
  rect(x - 4, y - 4, 250, 120, 4);
  noStroke();
  
  float py = y;
  
  // Title
  fill(200);
  text("Spectral Features", x, py);
  py += 22;
  
  // Centroid
  fill(180);
  text("Centroid:", x, py);
  fill(255, 220, 100);
  text(String.format("%.2f", spectralCentroid), x + 90, py);
  py += 20;
  
  // Centroid bar
  fill(40);
  rect(x, py, 230, 8);
  fill(100, 200, 255);
  rect(x, py, 230 * constrain(spectralCentroid, 0, 1), 8);
  py += 16;
  
  // Rolloff
  fill(180);
  text("Rolloff:", x, py);
  fill(255, 220, 100);
  text(String.format("%.0f Hz", spectralRolloff), x + 90, py);
  py += 20;
  
  // Flux
  fill(180);
  text("Flux:", x, py);
  fill(255, 220, 100);
  text(String.format("%.3f", spectralFlux), x + 90, py);
  py += 20;
  
  // Pitch
  fill(180);
  text("Pitch:", x, py);
  if (pitchConf > 0.6f && pitchHz > 0) {
    fill(255, 220, 100);
    text(String.format("%.1f Hz", pitchHz), x + 90, py);
  } else {
    fill(100);
    text("---", x + 90, py);
  }
}

void drawStructurePanel(float x, float y) {
  // Background panel
  fill(20);
  stroke(60);
  rect(x - 4, y - 4, 250, 100, 4);
  noStroke();
  
  float py = y;
  
  // Title
  fill(200);
  text("Structure Analysis", x, py);
  py += 22;
  
  // Build-up indicator
  if (isBuildup == 1) {
    fill(255, 200, 50);
    text("BUILD-UP", x, py);
  } else {
    fill(100);
    text("---", x, py);
  }
  py += 20;
  
  // Drop indicator
  if (isDrop == 1) {
    fill(255, 50, 50);
    text("DROP!", x, py);
    // Flash effect
    fill(255, 255, 255, 100);
    rect(0, 0, width, height);
  } else {
    fill(100);
    text("---", x, py);
  }
  py += 20;
  
  // Energy trend
  fill(180);
  text("Energy:", x, py);
  fill(energyTrend > 0 ? color(100, 255, 100) : color(255, 100, 100));
  text(String.format("%.2f", energyTrend), x + 90, py);
  py += 20;
  
  // Brightness
  fill(180);
  text("Brightness:", x, py);
  fill(255, 220, 100);
  text(String.format("%.2f", brightness), x + 90, py);
}

void drawEDMPanel(float x, float y) {
  // Background panel for EDM features
  fill(20);
  stroke(60);
  rect(x - 4, y - 4, 280, 140, 4);
  noStroke();
  
  float py = y;
  
  // Title
  fill(200);
  text("EDM Features", x, py);
  py += 22;
  
  // Energy displays
  fill(180);
  text("Energy:", x, py);
  fill(255, 220, 100);
  text(String.format("%.3f", energy), x + 90, py);
  fill(100, 200, 255);
  text("Smooth:", x + 160, py);
  text(String.format("%.2f", energySmooth), x + 220, py);
  py += 18;
  
  // Energy bar
  fill(40);
  rect(x, py, 260, 8);
  fill(100, 255, 150);
  rect(x, py, 260 * constrain(energySmooth, 0, 1), 8);
  py += 14;
  
  // Beat energies
  fill(180);
  text("Beat Energy:", x, py);
  py += 16;
  
  // Three columns for beat energy
  float col1 = x;
  float col2 = x + 90;
  float col3 = x + 180;
  
  fill(120);
  textSize(10);
  text("Global", col1, py);
  text("Low", col2, py);
  text("High", col3, py);
  textSize(16);
  py += 14;
  
  fill(255, 200, 100);
  text(String.format("%.2f", beatEnergyGlobal), col1, py);
  text(String.format("%.2f", beatEnergyLow), col2, py);
  text(String.format("%.2f", beatEnergyHigh), col3, py);
  py += 18;
  
  // Band energies
  fill(180);
  text("Bands (norm):", x, py);
  py += 16;
  
  fill(120);
  textSize(10);
  text("Bass", col1, py);
  text("Mid", col2, py);
  text("High", col3, py);
  textSize(16);
  py += 14;
  
  fill(255, 100, 50);
  text(String.format("%.2f", bassBand), col1, py);
  fill(100, 255, 100);
  text(String.format("%.2f", midBand), col2, py);
  fill(100, 100, 255);
  text(String.format("%.2f", highBand), col3, py);
  py += 18;
  
  // Spectral qualities
  fill(180);
  text("Brightness:", x, py);
  fill(255, 220, 100);
  text(String.format("%.2f", brightnessNorm), x + 100, py);
  
  fill(180);
  text("Noise:", x + 160, py);
  fill(noisiness > 0.5 ? color(255, 100, 100) : color(100, 255, 100));
  text(String.format("%.2f", noisiness), x + 220, py);
  
  textSize(16);
}

void keyPressed() {
  if (key == 'r' || key == 'R') {
    // Reset all values
    subBass = bass = lowMid = mid = highMid = presence = air = overallLevel = 0;
    for (int i = 0; i < spectrumBins; i++) {
      spectrum[i] = 0;
    }
    isBeat = 0;
    beatPulse = 0;
    bpm = bpmConfidence = 0;
    pitchHz = pitchConf = 0;
    spectralCentroid = spectralRolloff = spectralFlux = 0;
    isBuildup = isDrop = 0;
    energyTrend = brightness = 0;
    energySlow = brightnessSlow = noisinessSlow = 0;
    bassSlow = midSlow = highSlow = 0;
    intensitySlow = 0;
  }
}
