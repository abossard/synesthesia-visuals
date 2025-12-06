/**
 * Data Classes for VJUniverse
 * Pure data structures - immutable where possible
 */

// ============================================
// SHADER INFO
// ============================================

enum ShaderType {
  GLSL, ISF
}

class ShaderInfo {
  final String name;
  final String path;
  final ShaderType type;
  final boolean is3D;
  final boolean isGlitch;
  final boolean isDark;
  final boolean isBright;
  final boolean isPost;
  final String[] tags;
  
  ShaderInfo(String name, String path, ShaderType type) {
    this.name = name;
    this.path = path;
    this.type = type;
    
    // Infer properties from filename
    String lower = name.toLowerCase();
    this.is3D = lower.contains("3d") || lower.contains("tunnel") || lower.contains("raymarch");
    this.isGlitch = lower.contains("glitch") || lower.contains("distort");
    this.isDark = lower.contains("dark") || lower.contains("shadow");
    this.isBright = lower.contains("neon") || lower.contains("glow") || lower.contains("bloom");
    this.isPost = lower.contains("post") || lower.contains("bloom") || lower.contains("blur");
    
    // Build tags array
    ArrayList<String> tagList = new ArrayList<String>();
    if (is3D) tagList.add("3d");
    if (isGlitch) tagList.add("glitch");
    if (isDark) tagList.add("dark");
    if (isBright) tagList.add("bright");
    if (isPost) tagList.add("post");
    if (tagList.size() == 0) tagList.add("generator");
    this.tags = tagList.toArray(new String[0]);
  }
  
  String getTagString() {
    return String.join(", ", tags);
  }
}

// ============================================
// SHADER SELECTION
// ============================================

class ShaderSelection {
  final String songId;
  final String[] shaderIds;
  final String mood;
  final long createdAt;
  
  ShaderSelection(String songId, String[] shaderIds, String mood) {
    this.songId = songId;
    this.shaderIds = shaderIds;
    this.mood = mood;
    this.createdAt = System.currentTimeMillis();
  }
  
  ShaderSelection(String songId, String[] shaderIds, String mood, long createdAt) {
    this.songId = songId;
    this.shaderIds = shaderIds;
    this.mood = mood;
    this.createdAt = createdAt;
  }
}

// ============================================
// SHADER ANALYSIS (LLM-generated + ISF parsed)
// ============================================

// Input capabilities parsed from ISF JSON header
class ShaderInputs {
  final int floatCount;        // Number of float sliders (MIDI mappable)
  final int point2DCount;      // Number of point2D inputs (mouse/touch)
  final int colorCount;        // Number of color pickers
  final int boolCount;         // Number of toggles
  final int imageCount;        // Number of image inputs (compositing)
  final boolean hasAudio;      // Has audio/audioFFT input
  final String[] inputNames;   // All input names for reference
  
  ShaderInputs() {
    this(0, 0, 0, 0, 0, false, new String[0]);
  }
  
  ShaderInputs(int floatCount, int point2DCount, int colorCount, int boolCount,
               int imageCount, boolean hasAudio, String[] inputNames) {
    this.floatCount = floatCount;
    this.point2DCount = point2DCount;
    this.colorCount = colorCount;
    this.boolCount = boolCount;
    this.imageCount = imageCount;
    this.hasAudio = hasAudio;
    this.inputNames = inputNames;
  }
  
  // Capability checks for VJ matching
  boolean isInteractive() { return point2DCount > 0; }
  boolean isCompositable() { return imageCount > 0; }
  boolean isMidiMappable() { return floatCount >= 2; }
  boolean isAudioReactive() { return hasAudio; }
  boolean isAutonomous() { return floatCount == 0 && point2DCount == 0 && imageCount == 0; }
  
  int totalControls() { return floatCount + point2DCount + colorCount + boolCount; }
  
  String getCapabilityString() {
    ArrayList<String> caps = new ArrayList<String>();
    if (isAutonomous()) caps.add("generator");
    if (isInteractive()) caps.add("interactive");
    if (isCompositable()) caps.add("compositor");
    if (isMidiMappable()) caps.add("midi-mappable");
    if (isAudioReactive()) caps.add("audio-reactive");
    return caps.size() > 0 ? String.join(", ", caps) : "basic";
  }
}

class ShaderAnalysis {
  final String shaderName;
  final String mood;           // e.g., "energetic", "calm", "dark", "psychedelic"
  final String[] colors;       // dominant colors e.g., ["blue", "purple", "cyan"]
  final String[] geometry;     // e.g., ["circles", "lines", "fractals", "grid"]
  final String[] objects;      // e.g., ["tunnel", "waves", "particles", "landscape"]
  final String[] effects;      // e.g., ["glow", "distortion", "feedback", "blur"]
  final String energy;         // "low", "medium", "high"
  final String complexity;     // "simple", "medium", "complex"
  final String description;    // brief description
  final long analyzedAt;
  
  // Normalized feature scores for semantic matching (0.0 to 1.0, mood_valence: -1.0 to 1.0)
  final HashMap<String, Float> features;
  
  // Input capabilities parsed from ISF header
  final ShaderInputs inputs;
  
  // Feature keys for matching
  static final String FEAT_ENERGY = "energy_score";
  static final String FEAT_MOOD = "mood_valence";
  static final String FEAT_WARMTH = "color_warmth";
  static final String FEAT_MOTION = "motion_speed";
  static final String FEAT_GEOMETRIC = "geometric_score";
  static final String FEAT_DENSITY = "visual_density";
  
  ShaderAnalysis(String shaderName, String mood, String[] colors, String[] geometry,
                 String[] objects, String[] effects, String energy, 
                 String complexity, String description) {
    this(shaderName, mood, colors, geometry, objects, effects, energy, 
         complexity, description, System.currentTimeMillis(), new HashMap<String, Float>(), new ShaderInputs());
  }
  
  ShaderAnalysis(String shaderName, String mood, String[] colors, String[] geometry,
                 String[] objects, String[] effects, String energy, 
                 String complexity, String description, long analyzedAt) {
    this(shaderName, mood, colors, geometry, objects, effects, energy, 
         complexity, description, analyzedAt, new HashMap<String, Float>(), new ShaderInputs());
  }
  
  ShaderAnalysis(String shaderName, String mood, String[] colors, String[] geometry,
                 String[] objects, String[] effects, String energy, 
                 String complexity, String description, long analyzedAt,
                 HashMap<String, Float> features) {
    this(shaderName, mood, colors, geometry, objects, effects, energy, 
         complexity, description, analyzedAt, features, new ShaderInputs());
  }
  
  ShaderAnalysis(String shaderName, String mood, String[] colors, String[] geometry,
                 String[] objects, String[] effects, String energy, 
                 String complexity, String description, long analyzedAt,
                 HashMap<String, Float> features, ShaderInputs inputs) {
    this.shaderName = shaderName;
    this.mood = mood;
    this.colors = colors;
    this.geometry = geometry;
    this.objects = objects;
    this.effects = effects;
    this.energy = energy;
    this.complexity = complexity;
    this.description = description;
    this.analyzedAt = analyzedAt;
    this.features = features != null ? features : new HashMap<String, Float>();
    this.inputs = inputs != null ? inputs : new ShaderInputs();
  }
  
  // Get feature value with default
  float getFeature(String key, float defaultVal) {
    return features.containsKey(key) ? features.get(key) : defaultVal;
  }
  
  // Convenience getters for common features
  float getEnergyScore() { return getFeature(FEAT_ENERGY, 0.5f); }
  float getMoodValence() { return getFeature(FEAT_MOOD, 0.0f); }
  float getColorWarmth() { return getFeature(FEAT_WARMTH, 0.5f); }
  float getMotionSpeed() { return getFeature(FEAT_MOTION, 0.5f); }
  float getGeometricScore() { return getFeature(FEAT_GEOMETRIC, 0.5f); }
  float getVisualDensity() { return getFeature(FEAT_DENSITY, 0.5f); }
  
  // Check if features are populated
  boolean hasFeatures() {
    return features != null && features.size() > 0;
  }
  
  // Get all tags as a combined array for matching
  String[] getAllTags() {
    ArrayList<String> tags = new ArrayList<String>();
    tags.add(mood);
    tags.add(energy);
    tags.add(complexity);
    for (String c : colors) tags.add(c);
    for (String g : geometry) tags.add(g);
    for (String o : objects) tags.add(o);
    for (String e : effects) tags.add(e);
    return tags.toArray(new String[0]);
  }
  
  String getTagString() {
    return String.join(", ", getAllTags());
  }
  
  // Get feature vector as array for distance calculations
  float[] getFeatureVector() {
    return new float[] {
      getEnergyScore(),
      getMoodValence(),
      getColorWarmth(),
      getMotionSpeed(),
      getGeometricScore(),
      getVisualDensity()
    };
  }
}

// ============================================
// SCENE STATE
// ============================================

class SceneState {
  final ShaderSelection selection;
  final float globalIntensity;  // 0..1 from audio
  final float beat;             // 0..1 for current beat phase
  
  SceneState(ShaderSelection selection, float globalIntensity, float beat) {
    this.selection = selection;
    this.globalIntensity = globalIntensity;
    this.beat = beat;
  }
  
  SceneState withSelection(ShaderSelection newSelection) {
    return new SceneState(newSelection, globalIntensity, beat);
  }
  
  SceneState withAudio(float newIntensity, float newBeat) {
    return new SceneState(selection, newIntensity, newBeat);
  }
}

// ============================================
// UTILITY FUNCTIONS
// ============================================

String sanitizeFilename(String input) {
  if (input == null || input.isEmpty()) return "unknown";
  return input.toLowerCase()
    .replaceAll("[^a-z0-9]", "_")
    .replaceAll("_+", "_")
    .replaceAll("^_|_$", "");
}
