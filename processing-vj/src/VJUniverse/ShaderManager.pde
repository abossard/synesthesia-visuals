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

// Shader analyses cache (indexed by shader name)
HashMap<String, ShaderAnalysis> shaderAnalyses = new HashMap<String, ShaderAnalysis>();

// Shader analysis queue for background processing
ArrayList<ShaderInfo> shadersToAnalyze = new ArrayList<ShaderInfo>();
boolean analysisInProgress = false;
String currentAnalyzingShader = "";  // Name of shader currently being analyzed

// ============================================
// SHADER LOADING
// ============================================

void loadAllShaders() {
  availableShaders.clear();
  shaderAnalyses.clear();
  
  // Load GLSL shaders
  loadGlslShaders();
  
  // Load ISF shaders
  loadIsfShaders();
  
  // Update directory timestamps
  File glslDir = new File(dataPath(SHADERS_PATH + "/glsl"));
  File isfDir = new File(dataPath(SHADERS_PATH + "/isf"));
  if (glslDir.exists()) lastGlslDirModified = glslDir.lastModified();
  if (isfDir.exists()) lastIsfDirModified = isfDir.lastModified();
  
  println("Loaded " + availableShaders.size() + " shaders total");
  
  // Load existing analyses and queue missing ones
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
      if (f.lastModified() > newest) {
        newest = f.lastModified();
      }
    }
  }
  return newest;
}

void loadGlslShaders() {
  File glslDir = new File(dataPath(SHADERS_PATH + "/glsl"));
  if (!glslDir.exists()) {
    println("GLSL shader directory not found: " + glslDir.getPath());
    return;
  }
  
  File[] files = glslDir.listFiles();
  if (files == null) return;
  
  for (File f : files) {
    if (f.getName().endsWith(".frag")) {
      String name = f.getName().replace(".frag", "");
      String path = SHADERS_PATH + "/glsl/" + f.getName();
      availableShaders.add(new ShaderInfo(name, path, ShaderType.GLSL));
      println("  Found GLSL: " + name);
    }
  }
}

void loadIsfShaders() {
  File isfDir = new File(dataPath(SHADERS_PATH + "/isf"));
  if (!isfDir.exists()) {
    println("ISF shader directory not found: " + isfDir.getPath());
    return;
  }
  
  File[] files = isfDir.listFiles();
  if (files == null) return;
  
  for (File f : files) {
    if (f.getName().endsWith(".fs") || f.getName().endsWith(".isf")) {
      String name = f.getName().replace(".fs", "").replace(".isf", "");
      String path = SHADERS_PATH + "/isf/" + f.getName();
      availableShaders.add(new ShaderInfo(name, path, ShaderType.ISF));
      println("  Found ISF: " + name);
    }
  }
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
    if (info.type == ShaderType.ISF) {
      activeShader = loadIsfShader(info.path);
    } else {
      activeShader = loadShader(info.path);
    }
    println("Loaded shader: " + info.name);
  } catch (Exception e) {
    println("Error loading shader " + info.name + ": " + e.getMessage());
    activeShader = null;
  }
}

void loadShaderByName(String name) {
  for (int i = 0; i < availableShaders.size(); i++) {
    if (availableShaders.get(i).name.equals(name)) {
      loadShaderByIndex(i);
      return;
    }
  }
  println("Shader not found: " + name);
}

// ============================================
// ISF SHADER CONVERSION
// ============================================

PShader loadIsfShader(String path) {
  String[] lines = loadStrings(path);
  if (lines == null) {
    println("Could not load ISF file: " + path);
    return null;
  }
  
  // Clear previous ISF defaults before loading new shader
  isfUniformDefaults.clear();
  
  String isfSource = String.join("\n", lines);
  String convertedGlsl = convertIsfToGlsl(isfSource);
  
  // Save converted shader to temp file and load
  String tempPath = "temp_isf_converted.frag";
  saveStrings(dataPath(tempPath), new String[]{convertedGlsl});
  
  return loadShader(tempPath);
}

String convertIsfToGlsl(String isfSource) {
  // Remove ISF JSON header if present and extract inputs
  String glslBody = isfSource;
  String jsonHeader = "";
  int headerEnd = isfSource.indexOf("*/");
  if (isfSource.startsWith("/*{") && headerEnd > 0) {
    jsonHeader = isfSource.substring(2, headerEnd).trim();  // Remove /* and */
    glslBody = isfSource.substring(headerEnd + 2).trim();
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
  sb.append("uniform float bass;\n");
  sb.append("uniform float mid;\n");
  sb.append("uniform float treble;\n");
  sb.append("uniform float level;\n");
  sb.append("uniform float beat;\n\n");
  
  // Parse ISF INPUTS and add as uniforms
  if (!jsonHeader.isEmpty()) {
    ArrayList<String> inputUniforms = parseIsfInputs(jsonHeader);
    for (String uniform : inputUniforms) {
      sb.append(uniform).append("\n");
    }
    if (inputUniforms.size() > 0) {
      sb.append("\n");
    }
  }
  
  // ISF compatibility defines
  // gl_FragCoord is used directly - no Y flip needed, handled by texture coordinates
  sb.append("#define TIME time\n");
  sb.append("#define RENDERSIZE resolution\n");
  sb.append("#define isf_FragNormCoord (gl_FragCoord.xy / resolution)\n");
  sb.append("#define FRAMEINDEX int(time * 60.0)\n\n");
  
  // No gl_FragCoord replacement needed - shaders use it directly
  
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
      storeIsfDefault(name, type, defaultVal);
    }
    
    objStart = objEnd + 1;
  }
  
  return uniforms;
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
      // Format: [x, y]
      String cleaned = defaultVal.replace("[", "").replace("]", "").trim();
      String[] parts = cleaned.split(",");
      if (parts.length >= 2) {
        float x = Float.parseFloat(parts[0].trim());
        float y = Float.parseFloat(parts[1].trim());
        isfUniformDefaults.put(name, new float[]{x, y});
        println("  ISF default: " + name + " = [" + x + ", " + y + "]");
      }
    }
    else if (isfType.equals("point3D")) {
      // Format: [x, y, z]
      String cleaned = defaultVal.replace("[", "").replace("]", "").trim();
      String[] parts = cleaned.split(",");
      if (parts.length >= 3) {
        float x = Float.parseFloat(parts[0].trim());
        float y = Float.parseFloat(parts[1].trim());
        float z = Float.parseFloat(parts[2].trim());
        isfUniformDefaults.put(name, new float[]{x, y, z});
        println("  ISF default: " + name + " = [" + x + ", " + y + ", " + z + "]");
      }
    }
    else if (isfType.equals("color")) {
      // Format: [r, g, b, a]
      String cleaned = defaultVal.replace("[", "").replace("]", "").trim();
      String[] parts = cleaned.split(",");
      if (parts.length >= 4) {
        float r = Float.parseFloat(parts[0].trim());
        float g = Float.parseFloat(parts[1].trim());
        float b = Float.parseFloat(parts[2].trim());
        float a = Float.parseFloat(parts[3].trim());
        isfUniformDefaults.put(name, new float[]{r, g, b, a});
        println("  ISF default: " + name + " = [" + r + ", " + g + ", " + b + ", " + a + "]");
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
// SELECTION HELPERS
// ============================================

void applySelection() {
  if (currentSelection == null || currentSelection.shaderIds.length == 0) return;
  
  // Build shader pipeline from selection
  activeShaderPipeline.clear();
  
  for (String shaderId : currentSelection.shaderIds) {
    PShader s = getShaderByName(shaderId);
    if (s != null) {
      activeShaderPipeline.add(s);
    }
  }
  
  // Set first shader as active (for single-pass fallback)
  if (activeShaderPipeline.size() > 0) {
    activeShader = activeShaderPipeline.get(0);
    // Update currentShaderIndex to match
    for (int i = 0; i < availableShaders.size(); i++) {
      if (availableShaders.get(i).name.equals(currentSelection.shaderIds[0])) {
        currentShaderIndex = i;
        break;
      }
    }
  }
  
  println("Applied selection with " + activeShaderPipeline.size() + " shaders in pipeline");
}

PShader getShaderByName(String name) {
  for (int i = 0; i < availableShaders.size(); i++) {
    if (availableShaders.get(i).name.equals(name)) {
      ShaderInfo info = availableShaders.get(i);
      try {
        if (info.type == ShaderType.ISF) {
          return loadIsfShader(info.path);
        } else {
          return loadShader(info.path);
        }
      } catch (Exception e) {
        println("Error loading shader " + name + ": " + e.getMessage());
        return null;
      }
    }
  }
  println("Shader not found: " + name);
  return null;
}

void selectRandomShaders() {
  if (availableShaders.size() == 0) return;
  
  int numToSelect = min(3, availableShaders.size());
  String[] selected = new String[numToSelect];
  
  ArrayList<Integer> indices = new ArrayList<Integer>();
  for (int i = 0; i < availableShaders.size(); i++) {
    indices.add(i);
  }
  java.util.Collections.shuffle(indices);
  
  for (int i = 0; i < numToSelect; i++) {
    selected[i] = availableShaders.get(indices.get(i)).name;
  }
  
  currentSelection = new ShaderSelection(
    currentSong.getId(),
    selected,
    "random"
  );
  
  applySelection();
  saveCachedSelection(currentSelection);
}

// ============================================
// SHADER ANALYSIS MANAGEMENT
// ============================================

void loadShaderAnalyses() {
  shadersToAnalyze.clear();
  
  // For each shader, try to load existing analysis or queue for LLM analysis
  for (ShaderInfo shader : availableShaders) {
    ShaderAnalysis existing = loadShaderAnalysis(shader.path);
    
    if (existing != null) {
      shaderAnalyses.put(shader.name, existing);
      println("  Loaded analysis for: " + shader.name + " [" + existing.mood + "]");
    } else {
      // Queue for analysis
      shadersToAnalyze.add(shader);
      println("  Queued for analysis: " + shader.name);
    }
  }
  
  // Start background analysis if there are shaders to analyze
  if (shadersToAnalyze.size() > 0 && llmAvailable) {
    println("Starting background shader analysis for " + shadersToAnalyze.size() + " shaders...");
    thread("analyzeNextShader");
  } else if (shadersToAnalyze.size() > 0) {
    println("LLM not available - " + shadersToAnalyze.size() + " shaders need analysis");
  }
}

// Called in a background thread
void analyzeNextShader() {
  // Check if we should stop
  if (shadersToAnalyze.size() == 0 || !llmAvailable) {
    analysisInProgress = false;
    currentAnalyzingShader = "";
    println("Shader analysis complete!");
    return;
  }
  
  analysisInProgress = true;
  
  // Get next shader to analyze
  ShaderInfo shader = shadersToAnalyze.remove(0);
  currentAnalyzingShader = shader.name;  // Update for UI display
  int remaining = shadersToAnalyze.size();
  println("Analyzing shader: " + shader.name + " (" + remaining + " remaining after this)");
  
  // Analyze it
  ShaderAnalysis analysis = analyzeShader(shader.name, dataPath(shader.path));
  
  if (analysis != null) {
    // Save and cache
    shaderAnalyses.put(shader.name, analysis);
    saveShaderAnalysis(shader.path, analysis);
    println("  -> " + shader.name + ": " + analysis.mood + ", " + analysis.energy + " energy");
  } else {
    println("  -> Failed to analyze: " + shader.name);
  }
  
  // Check again if there are more shaders to analyze
  if (shadersToAnalyze.size() > 0 && llmAvailable) {
    // Small delay between analyses to not overload LLM
    delay(1000);
    // Continue with next shader in same thread (avoid thread explosion)
    analyzeNextShader();
  } else {
    // Done!
    analysisInProgress = false;
    currentAnalyzingShader = "";
    println("All shader analyses complete!");
  }
}

// Force re-analysis of all shaders (deletes existing JSON files)
void reanalyzeAllShaders() {
  // Delete existing analysis files
  for (ShaderInfo shader : availableShaders) {
    String analysisPath = shader.path.replaceAll("\\.(fs|frag|isf|glsl)$", ".analysis.json");
    File f = new File(dataPath(analysisPath));
    if (f.exists()) {
      f.delete();
    }
  }
  
  shaderAnalyses.clear();
  
  // Reload analyses (will queue all for LLM)
  loadShaderAnalyses();
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
