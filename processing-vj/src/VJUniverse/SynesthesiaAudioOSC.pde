/**
 * SynesthesiaAudioOSC.pde - OSC-driven audio analysis for VJUniverse
 *
 * Listens to Synesthesia's OSC audio feed (default port 7777) and converts
 * the stream into smoothed parameters for shader uniforms and bindings.
 *
 * Expected OSC address patterns (subset):
 *   /audio/level/{bass,mid,midhigh,high,all,raw}
 *   /audio/presence/{bass,mid,midhigh,high,all}
 *   /audio/hits/{bass,mid,midhigh,high,all}
 *   /audio/time/{bass,mid,midhigh,high,all,curved}
 *   /audio/energy/intensity
 *   /audio/beat/{onbeat,randomonbeat,beattime}
 *   /audio/bpm/{bpm,bpmconfidence,bpmtwitcher,bpmsin,bpmsin2, ...}
 *
 * The module exposes smoothed band levels, beat pulses, energy envelopes,
 * and audio binding utilities for GLSL uniforms.
 */

// ============================================
// OSC CONFIGURATION
// ============================================

// Note: All OSC uses the single OSC_PORT (10000) defined in VJUniverse.pde
final int SYN_AUDIO_TIMEOUT_MS = 1500;

HashMap<String, Float> synAudioValues = new HashMap<String, Float>();
HashMap<String, float[]> isfUniformDefaults = new HashMap<String, float[]>();
long synAudioLastMessageMs = 0;
String synAudioSourceLabel = "OSC";

// ============================================
// AUDIO STATE (SMOOTHED)
// ============================================

float smoothAudioBass = 0;
float smoothAudioLowMid = 0;
float smoothAudioMid = 0;
float smoothAudioHighs = 0;
float smoothAudioLevel = 0;

float kickEnv = 0;
int kickPulse = 0;
float beatPhaseAudio = 0;
int beat4 = 0;

float energyFast = 0;
float energySlow = 0;
float songStyle = 0.5;

float presenceBass = 0;
float presenceMid = 0;
float presenceHigh = 0;
float presenceAll = 0;

float beatOnSmooth = 0;
float beatRandom = 0;
float beatBarPhase = 0;
float beatHold = 0;

float bpmTwitcher = 0;
float bpmSin4 = 0;
float bpmConfidence = 0;

// Ramp state for Magic-style speed buildup
float rampedSpeed = 0.02f;       // Current ramped speed (starts at floor)
float beatBoostAccum = 0.0f;     // Beat boost accumulator (decays)

boolean showAudioBars = false;
boolean audioControlsDirty = true;
float lastSpeedMixDisplayed = -1;
float lastSpeedGainDisplayed = -1;
float lastKickBoostDisplayed = -1;

// Internal helpers
long lastKickPulseMs = 0;
float lastOnBeatValue = 0;

// ============================================
// CONSTANTS
// ============================================

final float AUDIO_SMOOTHING = 0.80;     // Higher = smoother response
final float ENERGY_FAST_SMOOTHING = 0.60;
final float ENERGY_SLOW_SMOOTHING = 0.92;
final float KICK_ENV_SMOOTHING = 0.55;
final float KICK_PULSE_THRESHOLD = 0.65;
final int KICK_COOLDOWN_MS = 140;
final float BEAT_PHASE_DECAY = 0.87;
final float BEAT_ON_THRESHOLD = 0.75;
final float TIMEOUT_DECAY = 0.90;
final float PRESENCE_SMOOTHING = 0.92;
final float BPM_LFO_SMOOTHING = 0.85;
final float BEAT_RANDOM_SMOOTHING = 0.70;
final float BEAT_ON_SMOOTHING = 0.60;
final float BEAT_HOLD_DECAY = 0.88f;

// Speed ramp constants (Magic-style smooth → scale → ramp)
final float BASE_SPEED_FLOOR = 0.02f;       // Near-standstill in silence
final float AUDIO_SPEED_MAX = 1.20f;        // 120% of real-time at sustained loud
final float SPEED_RAMP_UP = 0.008f;         // Slow ramp-up rate per frame
final float SPEED_RAMP_DOWN = 0.025f;       // Faster decay when quiet
final float BASS_BOOST_WEIGHT = 0.35f;      // Bass contribution to speed
final float BEAT_BOOST_AMOUNT = 0.15f;      // Additive boost on beat hits
final float BEAT_BOOST_DECAY = 0.92f;       // Beat boost decay per frame

// Legacy constants (kept for compatibility)
final float BASE_SPEED_FLOOR_MIN = 0.02f;   // Alias
final float BASE_SPEED_FLOOR_MAX = 0.10f;   // Unused
final float AUDIO_SPEED_GAIN = 0.75f;
final float AUDIO_SPEED_CURVE = 1.0f;
final float AUDIO_KICK_BOOST = 1.00f;
final float AUDIO_SPEED_IDLE = 0.02f;       // Match floor for consistency
final float AUDIO_DYNAMIC_MIX = 0.70f;

// Live tweak controls
float uiSpeedMix = AUDIO_DYNAMIC_MIX;
float uiSpeedGain = AUDIO_SPEED_GAIN;
float uiKickBoost = AUDIO_KICK_BOOST;
boolean showAudioControls = false;

// ============================================
// AUDIO BINDINGS (same interface as legacy AudioManager)
// ============================================

ArrayList<AudioBinding> audioBindings = new ArrayList<AudioBinding>();
HashMap<String, Float> boundUniformValues = new HashMap<String, Float>();

class AudioBinding {
  String uniformName;
  String audioSource;
  String modulationType;
  float multiplier;
  float smoothing;
  float baseValue;
  float minValue;
  float maxValue;
  float smoothedValue = 0;
  
  AudioBinding(String uniform, String source, String modType,
               float mult, float smooth, float base, float minV, float maxV) {
    uniformName = uniform;
    audioSource = source;
    modulationType = modType;
    multiplier = mult;
    smoothing = smooth;
    baseValue = base;
    minValue = minV;
    maxValue = maxV;
  }
  
  float getAudioValue() {
    switch (audioSource) {
      case "bass": return smoothAudioBass;
      case "lowMid": return smoothAudioLowMid;
      case "mid": return smoothAudioMid;
      case "highs":
      case "treble": return smoothAudioHighs;
      case "level": return smoothAudioLevel;
      case "kickEnv": return kickEnv;
      case "kickPulse": return (float)kickPulse;
      case "beat4": return beat4 / 3.0f;
      case "beatPhase": return beatPhaseAudio;
      case "energyFast": return energyFast;
      case "energySlow": return energySlow;
      default:
        return smoothAudioLevel;
    }
  }
  
  float compute() {
    float target = getAudioValue();
    smoothedValue = lerp(smoothedValue, target, 1 - smoothing);
    float result;
    switch (modulationType) {
      case "add":
        result = baseValue + smoothedValue * multiplier;
        break;
      case "multiply":
        result = baseValue * (1 + smoothedValue * multiplier);
        break;
      case "replace":
        result = smoothedValue * multiplier;
        break;
      case "threshold":
        result = smoothedValue > multiplier ? 1.0f : 0.0f;
        break;
      default:
        result = baseValue + smoothedValue * multiplier;
        break;
    }
    return constrain(result, minValue, maxValue);
  }
}

// ============================================
// INITIALISATION
// ============================================

void initSynesthesiaAudio() {
  // Note: Uses the main oscP5 instance from VJUniverse.pde (port 10000)
  // No separate OscP5 needed - all messages routed via oscEvent()
  synAudioValues.clear();
  synAudioLastMessageMs = 0;
  synAudioSourceLabel = "OSC Port " + OSC_PORT;
  println("[AudioOSC] Audio messages handled on main OSC port " + OSC_PORT);
}

// ============================================
// OSC MESSAGE HANDLING
// ============================================

boolean handleSynesthesiaAudioMessage(OscMessage msg) {
  String addr = msg.addrPattern();
  if (addr == null || !addr.startsWith("/audio/")) {
    return false;
  }
  
  // Allow control/config messages to reuse legacy protocol
  if (addr.startsWith("/audio/binding/") ||
      addr.equals("/audio/song_style") ||
      addr.equals("/audio/kick_threshold") ||
      addr.equals("/audio/show_bars")) {
    handleAudioControlMessage(msg);
    return true;
  }
  
  float value = getFirstArgAsFloat(msg);
  if (Float.isNaN(value)) {
    return true;
  }
  synAudioValues.put(addr, value);
  synAudioLastMessageMs = millis();
  if (msg.netAddress() != null) {
    synAudioSourceLabel = msg.netAddress().address() + ":" + OSC_PORT;
  }
  return true;
}

void handleAudioControlMessage(OscMessage msg) {
  String addr = msg.addrPattern();
  if (addr.equals("/audio/song_style")) {
    songStyle = constrain(getFirstArgAsFloat(msg), 0, 1);
  }
  else if (addr.equals("/audio/speed_mix")) {
    uiSpeedMix = constrain(getFirstArgAsFloat(msg), 0.0f, 1.0f);
  }
  else if (addr.equals("/audio/speed_gain")) {
    uiSpeedGain = constrain(getFirstArgAsFloat(msg), 0.1f, 2.0f);
  }
  else if (addr.equals("/audio/speed_kick")) {
    uiKickBoost = constrain(getFirstArgAsFloat(msg), 0.0f, 0.6f);
  }
  else if (addr.equals("/audio/kick_threshold")) {
    // Threshold kept for compatibility but mapped to envelope multiplier instead
    float override = constrain(getFirstArgAsFloat(msg), 0.05f, 1.0f);
    synAudioValues.put("__kick_threshold", override);
  }
  else if (addr.equals("/audio/show_bars")) {
    showAudioBars = msg.get(0).intValue() == 1;
  }
  else if (addr.equals("/audio/binding/clear")) {
    clearAudioBindings();
  }
  else if (addr.equals("/audio/binding/add")) {
    try {
      String uniform = msg.get(0).stringValue();
      String source = msg.get(1).stringValue();
      String modType = msg.get(2).stringValue();
      float mult = msg.get(3).floatValue();
      float smooth = msg.get(4).floatValue();
      float base = msg.get(5).floatValue();
      float minV = msg.get(6).floatValue();
      float maxV = msg.get(7).floatValue();
      addAudioBinding(uniform, source, modType, mult, smooth, base, minV, maxV);
    } catch (Exception e) {
      println("[AudioOSC] Binding parse error: " + e.getMessage());
    }
  }
}

float getFirstArgAsFloat(OscMessage msg) {
  if (msg.addrPattern() == null || msg.arguments().length == 0) {
    return Float.NaN;
  }
  char type = msg.typetag().charAt(0);
  switch (type) {
    case 'f':
      return msg.get(0).floatValue();
    case 'i':
      return (float)msg.get(0).intValue();
    case 'd':
      return (float)msg.get(0).doubleValue();
    default:
      return Float.NaN;
  }
}

float getAudioValue(String key, float fallback) {
  Float v = synAudioValues.get(key);
  return v != null ? v : fallback;
}

boolean isSynAudioActive() {
  if (synAudioLastMessageMs == 0) return false;
  return millis() - synAudioLastMessageMs < SYN_AUDIO_TIMEOUT_MS;
}

float synAudioAgeSeconds() {
  if (synAudioLastMessageMs == 0) return Float.POSITIVE_INFINITY;
  return (millis() - synAudioLastMessageMs) / 1000.0f;
}

// ============================================
// UPDATE LOOP (call every frame)
// ============================================

void updateSynesthesiaAudio() {
  boolean active = isSynAudioActive();
  
  float targetBass = getAudioValue("/audio/level/bass", smoothAudioBass);
  float targetMid = getAudioValue("/audio/level/mid", smoothAudioLowMid);
  float targetMidHigh = getAudioValue("/audio/level/midhigh", smoothAudioMid);
  float targetHigh = getAudioValue("/audio/level/high", smoothAudioHighs);
  float targetLevel = getAudioValue("/audio/level/all", smoothAudioLevel);
  
  smoothAudioBass = lerp(smoothAudioBass, targetBass, 1 - AUDIO_SMOOTHING);
  smoothAudioLowMid = lerp(smoothAudioLowMid, targetMid, 1 - AUDIO_SMOOTHING);
  smoothAudioMid = lerp(smoothAudioMid, targetMidHigh, 1 - AUDIO_SMOOTHING);
  smoothAudioHighs = lerp(smoothAudioHighs, targetHigh, 1 - AUDIO_SMOOTHING);
  smoothAudioLevel = lerp(smoothAudioLevel, targetLevel, 1 - AUDIO_SMOOTHING);
  
  float intensity = getAudioValue("/audio/energy/intensity", energyFast);
  energyFast = lerp(energyFast, intensity, 1 - ENERGY_FAST_SMOOTHING);
  energySlow = lerp(energySlow, energyFast, 1 - ENERGY_SLOW_SMOOTHING);
  
  float hitsBass = getAudioValue("/audio/hits/bass", 0);
  float envelopeOverride = getAudioValue("__kick_threshold", KICK_PULSE_THRESHOLD);
  float threshold = constrain(envelopeOverride, 0.05f, 1.0f);
  kickEnv = lerp(kickEnv, hitsBass, 1 - KICK_ENV_SMOOTHING);
  kickPulse = 0;
  int nowMs = millis();
  if (hitsBass > threshold && nowMs - lastKickPulseMs > KICK_COOLDOWN_MS) {
    kickPulse = 1;
    lastKickPulseMs = nowMs;
  }
  
  float onBeat = getAudioValue("/audio/beat/onbeat", 0);
  if (onBeat >= BEAT_ON_THRESHOLD && lastOnBeatValue < BEAT_ON_THRESHOLD) {
    beatPhaseAudio = 1.0f;
  } else {
    beatPhaseAudio *= BEAT_PHASE_DECAY;
  }
  beatOnSmooth = lerp(beatOnSmooth, onBeat, 1 - BEAT_ON_SMOOTHING);
  lastOnBeatValue = onBeat;

  float beatTimeRaw = getAudioValue("/audio/beat/beattime", beatBarPhase * 4.0f);
  float wrappedBeatTime = beatTimeRaw % 4.0f;
  if (wrappedBeatTime < 0) wrappedBeatTime += 4.0f;
  beatBarPhase = wrappedBeatTime / 4.0f;

  int beatCycle = ((int)round(beatTimeRaw)) % 8;
  if (beatCycle < 0) beatCycle += 8;
  beat4 = beatCycle % 4;

  float randomBeat = getAudioValue("/audio/beat/randomonbeat", beatRandom);
  beatRandom = lerp(beatRandom, randomBeat, 1 - BEAT_RANDOM_SMOOTHING);

  float presenceBassTarget = getAudioValue("/audio/presence/bass", presenceBass);
  float presenceMidTarget = getAudioValue("/audio/presence/mid", presenceMid);
  float presenceHighTarget = getAudioValue("/audio/presence/high", presenceHigh);
  float presenceAllTarget = getAudioValue("/audio/presence/all", presenceAll);
  presenceBass = lerp(presenceBass, presenceBassTarget, 1 - PRESENCE_SMOOTHING);
  presenceMid = lerp(presenceMid, presenceMidTarget, 1 - PRESENCE_SMOOTHING);
  presenceHigh = lerp(presenceHigh, presenceHighTarget, 1 - PRESENCE_SMOOTHING);
  presenceAll = lerp(presenceAll, presenceAllTarget, 1 - PRESENCE_SMOOTHING);

  float presenceSum = presenceBass + presenceHigh;
  if (presenceSum > 0.0001f) {
    songStyle = constrain(presenceHigh / presenceSum, 0, 1);
  }

  float bpmTwitcherTarget = getAudioValue("/audio/bpm/bpmtwitcher", bpmTwitcher);
  float bpmSin4Target = getAudioValue("/audio/bpm/bpmsin4", bpmSin4);
  float bpmConfidenceTarget = getAudioValue("/audio/bpm/bpmconfidence", bpmConfidence);
  bpmTwitcher = lerp(bpmTwitcher, bpmTwitcherTarget, 1 - BPM_LFO_SMOOTHING);
  bpmSin4 = lerp(bpmSin4, bpmSin4Target, 1 - BPM_LFO_SMOOTHING);
  bpmConfidence = lerp(bpmConfidence, bpmConfidenceTarget, 1 - BPM_LFO_SMOOTHING);
  
  if (!active) {
    smoothAudioBass *= TIMEOUT_DECAY;
    smoothAudioLowMid *= TIMEOUT_DECAY;
    smoothAudioMid *= TIMEOUT_DECAY;
    smoothAudioHighs *= TIMEOUT_DECAY;
    smoothAudioLevel *= TIMEOUT_DECAY;
    energyFast *= TIMEOUT_DECAY;
    energySlow *= TIMEOUT_DECAY;
    kickEnv *= TIMEOUT_DECAY;
    beatPhaseAudio *= TIMEOUT_DECAY;
    presenceBass *= TIMEOUT_DECAY;
    presenceMid *= TIMEOUT_DECAY;
    presenceHigh *= TIMEOUT_DECAY;
    presenceAll *= TIMEOUT_DECAY;
    beatOnSmooth *= TIMEOUT_DECAY;
    beatRandom *= TIMEOUT_DECAY;
    beatBarPhase *= TIMEOUT_DECAY;
    bpmTwitcher *= TIMEOUT_DECAY;
    bpmSin4 *= TIMEOUT_DECAY;
    bpmConfidence *= TIMEOUT_DECAY;
  }
  
  updateBoundUniforms();
}

// ============================================
// AUDIO BINDING MANAGEMENT
// ============================================

void clearAudioBindings() {
  audioBindings.clear();
  boundUniformValues.clear();
  println("[AudioOSC] Bindings cleared");
}

void addAudioBinding(String uniform, String source, String modType,
                     float mult, float smooth, float base, float minV, float maxV) {
  AudioBinding binding = new AudioBinding(uniform, source, modType, mult, smooth, base, minV, maxV);
  audioBindings.add(binding);
  println("[AudioOSC] Binding: " + uniform + " <- " + source + " (" + modType + ")");
}

void updateBoundUniforms() {
  boundUniformValues.clear();
  for (AudioBinding binding : audioBindings) {
    float val = binding.compute();
    boundUniformValues.put(binding.uniformName, val);
  }
}

float getBoundUniformValue(String uniformName, float defaultValue) {
  Float val = boundUniformValues.get(uniformName);
  return val != null ? val : defaultValue;
}

/**
 * Compute audio-reactive speed using Magic-style pipeline:
 *   1. SMOOTH: Use already-smoothed audio levels (smoothAudioLevel, smoothAudioBass)
 *   2. SCALE:  Map volume (0-1) to target speed (FLOOR - MAX)
 *   3. RAMP:   Gradually climb toward target; decay faster when quiet
 *   4. BOOST:  Add beat/kick transients on top
 *
 * Result: silence → near-standstill; sustained loud → gradual climb to 1.2×
 */
float computeAudioReactiveSpeed() {
  // No audio → decay to floor
  if (!isSynAudioActive()) {
    rampedSpeed = lerp(rampedSpeed, BASE_SPEED_FLOOR, SPEED_RAMP_DOWN);
    beatBoostAccum *= BEAT_BOOST_DECAY;
    return constrain(rampedSpeed + beatBoostAccum, BASE_SPEED_FLOOR, AUDIO_SPEED_MAX);
  }

  // ========================================
  // 1. SMOOTH (already done in updateSynesthesiaAudio)
  // ========================================
  // smoothAudioLevel, smoothAudioBass, etc. are EMA-smoothed

  // ========================================
  // 2. SCALE: Map volume → target speed
  // ========================================
  // Blend overall level with bass emphasis for "thump" response
  float volumeDriver = smoothAudioLevel * (1.0f - BASS_BOOST_WEIGHT)
                     + smoothAudioBass * BASS_BOOST_WEIGHT;
  volumeDriver = constrain(volumeDriver, 0, 1);

  // Scale to speed range: floor at silence, max at loud
  float targetSpeed = BASE_SPEED_FLOOR + volumeDriver * (AUDIO_SPEED_MAX - BASE_SPEED_FLOOR);

  // ========================================
  // 3. RAMP: Gradual buildup / faster decay
  // ========================================
  if (targetSpeed > rampedSpeed) {
    // Ramp UP slowly (sustained loud builds momentum)
    rampedSpeed = lerp(rampedSpeed, targetSpeed, SPEED_RAMP_UP);
  } else {
    // Ramp DOWN faster (quiet sections decay quicker)
    rampedSpeed = lerp(rampedSpeed, targetSpeed, SPEED_RAMP_DOWN);
  }

  // ========================================
  // 4. BEAT BOOST: Transient punch on kicks/beats
  // ========================================
  // Accumulate beat energy (kick hits add boost, decays over time)
  float beatTrigger = max(kickEnv, beatPhaseAudio) * BEAT_BOOST_AMOUNT;
  beatBoostAccum = max(beatBoostAccum * BEAT_BOOST_DECAY, beatTrigger);

  // Scale beat boost by user control
  float scaledBeatBoost = beatBoostAccum * uiKickBoost;

  // ========================================
  // Final speed = ramped base + beat transient
  // ========================================
  float finalSpeed = rampedSpeed + scaledBeatBoost;
  return constrain(finalSpeed, BASE_SPEED_FLOOR, AUDIO_SPEED_MAX);
}

void setupDefaultAudioBindings() {
  audioBindings.clear();
  boundUniformValues.clear();
  
  for (String name : isfUniformDefaults.keySet()) {
    float[] defaults = isfUniformDefaults.get(name);
    float baseVal = defaults.length > 0 ? defaults[0] : 0.5f;
    String lower = name.toLowerCase();
    
    if (lower.equals("time") || lower.contains("size") || lower.contains("colour") ||
        lower.contains("color") || lower.contains("position")) {
      continue;
    }
    if (lower.contains("speed") || lower.contains("rate") || lower.contains("velocity")) {
      addAudioBinding(name, "energyFast", "multiply", 2.0f, 0.8f, baseVal, 0.1f, baseVal * 3.0f);
      continue;
    }
    if (lower.contains("scale") || lower.contains("zoom") || lower.contains("size")) {
      addAudioBinding(name, "bass", "add", 0.5f, 0.7f, baseVal, baseVal * 0.5f, baseVal * 2.0f);
      continue;
    }
    if (lower.contains("intensity") || lower.contains("brightness") || lower.contains("amount") ||
        lower.contains("strength") || lower.contains("power")) {
      addAudioBinding(name, "level", "multiply", 1.5f, 0.6f, baseVal, 0.0f, 1.0f);
      continue;
    }
    if (lower.contains("distort") || lower.contains("warp") || lower.contains("noise") ||
        lower.contains("glitch") || lower.contains("chaos")) {
      addAudioBinding(name, "kickEnv", "add", 0.8f, 0.5f, baseVal * 0.3f, 0.0f, 1.0f);
      continue;
    }
    if (lower.contains("rotat") || lower.contains("angle") || lower.contains("spin")) {
      addAudioBinding(name, "mid", "add", 0.5f, 0.75f, baseVal, baseVal - 0.5f, baseVal + 0.5f);
      continue;
    }
    if (lower.contains("offset") || lower.contains("shift") || lower.contains("displace")) {
      addAudioBinding(name, "highs", "add", 0.3f, 0.6f, baseVal, baseVal - 0.3f, baseVal + 0.3f);
      continue;
    }
    if (lower.contains("freq") || lower.contains("wave")) {
      addAudioBinding(name, "bass", "multiply", 1.5f, 0.7f, baseVal, baseVal * 0.5f, baseVal * 2.0f);
      continue;
    }
    if (lower.contains("blend") || lower.contains("mix") || lower.contains("fade") ||
        lower.contains("alpha") || lower.contains("opacity")) {
      addAudioBinding(name, "energySlow", "replace", 1.0f, 0.9f, 0.5f, 0.0f, 1.0f);
      continue;
    }
    if (lower.contains("iter") || lower.contains("step") || lower.contains("detail") ||
        lower.contains("octave")) {
      addAudioBinding(name, "level", "multiply", 1.0f, 0.8f, baseVal, baseVal * 0.5f, baseVal * 1.5f);
      continue;
    }
    if (lower.contains("glow") || lower.contains("bloom") || lower.contains("bright") ||
        lower.contains("lumi") || lower.contains("emit")) {
      addAudioBinding(name, "level", "multiply", 2.0f, 0.7f, baseVal, baseVal * 0.3f, baseVal * 3.0f);
      continue;
    }
    if (lower.contains("radius") || lower.contains("width") || lower.contains("thick") ||
        lower.contains("stroke") || lower.contains("line")) {
      addAudioBinding(name, "bass", "add", 0.4f, 0.75f, baseVal, baseVal * 0.5f, baseVal * 2.0f);
      continue;
    }
    if (lower.contains("pulse") || lower.contains("beat") || lower.contains("kick") ||
        lower.contains("hit") || lower.contains("impact")) {
      addAudioBinding(name, "kickEnv", "replace", 1.0f, 0.4f, 0.0f, 0.0f, 1.0f);
      continue;
    }
    if (lower.contains("morph") || lower.contains("transform") || lower.contains("evolve") ||
        lower.contains("mutate")) {
      addAudioBinding(name, "energySlow", "replace", 1.0f, 0.85f, 0.5f, 0.0f, 1.0f);
      continue;
    }
    if (lower.contains("turb") || lower.contains("complex") || lower.contains("density") ||
        lower.contains("rough")) {
      addAudioBinding(name, "mid", "multiply", 1.5f, 0.7f, baseVal, baseVal * 0.5f, baseVal * 2.0f);
      continue;
    }
    if (lower.equals("seed") || lower.equals("rnd") || lower.contains("random") ||
        lower.contains("jitter")) {
      addAudioBinding(name, "highs", "add", 0.5f, 0.5f, baseVal, baseVal * 0.5f, baseVal * 1.5f);
      continue;
    }
    if (lower.contains("contrast") || lower.contains("gamma") || lower.contains("curve")) {
      addAudioBinding(name, "level", "multiply", 1.2f, 0.8f, baseVal, baseVal * 0.8f, baseVal * 1.5f);
      continue;
    }
  }
  if (audioBindings.size() > 0) {
    println("[AudioOSC] Auto-wired " + audioBindings.size() + " default bindings");
  }
}

// ============================================
// HUD RENDERING
// ============================================

void drawAudioBars() {
  if (!showAudioBars && !debugMode) return;
  int startX = width - 360;
  int startY = 20;
  int barWidth = 30;
  int barHeight = 150;
  int barSpacing = 5;
  int barCount = 10;
  int panelWidth = barCount * (barWidth + barSpacing) - barSpacing + 20;
  
  fill(0, 180);
  noStroke();
  rect(startX - 10, startY - 10, panelWidth, barHeight + 60);
  
  drawBarSegment(startX, startY, barWidth, barHeight, "BASS", smoothAudioBass, color(255, 70, 50));
  drawBarSegment(startX + (barWidth + barSpacing), startY, barWidth, barHeight, "LOWM", smoothAudioLowMid, color(255, 150, 60));
  drawBarSegment(startX + 2 * (barWidth + barSpacing), startY, barWidth, barHeight, "MID", smoothAudioMid, color(255, 230, 70));
  drawBarSegment(startX + 3 * (barWidth + barSpacing), startY, barWidth, barHeight, "HIGH", smoothAudioHighs, color(70, 255, 110));
  drawBarSegment(startX + 4 * (barWidth + barSpacing), startY, barWidth, barHeight, "LVL", smoothAudioLevel, color(70, 180, 255));
  drawBarSegment(startX + 5 * (barWidth + barSpacing), startY, barWidth, barHeight, "BEAT", kickEnv, color(255, 60, 220));
  drawBarSegment(startX + 6 * (barWidth + barSpacing), startY, barWidth, barHeight, "E-F", energyFast, color(255, 200, 90));
  drawBarSegment(startX + 7 * (barWidth + barSpacing), startY, barWidth, barHeight, "E-S", energySlow, color(90, 200, 255));
  drawBarSegment(startX + 8 * (barWidth + barSpacing), startY, barWidth, barHeight, "PR", presenceAll, color(120, 255, 190));
  float tempoSinValue = constrain((bpmSin4 * 0.5f) + 0.5f, 0, 1);
  drawBarSegment(startX + 9 * (barWidth + barSpacing), startY, barWidth, barHeight, "TMP", tempoSinValue, color(160, 160, 255));
  
  int beatX = startX;
  int beatY = startY + barHeight + 20;
  fill(kickPulse == 1 ? color(255, 50, 50) : color(60));
  ellipse(beatX + 15, beatY + 10, 20, 20);
  fill(200);
  textSize(10);
  textAlign(LEFT, CENTER);
  text("BEAT:" + beat4, beatX + 35, beatY + 10);
  text("AGE:" + nf(synAudioAgeSeconds(), 0, 1) + "s", beatX + 120, beatY + 10);

}

void drawAudioPanelTo(PGraphics pg) {
  if (pg == null) return;
  
  pg.pushStyle();
  pg.background(10);
  
  float padding = max(12, pg.width * 0.03);
  float headerH = max(26, pg.height * 0.08);
  float footerH = max(34, pg.height * 0.14);
  
  float barAreaY = padding + headerH;
  float barAreaH = pg.height - barAreaY - footerH - padding;
  if (barAreaH < 40) {
    barAreaH = max(40, pg.height * 0.45);
  }
  
  // Header
  pg.fill(255);
  pg.textAlign(LEFT, CENTER);
  pg.textSize(14);
  pg.text("AUDIO", padding, padding + headerH * 0.5);
  
  String status = isSynAudioActive() ? "stream" : "wait";
  String ageLabel = isSynAudioActive() ? ("age " + nf(synAudioAgeSeconds(), 0, 1) + "s") : "age --";
  pg.textAlign(RIGHT, CENTER);
  pg.text(status, pg.width - padding, padding + headerH * 0.5);
  pg.textSize(10);
  pg.fill(180);
  pg.text(ageLabel, pg.width - padding, padding + headerH * 0.5 + 14);
  
  // Bars
  String[] labels = {"BASS", "LOW", "MID", "HIGH", "LVL", "BEAT", "E-F", "E-S", "PR", "TMP"};
  float tempoValue = constrain((bpmSin4 * 0.5f) + 0.5f, 0, 1);
  float[] values = {
    smoothAudioBass,
    smoothAudioLowMid,
    smoothAudioMid,
    smoothAudioHighs,
    smoothAudioLevel,
    kickEnv,
    energyFast,
    energySlow,
    presenceAll,
    tempoValue
  };
  int[] colors = {
    color(255, 70, 50),
    color(255, 150, 60),
    color(255, 230, 70),
    color(70, 255, 110),
    color(70, 180, 255),
    color(255, 60, 220),
    color(255, 200, 90),
    color(90, 200, 255),
    color(120, 255, 190),
    color(160, 160, 255)
  };
  
  float gap = max(6, pg.width * 0.01);
  float totalGap = gap * (labels.length - 1);
  float barW = (pg.width - padding * 2 - totalGap) / labels.length;
  float barX = padding;
  float barY = barAreaY;
  
  for (int i = 0; i < labels.length; i++) {
    drawAudioBarSegment(pg, barX, barY, barW, barAreaH, labels[i], values[i], colors[i]);
    barX += barW + gap;
  }
  
  // Footer
  float footerY = pg.height - footerH;
  float beatX = padding;
  float beatY = footerY + footerH * 0.5;
  pg.noStroke();
  pg.fill(kickPulse == 1 ? color(255, 80, 80) : color(60));
  pg.ellipse(beatX + 10, beatY, 16, 16);
  pg.fill(200);
  pg.textAlign(LEFT, CENTER);
  pg.textSize(11);
  pg.text("Beat " + beat4, beatX + 26, beatY);
  
  pg.textAlign(RIGHT, CENTER);
  pg.text("Energy " + nf(energyFast, 0, 2), pg.width - padding, beatY);
  
  pg.popStyle();
}

void drawAudioBarSegment(PGraphics pg, float x, float y, float w, float h, String label, float value, int c) {
  pg.noStroke();
  pg.fill(30);
  pg.rect(x, y, w, h, 3);
  float barH = constrain(value, 0, 1) * h;
  pg.fill(c);
  pg.rect(x, y + h - barH, w, barH, 3);
  pg.fill(180);
  pg.textAlign(CENTER, TOP);
  pg.textSize(9);
  pg.text(label, x + w / 2, y + h + 6);
}

void drawBarSegment(int x, int y, int w, int h, String label, float value, int c) {
  fill(40);
  rect(x, y, w, h);
  float barH = constrain(value, 0, 1) * h;
  fill(c);
  rect(x, y + h - barH, w, barH);
  fill(210);
  textSize(9);
  textAlign(CENTER, TOP);
  text(label, x + w / 2, y + h + 3);
  textSize(8);
  text(nf(value, 0, 2), x + w / 2, y + h + 15);
}

void drawAudioControlPanel(int x, int y) {
  int panelW = 140;
  int panelH = 110;
  fill(0, 200);
  stroke(80);
  rect(x, y, panelW, panelH, 6);
  fill(220);
  textAlign(LEFT, TOP);
  textSize(11);
  text("Audio Speed Controls", x + 10, y + 8);
  textSize(10);
  drawSlider(x + 10, y + 30, panelW - 20, "Mix", uiSpeedMix, 0, 1);
  drawSlider(x + 10, y + 55, panelW - 20, "Gain", uiSpeedGain, 0.1f, 2.0f);
  drawSlider(x + 10, y + 80, panelW - 20, "Beat", uiKickBoost, 0.0f, 1.2f);
}

void drawSlider(int x, int y, int w, String label, float value, float minV, float maxV) {
  fill(140);
  rect(x, y, w, 10, 4);
  float t = (value - minV) / (maxV - minV);
  t = constrain(t, 0, 1);
  float knobX = x + t * w;
  fill(255);
  ellipse(knobX, y + 5, 10, 10);
  fill(210);
  textAlign(LEFT, CENTER);
  text(label + " " + nf(value, 0, 2), x, y - 8);
}

boolean handleAudioControlMouse(int mouseX, int mouseY) {
  if (!showAudioControls && !debugMode) return false;
  int startX = width - 360 - 150;
  int startY = 20 + 150 + 60;
  int panelW = 140;
  int panelH = 110;
  if (mouseX < startX || mouseX > startX + panelW || mouseY < startY || mouseY > startY + panelH) {
    return false;
  }
  float slider1 = map(constrain(mouseX, startX + 10, startX + panelW - 10), startX + 10, startX + panelW - 10, 0, 1);
  float sliderValue = slider1;
  if (mouseY >= startY + 30 && mouseY <= startY + 40) {
    uiSpeedMix = sliderValue;
  } else if (mouseY >= startY + 55 && mouseY <= startY + 65) {
    uiSpeedGain = 0.1f + sliderValue * (2.0f - 0.1f);
  } else if (mouseY >= startY + 80 && mouseY <= startY + 90) {
    uiKickBoost = sliderValue * 1.2f;
  }
  return true;
}

// ============================================
// SHADER UNIFORM APPLICATION
// ============================================

void applyAudioUniformsToShader(PShader s) {
  if (s == null) return;
  try {
    s.set("bass", smoothAudioBass);
    s.set("lowMid", smoothAudioLowMid);
    s.set("mid", smoothAudioMid);
    s.set("highs", smoothAudioHighs);
    s.set("treble", smoothAudioHighs);
    s.set("level", smoothAudioLevel);
    s.set("kickEnv", kickEnv);
    s.set("kickPulse", (float)kickPulse);
    s.set("beat", beatPhaseAudio);
    s.set("beat4", beat4 / 3.0f);
    s.set("energyFast", energyFast);
    s.set("energySlow", energySlow);
    s.set("presenceLow", presenceBass);
    s.set("presenceMid", presenceMid);
    s.set("presenceHigh", presenceHigh);
    s.set("presenceAll", presenceAll);
    s.set("beatOn", beatOnSmooth);
    s.set("beatRandom", beatRandom);
    s.set("beatBarPhase", beatBarPhase);

    float tempoSaw = constrain(bpmTwitcher, 0, 1);
    float tempoSin = constrain((bpmSin4 * 0.5f) + 0.5f, 0, 1);
    float beatGroove = max(beatPhaseAudio, beatOnSmooth);
    float reactiveSpeed = computeAudioReactiveSpeed();
    s.set("speed", reactiveSpeed);
    s.set("tempoSaw", tempoSaw);
    s.set("tempoSin", tempoSin);
    s.set("tempoConfidence", bpmConfidence);
    s.set("beatGroove", beatGroove);
    
    for (String uniform : boundUniformValues.keySet()) {
      s.set(uniform, boundUniformValues.get(uniform));
    }
  } catch (Exception ignored) {}
}
