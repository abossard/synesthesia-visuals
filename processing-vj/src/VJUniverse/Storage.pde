/**
 * Storage for VJUniverse
 * Caches shader selections per song to disk
 */

import java.nio.file.*;

// ============================================
// CACHE OPERATIONS
// ============================================

ShaderSelection loadCachedSelection(String songId) {
  String filename = sanitizeFilename(songId) + ".json";
  String filepath = dataPath(SCENES_PATH + "/" + filename);
  
  File f = new File(filepath);
  if (!f.exists()) {
    return null;
  }
  
  try {
    String[] lines = loadStrings(filepath);
    if (lines == null || lines.length == 0) return null;
    
    String json = String.join("\n", lines);
    return parseSelectionJson(json);
    
  } catch (Exception e) {
    println("Error loading cached selection: " + e.getMessage());
    return null;
  }
}

void saveCachedSelection(ShaderSelection selection) {
  // Ensure scenes directory exists
  File scenesDir = new File(dataPath(SCENES_PATH));
  if (!scenesDir.exists()) {
    scenesDir.mkdirs();
  }
  
  String filename = sanitizeFilename(selection.songId) + ".json";
  String filepath = dataPath(SCENES_PATH + "/" + filename);
  
  String json = selectionToJson(selection);
  saveStrings(filepath, new String[]{json});
  
  println("Saved selection to: " + filename);
}

// ============================================
// JSON SERIALIZATION (Pure Calculations)
// ============================================

String selectionToJson(ShaderSelection sel) {
  StringBuilder sb = new StringBuilder();
  sb.append("{\n");
  sb.append("  \"songId\": \"").append(escapeJson(sel.songId)).append("\",\n");
  sb.append("  \"mood\": \"").append(escapeJson(sel.mood)).append("\",\n");
  sb.append("  \"shaderIds\": [");
  
  for (int i = 0; i < sel.shaderIds.length; i++) {
    if (i > 0) sb.append(", ");
    sb.append("\"").append(escapeJson(sel.shaderIds[i])).append("\"");
  }
  
  sb.append("],\n");
  sb.append("  \"createdAt\": ").append(sel.createdAt).append("\n");
  sb.append("}");
  
  return sb.toString();
}

ShaderSelection parseSelectionJson(String json) {
  String songId = extractJsonString(json, "songId");
  String mood = extractJsonString(json, "mood");
  String[] shaderIds = extractJsonArray(json, "shaderIds");
  
  // Extract createdAt (number)
  long createdAt = System.currentTimeMillis();
  int caPos = json.indexOf("\"createdAt\"");
  if (caPos >= 0) {
    int colonPos = json.indexOf(":", caPos);
    if (colonPos >= 0) {
      int start = colonPos + 1;
      while (start < json.length() && !Character.isDigit(json.charAt(start))) {
        start++;
      }
      int end = start;
      while (end < json.length() && Character.isDigit(json.charAt(end))) {
        end++;
      }
      if (end > start) {
        try {
          createdAt = Long.parseLong(json.substring(start, end));
        } catch (NumberFormatException e) {}
      }
    }
  }
  
  if (songId == null || shaderIds == null) {
    return null;
  }
  
  return new ShaderSelection(songId, shaderIds, mood != null ? mood : "", createdAt);
}

String escapeJson(String s) {
  if (s == null) return "";
  return s
    .replace("\\", "\\\\")
    .replace("\"", "\\\"")
    .replace("\n", "\\n")
    .replace("\r", "\\r")
    .replace("\t", "\\t");
}

// ============================================
// JSON PARSING HELPERS
// ============================================

String extractJsonString(String json, String key) {
  int keyPos = json.indexOf("\"" + key + "\"");
  if (keyPos < 0) return null;
  
  int colonPos = json.indexOf(":", keyPos);
  if (colonPos < 0) return null;
  
  int quoteStart = json.indexOf("\"", colonPos);
  if (quoteStart < 0) return null;
  
  int quoteEnd = json.indexOf("\"", quoteStart + 1);
  if (quoteEnd < 0) return null;
  
  return json.substring(quoteStart + 1, quoteEnd);
}

String[] extractJsonArray(String json, String key) {
  int keyPos = json.indexOf("\"" + key + "\"");
  if (keyPos < 0) return null;
  
  int bracketStart = json.indexOf("[", keyPos);
  if (bracketStart < 0) return null;
  
  int bracketEnd = json.indexOf("]", bracketStart);
  if (bracketEnd < 0) return null;
  
  String arrayContent = json.substring(bracketStart + 1, bracketEnd);
  
  // Extract quoted strings
  ArrayList<String> items = new ArrayList<String>();
  int pos = 0;
  while (pos < arrayContent.length()) {
    int start = arrayContent.indexOf("\"", pos);
    if (start < 0) break;
    int end = arrayContent.indexOf("\"", start + 1);
    if (end < 0) break;
    items.add(arrayContent.substring(start + 1, end));
    pos = end + 1;
  }
  
  return items.toArray(new String[0]);
}

// ============================================
// FILE UTILITIES
// ============================================

boolean cachedSelectionExists(String songId) {
  String filename = sanitizeFilename(songId) + ".json";
  String filepath = dataPath(SCENES_PATH + "/" + filename);
  return new File(filepath).exists();
}

void deleteCachedSelection(String songId) {
  String filename = sanitizeFilename(songId) + ".json";
  String filepath = dataPath(SCENES_PATH + "/" + filename);
  File f = new File(filepath);
  if (f.exists()) {
    f.delete();
    println("Deleted cached selection: " + filename);
  }
}

String[] listCachedSelections() {
  File scenesDir = new File(dataPath(SCENES_PATH));
  if (!scenesDir.exists()) {
    return new String[0];
  }
  
  File[] files = scenesDir.listFiles();
  if (files == null) {
    return new String[0];
  }
  
  ArrayList<String> ids = new ArrayList<String>();
  for (File f : files) {
    if (f.getName().endsWith(".json")) {
      ids.add(f.getName().replace(".json", ""));
    }
  }
  
  return ids.toArray(new String[0]);
}

// ============================================
// SHADER ANALYSIS STORAGE
// ============================================

ShaderAnalysis loadShaderAnalysis(String shaderPath) {
  // Analysis JSON is stored alongside the shader file
  String analysisPath = shaderPath.replaceAll("\\.(fs|frag|isf|glsl)$", ".analysis.json");
  String filepath = dataPath(analysisPath);
  
  File f = new File(filepath);
  if (!f.exists()) return null;
  
  try {
    String[] lines = loadStrings(filepath);
    if (lines == null || lines.length == 0) return null;
    
    String json = String.join("\n", lines);
    return parseAnalysisJson(json);
    
  } catch (Exception e) {
    println("Error loading shader analysis: " + e.getMessage());
    return null;
  }
}

void saveShaderAnalysis(String shaderPath, ShaderAnalysis analysis) {
  String analysisPath = shaderPath.replaceAll("\\.(fs|frag|isf|glsl)$", ".analysis.json");
  String filepath = dataPath(analysisPath);
  
  String json = analysisToJson(analysis);
  saveStrings(filepath, new String[]{json});
  
  println("Saved shader analysis: " + analysisPath);
}

/**
 * Save just the rating for a shader to its .analysis.json file.
 * Re-serializes the entire analysis with updated rating.
 */
void saveShaderRating(String shaderName, int newRating) {
  ShaderAnalysis analysis = shaderAnalyses.get(shaderName);
  if (analysis == null) {
    println("[Rating] No analysis found for: " + shaderName);
    return;
  }
  
  // Update rating in memory
  analysis.rating = constrain(newRating, 1, 5);
  
  // Find shader path to derive analysis file path
  String shaderPath = null;
  for (ShaderInfo info : availableShaders) {
    if (info.name.equals(shaderName)) {
      shaderPath = info.path;
      break;
    }
  }
  
  if (shaderPath == null) {
    println("[Rating] Could not find shader path for: " + shaderName);
    return;
  }
  
  // Save updated analysis
  saveShaderAnalysis(shaderPath, analysis);
  println("[Rating] " + shaderName + " -> " + analysis.getRatingLabel());
}

boolean shaderAnalysisExists(String shaderPath) {
  String analysisPath = shaderPath.replaceAll("\\.(fs|frag|isf|glsl)$", ".analysis.json");
  String filepath = dataPath(analysisPath);
  return new File(filepath).exists();
}

String analysisToJson(ShaderAnalysis a) {
  StringBuilder sb = new StringBuilder();
  sb.append("{\n");
  sb.append("  \"shaderName\": \"").append(escapeJson(a.shaderName)).append("\",\n");
  sb.append("  \"mood\": \"").append(escapeJson(a.mood)).append("\",\n");
  sb.append("  \"energy\": \"").append(escapeJson(a.energy)).append("\",\n");
  sb.append("  \"complexity\": \"").append(escapeJson(a.complexity)).append("\",\n");
  sb.append("  \"description\": \"").append(escapeJson(a.description)).append("\",\n");
  
  sb.append("  \"colors\": ").append(arrayToJson(a.colors)).append(",\n");
  sb.append("  \"geometry\": ").append(arrayToJson(a.geometry)).append(",\n");
  sb.append("  \"objects\": ").append(arrayToJson(a.objects)).append(",\n");
  sb.append("  \"effects\": ").append(arrayToJson(a.effects)).append(",\n");
  
  // Serialize features HashMap
  sb.append("  \"features\": {\n");
  if (a.features != null && a.features.size() > 0) {
    int count = 0;
    for (String key : a.features.keySet()) {
      if (count > 0) sb.append(",\n");
      sb.append("    \"").append(escapeJson(key)).append("\": ").append(a.features.get(key));
      count++;
    }
    sb.append("\n");
  }
  sb.append("  },\n");
  
  // Serialize input capabilities
  sb.append("  \"inputs\": {\n");
  sb.append("    \"floatCount\": ").append(a.inputs.floatCount).append(",\n");
  sb.append("    \"point2DCount\": ").append(a.inputs.point2DCount).append(",\n");
  sb.append("    \"colorCount\": ").append(a.inputs.colorCount).append(",\n");
  sb.append("    \"boolCount\": ").append(a.inputs.boolCount).append(",\n");
  sb.append("    \"imageCount\": ").append(a.inputs.imageCount).append(",\n");
  sb.append("    \"hasAudio\": ").append(a.inputs.hasAudio).append(",\n");
  sb.append("    \"inputNames\": ").append(arrayToJson(a.inputs.inputNames)).append("\n");
  sb.append("  },\n");
  
  sb.append("  \"rating\": ").append(a.rating).append(",\n");
  sb.append("  \"analyzedAt\": ").append(a.analyzedAt).append("\n");
  sb.append("}");
  
  return sb.toString();
}

String arrayToJson(String[] arr) {
  StringBuilder sb = new StringBuilder();
  sb.append("[");
  for (int i = 0; i < arr.length; i++) {
    if (i > 0) sb.append(", ");
    sb.append("\"").append(escapeJson(arr[i])).append("\"");
  }
  sb.append("]");
  return sb.toString();
}

ShaderAnalysis parseAnalysisJson(String json) {
  String shaderName = extractJsonString(json, "shaderName");
  String mood = extractJsonString(json, "mood");
  String energy = extractJsonString(json, "energy");
  String complexity = extractJsonString(json, "complexity");
  String description = extractJsonString(json, "description");
  String[] colors = extractJsonArray(json, "colors");
  String[] geometry = extractJsonArray(json, "geometry");
  String[] objects = extractJsonArray(json, "objects");
  String[] effects = extractJsonArray(json, "effects");
  
  // Extract features object
  HashMap<String, Float> features = extractFeaturesObject(json);
  
  // Extract inputs object
  ShaderInputs inputs = extractInputsObject(json);
  
  // Extract analyzedAt (number)
  long analyzedAt = System.currentTimeMillis();
  int aaPos = json.indexOf("\"analyzedAt\"");
  if (aaPos >= 0) {
    int colonPos = json.indexOf(":", aaPos);
    if (colonPos >= 0) {
      int start = colonPos + 1;
      while (start < json.length() && !Character.isDigit(json.charAt(start))) {
        start++;
      }
      int end = start;
      while (end < json.length() && Character.isDigit(json.charAt(end))) {
        end++;
      }
      if (end > start) {
        try {
          analyzedAt = Long.parseLong(json.substring(start, end));
        } catch (NumberFormatException e) {}
      }
    }
  }
  
  if (shaderName == null) return null;
  
  // Provide defaults for missing arrays
  if (colors == null) colors = new String[0];
  if (geometry == null) geometry = new String[0];
  if (objects == null) objects = new String[0];
  if (effects == null) effects = new String[0];
  
  // Extract rating (0 = unrated, treated as 3)
  int rating = extractIntField(json, "rating", 0);
  
  return new ShaderAnalysis(
    shaderName,
    mood != null ? mood : "unknown",
    colors, geometry, objects, effects,
    energy != null ? energy : "medium",
    complexity != null ? complexity : "medium",
    description != null ? description : "",
    analyzedAt,
    features,
    inputs,
    rating
  );
}

// Extract inputs object from analysis JSON
ShaderInputs extractInputsObject(String json) {
  int inputsPos = json.indexOf("\"inputs\"");
  if (inputsPos < 0) return new ShaderInputs();
  
  int braceStart = json.indexOf("{", inputsPos);
  if (braceStart < 0) return new ShaderInputs();
  
  // Find matching closing brace
  int depth = 1;
  int braceEnd = braceStart + 1;
  while (braceEnd < json.length() && depth > 0) {
    char c = json.charAt(braceEnd);
    if (c == '{') depth++;
    else if (c == '}') depth--;
    braceEnd++;
  }
  
  if (depth != 0) return new ShaderInputs();
  
  String inputsJson = json.substring(braceStart, braceEnd);
  
  int floatCount = extractIntField(inputsJson, "floatCount", 0);
  int point2DCount = extractIntField(inputsJson, "point2DCount", 0);
  int colorCount = extractIntField(inputsJson, "colorCount", 0);
  int boolCount = extractIntField(inputsJson, "boolCount", 0);
  int imageCount = extractIntField(inputsJson, "imageCount", 0);
  boolean hasAudio = extractBoolField(inputsJson, "hasAudio", false);
  String[] inputNames = extractJsonArray(inputsJson, "inputNames");
  
  if (inputNames == null) inputNames = new String[0];
  
  return new ShaderInputs(floatCount, point2DCount, colorCount, boolCount,
                          imageCount, hasAudio, inputNames);
}

int extractIntField(String json, String key, int defaultVal) {
  int keyPos = json.indexOf("\"" + key + "\"");
  if (keyPos < 0) return defaultVal;
  
  int colonPos = json.indexOf(":", keyPos);
  if (colonPos < 0) return defaultVal;
  
  int start = colonPos + 1;
  while (start < json.length() && !Character.isDigit(json.charAt(start)) && json.charAt(start) != '-') {
    start++;
  }
  int end = start;
  if (end < json.length() && json.charAt(end) == '-') end++;
  while (end < json.length() && Character.isDigit(json.charAt(end))) {
    end++;
  }
  
  if (end > start) {
    try {
      return Integer.parseInt(json.substring(start, end));
    } catch (NumberFormatException e) {}
  }
  return defaultVal;
}

boolean extractBoolField(String json, String key, boolean defaultVal) {
  int keyPos = json.indexOf("\"" + key + "\"");
  if (keyPos < 0) return defaultVal;
  
  int colonPos = json.indexOf(":", keyPos);
  if (colonPos < 0) return defaultVal;
  
  String rest = json.substring(colonPos + 1, min(colonPos + 20, json.length())).trim();
  if (rest.startsWith("true")) return true;
  if (rest.startsWith("false")) return false;
  return defaultVal;
}

// Extract features object { "key": value, ... }
HashMap<String, Float> extractFeaturesObject(String json) {
  HashMap<String, Float> features = new HashMap<String, Float>();
  
  int featPos = json.indexOf("\"features\"");
  if (featPos < 0) return features;
  
  int braceStart = json.indexOf("{", featPos);
  if (braceStart < 0) return features;
  
  // Find matching closing brace
  int depth = 1;
  int braceEnd = braceStart + 1;
  while (braceEnd < json.length() && depth > 0) {
    char c = json.charAt(braceEnd);
    if (c == '{') depth++;
    else if (c == '}') depth--;
    braceEnd++;
  }
  
  if (depth != 0) return features;
  
  String featuresJson = json.substring(braceStart + 1, braceEnd - 1);
  
  // Parse key: value pairs
  String[] featureKeys = {"energy_score", "mood_valence", "color_warmth", 
                          "motion_speed", "geometric_score", "visual_density"};
  
  for (String key : featureKeys) {
    int keyPos = featuresJson.indexOf("\"" + key + "\"");
    if (keyPos >= 0) {
      int colonPos = featuresJson.indexOf(":", keyPos);
      if (colonPos >= 0) {
        // Find the number value
        int start = colonPos + 1;
        while (start < featuresJson.length() && 
               (featuresJson.charAt(start) == ' ' || featuresJson.charAt(start) == '\n')) {
          start++;
        }
        
        int end = start;
        // Handle negative sign for mood_valence
        if (end < featuresJson.length() && featuresJson.charAt(end) == '-') {
          end++;
        }
        while (end < featuresJson.length() && 
               (Character.isDigit(featuresJson.charAt(end)) || featuresJson.charAt(end) == '.')) {
          end++;
        }
        
        if (end > start) {
          try {
            float value = Float.parseFloat(featuresJson.substring(start, end));
            features.put(key, value);
          } catch (NumberFormatException e) {}
        }
      }
    }
  }
  
  return features;
}

// ============================================
// SHADER FILE MOVEMENT (Rate Mode)
// ============================================

/**
 * Move shader file based on rating (when rate mode is active).
 * Creates target folders if they don't exist.
 *
 * Rating destinations:
 *   1-2: Keep in glsl/ (no move)
 *   3:   Move to neutral/
 *   4:   Move to masks/
 *   5:   Move to trash/
 *
 * @param shaderName Name of the shader to move
 * @param rating     New rating (1-5)
 * @return true if file was moved, false if kept in place or error
 */
boolean moveShaderByRating(String shaderName, int rating) {
  // Rating 1-2: Keep in place (BEST/GOOD shaders stay)
  if (rating <= 2) {
    println("[RateMode] Keeping " + shaderName + " in glsl/ (rating " + rating + ")");
    return false;
  }

  // Find shader info to get file path
  ShaderInfo shaderInfo = null;
  for (ShaderInfo info : glslShaders) {
    if (info.name.equals(shaderName)) {
      shaderInfo = info;
      break;
    }
  }

  if (shaderInfo == null) {
    println("[RateMode] Shader not found: " + shaderName);
    return false;
  }

  // Get source file path
  String sourcePath = dataPath(shaderInfo.path);
  File sourceFile = new File(sourcePath);

  if (!sourceFile.exists()) {
    println("[RateMode] Source file not found: " + sourcePath);
    return false;
  }

  // Determine destination folder based on rating
  String destFolderName;
  switch (rating) {
    case 3:
      destFolderName = "neutral";
      break;
    case 4:
      destFolderName = "masks";
      break;
    case 5:
      destFolderName = "trash";
      break;
    default:
      return false;
  }

  // Create destination directory if needed
  File destDir = new File(dataPath(SHADERS_PATH + "/" + destFolderName));
  if (!destDir.exists()) {
    if (destDir.mkdirs()) {
      println("[RateMode] Created folder: " + destFolderName + "/");
    } else {
      println("[RateMode] Failed to create folder: " + destFolderName + "/");
      return false;
    }
  }

  // Move shader file
  File destFile = new File(destDir, sourceFile.getName());
  try {
    Files.move(sourceFile.toPath(), destFile.toPath(), StandardCopyOption.REPLACE_EXISTING);
    println("[RateMode] Moved " + shaderName + " -> " + destFolderName + "/");

    // Also move .analysis.json if it exists
    String analysisName = sourceFile.getName().replaceAll("\\.(frag|txt|glsl)$", ".analysis.json");
    File analysisSource = new File(sourceFile.getParent(), analysisName);
    if (analysisSource.exists()) {
      File analysisDest = new File(destDir, analysisName);
      Files.move(analysisSource.toPath(), analysisDest.toPath(), StandardCopyOption.REPLACE_EXISTING);
      println("[RateMode] Moved analysis file -> " + destFolderName + "/");
    }

    return true;
  } catch (Exception e) {
    println("[RateMode] Error moving file: " + e.getMessage());
    return false;
  }
}
