/**
 * EmptyLevel — Audio-reactive example level
 *
 * Demonstrates audio reactivity patterns:
 * - Bass controls size and pulse speed
 * - Mid controls color hue shift
 * - High controls brightness and glow
 *
 * Use as a template for new levels.
 */

class EmptyLevel implements Level {

  private SharedContext ctx;
  private LevelFSM fsm;
  private String name = "Empty";

  // Visual state
  private float pulse = 0;
  private int lastPadCol = -1;
  private int lastPadRow = -1;

  // Audio-reactive state
  private float bassBoost = 0;
  private float hueShift = 0;
  private float currentBass = 0;
  private float currentMid = 0;
  private float currentHigh = 0;

  EmptyLevel() {
    fsm = new LevelFSM();
    fsm.loadDefaults();

    // Simple rules: any pad hit starts, goal after 5 hits
    fsm.addRule(State.PLAYING, FSMEvent.GOAL_REACHED, State.WIN);
  }

  // ============================================
  // LEVEL INTERFACE
  // ============================================

  void init(SharedContext ctx) {
    this.ctx = ctx;
    fsm.reset();
    pulse = 0;
    lastPadCol = -1;
    lastPadRow = -1;
    bassBoost = 0;
    hueShift = 0;
  }

  void update(float dt, Inputs inputs) {
    fsm.update();

    // Store current audio levels for draw()
    currentBass = inputs.bassLevel;
    currentMid = inputs.midLevel;
    currentHigh = inputs.highLevel;

    // Pulse animation - speed increases with bass
    float pulseSpeed = 2.0 + currentBass * 4.0;  // 2-6 Hz based on bass
    pulse += dt * pulseSpeed;
    if (pulse > TWO_PI) pulse -= TWO_PI;

    // Bass boost (smooth decay for visual impact)
    bassBoost = lerp(bassBoost, currentBass, 0.3);

    // Hue shift accumulates with mid frequencies
    hueShift += currentMid * dt * 60;  // Cycles over time
    if (hueShift > 360) hueShift -= 360;
  }
  
  void draw(PGraphics g) {
    g.beginDraw();
    g.background(0);
    g.colorMode(HSB, 360, 100, 100, 100);

    // Screen layout helper
    ScreenLayout layout = new ScreenLayout(g);

    // === AUDIO-REACTIVE VISUALS ===

    // Base size with bass boost
    float baseSize = layout.scaleMin(0.25);  // 25% of smallest dimension
    float bassSize = baseSize * (1.0 + bassBoost * 0.5);  // Up to 50% larger with bass
    float size = bassSize + sin(pulse) * (baseSize * 0.2);

    // Brightness controlled by highs
    float brightness = 70 + currentHigh * 30;  // 70-100% brightness

    // Hue based on FSM state + mid frequency shift
    float baseHue = getStateHue();
    float hue = (baseHue + hueShift) % 360;
    float saturation = 80;

    // Draw outer glow rings (high frequencies)
    if (currentHigh > 0.1) {
      int numRings = 3;
      for (int i = 0; i < numRings; i++) {
        float ringSize = size * (1.2 + i * 0.3);
        float ringAlpha = currentHigh * 30 * (1.0 - i / (float)numRings);
        g.noFill();
        g.stroke(hue, saturation * 0.7, brightness, ringAlpha);
        g.strokeWeight(layout.scaleMin(0.01));
        g.ellipse(layout.centerX(), layout.centerY(), ringSize, ringSize);
      }
    }

    // Main circle
    g.noStroke();
    g.fill(hue, saturation, brightness);
    g.ellipse(layout.centerX(), layout.centerY(), size, size);

    // Inner glow (bass response)
    if (bassBoost > 0.2) {
      float glowSize = size * 0.6;
      g.fill(hue, saturation * 0.5, 100, bassBoost * 50);
      g.ellipse(layout.centerX(), layout.centerY(), glowSize, glowSize);
    }

    // Show last pad press (using grid positioning)
    if (lastPadCol >= 0 && lastPadRow >= 0) {
      PVector padPos = layout.gridPos(lastPadCol, lastPadRow);
      float padSize = layout.scaleMin(0.08);  // 8% of smallest dimension
      g.fill(60, 100, 100, 60);  // Yellow with transparency
      g.ellipse(padPos.x, padPos.y, padSize, padSize);
    }

    // State text (debug) - positioned at margin
    g.colorMode(RGB, 255);
    g.fill(255);
    g.textAlign(LEFT, TOP);
    g.textSize(layout.scaleH(0.033));  // ~3.3% of height
    String audioInfo = String.format("B:%.2f M:%.2f H:%.2f", currentBass, currentMid, currentHigh);
    g.text(name + " | " + fsm.getState() + " | " + audioInfo, layout.marginLeft() * 0.5, layout.marginTop() * 0.5);

    g.endDraw();
  }

  /**
   * Get base hue for current FSM state
   */
  float getStateHue() {
    switch (fsm.getState()) {
      case IDLE:    return 0;    // Red
      case PLAYING: return 120;  // Green
      case WIN:     return 180;  // Cyan
      case LOSE:    return 0;    // Red
      case PAUSED:  return 40;   // Orange
      case EXIT:    return 280;  // Purple
      default:      return 280;  // Purple
    }
  }
  
  void handlePad(int col, int row, int velocity) {
    if (velocity > 0) {
      // Pad pressed
      lastPadCol = col;
      lastPadRow = row;
      
      // Start game on first press
      if (fsm.isState(State.IDLE)) {
        fsm.trigger(FSMEvent.START);
      } else if (fsm.isPlaying()) {
        fsm.trigger(FSMEvent.PAD_HIT);
      }
    } else {
      // Pad released
      if (col == lastPadCol && row == lastPadRow) {
        lastPadCol = -1;
        lastPadRow = -1;
      }
    }
  }
  
  LevelFSM getFSM() {
    return fsm;
  }
  
  String getName() {
    return name;
  }
  
  void dispose() {
    // Nothing to clean up
  }
}
