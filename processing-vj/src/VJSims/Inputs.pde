/**
 * Inputs — Per-frame input data passed to levels
 * 
 * Contains timing, audio levels, and pad events.
 * Audio is for visual modulation only, not FSM logic.
 */

class Inputs {
  
  // Timing
  float dt;           // Delta time in seconds
  int frameNum;       // Current frame number
  
  // Audio levels (0-1, for visual modulation)
  float bassLevel;
  float midLevel;
  float highLevel;
  
  // Pad events this frame
  ArrayList<PadEvent> padEvents;
  
  Inputs() {
    dt = 1.0 / 60.0;
    frameNum = 0;
    bassLevel = 0;
    midLevel = 0;
    highLevel = 0;
    padEvents = new ArrayList<PadEvent>();
  }
  
  /**
   * Clear events for next frame
   */
  void clear() {
    padEvents.clear();
  }
  
  /**
   * Add a pad event
   */
  void addPadEvent(int col, int row, int velocity) {
    padEvents.add(new PadEvent(col, row, velocity));
  }
  
  /**
   * Get overall audio level (average of bands)
   */
  float getLevel() {
    return (bassLevel + midLevel + highLevel) / 3.0;
  }
  
  /**
   * Check if any audio band is above threshold
   */
  boolean hasAudioPeak(float threshold) {
    return bassLevel > threshold || midLevel > threshold || highLevel > threshold;
  }
}

/**
 * PadEvent — Single pad press/release event
 */
class PadEvent {
  int col;
  int row;
  int velocity;  // 0 = release, 1-127 = press
  
  PadEvent(int col, int row, int velocity) {
    this.col = col;
    this.row = row;
    this.velocity = velocity;
  }
  
  boolean isPress() {
    return velocity > 0;
  }
  
  boolean isRelease() {
    return velocity == 0;
  }
}
