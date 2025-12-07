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

// Beats
int isBeat = 0;
float beatPulse = 0.0f;
float bassHitPulse = 0.0f;
float midHitPulse = 0.0f;
float highHitPulse = 0.0f;

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

// === Connection Status ===
long lastOscTime = 0;
boolean oscConnected = false;

// === UI ===
PFont hudFont;
int frameCounter = 0;

void settings() {
  size(960, 540, P3D);  // P3D required for Syphon
}

void setup() {
  surface.setTitle("Audio Analysis OSC Visualizer");
  hudFont = createFont("IBM Plex Mono", 16, true);
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
  
  // Check connection status
  long now = millis();
  oscConnected = (now - lastOscTime) < 2000;  // 2 second timeout
  
  if (!oscConnected) {
    drawConnectionStatus();
  } else {
    // Draw all visualizations
    drawSpectrumBars(24, height - 120, width - 48, 100);
    drawLevelBars(width - 200, 24);
    drawBeatPanel(width - 200, 180);
    drawSpectralPanel(24, 24);
    drawStructurePanel(24, 180);
  }
  
  // Always draw HUD
  drawHud();
  
  // Send to Syphon
  syphon.sendScreen();
}

// === OSC Event Handler ===

void oscEvent(OscMessage msg) {
  lastOscTime = millis();
  
  String addr = msg.addrPattern();
  
  if (addr.equals("/audio/levels")) {
    // [sub_bass, bass, low_mid, mid, high_mid, presence, air, overall_rms]
    if (msg.checkTypetag("ffffffff")) {
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
  else if (addr.equals("/audio/beats")) {
    // [is_beat, beat_pulse, bass_pulse, mid_pulse, high_pulse]
    if (msg.typetag().length() >= 5) {
      isBeat = msg.get(0).intValue();
      beatPulse = msg.get(1).floatValue();
      bassHitPulse = msg.get(2).floatValue();
      midHitPulse = msg.get(3).floatValue();
      highHitPulse = msg.get(4).floatValue();
    }
  }
  else if (addr.equals("/audio/bpm")) {
    // [bpm, confidence]
    if (msg.checkTypetag("ff")) {
      bpm = msg.get(0).floatValue();
      bpmConfidence = msg.get(1).floatValue();
    }
  }
  else if (addr.equals("/audio/pitch")) {
    // [frequency_hz, confidence]
    if (msg.checkTypetag("ff")) {
      pitchHz = msg.get(0).floatValue();
      pitchConf = msg.get(1).floatValue();
    }
  }
  else if (addr.equals("/audio/spectral")) {
    // [centroid_norm, rolloff_hz, flux]
    if (msg.checkTypetag("fff")) {
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
}

// === Drawing Functions ===

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
    
    // Beat pulse indicators
    if (i == 1 && bassHitPulse > 0.1f) {
      fill(255, 100, 50, bassHitPulse * 255);
      ellipse(x + 65 + barWidth + 15, ly + barHeight/2, 10, 10);
    } else if (i == 3 && midHitPulse > 0.1f) {
      fill(100, 255, 100, midHitPulse * 255);
      ellipse(x + 65 + barWidth + 15, ly + barHeight/2, 10, 10);
    } else if (i == 5 && highHitPulse > 0.1f) {
      fill(100, 100, 255, highHitPulse * 255);
      ellipse(x + 65 + barWidth + 15, ly + barHeight/2, 10, 10);
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
  
  float circleSize = 30;
  float cx = x + 25;
  
  // Bass pulse circle
  fill(40);
  ellipse(cx, py + 15, circleSize, circleSize);
  if (bassHitPulse > 0.05f) {
    fill(255, 100, 50, 100 + bassHitPulse * 155);
    float pulseSize = circleSize * (0.5f + bassHitPulse * 0.5f);
    ellipse(cx, py + 15, pulseSize, pulseSize);
  }
  fill(180);
  textAlign(CENTER, TOP);
  text("Bass", cx, py + 32);
  
  // Mid pulse circle
  cx += 55;
  fill(40);
  ellipse(cx, py + 15, circleSize, circleSize);
  if (midHitPulse > 0.05f) {
    fill(100, 255, 100, 100 + midHitPulse * 155);
    float pulseSize = circleSize * (0.5f + midHitPulse * 0.5f);
    ellipse(cx, py + 15, pulseSize, pulseSize);
  }
  fill(180);
  text("Mid", cx, py + 32);
  
  // High pulse circle
  cx += 55;
  fill(40);
  ellipse(cx, py + 15, circleSize, circleSize);
  if (highHitPulse > 0.05f) {
    fill(150, 100, 255, 100 + highHitPulse * 155);
    float pulseSize = circleSize * (0.5f + highHitPulse * 0.5f);
    ellipse(cx, py + 15, pulseSize, pulseSize);
  }
  fill(180);
  text("High", cx, py + 32);
  
  textAlign(LEFT, TOP);
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

void keyPressed() {
  if (key == 'r' || key == 'R') {
    // Reset all values
    subBass = bass = lowMid = mid = highMid = presence = air = overallLevel = 0;
    for (int i = 0; i < spectrumBins; i++) {
      spectrum[i] = 0;
    }
    isBeat = 0;
    beatPulse = bassHitPulse = midHitPulse = highHitPulse = 0;
    bpm = bpmConfidence = 0;
    pitchHz = pitchConf = 0;
    spectralCentroid = spectralRolloff = spectralFlux = 0;
    isBuildup = isDrop = 0;
    energyTrend = brightness = 0;
  }
}
