/**
 * AudioEnvelope — Audio levels for visual modulation
 * 
 * Provides bass/mid/high levels (0-1) that can be:
 * - Manually controlled via Launchpad
 * - Fed from real audio input (Minim/Sound library)
 * 
 * This is for VISUAL effects only, not FSM/game logic.
 */

class AudioEnvelope {
  
  // Current levels (0-1)
  float bassLevel;
  float midLevel;
  float highLevel;

  // Decay control (per second)
  float falloffPerSecond = 1.8;
  
  // Smoothing
  float smoothing = 0.9;  // Higher = more smoothing
  
  // Manual mode (Launchpad control)
  boolean manualMode = true;
  
  AudioEnvelope() {
    bassLevel = 0;
    midLevel = 0;
    highLevel = 0;
  }
  
  /**
   * Update levels (call once per frame)
   * In manual mode, levels decay slowly
   */
  void update(float dt) {
    if (manualMode) {
      // Frame-rate independent exponential decay
      float decay = exp(-falloffPerSecond * dt);
      bassLevel *= decay;
      midLevel *= decay;
      highLevel *= decay;
    }
  }
  
  /**
   * Set level directly (manual mode, e.g., from pad press)
   */
  void setBass(float level) {
    bassLevel = constrain(level, 0, 1);
  }
  
  void setMid(float level) {
    midLevel = constrain(level, 0, 1);
  }
  
  void setHigh(float level) {
    highLevel = constrain(level, 0, 1);
  }
  
  /**
   * Trigger a hit (instant peak, then decay) for simulation
   */
  void hitBass(float intensity) {
    bassLevel = max(bassLevel, constrain(intensity, 0, 1));
  }
  
  void hitMid(float intensity) {
    midLevel = max(midLevel, constrain(intensity, 0, 1));
  }
  
  void hitHigh(float intensity) {
    highLevel = max(highLevel, constrain(intensity, 0, 1));
  }
  
  /**
   * Set levels from real audio input (non-manual mode)
   */
  void setFromAudio(float bass, float mid, float high) {
    if (!manualMode) {
      bassLevel = lerp(bassLevel, constrain(bass, 0, 1), 1 - smoothing);
      midLevel = lerp(midLevel, constrain(mid, 0, 1), 1 - smoothing);
      highLevel = lerp(highLevel, constrain(high, 0, 1), 1 - smoothing);
    }
  }
  
  /**
   * Get overall level
   */
  float getLevel() {
    return (bassLevel + midLevel + highLevel) / 3.0;
  }

  float getBass() {
    return bassLevel;
  }

  float getMid() {
    return midLevel;
  }

  float getHigh() {
    return highLevel;
  }
}
