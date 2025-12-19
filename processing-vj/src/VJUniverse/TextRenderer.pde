/**
 * TextRenderer.pde - Flexible text rendering framework
 * 
 * Modern implementation inspired by KaraokeOverlay patterns.
 * Provides:
 * - Font caching with fallback chain
 * - Text wrapping for multi-line layout
 * - Broadcast message overlay
 * - OSC-driven text queue for dynamic messages
 * 
 * Design Principles (Grokking Simplicity):
 * - Pure functions for text calculations (wrapText, measureText)
 * - Stateful operations isolated to TextRenderer instance
 * - Immutable TextMessage data class
 */

import java.util.HashMap;
import java.util.ArrayList;
import java.util.Iterator;

// =============================================================================
// TEXT MESSAGE - Immutable data class for OSC-driven text
// =============================================================================

class TextMessage {
  final String text;
  final float x, y;           // Position (0-1 normalized)
  final float size;           // Font size multiplier (1.0 = base size)
  final int align;            // Processing text align constant
  final float opacity;        // 0-255
  final float fadeInTime;     // Time to fade in (seconds)
  final float holdTime;       // Time to hold at full opacity (seconds)
  final float fadeOutTime;    // Time to fade out (seconds)
  final float createdAt;      // millis() when created
  final String layer;         // Layer name for grouping
  final int priority;         // Higher = rendered later (on top)
  
  TextMessage(String text, float x, float y, float size, int align, 
              float opacity, float fadeIn, float hold, float fadeOut, String layer, int priority) {
    this.text = text;
    this.x = x;
    this.y = y;
    this.size = size;
    this.align = align;
    this.opacity = opacity;
    this.fadeInTime = fadeIn;
    this.holdTime = hold;
    this.fadeOutTime = fadeOut;
    this.createdAt = millis();
    this.layer = layer;
    this.priority = priority;
  }
  
  /**
   * Calculate current opacity based on fade envelope
   */
  float getCurrentOpacity() {
    float elapsed = (millis() - createdAt) / 1000.0;
    
    // Fade in phase
    if (elapsed < fadeInTime) {
      return opacity * (elapsed / fadeInTime);
    }
    
    // Hold phase
    float holdEnd = fadeInTime + holdTime;
    if (elapsed < holdEnd) {
      return opacity;
    }
    
    // Fade out phase
    float fadeOutEnd = holdEnd + fadeOutTime;
    if (elapsed < fadeOutEnd) {
      float fadeProgress = (elapsed - holdEnd) / fadeOutTime;
      return opacity * (1.0 - fadeProgress);
    }
    
    // Expired
    return 0;
  }
  
  boolean isExpired() {
    float elapsed = (millis() - createdAt) / 1000.0;
    return elapsed >= (fadeInTime + holdTime + fadeOutTime);
  }
}


// =============================================================================
// TEXT RENDERER - Main rendering framework
// =============================================================================

class TextRenderer {
  
  // === FONT MANAGEMENT ===
  HashMap<String, PFont> fontCache = new HashMap<String, PFont>();
  String[] availableFonts;
  int fontIndex = 0;
  int fontSizeIndex = 1;
  int[] fontSizes = {24, 36, 48, 60, 72, 96};
  PFont currentFont;
  PFont hudFont;
  
  // === DJ FONT PRESETS ===
  String[] djFonts = {
    "Avenir Next Heavy",
    "Futura Bold",
    "DIN Condensed Bold",
    "Impact",
    "Phosphate"
  };
  int djFontIndex = 0;
  boolean useDJFonts = false;
  
  // === SETTINGS PERSISTENCE ===
  final String SETTINGS_FILE = "textler_font_settings.txt";
  
  // === BROADCAST MESSAGE ===
  String broadcastMessage = "";
  boolean typingBroadcast = false;
  String broadcastInput = "";
  
  // === MESSAGE QUEUE ===
  ArrayList<TextMessage> messageQueue = new ArrayList<TextMessage>();
  
  // === REFERENCE ===
  PApplet parent;
  
  /**
   * Constructor
   */
  TextRenderer(PApplet parent) {
    this.parent = parent;
    initFonts();
  }
  
  void initFonts() {
    availableFonts = PFont.list();
    if (availableFonts == null || availableFonts.length == 0) {
      availableFonts = new String[] { "Arial", "SansSerif", "Monospaced" };
    }
    hudFont = parent.createFont("Arial", 16);
    loadSettings();
    applyFontSelection();
  }
  
  // === FONT CACHING WITH FALLBACK ===
  
  PFont loadFontCached(String name, int size) {
    String key = name + "|" + size;
    PFont cached = fontCache.get(key);
    if (cached != null) {
      return cached;
    }
    
    try {
      PFont created = parent.createFont(name, size, true);
      fontCache.put(key, created);
      return created;
    } catch (Exception e) {
      // Fallback chain: SansSerif → Arial → first available
      String fallback = "SansSerif";
      if (!fallback.equals(name)) {
        println("[TextRenderer] Font load failed for '" + name + "', trying fallback");
        return loadFontCached(fallback, size);
      }
      
      if (!name.equals("Arial")) {
        try {
          PFont arial = parent.createFont("Arial", size, true);
          fontCache.put(key, arial);
          return arial;
        } catch (Exception ae) { }
      }
      
      // Last resort
      String[] systemFonts = PFont.list();
      String lastResort = (systemFonts != null && systemFonts.length > 0) ? systemFonts[0] : "Monospaced";
      PFont emergency = parent.createFont(lastResort, size, true);
      fontCache.put(key, emergency);
      return emergency;
    }
  }
  
  void applyFontSelection() {
    String fontName;
    if (useDJFonts) {
      djFontIndex = constrain(djFontIndex, 0, djFonts.length - 1);
      fontName = djFonts[djFontIndex];
    } else {
      fontIndex = constrain(fontIndex, 0, availableFonts.length - 1);
      fontName = availableFonts[fontIndex];
    }
    fontSizeIndex = constrain(fontSizeIndex, 0, fontSizes.length - 1);
    int size = fontSizes[fontSizeIndex];
    currentFont = loadFontCached(fontName, size);
    saveSettings();
    println("[TextRenderer] Font: " + fontName + " @ " + size + "px" + (useDJFonts ? " (DJ)" : ""));
  }
  
  void cycleFont() {
    fontIndex = (fontIndex + 1) % availableFonts.length;
    applyFontSelection();
  }
  
  void cycleFontSize() {
    fontSizeIndex = (fontSizeIndex + 1) % fontSizes.length;
    applyFontSelection();
  }
  
  // === DJ FONT CONTROL ===
  
  void setDJFont(int index) {
    useDJFonts = true;
    djFontIndex = constrain(index, 0, djFonts.length - 1);
    applyFontSelection();
  }
  
  void cycleDJFont() {
    useDJFonts = true;
    djFontIndex = (djFontIndex + 1) % djFonts.length;
    applyFontSelection();
  }
  
  boolean setFontByName(String name) {
    // First check DJ fonts
    for (int i = 0; i < djFonts.length; i++) {
      if (djFonts[i].equalsIgnoreCase(name) || djFonts[i].toLowerCase().contains(name.toLowerCase())) {
        setDJFont(i);
        return true;
      }
    }
    // Then check system fonts
    for (int i = 0; i < availableFonts.length; i++) {
      if (availableFonts[i].equalsIgnoreCase(name) || availableFonts[i].toLowerCase().contains(name.toLowerCase())) {
        useDJFonts = false;
        fontIndex = i;
        applyFontSelection();
        return true;
      }
    }
    println("[TextRenderer] Font not found: " + name);
    return false;
  }
  
  void setFontSizeByIndex(int index) {
    fontSizeIndex = constrain(index, 0, fontSizes.length - 1);
    applyFontSelection();
  }
  
  PFont getFont() {
    return currentFont;
  }
  
  int getFontSize() {
    return fontSizes[fontSizeIndex];
  }
  
  String getFontName() {
    return availableFonts[fontIndex];
  }
  
  // === SETTINGS PERSISTENCE ===
  
  void loadSettings() {
    try {
      String path = parent.dataPath(SETTINGS_FILE);
      java.io.File f = new java.io.File(path);
      if (!f.exists()) return;
      
      String[] lines = parent.loadStrings(path);
      String savedName = "";
      for (String line : lines) {
        if (line.startsWith("fontName=")) savedName = line.substring("fontName=".length());
        else if (line.startsWith("fontSizeIndex=")) fontSizeIndex = Integer.parseInt(line.substring("fontSizeIndex=".length()));
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
      println("[TextRenderer] Could not load settings: " + e.getMessage());
    }
  }
  
  void saveSettings() {
    try {
      java.io.File parent = new java.io.File(this.parent.dataPath(""));
      if (!parent.exists()) parent.mkdirs();
      String[] lines = {
        "fontName=" + availableFonts[fontIndex],
        "fontSizeIndex=" + fontSizeIndex
      };
      this.parent.saveStrings(this.parent.dataPath(SETTINGS_FILE), lines);
    } catch (Exception e) {
      println("[TextRenderer] Could not save settings: " + e.getMessage());
    }
  }
  
  // === TEXT WRAPPING (Pure Function) ===
  
  /**
   * Wrap text to fit within maxWidth, respecting newlines
   */
  ArrayList<String> wrapText(String text, PGraphics pg, float maxWidth) {
    ArrayList<String> lines = new ArrayList<String>();
    if (text == null) return lines;
    
    String[] paragraphs = split(text, '\n');
    for (String paragraph : paragraphs) {
      if (paragraph.trim().length() == 0) {
        lines.add("");
        continue;
      }
      
      String[] words = splitTokens(paragraph, " ");
      String current = "";
      
      for (String word : words) {
        // Hard-break long words
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
  
  // === DRAWING HELPERS ===
  
  void drawWrappedLines(PGraphics pg, ArrayList<String> lines, float centerX, float startY, float lineHeight) {
    if (lines == null || lines.size() == 0) return;
    for (int i = 0; i < lines.size(); i++) {
      float y = startY + i * lineHeight;
      pg.text(lines.get(i), centerX, y);
    }
  }
  
  void drawWrappedBlock(PGraphics pg, String text, float centerX, float centerY, float maxWidth, float textSize, float lineHeight) {
    pg.textSize(textSize);
    ArrayList<String> lines = wrapText(text, pg, maxWidth);
    float totalHeight = lines.size() * lineHeight;
    float startY = centerY - totalHeight / 2;
    drawWrappedLines(pg, lines, centerX, startY, lineHeight);
  }
  
  // === BROADCAST MESSAGE ===
  
  void drawBroadcast(PGraphics pg) {
    if (broadcastMessage == null || broadcastMessage.trim().length() == 0) return;
    
    float boxHeight = 110;
    pg.pushStyle();
    pg.textAlign(CENTER, TOP);
    pg.textFont(currentFont);
    pg.textSize(max(getFontSize(), 42));
    
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
  
  void setBroadcast(String message) {
    broadcastMessage = message != null ? message : "";
  }
  
  void clearBroadcast() {
    broadcastMessage = "";
  }
  
  // === MESSAGE QUEUE (OSC-driven) ===
  
  /**
   * Add a text message to the queue
   * OSC: /textler/message [text, x, y, size, align, opacity, fadeIn, hold, fadeOut, layer, priority]
   */
  void addMessage(String text, float x, float y, float size, int align,
                  float opacity, float fadeIn, float hold, float fadeOut, String layer, int priority) {
    TextMessage msg = new TextMessage(text, x, y, size, align, opacity, fadeIn, hold, fadeOut, layer, priority);
    messageQueue.add(msg);
    
    // Sort by priority
    messageQueue.sort((a, b) -> Integer.compare(a.priority, b.priority));
  }
  
  /**
   * Add a simple message with defaults
   */
  void addMessage(String text, float x, float y) {
    addMessage(text, x, y, 1.0, CENTER, 255, 0.3, 3.0, 0.5, "default", 0);
  }
  
  /**
   * Clear all messages (optionally by layer)
   */
  void clearMessages(String layer) {
    if (layer == null || layer.isEmpty()) {
      messageQueue.clear();
    } else {
      messageQueue.removeIf(m -> m.layer.equals(layer));
    }
  }
  
  /**
   * Update message queue (remove expired)
   */
  void updateQueue() {
    messageQueue.removeIf(m -> m.isExpired());
  }
  
  /**
   * Render all queued messages to a buffer
   */
  void renderQueue(PGraphics pg) {
    updateQueue();
    
    pg.pushStyle();
    pg.textFont(currentFont);
    
    for (TextMessage msg : messageQueue) {
      float opacity = msg.getCurrentOpacity();
      if (opacity <= 0) continue;
      
      float x = msg.x * pg.width;
      float y = msg.y * pg.height;
      float textSize = getFontSize() * msg.size;
      
      pg.textAlign(msg.align, CENTER);
      pg.textSize(textSize);
      pg.fill(255, opacity);
      pg.text(msg.text, x, y);
    }
    
    pg.popStyle();
  }
  
  // === KEYBOARD HANDLING ===
  
  /**
   * Handle key for broadcast typing mode
   * Returns true if key was consumed
   */
  boolean handleKey(char key, int keyCode) {
    if (!typingBroadcast) {
      if (key == 't' || key == 'T') {
        typingBroadcast = true;
        broadcastInput = broadcastMessage;
        println("[TextRenderer] Typing broadcast...");
        return true;
      }
      return false;
    }
    
    // In typing mode
    if (key == ENTER || key == RETURN) {
      broadcastMessage = broadcastInput.trim();
      typingBroadcast = false;
      broadcastInput = "";
      println("[TextRenderer] Broadcast: " + (broadcastMessage.isEmpty() ? "(cleared)" : broadcastMessage));
      return true;
    }
    else if (key == ESC) {
      typingBroadcast = false;
      broadcastInput = "";
      println("[TextRenderer] Broadcast cancelled");
      return true;
    }
    else if (key == BACKSPACE || keyCode == DELETE) {
      if (broadcastInput.length() > 0) {
        broadcastInput = broadcastInput.substring(0, broadcastInput.length() - 1);
      }
      return true;
    }
    else if (key != CODED) {
      broadcastInput += key;
      return true;
    }
    
    return false;
  }
  
  boolean isTypingBroadcast() {
    return typingBroadcast;
  }
  
  String getBroadcastInput() {
    return broadcastInput;
  }
  
  // === OSC HANDLING ===
  
  /**
   * Handle OSC messages for text rendering
   * Returns true if message was handled
   */
  boolean handleOSC(OscMessage msg) {
    String addr = msg.addrPattern();
    
    // /textler/message [text, x, y, size, align, opacity, fadeIn, hold, fadeOut, layer, priority]
    if (addr.equals("/textler/message")) {
      String text = safeGetString(msg, 0, "");
      float x = safeGetFloat(msg, 1, 0.5);
      float y = safeGetFloat(msg, 2, 0.5);
      float size = safeGetFloat(msg, 3, 1.0);
      int align = safeGetInt(msg, 4, CENTER);
      float opacity = safeGetFloat(msg, 5, 255);
      float fadeIn = safeGetFloat(msg, 6, 0.3);
      float hold = safeGetFloat(msg, 7, 3.0);
      float fadeOut = safeGetFloat(msg, 8, 0.5);
      String layer = safeGetString(msg, 9, "default");
      int priority = safeGetInt(msg, 10, 0);
      
      addMessage(text, x, y, size, align, opacity, fadeIn, hold, fadeOut, layer, priority);
      return true;
    }
    
    // /textler/broadcast [text]
    if (addr.equals("/textler/broadcast")) {
      String text = safeGetString(msg, 0, "");
      setBroadcast(text);
      return true;
    }
    
    // /textler/clear [layer]
    if (addr.equals("/textler/clear")) {
      String layer = safeGetString(msg, 0, "");
      clearMessages(layer);
      return true;
    }
    
    // /textler/font [name] - set font by name
    if (addr.equals("/textler/font")) {
      String fontName = safeGetString(msg, 0, "");
      if (fontName.length() > 0) {
        setFontByName(fontName);
      }
      return true;
    }
    
    // /textler/font/index [int] - set DJ font by index 0-4
    if (addr.equals("/textler/font/index")) {
      int index = safeGetInt(msg, 0, 0);
      setDJFont(index);
      return true;
    }
    
    // /textler/font/cycle - cycle through DJ fonts
    if (addr.equals("/textler/font/cycle")) {
      cycleDJFont();
      return true;
    }
    
    // /textler/fontsize [int] - set font size by index
    if (addr.equals("/textler/fontsize")) {
      int index = safeGetInt(msg, 0, 1);
      setFontSizeByIndex(index);
      return true;
    }
    
    // /textler/fontsize/cycle - cycle through font sizes
    if (addr.equals("/textler/fontsize/cycle")) {
      cycleFontSize();
      return true;
    }
    
    return false;
  }
  
  // === SAFE OSC HELPERS ===
  
  String safeGetString(OscMessage msg, int index, String defaultValue) {
    try {
      if (index >= msg.typetag().length()) return defaultValue;
      String val = msg.get(index).stringValue();
      return (val != null) ? val : defaultValue;
    } catch (Exception e) {
      return defaultValue;
    }
  }
  
  int safeGetInt(OscMessage msg, int index, int defaultValue) {
    try {
      if (index >= msg.typetag().length()) return defaultValue;
      return msg.get(index).intValue();
    } catch (Exception e) {
      return defaultValue;
    }
  }
  
  float safeGetFloat(OscMessage msg, int index, float defaultValue) {
    try {
      if (index >= msg.typetag().length()) return defaultValue;
      return msg.get(index).floatValue();
    } catch (Exception e) {
      return defaultValue;
    }
  }
}
