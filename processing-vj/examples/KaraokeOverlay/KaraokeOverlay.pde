/**
 * Karaoke Overlay - Multi-Channel VJ Lyrics
 * 
 * Displays synced lyrics via OSC from Python Karaoke Engine.
 * Outputs 3 SEPARATE Syphon channels for Magic Music Visuals:
 *   - KaraokeFullLyrics   : Full lyrics with prev/current/next
 *   - KaraokeRefrain      : Chorus/refrain lines only  
 *   - KaraokeKeywords     : Key words extracted from lyrics
 * 
 * Requirements:
 * - Processing 4.x (Intel/x64 build for Apple Silicon)
 * - oscP5 library
 * - Syphon library
 * - Python Karaoke Engine running
 * 
 * OSC Channels Received:
 *   /karaoke/...          Full lyrics
 *   /karaoke/refrain/...  Chorus only
 *   /karaoke/keywords/... Key words only
 * 
 * Controls:
 * - 's': Toggle show/hide all
 * - '1': Toggle full lyrics
 * - '2': Toggle refrain
 * - '3': Toggle keywords
 * - 'f': Cycle font sizes
 * - 'c': Cycle color schemes
 * - 'r': Reset/reconnect OSC
 */

import oscP5.*;
import netP5.*;
import codeanticode.syphon.*;
import java.util.ArrayList;

// OSC
OscP5 osc;
int OSC_PORT = 9000;

// Three separate Syphon outputs - each can be selected in Magic
SyphonServer syphonFull;
SyphonServer syphonRefrain;
SyphonServer syphonKeywords;

// Off-screen buffers for each channel
PGraphics bufferFull;
PGraphics bufferRefrain;
PGraphics bufferKeywords;

// State for each channel
KaraokeState stateFull;
RefrainState stateRefrain;
KeywordsState stateKeywords;

// Visibility toggles
boolean showFull = true;
boolean showRefrain = true;
boolean showKeywords = true;

// Visual settings
int fontSizeIndex = 1;
int[] fontSizes = {32, 48, 64, 80};
int colorSchemeIndex = 0;

// Animation
float fadeAmount = 0;
float targetFade = 1;
float pulsePhase = 0;

void settings() {
  size(1920, 1080, P3D);  // Full HD, P3D required for Syphon
}

void setup() {
  colorMode(HSB, 360, 100, 100, 100);
  textAlign(CENTER, CENTER);
  
  // Initialize states
  stateFull = new KaraokeState();
  stateRefrain = new RefrainState();
  stateKeywords = new KeywordsState();
  
  // Initialize OSC receiver
  osc = new OscP5(this, OSC_PORT);
  println("OSC listening on port " + OSC_PORT);
  
  // Create off-screen buffers for each Syphon output
  bufferFull = createGraphics(1920, 1080, P3D);
  bufferRefrain = createGraphics(1920, 1080, P3D);
  bufferKeywords = createGraphics(1920, 1080, P3D);
  
  // Initialize THREE separate Syphon servers
  syphonFull = new SyphonServer(this, "KaraokeFullLyrics");
  syphonRefrain = new SyphonServer(this, "KaraokeRefrain");
  syphonKeywords = new SyphonServer(this, "KaraokeKeywords");
  
  println("Syphon outputs: KaraokeFullLyrics, KaraokeRefrain, KaraokeKeywords");
  
  // Load fonts
  textFont(createFont("Arial", 64));
}

void draw() {
  // Animation updates
  fadeAmount = lerp(fadeAmount, targetFade, 0.1);
  pulsePhase += 0.05;
  
  // Clear main display
  background(0);
  
  // Render each channel to its buffer
  renderFullLyrics();
  renderRefrain();
  renderKeywords();
  
  // Show preview on main display (composited)
  tint(255, showFull ? 255 : 50);
  image(bufferFull, 0, 0);
  
  // Send each buffer to its own Syphon server
  syphonFull.sendImage(bufferFull);
  syphonRefrain.sendImage(bufferRefrain);
  syphonKeywords.sendImage(bufferKeywords);
}

// ========== FULL LYRICS CHANNEL ==========

void renderFullLyrics() {
  bufferFull.beginDraw();
  bufferFull.colorMode(HSB, 360, 100, 100, 100);
  bufferFull.background(0);
  bufferFull.textAlign(CENTER, CENTER);
  bufferFull.textFont(createFont("Arial", 64));
  
  if (!showFull || !stateFull.active) {
    bufferFull.endDraw();
    return;
  }
  
  int fontSize = fontSizes[fontSizeIndex];
  float lineHeight = fontSize * 1.4;
  color[] scheme = getColorScheme(colorSchemeIndex);
  
  // Title/artist at top
  bufferFull.textSize(fontSize * 0.6);
  bufferFull.fill(scheme[0], 60 * fadeAmount);
  bufferFull.text(stateFull.artist + " — " + stateFull.title, width / 2, 60);
  
  if (!stateFull.hasSyncedLyrics || stateFull.lines.size() == 0) {
    bufferFull.textSize(fontSize * 0.8);
    bufferFull.fill(scheme[0], 50 * fadeAmount);
    bufferFull.text("♪ No synced lyrics", width / 2, height / 2);
    bufferFull.endDraw();
    return;
  }
  
  int active = stateFull.activeIndex >= 0 ? stateFull.activeIndex : computeActiveLine(stateFull);
  float centerY = height / 2;
  
  // Previous line
  if (active > 0) {
    bufferFull.textSize(fontSize * 0.8);
    bufferFull.fill(scheme[0], 40 * fadeAmount);
    bufferFull.text(stateFull.lines.get(active - 1).text, width / 2, centerY - lineHeight * 1.2);
  }
  
  // Current line with glow
  if (active >= 0 && active < stateFull.lines.size()) {
    float pulse = 1 + sin(pulsePhase) * 0.03;
    for (int i = 3; i > 0; i--) {
      bufferFull.fill(scheme[2], 15 * fadeAmount);
      bufferFull.textSize(fontSize * pulse + i * 3);
      bufferFull.text(stateFull.lines.get(active).text, width / 2, centerY);
    }
    bufferFull.fill(scheme[1], 100 * fadeAmount);
    bufferFull.textSize(fontSize * pulse);
    bufferFull.text(stateFull.lines.get(active).text, width / 2, centerY);
  }
  
  // Next lines
  if (active >= 0 && active < stateFull.lines.size() - 1) {
    bufferFull.textSize(fontSize * 0.8);
    bufferFull.fill(scheme[0], 50 * fadeAmount);
    bufferFull.text(stateFull.lines.get(active + 1).text, width / 2, centerY + lineHeight * 1.2);
  }
  
  // Progress bar
  if (stateFull.durationSec > 0) {
    float progress = stateFull.positionSec / stateFull.durationSec;
    float barW = width * 0.6;
    float barX = (width - barW) / 2;
    bufferFull.noStroke();
    bufferFull.fill(255, 20 * fadeAmount);
    bufferFull.rect(barX, height - 50, barW, 4, 2);
    bufferFull.fill(255, 60 * fadeAmount);
    bufferFull.rect(barX, height - 50, barW * progress, 4, 2);
  }
  
  bufferFull.endDraw();
}

// ========== REFRAIN CHANNEL ==========

void renderRefrain() {
  bufferRefrain.beginDraw();
  bufferRefrain.colorMode(HSB, 360, 100, 100, 100);
  bufferRefrain.background(0);
  bufferRefrain.textAlign(CENTER, CENTER);
  bufferRefrain.textFont(createFont("Arial", 80));
  
  if (!showRefrain || !stateRefrain.active || stateRefrain.currentText.isEmpty()) {
    bufferRefrain.endDraw();
    return;
  }
  
  int fontSize = fontSizes[fontSizeIndex] + 16;  // Larger for refrain
  float pulse = 1 + sin(pulsePhase * 1.5) * 0.05;  // Stronger pulse
  
  // Refrain gets a special dramatic color
  color refrainColor = color(320, 80, 100);  // Magenta
  color glowColor = color(340, 100, 100);
  
  // Big glow effect
  for (int i = 5; i > 0; i--) {
    bufferRefrain.fill(glowColor, 10 * fadeAmount);
    bufferRefrain.textSize(fontSize * pulse + i * 5);
    bufferRefrain.text(stateRefrain.currentText, width / 2, height / 2);
  }
  
  // Main text
  bufferRefrain.fill(refrainColor, 100 * fadeAmount);
  bufferRefrain.textSize(fontSize * pulse);
  bufferRefrain.text(stateRefrain.currentText, width / 2, height / 2);
  
  // "REFRAIN" label
  bufferRefrain.textSize(14);
  bufferRefrain.fill(refrainColor, 50 * fadeAmount);
  bufferRefrain.text("♪ REFRAIN ♪", width / 2, height - 60);
  
  bufferRefrain.endDraw();
}

// ========== KEYWORDS CHANNEL ==========

void renderKeywords() {
  bufferKeywords.beginDraw();
  bufferKeywords.colorMode(HSB, 360, 100, 100, 100);
  bufferKeywords.background(0);
  bufferKeywords.textAlign(CENTER, CENTER);
  bufferKeywords.textFont(createFont("Arial Bold", 100));
  
  if (!showKeywords || !stateKeywords.active || stateKeywords.currentKeywords.isEmpty()) {
    bufferKeywords.endDraw();
    return;
  }
  
  int fontSize = fontSizes[fontSizeIndex] + 32;  // Even larger for keywords
  float pulse = 1 + sin(pulsePhase * 2) * 0.08;  // Strong pulse
  
  // Keywords get bold cyan/white
  color keyColor = color(180, 60, 100);  // Cyan
  color glowColor = color(180, 100, 100);
  
  // Strong glow
  for (int i = 6; i > 0; i--) {
    bufferKeywords.fill(glowColor, 8 * fadeAmount);
    bufferKeywords.textSize(fontSize * pulse + i * 6);
    bufferKeywords.text(stateKeywords.currentKeywords, width / 2, height / 2);
  }
  
  // Main text
  bufferKeywords.fill(keyColor, 100 * fadeAmount);
  bufferKeywords.textSize(fontSize * pulse);
  bufferKeywords.text(stateKeywords.currentKeywords, width / 2, height / 2);
  
  bufferKeywords.endDraw();
}

String formatTime(float seconds) {
  int mins = (int)(seconds / 60);
  int secs = (int)(seconds % 60);
  return nf(mins, 1) + ":" + nf(secs, 2);
}

int computeActiveLine(KaraokeState s) {
  if (s.lines.size() == 0) return -1;
  int active = -1;
  for (int i = 0; i < s.lines.size(); i++) {
    if (s.lines.get(i).timeSec <= s.positionSec) {
      active = i;
    } else {
      break;
    }
  }
  return active;
}

color[] getColorScheme(int index) {
  switch (index % 4) {
    case 0: return new color[]{color(0, 0, 60), color(0, 0, 100), color(180, 50, 100)};
    case 1: return new color[]{color(300, 30, 60), color(320, 60, 100), color(340, 80, 100)};
    case 2: return new color[]{color(120, 30, 50), color(120, 70, 100), color(90, 90, 100)};
    case 3: return new color[]{color(30, 40, 60), color(30, 80, 100), color(45, 100, 100)};
    default: return new color[]{color(0, 0, 60), color(0, 0, 100), color(180, 50, 100)};
  }
}

// ========== OSC EVENT HANDLER ==========

void oscEvent(OscMessage msg) {
  String addr = msg.addrPattern();
  
  try {
    // === Full lyrics channel ===
    if (addr.equals("/karaoke/track")) {
      stateFull.active = msg.get(0).intValue() == 1;
      stateRefrain.active = stateFull.active;
      stateKeywords.active = stateFull.active;
      stateFull.source = msg.get(1).stringValue();
      stateFull.artist = msg.get(2).stringValue();
      stateFull.title = msg.get(3).stringValue();
      stateFull.album = msg.get(4).stringValue();
      stateFull.durationSec = msg.get(5).floatValue();
      stateFull.hasSyncedLyrics = msg.get(6).intValue() == 1;
      targetFade = stateFull.active ? 1 : 0;
      if (stateFull.active) println("Track: " + stateFull.artist + " - " + stateFull.title);
    }
    else if (addr.equals("/karaoke/lyrics/reset")) {
      stateFull.lines.clear();
      stateFull.activeIndex = -1;
    }
    else if (addr.equals("/karaoke/lyrics/line")) {
      int idx = msg.get(0).intValue();
      float t = msg.get(1).floatValue();
      String txt = msg.get(2).stringValue();
      while (stateFull.lines.size() <= idx) stateFull.lines.add(new LyricLine(0, ""));
      stateFull.lines.set(idx, new LyricLine(t, txt));
    }
    else if (addr.equals("/karaoke/pos")) {
      stateFull.positionSec = msg.get(0).floatValue();
      stateFull.isPlaying = msg.get(1).intValue() == 1;
    }
    else if (addr.equals("/karaoke/line/active")) {
      stateFull.activeIndex = msg.get(0).intValue();
    }
    
    // === Refrain channel ===
    else if (addr.equals("/karaoke/refrain/reset")) {
      stateRefrain.lines.clear();
    }
    else if (addr.equals("/karaoke/refrain/line")) {
      int idx = msg.get(0).intValue();
      float t = msg.get(1).floatValue();
      String txt = msg.get(2).stringValue();
      while (stateRefrain.lines.size() <= idx) stateRefrain.lines.add(new LyricLine(0, ""));
      stateRefrain.lines.set(idx, new LyricLine(t, txt));
    }
    else if (addr.equals("/karaoke/refrain/active")) {
      stateRefrain.activeIndex = msg.get(0).intValue();
      if (msg.typetag().length() > 1) {
        stateRefrain.currentText = msg.get(1).stringValue();
      }
    }
    
    // === Keywords channel ===
    else if (addr.equals("/karaoke/keywords/reset")) {
      stateKeywords.lines.clear();
    }
    else if (addr.equals("/karaoke/keywords/line")) {
      int idx = msg.get(0).intValue();
      float t = msg.get(1).floatValue();
      String kw = msg.get(2).stringValue();
      while (stateKeywords.lines.size() <= idx) stateKeywords.lines.add(new LyricLine(0, ""));
      stateKeywords.lines.set(idx, new LyricLine(t, kw));
    }
    else if (addr.equals("/karaoke/keywords/active")) {
      stateKeywords.activeIndex = msg.get(0).intValue();
      if (msg.typetag().length() > 1) {
        stateKeywords.currentKeywords = msg.get(1).stringValue();
      }
    }
    
  } catch (Exception e) {
    println("OSC error: " + e.getMessage());
  }
}

// ========== KEYBOARD CONTROLS ==========

void keyPressed() {
  if (key == 's' || key == 'S') {
    showFull = !showFull;
    showRefrain = showFull;
    showKeywords = showFull;
    println("All channels: " + (showFull ? "visible" : "hidden"));
  }
  else if (key == '1') {
    showFull = !showFull;
    println("Full lyrics: " + (showFull ? "visible" : "hidden"));
  }
  else if (key == '2') {
    showRefrain = !showRefrain;
    println("Refrain: " + (showRefrain ? "visible" : "hidden"));
  }
  else if (key == '3') {
    showKeywords = !showKeywords;
    println("Keywords: " + (showKeywords ? "visible" : "hidden"));
  }
  else if (key == 'f' || key == 'F') {
    fontSizeIndex = (fontSizeIndex + 1) % fontSizes.length;
    println("Font size: " + fontSizes[fontSizeIndex]);
  }
  else if (key == 'c' || key == 'C') {
    colorSchemeIndex = (colorSchemeIndex + 1) % 4;
    println("Color scheme: " + colorSchemeIndex);
  }
  else if (key == 'r' || key == 'R') {
    osc.stop();
    osc = new OscP5(this, OSC_PORT);
    println("OSC reconnected on port " + OSC_PORT);
  }
}

// ========== DATA CLASSES ==========

class LyricLine {
  float timeSec;
  String text;
  LyricLine(float t, String txt) { timeSec = t; text = txt; }
}

class KaraokeState {
  boolean active = false;
  String source = "", artist = "", title = "", album = "";
  float durationSec = 0, positionSec = 0;
  boolean isPlaying = false, hasSyncedLyrics = false;
  ArrayList<LyricLine> lines = new ArrayList<LyricLine>();
  int activeIndex = -1;
}

class RefrainState {
  boolean active = false;
  ArrayList<LyricLine> lines = new ArrayList<LyricLine>();
  int activeIndex = -1;
  String currentText = "";
}

class KeywordsState {
  boolean active = false;
  ArrayList<LyricLine> lines = new ArrayList<LyricLine>();
  int activeIndex = -1;
  String currentKeywords = "";
}
