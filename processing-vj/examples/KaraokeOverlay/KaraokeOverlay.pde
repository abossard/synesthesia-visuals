/**
 * Karaoke Overlay
 * 
 * A VJ overlay that displays synced lyrics received via OSC from the
 * Python Karaoke Engine. Perfect for live VJ sets with song lyrics.
 * 
 * Requirements:
 * - Processing 4.x (Intel/x64 build for Apple Silicon)
 * - oscP5 library (Sketch → Import Library → Add Library → oscP5)
 * - Syphon library
 * - Python Karaoke Engine running (python-vj/karaoke_engine.py)
 * 
 * OSC Messages Received:
 * - /karaoke/track [is_active, source, artist, title, album, duration, has_synced_lyrics]
 * - /karaoke/lyrics/reset [song_id]
 * - /karaoke/lyrics/line [index, time_sec, text]
 * - /karaoke/pos [position_sec, is_playing]
 * - /karaoke/line/active [index]
 * 
 * Controls:
 * - 's': Toggle show/hide overlay
 * - 'f': Cycle font sizes
 * - 'c': Cycle color schemes
 * - 'r': Reset/reconnect OSC
 * 
 * VJ Output:
 * - 1920x1080 Full HD via Syphon
 * - Black background for overlay compositing
 */

import oscP5.*;
import netP5.*;
import codeanticode.syphon.*;
import java.util.ArrayList;

// OSC
OscP5 osc;
int OSC_PORT = 9000;

// Syphon
SyphonServer syphon;

// State
KaraokeState state;
boolean overlayVisible = true;

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
  
  // Initialize state
  state = new KaraokeState();
  
  // Initialize OSC receiver
  osc = new OscP5(this, OSC_PORT);
  println("OSC listening on port " + OSC_PORT);
  
  // Initialize Syphon
  syphon = new SyphonServer(this, "KaraokeOverlay");
  
  // Load fonts
  textFont(createFont("Arial", 64));
}

void draw() {
  // Semi-transparent background for trail effect
  background(0);
  
  // Animation updates
  fadeAmount = lerp(fadeAmount, targetFade, 0.1);
  pulsePhase += 0.05;
  
  if (overlayVisible && state.active) {
    drawKaraokeOverlay();
  }
  
  // Send to Syphon
  syphon.sendScreen();
}

void drawKaraokeOverlay() {
  int fontSize = fontSizes[fontSizeIndex];
  float lineHeight = fontSize * 1.4;
  
  // Get colors based on scheme
  color[] scheme = getColorScheme(colorSchemeIndex);
  color dimColor = scheme[0];
  color currentColor = scheme[1];
  color highlightColor = scheme[2];
  
  // Draw title/artist at top
  textSize(fontSize * 0.6);
  fill(dimColor, 60 * fadeAmount);
  String trackInfo = state.artist + " — " + state.title;
  text(trackInfo, width / 2, 60);
  
  if (!state.hasSyncedLyrics || state.lines.size() == 0) {
    // No synced lyrics - show message
    textSize(fontSize * 0.8);
    fill(dimColor, 50 * fadeAmount);
    text("♪ No synced lyrics available", width / 2, height / 2);
    return;
  }
  
  // Calculate active line if not provided
  int activeIndex = state.activeIndex;
  if (activeIndex < 0) {
    activeIndex = computeActiveLine();
  }
  
  // Vertical center position
  float centerY = height / 2;
  
  // Previous line (above)
  if (activeIndex > 0) {
    textSize(fontSize * 0.8);
    fill(dimColor, 40 * fadeAmount);
    String prevText = state.lines.get(activeIndex - 1).text;
    text(prevText, width / 2, centerY - lineHeight * 1.2);
  }
  
  // Current line (center, highlighted)
  if (activeIndex >= 0 && activeIndex < state.lines.size()) {
    textSize(fontSize);
    
    // Pulse effect on beat
    float pulse = 1 + sin(pulsePhase) * 0.03;
    
    // Glow effect
    for (int i = 3; i > 0; i--) {
      fill(highlightColor, 15 * fadeAmount);
      textSize(fontSize * pulse + i * 3);
      text(state.lines.get(activeIndex).text, width / 2, centerY);
    }
    
    // Main text
    fill(currentColor, 100 * fadeAmount);
    textSize(fontSize * pulse);
    text(state.lines.get(activeIndex).text, width / 2, centerY);
  }
  
  // Next line (below)
  if (activeIndex >= 0 && activeIndex < state.lines.size() - 1) {
    textSize(fontSize * 0.8);
    fill(dimColor, 50 * fadeAmount);
    String nextText = state.lines.get(activeIndex + 1).text;
    text(nextText, width / 2, centerY + lineHeight * 1.2);
  }
  
  // Second next line (even more dim)
  if (activeIndex >= 0 && activeIndex < state.lines.size() - 2) {
    textSize(fontSize * 0.6);
    fill(dimColor, 25 * fadeAmount);
    String nextText2 = state.lines.get(activeIndex + 2).text;
    text(nextText2, width / 2, centerY + lineHeight * 2);
  }
  
  // Progress indicator (bottom)
  drawProgressBar();
}

void drawProgressBar() {
  if (state.durationSec <= 0) return;
  
  float progress = state.positionSec / state.durationSec;
  float barWidth = width * 0.6;
  float barHeight = 4;
  float x = (width - barWidth) / 2;
  float y = height - 50;
  
  // Background bar
  noStroke();
  fill(255, 20 * fadeAmount);
  rect(x, y, barWidth, barHeight, barHeight/2);
  
  // Progress bar
  fill(255, 60 * fadeAmount);
  rect(x, y, barWidth * progress, barHeight, barHeight/2);
  
  // Time display
  textSize(14);
  fill(255, 40 * fadeAmount);
  textAlign(LEFT, CENTER);
  text(formatTime(state.positionSec), x, y + 20);
  textAlign(RIGHT, CENTER);
  text(formatTime(state.durationSec), x + barWidth, y + 20);
  textAlign(CENTER, CENTER);
}

String formatTime(float seconds) {
  int mins = (int)(seconds / 60);
  int secs = (int)(seconds % 60);
  return nf(mins, 1) + ":" + nf(secs, 2);
}

int computeActiveLine() {
  if (state.lines.size() == 0) return -1;
  
  int active = -1;
  for (int i = 0; i < state.lines.size(); i++) {
    if (state.lines.get(i).timeSec <= state.positionSec) {
      active = i;
    } else {
      break;
    }
  }
  return active;
}

color[] getColorScheme(int index) {
  // Returns [dim, current, highlight]
  switch (index % 4) {
    case 0: // White/cyan
      return new color[]{color(0, 0, 60), color(0, 0, 100), color(180, 50, 100)};
    case 1: // Pink/magenta
      return new color[]{color(300, 30, 60), color(320, 60, 100), color(340, 80, 100)};
    case 2: // Green/lime
      return new color[]{color(120, 30, 50), color(120, 70, 100), color(90, 90, 100)};
    case 3: // Orange/gold
      return new color[]{color(30, 40, 60), color(30, 80, 100), color(45, 100, 100)};
    default:
      return new color[]{color(0, 0, 60), color(0, 0, 100), color(180, 50, 100)};
  }
}

// ========== OSC Event Handler ==========

void oscEvent(OscMessage msg) {
  String addr = msg.addrPattern();
  
  try {
    if (addr.equals("/karaoke/track")) {
      handleTrackMessage(msg);
    }
    else if (addr.equals("/karaoke/lyrics/reset")) {
      handleLyricsReset(msg);
    }
    else if (addr.equals("/karaoke/lyrics/line")) {
      handleLyricLine(msg);
    }
    else if (addr.equals("/karaoke/pos")) {
      handlePosition(msg);
    }
    else if (addr.equals("/karaoke/line/active")) {
      handleActiveLine(msg);
    }
  } catch (Exception e) {
    println("OSC error: " + e.getMessage());
  }
}

void handleTrackMessage(OscMessage msg) {
  state.active = msg.get(0).intValue() == 1;
  state.source = msg.get(1).stringValue();
  state.artist = msg.get(2).stringValue();
  state.title = msg.get(3).stringValue();
  state.album = msg.get(4).stringValue();
  state.durationSec = msg.get(5).floatValue();
  state.hasSyncedLyrics = msg.get(6).intValue() == 1;
  
  if (state.active) {
    println("Track: " + state.artist + " - " + state.title);
    targetFade = 1;
  } else {
    targetFade = 0;
  }
}

void handleLyricsReset(OscMessage msg) {
  String songId = msg.get(0).stringValue();
  state.lines.clear();
  state.activeIndex = -1;
  println("Lyrics reset for: " + songId);
}

void handleLyricLine(OscMessage msg) {
  int index = msg.get(0).intValue();
  float timeSec = msg.get(1).floatValue();
  String text = msg.get(2).stringValue();
  
  // Ensure list is large enough
  while (state.lines.size() <= index) {
    state.lines.add(new LyricLine(0, ""));
  }
  
  state.lines.set(index, new LyricLine(timeSec, text));
}

void handlePosition(OscMessage msg) {
  state.positionSec = msg.get(0).floatValue();
  state.isPlaying = msg.get(1).intValue() == 1;
}

void handleActiveLine(OscMessage msg) {
  state.activeIndex = msg.get(0).intValue();
}

// ========== Keyboard Controls ==========

void keyPressed() {
  if (key == 's' || key == 'S') {
    overlayVisible = !overlayVisible;
    println("Overlay visible: " + overlayVisible);
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
    // Reconnect OSC
    osc.stop();
    osc = new OscP5(this, OSC_PORT);
    println("OSC reconnected on port " + OSC_PORT);
  }
}

// ========== Data Classes ==========

class LyricLine {
  float timeSec;
  String text;
  
  LyricLine(float timeSec, String text) {
    this.timeSec = timeSec;
    this.text = text;
  }
}

class KaraokeState {
  boolean active = false;
  String source = "";
  String artist = "";
  String title = "";
  String album = "";
  float durationSec = 0;
  float positionSec = 0;
  boolean isPlaying = false;
  boolean hasSyncedLyrics = false;
  ArrayList<LyricLine> lines = new ArrayList<LyricLine>();
  int activeIndex = -1;
}
