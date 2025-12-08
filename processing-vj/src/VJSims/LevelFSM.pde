/**
 * LevelFSM — Table-driven Finite State Machine for level game states
 * 
 * Each level owns an FSM that tracks its current state (Idle, Playing, Win, Lose, etc.)
 * and handles transitions based on game events (pad press, timer, goal reached, etc.)
 * 
 * Levels configure their own transition rules to match their win/lose/advance conditions.
 */

// ============================================
// STATE ENUM
// ============================================

enum State {
  IDLE,       // Waiting for game to start
  PLAYING,    // Active gameplay
  WIN,        // Player achieved goal
  LOSE,       // Player failed
  PAUSED,     // Temporarily paused
  EXIT;       // Ready for level transition
  
  boolean isGameOver() {
    return this == WIN || this == LOSE;
  }
  
  boolean isActive() {
    return this == PLAYING;
  }
}

// ============================================
// EVENT ENUM
// ============================================

enum FSMEvent {
  START,          // Begin gameplay
  PAD_HIT,        // Correct pad pressed
  PAD_MISS,       // Wrong pad pressed or missed target
  GOAL_REACHED,   // Win condition met (score, collect all, etc.)
  TIME_UP,        // Timer expired
  LIVES_EMPTY,    // No lives remaining
  PAUSE,          // Pause requested
  RESUME,         // Resume from pause
  RESTART,        // Restart level
  ADVANCE,        // Move to next level
  FORCE_EXIT;     // Immediate exit (level swap)
}

// ============================================
// TRANSITION RULE
// ============================================

class TransitionRule {
  State fromState;
  FSMEvent onEvent;
  State toState;
  
  TransitionRule(State fromState, FSMEvent onEvent, State toState) {
    this.fromState = fromState;
    this.onEvent = onEvent;
    this.toState = toState;
  }
}

// ============================================
// LEVEL FSM CLASS
// ============================================

class LevelFSM {
  
  private State current;
  private State initial;
  private ArrayList<TransitionRule> rules;
  
  // Timing
  private int stateStartFrame;
  private int stateDurationFrames;
  
  // Callbacks (optional)
  private FSMListener listener;
  
  /**
   * Create FSM with IDLE as initial state
   */
  LevelFSM() {
    this(State.IDLE);
  }
  
  /**
   * Create FSM with specific initial state
   */
  LevelFSM(State initialState) {
    this.initial = initialState;
    this.current = initialState;
    this.rules = new ArrayList<TransitionRule>();
    this.stateStartFrame = 0;
    this.stateDurationFrames = 0;
  }
  
  /**
   * Set listener for state change callbacks
   */
  void setListener(FSMListener l) {
    this.listener = l;
  }
  
  // ============================================
  // STATE ACCESS
  // ============================================
  
  State getState() {
    return current;
  }
  
  boolean isState(State s) {
    return current == s;
  }
  
  boolean isPlaying() {
    return current == State.PLAYING;
  }
  
  boolean isGameOver() {
    return current.isGameOver();
  }
  
  boolean isWin() {
    return current == State.WIN;
  }
  
  boolean isLose() {
    return current == State.LOSE;
  }
  
  boolean isExit() {
    return current == State.EXIT;
  }
  
  /**
   * Frames spent in current state
   */
  int getStateFrames() {
    return stateDurationFrames;
  }
  
  /**
   * Seconds spent in current state (at 60fps)
   */
  float getStateSeconds() {
    return stateDurationFrames / 60.0;
  }
  
  // ============================================
  // TRANSITIONS
  // ============================================
  
  /**
   * Process an event and transition if a rule matches
   * Returns true if transition occurred
   */
  boolean trigger(FSMEvent e) {
    for (TransitionRule rule : rules) {
      if (rule.fromState == current && rule.onEvent == e) {
        State oldState = current;
        current = rule.toState;
        stateStartFrame = frameCount;
        stateDurationFrames = 0;
        
        if (listener != null) {
          listener.onStateChange(oldState, current, e);
        }
        
        return true;
      }
    }
    return false;
  }
  
  /**
   * Force transition to a specific state (bypasses rules)
   */
  void forceState(State s) {
    State oldState = current;
    current = s;
    stateStartFrame = frameCount;
    stateDurationFrames = 0;
    
    if (listener != null) {
      listener.onStateChange(oldState, current, null);
    }
  }
  
  /**
   * Reset to initial state
   */
  void reset() {
    forceState(initial);
  }
  
  /**
   * Update timing (call once per frame)
   */
  void update() {
    stateDurationFrames = frameCount - stateStartFrame;
  }
  
  // ============================================
  // RULE MANAGEMENT
  // ============================================
  
  /**
   * Add a transition rule
   */
  void addRule(State fromState, FSMEvent onEvent, State toState) {
    rules.add(new TransitionRule(fromState, onEvent, toState));
  }
  
  /**
   * Clear all rules (call before configuring level-specific rules)
   */
  void clearRules() {
    rules.clear();
  }
  
  /**
   * Load minimal default rules (start/restart/exit)
   * Levels should add their own win/lose conditions
   */
  void loadDefaults() {
    // Basic flow
    addRule(State.IDLE, FSMEvent.START, State.PLAYING);
    addRule(State.IDLE, FSMEvent.FORCE_EXIT, State.EXIT);
    
    // Pause/resume
    addRule(State.PLAYING, FSMEvent.PAUSE, State.PAUSED);
    addRule(State.PAUSED, FSMEvent.RESUME, State.PLAYING);
    
    // Restart from any game-over state
    addRule(State.WIN, FSMEvent.RESTART, State.IDLE);
    addRule(State.LOSE, FSMEvent.RESTART, State.IDLE);
    
    // Advance after win
    addRule(State.WIN, FSMEvent.ADVANCE, State.EXIT);
    
    // Force exit from anywhere
    addRule(State.PLAYING, FSMEvent.FORCE_EXIT, State.EXIT);
    addRule(State.WIN, FSMEvent.FORCE_EXIT, State.EXIT);
    addRule(State.LOSE, FSMEvent.FORCE_EXIT, State.EXIT);
    addRule(State.PAUSED, FSMEvent.FORCE_EXIT, State.EXIT);
  }
  
  // ============================================
  // UTILITY
  // ============================================
  
  /**
   * Get LED color for current state (for HUD feedback)
   */
  int getStateColor() {
    switch (current) {
      case IDLE:    return LP_WHITE_DIM;
      case PLAYING: return LP_GREEN;
      case WIN:     return LP_CYAN;
      case LOSE:    return LP_RED;
      case PAUSED:  return LP_AMBER;
      case EXIT:    return LP_PURPLE;
      default:      return LP_OFF;
    }
  }
  
  String toString() {
    return "FSM[" + current + " @ " + getStateSeconds() + "s]";
  }
}

// ============================================
// LISTENER INTERFACE
// ============================================

interface FSMListener {
  void onStateChange(State fromState, State toState, FSMEvent trigger);
}
