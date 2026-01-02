/**
 * ImageTile.pde - Image display tile with crossfade and beat-sync folder cycling
 * 
 * Features:
 * - Aspect-ratio preserving display (contain or cover mode)
 * - Crossfade transitions between images
 * - Folder mode: load all images, cycle on beat
 * - Async image loading (non-blocking)
 * - Syphon output: VJUniverse/Image
 * 
 * OSC Protocol:
 *   /image/load <path>           - Load single image (absolute or relative to data/)
 *   /image/folder <path>         - Load folder, cycle images on beat
 *   /image/next                  - Advance to next image (manual)
 *   /image/prev                  - Go to previous image
 *   /image/index <int>           - Jump to specific image index
 *   /image/clear                 - Clear current image
 *   /image/fit <mode>            - "contain" (show all) or "cover" (fill, crop)
 *   /image/fade <ms>             - Set crossfade duration (default 500ms)
 *   /image/beat <int>            - Beats between changes: 1=every beat, 4=every 4 beats, 0=manual
 */

class ImageTile extends Tile {
  
  // === IMAGE STATE ===
  PImage currentImage = null;     // Currently displayed (fading out during transition)
  PImage nextImage = null;        // Next image (fading in during transition)
  PImage pendingImage = null;     // Being loaded async
  String currentPath = "";
  boolean isLoading = false;
  
  // === FOLDER MODE ===
  ArrayList<String> folderImages = new ArrayList<String>();
  int folderIndex = 0;
  boolean folderMode = false;
  
  // === CROSSFADE ===
  float crossfadeProgress = 1.0;  // 0.0 = showing current, 1.0 = showing next (transition complete)
  int fadeDuration = 500;         // ms
  int fadeStartTime = 0;
  boolean fading = false;
  
  // === FIT MODE ===
  boolean coverMode = false;      // false = contain (show all), true = cover (fill, crop)
  
  // === BEAT CYCLING ===
  int beatsPerChange = 4;         // 0 = manual, 1 = every beat, 4 = every 4 beats
  int lastBeatCount = 0;
  
  // === OPTIMIZATION ===
  boolean needsRedraw = true;     // Set true when image changes
  boolean bufferDirty = true;     // Set true after buffer modified, false after Syphon send
  
  // === SUPPORTED EXTENSIONS ===
  final String[] IMAGE_EXTENSIONS = {".jpg", ".jpeg", ".png", ".gif", ".tif", ".tiff", ".bmp"};
  
  ImageTile() {
    super("Image", "VJUniverse/Image");
    setOSCAddresses(
      new String[] {"/image/load", "/image/folder", "/image/next", "/image/prev", 
                    "/image/index", "/image/clear", "/image/fit", "/image/fade", "/image/beat"},
      new String[] {"Load single image", "Load folder (beat cycle)", "Next image", "Previous image",
                    "Jump to index", "Clear image", "Fit mode", "Fade duration", "Beats per change"}
    );
  }
  
  // ==========================================================================
  // LIFECYCLE
  // ==========================================================================
  
  @Override
  void update() {
    checkPendingImage();
    updateCrossfade();
    updateBeatCycling();
  }
  
  @Override
  void render() {
    // Skip redraw if static image (no animation, no loading) - prevents flicker
    if (!fading && !isLoading && currentImage != null && !needsRedraw) {
      return;  // Buffer already contains the correct image
    }
    
    buffer.beginDraw();
    buffer.background(0, 0);  // Transparent for Syphon compositing
    
    // Crossfade logic:
    // - fading=true: draw currentImage fading out, nextImage fading in
    // - fading=false: draw currentImage at full opacity
    
    if (fading && currentImage != null && nextImage != null) {
      // Crossfade between two images
      float alphaOut = (1.0 - crossfadeProgress) * 255;
      float alphaIn = crossfadeProgress * 255;
      drawImageAspectRatio(buffer, currentImage, alphaOut);
      drawImageAspectRatio(buffer, nextImage, alphaIn);
    } else if (fading && nextImage != null) {
      // First image loading - fade in from black
      float alpha = crossfadeProgress * 255;
      drawImageAspectRatio(buffer, nextImage, alpha);
    } else if (currentImage != null) {
      // Steady state - show current at full opacity
      drawImageAspectRatio(buffer, currentImage, 255);
      needsRedraw = false;  // Mark as stable - skip future redraws
    }
    
    // Loading indicator
    if (isLoading) {
      buffer.fill(255, 100);
      buffer.noStroke();
      buffer.textAlign(CENTER, CENTER);
      buffer.textSize(16);
      buffer.text("Loading...", buffer.width / 2, buffer.height - 30);
    }
    
    buffer.endDraw();
    bufferDirty = true;  // We drew something - mark for Syphon
  }
  
  /**
   * Override sendToSyphon: only send when buffer changed
   */
  @Override
  void sendToSyphon() {
    if (!bufferDirty) return;  // Skip if buffer hasn't changed
    super.sendToSyphon();
    bufferDirty = false;
  }
  
  // ==========================================================================
  // IMAGE DRAWING - Pure calculation for aspect ratio (Grokking Simplicity)
  // ==========================================================================
  
  /**
   * Calculate draw dimensions preserving aspect ratio.
   * Pure function: no side effects.
   *
   * @param imgW    Image width
   * @param imgH    Image height
   * @param bufW    Buffer/container width
   * @param bufH    Buffer/container height
   * @param cover   true = cover (fill, may crop), false = contain (show all)
   * @return float[4] = {x, y, drawWidth, drawHeight}
   */
  float[] calcAspectRatioDimensions(float imgW, float imgH, float bufW, float bufH, boolean cover) {
    float imgAspect = imgW / imgH;
    float bufAspect = bufW / bufH;
    
    float drawW, drawH;
    
    if (cover) {
      // Cover: fill container, may crop
      if (imgAspect > bufAspect) {
        // Image wider - fit height, crop sides
        drawH = bufH;
        drawW = bufH * imgAspect;
      } else {
        // Image taller - fit width, crop top/bottom
        drawW = bufW;
        drawH = bufW / imgAspect;
      }
    } else {
      // Contain: show all, may have letterboxing
      if (imgAspect > bufAspect) {
        // Image wider - fit width
        drawW = bufW;
        drawH = bufW / imgAspect;
      } else {
        // Image taller - fit height
        drawH = bufH;
        drawW = bufH * imgAspect;
      }
    }
    
    // Center in buffer
    float x = (bufW - drawW) / 2;
    float y = (bufH - drawH) / 2;
    
    return new float[] { x, y, drawW, drawH };
  }
  
  /**
   * Draw image to buffer with aspect ratio preservation and alpha.
   */
  void drawImageAspectRatio(PGraphics pg, PImage img, float alpha) {
    if (img == null || img.width <= 0 || img.height <= 0) return;
    
    float[] dims = calcAspectRatioDimensions(img.width, img.height, pg.width, pg.height, coverMode);
    
    pg.imageMode(CORNER);
    pg.tint(255, alpha);
    pg.image(img, dims[0], dims[1], dims[2], dims[3]);
    pg.noTint();
  }
  
  // ==========================================================================
  // ASYNC IMAGE LOADING
  // ==========================================================================
  
  void loadImageAsync(String path) {
    // Resolve relative paths to data folder
    String resolvedPath = resolvePath(path);
    
    java.io.File file = new java.io.File(resolvedPath);
    if (!file.exists() || !file.canRead()) {
      println("[ImageTile] File not found: " + resolvedPath);
      return;
    }
    
    isLoading = true;
    needsRedraw = true;  // Force redraw when new image incoming
    currentPath = resolvedPath;
    pendingImage = requestImage(resolvedPath);
    println("[ImageTile] Loading: " + file.getName());
  }
  
  void checkPendingImage() {
    if (!isLoading || pendingImage == null) return;
    
    if (pendingImage.width > 0 && pendingImage.height > 0) {
      // Success - start crossfade
      println("[ImageTile] Loaded: " + pendingImage.width + "x" + pendingImage.height);
      startCrossfade(pendingImage);
      pendingImage = null;
      isLoading = false;
    } else if (pendingImage.width == -1) {
      // Error
      println("[ImageTile] Load failed: " + currentPath);
      pendingImage = null;
      isLoading = false;
    }
    // else: still loading (width == 0)
  }
  
  /**
   * Resolve path: if not absolute, prepend data folder path.
   */
  String resolvePath(String path) {
    if (path.startsWith("/") || path.contains(":")) {
      return path;  // Already absolute
    }
    return dataPath(path);
  }
  
  // ==========================================================================
  // CROSSFADE ANIMATION
  // ==========================================================================
  
  void startCrossfade(PImage newImage) {
    // Move next to current, set new as next
    currentImage = nextImage;
    nextImage = newImage;
    needsRedraw = true;  // New image - force redraw
    
    // Always fade - even first image fades in from black
    crossfadeProgress = 0.0;
    fadeStartTime = millis();
    fading = true;
  }
  
  void updateCrossfade() {
    if (!fading) return;
    
    needsRedraw = true;  // Keep redrawing during fade animation
    
    int elapsed = millis() - fadeStartTime;
    crossfadeProgress = constrain((float) elapsed / fadeDuration, 0, 1);
    
    // Ease in-out for smooth transition
    crossfadeProgress = easeInOutQuad(crossfadeProgress);
    
    if (elapsed >= fadeDuration) {
      fading = false;
      crossfadeProgress = 1.0;
      // Transition complete: next becomes current, clear next
      currentImage = nextImage;
      nextImage = null;
      needsRedraw = true;  // Final frame after fade
    }
  }
  
  /**
   * Quadratic ease in-out. Pure function.
   */
  float easeInOutQuad(float t) {
    return t < 0.5 
      ? 2 * t * t 
      : 1 - pow(-2 * t + 2, 2) / 2;
  }
  
  // ==========================================================================
  // FOLDER MODE
  // ==========================================================================
  
  void loadFolder(String folderPath) {
    String resolvedPath = resolvePath(folderPath);
    java.io.File folder = new java.io.File(resolvedPath);
    
    if (!folder.exists() || !folder.isDirectory()) {
      println("[ImageTile] Folder not found: " + resolvedPath);
      return;
    }
    
    // Clear previous state completely
    folderImages.clear();
    currentImage = null;
    nextImage = null;
    pendingImage = null;
    fading = false;
    crossfadeProgress = 1.0;
    needsRedraw = true;
    
    // Scan for image files
    java.io.File[] files = folder.listFiles();
    if (files != null) {
      for (java.io.File file : files) {
        if (file.isFile() && isImageFile(file.getName())) {
          folderImages.add(file.getAbsolutePath());
        }
      }
    }
    
    // Sort for consistent ordering
    java.util.Collections.sort(folderImages);
    
    if (folderImages.size() == 0) {
      println("[ImageTile] No images found in: " + resolvedPath);
      folderMode = false;
      return;
    }
    
    folderMode = true;
    folderIndex = 0;
    println("[ImageTile] Loaded folder: " + folderImages.size() + " images");
    
    // Load first image
    loadImageAsync(folderImages.get(0));
  }
  
  boolean isImageFile(String filename) {
    String lower = filename.toLowerCase();
    for (String ext : IMAGE_EXTENSIONS) {
      if (lower.endsWith(ext)) return true;
    }
    return false;
  }
  
  void nextFolderImage() {
    if (!folderMode || folderImages.size() == 0) return;
    folderIndex = (folderIndex + 1) % folderImages.size();
    loadImageAsync(folderImages.get(folderIndex));
  }
  
  void prevFolderImage() {
    if (!folderMode || folderImages.size() == 0) return;
    folderIndex = (folderIndex - 1 + folderImages.size()) % folderImages.size();
    loadImageAsync(folderImages.get(folderIndex));
  }
  
  void jumpToIndex(int index) {
    if (!folderMode || folderImages.size() == 0) return;
    folderIndex = constrain(index, 0, folderImages.size() - 1);
    loadImageAsync(folderImages.get(folderIndex));
  }
  
  // ==========================================================================
  // BEAT-SYNCED CYCLING
  // ==========================================================================
  
  void updateBeatCycling() {
    if (!folderMode || beatsPerChange <= 0 || folderImages.size() <= 1) return;
    
    // Use global beat counter from SynesthesiaAudio.pde
    int currentBeat = beat4;  // Global beat counter from audio system
    
    // Check if we've crossed a beat boundary
    if (currentBeat != lastBeatCount) {
      lastBeatCount = currentBeat;
      
      // Check if this beat triggers a change
      if (currentBeat % beatsPerChange == 0) {
        nextFolderImage();
      }
    }
  }
  
  // ==========================================================================
  // OSC HANDLING
  // ==========================================================================
  
  @Override
  boolean handleOSC(OscMessage msg) {
    String addr = msg.addrPattern();
    
    // /image/load <path>
    if (addr.equals("/image/load") && msg.typetag().length() >= 1) {
      folderMode = false;  // Exit folder mode
      loadImageAsync(msg.get(0).stringValue());
      markOSCReceived(addr);
      return true;
    }
    
    // /image/folder <path>
    if (addr.equals("/image/folder") && msg.typetag().length() >= 1) {
      loadFolder(msg.get(0).stringValue());
      markOSCReceived(addr);
      return true;
    }
    
    // /image/next
    if (addr.equals("/image/next")) {
      if (folderMode) {
        nextFolderImage();
      }
      markOSCReceived(addr);
      return true;
    }
    
    // /image/prev
    if (addr.equals("/image/prev")) {
      if (folderMode) {
        prevFolderImage();
      }
      markOSCReceived(addr);
      return true;
    }
    
    // /image/index <int>
    if (addr.equals("/image/index") && msg.typetag().length() >= 1) {
      jumpToIndex(msg.get(0).intValue());
      markOSCReceived(addr);
      return true;
    }
    
    // /image/clear
    if (addr.equals("/image/clear")) {
      currentImage = null;
      nextImage = null;
      pendingImage = null;
      currentPath = "";
      folderMode = false;
      folderImages.clear();
      isLoading = false;
      fading = false;
      crossfadeProgress = 1.0;
      markOSCReceived(addr);
      return true;
    }
    
    // /image/fit <mode>
    if (addr.equals("/image/fit") && msg.typetag().length() >= 1) {
      String mode = msg.get(0).stringValue().toLowerCase();
      coverMode = mode.equals("cover");
      println("[ImageTile] Fit mode: " + (coverMode ? "cover" : "contain"));
      markOSCReceived(addr);
      return true;
    }
    
    // /image/fade <ms>
    if (addr.equals("/image/fade") && msg.typetag().length() >= 1) {
      fadeDuration = max(0, msg.get(0).intValue());
      println("[ImageTile] Fade duration: " + fadeDuration + "ms");
      markOSCReceived(addr);
      return true;
    }
    
    // /image/beat <int>
    if (addr.equals("/image/beat") && msg.typetag().length() >= 1) {
      beatsPerChange = max(0, msg.get(0).intValue());
      println("[ImageTile] Beats per change: " + (beatsPerChange == 0 ? "manual" : beatsPerChange));
      markOSCReceived(addr);
      return true;
    }
    
    return false;
  }
  
  // ==========================================================================
  // KEYBOARD HANDLING
  // ==========================================================================
  
  @Override
  boolean handleKey(char key, int keyCode) {
    if (keyCode == RIGHT) {
      nextFolderImage();
      return true;
    }
    if (keyCode == LEFT) {
      prevFolderImage();
      return true;
    }
    return false;
  }
  
  // ==========================================================================
  // STATUS
  // ==========================================================================
  
  @Override
  String getStatusString() {
    if (isLoading) return "Loading...";
    
    String name = getCurrentImageName();
    if (folderMode) {
      String indexInfo = folderImages.size() > 0
        ? (folderIndex + 1) + "/" + folderImages.size()
        : "0/0";
      String beatInfo = beatsPerChange == 0 ? "manual" : ("beat:" + beatsPerChange);
      if (!name.isEmpty()) {
        return "Folder " + indexInfo + " - " + name + " (" + beatInfo + ")";
      }
      return "Folder " + indexInfo + " (" + beatInfo + ")";
    }
    if (!name.isEmpty()) return name;
    if (currentImage != null || nextImage != null) return "Image loaded";
    return "Empty";
  }

  String getCurrentImageName() {
    if (currentPath == null || currentPath.isEmpty()) return "";
    return new java.io.File(currentPath).getName();
  }
}
