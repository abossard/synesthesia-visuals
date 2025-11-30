/**
 * LaunchpadHUD — LED state buffer with batch updates
 * 
 * Maintains a virtual representation of the Launchpad LED state.
 * Only sends MIDI messages when state changes, reducing MIDI traffic.
 * Supports dirty tracking and batch updates.
 */

class LaunchpadHUD {
  
  private LaunchpadGrid grid;
  
  // LED state buffer: [row][col] = colorIndex
  private int[][] state;
  private int[][] pending;
  private boolean[][] dirty;
  
  // Scene button state
  private int[] sceneState;
  private int[] scenePending;
  private boolean[] sceneDirty;
  
  // Batch mode
  private boolean batchMode = false;
  
  LaunchpadHUD(LaunchpadGrid grid) {
    this.grid = grid;
    
    // Initialize state buffers
    state = new int[8][8];
    pending = new int[8][8];
    dirty = new boolean[8][8];
    
    sceneState = new int[8];
    scenePending = new int[8];
    sceneDirty = new boolean[8];
    
    // Clear to known state
    clearState();
  }
  
  // ============================================
  // STATE MANAGEMENT
  // ============================================
  
  /**
   * Reset all state to off
   */
  void clearState() {
    for (int row = 0; row < 8; row++) {
      for (int col = 0; col < 8; col++) {
        state[row][col] = LP_OFF;
        pending[row][col] = LP_OFF;
        dirty[row][col] = false;
      }
    }
    for (int i = 0; i < 8; i++) {
      sceneState[i] = LP_OFF;
      scenePending[i] = LP_OFF;
      sceneDirty[i] = false;
    }
  }
  
  /**
   * Get current color at position
   */
  int getColor(int col, int row) {
    if (col < 0 || col > 7 || row < 0 || row > 7) return LP_OFF;
    return batchMode ? pending[row][col] : state[row][col];
  }
  
  /**
   * Get scene button color
   */
  int getSceneColor(int index) {
    if (index < 0 || index > 7) return LP_OFF;
    return batchMode ? scenePending[index] : sceneState[index];
  }
  
  // ============================================
  // SETTING LEDS
  // ============================================
  
  /**
   * Set pad color (immediate or batched)
   */
  void setPad(int col, int row, int colorIndex) {
    if (col < 0 || col > 7 || row < 0 || row > 7) return;
    
    if (batchMode) {
      if (pending[row][col] != colorIndex) {
        pending[row][col] = colorIndex;
        dirty[row][col] = true;
      }
    } else {
      if (state[row][col] != colorIndex) {
        state[row][col] = colorIndex;
        grid.lightPad(col, row, colorIndex);
      }
    }
  }
  
  /**
   * Set scene button color
   */
  void setSceneButton(int index, int colorIndex) {
    if (index < 0 || index > 7) return;
    
    if (batchMode) {
      if (scenePending[index] != colorIndex) {
        scenePending[index] = colorIndex;
        sceneDirty[index] = true;
      }
    } else {
      if (sceneState[index] != colorIndex) {
        sceneState[index] = colorIndex;
        grid.lightSceneButton(index, colorIndex);
      }
    }
  }
  
  /**
   * Clear a pad
   */
  void clearPad(int col, int row) {
    setPad(col, row, LP_OFF);
  }
  
  /**
   * Clear all pads
   */
  void clearAllPads() {
    for (int row = 0; row < 8; row++) {
      for (int col = 0; col < 8; col++) {
        setPad(col, row, LP_OFF);
      }
    }
  }
  
  /**
   * Clear all scene buttons
   */
  void clearSceneButtons() {
    for (int i = 0; i < 8; i++) {
      setSceneButton(i, LP_OFF);
    }
  }
  
  /**
   * Clear everything
   */
  void clearAll() {
    clearAllPads();
    clearSceneButtons();
  }
  
  // ============================================
  // ROW/COLUMN HELPERS
  // ============================================
  
  /**
   * Set entire row to a color
   */
  void setRow(int row, int colorIndex) {
    if (row < 0 || row > 7) return;
    for (int col = 0; col < 8; col++) {
      setPad(col, row, colorIndex);
    }
  }
  
  /**
   * Set entire column to a color
   */
  void setColumn(int col, int colorIndex) {
    if (col < 0 || col > 7) return;
    for (int row = 0; row < 8; row++) {
      setPad(col, row, colorIndex);
    }
  }
  
  /**
   * Set row with individual colors per column
   */
  void setRowColors(int row, int[] colors) {
    if (row < 0 || row > 7) return;
    for (int col = 0; col < min(8, colors.length); col++) {
      setPad(col, row, colors[col]);
    }
  }
  
  // ============================================
  // BATCH MODE
  // ============================================
  
  /**
   * Begin batch update (changes are queued, not sent)
   */
  void beginBatch() {
    batchMode = true;
    
    // Copy current state to pending
    for (int row = 0; row < 8; row++) {
      for (int col = 0; col < 8; col++) {
        pending[row][col] = state[row][col];
        dirty[row][col] = false;
      }
    }
    for (int i = 0; i < 8; i++) {
      scenePending[i] = sceneState[i];
      sceneDirty[i] = false;
    }
  }
  
  /**
   * End batch and send all changes
   */
  void endBatch() {
    if (!batchMode) return;
    
    // Send dirty pads
    for (int row = 0; row < 8; row++) {
      for (int col = 0; col < 8; col++) {
        if (dirty[row][col]) {
          state[row][col] = pending[row][col];
          grid.lightPad(col, row, state[row][col]);
          dirty[row][col] = false;
        }
      }
    }
    
    // Send dirty scene buttons
    for (int i = 0; i < 8; i++) {
      if (sceneDirty[i]) {
        sceneState[i] = scenePending[i];
        grid.lightSceneButton(i, sceneState[i]);
        sceneDirty[i] = false;
      }
    }
    
    batchMode = false;
  }
  
  /**
   * Cancel batch without sending
   */
  void cancelBatch() {
    batchMode = false;
  }
  
  // ============================================
  // VISUAL EFFECTS
  // ============================================
  
  /**
   * Flash all pads with a color (non-blocking, call in draw loop)
   */
  void flashAll(int colorIndex, int frameCount, int flashFrames) {
    boolean on = (frameCount % (flashFrames * 2)) < flashFrames;
    if (on) {
      for (int row = 0; row < 8; row++) {
        for (int col = 0; col < 8; col++) {
          setPad(col, row, colorIndex);
        }
      }
    } else {
      clearAllPads();
    }
  }
  
  /**
   * Pulse a specific pad (call in draw loop)
   */
  void pulsePad(int col, int row, int colorOn, int colorOff, int frameCount, int pulseFrames) {
    boolean on = (frameCount % (pulseFrames * 2)) < pulseFrames;
    setPad(col, row, on ? colorOn : colorOff);
  }
  
  /**
   * Show level selection on top row
   * activeLevel: currently active (green)
   * queuedLevel: queued next (amber)
   * availableLevels: how many levels are available (dim)
   */
  void showLevelRow(int activeLevel, int queuedLevel, int availableLevels) {
    for (int col = 0; col < 8; col++) {
      int color = LP_OFF;
      
      if (col == activeLevel) {
        color = LP_GREEN;
      } else if (col == queuedLevel) {
        color = LP_AMBER;
      } else if (col < availableLevels) {
        color = LP_WHITE_DIM;
      }
      
      setPad(col, 7, color);  // Top row = row 7
    }
  }
  
  /**
   * Force sync all state to hardware
   * Use sparingly (sends all 64 pads + 8 scene buttons)
   */
  void forceSync() {
    for (int row = 0; row < 8; row++) {
      for (int col = 0; col < 8; col++) {
        grid.lightPad(col, row, state[row][col]);
      }
    }
    for (int i = 0; i < 8; i++) {
      grid.lightSceneButton(i, sceneState[i]);
    }
  }
}
