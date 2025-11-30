/**
 * LevelManager — Manages active level and level switching
 * 
 * Responsibilities:
 * - Maintain list of all levels
 * - Track active and queued levels
 * - Handle level transitions (instant cut for now)
 * - Route pad events to active level
 * - Update LED feedback for level selection
 */

class LevelManager {
  
  private ArrayList<Level> levels;
  private int activeIndex;
  private int queuedIndex;
  private Level activeLevel;
  private SharedContext ctx;
  
  // LED feedback
  private LaunchpadHUD hud;
  
  // Level selection row (row 7 = notes 71-78)
  private static final int LEVEL_ROW = 7;
  
  LevelManager(SharedContext ctx) {
    this.ctx = ctx;
    this.levels = new ArrayList<Level>();
    this.activeIndex = -1;
    this.queuedIndex = -1;
    this.activeLevel = null;
    this.hud = null;
  }
  
  /**
   * Set HUD for LED feedback
   */
  void setHUD(LaunchpadHUD hud) {
    this.hud = hud;
  }
  
  // ============================================
  // LEVEL REGISTRATION
  // ============================================
  
  /**
   * Add a level to the manager
   * Returns the level's index
   */
  int addLevel(Level level) {
    levels.add(level);
    return levels.size() - 1;
  }
  
  /**
   * Get level count
   */
  int getLevelCount() {
    return levels.size();
  }
  
  /**
   * Get level by index
   */
  Level getLevel(int index) {
    if (index < 0 || index >= levels.size()) return null;
    return levels.get(index);
  }
  
  /**
   * Get active level
   */
  Level getActiveLevel() {
    return activeLevel;
  }
  
  /**
   * Get active level index
   */
  int getActiveIndex() {
    return activeIndex;
  }
  
  // ============================================
  // LEVEL SWITCHING
  // ============================================
  
  /**
   * Immediately switch to a level (instant cut)
   */
  void switchTo(int index) {
    if (index < 0 || index >= levels.size()) return;
    if (index == activeIndex) return;
    
    // Dispose current level
    if (activeLevel != null) {
      activeLevel.dispose();
    }
    
    // Activate new level
    activeIndex = index;
    activeLevel = levels.get(index);
    activeLevel.init(ctx);
    
    // Clear queued
    queuedIndex = -1;
    
    // Update LEDs
    updateLevelLEDs();
    
    println("Switched to level " + index + ": " + activeLevel.getName());
  }
  
  /**
   * Queue a level for later transition
   * (For now, this just switches immediately)
   */
  void queueNext(int index) {
    if (index < 0 || index >= levels.size()) return;
    if (index == activeIndex) return;
    
    queuedIndex = index;
    updateLevelLEDs();
    
    // TODO: Wait for transition trigger
    // For now, switch immediately
    switchTo(index);
  }
  
  /**
   * Switch to next level (wrap around)
   */
  void nextLevel() {
    int next = (activeIndex + 1) % levels.size();
    switchTo(next);
  }
  
  /**
   * Switch to previous level (wrap around)
   */
  void prevLevel() {
    int prev = (activeIndex - 1 + levels.size()) % levels.size();
    switchTo(prev);
  }
  
  // ============================================
  // UPDATE & DRAW
  // ============================================
  
  /**
   * Update active level
   */
  void update(float dt, Inputs inputs) {
    if (activeLevel == null) return;
    
    // Process pad events for level
    for (PadEvent evt : inputs.padEvents) {
      // Check if it's a level selection pad (top row)
      if (evt.row == LEVEL_ROW && evt.isPress()) {
        // Top row selects levels 0-7
        if (evt.col < levels.size()) {
          queueNext(evt.col);
        }
      } else {
        // Forward to active level
        activeLevel.handlePad(evt.col, evt.row, evt.velocity);
      }
    }
    
    // Update level
    activeLevel.update(dt, inputs);
    
    // Check for exit condition
    if (activeLevel.getFSM().isExit()) {
      // Auto-advance to next level on exit
      nextLevel();
    }
  }
  
  /**
   * Draw active level to graphics buffer
   */
  void draw(PGraphics g) {
    if (activeLevel == null) {
      // No active level - draw black
      g.beginDraw();
      g.background(0);
      g.endDraw();
      return;
    }
    
    activeLevel.draw(g);
  }
  
  // ============================================
  // PAD HANDLING
  // ============================================
  
  /**
   * Handle pad press/release from main sketch
   * Returns true if handled by manager (level selection)
   */
  boolean handlePad(int col, int row, int velocity) {
    // Top row = level selection
    if (row == LEVEL_ROW && velocity > 0) {
      if (col < levels.size()) {
        queueNext(col);
        return true;
      }
    }
    
    // Forward to active level
    if (activeLevel != null) {
      activeLevel.handlePad(col, row, velocity);
    }
    
    return false;
  }
  
  /**
   * Handle scene button (right column)
   * Scene buttons could be used for level banks or special functions
   */
  void handleSceneButton(int index, int velocity) {
    if (velocity == 0) return;
    
    // Scene buttons 0-7 could select level banks
    // For now, just use as alternate level selection (8-15)
    int levelIndex = 8 + index;
    if (levelIndex < levels.size()) {
      queueNext(levelIndex);
    }
  }
  
  // ============================================
  // LED FEEDBACK
  // ============================================
  
  /**
   * Update level selection LEDs on top row
   */
  void updateLevelLEDs() {
    if (hud == null) return;
    
    hud.beginBatch();
    
    // Show available, active, and queued levels on top row
    for (int col = 0; col < 8; col++) {
      int color;
      
      if (col == activeIndex) {
        color = LP_GREEN;           // Active level
      } else if (col == queuedIndex) {
        color = LP_AMBER;           // Queued level
      } else if (col < levels.size()) {
        color = LP_WHITE_DIM;       // Available level
      } else {
        color = LP_OFF;             // No level
      }
      
      hud.setPad(col, LEVEL_ROW, color);
    }
    
    hud.endBatch();
  }
  
  /**
   * Show FSM state on a specific row
   */
  void showFSMState(int row) {
    if (hud == null || activeLevel == null) return;
    
    int stateColor = activeLevel.getFSM().getStateColor();
    
    hud.beginBatch();
    for (int col = 0; col < 8; col++) {
      hud.setPad(col, row, stateColor);
    }
    hud.endBatch();
  }
  
  // ============================================
  // UTILITY
  // ============================================
  
  /**
   * Initialize with first level
   */
  void start() {
    if (levels.size() > 0 && activeLevel == null) {
      switchTo(0);
    }
  }
  
  /**
   * Dispose all levels
   */
  void dispose() {
    for (Level level : levels) {
      level.dispose();
    }
    levels.clear();
    activeLevel = null;
    activeIndex = -1;
  }
  
  /**
   * Debug info
   */
  String toString() {
    String name = activeLevel != null ? activeLevel.getName() : "none";
    return "LevelManager[" + activeIndex + "/" + levels.size() + " : " + name + "]";
  }
}
