/**
 * Shader Management for VJUniverse
 * Handles loading GLSL and ISF shaders from the data folder
 */

// Auto-reload tracking
long lastGlslDirModified = 0;
long lastIsfDirModified = 0;
int autoReloadCheckInterval = 5000;  // ms
int lastAutoReloadCheck = 0;

// ISF uniform defaults - stores default values for ISF INPUTS
// Maps uniform name -> default value (float, vec2, vec3, vec4, or bool as float 0/1)
HashMap<String, float[]> isfUniformDefaults = new HashMap<String, float[]>();

// GLSL detected uniforms - auto-detected from shader source
HashMap<String, String> glslDetectedUniforms = new HashMap<String, String>();

// Shader analyses cache (indexed by shader name) - loaded from .analysis.json files
HashMap<String, ShaderAnalysis> shaderAnalyses = new HashMap<String, ShaderAnalysis>();

// Shader type filter for manual navigation (T key toggles)
ShaderType currentTypeFilter = null;  // null = show all types

// Separate lists for each type (for filtered navigation)
ArrayList<ShaderInfo> glslShaders = new ArrayList<ShaderInfo>();
ArrayList<ShaderInfo> isfShaders = new ArrayList<ShaderInfo>();

// Error logging - accumulated errors written to errors.json
ArrayList<String> shaderErrors = new ArrayList<String>();
final String ERRORS_FILE = "errors.json";

// ============================================
// SHADER LOADING
// ============================================

void loadAllShaders() {
  availableShaders.clear();
  glslShaders.clear();
  isfShaders.clear();
  shaderAnalyses.clear();
  shaderErrors.clear();
  
  // Load GLSL shaders
  loadGlslShaders();
  
  // Load ISF shaders
  loadIsfShaders();
  
  // Update directory timestamps
  File glslDir = new File(dataPath(SHADERS_PATH + "/glsl"));
  File isfDir = new File(dataPath(SHADERS_PATH + "/isf"));
  if (glslDir.exists()) lastGlslDirModified = getNewestFileTime(glslDir);
  if (isfDir.exists()) lastIsfDirModified = getNewestFileTime(isfDir);
  
  println("Loaded " + availableShaders.size() + " shaders total");
  println("  GLSL: " + glslShaders.size() + ", ISF: " + isfShaders.size());
  
  // Load existing analysis files (from Python-side analysis)
  loadShaderAnalyses();
}

void reloadShadersIfChanged() {
  // Only check periodically
  if (millis() - lastAutoReloadCheck < autoReloadCheckInterval) return;
  lastAutoReloadCheck = millis();
  
  File glslDir = new File(dataPath(SHADERS_PATH + "/glsl"));
  File isfDir = new File(dataPath(SHADERS_PATH + "/isf"));
  
  boolean changed = false;
  
  // Check GLSL directory
  if (glslDir.exists()) {
    long currentMod = getNewestFileTime(glslDir);
    if (currentMod > lastGlslDirModified) {
      changed = true;
      lastGlslDirModified = currentMod;
    }
  }
  
  // Check ISF directory
  if (isfDir.exists()) {
    long currentMod = getNewestFileTime(isfDir);
    if (currentMod > lastIsfDirModified) {
      changed = true;
      lastIsfDirModified = currentMod;
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
 * Generate audio uniform declarations (shared between GLSL and ISF)
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

void loadIsfShaders() {
  File isfDir = new File(dataPath(SHADERS_PATH + "/isf"));
  if (!isfDir.exists()) {
    println("[ISF] Shader directory not found: " + isfDir.getPath());
    return;
  }
  
  // Recursively load shaders from directory and subdirectories
  loadIsfShadersRecursive(isfDir, "");
  println("[ISF] Loaded " + isfShaders.size() + " shaders");
}

void loadIsfShadersRecursive(File dir, String prefix) {
  File[] files = dir.listFiles();
  if (files == null) return;
  
  for (File f : files) {
    // Recurse into subdirectories
    if (f.isDirectory()) {
      String subPrefix = prefix.isEmpty() ? f.getName() : prefix + "/" + f.getName();
      loadIsfShadersRecursive(f, subPrefix);
      continue;
    }
    
    // Load .fs and .isf files (must be actual files, not directories)
    if (!f.isFile()) continue;  // Skip directories with .fs extension
    
    if (f.getName().endsWith(".fs") || f.getName().endsWith(".isf")) {
      // Skip vertex shaders
      if (f.getName().endsWith(".vs.fs")) continue;
      
      String baseName = f.getName().replace(".fs", "").replace(".isf", "");
      String name = prefix.isEmpty() ? baseName : prefix + "/" + baseName;
      String path = SHADERS_PATH + "/isf/" + (prefix.isEmpty() ? "" : prefix + "/") + f.getName();
      ShaderInfo info = new ShaderInfo(name, path, ShaderType.ISF);
      availableShaders.add(info);
      isfShaders.add(info);
    }
  }
}

void loadShaderByIndex(int index) {
  // Use filtered list for navigation
  ArrayList<ShaderInfo> targetList = getFilteredShaderList();
  
  if (index < 0 || index >= targetList.size()) {
    println("Invalid shader index: " + index);
    activeShader = null;
    return;
  }
  
  ShaderInfo info = targetList.get(index);
  currentShaderIndex = index;
  
  try {
    if (info.type == ShaderType.ISF) {
      activeShader = loadIsfShader(info.path);
    } else {
      activeShader = loadGlslShader(info.path);
    }
    println("Loaded " + info.type + " shader: " + info.name);
    
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

// Get shader list based on current type filter
ArrayList<ShaderInfo> getFilteredShaderList() {
  if (currentTypeFilter == null) {
    return availableShaders;
  } else if (currentTypeFilter == ShaderType.GLSL) {
    return glslShaders;
  } else {
    return isfShaders;
  }
}

// Toggle shader type filter (T key)
void toggleShaderTypeFilter() {
  if (currentTypeFilter == null) {
    currentTypeFilter = ShaderType.GLSL;
    println("Filter: GLSL only (" + glslShaders.size() + " shaders)");
  } else if (currentTypeFilter == ShaderType.GLSL) {
    currentTypeFilter = ShaderType.ISF;
    println("Filter: ISF only (" + isfShaders.size() + " shaders)");
  } else {
    currentTypeFilter = null;
    println("Filter: All shaders (" + availableShaders.size() + " shaders)");
  }
  
  // Reset to first shader in filtered list
  currentShaderIndex = 0;
  ArrayList<ShaderInfo> list = getFilteredShaderList();
  if (list.size() > 0) {
    loadShaderByIndex(0);
  }
  
  consoleLog("Type: " + (currentTypeFilter == null ? "ALL" : currentTypeFilter.toString()));
}

// Get current shader info (respecting filter)
ShaderInfo getCurrentShaderInfo() {
  ArrayList<ShaderInfo> list = getFilteredShaderList();
  if (currentShaderIndex >= 0 && currentShaderIndex < list.size()) {
    return list.get(currentShaderIndex);
  }
  return null;
}

String normalizeShaderRequest(String request) {
  if (request == null) return null;
  String normalized = request.trim().replace("\\", "/");
  if (normalized.length() == 0) return normalized;
  // Strip optional type prefix (glsl/, isf/)
  int slash = normalized.indexOf('/');
  if (slash > 0) {
    String prefix = normalized.substring(0, slash).toLowerCase();
    if (prefix.equals("glsl") || prefix.equals("isf")) {
      normalized = normalized.substring(slash + 1);
    }
  }
  // Remove known extensions
  if (normalized.endsWith(".frag")) normalized = normalized.substring(0, normalized.length()-5);
  else if (normalized.endsWith(".txt")) normalized = normalized.substring(0, normalized.length()-4);
  else if (normalized.endsWith(".glsl")) normalized = normalized.substring(0, normalized.length()-5);
  else if (normalized.endsWith(".fs")) normalized = normalized.substring(0, normalized.length()-3);
  else if (normalized.endsWith(".isf")) normalized = normalized.substring(0, normalized.length()-4);
  return normalized;
}

void loadShaderByName(String name) {
  String normalized = normalizeShaderRequest(name);
  if (normalized == null || normalized.length() == 0) {
    println("Shader request was empty");
    return;
  }
  // Search in ALL shaders (not filtered) - allows OSC to load any shader
  for (int i = 0; i < availableShaders.size(); i++) {
    ShaderInfo info = availableShaders.get(i);
    if (info.name.equals(normalized) || info.name.equalsIgnoreCase(normalized)) {
      
      // Temporarily disable filter to load by absolute index
      ShaderType savedFilter = currentTypeFilter;
      currentTypeFilter = null;
      loadShaderByIndex(i);
      currentTypeFilter = savedFilter;
      return;
    }
  }
  println("Shader not found: " + name + " (normalized: " + normalized + ")");
}

// ============================================
// ISF SHADER CONVERSION
// ============================================

PShader loadIsfShader(String path) {
  String[] lines = loadStrings(path);
  if (lines == null) {
    String error = "Could not read file";
    println("Could not load ISF file: " + path);
    logShaderError(path, path, error);
    return null;
  }
  
  // Clear previous ISF defaults before loading new shader
  isfUniformDefaults.clear();
  
  String isfSource = String.join("\n", lines);
  String convertedGlsl = convertIsfToGlsl(isfSource);
  
  // Save converted shader to temp file and load
  String tempPath = "temp_isf_converted.frag";
  saveStrings(dataPath(tempPath), new String[]{convertedGlsl});
  
  try {
    return loadShader(tempPath);
  } catch (Exception e) {
    String error = "GLSL compilation failed: " + e.getMessage();
    println("ISF shader error: " + error);
    logShaderError(path, path, error);
    throw e;  // Re-throw to be caught by loadShaderByIndex
  }
}

String convertIsfToGlsl(String isfSource) {
  // Remove ISF JSON header if present and extract inputs
  String glslBody = isfSource;
  String jsonHeader = "";
  int headerEnd = isfSource.indexOf("*/");
  if (isfSource.startsWith("/*{") && headerEnd > 0) {
    jsonHeader = isfSource.substring(2, headerEnd).trim();  // Remove /* and */
    glslBody = isfSource.substring(headerEnd + 2).trim();
    println("  [ISF] Parsed JSON header (" + jsonHeader.length() + " chars)");
  } else {
    println("  [ISF] Warning: No JSON header found");
  }
  
  // Build Processing-compatible shader
  StringBuilder sb = new StringBuilder();
  
  // Add precision and uniforms
  sb.append("#ifdef GL_ES\n");
  sb.append("precision highp float;\n");
  sb.append("precision highp int;\n");
  sb.append("#endif\n\n");
  
  // Processing uniforms
  sb.append("uniform float time;\n");
  sb.append("uniform vec2 resolution;\n");
  sb.append("uniform float speed;  // Audio-reactive speed 0-1\n\n");
  
  // Parse ISF INPUTS and add as uniforms
  if (!jsonHeader.isEmpty()) {
    ArrayList<String> inputUniforms = parseIsfInputs(jsonHeader);
    println("  [ISF] Found " + inputUniforms.size() + " inputs, defaults: " + isfUniformDefaults.size());
    for (String uniform : inputUniforms) {
      sb.append(uniform).append("\n");
    }
    if (inputUniforms.size() > 0) {
      sb.append("\n");
    }
  }
  
  // Audio uniforms - use shared generation function
  sb.append(generateAudioUniformDeclarations());
  sb.append("\n");
  
  // ISF compatibility defines
  // ISF uses bottom-left origin, Processing uses top-left - flip Y coordinate
  // Use max(time, 0.001) to avoid log(0) and division by zero at startup
  sb.append("#define TIME max(time, 0.001)\n");
  sb.append("#define RENDERSIZE resolution\n");
  sb.append("#define isf_FragCoord vec2(gl_FragCoord.x, resolution.y - gl_FragCoord.y)\n");
  sb.append("#define isf_FragNormCoord (isf_FragCoord / resolution)\n");
  sb.append("#define FRAMEINDEX int(time * 60.0)\n\n");
  
  // Replace gl_FragCoord with flipped version for ISF compatibility
  // Use word boundary check to avoid replacing partial matches
  glslBody = glslBody.replaceAll("\\bgl_FragCoord\\b", "isf_FragCoord");
  
  // Add the shader body
  sb.append(glslBody);
  
  return sb.toString();
}

ArrayList<String> parseIsfInputs(String jsonHeader) {
  // Simple parser for ISF INPUTS array
  // Format: "INPUTS": [ { "NAME": "x", "TYPE": "float", "DEFAULT": 0.5 }, ... ]
  ArrayList<String> uniforms = new ArrayList<String>();
  
  int inputsStart = jsonHeader.indexOf("\"INPUTS\"");
  if (inputsStart < 0) return uniforms;
  
  int arrayStart = jsonHeader.indexOf("[", inputsStart);
  if (arrayStart < 0) return uniforms;
  
  // Find matching closing bracket
  int depth = 1;
  int pos = arrayStart + 1;
  while (pos < jsonHeader.length() && depth > 0) {
    char c = jsonHeader.charAt(pos);
    if (c == '[' || c == '{') depth++;
    else if (c == ']' || c == '}') depth--;
    pos++;
  }
  
  String inputsArray = jsonHeader.substring(arrayStart, pos);
  
  // Extract each input object
  int objStart = 0;
  while ((objStart = inputsArray.indexOf("{", objStart)) >= 0) {
    int objEnd = inputsArray.indexOf("}", objStart);
    if (objEnd < 0) break;
    
    String inputObj = inputsArray.substring(objStart, objEnd + 1);
    
    // Extract NAME, TYPE, and DEFAULT
    String name = extractJsonField(inputObj, "NAME");
    String type = extractJsonField(inputObj, "TYPE");
    String defaultVal = extractJsonField(inputObj, "DEFAULT");
    
    if (name != null && type != null) {
      String glslType = isfTypeToGlsl(type);
      String uniform = "uniform " + glslType + " " + name + ";";
      uniforms.add(uniform);
      
      // Store default value for this uniform
      println("  [ISF] Input: " + name + " (" + type + ") default=" + (defaultVal != null ? defaultVal : "null"));
      storeIsfDefault(name, type, defaultVal);
    }
    
    objStart = objEnd + 1;
  }
  
  return uniforms;
}

// Parse ISF header and extract input capabilities for VJ matching
ShaderInputs parseIsfInputCapabilities(String jsonHeader) {
  int floatCount = 0;
  int point2DCount = 0;
  int colorCount = 0;
  int boolCount = 0;
  int imageCount = 0;
  boolean hasAudio = false;
  ArrayList<String> inputNames = new ArrayList<String>();
  
  int inputsStart = jsonHeader.indexOf("\"INPUTS\"");
  if (inputsStart < 0) {
    return new ShaderInputs(floatCount, point2DCount, colorCount, boolCount, 
                            imageCount, hasAudio, new String[0]);
  }
  
  int arrayStart = jsonHeader.indexOf("[", inputsStart);
  if (arrayStart < 0) {
    return new ShaderInputs(floatCount, point2DCount, colorCount, boolCount, 
                            imageCount, hasAudio, new String[0]);
  }
  
  // Find matching closing bracket
  int depth = 1;
  int pos = arrayStart + 1;
  while (pos < jsonHeader.length() && depth > 0) {
    char c = jsonHeader.charAt(pos);
    if (c == '[' || c == '{') depth++;
    else if (c == ']' || c == '}') depth--;
    pos++;
  }
  
  String inputsArray = jsonHeader.substring(arrayStart, pos);
  
  // Count each input type
  int objStart = 0;
  while ((objStart = inputsArray.indexOf("{", objStart)) >= 0) {
    int objEnd = inputsArray.indexOf("}", objStart);
    if (objEnd < 0) break;
    
    String inputObj = inputsArray.substring(objStart, objEnd + 1);
    String name = extractJsonField(inputObj, "NAME");
    String type = extractJsonField(inputObj, "TYPE");
    
    if (name != null) inputNames.add(name);
    
    if (type != null) {
      type = type.toLowerCase();
      if (type.equals("float") || type.equals("long")) {
        floatCount++;
      } else if (type.equals("point2d")) {
        point2DCount++;
      } else if (type.equals("color")) {
        colorCount++;
      } else if (type.equals("bool") || type.equals("event")) {
        boolCount++;
      } else if (type.equals("image")) {
        imageCount++;
      } else if (type.equals("audio") || type.equals("audiofft")) {
        hasAudio = true;
      }
    }
    
    objStart = objEnd + 1;
  }
  
  return new ShaderInputs(floatCount, point2DCount, colorCount, boolCount,
                          imageCount, hasAudio, inputNames.toArray(new String[0]));
}

void storeIsfDefault(String name, String isfType, String defaultVal) {
  // Parse and store default values based on type
  // Defaults are stored as float arrays for easy uniform setting
  
  if (defaultVal == null || defaultVal.isEmpty()) {
    // Use sensible defaults if none specified
    if (isfType.equals("float")) {
      isfUniformDefaults.put(name, new float[]{1.0});  // Default to 1 so multipliers work
    } else if (isfType.equals("bool")) {
      isfUniformDefaults.put(name, new float[]{0.0});
    } else if (isfType.equals("point2D")) {
      isfUniformDefaults.put(name, new float[]{0.0, 0.0});
    } else if (isfType.equals("color")) {
      isfUniformDefaults.put(name, new float[]{1.0, 1.0, 1.0, 1.0});
    }
    return;
  }
  
  try {
    if (isfType.equals("float") || isfType.equals("long")) {
      float val = Float.parseFloat(defaultVal.trim());
      isfUniformDefaults.put(name, new float[]{val});
      println("  ISF default: " + name + " = " + val);
    } 
    else if (isfType.equals("bool")) {
      float val = defaultVal.trim().equals("true") || defaultVal.trim().equals("1") ? 1.0 : 0.0;
      isfUniformDefaults.put(name, new float[]{val});
      println("  ISF default: " + name + " = " + val);
    }
    else if (isfType.equals("point2D")) {
      // Format: [x, y] - may contain newlines
      String cleaned = defaultVal.replace("[", "").replace("]", "")
                                 .replace("\n", "").replace("\r", "").replace("\t", " ").trim();
      String[] parts = cleaned.split(",");
      if (parts.length >= 2) {
        float x = Float.parseFloat(parts[0].trim());
        float y = Float.parseFloat(parts[1].trim());
        isfUniformDefaults.put(name, new float[]{x, y});
        println("  ISF default: " + name + " = [" + x + ", " + y + "]");
      } else {
        println("  Warning: point2D parse failed for " + name + ": '" + cleaned + "'");
      }
    }
    else if (isfType.equals("point3D")) {
      // Format: [x, y, z] - may contain newlines
      String cleaned = defaultVal.replace("[", "").replace("]", "")
                                 .replace("\n", "").replace("\r", "").replace("\t", " ").trim();
      String[] parts = cleaned.split(",");
      if (parts.length >= 3) {
        float x = Float.parseFloat(parts[0].trim());
        float y = Float.parseFloat(parts[1].trim());
        float z = Float.parseFloat(parts[2].trim());
        isfUniformDefaults.put(name, new float[]{x, y, z});
        println("  ISF default: " + name + " = [" + x + ", " + y + ", " + z + "]");
      } else {
        println("  Warning: point3D parse failed for " + name + ": '" + cleaned + "'");
      }
    }
    else if (isfType.equals("color")) {
      // Format: [r, g, b, a] - may contain newlines
      String cleaned = defaultVal.replace("[", "").replace("]", "")
                                 .replace("\n", "").replace("\r", "").replace("\t", " ").trim();
      String[] parts = cleaned.split(",");
      if (parts.length >= 4) {
        float r = Float.parseFloat(parts[0].trim());
        float g = Float.parseFloat(parts[1].trim());
        float b = Float.parseFloat(parts[2].trim());
        float a = Float.parseFloat(parts[3].trim());
        isfUniformDefaults.put(name, new float[]{r, g, b, a});
        println("  ISF default: " + name + " = [" + r + ", " + g + ", " + b + ", " + a + "]");
      } else {
        println("  Warning: color parse failed for " + name + ": '" + cleaned + "'");
      }
    }
  } catch (Exception e) {
    println("  Warning: could not parse default for " + name + ": " + defaultVal);
  }
}

String extractJsonField(String json, String field) {
  // Look for "FIELD" : "value" or "FIELD" : value or "FIELD": [value, value]
  String pattern1 = "\"" + field + "\"";
  int fieldPos = json.indexOf(pattern1);
  if (fieldPos < 0) return null;
  
  int colonPos = json.indexOf(":", fieldPos);
  if (colonPos < 0) return null;
  
  // Skip whitespace
  int valueStart = colonPos + 1;
  while (valueStart < json.length() && Character.isWhitespace(json.charAt(valueStart))) {
    valueStart++;
  }
  
  if (valueStart >= json.length()) return null;
  
  char firstChar = json.charAt(valueStart);
  
  // String value
  if (firstChar == '"') {
    int valueEnd = json.indexOf("\"", valueStart + 1);
    if (valueEnd < 0) return null;
    return json.substring(valueStart + 1, valueEnd);
  }
  
  // Array value [x, y]
  if (firstChar == '[') {
    int valueEnd = json.indexOf("]", valueStart);
    if (valueEnd < 0) return null;
    return json.substring(valueStart, valueEnd + 1);
  }
  
  // Number or other value - read until comma, }, or whitespace
  int valueEnd = valueStart;
  while (valueEnd < json.length()) {
    char c = json.charAt(valueEnd);
    if (c == ',' || c == '}' || c == ']' || Character.isWhitespace(c)) break;
    valueEnd++;
  }
  return json.substring(valueStart, valueEnd);
}

String isfTypeToGlsl(String isfType) {
  // Map ISF types to GLSL types
  if (isfType.equals("float")) return "float";
  if (isfType.equals("bool")) return "bool";
  if (isfType.equals("long")) return "int";
  if (isfType.equals("point2D")) return "vec2";
  if (isfType.equals("point3D")) return "vec3";
  if (isfType.equals("color")) return "vec4";
  if (isfType.equals("image")) return "sampler2D";
  return "float";  // Default fallback
}

// ============================================
// SHADER LOOKUP
// ============================================

PShader getShaderByName(String name) {
  for (int i = 0; i < availableShaders.size(); i++) {
    if (availableShaders.get(i).name.equals(name)) {
      ShaderInfo info = availableShaders.get(i);
      try {
        if (info.type == ShaderType.ISF) {
          return loadIsfShader(info.path);
        } else {
          return loadGlslShader(info.path);
        }
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
