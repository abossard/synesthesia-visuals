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
  // e.g., shaders/isf/CandyWarp.fs -> shaders/isf/CandyWarp.analysis.json
  String analysisPath = shaderPath.replaceAll("\\.(fs|frag|isf|glsl)$", ".analysis.json");
  String filepath = dataPath(analysisPath);
  
  println("    [loadShaderAnalysis] Checking: " + filepath);
  
  File f = new File(filepath);
  if (!f.exists()) {
    println("    [loadShaderAnalysis] NOT FOUND");
    return null;
  }
  
  println("    [loadShaderAnalysis] FOUND - loading...");
  
  try {
    String[] lines = loadStrings(filepath);
    if (lines == null || lines.length == 0) {
      println("    [loadShaderAnalysis] File empty or null");
      return null;
    }
    
    String json = String.join("\n", lines);
    ShaderAnalysis result = parseAnalysisJson(json);
    if (result != null) {
      println("    [loadShaderAnalysis] Parsed OK: " + result.mood);
    }
    return result;
    
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
  
  return new ShaderAnalysis(
    shaderName,
    mood != null ? mood : "unknown",
    colors, geometry, objects, effects,
    energy != null ? energy : "medium",
    complexity != null ? complexity : "medium",
    description != null ? description : "",
    analyzedAt
  );
}
