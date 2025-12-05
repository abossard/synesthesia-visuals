/**
 * Data Classes for VJUniverse
 * Pure data structures - immutable where possible
 */

// ============================================
// SONG METADATA
// ============================================

class SongMetadata {
  final String id;
  final String title;
  final String artist;
  final String lyrics;
  
  SongMetadata(String id, String title, String artist, String lyrics) {
    this.id = id;
    this.title = title;
    this.artist = artist;
    this.lyrics = lyrics;
  }
  
  String getId() {
    if (id != null && !id.isEmpty()) return id;
    // Generate ID from title+artist
    return sanitizeFilename(title + "_" + artist);
  }
  
  SongMetadata withId(String newId) {
    return new SongMetadata(newId, title, artist, lyrics);
  }
  
  SongMetadata withTitle(String newTitle) {
    return new SongMetadata(id, newTitle, artist, lyrics);
  }
  
  SongMetadata withArtist(String newArtist) {
    return new SongMetadata(id, title, newArtist, lyrics);
  }
  
  SongMetadata withLyrics(String newLyrics) {
    return new SongMetadata(id, title, artist, newLyrics);
  }
}

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
// SHADER ANALYSIS (LLM-generated)
// ============================================

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
  
  ShaderAnalysis(String shaderName, String mood, String[] colors, String[] geometry,
                 String[] objects, String[] effects, String energy, 
                 String complexity, String description) {
    this.shaderName = shaderName;
    this.mood = mood;
    this.colors = colors;
    this.geometry = geometry;
    this.objects = objects;
    this.effects = effects;
    this.energy = energy;
    this.complexity = complexity;
    this.description = description;
    this.analyzedAt = System.currentTimeMillis();
  }
  
  ShaderAnalysis(String shaderName, String mood, String[] colors, String[] geometry,
                 String[] objects, String[] effects, String energy, 
                 String complexity, String description, long analyzedAt) {
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
