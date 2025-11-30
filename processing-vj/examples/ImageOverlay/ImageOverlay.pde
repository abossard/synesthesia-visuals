/**
 * ImageOverlay - Loads and displays AI-generated images via OSC
 * 
 * Receives image file paths from the Python Karaoke Engine via OSC,
 * loads them dynamically, and outputs via Syphon for VJ compositing.
 * 
 * OSC Messages:
 *   /karaoke/image [path]     - Load and display image at absolute path
 *   /karaoke/image/clear      - Clear current image (show black)
 *   /karaoke/image/opacity [f] - Set image opacity (0.0-1.0)
 *   /karaoke/image/fade [ms]  - Set fade duration in milliseconds
 * 
 * Syphon Output:
 *   KaraokeImage - The loaded image with optional fade transitions
 * 
 * Controls:
 *   c - Clear image
 *   r - Reload current image
 *   +/- - Adjust opacity
 *   1-9 - Set opacity (10%-90%)
 *   0 - Set opacity to 100%
 */

// Syphon is macOS-only; stub for cross-platform development
boolean SYPHON_AVAILABLE = false;
Object syphon;  // Will be SyphonServer on macOS

import oscP5.*;
import netP5.*;

// OSC
OscP5 osc;
int OSC_PORT = 9000;

// Image state
PImage currentImage = null;
PImage nextImage = null;
String currentPath = "";
String pendingPath = "";
float imageOpacity = 1.0;
float targetOpacity = 1.0;
int fadeDuration = 500;  // ms

// Fade animation
boolean fading = false;
float fadeProgress = 0;
int fadeStartTime = 0;

// Logging
ArrayList<String> logs = new ArrayList<String>();
int MAX_LOGS = 20;
boolean showLogs = true;

// Loading state
boolean isLoading = false;

void settings() {
  size(1920, 1080, P3D);
}

void setup() {
  frameRate(60);
  background(0);
  
  // Initialize OSC
  osc = new OscP5(this, OSC_PORT);
  log("OSC listening on port " + OSC_PORT);
  
  // Initialize Syphon (macOS only)
  initSyphon();
  
  log("ImageOverlay ready");
  log("Waiting for /karaoke/image messages...");
}

void initSyphon() {
  try {
    // Try to load Syphon (macOS only)
    Class<?> syphonClass = Class.forName("codeanticode.syphon.SyphonServer");
    java.lang.reflect.Constructor<?> constructor = syphonClass.getConstructor(processing.core.PApplet.class, String.class);
    syphon = constructor.newInstance(this, "KaraokeImage");
    SYPHON_AVAILABLE = true;
    log("Syphon: KaraokeImage server started");
  } catch (Exception e) {
    log("Syphon: Not available (macOS only)");
    SYPHON_AVAILABLE = false;
  }
}

void draw() {
  background(0);
  
  // Check for completed async image loading
  checkPendingImage();
  
  // Update fade animation
  updateFade();
  
  // Draw current image
  if (currentImage != null) {
    tint(255, imageOpacity * 255);
    imageMode(CENTER);
    
    // Scale to fit while maintaining aspect ratio
    float imgAspect = (float)currentImage.width / currentImage.height;
    float screenAspect = (float)width / height;
    
    float drawWidth, drawHeight;
    if (imgAspect > screenAspect) {
      drawWidth = width;
      drawHeight = width / imgAspect;
    } else {
      drawHeight = height;
      drawWidth = height * imgAspect;
    }
    
    image(currentImage, width/2, height/2, drawWidth, drawHeight);
    noTint();
  }
  
  // Draw loading indicator
  if (isLoading) {
    drawLoadingIndicator();
  }
  
  // Draw logs overlay
  if (showLogs) {
    drawLogs();
  }
  
  // Send to Syphon
  sendSyphon();
}

void updateFade() {
  if (fading) {
    int elapsed = millis() - fadeStartTime;
    fadeProgress = constrain((float)elapsed / fadeDuration, 0, 1);
    
    // Ease in-out
    fadeProgress = fadeProgress < 0.5 
      ? 2 * fadeProgress * fadeProgress 
      : 1 - pow(-2 * fadeProgress + 2, 2) / 2;
    
    imageOpacity = lerp(0, targetOpacity, fadeProgress);
    
    if (elapsed >= fadeDuration) {
      fading = false;
      imageOpacity = targetOpacity;
    }
  }
}

void drawLoadingIndicator() {
  pushStyle();
  fill(255, 150);
  noStroke();
  
  // Spinning dots
  int dots = 8;
  float radius = 40;
  float dotSize = 10;
  float angle = (millis() / 100.0) % TWO_PI;
  
  translate(width/2, height/2);
  for (int i = 0; i < dots; i++) {
    float a = angle + i * TWO_PI / dots;
    float x = cos(a) * radius;
    float y = sin(a) * radius;
    float alpha = map(i, 0, dots-1, 255, 50);
    fill(255, alpha);
    ellipse(x, y, dotSize, dotSize);
  }
  
  popStyle();
}

void drawLogs() {
  pushStyle();
  textAlign(LEFT, TOP);
  textSize(14);
  
  int y = 10;
  int maxToShow = min(logs.size(), 10);
  
  for (int i = logs.size() - maxToShow; i < logs.size(); i++) {
    String logLine = logs.get(i);
    
    // Color code by type
    if (logLine.contains("ERROR") || logLine.contains("✗")) {
      fill(255, 100, 100);
    } else if (logLine.contains("✓") || logLine.contains("Loaded")) {
      fill(100, 255, 100);
    } else if (logLine.contains("Loading")) {
      fill(255, 255, 100);
    } else {
      fill(200);
    }
    
    text(logLine, 10, y);
    y += 18;
  }
  
  // Status bar at bottom
  fill(100);
  textAlign(LEFT, BOTTOM);
  String status = "Image: " + (currentPath.isEmpty() ? "(none)" : new java.io.File(currentPath).getName());
  status += "  |  Opacity: " + nf(imageOpacity * 100, 0, 0) + "%";
  status += "  |  Press 'L' to toggle logs";
  text(status, 10, height - 10);
  
  popStyle();
}

void sendSyphon() {
  if (SYPHON_AVAILABLE && syphon != null) {
    try {
      java.lang.reflect.Method sendScreen = syphon.getClass().getMethod("sendScreen");
      sendScreen.invoke(syphon);
    } catch (Exception e) {
      // Ignore
    }
  }
}

// ============================================================================
// OSC Event Handler
// ============================================================================

void oscEvent(OscMessage msg) {
  String addr = msg.addrPattern();
  
  if (addr.equals("/karaoke/image")) {
    if (msg.typetag().length() > 0 && msg.typetag().charAt(0) == 's') {
      String path = msg.get(0).stringValue();
      loadImageAsync(path);
    }
  }
  else if (addr.equals("/karaoke/image/clear")) {
    clearImage();
  }
  else if (addr.equals("/karaoke/image/opacity")) {
    if (msg.typetag().length() > 0) {
      float opacity = msg.get(0).floatValue();
      setOpacity(opacity);
    }
  }
  else if (addr.equals("/karaoke/image/fade")) {
    if (msg.typetag().length() > 0) {
      fadeDuration = msg.get(0).intValue();
      log("Fade duration: " + fadeDuration + "ms");
    }
  }
}

// ============================================================================
// Image Loading
// ============================================================================

void loadImageAsync(String path) {
  if (path == null || path.isEmpty()) {
    log("ERROR: Empty image path received");
    return;
  }
  
  // Check if file exists
  java.io.File file = new java.io.File(path);
  if (!file.exists()) {
    log("ERROR: File not found: " + path);
    return;
  }
  
  if (!file.canRead()) {
    log("ERROR: Cannot read file: " + path);
    return;
  }
  
  // Check file extension
  String ext = path.substring(path.lastIndexOf('.') + 1).toLowerCase();
  if (!ext.equals("png") && !ext.equals("jpg") && !ext.equals("jpeg") && !ext.equals("gif")) {
    log("ERROR: Unsupported format: " + ext);
    return;
  }
  
  log("Loading: " + file.getName());
  pendingPath = path;
  isLoading = true;
  
  // Use requestImage() for async loading (thread-safe in Processing)
  // This returns immediately and loads in background
  nextImage = requestImage(pendingPath);
  currentPath = pendingPath;
}

// Called from draw() to check if async loading completed
void checkPendingImage() {
  if (isLoading && nextImage != null) {
    // Check if requestImage() has completed loading
    if (nextImage.width > 0 && nextImage.height > 0) {
      // Image loaded successfully
      currentImage = nextImage;
      nextImage = null;
      isLoading = false;
      startFadeIn();
      log("✓ Loaded: " + new java.io.File(currentPath).getName() + 
          " (" + currentImage.width + "x" + currentImage.height + ")");
    } else if (nextImage.width == -1) {
      // requestImage() returns width=-1 on error
      log("ERROR: Failed to load image");
      nextImage = null;
      isLoading = false;
    }
    // else: still loading (width == 0), wait for next frame
  }
}

void startFadeIn() {
  imageOpacity = 0;
  targetOpacity = 1.0;
  fadeProgress = 0;
  fadeStartTime = millis();
  fading = true;
}

void clearImage() {
  currentImage = null;
  currentPath = "";
  log("Image cleared");
}

void setOpacity(float opacity) {
  targetOpacity = constrain(opacity, 0, 1);
  imageOpacity = targetOpacity;
  log("Opacity: " + nf(targetOpacity * 100, 0, 0) + "%");
}

void reloadImage() {
  if (!currentPath.isEmpty()) {
    loadImageAsync(currentPath);
  }
}

// ============================================================================
// Keyboard Controls
// ============================================================================

void keyPressed() {
  if (key == 'c' || key == 'C') {
    clearImage();
  }
  else if (key == 'r' || key == 'R') {
    reloadImage();
  }
  else if (key == 'l' || key == 'L') {
    showLogs = !showLogs;
  }
  else if (key == '+' || key == '=') {
    setOpacity(targetOpacity + 0.1);
  }
  else if (key == '-' || key == '_') {
    setOpacity(targetOpacity - 0.1);
  }
  else if (key >= '1' && key <= '9') {
    setOpacity((key - '0') * 0.1);
  }
  else if (key == '0') {
    setOpacity(1.0);
  }
}

// ============================================================================
// Logging
// ============================================================================

void log(String message) {
  String timestamp = nf(hour(), 2) + ":" + nf(minute(), 2) + ":" + nf(second(), 2);
  String logLine = timestamp + " " + message;
  logs.add(logLine);
  
  if (logs.size() > MAX_LOGS) {
    logs.remove(0);
  }
  
  println(logLine);  // Also print to console
}
