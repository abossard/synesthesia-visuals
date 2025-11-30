/**
 * LaunchpadGrid — Note↔Cell math and LED color constants
 * 
 * Handles conversion between MIDI notes and grid coordinates
 * for Launchpad Mini Mk3 in Programmer mode.
 * 
 * Grid layout (Programmer mode):
 *   Row 8: 81 82 83 84 85 86 87 88 | 89 (scene)
 *   Row 7: 71 72 73 74 75 76 77 78 | 79
 *   ...
 *   Row 1: 11 12 13 14 15 16 17 18 | 19
 * 
 * Columns 0-7 are the main 8x8 grid
 * Column 8 (notes ending in 9) are scene launch buttons
 */

// ============================================
// LED COLOR CONSTANTS (Launchpad Mini Mk3)
// ============================================

static final int LP_OFF = 0;

// Basic colors
static final int LP_WHITE = 3;
static final int LP_WHITE_DIM = 1;

// Reds
static final int LP_RED = 5;
static final int LP_RED_DIM = 1;
static final int LP_RED_BRIGHT = 6;

// Oranges
static final int LP_ORANGE = 9;
static final int LP_ORANGE_DIM = 7;
static final int LP_AMBER = 11;

// Yellows
static final int LP_YELLOW = 13;
static final int LP_YELLOW_DIM = 12;

// Greens
static final int LP_GREEN = 21;
static final int LP_GREEN_DIM = 17;
static final int LP_GREEN_BRIGHT = 23;
static final int LP_LIME = 17;

// Cyans
static final int LP_CYAN = 37;
static final int LP_CYAN_DIM = 33;

// Blues
static final int LP_BLUE = 45;
static final int LP_BLUE_DIM = 41;
static final int LP_BLUE_BRIGHT = 47;

// Purples
static final int LP_PURPLE = 53;
static final int LP_PURPLE_DIM = 49;
static final int LP_VIOLET = 49;

// Pinks/Magentas
static final int LP_PINK = 57;
static final int LP_MAGENTA = 53;
static final int LP_HOT_PINK = 57;


// ============================================
// LAUNCHPAD GRID CLASS
// ============================================

class LaunchpadGrid {
  
  private MidiIO midi;
  
  LaunchpadGrid(MidiIO midi) {
    this.midi = midi;
  }
  
  // ============================================
  // NOTE ↔ CELL CONVERSION
  // ============================================
  
  /**
   * Convert MIDI note to grid cell (col, row)
   * Returns null if not a valid 8x8 pad
   */
  PVector noteToCell(int note) {
    int col = (note % 10) - 1;
    int row = (note / 10) - 1;
    
    if (col >= 0 && col < 8 && row >= 0 && row < 8) {
      return new PVector(col, row);
    }
    return null;
  }
  
  /**
   * Convert grid cell to MIDI note
   */
  int cellToNote(int col, int row) {
    return (row + 1) * 10 + (col + 1);
  }
  
  /**
   * Check if note is a valid 8x8 pad (not scene button)
   */
  boolean isValidPad(int note) {
    int col = note % 10;
    int row = note / 10;
    return col >= 1 && col <= 8 && row >= 1 && row <= 8;
  }
  
  /**
   * Check if note is a scene launch button (right column)
   */
  boolean isSceneButton(int note) {
    int col = note % 10;
    int row = note / 10;
    return col == 9 && row >= 1 && row <= 8;
  }
  
  /**
   * Get scene button index (0-7) from note
   * Returns -1 if not a scene button
   */
  int getSceneIndex(int note) {
    if (!isSceneButton(note)) return -1;
    return (note / 10) - 1;
  }
  
  // ============================================
  // LED CONTROL
  // ============================================
  
  /**
   * Light a single pad at grid position
   */
  void lightPad(int col, int row, int colorIndex) {
    if (midi == null || !midi.isConnected()) return;
    int note = cellToNote(col, row);
    midi.sendLED(note, colorIndex);
  }
  
  /**
   * Clear a single pad
   */
  void clearPad(int col, int row) {
    lightPad(col, row, LP_OFF);
  }
  
  /**
   * Light a scene button (index 0-7)
   */
  void lightSceneButton(int index, int colorIndex) {
    if (midi == null || !midi.isConnected()) return;
    if (index < 0 || index > 7) return;
    int note = (index + 1) * 10 + 9;
    midi.sendLED(note, colorIndex);
  }
  
  /**
   * Clear all pads on the 8x8 grid
   */
  void clearAllPads() {
    if (midi == null || !midi.isConnected()) return;
    
    for (int row = 0; row < 8; row++) {
      for (int col = 0; col < 8; col++) {
        clearPad(col, row);
      }
    }
  }
  
  /**
   * Clear all scene buttons
   */
  void clearSceneButtons() {
    if (midi == null || !midi.isConnected()) return;
    
    for (int i = 0; i < 8; i++) {
      lightSceneButton(i, LP_OFF);
    }
  }
  
  /**
   * Clear entire Launchpad (pads + scene buttons)
   */
  void clearAll() {
    clearAllPads();
    clearSceneButtons();
  }
  
  /**
   * Light all pads with same color
   */
  void fillAll(int colorIndex) {
    if (midi == null || !midi.isConnected()) return;
    
    for (int row = 0; row < 8; row++) {
      for (int col = 0; col < 8; col++) {
        lightPad(col, row, colorIndex);
      }
    }
  }
  
  /**
   * Light a specific row with a color
   */
  void lightRow(int row, int colorIndex) {
    if (midi == null || !midi.isConnected()) return;
    if (row < 0 || row > 7) return;
    
    for (int col = 0; col < 8; col++) {
      lightPad(col, row, colorIndex);
    }
  }
  
  /**
   * Light a specific column with a color
   */
  void lightColumn(int col, int colorIndex) {
    if (midi == null || !midi.isConnected()) return;
    if (col < 0 || col > 7) return;
    
    for (int row = 0; row < 8; row++) {
      lightPad(col, row, colorIndex);
    }
  }
}
