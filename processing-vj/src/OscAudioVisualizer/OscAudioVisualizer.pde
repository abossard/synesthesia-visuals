/**
 * OscAudioVisualizer - Reactive monitor for python-vj/audio_analyzer.py
 *
 * Listens to the OSC stream emitted by audio_analyzer.py and turns the band
 * energies, spectrum, beat pulses, BPM, and structural hints into a layered
 * VJ-safe visual.
 *
 * Features
 * --------
 * - Neon orbital arcs for the 7 audio bands + halo driven by RMS
 * - Radial pulse + particle bursts on every beat (flux-weighted)
 * - Spectrum river with logarithmic spacing and smooth interpolation
 * - Build-up vs drop indicators + brightness trend meter
 * - Minimal HUD (toggle with 'h') for BPM / pitch / OSC status
 * - Syphon output for downstream mixing (default name: "AudioOSCVisualizer")
 *
 * Requirements
 * ------------
 * - Processing 4.x (Intel build on Apple Silicon when Syphon is used)
 * - oscP5 + netP5 libraries (Manage Libraries)
 * - Syphon library for Processing
 * - python-vj/audio_analyzer.py running with osc_port matching this sketch
 */

import oscP5.*;
import netP5.*;
import codeanticode.syphon.*;
import processing.data.JSONObject;
import java.util.ArrayList;
import java.util.Locale;

final int OUTPUT_WIDTH = 1280;
final int OUTPUT_HEIGHT = 720;

OscP5 osc;
SyphonServer syphon;
VisualizerConfig config = new VisualizerConfig();
AudioState audio = new AudioState();
ArrayList<BeatParticle> particles = new ArrayList<BeatParticle>();
float[] spectrumDisplay = new float[32];
color[] bandPalette;

PFont hudFont;
boolean showHud = true;
long lastFrameMillis = 0;
long lastOscMessageTime = 0;
boolean oscConnected = false;

void settings() {
  size(OUTPUT_WIDTH, OUTPUT_HEIGHT, P3D);
  smooth(8);
}

void setup() {
  loadConfig();
  colorMode(HSB, 360, 100, 100, 100);
  frameRate(config.frameRate);
  hudFont = createFont("IBM Plex Mono", 24, true);
  textFont(hudFont);
  initPalettes();
  restartOsc();
  initSyphon();
  lastFrameMillis = millis();
}

void draw() {
  float now = millis();
  float dt = max(1e-3f, (now - lastFrameMillis) / 1000.0f);
  lastFrameMillis = (long) now;
  audio.tick(dt);
  updateSpectrumDisplay();
  updateConnectionState(now);

  background(0);
  drawBackdropGrid();
  drawSpectrumRiver();
  drawBandOrbitals();
  drawBeatPulse();
  updateParticles(dt);
  drawParticles();
  drawTrendMeter();
  if (showHud) {
    drawHud();
  }

  if (syphon != null) {
    syphon.sendScreen();
  }
}

void updateConnectionState(float now) {
  oscConnected = (now - lastOscMessageTime) < config.oscTimeoutMs;
}

void initPalettes() {
  bandPalette = new color[] {
    color(210, 70, 90, 100),  // sub bass
    color(195, 80, 100, 100), // bass
    color(170, 70, 95, 100),  // low mid
    color(140, 65, 95, 100),  // mid
    color(110, 70, 98, 100),  // high mid
    color(60, 75, 100, 100),  // presence
    color(35, 80, 100, 100)   // air
  };
}

void updateSpectrumDisplay() {
  int len = audio.spectrumSize();
  if (len == 0) {
    return;
  }
  if (spectrumDisplay == null || spectrumDisplay.length != len) {
    spectrumDisplay = new float[len];
  }
  float lerpAmount = 1.0f - config.spectrumSmoothing;
  for (int i = 0; i < len; i++) {
    float target = audio.spectrum[i];
    spectrumDisplay[i] = lerp(spectrumDisplay[i], target, lerpAmount);
  }
}

void drawBackdropGrid() {
  pushMatrix();
  translate(width * 0.5f, height * 0.5f);
  strokeWeight(1);
  float glow = constrain(audio.brightness * 85.0f, 5, 85);
  for (int i = 0; i < 12; i++) {
    float angle = i * TWO_PI / 12.0f + frameCount * 0.0025f;
    float radius = width * 0.55f;
    stroke(200, 10, glow, 12);
    line(0, 0, cos(angle) * radius, sin(angle) * radius);
  }
  noFill();
  stroke(200, 5, 60, 10);
  for (int r = 120; r < width; r += 120) {
    ellipse(0, 0, r, r);
  }
  popMatrix();
}

void drawBandOrbitals() {
  pushMatrix();
  translate(width * 0.5f, height * 0.5f);
  strokeCap(SQUARE);
  noFill();
  for (int i = 0; i < audio.bands.length; i++) {
    float energy = constrain(audio.bands[i] * 4.0f, 0, 1.5f);
    float radius = 160 + i * 60;
    float sweep = map(energy, 0, 1.5f, PI * 0.05f, TWO_PI * 0.85f);
    float start = frameCount * 0.002f + i * 0.4f;
    stroke(bandPalette[i]);
    strokeWeight(map(i, 0, audio.bands.length - 1, 6, 3));
    arc(0, 0, radius * 2, radius * 2, start, start + sweep);
  }
  popMatrix();
}

void drawBeatPulse() {
  pushMatrix();
  translate(width * 0.5f, height * 0.5f);
  float rmsBoost = constrain(audio.rms * 6.0f, 0, 1.2f);
  float beatBoost = pow(audio.beatPulse, 0.5f);
  float radius = lerp(80, width * 0.35f, rmsBoost) + beatBoost * 180;
  noFill();
  stroke(200, 40, 100, 30);
  strokeWeight(8);
  ellipse(0, 0, radius * 2, radius * 2);
  if (audio.dropGlow > 0.05f) {
    stroke(0, 0, 100, audio.dropGlow * 70);
    strokeWeight(12);
    ellipse(0, 0, (radius + 90) * 2, (radius + 90) * 2);
  }
  if (audio.buildupGlow > 0.05f) {
    stroke(35, 90, 100, audio.buildupGlow * 60);
    strokeWeight(6);
    ellipse(0, 0, (radius - 60) * 2, (radius - 60) * 2);
  }
  popMatrix();
}

void drawSpectrumRiver() {
  int len = audio.spectrumSize();
  if (len == 0) {
    return;
  }
  float baseY = height * 0.78f;
  float span = width * 0.9f;
  float startX = (width - span) * 0.5f;
  noStroke();
  beginShape();
  for (int i = 0; i < len; i++) {
    float norm = (float) i / max(1, len - 1);
    float x = startX + norm * span;
    float scale = pow(norm, 1.3f);
    float val = constrain(spectrumDisplay[i] * (0.3f + scale * 2.0f), 0, 1.2f);
    float y = baseY - val * 260;
    float hue = lerp(200, 35, norm);
    fill(hue, 80, 100, 35);
    vertex(x, y);
  }
  for (int i = len - 1; i >= 0; i--) {
    float norm = (float) i / max(1, len - 1);
    float x = startX + norm * span;
    float y = baseY + 40;
    fill(200, 10, 20, 0);
    vertex(x, y);
  }
  endShape(CLOSE);
}

void drawTrendMeter() {
  float barX = width * 0.08f;
  float barY = height * 0.2f;
  float barH = height * 0.35f;
  float midY = barY + barH * 0.5f;
  stroke(200, 5, 60, 50);
  strokeWeight(2);
  line(barX, barY, barX, barY + barH);
  float trend = constrain(audio.energyTrend * 4.0f, -1, 1);
  float trendY = midY - trend * (barH * 0.45f);
  stroke(40, 80, 100, 80);
  strokeWeight(6);
  line(barX - 20, trendY, barX + 20, trendY);
  noStroke();
  fill(40, 80, 100, 60);
  ellipse(barX, trendY, 18, 18);
}

void drawHud() {
  fill(0, 0, 100, 60);
  textAlign(LEFT, TOP);
  float y = 36;
  String bpmStr = audio.bpm > 0 ? String.format(Locale.US, "%.1f BPM", audio.bpm) : "---";
  String confStr = String.format(Locale.US, "%d%%", round(audio.bpmConfidence * 100));
  text(bpmStr + "  (" + confStr + ")", 36, y);
  y += 32;
  String pitchStr = audio.pitchHz > 0 ? String.format(Locale.US, "Pitch %.1f Hz", audio.pitchHz) : "Pitch --";
  text(pitchStr, 36, y);
  y += 28;
  String status = oscConnected ? "OSC: connected" : "OSC: waiting";
  fill(oscConnected ? color(120, 80, 100) : color(0, 0, 60));
  text(status + " @ " + config.oscPort, 36, y);
  y += 28;
  fill(0, 0, 80);
  text("Host: " + config.oscHostSummary(), 36, y);
  y += 28;
  text("'h' HUD  'c' reload config", 36, y);
}

void updateParticles(float dt) {
  if (audio.consumeBeatTrigger()) {
    spawnBeatBurst(audio.lastBeatFlux);
  }
  for (int i = particles.size() - 1; i >= 0; i--) {
    BeatParticle p = particles.get(i);
    p.update(dt, config.particleDrag);
    if (p.life <= 0) {
      particles.remove(i);
    }
  }
  while (particles.size() > config.maxParticles) {
    particles.remove(0);
  }
}

void drawParticles() {
  blendMode(ADD);
  strokeCap(ROUND);
  for (BeatParticle p : particles) {
    p.draw();
  }
  blendMode(BLEND);
}

void spawnBeatBurst(float flux) {
  float energy = constrain((float) Math.tanh(flux * 0.02f), 0.05f, 1.0f);
  int count = (int) map(energy, 0.05f, 1.0f, 20, 110);
  for (int i = 0; i < count; i++) {
    float angle = random(TWO_PI);
    float speed = lerp(180, 680, energy) * (0.4f + random(0.6f));
    particles.add(new BeatParticle(angle, speed, energy));
  }
}

void keyPressed() {
  if (key == 'h' || key == 'H') {
    showHud = !showHud;
  } else if (key == 'c' || key == 'C') {
    loadConfig();
    restartOsc();
    initSyphon();
  } else if (key == 'r' || key == 'R') {
    restartOsc();
  }
}

void restartOsc() {
  if (osc != null) {
    osc.stop();
  }
  osc = new OscP5(this, config.oscPort);
  lastOscMessageTime = millis();
}

void initSyphon() {
  try {
    if (syphon != null) {
      syphon.stop();
    }
    syphon = new SyphonServer(this, config.syphonName);
  } catch (Exception e) {
    println("Syphon unavailable: " + e.getMessage());
    syphon = null;
  }
}

void loadConfig() {
  try {
    JSONObject cfg = loadJSONObject("osc_visualizer_config.json");
    if (cfg != null) {
      if (cfg.hasKey("oscPort")) config.oscPort = cfg.getInt("oscPort");
      if (cfg.hasKey("oscHost")) config.oscHost = cfg.getString("oscHost");
      if (cfg.hasKey("syphonName")) config.syphonName = cfg.getString("syphonName");
      if (cfg.hasKey("frameRate")) config.frameRate = cfg.getInt("frameRate");
      if (cfg.hasKey("spectrumSmoothing")) config.spectrumSmoothing = cfg.getFloat("spectrumSmoothing");
      if (cfg.hasKey("particleDrag")) config.particleDrag = cfg.getFloat("particleDrag");
      if (cfg.hasKey("maxParticles")) config.maxParticles = cfg.getInt("maxParticles");
      if (cfg.hasKey("oscTimeoutMs")) config.oscTimeoutMs = cfg.getInt("oscTimeoutMs");
    }
  } catch (Exception e) {
    println("Using default config (" + e.getMessage() + ")");
  }
}

void oscEvent(OscMessage msg) {
  lastOscMessageTime = millis();
  String addr = msg.addrPattern();
  if (addr.equals("/audio/levels")) {
    float[] values = new float[msg.typetag().length()];
    for (int i = 0; i < values.length; i++) {
      values[i] = msg.get(i).floatValue();
    }
    audio.setLevels(values);
  } else if (addr.equals("/audio/spectrum")) {
    float[] values = new float[msg.typetag().length()];
    for (int i = 0; i < values.length; i++) {
      values[i] = msg.get(i).floatValue();
    }
    audio.setSpectrum(values);
  } else if (addr.equals("/audio/beat")) {
    int beat = msg.get(0).intValue();
    float flux = msg.typetag().length() > 1 ? msg.get(1).floatValue() : 0;
    if (beat == 1) {
      audio.triggerBeat(flux);
    }
  } else if (addr.equals("/audio/bpm")) {
    float bpm = msg.get(0).floatValue();
    float conf = msg.typetag().length() > 1 ? msg.get(1).floatValue() : 0;
    audio.setBpm(bpm, conf);
  } else if (addr.equals("/audio/pitch")) {
    float hz = msg.get(0).floatValue();
    float conf = msg.typetag().length() > 1 ? msg.get(1).floatValue() : 0;
    audio.setPitch(hz, conf);
  } else if (addr.equals("/audio/structure")) {
    int buildup = msg.get(0).intValue();
    int drop = msg.get(1).intValue();
    float trend = msg.get(2).floatValue();
    float brightness = msg.get(3).floatValue();
    audio.setStructure(buildup == 1, drop == 1, trend, brightness);
  }
}

class VisualizerConfig {
  int oscPort = 9000;
  String oscHost = "127.0.0.1";
  String syphonName = "AudioOSCVisualizer";
  int frameRate = 60;
  float spectrumSmoothing = 0.7f;
  float particleDrag = 0.92f;
  int maxParticles = 900;
  int oscTimeoutMs = 1200;

  String oscHostSummary() {
    return oscHost + ":" + oscPort;
  }
}

class AudioState {
  float[] bands = new float[7];
  float rms = 0;
  float[] spectrum = new float[0];
  float bpm = 0;
  float bpmConfidence = 0;
  float pitchHz = 0;
  float pitchConf = 0;
  float energyTrend = 0;
  float brightness = 0;
  float beatPulse = 0;
  float lastBeatFlux = 0;
  boolean beatPending = false;
  float bassLevel = 0;
  float midLevel = 0;
  float highLevel = 0;
  float buildupGlow = 0;
  float dropGlow = 0;

  void setLevels(float[] values) {
    if (values.length < bands.length + 1) {
      return;
    }
    for (int i = 0; i < bands.length; i++) {
      bands[i] = values[i];
    }
    rms = values[bands.length];
    bassLevel = (bands[0] + bands[1]) * 0.5f;
    midLevel = (bands[2] + bands[3] + bands[4]) / 3.0f;
    highLevel = (bands[5] + bands[6]) * 0.5f;
  }

  void setSpectrum(float[] values) {
    spectrum = values;
  }

  void setBpm(float bpmVal, float confidence) {
    bpm = bpmVal;
    bpmConfidence = confidence;
  }

  void setPitch(float hz, float confidence) {
    pitchHz = hz;
    pitchConf = confidence;
  }

  void setStructure(boolean buildup, boolean drop, float trend, float bright) {
    energyTrend = trend;
    brightness = bright;
    float buildupTarget = buildup ? 1.0f : 0.0f;
    float dropTarget = drop ? 1.0f : 0.0f;
    buildupGlow = lerp(buildupGlow, buildupTarget, 0.2f);
    dropGlow = lerp(dropGlow, dropTarget, 0.2f);
  }

  void triggerBeat(float flux) {
    beatPulse = 1.0f;
    beatPending = true;
    lastBeatFlux = flux;
  }

  boolean consumeBeatTrigger() {
    if (beatPending) {
      beatPending = false;
      return true;
    }
    return false;
  }

  void tick(float dt) {
    beatPulse = max(0, beatPulse - dt * 2.8f);
    lastBeatFlux *= (1.0f - dt * 0.6f);
    buildupGlow = max(0, buildupGlow - dt * 0.4f);
    dropGlow = max(0, dropGlow - dt * 0.45f);
  }

  int spectrumSize() {
    return spectrum != null ? spectrum.length : 0;
  }
}

class BeatParticle {
  PVector pos;
  PVector vel;
  float life;
  float maxLife;
  float strokeW;
  color col;
  PVector prevPos;

  BeatParticle(float angle, float speed, float energy) {
    pos = new PVector(width * 0.5f, height * 0.5f);
    vel = PVector.fromAngle(angle).mult(speed);
    maxLife = lerp(0.4f, 1.4f, energy);
    life = maxLife;
    strokeW = lerp(1.5f, 4.5f, energy) * (0.6f + random(0.4f));
    float hue = (angle / TWO_PI) * 120 + 180;
    col = color(hue % 360, 80, 100, 80);
    prevPos = pos.copy();
  }

  void update(float dt, float drag) {
    prevPos.set(pos);
    pos.add(PVector.mult(vel, dt));
    vel.mult(drag);
    life -= dt;
  }

  void draw() {
    float alpha = constrain(life / maxLife, 0, 1);
    strokeWeight(strokeW);
    stroke(hue(col), saturation(col), brightness(col), alpha * 100);
    line(prevPos.x, prevPos.y, pos.x, pos.y);
  }
}
