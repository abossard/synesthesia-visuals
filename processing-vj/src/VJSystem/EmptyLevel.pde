/**
 * EmptyLevel — Minimal Level implementation for testing
 * 
 * Shows a simple visual (pulsing circle) and responds to pad presses.
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
  }
  
  void update(float dt, Inputs inputs) {
    fsm.update();
    
    // Pulse animation
    pulse += dt * 2;
    if (pulse > TWO_PI) pulse -= TWO_PI;
  }
  
  void draw(PGraphics g) {
    g.beginDraw();
    g.background(0);
    
    // Pulsing circle in center
    float size = 200 + sin(pulse) * 50;
    g.noStroke();
    
    // Color based on FSM state
    switch (fsm.getState()) {
      case IDLE:
        g.fill(100);
        break;
      case PLAYING:
        g.fill(0, 200, 100);
        break;
      case WIN:
        g.fill(0, 255, 255);
        break;
      case LOSE:
        g.fill(255, 50, 50);
        break;
      case PAUSED:
        g.fill(255, 200, 0);
        break;
      default:
        g.fill(128, 0, 128);
    }
    
    g.ellipse(g.width / 2, g.height / 2, size, size);
    
    // Show last pad press
    if (lastPadCol >= 0 && lastPadRow >= 0) {
      float padX = map(lastPadCol, 0, 7, 100, g.width - 100);
      float padY = map(lastPadRow, 0, 7, g.height - 100, 100);
      g.fill(255, 255, 0, 150);
      g.ellipse(padX, padY, 80, 80);
    }
    
    // State text (debug)
    g.fill(255);
    g.textAlign(LEFT, TOP);
    g.textSize(24);
    g.text(name + " | " + fsm.getState(), 20, 20);
    
    g.endDraw();
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
