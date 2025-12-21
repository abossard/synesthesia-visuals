/**
 * Shader Management for VJUniverse
 * Handles loading GLSL shaders (.glsl, .txt, .frag) from the data folder
 */

// Auto-reload tracking
long lastGlslDirModified = 0;
int autoReloadCheckInterval = 5000;  // ms
int lastAutoReloadCheck = 0;

// GLSL detected uniforms - auto-detected from shader source
HashMap<String, String> glslDetectedUniforms = new HashMap<String, String>();

// Shader analyses cache (indexed by shader name) - loaded from .analysis.json files
HashMap<String, ShaderAnalysis> shaderAnalyses = new HashMap<String, ShaderAnalysis>();

// Shader type filter for manual navigation (T key toggles) - removed, only GLSL now

// Shader list (only GLSL shaders)
ArrayList<ShaderInfo> glslShaders = new ArrayList<ShaderInfo>();

// Error logging - accumulated errors written to errors.json
ArrayList<String> shaderErrors = new ArrayList<String>();
final String ERRORS_FILE = "errors.json";

// ============================================
// SHADER LOADING
// ============================================

void loadAllShaders() {
  availableShaders.clear();
  glslShaders.clear();
  shaderAnalyses.clear();
  shaderErrors.clear();
  
  // Load GLSL shaders
  loadGlslShaders();
  
  // Update directory timestamps
  File glslDir = new File(dataPath(SHADERS_PATH + "/glsl"));
  if (glslDir.exists()) lastGlslDirModified = getNewestFileTime(glslDir);
  
  println("Loaded " + availableShaders.size() + " GLSL shaders");
  
  // Load existing analysis files (from Python-side analysis)
  loadShaderAnalyses();
  
  // Filter out rating=5 shaders and warn about rating=4 (masks)
  filterShadersByRating();
}

void reloadShadersIfChanged() {
  // Only check periodically
  if (millis() - lastAutoReloadCheck < autoReloadCheckInterval) return;
  lastAutoReloadCheck = millis();
  
  File glslDir = new File(dataPath(SHADERS_PATH + "/glsl"));
  
  boolean changed = false;
  
  // Check GLSL directory
  if (glslDir.exists()) {
    long currentMod = getNewestFileTime(glslDir);
    if (currentMod > lastGlslDirModified) {
      changed = true;
      lastGlslDirModified = currentMod;
    }
  }
  
  if (changed) {
    println("Shader files changed, reloading...");
    loadAllShaders();
  }
}

long getNewestFileTime(File dir) {
  long newest = dir.lastModified();
  File[] files = dir.listFiles();
  if (files != null) {
    for (File f : files) {
      if (f.isDirectory()) {
        // Recurse into subdirectories
        long subNewest = getNewestFileTime(f);
        if (subNewest > newest) {
          newest = subNewest;
        }
      } else if (f.lastModified() > newest) {
        newest = f.lastModified();
      }
    }
  }
  return newest;
}

void loadGlslShaders() {
  File glslDir = new File(dataPath(SHADERS_PATH + "/glsl"));
  if (!glslDir.exists()) {
    println("[GLSL] Shader directory not found: " + glslDir.getPath());
    return;
  }
  
  File[] files = glslDir.listFiles();
  if (files == null) return;
  
  int count = 0;
  for (File f : files) {
    // Support both .frag, .txt, and .glsl extensions
    if (isGlslFile(f.getName())) {
      String name = stripGlslExtension(f.getName());
      String path = SHADERS_PATH + "/glsl/" + f.getName();
      ShaderInfo info = new ShaderInfo(name, path, ShaderType.GLSL);
      availableShaders.add(info);
      glslShaders.add(info);
      count++;
    }
  }
  println("[GLSL] Loaded " + count + " shaders");
}

// Pure function: check if filename is a GLSL shader
boolean isGlslFile(String filename) {
  String lower = filename.toLowerCase();
  return lower.endsWith(".frag") || lower.endsWith(".txt") || lower.endsWith(".glsl");
}

// Pure function: strip GLSL extension from filename
String stripGlslExtension(String filename) {
  if (filename.endsWith(".frag")) return filename.replace(".frag", "");
  if (filename.endsWith(".txt")) return filename.replace(".txt", "");
  if (filename.endsWith(".glsl")) return filename.replace(".glsl", "");
  return filename;
}

/**
 * Load and convert a raw GLSL shader for Processing
 * Adds precision qualifiers, audio uniforms, and Processing compatibility
 */
PShader loadGlslShader(String path) {
  String[] lines = loadStrings(path);
  if (lines == null) {
    String error = "Could not read file: " + path;
    println("[GLSL] " + error);
    logShaderError(path, path, error, ShaderType.GLSL);
    return null;
  }
  
  // Clear previous detected uniforms
  glslDetectedUniforms.clear();
  
  String glslSource = String.join("\n", lines);
  String convertedGlsl = convertGlslForProcessing(glslSource);
  
  // Save converted shader to temp file and load
  String tempPath = "temp_glsl_converted.frag";
  saveStrings(dataPath(tempPath), new String[]{convertedGlsl});
  
  try {
    return loadShader(tempPath);
  } catch (Exception e) {
    String error = "GLSL compilation failed: " + e.getMessage();
    if (e.getCause() != null) {
      error += " | Cause: " + e.getCause().getMessage();
    }
    println("[GLSL] Shader error: " + error);
    logShaderError(path, path, error, ShaderType.GLSL);
    throw e;
  }
}

/**
 * Convert raw GLSL (Shadertoy-style) to Processing-compatible fragment shader
 * 
 * This is a CALCULATION (pure function) - no side effects
 * Input: raw GLSL source
 * Output: Processing-compatible GLSL with audio uniforms
 */
String convertGlslForProcessing(String glslSource) {
  StringBuilder sb = new StringBuilder();
  
  // Detect what uniforms the shader already declares
  boolean hasTime = glslSource.contains("uniform float time");
  boolean hasMouse = glslSource.contains("uniform vec2 mouse");
  boolean hasResolution = glslSource.contains("uniform vec2 resolution");
  boolean hasSpeed = glslSource.contains("uniform float speed");
  boolean hasPrecision = glslSource.contains("precision ");
  
  // Auto-detect other uniform patterns (store for reference)
  detectGlslUniforms(glslSource);
  
  // Add precision qualifiers if not present
  if (!hasPrecision) {
    sb.append("#ifdef GL_ES\n");
    sb.append("precision highp float;\n");
    sb.append("precision highp int;\n");
    sb.append("#endif\n\n");
  }
  
  // Add standard uniforms FIRST (Processing will set these)
  if (!hasTime) sb.append("uniform float time;\n");
  if (!hasMouse) sb.append("uniform vec2 mouse;\n");
  if (!hasResolution) sb.append("uniform vec2 resolution;\n");
  sb.append("\n");
  
  // Add speed uniform for audio-reactive time scaling (0-1)
  // This is THE KEY audio reactivity hook for GLSL shaders
  if (!hasSpeed) {
    sb.append("uniform float speed;  // Audio-reactive speed 0-1\n");
  }
  sb.append("\n");
  
  // Add audio uniforms (always inject, shader can use or ignore)
  sb.append(generateAudioUniformDeclarations());
  sb.append("\n");
  
  // Add the original shader source
  sb.append(glslSource);
  
  return sb.toString();
}

/**
 * Detect uniforms declared in GLSL source
 * Stores in glslDetectedUniforms for debugging/analysis
 */
void detectGlslUniforms(String source) {
  // Simple pattern matching for uniform declarations
  String[] lines = source.split("\n");
  for (String line : lines) {
    line = line.trim();
    if (line.startsWith("uniform ")) {
      // Parse: uniform type name;
      String[] parts = line.replace(";", "").split("\\s+");
      if (parts.length >= 3) {
        String type = parts[1];
        String name = parts[2];
        glslDetectedUniforms.put(name, type);
      }
    }
  }
  
  if (glslDetectedUniforms.size() > 0) {
    println("[GLSL] Detected uniforms: " + glslDetectedUniforms.keySet());
  }
}

/**
 * Generate audio uniform declarations for GLSL shaders
 * 
 * This is a CALCULATION (pure function) - returns string, no side effects
 */
String generateAudioUniformDeclarations() {
  StringBuilder sb = new StringBuilder();
  sb.append("// Audio-reactive uniforms (injected by VJUniverse)\n");
  sb.append("uniform float bass;       // Low frequency energy 0-1\n");
  sb.append("uniform float lowMid;     // Low-mid energy 0-1\n");
  sb.append("uniform float mid;        // Mid frequency energy 0-1\n");
  sb.append("uniform float highs;      // High frequency energy 0-1\n");
  sb.append("uniform float level;      // Overall loudness 0-1\n");
  sb.append("uniform float kickEnv;    // Kick/beat envelope 0-1\n");
  sb.append("uniform float kickPulse;  // 1 on kick, decays to 0\n");
  sb.append("uniform float beat;       // Beat phase 0-1\n");
  sb.append("uniform float energyFast; // Fast energy envelope\n");
  sb.append("uniform float energySlow; // Slow energy envelope\n");
  return sb.toString();
}


void loadShaderByIndex(int index) {
  if (index < 0 || index >= availableShaders.size()) {
    println("Invalid shader index: " + index);
    activeShader = null;
    return;
  }
  
  ShaderInfo info = availableShaders.get(index);
  currentShaderIndex = index;
  
  try {
    activeShader = loadGlslShader(info.path);
    println("Loaded GLSL shader: " + info.name);
    
    // Setup default audio bindings if none were configured via OSC
    if (audioBindings.size() == 0) {
      setupDefaultAudioBindings();
    }
    
    // Schedule screenshot after shader loads successfully
    scheduleScreenshot(info.name);
    
  } catch (Exception e) {
    String error = e.getMessage();
    if (e.getCause() != null) {
      error += " | Cause: " + e.getCause().getMessage();
    }
    println("Error loading shader " + info.name + ": " + error);
    logShaderError(info.name, info.path, error, info.type);
    activeShader = null;
  }
}

// Get current shader info
ShaderInfo getCurrentShaderInfo() {
  if (currentShaderIndex >= 0 && currentShaderIndex < availableShaders.size()) {
    return availableShaders.get(currentShaderIndex);
  }
  return null;
}

String normalizeShaderRequest(String request) {
  if (request == null) return null;
  String normalized = request.trim().replace("\\", "/");
  if (normalized.length() == 0) return normalized;
  // Strip optional type prefix (glsl/)
  int slash = normalized.indexOf('/');
  if (slash > 0) {
    String prefix = normalized.substring(0, slash).toLowerCase();
    if (prefix.equals("glsl")) {
      normalized = normalized.substring(slash + 1);
    }
  }
  // Remove known extensions
  if (normalized.endsWith(".frag")) normalized = normalized.substring(0, normalized.length()-5);
  else if (normalized.endsWith(".txt")) normalized = normalized.substring(0, normalized.length()-4);
  else if (normalized.endsWith(".glsl")) normalized = normalized.substring(0, normalized.length()-5);
  else if (normalized.endsWith(".fs")) normalized = normalized.substring(0, normalized.length()-3);
  return normalized;
}

void loadShaderByName(String name) {
  String normalized = normalizeShaderRequest(name);
  if (normalized == null || normalized.length() == 0) {
    println("Shader request was empty");
    return;
  }
  // Search in ALL shaders - allows OSC to load any shader
  for (int i = 0; i < availableShaders.size(); i++) {
    ShaderInfo info = availableShaders.get(i);
    if (info.name.equals(normalized) || info.name.equalsIgnoreCase(normalized)) {
      loadShaderByIndex(i);
      return;
    }
  }
  println("Shader not found: " + name + " (normalized: " + normalized + ")");
}

// ============================================
// SHADER LOOKUP
// ============================================

PShader getShaderByName(String name) {
  for (int i = 0; i < availableShaders.size(); i++) {
    if (availableShaders.get(i).name.equals(name)) {
      ShaderInfo info = availableShaders.get(i);
      try {
        return loadGlslShader(info.path);
      } catch (Exception e) {
        String error = e.getMessage();
        println("Error loading shader " + name + ": " + error);
        logShaderError(name, info.path, error, info.type);
        return null;
      }
    }
  }
  println("Shader not found: " + name);
  return null;
}

// ============================================
// SHADER ANALYSIS LOADING
// ============================================

void loadShaderAnalyses() {
  // Load existing analysis files (created by Python)
  for (ShaderInfo shader : availableShaders) {
    ShaderAnalysis existing = loadShaderAnalysis(shader.path);
    if (existing != null) {
      shaderAnalyses.put(shader.name, existing);
    }
  }
  println("Loaded " + shaderAnalyses.size() + "/" + availableShaders.size() + " shader analyses");
}

/**
 * Filter out rating=5 shaders and warn about rating=4 (mask candidates).
 * Rating meanings:
 *   1 = BEST (use often)
 *   2 = GOOD (special occasions)
 *   3 = NORMAL (working shader)
 *   4 = MASK (usable as black/white mask)
 *   5 = SKIP (don't use)
 */
void filterShadersByRating() {
  ArrayList<ShaderInfo> filtered = new ArrayList<ShaderInfo>();
  ArrayList<String> skipped = new ArrayList<String>();
  ArrayList<String> masks = new ArrayList<String>();
  
  for (ShaderInfo shader : availableShaders) {
    ShaderAnalysis analysis = shaderAnalyses.get(shader.name);
    int rating = (analysis != null) ? analysis.getEffectiveRating() : 3;
    
    if (rating == 5) {
      skipped.add(shader.name);
    } else {
      filtered.add(shader);
      if (rating == 4) {
        masks.add(shader.name);
      }
    }
  }
  
  // Update available shaders
  availableShaders = filtered;
  
  // Log skipped shaders
  if (skipped.size() > 0) {
    println("[Rating] Skipped " + skipped.size() + " shaders with rating=5 (SKIP):");
    for (String name : skipped) {
      println("  - " + name);
    }
  }
  
  // Warn about mask shaders
  if (masks.size() > 0) {
    println("[Rating] " + masks.size() + " shaders with rating=4 (MASK-only):");
    for (String name : masks) {
      println("  ◐ " + name);
    }
  }
  
  // Stats summary
  int best = 0, good = 0, normal = 0;
  for (ShaderInfo shader : availableShaders) {
    ShaderAnalysis analysis = shaderAnalyses.get(shader.name);
    int rating = (analysis != null) ? analysis.getEffectiveRating() : 3;
    if (rating == 1) best++;
    else if (rating == 2) good++;
    else if (rating == 3) normal++;
  }
  println("[Rating] Available: " + best + " BEST, " + good + " GOOD, " + normal + " NORMAL, " + masks.size() + " MASK");
}

// ============================================
// ERROR LOGGING
// ============================================

void logShaderError(String shaderName, String filePath, String error, ShaderType type) {
  // Build JSON entry with shader type
  String timestamp = new java.text.SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss").format(new java.util.Date());
  String escapedError = error.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n");
  String entry = "{\"name\":\"" + shaderName + "\",\"path\":\"" + filePath + 
                 "\",\"type\":\"" + type.toString() + "\",\"error\":\"" + escapedError + 
                 "\",\"timestamp\":\"" + timestamp + "\"}";
  shaderErrors.add(entry);
  
  // Write to file
  saveErrorsFile();
}

// Backward compatibility overload
void logShaderError(String shaderName, String filePath, String error) {
  ShaderType type = ShaderType.GLSL;  // Default
  for (ShaderInfo info : availableShaders) {
    if (info.name.equals(shaderName) || info.path.equals(filePath)) {
      type = info.type;
      break;
    }
  }
  logShaderError(shaderName, filePath, error, type);
}

void saveErrorsFile() {
  StringBuilder sb = new StringBuilder();
  sb.append("[\n");
  for (int i = 0; i < shaderErrors.size(); i++) {
    sb.append("  ").append(shaderErrors.get(i));
    if (i < shaderErrors.size() - 1) sb.append(",");
    sb.append("\n");
  }
  sb.append("]");
  saveStrings(dataPath(ERRORS_FILE), new String[]{sb.toString()});
  println("Shader errors saved to: " + ERRORS_FILE);
}

// Get analysis for a shader by name
ShaderAnalysis getShaderAnalysis(String shaderName) {
  return shaderAnalyses.get(shaderName);
}

// Get all analyzed shaders matching a mood
ArrayList<ShaderInfo> getShadersForMood(String mood) {
  ArrayList<ShaderInfo> matches = new ArrayList<ShaderInfo>();
  
  for (ShaderInfo shader : availableShaders) {
    ShaderAnalysis analysis = shaderAnalyses.get(shader.name);
    if (analysis != null && analysis.mood.equalsIgnoreCase(mood)) {
      matches.add(shader);
    }
  }
  
  return matches;
}

// Get all analyzed shaders with high energy
ArrayList<ShaderInfo> getHighEnergyShaders() {
  ArrayList<ShaderInfo> matches = new ArrayList<ShaderInfo>();
  
  for (ShaderInfo shader : availableShaders) {
    ShaderAnalysis analysis = shaderAnalyses.get(shader.name);
    if (analysis != null && analysis.energy.equalsIgnoreCase("high")) {
      matches.add(shader);
    }
  }
  
  return matches;
}

// ============================================
// TYPE FILTER (LEGACY - now GLSL only)
// ============================================

// No filter applied since we only support GLSL shaders now
ShaderType currentTypeFilter = null;

// Returns all available shaders (no filtering since ISF was removed)
ArrayList<ShaderInfo> getFilteredShaderList() {
  return availableShaders;
}

// No-op since we only support GLSL now
void toggleShaderTypeFilter() {
  // ISF support was removed - only GLSL shaders are used
  println("Type filter disabled (GLSL only mode)");
}
