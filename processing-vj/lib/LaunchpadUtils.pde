/**
 * Launchpad Mini Mk3 Utilities
 * 
 * Helper functions for working with Launchpad Mini Mk3 in Programmer mode.
 * Copy this file to your Processing sketch folder to use these utilities.
 * 
 * Requires: The MidiBus library
 */

// ============================================
// LAUNCHPAD COLOR PALETTE (common colors)
// ============================================

final int LP_OFF = 0;
final int LP_WHITE = 3;
final int LP_RED = 5;
final int LP_RED_DIM = 1;
final int LP_ORANGE = 9;
final int LP_YELLOW = 13;
final int LP_GREEN = 21;
final int LP_GREEN_DIM = 17;
final int LP_CYAN = 37;
final int LP_BLUE = 45;
final int LP_BLUE_DIM = 41;
final int LP_PURPLE = 53;
final int LP_PINK = 57;
final int LP_MAGENTA = 61;

// ============================================
// GRID CONVERSION UTILITIES
// ============================================

/**
 * Convert MIDI note to grid position (0-7, 0-7)
 * Returns null if note is not a valid pad
 */
PVector noteToGrid(int note) {
  int col = (note % 10) - 1;
  int row = (note / 10) - 1;
  if (col >= 0 && col < 8 && row >= 0 && row < 8) {
    return new PVector(col, row);
  }
  return null;
}

/**
 * Convert grid position (0-7, 0-7) to MIDI note
 */
int gridToNote(int col, int row) {
  return (row + 1) * 10 + (col + 1);
}

/**
 * Check if MIDI note is a valid 8x8 pad (not scene launch button)
 */
boolean isValidPad(int note) {
  int col = note % 10;
  int row = note / 10;
  return col >= 1 && col <= 8 && row >= 1 && row <= 8;
}

/**
 * Check if MIDI note is a scene launch button (right column)
 */
boolean isSceneLaunch(int note) {
  return note % 10 == 9 && note >= 19 && note <= 89;
}

// ============================================
// LED CONTROL
// ============================================

/**
 * Light a single pad at grid position with color
 */
void lightPad(MidiBus bus, int col, int row, int colorIndex) {
  int note = gridToNote(col, row);
  bus.sendNoteOn(0, note, colorIndex);
}

/**
 * Clear a single pad (turn off LED)
 */
void clearPad(MidiBus bus, int col, int row) {
  lightPad(bus, col, row, LP_OFF);
}

/**
 * Clear all pads on the 8x8 grid
 */
void clearAllPads(MidiBus bus) {
  for (int row = 0; row < 8; row++) {
    for (int col = 0; col < 8; col++) {
      clearPad(bus, col, row);
    }
  }
}

/**
 * Light all pads with the same color
 */
void lightAllPads(MidiBus bus, int colorIndex) {
  for (int row = 0; row < 8; row++) {
    for (int col = 0; col < 8; col++) {
      lightPad(bus, col, row, colorIndex);
    }
  }
}

/**
 * Light scene launch button (0-7 from bottom to top)
 */
void lightSceneButton(MidiBus bus, int index, int colorIndex) {
  int note = (index + 1) * 10 + 9;
  bus.sendNoteOn(0, note, colorIndex);
}

// ============================================
// ANIMATION HELPERS
// ============================================

/**
 * Create a rainbow wave animation across the grid
 */
void animateRainbow(MidiBus bus, int timeOffset) {
  for (int row = 0; row < 8; row++) {
    for (int col = 0; col < 8; col++) {
      int colorIndex = ((col + row + timeOffset) % 8) * 8;
      lightPad(bus, col, row, colorIndex);
    }
  }
}

/**
 * Flash all pads with a color, then clear
 */
void flashAll(MidiBus bus, int colorIndex, int duration) {
  lightAllPads(bus, colorIndex);
  delay(duration);
  clearAllPads(bus);
}

/**
 * Create a ripple effect from center
 */
void animateRipple(MidiBus bus, float phase, int colorIndex) {
  float centerX = 3.5;
  float centerY = 3.5;
  
  for (int row = 0; row < 8; row++) {
    for (int col = 0; col < 8; col++) {
      float dist = dist(col, row, centerX, centerY);
      float wave = sin(dist * 0.5 - phase);
      
      if (wave > 0.5) {
        lightPad(bus, col, row, colorIndex);
      } else {
        clearPad(bus, col, row);
      }
    }
  }
}

// ============================================
// VISUAL HELPERS (for screen display)
// ============================================

/**
 * Draw a representation of the Launchpad grid on screen
 */
void drawLaunchpadGrid(float x, float y, float size, int[][] colors) {
  float cellSize = size / 8;
  
  for (int row = 0; row < 8; row++) {
    for (int col = 0; col < 8; col++) {
      float cx = x + col * cellSize;
      float cy = y + (7 - row) * cellSize; // Flip Y to match Launchpad orientation
      
      // Get color from array or use default
      int colorVal = (colors != null && col < colors.length && row < colors[col].length) 
                     ? colors[col][row] : 50;
      
      fill(colorVal);
      stroke(100);
      rect(cx, cy, cellSize - 2, cellSize - 2);
    }
  }
}

/**
 * Convert Launchpad color index to Processing color (approximate)
 */
color launchpadColorToRGB(int lpColor) {
  // Simplified mapping - Launchpad has 128 colors
  // This maps common color ranges
  if (lpColor == 0) return color(20);
  if (lpColor <= 3) return color(255); // White
  if (lpColor <= 7) return color(255, 0, 0); // Red
  if (lpColor <= 11) return color(255, 128, 0); // Orange
  if (lpColor <= 15) return color(255, 255, 0); // Yellow
  if (lpColor <= 23) return color(0, 255, 0); // Green
  if (lpColor <= 39) return color(0, 255, 255); // Cyan
  if (lpColor <= 47) return color(0, 0, 255); // Blue
  if (lpColor <= 55) return color(128, 0, 255); // Purple
  if (lpColor <= 63) return color(255, 0, 128); // Pink
  return color(255); // Default
}
