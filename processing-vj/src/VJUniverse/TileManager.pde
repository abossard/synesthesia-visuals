/**
 * TileManager.pde - Manages tile grid and Syphon outputs
 * 
 * Responsibilities:
 * - Hold all Tile instances
 * - Initialize tiles with PApplet reference
 * - Update and render all tiles each frame
 * - Draw preview grid on main display
 * - Route OSC messages to appropriate tiles
 * - Keyboard routing for tile focus
 */

class TileManager {
  
  // === TILES ===
  ArrayList<Tile> tiles = new ArrayList<Tile>();
  
  // === LAYOUT ===
  int gridCols = 2;
  int gridRows = 2;
  int focusedTileIndex = -1;  // -1 = show all, 0+ = fullscreen single tile
  
  // === PREVIEW SETTINGS ===
  int previewPadding = 4;
  boolean showLabels = false;
  
  // === REFERENCE ===
  PApplet parent;
  
  /**
   * Constructor
   */
  TileManager(PApplet parent) {
    this.parent = parent;
  }
  
  /**
   * Add a tile to the manager
   */
  void addTile(Tile tile) {
    tile.init(parent);
    tiles.add(tile);
    updateGridLayout();
  }
  
  /**
   * Remove a tile by name
   */
  void removeTile(String name) {
    Tile toRemove = null;
    for (Tile t : tiles) {
      if (t.name.equals(name)) {
        toRemove = t;
        break;
      }
    }
    if (toRemove != null) {
      toRemove.dispose();
      tiles.remove(toRemove);
      updateGridLayout();
    }
  }
  
  /**
   * Get tile by name
   */
  Tile getTile(String name) {
    for (Tile t : tiles) {
      if (t.name.equals(name)) return t;
    }
    return null;
  }
  
  /**
   * Update grid layout based on tile count
   */
  void updateGridLayout() {
    int count = tiles.size();
    if (count == 0) {
      gridCols = 1;
      gridRows = 1;
    } else if (count == 1) {
      gridCols = 1;
      gridRows = 1;
    } else if (count == 2) {
      gridCols = 2;
      gridRows = 1;
    } else if (count <= 4) {
      gridCols = 2;
      gridRows = 2;
    } else if (count <= 6) {
      gridCols = 2;
      gridRows = 3;
    } else {
      gridCols = 3;
      gridRows = 3;
    }
  }
  
  /**
   * Update all tiles
   */
  void update() {
    for (Tile t : tiles) {
      if (t.visible) {
        t.update();
      }
    }
  }
  
  /**
   * Render all tiles to their buffers
   */
  void render() {
    for (Tile t : tiles) {
      if (t.visible) {
        t.render();
      }
    }
  }
  
  /**
   * Send all tile buffers to Syphon
   */
  void sendToSyphon() {
    for (Tile t : tiles) {
      if (t.visible) {
        t.sendToSyphon();
      }
    }
  }
  
  /**
   * Draw preview grid on main display
   */
  void drawPreview(int displayWidth, int displayHeight) {
    if (tiles.size() == 0) return;
    
    // Fullscreen single tile mode
    if (focusedTileIndex >= 0 && focusedTileIndex < tiles.size()) {
      Tile focused = tiles.get(focusedTileIndex);
      float tileAspect = getTileAspect(focused);
      float drawW = displayWidth;
      float drawH = drawW / tileAspect;
      if (drawH > displayHeight) {
        drawH = displayHeight;
        drawW = drawH * tileAspect;
      }
      float drawX = (displayWidth - drawW) * 0.5;
      float drawY = (displayHeight - drawH) * 0.5;
      
      PGraphics focusedBuffer = focused.getBuffer();
      if (focusedBuffer != null) {
        parent.image(focusedBuffer, drawX, drawY, drawW, drawH);
      } else {
        parent.fill(30);
        parent.noStroke();
        parent.rect(drawX, drawY, drawW, drawH);
      }
      
      // Border
      parent.noFill();
      parent.stroke(80);
      parent.strokeWeight(1);
      parent.rect(drawX, drawY, drawW, drawH);
      
      // Draw overlay info (not in Syphon)
      if (showLabels) {
        drawTileOverlay(focused, drawX, drawY, drawW, drawH, true);
      }
      return;
    }
    
    // Grid preview mode
    float cellWidth = (displayWidth - previewPadding * (gridCols + 1)) / (float) gridCols;
    float cellHeight = (displayHeight - previewPadding * (gridRows + 1)) / (float) gridRows;
    
    int idx = 0;
    for (int row = 0; row < gridRows && idx < tiles.size(); row++) {
      for (int col = 0; col < gridCols && idx < tiles.size(); col++) {
        Tile t = tiles.get(idx);
        
        float x = previewPadding + col * (cellWidth + previewPadding);
        float y = previewPadding + row * (cellHeight + previewPadding);
        
        // Fit tile buffer inside the cell while preserving aspect ratio.
        float tileAspect = getTileAspect(t);
        float drawW = cellWidth;
        float drawH = drawW / tileAspect;
        if (drawH > cellHeight) {
          drawH = cellHeight;
          drawW = drawH * tileAspect;
        }
        float drawX = x + (cellWidth - drawW) * 0.5;
        float drawY = y + (cellHeight - drawH) * 0.5;
        
        // Draw tile buffer
        PGraphics previewBuffer = t.getBuffer();
        if (previewBuffer != null) {
          parent.image(previewBuffer, drawX, drawY, drawW, drawH);
        } else {
          // Placeholder for uninitialized tile
          parent.fill(30);
          parent.noStroke();
          parent.rect(drawX, drawY, drawW, drawH);
        }
        
        // Border
        parent.noFill();
        parent.stroke(80);
        parent.strokeWeight(1);
        parent.rect(drawX, drawY, drawW, drawH);
        
        // Draw overlay info (not in Syphon)
        if (showLabels) {
          drawTileOverlay(t, drawX, drawY, drawW, drawH, false);
        }
        
        idx++;
      }
    }
  }
  
  float getTileAspect(Tile t) {
    if (t == null) return 16.0f / 9.0f;
    if (t.buffer != null && t.buffer.height > 0) {
      return (float) t.buffer.width / (float) t.buffer.height;
    }
    if (t.bufferHeight > 0) {
      return (float) t.bufferWidth / (float) t.bufferHeight;
    }
    return 16.0f / 9.0f;
  }
  
  /**
   * Draw tile overlay with title, Syphon name, and OSC info
   * This is drawn AFTER the tile buffer image, so it's preview-only (not in Syphon)
   */
  void drawTileOverlay(Tile t, float x, float y, float w, float h, boolean large) {
    parent.pushStyle();
    
    float fontSize = large ? 14 : 10;
    float lineHeight = fontSize * 1.4;
    float padding = large ? 10 : 5;
    
    // === HEADER: Name + Syphon ===
    parent.textAlign(LEFT, TOP);
    parent.textSize(large ? 18 : 12);
    
    String header = t.name + "  →  " + t.syphonName;
    float headerH = large ? 26 : 18;
    
    // Header background
    parent.noStroke();
    parent.fill(0, 200);
    parent.rect(x, y, w, headerH);
    
    // Header text
    parent.fill(255);
    parent.text(header, x + padding, y + 2);
    
    // === OSC INFO PANEL ===
    if (t.oscAddresses.length > 0) {
      float oscPanelY = y + headerH + 2;
      float oscLineH = fontSize * 1.3;
      float oscPanelH = t.oscAddresses.length * oscLineH + padding * 2;
      
      // OSC panel background (semi-transparent)
      parent.fill(0, 150);
      parent.rect(x, oscPanelY, w, oscPanelH);
      
      // Draw each OSC address with glow
      parent.textSize(fontSize);
      for (int i = 0; i < t.oscAddresses.length; i++) {
        float lineY = oscPanelY + padding + i * oscLineH;
        float glow = t.getOSCGlow(i);
        
        // Glow background when recently received
        if (glow > 0) {
          parent.fill(0, 255, 100, glow * 180);
          parent.rect(x + 1, lineY - 1, w - 2, oscLineH, 2);
        }
        
        // Address
        parent.fill(glow > 0 ? color(150, 255, 150) : color(120, 180, 255));
        parent.text(t.oscAddresses[i], x + padding, lineY);
        
        // Description (right side, dimmer)
        if (i < t.oscDescriptions.length) {
          parent.fill(glow > 0 ? color(200, 255, 200) : color(150));
          parent.textAlign(RIGHT, TOP);
          parent.text(t.oscDescriptions[i], x + w - padding, lineY);
          parent.textAlign(LEFT, TOP);
        }
      }
    }
    
    // === TILE INDEX BADGE (bottom-left) ===
    int idx = tiles.indexOf(t);
    if (idx >= 0) {
      String badge = "[" + (idx + 1) + "]";
      parent.textAlign(LEFT, BOTTOM);
      parent.textSize(large ? 16 : 11);
      float badgeW = parent.textWidth(badge) + 8;
      
      parent.fill(0, 180);
      parent.rect(x, y + h - (large ? 24 : 16), badgeW, large ? 24 : 16);
      
      parent.fill(255, 200);
      parent.text(badge, x + 4, y + h - 3);
    }
    
    parent.popStyle();
  }
  
  /**
   * Draw tile label with background (legacy - now using drawTileOverlay)
   */
  void drawTileLabel(String name, float x, float y, boolean large) {
    parent.pushStyle();
    parent.textAlign(LEFT, BOTTOM);
    parent.textSize(large ? 18 : 12);
    
    float tw = parent.textWidth(name);
    float th = large ? 22 : 16;
    
    parent.noStroke();
    parent.fill(0, 180);
    parent.rect(x - 2, y - th + 2, tw + 8, th, 3);
    
    parent.fill(255);
    parent.text(name, x + 2, y);
    parent.popStyle();
  }
  
  /**
   * Handle OSC message - route to tiles
   * Returns true if any tile handled it
   */
  boolean handleOSC(OscMessage msg) {
    for (Tile t : tiles) {
      if (t.handleOSC(msg)) return true;
    }
    return false;
  }
  
  /**
   * Handle key press - route to tiles
   * Returns true if any tile consumed it
   */
  boolean handleKey(char key, int keyCode) {
    // Number keys 1-5 for tile focus (toggle back to grid)
    if (key >= '1' && key <= '5') {
      int idx = key - '1';
      if (idx < tiles.size()) {
        focusedTileIndex = (focusedTileIndex == idx) ? -1 : idx;
        println("[TileManager] Focus: " + (focusedTileIndex < 0 ? "all" : tiles.get(focusedTileIndex).name));
        return true;
      }
    }
    
    // Route to focused tile only (if any)
    if (focusedTileIndex >= 0 && focusedTileIndex < tiles.size()) {
      return tiles.get(focusedTileIndex).handleKey(key, keyCode);
    }
    
    return false;
  }
  
  /**
   * Toggle tile visibility by name
   */
  void toggleTile(String name) {
    Tile t = getTile(name);
    if (t != null) {
      t.visible = !t.visible;
      println("[TileManager] " + name + " visibility: " + t.visible);
    }
  }

  Tile getFocusedTile() {
    if (focusedTileIndex >= 0 && focusedTileIndex < tiles.size()) {
      return tiles.get(focusedTileIndex);
    }
    return null;
  }

  int getFocusedTileIndex() {
    return focusedTileIndex;
  }

  String getTileShortcutLabels() {
    if (tiles.size() == 0) return "No tiles";
    StringBuilder sb = new StringBuilder();
    int count = min(tiles.size(), 5);
    for (int i = 0; i < count; i++) {
      if (i > 0) sb.append(" | ");
      sb.append((i + 1) + " " + tiles.get(i).name);
    }
    return sb.toString();
  }
  
  String getTileOrderString() {
    if (tiles.size() == 0) return "Tiles: none";
    StringBuilder sb = new StringBuilder();
    sb.append("Tiles: ");
    for (int i = 0; i < tiles.size(); i++) {
      if (i > 0) sb.append(", ");
      sb.append((i + 1) + " " + tiles.get(i).name);
    }
    return sb.toString();
  }
  
  /**
   * Get status string for debug overlay
   */
  String getStatusString() {
    StringBuilder sb = new StringBuilder();
    sb.append("Tiles: ");
    for (int i = 0; i < tiles.size(); i++) {
      Tile t = tiles.get(i);
      if (i > 0) sb.append(", ");
      sb.append("[" + (i + 1) + "] " + t.name);
      if (!t.visible) sb.append(" (off)");
    }
    if (focusedTileIndex >= 0 && focusedTileIndex < tiles.size()) {
      sb.append(" | Focus: " + tiles.get(focusedTileIndex).name);
    }
    return sb.toString();
  }
  
  /**
   * Get tile count
   */
  int getTileCount() {
    return tiles.size();
  }
  
  /**
   * Dispose all tiles
   */
  void dispose() {
    for (Tile t : tiles) {
      t.dispose();
    }
    tiles.clear();
  }
}
