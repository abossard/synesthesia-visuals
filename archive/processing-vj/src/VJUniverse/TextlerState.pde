/**
 * TextlerState.pde - State classes for Textler (text/lyrics) system
 * 
 * Replaces "Karaoke" naming with "Textler" for a more generic text framework.
 * Handles OSC messages for lyrics, refrain, and song info.
 * 
 * Design Principles:
 * - Immutable data where possible (TextLine)
 * - State classes encapsulate fade logic
 * - Safe OSC extraction with defaults
 */

// =============================================================================
// TEXT LINE - Immutable data class for a timestamped text line
// =============================================================================

class TextLine {
  final float timeSec;
  final String text;
  
  TextLine(float timeSec, String text) {
    this.timeSec = timeSec;
    this.text = text != null ? text : "";
  }
}


// =============================================================================
// TEXTLER STATE - Main lyrics state (prev/current/next)
// =============================================================================

class TextlerState {
  
  // === TRACK INFO ===
  boolean active = false;
  String source = "";
  String artist = "";
  String title = "";
  String album = "";
  float durationSec = 0;
  boolean hasSyncedLyrics = false;
  
  // === LYRICS ===
  ArrayList<TextLine> lines = new ArrayList<TextLine>();
  int activeIndex = -1;
  int lastActiveIndex = -1;
  
  // === FADE TIMING ===
  float lineChangeTime = 0;
  float textOpacity = 0;
  float targetOpacity = 255;
  
  // === FADE PARAMETERS ===
  float fadeDelay = 5000;      // ms before starting fade
  float fadeDuration = 1000;   // ms for fade out
  float fadeSmoothing = 0.15;  // lerp factor
  
  /**
   * Update fade logic (call every frame)
   */
  void updateFades() {
    float currentTime = millis();
    float elapsed = currentTime - lineChangeTime;
    
    if (elapsed > fadeDelay) {
      float fadeProgress = min(1.0, (elapsed - fadeDelay) / fadeDuration);
      targetOpacity = 255 * (1.0 - fadeProgress);
    } else {
      targetOpacity = 255;
    }
    
    textOpacity = lerp(textOpacity, targetOpacity, fadeSmoothing);
  }
  
  /**
   * Reset lyrics
   */
  void reset() {
    lines.clear();
    activeIndex = -1;
    lastActiveIndex = -1;
  }
  
  /**
   * Add or update a lyric line
   */
  void setLine(int index, float timeSec, String text) {
    while (lines.size() <= index) {
      lines.add(new TextLine(0, ""));
    }
    lines.set(index, new TextLine(timeSec, text));
  }
  
  /**
   * Set active line index and trigger fade reset
   */
  void setActiveLine(int index) {
    if (index != lastActiveIndex) {
      lastActiveIndex = index;
      lineChangeTime = millis();
      targetOpacity = 255;
    }
    activeIndex = index;
  }
  
  /**
   * Handle OSC messages for this state
   * Returns true if message was handled
   */
  boolean handleOSC(OscMessage msg) {
    String addr = msg.addrPattern();
    
    // /textler/track [active, source, artist, title, album, duration, has_lyrics]
    if (addr.equals("/textler/track")) {
      if (msg.typetag().length() < 7) return false;
      
      active = safeGetInt(msg, 0, 0) == 1;
      source = safeGetString(msg, 1, "");
      artist = safeGetString(msg, 2, "");
      title = safeGetString(msg, 3, "");
      album = safeGetString(msg, 4, "");
      durationSec = safeGetFloat(msg, 5, 0);
      hasSyncedLyrics = safeGetInt(msg, 6, 0) == 1;
      
      return true;
    }
    
    // /textler/lyrics/reset
    if (addr.equals("/textler/lyrics/reset")) {
      reset();
      return true;
    }
    
    // /textler/lyrics/line [index, time, text]
    if (addr.equals("/textler/lyrics/line")) {
      if (msg.typetag().length() < 3) return false;
      int idx = safeGetInt(msg, 0, -1);
      if (idx < 0) return false;
      float t = safeGetFloat(msg, 1, 0);
      String txt = safeGetString(msg, 2, "");
      setLine(idx, t, txt);
      return true;
    }
    
    // /textler/line/active [index]
    if (addr.equals("/textler/line/active")) {
      if (msg.typetag().length() < 1) return false;
      int newIndex = safeGetInt(msg, 0, -1);
      if (newIndex >= 0) {
        setActiveLine(newIndex);
      }
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


// =============================================================================
// REFRAIN STATE - Chorus/refrain display (larger, faster fade)
// =============================================================================

class RefrainState {
  
  boolean active = false;
  ArrayList<TextLine> lines = new ArrayList<TextLine>();
  int activeIndex = -1;
  String currentText = "";
  String lastText = "";
  
  // === FADE TIMING (faster than main lyrics) ===
  float textChangeTime = 0;
  float textOpacity = 0;
  float targetOpacity = 255;
  float fadeDelay = 2000;      // Shorter delay for refrain
  float fadeDuration = 1000;
  float fadeSmoothing = 0.15;
  
  void updateFades() {
    float currentTime = millis();
    float elapsed = currentTime - textChangeTime;
    
    if (elapsed > fadeDelay) {
      float fadeProgress = min(1.0, (elapsed - fadeDelay) / fadeDuration);
      targetOpacity = 255 * (1.0 - fadeProgress);
    } else {
      targetOpacity = 255;
    }
    
    textOpacity = lerp(textOpacity, targetOpacity, fadeSmoothing);
  }
  
  void reset() {
    lines.clear();
    currentText = "";
    lastText = "";
    activeIndex = -1;
  }
  
  void setLine(int index, float timeSec, String text) {
    while (lines.size() <= index) {
      lines.add(new TextLine(0, ""));
    }
    lines.set(index, new TextLine(timeSec, text));
  }
  
  void setActive(int index, String text) {
    activeIndex = index;
    if (text != null && !text.equals(lastText)) {
      lastText = text;
      textChangeTime = millis();
      targetOpacity = 255;
    }
    currentText = (text != null) ? text : "";
  }
  
  boolean handleOSC(OscMessage msg) {
    String addr = msg.addrPattern();
    
    // /textler/refrain/reset
    if (addr.equals("/textler/refrain/reset")) {
      reset();
      return true;
    }
    
    // /textler/refrain/line [index, time, text]
    if (addr.equals("/textler/refrain/line")) {
      if (msg.typetag().length() < 3) return false;
      int idx = safeGetInt(msg, 0, -1);
      if (idx < 0) return false;
      float t = safeGetFloat(msg, 1, 0);
      String txt = safeGetString(msg, 2, "");
      setLine(idx, t, txt);
      return true;
    }
    
    // /textler/refrain/active [index, text]
    if (addr.equals("/textler/refrain/active")) {
      if (msg.typetag().length() < 1) return false;
      int idx = safeGetInt(msg, 0, -1);
      String txt = (msg.typetag().length() > 1) ? safeGetString(msg, 1, "") : "";
      setActive(idx, txt);
      return true;
    }
    
    return false;
  }
  
  // Safe OSC helpers (same as TextlerState)
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


// =============================================================================
// SONG INFO STATE - Artist/title display (fades after delay)
// =============================================================================

class SongInfoState {
  
  boolean active = false;
  String artist = "";
  String title = "";
  
  // === FADE TIMING ===
  float textChangeTime = 0;
  float textOpacity = 0;
  float targetOpacity = 255;
  float fadeDelay = 5000;
  float fadeDuration = 1000;
  float fadeSmoothing = 0.15;
  
  void updateFades() {
    float currentTime = millis();
    float elapsed = currentTime - textChangeTime;
    
    if (elapsed > fadeDelay) {
      float fadeProgress = min(1.0, (elapsed - fadeDelay) / fadeDuration);
      targetOpacity = 255 * (1.0 - fadeProgress);
    } else {
      targetOpacity = 255;
    }
    
    textOpacity = lerp(textOpacity, targetOpacity, fadeSmoothing);
  }
  
  void setTrack(String artist, String title) {
    boolean isChange = !artist.equals(this.artist) || !title.equals(this.title);
    this.artist = artist;
    this.title = title;
    
    if (isChange && (artist.length() > 0 || title.length() > 0)) {
      textChangeTime = millis();
      targetOpacity = 255;
      textOpacity = 255;
    }
  }
  
  boolean handleOSC(OscMessage msg) {
    String addr = msg.addrPattern();
    
    // Song info comes from /textler/track
    if (addr.equals("/textler/track")) {
      if (msg.typetag().length() < 7) return false;
      
      active = safeGetInt(msg, 0, 0) == 1;
      String newArtist = safeGetString(msg, 2, "");
      String newTitle = safeGetString(msg, 3, "");
      setTrack(newArtist, newTitle);
      return true;
    }
    
    return false;
  }
  
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
}
