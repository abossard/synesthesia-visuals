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
   * Resets camera to default to prevent state accumulation across levels
   */
  void beginDraw() {
    if (buffer != null) {
      buffer.beginDraw();
      buffer.background(0, 0);  // Transparent background for Syphon compositing
      buffer.camera();       // Reset camera to default (prevents off-center after level switches)
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
  
  // Lyrics and refrain state (from TextlerState.pde)
  TextlerState lyricsState = new TextlerState();
  RefrainState refrainState = new RefrainState();
  
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
    
    // Create lyrics slot (center area)
    TextSlot lyricsSlot = new TextSlot("lyrics", 0.5);
    lyricsSlot.sizeMultiplier = 1.0;
    lyricsSlot.opacity = 1.0;
    slots.put("lyrics", lyricsSlot);
    
    // Create refrain slot (slightly below center, larger)
    TextSlot refrainSlot = new TextSlot("refrain", 0.6);
    refrainSlot.sizeMultiplier = 1.3;
    refrainSlot.opacity = 0;
    slots.put("refrain", refrainSlot);
    
    // Configure default sizes
    slots.get("title").sizeMultiplier = 0.7;
    slots.get("sub").sizeMultiplier = 0.6;
    slots.get("center").sizeMultiplier = 1.2;
    
    setOSCAddresses(
      new String[] {"/textler/track", "/textler/slot", "/textler/lyrics/*", "/textler/refrain/*", "/textler/fade", "/textler/flash", "/textler/clear", "/textler/preset"},
      new String[] {"Song info (fade)", "Set slot text/props", "Lyrics lines/active", "Refrain lines/active", "Fade opacity", "Flash effect", "Clear slots", "Load preset"}
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
    
    // Update lyrics and refrain fades
    lyricsState.updateFades();
    refrainState.updateFades();
    
    // Update lyrics slot text from active line
    TextSlot lyricsSlot = slots.get("lyrics");
    if (lyricsSlot != null && lyricsState.activeIndex >= 0 && lyricsState.activeIndex < lyricsState.lines.size()) {
      TextLine activeLine = lyricsState.lines.get(lyricsState.activeIndex);
      lyricsSlot.text = activeLine.text;
      lyricsSlot.opacity = lyricsState.textOpacity / 255.0;
    }
    
    // Update refrain slot text
    TextSlot refrainSlot = slots.get("refrain");
    if (refrainSlot != null && refrainState.active && !refrainState.currentText.isEmpty()) {
      refrainSlot.text = refrainState.currentText;
      refrainSlot.opacity = refrainState.textOpacity / 255.0;
    } else if (refrainSlot != null) {
      refrainSlot.opacity = 0;
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
    
    // Delegate lyrics messages to lyricsState
    if (lyricsState.handleOSC(msg)) {
      markOSCReceived(addr);
      return true;
    }
    
    // Delegate refrain messages to refrainState
    if (refrainState.handleOSC(msg)) {
      // When refrain becomes active, show it
      if (addr.equals("/textler/refrain/active")) {
        refrainState.active = true;
      }
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
// TEXTLER MULTI-OUTPUT TILE - Single tile with 3 Syphon outputs
// =============================================================================
//
// One tile that manages 3 separate Syphon outputs:
//   - VJUniverse/Lyrics   : prev/current/next lyrics lines
//   - VJUniverse/Refrain  : chorus/refrain (larger)
//   - VJUniverse/SongInfo : artist/title (fades after delay)
//
// This keeps preview grid compact while providing separate mixable layers.
//

class TextlerMultiTile extends Tile {
  
  // === STATE ===
  TextlerState lyricsState;
  RefrainState refrainState;
  SongInfoState songInfoState;
  TextRenderer textRenderer;
  
  // === ADDITIONAL BUFFERS & SYPHONS ===
  PGraphics refrainBuffer;
  PGraphics songInfoBuffer;
  SyphonServer refrainSyphon;
  SyphonServer songInfoSyphon;
  
  TextlerMultiTile(TextRenderer textRenderer) {
    super("Textler", "VJUniverse/Lyrics");  // Main buffer = Lyrics
    this.textRenderer = textRenderer;
    this.lyricsState = new TextlerState();
    this.refrainState = new RefrainState();
    this.songInfoState = new SongInfoState();
    
    setOSCAddresses(
      new String[] {"/textler/track", "/textler/lyrics/*", "/textler/refrain/*", "/textler/line/active"},
      new String[] {"Track info", "Lyrics lines", "Refrain lines", "Active line"}
    );
  }
  
  @Override
  void init(PApplet parent) {
    super.init(parent);  // Creates main buffer + syphonServer (Lyrics)
    
    // Create additional buffers and Syphons
    refrainBuffer = parent.createGraphics(bufferWidth, bufferHeight, P3D);
    songInfoBuffer = parent.createGraphics(bufferWidth, bufferHeight, P3D);
    refrainSyphon = new SyphonServer(parent, "VJUniverse/Refrain");
    songInfoSyphon = new SyphonServer(parent, "VJUniverse/SongInfo");
    
    println("[TextlerMulti] 3 Syphon outputs: Lyrics, Refrain, SongInfo");
  }
  
  @Override
  void update() {
    lyricsState.updateFades();
    refrainState.updateFades();
    songInfoState.updateFades();
  }
  
  @Override
  void render() {
    renderLyrics();
    renderRefrain();
    renderSongInfo();
  }
  
  void renderLyrics() {
    buffer.beginDraw();
    buffer.background(0, 0);  // Transparent
    
    if (textRenderer != null && lyricsState.activeIndex >= 0) {
      PFont font = textRenderer.getFont();
      int fontSize = textRenderer.getFontSize();
      float lineHeight = fontSize * 1.4;
      float maxWidth = buffer.width * 0.88;
      
      buffer.textFont(font);
      buffer.textAlign(CENTER, CENTER);
      
      int activeIdx = lyricsState.activeIndex;
      
      // Previous line (dim)
      if (activeIdx > 0 && activeIdx - 1 < lyricsState.lines.size()) {
        String prevText = lyricsState.lines.get(activeIdx - 1).text;
        buffer.fill(255, lyricsState.textOpacity * 0.4);
        buffer.textSize(fontSize * 0.8);
        buffer.text(prevText, buffer.width / 2, buffer.height * 0.3);
      }
      
      // Current line (bright)
      if (activeIdx >= 0 && activeIdx < lyricsState.lines.size()) {
        String currText = lyricsState.lines.get(activeIdx).text;
        buffer.fill(255, lyricsState.textOpacity);
        buffer.textSize(fontSize * 1.1);
        ArrayList<String> wrapped = textRenderer.wrapText(currText, buffer, maxWidth);
        float startY = buffer.height * 0.5 - (wrapped.size() - 1) * lineHeight * 0.5;
        for (int i = 0; i < wrapped.size(); i++) {
          buffer.text(wrapped.get(i), buffer.width / 2, startY + i * lineHeight);
        }
      }
      
      // Next line (dim)
      if (activeIdx + 1 < lyricsState.lines.size()) {
        String nextText = lyricsState.lines.get(activeIdx + 1).text;
        buffer.fill(255, lyricsState.textOpacity * 0.4);
        buffer.textSize(fontSize * 0.8);
        buffer.text(nextText, buffer.width / 2, buffer.height * 0.7);
      }
      
      textRenderer.drawBroadcast(buffer);
    }
    
    buffer.endDraw();
  }
  
  void renderRefrain() {
    refrainBuffer.beginDraw();
    refrainBuffer.background(0, 0);  // Transparent
    
    if (textRenderer != null && !refrainState.currentText.isEmpty()) {
      PFont font = textRenderer.getFont();
      int fontSize = textRenderer.getFontSize() + 16;
      float lineHeight = fontSize * 1.3;
      float maxWidth = refrainBuffer.width * 0.85;
      
      refrainBuffer.textFont(font);
      refrainBuffer.textAlign(CENTER, CENTER);
      refrainBuffer.fill(255, refrainState.textOpacity);
      refrainBuffer.textSize(fontSize);
      
      ArrayList<String> lines = textRenderer.wrapText(refrainState.currentText, refrainBuffer, maxWidth);
      float totalHeight = lines.size() * lineHeight;
      float startY = refrainBuffer.height / 2 - totalHeight / 2 + lineHeight / 2;
      
      for (int i = 0; i < lines.size(); i++) {
        refrainBuffer.text(lines.get(i), refrainBuffer.width / 2, startY + i * lineHeight);
      }
      
      textRenderer.drawBroadcast(refrainBuffer);
    }
    
    refrainBuffer.endDraw();
  }
  
  void renderSongInfo() {
    songInfoBuffer.beginDraw();
    songInfoBuffer.background(0, 0);  // Transparent
    
    if (textRenderer != null && songInfoState.active && 
        (!songInfoState.artist.isEmpty() || !songInfoState.title.isEmpty())) {
      PFont font = textRenderer.getFont();
      int fontSize = textRenderer.getFontSize() + 24;
      
      songInfoBuffer.textFont(font);
      songInfoBuffer.textAlign(CENTER, CENTER);
      
      // Artist (smaller, above center)
      songInfoBuffer.fill(255, songInfoState.textOpacity);
      songInfoBuffer.textSize(fontSize * 0.65);
      songInfoBuffer.text(songInfoState.artist, songInfoBuffer.width / 2, songInfoBuffer.height * 0.42);
      
      // Title (larger, below center)
      songInfoBuffer.textSize(fontSize);
      songInfoBuffer.text(songInfoState.title, songInfoBuffer.width / 2, songInfoBuffer.height * 0.55);
      
      textRenderer.drawBroadcast(songInfoBuffer);
    }
    
    songInfoBuffer.endDraw();
  }
  
  @Override
  void sendToSyphon() {
    if (syphonServer != null && buffer != null) {
      syphonServer.sendImage(buffer);  // Lyrics
    }
    if (refrainSyphon != null && refrainBuffer != null) {
      refrainSyphon.sendImage(refrainBuffer);
    }
    if (songInfoSyphon != null && songInfoBuffer != null) {
      songInfoSyphon.sendImage(songInfoBuffer);
    }
  }
  
  @Override
  PGraphics getBuffer() {
    // For preview, composite all 3 layers
    // Return main buffer (lyrics) - preview shows lyrics layer
    return buffer;
  }
  
  @Override
  boolean handleOSC(OscMessage msg) {
    String addr = msg.addrPattern();
    boolean handled = false;
    
    // Route to appropriate state
    if (addr.startsWith("/textler/lyrics") || addr.equals("/textler/line/active")) {
      handled = lyricsState.handleOSC(msg);
    }
    else if (addr.startsWith("/textler/refrain")) {
      handled = refrainState.handleOSC(msg);
      if (handled && addr.equals("/textler/refrain/active")) {
        refrainState.active = true;
      }
    }
    else if (addr.equals("/textler/track")) {
      handled = songInfoState.handleOSC(msg);
    }
    
    if (handled) {
      markOSCReceived(addr);
    }
    return handled;
  }
  
  @Override
  void dispose() {
    super.dispose();
    if (refrainSyphon != null) {
      refrainSyphon.stop();
      refrainSyphon = null;
    }
    if (songInfoSyphon != null) {
      songInfoSyphon.stop();
      songInfoSyphon = null;
    }
    refrainBuffer = null;
    songInfoBuffer = null;
  }
}
