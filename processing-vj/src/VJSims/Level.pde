/**
 * Level — Interface for all VJ levels
 * 
 * Each level implements this interface to provide:
 * - Initialization with shared context
 * - Per-frame update and draw
 * - Launchpad pad handling
 * - FSM for game state management
 * - Cleanup on exit
 */

interface Level {
  
  /**
   * Initialize the level with shared resources
   * Called once when level becomes active
   */
  void init(SharedContext ctx);
  
  /**
   * Update level state
   * @param dt Delta time in seconds since last frame
   * @param inputs Current frame inputs (pads, audio levels)
   */
  void update(float dt, Inputs inputs);
  
  /**
   * Draw level visuals to the provided graphics buffer
   * @param g Graphics buffer (typically the main framebuffer)
   */
  void draw(PGraphics g);
  
  /**
   * Handle Launchpad pad press/release
   * @param col Pad column (0-7)
   * @param row Pad row (0-7)
   * @param velocity 0 = release, 1-127 = press velocity
   */
  void handlePad(int col, int row, int velocity);
  
  /**
   * Get the level's state machine
   * Used by LevelManager to check for exit conditions
   */
  LevelFSM getFSM();
  
  /**
   * Get display name for UI/debug
   */
  String getName();
  
  /**
   * Clean up resources when level is deactivated
   * Called before switching to another level
   */
  void dispose();
}
