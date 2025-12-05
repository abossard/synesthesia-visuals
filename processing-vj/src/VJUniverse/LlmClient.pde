/**
 * LLM Integration for VJUniverse
 * Communicates with LM Studio server (OpenAI-compatible API) for shader selection
 */

import java.net.*;
import java.io.*;

// ============================================
// LM STUDIO API (OpenAI-compatible)
// ============================================

// Timeout settings (in milliseconds)
int LLM_CONNECT_TIMEOUT = 30000;    // 30 seconds to connect
int LLM_READ_TIMEOUT = 600000;      // 10 minutes to wait for response (LLMs can be slow)
int LLM_MAX_RETRIES = 3;            // Number of retry attempts
int LLM_RETRY_DELAY = 5000;         // 5 seconds between retries

boolean checkLlmAvailable() {
  try {
    URL url = new URL(LLM_URL + "/v1/models");
    HttpURLConnection conn = (HttpURLConnection) url.openConnection();
    conn.setRequestMethod("GET");
    conn.setConnectTimeout(5000);
    conn.setReadTimeout(10000);
    
    int code = conn.getResponseCode();
    conn.disconnect();
    return code == 200;
  } catch (Exception e) {
    println("LM Studio not available: " + e.getMessage());
    return false;
  }
}

String callLlm(String prompt) {
  return callLlmWithRetry(prompt, LLM_MAX_RETRIES);
}

String callLlmWithRetry(String prompt, int retriesLeft) {
  try {
    println("  [callLlm] Connecting to: " + LLM_URL + "/v1/chat/completions");
    println("  [callLlm] Timeout: " + (LLM_READ_TIMEOUT / 1000) + "s, Retries left: " + retriesLeft);
    
    URL url = new URL(LLM_URL + "/v1/chat/completions");
    HttpURLConnection conn = (HttpURLConnection) url.openConnection();
    conn.setRequestMethod("POST");
    conn.setRequestProperty("Content-Type", "application/json");
    conn.setDoOutput(true);
    conn.setConnectTimeout(LLM_CONNECT_TIMEOUT);
    conn.setReadTimeout(LLM_READ_TIMEOUT);
    
    // Build request JSON (OpenAI chat completions format)
    String requestBody = buildLmStudioRequest(prompt);
    println("  [callLlm] Sending request (" + requestBody.length() + " bytes)...");
    
    // Send request
    OutputStream os = conn.getOutputStream();
    os.write(requestBody.getBytes("UTF-8"));
    os.close();
    
    println("  [callLlm] Waiting for response (this may take several minutes for complex prompts)...");
    long startTime = System.currentTimeMillis();
    
    // Read response
    int code = conn.getResponseCode();
    long elapsed = (System.currentTimeMillis() - startTime) / 1000;
    println("  [callLlm] Response code: " + code + " (took " + elapsed + "s)");
    
    if (code != 200) {
      println("  [callLlm] LM Studio returned error: " + code);
      // Try to read error message
      try {
        BufferedReader errReader = new BufferedReader(
          new InputStreamReader(conn.getErrorStream(), "UTF-8")
        );
        String errLine;
        while ((errLine = errReader.readLine()) != null) {
          println("    " + errLine);
        }
        errReader.close();
      } catch (Exception ignored) {}
      conn.disconnect();
      return null;
    }
    
    BufferedReader reader = new BufferedReader(
      new InputStreamReader(conn.getInputStream(), "UTF-8")
    );
    
    StringBuilder response = new StringBuilder();
    String line;
    while ((line = reader.readLine()) != null) {
      response.append(line);
    }
    reader.close();
    conn.disconnect();
    
    println("  [callLlm] Response length: " + response.length() + " chars");
    
    // Extract content from OpenAI response format
    String content = extractChatContent(response.toString());
    if (content == null) {
      println("  [callLlm] Failed to extract content from response");
      println("  [callLlm] Raw response: " + response.toString().substring(0, min(500, response.length())));
    }
    return content;
    
  } catch (java.net.SocketTimeoutException e) {
    println("  [callLlm] Timeout: " + e.getMessage());
    if (retriesLeft > 0) {
      println("  [callLlm] Retrying in " + (LLM_RETRY_DELAY / 1000) + " seconds...");
      try { Thread.sleep(LLM_RETRY_DELAY); } catch (InterruptedException ie) {}
      return callLlmWithRetry(prompt, retriesLeft - 1);
    }
    println("  [callLlm] All retries exhausted");
    return null;
  } catch (java.net.ConnectException e) {
    println("  [callLlm] Connection failed: " + e.getMessage());
    if (retriesLeft > 0) {
      println("  [callLlm] Retrying in " + (LLM_RETRY_DELAY / 1000) + " seconds...");
      try { Thread.sleep(LLM_RETRY_DELAY); } catch (InterruptedException ie) {}
      return callLlmWithRetry(prompt, retriesLeft - 1);
    }
    println("  [callLlm] All retries exhausted");
    return null;
  } catch (IOException e) {
    println("  [callLlm] IO Exception: " + e.getMessage());
    if (retriesLeft > 0 && !e.getMessage().contains("refused")) {
      println("  [callLlm] Retrying in " + (LLM_RETRY_DELAY / 1000) + " seconds...");
      try { Thread.sleep(LLM_RETRY_DELAY); } catch (InterruptedException ie) {}
      return callLlmWithRetry(prompt, retriesLeft - 1);
    }
    return null;
  } catch (Exception e) {
    println("  [callLlm] Exception: " + e.getMessage());
    e.printStackTrace();
    return null;
  }
}

String buildLmStudioRequest(String prompt) {
  // Escape special characters in prompt
  String escapedPrompt = prompt
    .replace("\\", "\\\\")
    .replace("\"", "\\\"")
    .replace("\n", "\\n")
    .replace("\r", "")
    .replace("\t", "\\t");
  
  // OpenAI chat completions format
  return "{" +
    "\"model\":\"" + LLM_MODEL + "\"," +
    "\"messages\":[{\"role\":\"user\",\"content\":\"" + escapedPrompt + "\"}]," +
    "\"temperature\":0.7," +
    "\"max_tokens\":500" +
    "}";
}

String extractChatContent(String jsonResponse) {
  // Extract content from OpenAI chat completions response
  // Format: {"choices":[{"message":{"content":"..."}}]}
  
  int contentStart = jsonResponse.indexOf("\"content\":");
  if (contentStart < 0) {
    println("Could not find content in response");
    return null;
  }
  
  // Find the string value after "content":
  int quoteStart = jsonResponse.indexOf("\"", contentStart + 10);
  if (quoteStart < 0) return null;
  
  // Find closing quote (handle escaped quotes)
  int pos = quoteStart + 1;
  StringBuilder content = new StringBuilder();
  while (pos < jsonResponse.length()) {
    char c = jsonResponse.charAt(pos);
    if (c == '\\' && pos + 1 < jsonResponse.length()) {
      char next = jsonResponse.charAt(pos + 1);
      if (next == '"') {
        content.append('"');
        pos += 2;
        continue;
      } else if (next == 'n') {
        content.append('\n');
        pos += 2;
        continue;
      } else if (next == 't') {
        content.append('\t');
        pos += 2;
        continue;
      } else if (next == '\\') {
        content.append('\\');
        pos += 2;
        continue;
      }
    }
    if (c == '"') break;
    content.append(c);
    pos++;
  }
  
  return content.toString();
}

// ============================================
// PROMPT BUILDING (Pure Calculation)
// ============================================

String buildShaderSelectionPrompt(SongMetadata song, ArrayList<ShaderInfo> shaders) {
  StringBuilder sb = new StringBuilder();
  
  sb.append("You are a VJ assistant that selects visual shaders based on song mood.\n\n");
  
  sb.append("Song Information:\n");
  sb.append("Title: ").append(song.title).append("\n");
  sb.append("Artist: ").append(song.artist).append("\n");
  
  if (song.lyrics != null && !song.lyrics.isEmpty()) {
    String truncatedLyrics = song.lyrics.length() > 500 ? 
      song.lyrics.substring(0, 500) + "..." : song.lyrics;
    sb.append("Lyrics sample: ").append(truncatedLyrics).append("\n");
  }
  
  sb.append("\nAvailable shaders (with analyzed properties):\n");
  for (ShaderInfo info : shaders) {
    sb.append("- ").append(info.name);
    
    // Include LLM-analyzed properties if available
    ShaderAnalysis analysis = shaderAnalyses.get(info.name);
    if (analysis != null) {
      sb.append(" | mood: ").append(analysis.mood);
      sb.append(", energy: ").append(analysis.energy);
      if (analysis.colors.length > 0) {
        sb.append(", colors: ").append(String.join("/", analysis.colors));
      }
      if (analysis.objects.length > 0) {
        sb.append(", visuals: ").append(String.join("/", analysis.objects));
      }
    } else {
      // Fallback to filename-based tags
      sb.append(" [").append(info.getTagString()).append("]");
    }
    sb.append("\n");
  }
  
  sb.append("\nSelect 2-4 shaders that match the song's mood and energy.\n");
  sb.append("Respond with ONLY valid JSON in this exact format:\n");
  sb.append("{\"mood\": \"short mood description\", \"shader_ids\": [\"shader1\", \"shader2\"]}\n");
  sb.append("\nJSON response:");
  
  return sb.toString();
}

// ============================================
// RESPONSE PARSING (Pure Calculation)
// ============================================

ShaderSelection parseShaderSelectionResponse(String songId, String response) {
  if (response == null || response.isEmpty()) return null;
  
  // Find JSON in response (may have extra text)
  int jsonStart = response.indexOf("{");
  int jsonEnd = response.lastIndexOf("}");
  
  if (jsonStart < 0 || jsonEnd < 0 || jsonEnd <= jsonStart) {
    println("No valid JSON found in LLM response");
    return null;
  }
  
  String jsonStr = response.substring(jsonStart, jsonEnd + 1);
  
  // Simple JSON parsing (avoid external dependencies)
  String mood = extractJsonString(jsonStr, "mood");
  String[] shaderIds = extractJsonArray(jsonStr, "shader_ids");
  
  if (shaderIds == null || shaderIds.length == 0) {
    // Try alternative key names
    shaderIds = extractJsonArray(jsonStr, "shaderIds");
    if (shaderIds == null) {
      shaderIds = extractJsonArray(jsonStr, "shaders");
    }
  }
  
  if (shaderIds == null || shaderIds.length == 0) {
    println("Could not extract shader IDs from response");
    return null;
  }
  
  return new ShaderSelection(songId, shaderIds, mood != null ? mood : "unknown");
}

String extractJsonString(String json, String key) {
  String pattern = "\"" + key + "\"\\s*:\\s*\"";
  int start = -1;
  
  // Simple search for key
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
// LLM QUERY (threaded)
// ============================================

void queryLlmForSelection() {
  if (!llmAvailable) {
    println("LLM not available");
    selectRandomShaders();
    return;
  }
  
  println("Building prompt...");
  String prompt = buildShaderSelectionPrompt(currentSong, availableShaders);
  
  println("Calling LM Studio...");
  String response = callLlm(prompt);
  
  if (response == null) {
    println("LLM call failed, using random selection");
    selectRandomShaders();
    return;
  }
  
  println("LLM response: " + response);
  
  ShaderSelection selection = parseShaderSelectionResponse(currentSong.getId(), response);
  
  if (selection == null) {
    println("Could not parse LLM response, using random selection");
    selectRandomShaders();
    return;
  }
  
  println("LLM selected mood: " + selection.mood);
  println("LLM selected shaders: " + String.join(", ", selection.shaderIds));
  
  currentSelection = selection;
  saveCachedSelection(selection);
  applySelection();
}

// ============================================
// SHADER ANALYSIS
// ============================================

String buildShaderAnalysisPrompt(String shaderName, String shaderSource) {
  // Truncate very long shaders
  String source = shaderSource.length() > 3000 ? 
    shaderSource.substring(0, 3000) + "\n// ... (truncated)" : shaderSource;
  
  StringBuilder sb = new StringBuilder();
  sb.append("Analyze this GLSL shader and describe its visual properties.\n\n");
  sb.append("Shader name: ").append(shaderName).append("\n\n");
  sb.append("Source code:\n```glsl\n").append(source).append("\n```\n\n");
  
  sb.append("Respond with ONLY valid JSON in this exact format:\n");
  sb.append("{\n");
  sb.append("  \"mood\": \"<one word: energetic|calm|dark|bright|psychedelic|mysterious|chaotic|peaceful|aggressive|dreamy>\",\n");
  sb.append("  \"colors\": [\"<dominant color>\", \"<secondary color>\"],\n");
  sb.append("  \"geometry\": [\"<shape type>\"],\n");
  sb.append("  \"objects\": [\"<visual element>\"],\n");
  sb.append("  \"effects\": [\"<visual effect>\"],\n");
  sb.append("  \"energy\": \"<low|medium|high>\",\n");
  sb.append("  \"complexity\": \"<simple|medium|complex>\",\n");
  sb.append("  \"description\": \"<one sentence description>\"\n");
  sb.append("}\n\n");
  sb.append("JSON response:");
  
  return sb.toString();
}

ShaderAnalysis parseShaderAnalysisResponse(String shaderName, String response) {
  if (response == null || response.isEmpty()) return null;
  
  // Find JSON in response
  int jsonStart = response.indexOf("{");
  int jsonEnd = response.lastIndexOf("}");
  
  if (jsonStart < 0 || jsonEnd < 0 || jsonEnd <= jsonStart) {
    println("No valid JSON found in analysis response");
    return null;
  }
  
  String json = response.substring(jsonStart, jsonEnd + 1);
  
  // Extract fields
  String mood = extractJsonString(json, "mood");
  String energy = extractJsonString(json, "energy");
  String complexity = extractJsonString(json, "complexity");
  String description = extractJsonString(json, "description");
  String[] colors = extractJsonArray(json, "colors");
  String[] geometry = extractJsonArray(json, "geometry");
  String[] objects = extractJsonArray(json, "objects");
  String[] effects = extractJsonArray(json, "effects");
  
  // Provide defaults
  if (mood == null) mood = "unknown";
  if (energy == null) energy = "medium";
  if (complexity == null) complexity = "medium";
  if (description == null) description = "";
  if (colors == null) colors = new String[0];
  if (geometry == null) geometry = new String[0];
  if (objects == null) objects = new String[0];
  if (effects == null) effects = new String[0];
  
  return new ShaderAnalysis(shaderName, mood, colors, geometry, objects, effects, 
                            energy, complexity, description);
}

// Analyze a single shader (blocking)
ShaderAnalysis analyzeShader(String shaderName, String shaderPath) {
  println("  [analyzeShader] Starting analysis for: " + shaderName);
  
  if (!llmAvailable) {
    println("  [analyzeShader] LLM not available");
    return null;
  }
  
  // Load shader source
  println("  [analyzeShader] Loading from: " + shaderPath);
  String[] lines = loadStrings(shaderPath);
  if (lines == null) {
    println("  [analyzeShader] Could not load shader file");
    return null;
  }
  String source = String.join("\n", lines);
  println("  [analyzeShader] Loaded " + lines.length + " lines, " + source.length() + " chars");
  
  // Build and send prompt
  String prompt = buildShaderAnalysisPrompt(shaderName, source);
  println("  [analyzeShader] Calling LLM...");
  String response = callLlm(prompt);
  
  if (response == null) {
    println("  [analyzeShader] LLM returned null");
    return null;
  }
  
  println("  [analyzeShader] Got response: " + response.substring(0, min(200, response.length())) + "...");
  return parseShaderAnalysisResponse(shaderName, response);
}
