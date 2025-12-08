/**
 * SynesthesiaOSCMonitor - OSC visualizer for Synesthesia Live Pro audio engine output
 *
 * Receives OSC messages on the standard Synesthesia output port (7000) and
 * renders band levels, presence envelopes, transient hits, BPM metrics, and
 * beat timing indicators. Designed for Syphon output into VJ pipelines.
 *
 * Requirements:
 * - Processing 4.x (macOS Intel build under Rosetta for Syphon compatibility)
 * - oscP5 library (OSC input)
 * - Syphon library (frame sharing)
 */

import oscP5.*;
import netP5.*;
import codeanticode.syphon.*;

// === OSC Configuration ===
OscP5 osc;
int listenPort = 7777;
int oscBufferBytes = 4096;

// === Syphon Output ===
SyphonServer syphon;

// === Audio Metrics ===
// Levels
float levelBass, levelMid, levelMidHigh, levelHigh, levelAll, levelRaw;
// Presence
float presenceBass, presenceMid, presenceMidHigh, presenceHigh, presenceAll;
// Hits
float hitsBass, hitsMid, hitsMidHigh, hitsHigh, hitsAll;
// Time accumulators
float timeBass, timeMid, timeMidHigh, timeHigh, timeAll, timeCurved;
// Global energy and beat data
float energyIntensity;
float beatTime;
float beatOn;
float beatRandom;
float beatOnPrev;

// BPM + LFO family
float bpmValue;
float bpmConfidence;
float bpmTwitcher;
float bpmTri;
float bpmTri2;
float bpmTri4;
float bpmTri8;
float bpmSin;
float bpmSin2;
float bpmSin4;
float bpmSin8;

// Connection tracking
long lastOscMillis = 0;
boolean hasConnection = false;

// UI helpers
PFont hudFont;
float smoothing = 0.85f;

String fmt(float value, int decimals) {
  if (Float.isNaN(value) || Float.isInfinite(value)) {
    value = 0;
  }
  return nf(value, 0, decimals);
}

void settings() {
  size(1280, 720, P3D);
}

void setup() {
  surface.setTitle("Synesthesia OSC Monitor");

  try {
    hudFont = createFont("IBM Plex Mono", 18, true);
  } catch (Exception e) {
    hudFont = createFont("Courier New", 18, true);
  }
  textFont(hudFont);

  OscProperties props = new OscProperties();
  props.setRemoteAddress("127.0.0.1", listenPort);
  props.setListeningPort(listenPort);
  props.setNetworkProtocol(OscProperties.UDP);
  props.setDatagramSize(oscBufferBytes);
  osc = new OscP5(this, props);
  println("Listening for Synesthesia OSC on port " + listenPort);

  syphon = new SyphonServer(this, "SynesthesiaOSC");

  frameRate(60);
}

void draw() {
  background(0);
  hasConnection = (millis() - lastOscMillis) < 1500;

  drawHeader();
  if (!hasConnection) {
    drawConnectionWarning();
  } else {
    drawLevelsPanel(40, 120);
    drawHitsPanel(400, 120);
    drawBeatPanel(760, 120);
    drawPresencePanel(40, 410);
    drawTimePanel(400, 410);
    drawBpmPanel(760, 360);
  }

  syphon.sendScreen();
}

// === Drawing helpers ===

void drawHeader() {
  fill(255);
  textAlign(LEFT, TOP);
  textSize(24);
  text("Synesthesia OSC Monitor", 64, 40);
  textSize(16);
  fill(hasConnection ? color(120, 255, 160) : color(255, 90, 90));
  String status = hasConnection ? "OSC Connected" : "Waiting for OSC";
  text(status + "  •  port " + listenPort, 64, 80);
  fill(180);
  text("FPS: " + round(frameRate), 64, 102);
}

void drawConnectionWarning() {
  fill(255, 80, 80);
  textSize(32);
  textAlign(CENTER, CENTER);
  text("No OSC packets received. Configure Synesthesia → Settings → OSC → Output Audio Variables.", width/2, height/2 - 30);
  textSize(20);
  fill(200);
  text("Target address: 127.0.0.1  •  Port: " + listenPort, width/2, height/2 + 10);
  textAlign(LEFT, TOP);
  textSize(16);
}

void drawLevelsPanel(float x, float y) {
  String[] labels = {"Bass", "Mid", "MidHigh", "High", "All", "Raw"};
  float[] values = {levelBass, levelMid, levelMidHigh, levelHigh, levelAll, levelRaw};
  int[] colors = {color(255, 110, 70), color(120, 255, 120), color(110, 200, 255), color(150, 120, 255), color(255), color(255, 200, 80)};

  drawPanel(x, y, 340, 260, "Level (instant)");
  float barW = 200;
  float barH = 22;
  float py = y + 48;
  textAlign(LEFT, CENTER);
  for (int i = 0; i < labels.length; i++) {
    fill(180);
    text(labels[i], x + 20, py + barH/2);
    fill(40);
    rect(x + 110, py, barW, barH);
    fill(colors[i]);
    float level = constrain(values[i], 0, 1);
    rect(x + 110, py, barW * level, barH);
    fill(200);
    text(fmt(level, 3), x + 110 + barW + 14, py + barH/2);
    py += barH + 10;
  }
}

void drawPresencePanel(float x, float y) {
  String[] labels = {"Bass", "Mid", "MidHigh", "High", "All"};
  float[] values = {presenceBass, presenceMid, presenceMidHigh, presenceHigh, presenceAll};
  drawPanel(x, y, 340, 230, "Presence (slow envelope)");
  float radius = 46;
  float baseX = x + 110;
  float baseY = y + 100;
  float spacingX = 85;
  float spacingY = 80;
  float[][] offsets = {
    {0f, 0f},
    {1f, 0f},
    {2f, 0f},
    {0.5f, 1f},
    {1.5f, 1f}
  };

  for (int i = 0; i < labels.length; i++) {
    float vx = baseX + offsets[i][0] * spacingX;
    float vy = baseY + offsets[i][1] * spacingY;
    float val = constrain(values[i], 0, 1);
    int c = color(100 + 80 * i, 200 - 40 * i, 255);
    fill(40);
    ellipse(vx, vy, radius, radius);
    fill(c, 150);
    float inner = max(radius * val, 6);
    ellipse(vx, vy, inner, inner);
    fill(200);
    textAlign(CENTER, CENTER);
    text(labels[i], vx, vy + radius/2 + 10);
    text(fmt(val, 2), vx, vy - radius/2 - 10);
  }
  textAlign(LEFT, TOP);
}

void drawHitsPanel(float x, float y) {
  String[] labels = {"Bass", "Mid", "MidHigh", "High", "All"};
  float[] values = {hitsBass, hitsMid, hitsMidHigh, hitsHigh, hitsAll};
  drawPanel(x, y, 340, 260, "Hits (transients)");
  float px = x + 60;
  float py = y + 70;
  float diameter = 66;
  for (int i = 0; i < labels.length; i++) {
    float val = constrain(values[i], 0, 1);
    int c = color(255, 150 - i * 20, 90 + i * 30);
    fill(40);
    ellipse(px, py, diameter, diameter);
    fill(c, 180);
    ellipse(px, py, diameter * val, diameter * val);
    fill(220);
    textAlign(CENTER, CENTER);
    text(labels[i], px, py + diameter / 2 + 16);
    text(fmt(val, 2), px, py - diameter / 2 - 12);
    px += 100;
    if ((i + 1) % 3 == 0) {
      px = x + 60;
      py += 110;
    }
  }
  textAlign(LEFT, TOP);
}

void drawTimePanel(float x, float y) {
  drawPanel(x, y, 340, 220, "Active Time (seconds)");
  float[] values = {timeBass, timeMid, timeMidHigh, timeHigh, timeAll, timeCurved};
  String[] labels = {"Bass", "Mid", "MidHigh", "High", "All", "Curved"};
  float py = y + 54;
  for (int i = 0; i < labels.length; i++) {
    fill(180);
    text(labels[i], x + 24, py);
    fill(220);
    text(fmt(values[i], 1), x + 170, py);
    py += 28;
  }
}

void drawBeatPanel(float x, float y) {
  drawPanel(x, y, 300, 260, "Beat Timeline");
  fill(180);
  text("beattime", x + 32, y + 56);
  fill(255, 220, 120);
  text(fmt(beatTime, 1), x + 150, y + 56);

  fill(180);
  text("onbeat", x + 32, y + 96);
  fill(beatOn > 0.75f ? color(255, 200, 120) : color(140, 180, 255));
  text(fmt(beatOn, 3), x + 150, y + 96);

  fill(180);
  text("random", x + 32, y + 136);
  fill(200);
  text(fmt(beatRandom, 3), x + 150, y + 136);

  // Beat arc visual
  float cx = x + 160;
  float cy = y + 200;
  float radius = 96;
  noFill();
  stroke(60);
  strokeWeight(4);
  ellipse(cx, cy, radius * 2, radius * 2);
  float progress = (beatTime % 8.0f) / 8.0f;
  stroke(255, 200, 120);
  arc(cx, cy, radius * 2, radius * 2, -HALF_PI, -HALF_PI + TWO_PI * progress);
  strokeWeight(1);
  fill(beatOn > 0.75f ? color(255, 180, 80) : color(80, 180, 255));
  ellipse(cx, cy, 30 + beatOn * 26, 30 + beatOn * 26);
  fill(200);
  textAlign(CENTER, CENTER);
  float beatIndex = floor(beatTime) % 8.0f;
  text("Beat " + fmt(beatIndex, 0), cx, cy);
  textAlign(LEFT, TOP);
}

void drawBpmPanel(float x, float y) {
  drawPanel(x, y, 360, 340, "BPM & LFO");
  fill(200);
  textSize(36);
  textAlign(LEFT, TOP);
  text(fmt(bpmValue, 2) + " BPM", x + 24, y + 56);
  textSize(14);
  fill(180);
  text("Confidence", x + 24, y + 108);
  fill(40);
  rect(x + 130, y + 108 - 6, 190, 10);
  fill(120, 250, 160);
  rect(x + 130, y + 108 - 6, 190 * constrain(bpmConfidence, 0, 1), 10);

  float py = y + 142;
  textSize(14);
  text("bpmtwitcher", x + 24, py);
  fill(220);
  text(fmt(bpmTwitcher, 2), x + 210, py);
  py += 24;

  String[] labels = {"bpmtri", "bpmtri2", "bpmtri4", "bpmtri8", "bpmsin", "bpmsin2", "bpmsin4", "bpmsin8"};
  float[] values = {bpmTri, bpmTri2, bpmTri4, bpmTri8, bpmSin, bpmSin2, bpmSin4, bpmSin8};

  for (int i = 0; i < labels.length; i++) {
    fill(180);
    text(labels[i], x + 24, py);
    float val = values[i];
    float normalized = constrain((val + 1.0f) * 0.5f, 0, 1);
    fill(40);
    rect(x + 130, py - 8, 190, 10);
    fill(120, 200, 255);
    rect(x + 130, py - 8, 190 * normalized, 10);
    fill(210);
    text(fmt(val, 3), x + 330, py);
    py += 22;
  }
  textSize(16);
}

void drawPanel(float x, float y, float w, float h, String title) {
  noStroke();
  fill(12, 12, 16, 240);
  rect(x, y, w, h, 12);
  fill(255);
  textSize(18);
  textAlign(LEFT, TOP);
  text(title, x + 24, y + 16);
  textSize(16);
}

// === OSC Handling ===

void oscEvent(OscMessage msg) {
  lastOscMillis = millis();
  String addr = msg.addrPattern();
  float val = msg.checkTypetag("f") ? msg.get(0).floatValue() : (msg.arguments().length > 0 ? msg.get(0).floatValue() : 0);

  switch(addr) {
  case "/audio/level/bass":
    levelBass = val;
    break;
  case "/audio/level/mid":
    levelMid = val;
    break;
  case "/audio/level/midhigh":
    levelMidHigh = val;
    break;
  case "/audio/level/high":
    levelHigh = val;
    break;
  case "/audio/level/all":
    levelAll = val;
    break;
  case "/audio/level/raw":
    levelRaw = val;
    break;

  case "/audio/presence/bass":
    presenceBass = val;
    break;
  case "/audio/presence/mid":
    presenceMid = val;
    break;
  case "/audio/presence/midhigh":
    presenceMidHigh = val;
    break;
  case "/audio/presence/high":
    presenceHigh = val;
    break;
  case "/audio/presence/all":
    presenceAll = val;
    break;

  case "/audio/hits/bass":
    hitsBass = lerp(hitsBass, val, 1 - smoothing);
    break;
  case "/audio/hits/mid":
    hitsMid = lerp(hitsMid, val, 1 - smoothing);
    break;
  case "/audio/hits/midhigh":
    hitsMidHigh = lerp(hitsMidHigh, val, 1 - smoothing);
    break;
  case "/audio/hits/high":
    hitsHigh = lerp(hitsHigh, val, 1 - smoothing);
    break;
  case "/audio/hits/all":
    hitsAll = lerp(hitsAll, val, 1 - smoothing);
    break;

  case "/audio/time/bass":
    timeBass = val;
    break;
  case "/audio/time/mid":
    timeMid = val;
    break;
  case "/audio/time/midhigh":
    timeMidHigh = val;
    break;
  case "/audio/time/high":
    timeHigh = val;
    break;
  case "/audio/time/all":
    timeAll = val;
    break;
  case "/audio/time/curved":
    timeCurved = val;
    break;

  case "/audio/energy/intensity":
    energyIntensity = val;
    break;

  case "/audio/beat/beattime":
    beatTime = val;
    break;
  case "/audio/beat/onbeat":
    beatOnPrev = beatOn;
    beatOn = val;
    break;
  case "/audio/beat/randomonbeat":
    beatRandom = val;
    break;

  case "/audio/bpm/bpm":
    bpmValue = val;
    break;
  case "/audio/bpm/bpmconfidence":
    bpmConfidence = val;
    break;
  case "/audio/bpm/bpmtwitcher":
    bpmTwitcher = val;
    break;
  case "/audio/bpm/bpmtri":
    bpmTri = val;
    break;
  case "/audio/bpm/bpmtri2":
    bpmTri2 = val;
    break;
  case "/audio/bpm/bpmtri4":
    bpmTri4 = val;
    break;
  case "/audio/bpm/bpmtri8":
    bpmTri8 = val;
    break;
  case "/audio/bpm/bpmsin":
    bpmSin = val;
    break;
  case "/audio/bpm/bpmsin2":
    bpmSin2 = val;
    break;
  case "/audio/bpm/bpmsin4":
    bpmSin4 = val;
    break;
  case "/audio/bpm/bpmsin8":
    bpmSin8 = val;
    break;

  default:
    // Ignored or unsupported address
    break;
  }
}

void keyPressed() {
  if (key == 'c' || key == 'C') {
    resetValues();
  }
}

void resetValues() {
  levelBass = levelMid = levelMidHigh = levelHigh = levelAll = levelRaw = 0;
  presenceBass = presenceMid = presenceMidHigh = presenceHigh = presenceAll = 0;
  hitsBass = hitsMid = hitsMidHigh = hitsHigh = hitsAll = 0;
  timeBass = timeMid = timeMidHigh = timeHigh = timeAll = timeCurved = 0;
  energyIntensity = 0;
  beatTime = beatOn = beatRandom = 0;
  bpmValue = bpmConfidence = 0;
  bpmTwitcher = bpmTri = bpmTri2 = bpmTri4 = bpmTri8 = 0;
  bpmSin = bpmSin2 = bpmSin4 = bpmSin8 = 0;
}
