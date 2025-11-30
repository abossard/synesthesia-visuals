/**
 * Karaoke Overlay - Multi-Channel VJ Lyrics
 * 
 * White text on black background for clean VJ compositing.
 * Outputs 3 SEPARATE Syphon channels for Magic Music Visuals:
 *   - KaraokeFullLyrics   : Full lyrics with prev/current/next
 *   - KaraokeRefrain      : Chorus/refrain lines only (AI-detected)
 *   - KaraokeSongInfo     : Artist & Song Title (brief display on track change)
 * 
 * Requirements:
 * - Processing 4.x (Intel/x64 build for Apple Silicon)
 * - oscP5 library
 * - Syphon library
 * - Python Karaoke Engine (karaoke_engine.py)
 * 
 * OSC Protocol (sent by karaoke_engine.py):
 *   /karaoke/track [active, source, artist, title, album, duration, has_lyrics]
 *   /karaoke/pos [position, playing]
 *   /karaoke/lyrics/reset [song_id]
 *   /karaoke/lyrics/line [index, time_sec, text]
 *   /karaoke/line/active [index]
 *   /karaoke/refrain/reset [song_id]
 *   /karaoke/refrain/line [index, time_sec, text]
 *   /karaoke/refrain/active [index, text]
 * 
 * Controls:
 * - 's': Toggle show/hide all
 * - '1': Toggle full lyrics
 * - '2': Toggle refrain
 * - '3': Toggle song info
 * - 'f': Cycle fonts (uses system fonts via PFont.list)
 * - 'g': Cycle font sizes
 * - 'r': Reset/reconnect OSC
 * - 't': Type a broadcast message (Enter to send to all outputs)
 */

import oscP5.*;
import netP5.*;
import codeanticode.syphon.*;
import java.util.ArrayList;
import java.util.HashMap;
import java.io.File;
import processing.core.PConstants;
import java.awt.Font;

// OSC
OscP5 osc;
int OSC_PORT = 9000;

// Three separate Syphon outputs - each can be selected in Magic
SyphonServer syphonFull;
SyphonServer syphonRefrain;
SyphonServer syphonSongInfo;

// Off-screen buffers for each channel
PGraphics bufferFull;
PGraphics bufferRefrain;
PGraphics bufferSongInfo;

// State for each channel
KaraokeState stateFull;
RefrainState stateRefrain;
SongInfoState stateSongInfo;

// OSC connection monitoring
long lastOscMessageTime = 0;
boolean oscConnected = false;
final long OSC_TIMEOUT_MS = 5000;  // 5 seconds without messages = disconnected

// Operator overlay + broadcast message
boolean typingBroadcast = false;  // Capture text input until Enter/Esc
String broadcastInput = "";
String broadcastMessage = "";
PFont hudFont;
PFont currentFont;
String[] availableFonts;
int fontIndex = 0;
final String SETTINGS_FILE = "karaoke_font_settings.txt";
final HashMap<String, PFont> fontCache = new HashMap<String, PFont>();

// Visual settings (scaled for HD Ready 1280x720)
int fontSizeIndex = 1;
int[] fontSizes = {24, 36, 48, 60};

// Animation
float fadeAmount = 0;
float targetFade = 1;

void settings() {
  size(1280, 720, P3D);  // HD Ready (1280x720), P3D required for Syphon
}

void setup() {
  textAlign(CENTER, CENTER);
  
  // Initialize states
  stateFull = new KaraokeState();
  stateRefrain = new RefrainState();
  stateSongInfo = new SongInfoState();
  
  // Initialize OSC receiver
  osc = new OscP5(this, OSC_PORT);
  println("OSC listening on port " + OSC_PORT);
  
  // Create off-screen buffers for each Syphon output
  bufferFull = createGraphics(1280, 720, P3D);
  bufferRefrain = createGraphics(1280, 720, P3D);
  bufferSongInfo = createGraphics(1280, 720, P3D);
  
  // Initialize THREE separate Syphon servers
  syphonFull = new SyphonServer(this, "KaraokeFullLyrics");
  syphonRefrain = new SyphonServer(this, "KaraokeRefrain");
  syphonSongInfo = new SyphonServer(this, "KaraokeSongInfo");
  
  println("Syphon outputs: KaraokeFullLyrics, KaraokeRefrain, KaraokeSongInfo");
  
  // Load fonts (scaled for HD Ready)
  availableFonts = PFont.list();
  if (availableFonts == null || availableFonts.length == 0) {
    availableFonts = new String[] { "Arial", "SansSerif" };
  }
  hudFont = createFont("Arial", 16);
  loadFontSettings();
  applyFontSelection();
}

void draw() {
  // Check OSC connection status
  if (millis() - lastOscMessageTime > OSC_TIMEOUT_MS) {
    oscConnected = false;
  }
  
  // Animation updates
  fadeAmount = lerp(fadeAmount, targetFade, 0.1);
  
  // Update text fade timers
  updateTextFades();
  
  // Clear main display
  background(0);
  
  // Show OSC disconnected warning if no recent messages
  if (!oscConnected && lastOscMessageTime > 0) {
    fill(255, 100);
    textAlign(CENTER, CENTER);
    textFont(hudFont);
    textSize(24);
    text("⚠ OSC Disconnected\nPress 'r' to reconnect", width/2, 100);
  }
  
  // Render each channel to its buffer
  renderFullLyrics();
  renderRefrain();
  renderSongInfo();
  
  // Show preview on main display with additive blending (black = transparent, white accumulates)
  blendMode(ADD);
  
  // Always draw all three channels
  tint(255, 255);
  image(bufferFull, 0, 0);
  image(bufferRefrain, 0, 0);
  image(bufferSongInfo, 0, 0);
  
  noTint();
  blendMode(BLEND);  // Reset to normal blending

  drawHUD();
  
  // Send each buffer to its own Syphon server
  syphonFull.sendImage(bufferFull);
  syphonRefrain.sendImage(bufferRefrain);
  syphonSongInfo.sendImage(bufferSongInfo);
}

// ========== FULL LYRICS CHANNEL ==========

void renderFullLyrics() {
  bufferFull.beginDraw();
  bufferFull.background(0);
  bufferFull.textAlign(CENTER, TOP);
  bufferFull.textFont(currentFont);
  
  if (stateFull.active) {
    int fontSize = fontSizes[fontSizeIndex];
    float lineHeight = fontSize * 1.4;
    float maxWidth = bufferFull.width * 0.86;
    
    // Title/artist at top - pure white
    bufferFull.textSize(fontSize * 0.6);
    bufferFull.fill(255, stateFull.textOpacity);
    bufferFull.text(stateFull.artist + " — " + stateFull.title, bufferFull.width / 2, 60);
  
    if (!stateFull.hasSyncedLyrics || stateFull.lines.size() == 0) {
      bufferFull.textSize(fontSize * 0.8);
      bufferFull.fill(255, stateFull.textOpacity);
      drawWrappedBlock(bufferFull, "No synced lyrics", bufferFull.width / 2, bufferFull.height / 2, maxWidth, fontSize * 0.8, fontSize * 1.0);
      drawBroadcastMessage(bufferFull);
      bufferFull.endDraw();
      return;
    }
  
    int active = stateFull.activeIndex >= 0 ? stateFull.activeIndex : computeActiveLine(stateFull);
    float centerY = bufferFull.height / 2;
    float prevFontSize = fontSize * 0.8;
    float nextFontSize = fontSize * 0.8;
    float prevLineHeight = prevFontSize * 1.2;
    float currLineHeight = fontSize * 1.2;
    float nextLineHeight = nextFontSize * 1.2;
    float gap = fontSize * 0.35;
    
    ArrayList<String> prevLines = new ArrayList<String>();
    ArrayList<String> currLines = new ArrayList<String>();
    ArrayList<String> nextLines = new ArrayList<String>();
    
    // Previous line - pure white
    if (active > 0) {
      bufferFull.textSize(prevFontSize);
      bufferFull.fill(255, stateFull.textOpacity);
      prevLines = wrapText(stateFull.lines.get(active - 1).text, bufferFull, maxWidth);
    }
  
    // Current line - pure white
    if (active >= 0 && active < stateFull.lines.size()) {
      bufferFull.fill(255, stateFull.textOpacity);
      bufferFull.textSize(fontSize);
      currLines = wrapText(stateFull.lines.get(active).text, bufferFull, maxWidth);
    }
  
    // Next line - pure white
    if (active >= 0 && active < stateFull.lines.size() - 1) {
      bufferFull.textSize(nextFontSize);
      bufferFull.fill(255, stateFull.textOpacity);
      nextLines = wrapText(stateFull.lines.get(active + 1).text, bufferFull, maxWidth);
    }
    
    float prevHeight = prevLines.size() * prevLineHeight;
    float currHeight = currLines.size() * currLineHeight;
    float nextHeight = nextLines.size() * nextLineHeight;
    float totalHeight = prevHeight + currHeight + nextHeight;
    if (prevLines.size() > 0 && currLines.size() > 0) totalHeight += gap;
    if (currLines.size() > 0 && nextLines.size() > 0) totalHeight += gap;
    float startY = centerY - totalHeight / 2;

    float y = startY;
    if (prevLines.size() > 0) {
      bufferFull.textSize(prevFontSize);
      drawWrappedLines(bufferFull, prevLines, bufferFull.width / 2, y, prevLineHeight);
      y += prevHeight + gap;
    }
    if (currLines.size() > 0) {
      bufferFull.textSize(fontSize);
      drawWrappedLines(bufferFull, currLines, bufferFull.width / 2, y, currLineHeight);
      y += currHeight;
      if (nextLines.size() > 0) y += gap;
    }
    if (nextLines.size() > 0) {
      bufferFull.textSize(nextFontSize);
      drawWrappedLines(bufferFull, nextLines, bufferFull.width / 2, y, nextLineHeight);
    }
  
    // Progress bar - pure white
    if (stateFull.durationSec > 0) {
      float progress = stateFull.positionSec / stateFull.durationSec;
      float barW = bufferFull.width * 0.6;
      float barX = (bufferFull.width - barW) / 2;
      bufferFull.noStroke();
      bufferFull.fill(255, stateFull.textOpacity * 0.3);
      bufferFull.rect(barX, bufferFull.height - 50, barW, 4, 2);
      bufferFull.fill(255, stateFull.textOpacity);
      bufferFull.rect(barX, bufferFull.height - 50, barW * progress, 4, 2);
    }
  }

  drawBroadcastMessage(bufferFull);
  bufferFull.endDraw();
}

// ========== REFRAIN CHANNEL ==========

void renderRefrain() {
  bufferRefrain.beginDraw();
  bufferRefrain.background(0);
  bufferRefrain.textAlign(CENTER, TOP);
  bufferRefrain.textFont(currentFont);

  if (stateRefrain.active && !stateRefrain.currentText.isEmpty()) {
    int fontSize = fontSizes[fontSizeIndex] + 12;  // Larger for refrain
    float lineHeight = fontSize * 1.25;
    float maxWidth = bufferRefrain.width * 0.86;
  
    // Main text - pure white
    bufferRefrain.fill(255, stateRefrain.textOpacity);
    bufferRefrain.textSize(fontSize);
    ArrayList<String> lines = wrapText(stateRefrain.currentText, bufferRefrain, maxWidth);
    float totalHeight = lines.size() * lineHeight;
    float startY = bufferRefrain.height / 2 - totalHeight / 2;
    drawWrappedLines(bufferRefrain, lines, bufferRefrain.width / 2, startY, lineHeight);
  }

  drawBroadcastMessage(bufferRefrain);
  bufferRefrain.endDraw();
}

// ========== SONG INFO CHANNEL ==========

void renderSongInfo() {
  bufferSongInfo.beginDraw();
  bufferSongInfo.background(0);
  bufferSongInfo.textAlign(CENTER, CENTER);
  bufferSongInfo.textFont(currentFont);

  if (stateSongInfo.active) {
    int fontSize = fontSizes[fontSizeIndex] + 24;  // Large for song info
    float lineHeight = fontSize * 1.25;
    
    // Artist - pure white
    bufferSongInfo.fill(255, stateSongInfo.textOpacity);
    bufferSongInfo.textSize(fontSize * 0.7);
    bufferSongInfo.text(stateSongInfo.artist, bufferSongInfo.width / 2, bufferSongInfo.height / 2 - fontSize * 0.6);
    
    // Title - pure white, larger
    bufferSongInfo.textSize(fontSize);
    bufferSongInfo.text(stateSongInfo.title, bufferSongInfo.width / 2, bufferSongInfo.height / 2 + fontSize * 0.3);
  }

  drawBroadcastMessage(bufferSongInfo);
  bufferSongInfo.endDraw();
}

// ========== SHARED OVERLAYS ==========

void drawBroadcastMessage(PGraphics pg) {
  if (broadcastMessage == null || broadcastMessage.trim().length() == 0) return;
  
  float boxHeight = 110;
  pg.pushStyle();
  pg.textAlign(CENTER, TOP);
  pg.textFont(currentFont);
  pg.textSize(max(fontSizes[fontSizeIndex], 42));
  
  pg.noStroke();
  pg.fill(0, 190);
  pg.rect(0, pg.height - boxHeight, pg.width, boxHeight);
  
  pg.fill(255, 240);
  float textY = pg.height - boxHeight + 18;
  float lineHeight = (pg.textAscent() + pg.textDescent()) * 1.1;
  ArrayList<String> lines = wrapText(broadcastMessage, pg, pg.width - 60);
  drawWrappedLines(pg, lines, pg.width / 2, textY, lineHeight);
  pg.popStyle();
}

void drawHUD() {
  pushStyle();
  textFont(hudFont);
  textAlign(LEFT, TOP);
  
  int baseY = height - 120;
  noStroke();
  fill(0, 180);
  rect(12, baseY - 12, width - 24, 118, 10);

  fill(255);
  text("Local display only · Controls: [f] font [g] size [r] reconnect OSC [t] broadcast (HUD always on)", 20, baseY);
  
  String timeSinceMsg = oscConnected ? "" : " (" + ((millis() - lastOscMessageTime) / 1000) + "s)";
  text("Status: OSC " + (oscConnected ? "connected" : "disconnected" + timeSinceMsg) + " · font " + availableFonts[fontIndex] + " @ " + fontSizes[fontSizeIndex], 20, baseY + 18);

  String messageLine;
  if (typingBroadcast) {
    String cursor = (frameCount % 30 < 15) ? "_" : "";
    messageLine = "Typing broadcast → " + broadcastInput + cursor + "  (Enter: send to all outputs, Esc: cancel)";
  } else if (broadcastMessage != null && broadcastMessage.trim().length() > 0) {
    messageLine = "Broadcasting to all outputs: \"" + broadcastMessage + "\"  (press 't' then Enter on empty to clear)";
  } else {
    messageLine = "Broadcast message: none (press 't' to type and Enter to send everywhere)";
  }
  text(messageLine, 20, baseY + 36);
  
  popStyle();
}

ArrayList<String> wrapText(String text, PGraphics pg, float maxWidth) {
  ArrayList<String> lines = new ArrayList<String>();
  if (text == null) return lines;
  
  String[] paragraphs = split(text, '\n');
  for (int p = 0; p < paragraphs.length; p++) {
    String paragraph = paragraphs[p];
    if (paragraph.trim().length() == 0) {
      lines.add("");
      continue;
    }
    String[] words = splitTokens(paragraph, " ");
    String current = "";
    for (int i = 0; i < words.length; i++) {
      String word = words[i];
      // If a single word is longer than the max width, hard-break it
      if (pg.textWidth(word) > maxWidth) {
        for (int c = 0; c < word.length(); c++) {
          String next = current + word.charAt(c);
          if (pg.textWidth(next) > maxWidth && current.length() > 0) {
            lines.add(current);
            current = "" + word.charAt(c);
          } else {
            current = next;
          }
        }
        continue;
      }
      
      String candidate = (current.length() == 0) ? word : current + " " + word;
      if (pg.textWidth(candidate) <= maxWidth) {
        current = candidate;
      } else {
        lines.add(current);
        current = word;
      }
    }
    if (current.length() > 0) lines.add(current);
  }
  
  if (lines.size() == 0) lines.add("");
  return lines;
}

void drawWrappedLines(PGraphics pg, ArrayList<String> lines, float centerX, float startY, float lineHeight) {
  if (lines == null || lines.size() == 0) return;
  for (int i = 0; i < lines.size(); i++) {
    float y = startY + i * lineHeight;
    pg.text(lines.get(i), centerX, y);
  }
}

void drawWrappedBlock(PGraphics pg, String text, float centerX, float centerY, float maxWidth, float textSizeVal, float lineHeight) {
  pg.textSize(textSizeVal);
  ArrayList<String> lines = wrapText(text, pg, maxWidth);
  float totalHeight = lines.size() * lineHeight;
  float startY = centerY - totalHeight / 2;
  drawWrappedLines(pg, lines, centerX, startY, lineHeight);
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

String onOff(boolean val) {
  return val ? "on" : "off";
}

// ========== SAFE OSC PARAMETER EXTRACTION ==========

String safeGetString(OscMessage msg, int index, String defaultValue) {
  try {
    if (index >= msg.typetag().length()) return defaultValue;
    String val = msg.get(index).stringValue();
    return (val != null) ? val : defaultValue;
  } catch (Exception e) {
    println("ERROR: Failed to get string at index " + index + ": " + e.getMessage());
    return defaultValue;
  }
}

int safeGetInt(OscMessage msg, int index, int defaultValue) {
  try {
    if (index >= msg.typetag().length()) return defaultValue;
    return msg.get(index).intValue();
  } catch (Exception e) {
    println("ERROR: Failed to get int at index " + index + ": " + e.getMessage());
    return defaultValue;
  }
}

float safeGetFloat(OscMessage msg, int index, float defaultValue) {
  try {
    if (index >= msg.typetag().length()) return defaultValue;
    return msg.get(index).floatValue();
  } catch (Exception e) {
    println("ERROR: Failed to get float at index " + index + ": " + e.getMessage());
    return defaultValue;
  }
}

void applyFontSelection() {
  if (availableFonts == null || availableFonts.length == 0) {
    availableFonts = new String[] { "SansSerif" };
  }
  fontIndex = constrain(fontIndex, 0, availableFonts.length - 1);
  fontSizeIndex = constrain(fontSizeIndex, 0, fontSizes.length - 1);
  String fontName = availableFonts[fontIndex];
  int size = fontSizes[fontSizeIndex];
  currentFont = loadFontCached(fontName, size);
  textFont(currentFont);
  saveFontSettings();
  println("Font set to " + fontName + " @ " + size + "px");
}

PFont loadFontCached(String name, int size) {
  String key = name + "|" + size;
  PFont cached = fontCache.get(key);
  if (cached != null) {
    return cached;
  }

  try {
    PFont created = createFont(name, size, true);
    fontCache.put(key, created);
    return created;
  } catch (Exception primary) {
    // Fallback chain: SansSerif → Arial → first available font
    String fallbackName = "SansSerif";
    if (!fallbackName.equals(name)) {
      println("Font load failed for " + name + ": " + primary.getMessage());
      PFont fallbackFont = loadFontCached(fallbackName, size);
      fontCache.put(key, fallbackFont);
      return fallbackFont;
    }
    
    // If SansSerif fails, try Arial
    if (!name.equals("Arial")) {
      println("SansSerif fallback failed, trying Arial");
      try {
        PFont arialFont = createFont("Arial", size, true);
        fontCache.put(key, arialFont);
        return arialFont;
      } catch (Exception arial) {
        println("Arial fallback also failed: " + arial.getMessage());
      }
    }
    
    // Last resort: use first available system font
    println("All fallbacks failed, using first available system font");
    String[] systemFonts = PFont.list();
    String lastResort = (systemFonts != null && systemFonts.length > 0) ? systemFonts[0] : "Monospaced";
    PFont emergencyFont = createFont(lastResort, size, true);
    fontCache.put(key, emergencyFont);
    return emergencyFont;
  }
}

void cycleFont() {
  fontIndex = (fontIndex + 1) % availableFonts.length;
  applyFontSelection();
}

void cycleFontSize() {
  fontSizeIndex = (fontSizeIndex + 1) % fontSizes.length;
  applyFontSelection();
}

void loadFontSettings() {
  try {
    String path = dataPath(SETTINGS_FILE);
    File f = new File(path);
    if (!f.exists()) return;
    String[] lines = loadStrings(path);
    String savedName = "";
    for (int i = 0; i < lines.length; i++) {
      if (lines[i].startsWith("fontName=")) savedName = lines[i].substring("fontName=".length());
      else if (lines[i].startsWith("fontSizeIndex=")) fontSizeIndex = Integer.parseInt(lines[i].substring("fontSizeIndex=".length()));
    }
    if (savedName.length() > 0) {
      for (int i = 0; i < availableFonts.length; i++) {
        if (availableFonts[i].equals(savedName)) {
          fontIndex = i;
          break;
        }
      }
    }
  } catch (Exception e) {
    println("Could not load font settings: " + e.getMessage());
  }
}

void saveFontSettings() {
  try {
    File parent = new File(dataPath(""));
    if (!parent.exists()) parent.mkdirs();
    String[] lines = {
      "fontName=" + availableFonts[fontIndex],
      "fontSizeIndex=" + fontSizeIndex
    };
    saveStrings(dataPath(SETTINGS_FILE), lines);
  } catch (Exception e) {
    println("Could not save font settings: " + e.getMessage());
  }
}

// ========== OSC EVENT HANDLER ==========

void oscEvent(OscMessage msg) {
  // Update connection status
  lastOscMessageTime = millis();
  oscConnected = true;
  
  String addr = msg.addrPattern();
  
  try {
    // === Full lyrics channel ===
    if (addr.equals("/karaoke/track")) {
      // Validate message format: [active, source, artist, title, album, duration, has_lyrics]
      if (msg.typetag().length() < 7) {
        println("ERROR: /karaoke/track message too short (expected 7 args, got " + msg.typetag().length() + ")");
        return;
      }
      
      stateFull.active = msg.get(0).intValue() == 1;
      stateRefrain.active = stateFull.active;
      stateSongInfo.active = stateFull.active;
      
      // Safe string extraction with null checks
      String newArtist = safeGetString(msg, 2, "");
      String newTitle = safeGetString(msg, 3, "");
      
      // Detect track change (handle initial empty state and edge cases)
      boolean hasExistingTrack = stateSongInfo.artist.length() > 0 || stateSongInfo.title.length() > 0;
      boolean isTrackChange = !newArtist.equals(stateSongInfo.artist) || !newTitle.equals(stateSongInfo.title);
      boolean isFirstTrack = !hasExistingTrack && (newArtist.length() > 0 || newTitle.length() > 0);
      
      if (isTrackChange || isFirstTrack) {
        stateSongInfo.artist = newArtist;
        stateSongInfo.title = newTitle;
        stateSongInfo.textChangeTime = millis();
        stateSongInfo.targetOpacity = 255;
        stateSongInfo.textOpacity = 255;
        println("Track change detected: " + newArtist + " - " + newTitle);
      }
      
      stateFull.source = safeGetString(msg, 1, "unknown");
      stateFull.artist = newArtist;
      stateFull.title = newTitle;
      stateFull.album = safeGetString(msg, 4, "");
      stateFull.durationSec = safeGetFloat(msg, 5, 0.0);
      stateFull.hasSyncedLyrics = safeGetInt(msg, 6, 0) == 1;
      targetFade = stateFull.active ? 1 : 0;
      
      if (stateFull.active) {
        println("Track: " + stateFull.artist + " - " + stateFull.title + " (" + (stateFull.hasSyncedLyrics ? "synced lyrics" : "no lyrics") + ")");
      }
    }
    else if (addr.equals("/karaoke/lyrics/reset")) {
      stateFull.lines.clear();
      stateFull.activeIndex = -1;
    }
    else if (addr.equals("/karaoke/lyrics/line")) {
      if (msg.typetag().length() < 3) {
        println("ERROR: /karaoke/lyrics/line message too short");
        return;
      }
      int idx = safeGetInt(msg, 0, -1);
      if (idx < 0) return;
      float t = safeGetFloat(msg, 1, 0.0);
      String txt = safeGetString(msg, 2, "");
      while (stateFull.lines.size() <= idx) stateFull.lines.add(new LyricLine(0, ""));
      stateFull.lines.set(idx, new LyricLine(t, txt));
    }
    else if (addr.equals("/karaoke/pos")) {
      if (msg.typetag().length() < 2) return;
      stateFull.positionSec = safeGetFloat(msg, 0, 0.0);
      stateFull.isPlaying = safeGetInt(msg, 1, 0) == 1;
    }
    else if (addr.equals("/karaoke/line/active")) {
      if (msg.typetag().length() < 1) return;
      int newIndex = safeGetInt(msg, 0, -1);
      if (newIndex < 0) return;
      if (newIndex != stateFull.lastActiveIndex) {
        stateFull.lastActiveIndex = newIndex;
        stateFull.lineChangeTime = millis();
        stateFull.targetOpacity = 255;
      }
      stateFull.activeIndex = newIndex;
    }
    
    // === Refrain channel ===
    else if (addr.equals("/karaoke/refrain/reset")) {
      stateRefrain.lines.clear();
      stateRefrain.currentText = "";
      stateRefrain.lastText = "";
    }
    else if (addr.equals("/karaoke/refrain/line")) {
      if (msg.typetag().length() < 3) {
        println("ERROR: /karaoke/refrain/line message too short");
        return;
      }
      int idx = safeGetInt(msg, 0, -1);
      if (idx < 0) return;
      float t = safeGetFloat(msg, 1, 0.0);
      String txt = safeGetString(msg, 2, "");
      while (stateRefrain.lines.size() <= idx) stateRefrain.lines.add(new LyricLine(0, ""));
      stateRefrain.lines.set(idx, new LyricLine(t, txt));
    }
    else if (addr.equals("/karaoke/refrain/active")) {
      if (msg.typetag().length() < 1) return;
      stateRefrain.activeIndex = safeGetInt(msg, 0, -1);
      if (msg.typetag().length() > 1) {
        String newText = safeGetString(msg, 1, "");
        if (newText != null && !newText.equals(stateRefrain.lastText)) {
          stateRefrain.lastText = newText;
          stateRefrain.textChangeTime = millis();
          stateRefrain.targetOpacity = 255;
        }
        stateRefrain.currentText = (newText != null) ? newText : "";
      }
    }
    
  } catch (Exception e) {
    println("OSC error: " + e.getMessage());
  }
}

// ========== TEXT FADE LOGIC ==========

void updateTextFades() {
  float fadeDelay = 5000; // 5 seconds before starting fade
  float fadeDuration = 1000; // 1 second fade out
  float currentTime = millis();
  
  // Full lyrics fade
  float fullElapsed = currentTime - stateFull.lineChangeTime;
  if (fullElapsed > fadeDelay) {
    float fadeProgress = min(1.0, (fullElapsed - fadeDelay) / fadeDuration);
    stateFull.targetOpacity = 255 * (1.0 - fadeProgress);
  } else {
    stateFull.targetOpacity = 255;
  }
  stateFull.textOpacity = lerp(stateFull.textOpacity, stateFull.targetOpacity, 0.15);
  
  // Refrain fade
  float refrainElapsed = currentTime - stateRefrain.textChangeTime;
  if (refrainElapsed > fadeDelay) {
    float fadeProgress = min(1.0, (refrainElapsed - fadeDelay) / fadeDuration);
    stateRefrain.targetOpacity = 255 * (1.0 - fadeProgress);
  } else {
    stateRefrain.targetOpacity = 255;
  }
  stateRefrain.textOpacity = lerp(stateRefrain.textOpacity, stateRefrain.targetOpacity, 0.15);
  
  // Song info fade
  float songInfoElapsed = currentTime - stateSongInfo.textChangeTime;
  if (songInfoElapsed > fadeDelay) {
    float fadeProgress = min(1.0, (songInfoElapsed - fadeDelay) / fadeDuration);
    stateSongInfo.targetOpacity = 255 * (1.0 - fadeProgress);
  } else {
    stateSongInfo.targetOpacity = 255;
  }
  stateSongInfo.textOpacity = lerp(stateSongInfo.textOpacity, stateSongInfo.targetOpacity, 0.15);
}

// ========== KEYBOARD CONTROLS ==========

void keyPressed() {
  if (typingBroadcast) {
    if (key == ENTER || key == RETURN) {
      broadcastMessage = broadcastInput.trim();
      typingBroadcast = false;
      broadcastInput = "";
      if (broadcastMessage.length() == 0) {
        println("Broadcast message cleared.");
      } else {
        println("Broadcast message set for all outputs: " + broadcastMessage);
      }
    }
    else if (key == ESC) {
      key = 0;  // prevent Processing from quitting
      typingBroadcast = false;
      broadcastInput = "";
      println("Broadcast entry cancelled.");
    }
    else if (key == BACKSPACE || keyCode == DELETE) {
      if (broadcastInput.length() > 0) {
        broadcastInput = broadcastInput.substring(0, broadcastInput.length() - 1);
      }
    }
    else if (key == CODED) {
      return;
    }
    else {
      broadcastInput += key;
    }
    return;
  }

  if (key == 't' || key == 'T') {
    typingBroadcast = true;
    broadcastInput = broadcastMessage;
    println("Type broadcast text, Enter to send to all outputs, Esc to cancel.");
  }
  else if (key == 'f' || key == 'F') {
    cycleFont();
  }
  else if (key == 'g' || key == 'G') {
    cycleFontSize();
  }
  else if (key == 'r' || key == 'R') {
    try {
      osc.stop();
      osc = new OscP5(this, OSC_PORT);
      lastOscMessageTime = millis();  // Reset timeout counter
      oscConnected = false;  // Wait for first message
      println("OSC reconnected on port " + OSC_PORT + " - waiting for messages...");
    } catch (Exception e) {
      println("ERROR: Failed to reconnect OSC: " + e.getMessage());
    }
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
  int lastActiveIndex = -1;
  float lineChangeTime = 0;
  float textOpacity = 0;
  float targetOpacity = 255;
}

class RefrainState {
  boolean active = false;
  ArrayList<LyricLine> lines = new ArrayList<LyricLine>();
  int activeIndex = -1;
  String currentText = "";
  String lastText = "";
  float textChangeTime = 0;
  float textOpacity = 0;
  float targetOpacity = 255;
}

class SongInfoState {
  boolean active = false;
  String artist = "";
  String title = "";
  float textChangeTime = 0;
  float textOpacity = 0;
  float targetOpacity = 255;
}
