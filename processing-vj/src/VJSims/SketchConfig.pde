/**
 * SketchConfig — Configuration for the VJ system
 * 
 * Stores settings that can be adjusted at runtime or loaded from file.
 */

class SketchConfig {
  
  // Display (defaults, overridden by sketch size)
  int width = 1280;
  int height = 720;
  int targetFPS = 60;
  
  // Levels
  int[] levelOrder = {0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13};
  int defaultLevel = 0;
  
  // Timing
  float transitionDuration = 1.0;  // seconds
  int barsPerLevel = 16;           // for auto-rotate
  float bpm = 120;
  
  // Auto-rotate
  boolean autoRotate = false;
  
  SketchConfig() {
    // Default values set above
  }
  
  /**
   * Get beat duration in seconds
   */
  float getBeatDuration() {
    return 60.0 / bpm;
  }
  
  /**
   * Get bar duration in seconds (4 beats per bar)
   */
  float getBarDuration() {
    return getBeatDuration() * 4;
  }
  
  /**
   * Get level rotation interval in seconds
   */
  float getRotationInterval() {
    return getBarDuration() * barsPerLevel;
  }
}
