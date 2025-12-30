/**
 * MaskShaderTile.pde - Dedicated tile for mask shaders (rating 4)
 *
 * Provides a separate Syphon output for black/white mask shaders.
 * Independent shader cycling from the main ShaderTile.
 *
 * Syphon output: VJUniverse/Mask
 */

class MaskShaderTile extends Tile {

  // === MASK SHADER STATE (independent from main shader) ===
  PShader activeMaskShader;
  int currentMaskIndex = 0;
  String currentMaskName = "";

  MaskShaderTile() {
    super("Mask", "VJUniverse/Mask");
    setOSCAddresses(
      new String[] {"/mask/next", "/mask/prev", "/mask/load", "/mask/index"},
      new String[] {"Next mask shader", "Previous mask shader", "Load mask by name", "Load mask by index"}
    );
  }

  @Override
  void init(PApplet parent) {
    super.init(parent);

    // Load first mask shader if available
    if (maskShaders.size() > 0) {
      loadMaskByIndex(0);
    }
    println("[MaskShaderTile] Initialized with " + maskShaders.size() + " mask shaders");
  }

  @Override
  void render() {
    beginDraw();

    if (activeMaskShader != null && maskShaders.size() > 0) {
      try {
        applyShaderUniformsTo(activeMaskShader, buffer);
        buffer.shader(activeMaskShader);
        drawQuadTo(buffer);
        buffer.resetShader();
      } catch (Exception e) {
        // Shader error - show black
        buffer.background(0);
        println("[MaskShaderTile] Render error: " + e.getMessage());
      }
    } else {
      // No mask shader loaded - show dark gray
      buffer.background(32);
    }

    endDraw();
  }

  // === MASK SHADER NAVIGATION ===

  void nextMaskShader() {
    if (maskShaders.size() == 0) {
      println("[MaskShaderTile] No mask shaders available");
      return;
    }
    currentMaskIndex = (currentMaskIndex + 1) % maskShaders.size();
    loadMaskByIndex(currentMaskIndex);
  }

  void prevMaskShader() {
    if (maskShaders.size() == 0) {
      println("[MaskShaderTile] No mask shaders available");
      return;
    }
    currentMaskIndex = (currentMaskIndex - 1 + maskShaders.size()) % maskShaders.size();
    loadMaskByIndex(currentMaskIndex);
  }

  void loadMaskByIndex(int index) {
    if (maskShaders.size() == 0) {
      println("[MaskShaderTile] No mask shaders available");
      return;
    }
    if (index < 0 || index >= maskShaders.size()) {
      println("[MaskShaderTile] Invalid index: " + index);
      return;
    }

    ShaderInfo info = maskShaders.get(index);
    currentMaskIndex = index;
    currentMaskName = info.name;

    try {
      activeMaskShader = loadGlslShader(info.path);
      println("[MaskShaderTile] Loaded [" + (index + 1) + "/" + maskShaders.size() + "]: " + info.name);
    } catch (Exception e) {
      println("[MaskShaderTile] Error loading " + info.name + ": " + e.getMessage());
      activeMaskShader = null;
    }
  }

  void loadMaskByName(String name) {
    String normalized = normalizeShaderRequest(name);
    if (normalized == null || normalized.isEmpty()) {
      println("[MaskShaderTile] Empty mask name");
      return;
    }

    for (int i = 0; i < maskShaders.size(); i++) {
      ShaderInfo info = maskShaders.get(i);
      if (info.name.equalsIgnoreCase(normalized)) {
        loadMaskByIndex(i);
        return;
      }
    }
    println("[MaskShaderTile] Mask not found: " + name);
  }

  // === OSC HANDLING ===

  @Override
  boolean handleOSC(OscMessage msg) {
    String addr = msg.addrPattern();

    if (addr.equals("/mask/next")) {
      nextMaskShader();
      markOSCReceived(addr);
      return true;
    }

    if (addr.equals("/mask/prev")) {
      prevMaskShader();
      markOSCReceived(addr);
      return true;
    }

    if (addr.equals("/mask/load") && msg.typetag().length() >= 1) {
      loadMaskByName(msg.get(0).stringValue());
      markOSCReceived(addr);
      return true;
    }

    if (addr.equals("/mask/index") && msg.typetag().length() >= 1) {
      loadMaskByIndex(msg.get(0).intValue());
      markOSCReceived(addr);
      return true;
    }

    return false;
  }

  // === KEYBOARD HANDLING ===

  @Override
  boolean handleKey(char key, int keyCode) {
    // When tile is focused (via number keys), use standard N/P for navigation
    // This method is called by TileManager when this tile is focused
    return false;  // Let main keyboard handler deal with it
  }

  // === STATUS ===

  String getStatusString() {
    if (maskShaders.size() == 0) {
      return "No masks";
    }
    return currentMaskName + " [" + (currentMaskIndex + 1) + "/" + maskShaders.size() + "]";
  }
}
