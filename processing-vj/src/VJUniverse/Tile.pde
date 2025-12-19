/**
 * Tile.pde - Abstract tile base class for multiplexed VJ rendering
 * 
 * Each tile owns a full-HD PGraphics buffer (1280x720 P3D) for Syphon output.
 * App window shows tiled preview; Syphon receives full resolution per tile.
 * 
 * Architecture:
 * - Tile is the abstract base with buffer lifecycle
 * - Concrete subclasses: ShaderTile, TextlerTile, etc.
 * - TileManager orchestrates all tiles
 */

abstract class Tile {
  
  // === IDENTITY ===
  String name;
  String syphonName;  // Syphon server name (e.g., "VJUniverse/Shader")
  
  // === RENDERING ===
  PGraphics buffer;
  int bufferWidth = 1280;
  int bufferHeight = 720;
  
  // === STATE ===
  boolean visible = true;
  boolean needsRedraw = true;
  float lastRenderTime = 0;
  
  // === OSC TRACKING (for preview overlay) ===
  String[] oscAddresses = {};        // Expected OSC addresses
  String[] oscDescriptions = {};     // Descriptions for each address
  float[] oscLastReceived = {};      // Timestamp of last message per address
  float oscGlowDuration = 1.5;       // How long the glow lasts (seconds)
  
  // === SYPHON ===
  SyphonServer syphonServer;
  
  /**
   * Constructor with name only (uses default resolution)
   */
  Tile(String name) {
    this(name, name, 1280, 720);
  }
  
  /**
   * Constructor with name and Syphon name
   */
  Tile(String name, String syphonName) {
    this(name, syphonName, 1280, 720);
  }
  
  /**
   * Full constructor with custom resolution
   */
  Tile(String name, String syphonName, int w, int h) {
    this.name = name;
    this.syphonName = syphonName;
    this.bufferWidth = w;
    this.bufferHeight = h;
  }
  
  /**
   * Initialize the tile (create buffer and Syphon server)
   * Called by TileManager after construction
   */
  void init(PApplet parent) {
    buffer = parent.createGraphics(bufferWidth, bufferHeight, P3D);
    syphonServer = new SyphonServer(parent, syphonName);
    println("[Tile] Created '" + name + "' → Syphon '" + syphonName + "' @ " + bufferWidth + "x" + bufferHeight);
  }
  
  /**
   * Update tile state (called every frame before render)
   * Override in subclasses for animation/state updates
   */
  void update() {
    // Default: no-op
  }
  
  /**
   * Render to internal buffer
   * Subclasses implement this to draw their content
   */
  abstract void render();
  
  /**
   * Send buffer to Syphon (called after render)
   */
  void sendToSyphon() {
    if (syphonServer != null && buffer != null) {
      syphonServer.sendImage(buffer);
    }
  }
  
  /**
   * Get the buffer for preview drawing
   */
  PGraphics getBuffer() {
    return buffer;
  }
  
  /**
   * Handle OSC message (return true if handled)
   */
  boolean handleOSC(OscMessage msg) {
    return false;  // Default: not handled
  }
  
  /**
   * Handle key press (return true if consumed)
   */
  boolean handleKey(char key, int keyCode) {
    return false;  // Default: not consumed
  }
  
  /**
   * Clean up resources
   */
  void dispose() {
    if (syphonServer != null) {
      syphonServer.stop();
      syphonServer = null;
    }
    buffer = null;
  }
  
  // === OSC TRACKING METHODS ===
  
  /**
   * Set up OSC addresses this tile listens to
   */
  void setOSCAddresses(String[] addresses, String[] descriptions) {
    this.oscAddresses = addresses;
    this.oscDescriptions = descriptions;
    this.oscLastReceived = new float[addresses.length];
    for (int i = 0; i < oscLastReceived.length; i++) {
      oscLastReceived[i] = -999;  // Never received
    }
  }
  
  /**
   * Mark an OSC address as received (triggers glow)
   */
  void markOSCReceived(String addr) {
    for (int i = 0; i < oscAddresses.length; i++) {
      if (oscAddresses[i].equals(addr) || addr.startsWith(oscAddresses[i])) {
        oscLastReceived[i] = millis() / 1000.0;
        return;
      }
    }
  }
  
  /**
   * Get glow intensity for an OSC address (0.0-1.0)
   */
  float getOSCGlow(int index) {
    if (index < 0 || index >= oscLastReceived.length) return 0;
    float elapsed = (millis() / 1000.0) - oscLastReceived[index];
    if (elapsed < 0 || elapsed > oscGlowDuration) return 0;
    return 1.0 - (elapsed / oscGlowDuration);
  }
  
  // === UTILITY METHODS FOR SUBCLASSES ===
  
  /**
   * Begin drawing to buffer (convenience wrapper)
   */
  void beginDraw() {
    if (buffer != null) {
      buffer.beginDraw();
      buffer.background(0);  // Default black background
    }
  }
  
  /**
   * End drawing to buffer (convenience wrapper)
   */
  void endDraw() {
    if (buffer != null) {
      buffer.endDraw();
      lastRenderTime = millis() / 1000.0;
    }
  }
}


// =============================================================================
// SHADER TILE - Wraps existing shader rendering
// =============================================================================

class ShaderTile extends Tile {
  
  // Reference to main sketch's shader state
  // (ShaderTile delegates to existing ShaderManager functions)
  
  ShaderTile() {
    super("Shader", "VJUniverse/Shader");
    setOSCAddresses(
      new String[] {"/shader/load", "/shader/next", "/shader/prev", "/audio/*"},
      new String[] {"Load shader by name", "Next shader", "Previous shader", "Audio levels"}
    );
  }
  
  @Override
  void render() {
    beginDraw();
    
    if (activeShader != null) {
      try {
        applyShaderUniformsTo(activeShader, buffer);
        buffer.shader(activeShader);
        drawQuadTo(buffer);
        buffer.resetShader();
      } catch (Exception e) {
        // Shader error - show black
        buffer.background(0);
      }
    }
    
    endDraw();
  }
}


// =============================================================================
// TEXTLER TILE - Generic flexible text rendering via OSC
// =============================================================================
// 
// OSC Protocol:
//   /textler/slot <name> <text>           - Set text in named slot (top, center, bottom, title, sub, custom)
//   /textler/slot/<name>/size <float>     - Font size multiplier (0.5=small, 1.0=normal, 2.0=large)
//   /textler/slot/<name>/opacity <float>  - Opacity 0.0-1.0
//   /textler/slot/<name>/y <float>        - Y position 0.0-1.0 (0=top, 0.5=center, 1=bottom)
//   /textler/slot/<name>/color <r> <g> <b> - RGB color 0-255
//   /textler/slot/<name>/align <string>   - "left", "center", "right"
//   /textler/fade <name> <target> <dur>   - Animate opacity to target over duration seconds
//   /textler/flash <name>                 - Quick flash effect (opacity spike then fade)
//   /textler/clear [name]                 - Clear one slot or all slots
//   /textler/preset <name>                - Load preset layout (karaoke, songinfo, refrain, minimal)
//

class TextSlot {
  String name;
  String text = "";
  float sizeMultiplier = 1.0;
  float opacity = 1.0;
  float targetOpacity = 1.0;
  float fadeSpeed = 0.0;  // opacity units per second
  float yPosition = 0.5;  // 0=top, 0.5=center, 1=bottom
  int align = CENTER;     // LEFT, CENTER, RIGHT
  color textColor = color(255);
  float lastUpdate = 0;
  
  TextSlot(String name, float y) {
    this.name = name;
    this.yPosition = y;
  }
  
  void update(float dt) {
    // Animate opacity
    if (fadeSpeed != 0) {
      float diff = targetOpacity - opacity;
      if (abs(diff) < 0.01) {
        opacity = targetOpacity;
        fadeSpeed = 0;
      } else {
        opacity += fadeSpeed * dt;
        opacity = constrain(opacity, 0, 1);
      }
    }
  }
  
  void fadeTo(float target, float duration) {
    targetOpacity = constrain(target, 0, 1);
    if (duration <= 0) {
      opacity = targetOpacity;
      fadeSpeed = 0;
    } else {
      fadeSpeed = (targetOpacity - opacity) / duration;
    }
  }
  
  void flash() {
    opacity = 1.0;
    fadeTo(0.7, 0.3);  // Flash then settle to 0.7
  }
}

class TextlerTile extends Tile {
  
  HashMap<String, TextSlot> slots = new HashMap<String, TextSlot>();
  TextRenderer textRenderer;
  float lastFrameTime = 0;
  
  // Track info state
  String currentArtist = "";
  String currentTitle = "";
  String currentAlbum = "";
  float currentDuration = 0;
  boolean hasLyrics = false;
  boolean trackActive = false;
  float trackDisplayTime = 0;       // How long track info has been shown
  float trackFadeInDuration = 0.5;  // Fade in duration
  float trackHoldDuration = 5.0;    // Hold at full opacity
  float trackFadeOutDuration = 1.0; // Fade out duration
  
  TextlerTile(String name, String syphonName, TextRenderer textRenderer) {
    super(name, syphonName);
    this.textRenderer = textRenderer;
    
    // Create default slots
    String[] slotNames = {"title", "top", "center", "bottom", "sub"};
    float[] slotY = {0.08, 0.25, 0.5, 0.75, 0.92};
    for (int i = 0; i < slotNames.length; i++) {
      slots.put(slotNames[i], new TextSlot(slotNames[i], slotY[i]));
    }
    
    // Create track info slot (bottom area, smaller text)
    TextSlot trackSlot = new TextSlot("track", 0.92);
    trackSlot.sizeMultiplier = 0.5;
    trackSlot.opacity = 0;
    slots.put("track", trackSlot);
    
    // Configure default sizes
    slots.get("title").sizeMultiplier = 0.7;
    slots.get("sub").sizeMultiplier = 0.6;
    slots.get("center").sizeMultiplier = 1.2;
    
    setOSCAddresses(
      new String[] {"/textler/track", "/textler/slot", "/textler/fade", "/textler/flash", "/textler/clear", "/textler/preset"},
      new String[] {"Song info (fade)", "Set slot text/props", "Fade opacity", "Flash effect", "Clear slots", "Load preset"}
    );
  }
  
  @Override
  void update() {
    float now = millis() / 1000.0;
    float dt = (lastFrameTime > 0) ? (now - lastFrameTime) : 0.016;
    lastFrameTime = now;
    
    for (TextSlot slot : slots.values()) {
      slot.update(dt);
    }
    
    // Update track info fade envelope
    if (trackActive) {
      trackDisplayTime += dt;
      TextSlot trackSlot = slots.get("track");
      if (trackSlot != null) {
        float totalDuration = trackFadeInDuration + trackHoldDuration + trackFadeOutDuration;
        
        if (trackDisplayTime < trackFadeInDuration) {
          // Fade in
          trackSlot.opacity = trackDisplayTime / trackFadeInDuration;
        } else if (trackDisplayTime < trackFadeInDuration + trackHoldDuration) {
          // Hold
          trackSlot.opacity = 1.0;
        } else if (trackDisplayTime < totalDuration) {
          // Fade out
          float fadeProgress = (trackDisplayTime - trackFadeInDuration - trackHoldDuration) / trackFadeOutDuration;
          trackSlot.opacity = 1.0 - fadeProgress;
        } else {
          // Done - hide
          trackSlot.opacity = 0;
          trackActive = false;
        }
      }
    }
  }
  
  @Override
  void render() {
    beginDraw();
    buffer.textAlign(CENTER, CENTER);
    
    if (textRenderer != null) {
      PFont font = textRenderer.getFont();
      int baseSize = textRenderer.getFontSize();
      float maxWidth = buffer.width * 0.9;
      
      buffer.textFont(font);
      
      // Render all slots with text
      for (TextSlot slot : slots.values()) {
        if (slot.text.isEmpty() || slot.opacity < 0.01) continue;
        
        float fontSize = baseSize * slot.sizeMultiplier;
        buffer.textSize(fontSize);
        buffer.textAlign(slot.align, CENTER);
        buffer.fill(red(slot.textColor), green(slot.textColor), blue(slot.textColor), slot.opacity * 255);
        
        float y = slot.yPosition * buffer.height;
        float x = (slot.align == LEFT) ? 40 : (slot.align == RIGHT) ? buffer.width - 40 : buffer.width / 2;
        
        // Wrap text if needed
        ArrayList<String> lines = textRenderer.wrapText(slot.text, buffer, maxWidth);
        float lineHeight = fontSize * 1.3;
        float totalHeight = lines.size() * lineHeight;
        float startY = y - totalHeight / 2 + lineHeight / 2;
        
        for (int i = 0; i < lines.size(); i++) {
          buffer.text(lines.get(i), x, startY + i * lineHeight);
        }
      }
    }
    
    // Broadcast overlay
    if (textRenderer != null) {
      textRenderer.drawBroadcast(buffer);
    }
    endDraw();
  }
  
  @Override
  boolean handleOSC(OscMessage msg) {
    String addr = msg.addrPattern();
    
    // /textler/track [active, source, artist, title, album, duration, has_lyrics]
    if (addr.equals("/textler/track") && msg.typetag().length() >= 4) {
      int active = msg.get(0).intValue();
      String source = msg.get(1).stringValue();
      String artist = msg.get(2).stringValue();
      String title = msg.get(3).stringValue();
      String album = (msg.typetag().length() >= 5) ? msg.get(4).stringValue() : "";
      float duration = (msg.typetag().length() >= 6) ? msg.get(5).floatValue() : 0;
      int hasLyricsInt = (msg.typetag().length() >= 7) ? msg.get(6).intValue() : 0;
      
      // Store track info
      currentArtist = artist;
      currentTitle = title;
      currentAlbum = album;
      currentDuration = duration;
      hasLyrics = (hasLyricsInt == 1);
      
      // Update track slot with artist - title
      TextSlot trackSlot = slots.get("track");
      if (trackSlot != null) {
        if (active == 1 && !artist.isEmpty() && !title.isEmpty()) {
          trackSlot.text = artist + " - " + title;
          trackActive = true;
          trackDisplayTime = 0;  // Reset fade timer
          trackSlot.opacity = 0; // Start from 0, will fade in
        } else {
          trackSlot.text = "";
          trackActive = false;
          trackSlot.opacity = 0;
        }
      }
      markOSCReceived(addr);
      return true;
    }
    
    // /textler/slot <name> <text>
    if (addr.equals("/textler/slot") && msg.typetag().length() >= 2) {
      String slotName = msg.get(0).stringValue();
      String text = msg.get(1).stringValue();
      getOrCreateSlot(slotName).text = text;
      markOSCReceived(addr);
      return true;
    }
    
    // /textler/slot/<name>/size <float>
    if (addr.startsWith("/textler/slot/") && addr.endsWith("/size")) {
      String slotName = extractSlotName(addr);
      if (slotName != null && msg.typetag().length() >= 1) {
        getOrCreateSlot(slotName).sizeMultiplier = msg.get(0).floatValue();
        markOSCReceived("/textler/slot");
        return true;
      }
    }
    
    // /textler/slot/<name>/opacity <float>
    if (addr.startsWith("/textler/slot/") && addr.endsWith("/opacity")) {
      String slotName = extractSlotName(addr);
      if (slotName != null && msg.typetag().length() >= 1) {
        TextSlot slot = getOrCreateSlot(slotName);
        slot.opacity = msg.get(0).floatValue();
        slot.targetOpacity = slot.opacity;
        slot.fadeSpeed = 0;
        markOSCReceived("/textler/slot");
        return true;
      }
    }
    
    // /textler/slot/<name>/y <float>
    if (addr.startsWith("/textler/slot/") && addr.endsWith("/y")) {
      String slotName = extractSlotName(addr);
      if (slotName != null && msg.typetag().length() >= 1) {
        getOrCreateSlot(slotName).yPosition = msg.get(0).floatValue();
        markOSCReceived("/textler/slot");
        return true;
      }
    }
    
    // /textler/slot/<name>/align <string>
    if (addr.startsWith("/textler/slot/") && addr.endsWith("/align")) {
      String slotName = extractSlotName(addr);
      if (slotName != null && msg.typetag().length() >= 1) {
        String alignStr = msg.get(0).stringValue().toLowerCase();
        TextSlot slot = getOrCreateSlot(slotName);
        if (alignStr.equals("left")) slot.align = LEFT;
        else if (alignStr.equals("right")) slot.align = RIGHT;
        else slot.align = CENTER;
        markOSCReceived("/textler/slot");
        return true;
      }
    }
    
    // NOTE: Color OSC handler removed - text is always rendered WHITE for VJ readability
    // All slots use textColor = color(255) by default
    
    // /textler/fade <name> <target> <duration>
    if (addr.equals("/textler/fade") && msg.typetag().length() >= 3) {
      String slotName = msg.get(0).stringValue();
      float target = msg.get(1).floatValue();
      float duration = msg.get(2).floatValue();
      TextSlot slot = slots.get(slotName);
      if (slot != null) {
        slot.fadeTo(target, duration);
        markOSCReceived(addr);
        return true;
      }
    }
    
    // /textler/flash <name>
    if (addr.equals("/textler/flash") && msg.typetag().length() >= 1) {
      String slotName = msg.get(0).stringValue();
      TextSlot slot = slots.get(slotName);
      if (slot != null) {
        slot.flash();
        markOSCReceived(addr);
        return true;
      }
    }
    
    // /textler/clear [name]
    if (addr.equals("/textler/clear")) {
      if (msg.typetag().length() >= 1) {
        String slotName = msg.get(0).stringValue();
        TextSlot slot = slots.get(slotName);
        if (slot != null) slot.text = "";
      } else {
        for (TextSlot slot : slots.values()) {
          slot.text = "";
        }
      }
      markOSCReceived(addr);
      return true;
    }
    
    // /textler/preset <name>
    if (addr.equals("/textler/preset") && msg.typetag().length() >= 1) {
      String preset = msg.get(0).stringValue().toLowerCase();
      applyPreset(preset);
      markOSCReceived(addr);
      return true;
    }
    
    return false;
  }
  
  TextSlot getOrCreateSlot(String name) {
    if (!slots.containsKey(name)) {
      slots.put(name, new TextSlot(name, 0.5));
    }
    return slots.get(name);
  }
  
  String extractSlotName(String addr) {
    // /textler/slot/<name>/property -> extract <name>
    String[] parts = addr.split("/");
    if (parts.length >= 4) {
      return parts[3];
    }
    return null;
  }
  
  void applyPreset(String preset) {
    // Clear all first
    for (TextSlot slot : slots.values()) {
      slot.text = "";
      slot.opacity = 1.0;
    }
    
    if (preset.equals("karaoke")) {
      slots.get("title").sizeMultiplier = 0.6;
      slots.get("title").yPosition = 0.06;
      slots.get("top").sizeMultiplier = 0.85;
      slots.get("top").yPosition = 0.35;
      slots.get("center").sizeMultiplier = 1.3;
      slots.get("center").yPosition = 0.5;
      slots.get("bottom").sizeMultiplier = 0.85;
      slots.get("bottom").yPosition = 0.65;
    } else if (preset.equals("songinfo")) {
      slots.get("center").sizeMultiplier = 1.5;
      slots.get("center").yPosition = 0.45;
      slots.get("sub").sizeMultiplier = 1.0;
      slots.get("sub").yPosition = 0.55;
    } else if (preset.equals("refrain")) {
      slots.get("center").sizeMultiplier = 1.8;
      slots.get("center").yPosition = 0.5;
    } else if (preset.equals("minimal")) {
      slots.get("center").sizeMultiplier = 1.0;
      slots.get("center").yPosition = 0.5;
    }
  }
}


// =============================================================================
// REFRAIN TILE - (DEPRECATED - use TextlerTile with preset)
// =============================================================================

class RefrainTile extends Tile {
  
  RefrainState state;
  TextRenderer textRenderer;
  
  RefrainTile(RefrainState state, TextRenderer textRenderer) {
    super("Refrain", "VJUniverse/Refrain");
    this.state = state;
    this.textRenderer = textRenderer;
    setOSCAddresses(
      new String[] {"/textler/refrain/line", "/textler/refrain/active", "/textler/refrain/reset", "/karaoke/refrain/*"},
      new String[] {"Refrain line", "Active refrain", "Reset refrain", "Refrain (legacy)"}
    );
  }
  
  @Override
  void update() {
    state.updateFades();
  }
  
  @Override
  void render() {
    beginDraw();
    buffer.textAlign(CENTER, TOP);
    
    if (state.active && !state.currentText.isEmpty() && textRenderer != null) {
      PFont font = textRenderer.getFont();
      int fontSize = textRenderer.getFontSize() + 12;  // Larger for refrain
      float lineHeight = fontSize * 1.25;
      float maxWidth = buffer.width * 0.86;
      
      buffer.textFont(font);
      buffer.fill(255, state.textOpacity);
      buffer.textSize(fontSize);
      ArrayList<String> lines = textRenderer.wrapText(state.currentText, buffer, maxWidth);
      float totalHeight = lines.size() * lineHeight;
      float startY = buffer.height / 2 - totalHeight / 2;
      textRenderer.drawWrappedLines(buffer, lines, buffer.width / 2, startY, lineHeight);
    }
    
    textRenderer.drawBroadcast(buffer);
    endDraw();
  }
  
  @Override
  boolean handleOSC(OscMessage msg) {
    boolean handled = state.handleOSC(msg);
    if (handled) {
      markOSCReceived(msg.addrPattern());
    }
    return handled;
  }
}


// =============================================================================
// SONG INFO TILE - Artist/title display (fades after 5s)
// =============================================================================

class SongInfoTile extends Tile {
  
  SongInfoState state;
  TextRenderer textRenderer;
  
  SongInfoTile(SongInfoState state, TextRenderer textRenderer) {
    super("SongInfo", "VJUniverse/SongInfo");
    this.state = state;
    this.textRenderer = textRenderer;
    setOSCAddresses(
      new String[] {"/textler/track", "/textler/song/*", "/karaoke/track"},
      new String[] {"Track info", "Song metadata", "Track (legacy)"}
    );
  }
  
  @Override
  void update() {
    state.updateFades();
  }
  
  @Override
  void render() {
    beginDraw();
    buffer.textAlign(CENTER, CENTER);
    
    if (state.active && textRenderer != null) {
      PFont font = textRenderer.getFont();
      int fontSize = textRenderer.getFontSize() + 24;  // Large for song info
      
      buffer.textFont(font);
      
      // Artist
      buffer.fill(255, state.textOpacity);
      buffer.textSize(fontSize * 0.7);
      buffer.text(state.artist, buffer.width / 2, buffer.height / 2 - fontSize * 0.6);
      
      // Title (larger)
      buffer.textSize(fontSize);
      buffer.text(state.title, buffer.width / 2, buffer.height / 2 + fontSize * 0.3);
    }
    
    textRenderer.drawBroadcast(buffer);
    endDraw();
  }
  
  @Override
  boolean handleOSC(OscMessage msg) {
    boolean handled = state.handleOSC(msg);
    if (handled) {
      markOSCReceived(msg.addrPattern());
    }
    return handled;
  }
}
