/**
 * Karaoke Overlay - Multi-Channel VJ Lyrics
 * 
 * White text on black background for clean VJ compositing.
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

// Animation
float fadeAmount = 0;
float targetFade = 1;

void settings() {
  size(1920, 1080, P3D);  // Full HD, P3D required for Syphon
}

void setup() {
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
  bufferFull.background(0);
  bufferFull.textAlign(CENTER, CENTER);
  bufferFull.textFont(createFont("Arial", 64));
  
  if (!showFull || !stateFull.active) {
    bufferFull.endDraw();
    return;
  }
  
  int fontSize = fontSizes[fontSizeIndex];
  float lineHeight = fontSize * 1.4;
  
  // Title/artist at top - dim white
  bufferFull.textSize(fontSize * 0.6);
  bufferFull.fill(255, 150 * fadeAmount);
  bufferFull.text(stateFull.artist + " — " + stateFull.title, width / 2, 60);
  
  if (!stateFull.hasSyncedLyrics || stateFull.lines.size() == 0) {
    bufferFull.textSize(fontSize * 0.8);
    bufferFull.fill(255, 120 * fadeAmount);
    bufferFull.text("No synced lyrics", width / 2, height / 2);
    bufferFull.endDraw();
    return;
  }
  
  int active = stateFull.activeIndex >= 0 ? stateFull.activeIndex : computeActiveLine(stateFull);
  float centerY = height / 2;
  
  // Previous line - dim white
  if (active > 0) {
    bufferFull.textSize(fontSize * 0.8);
    bufferFull.fill(255, 100 * fadeAmount);
    bufferFull.text(stateFull.lines.get(active - 1).text, width / 2, centerY - lineHeight * 1.2);
  }
  
  // Current line - bright white
  if (active >= 0 && active < stateFull.lines.size()) {
    bufferFull.fill(255, 255 * fadeAmount);
    bufferFull.textSize(fontSize);
    bufferFull.text(stateFull.lines.get(active).text, width / 2, centerY);
  }
  
  // Next line - dim white
  if (active >= 0 && active < stateFull.lines.size() - 1) {
    bufferFull.textSize(fontSize * 0.8);
    bufferFull.fill(255, 120 * fadeAmount);
    bufferFull.text(stateFull.lines.get(active + 1).text, width / 2, centerY + lineHeight * 1.2);
  }
  
  // Progress bar - white
  if (stateFull.durationSec > 0) {
    float progress = stateFull.positionSec / stateFull.durationSec;
    float barW = width * 0.6;
    float barX = (width - barW) / 2;
    bufferFull.noStroke();
    bufferFull.fill(255, 50 * fadeAmount);
    bufferFull.rect(barX, height - 50, barW, 4, 2);
    bufferFull.fill(255, 150 * fadeAmount);
    bufferFull.rect(barX, height - 50, barW * progress, 4, 2);
  }
  
  bufferFull.endDraw();
}

// ========== REFRAIN CHANNEL ==========

void renderRefrain() {
  bufferRefrain.beginDraw();
  bufferRefrain.background(0);
  bufferRefrain.textAlign(CENTER, CENTER);
  bufferRefrain.textFont(createFont("Arial", 80));
  
  if (!showRefrain || !stateRefrain.active || stateRefrain.currentText.isEmpty()) {
    bufferRefrain.endDraw();
    return;
  }
  
  int fontSize = fontSizes[fontSizeIndex] + 16;  // Larger for refrain
  
  // Main text - bright white
  bufferRefrain.fill(255, 255 * fadeAmount);
  bufferRefrain.textSize(fontSize);
  bufferRefrain.text(stateRefrain.currentText, width / 2, height / 2);
  
  bufferRefrain.endDraw();
}

// ========== KEYWORDS CHANNEL ==========

void renderKeywords() {
  bufferKeywords.beginDraw();
  bufferKeywords.background(0);
  bufferKeywords.textAlign(CENTER, CENTER);
  bufferKeywords.textFont(createFont("Arial Bold", 100));
  
  if (!showKeywords || !stateKeywords.active || stateKeywords.currentKeywords.isEmpty()) {
    bufferKeywords.endDraw();
    return;
  }
  
  int fontSize = fontSizes[fontSizeIndex] + 32;  // Even larger for keywords
  
  // Main text - bright white
  bufferKeywords.fill(255, 255 * fadeAmount);
  bufferKeywords.textSize(fontSize);
  bufferKeywords.text(stateKeywords.currentKeywords, width / 2, height / 2);
  
  bufferKeywords.endDraw();
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
