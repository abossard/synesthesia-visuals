Below is a single, detailed spec you can paste into GitHub Copilot (or an issue) for it to build the system.

⸻

Spec: Audioreactive P3D + ISF Shader Engine with Ollama + OSC

Goal

Build a Processing (Java mode) project that:
	1.	Uses P3D renderer to draw real-time, mind-bending generative visuals.
	2.	Dynamically loads many shaders (100+), including GLSL and ISF (Interactive Shader Format) files, from a folder.
	3.	Is fully audio-reactive via FFT analysis.
	4.	Receives current song name and lyrics via OSC.
	5.	Calls a local Ollama LLM (e.g. 16B model) via HTTP on http://localhost:11434 to:
	•	Interpret the song’s mood/style from name + lyrics.
	•	Select and combine shaders for that song.
	6.	Caches the shader selection per song (persisted on disk).
	7.	Automatically picks up new shaders dropped into the folder without changing code.
	8.	Follows design principles from:
	•	“Grokking Simplicity” (actions vs calculations vs data; minimize side effects).
	•	“A Philosophy of Software Design” (deep modules, clear interfaces, information hiding).
	9.	Contains enough structure and examples that it can be run and manually tested.

Use Processing 4.x in Java Mode.

⸻

Design Principles (apply to all code)

Apply these throughout:
	•	Separate:
	•	Calculations (pure functions): logic that has no side effects (e.g. mapping song metadata to shader IDs).
	•	Actions (effects): I/O (OSC, HTTP, disk, audio input, drawing).
	•	Data: plain, immutable data structures.
(Grokking Simplicity style.)
	•	For each module:
	•	Make it deep: simple public API, complex logic inside.
	•	Avoid leaking internal representations (no direct field access to mutable state).
	•	Define clear invariants; preserve them aggressively.
	•	Prefer composition over implicit coupling.
(A Philosophy of Software Design style.)
	•	Keep top-level draw() thin: orchestrate modules, don’t put heavy logic there.
	•	Prefer small, well-named functions over large multi-purpose ones.

⸻

Project Structure

Create a Gradle or Maven project with Processing integrated, but keep the Processing sketch in src/main/java so IDEs work well.

Example layout (adjust as needed for Processing’s expectations):

project-root/
  build.gradle / pom.xml
  processing/
    AudioreactiveSketch.pde      // main sketch (Processing mode)
  src/main/java/
    core/
      AppConfig.java
      SceneState.java
      ShaderConfig.java
      ShaderSelection.java
    audio/
      AudioAnalyzer.java
    osc/
      OscServer.java
      SongMetadata.java
    llm/
      LlmClient.java
      ScenePromptBuilder.java
    shaders/
      ShaderManager.java
      IsfShaderLoader.java
      ShaderMetadata.java
    storage/
      SongSceneStore.java
  data/
    shaders/
      glsl/       // *.frag (and optional *.vert)
      isf/        // *.fs / *.isf
  test/
    java/
      core/
      llm/
      shaders/

If easier, the main sketch can be a *.pde file plus .java files in the same folder; still keep package structure in /src/main/java for non-sketch code.

⸻

Core Data Model

Create small, immutable data classes:

// core/SongMetadata.java (or osc/SongMetadata if you prefer)
public final class SongMetadata {
  public final String id;        // stable ID (e.g. filename or hash of name+artist)
  public final String title;
  public final String artist;
  public final String lyrics;    // may be partial
  // constructor, equals, hashCode, toString
}

// core/ShaderMetadata.java
public final class ShaderMetadata {
  public final String id;           // unique, usually filename without extension
  public final String displayName;  // nice name for logs / UI
  public final String path;         // absolute or data-relative path
  public final ShaderType type;     // GLSL_FRAGMENT, GLSL_PASS, ISF
  public final boolean is3D;        // hint for 3D scenes
  public final boolean isGlitch;
  public final boolean isDark;
  public final boolean isBright;
  public final boolean isPostEffect;
  // etc. (simple flags used by LLM and selection logic)
}

// core/ShaderSelection.java
public final class ShaderSelection {
  public final String songId;
  public final List<String> shaderIds;  // ordered, e.g. [base, mid-pass, post-effect]
  public final String mood;             // e.g. "dark glitchy 3d"
  public final long createdAtMillis;
  // constructor, etc.
}

// core/SceneState.java
public final class SceneState {
  public final ShaderSelection selection;
  public final float globalIntensity;   // 0..1 from audio
  public final float beat;              // 0..1 for current beat phase
  // possibly more
}

These should be pure data (no logic, no I/O).

⸻

Shader Management

Use Processing’s PShader facilities:
	•	Use PShader and loadShader() for fragment/vertex shaders, compatible with P2D and P3D.
	•	A ShaderManager will:
	•	Scan data/shaders/glsl and data/shaders/isf at startup.
	•	Build ShaderMetadata entries for each shader file discovered.
	•	Expose:
	•	List<ShaderMetadata> listAll()
	•	Optional<PShader> getShaderInstance(String shaderId)
	•	void reloadShaders() to rescan directories (e.g. on keypress).
	•	Maintain a map from shaderId → compiled PShader (lazy load or preload).

GLSL Shaders
	•	Support basic shaders: single fragment shaders, optionally with a vertex shader.
	•	For now, assume fragment-only shaders using loadShader("filename.frag") from data/shaders/glsl.
	•	Provide a sample GLSL shader in data/shaders/glsl/:

// data/shaders/glsl/simple_pulse.frag
#ifdef GL_ES
precision mediump float;
precision mediump int;
#endif

uniform float time;
uniform vec2 resolution;
uniform float bass;
uniform float mid;
uniform float treble;

void main() {
  vec2 uv = gl_FragCoord.xy / resolution.xy;
  float v = 0.5 + 0.5 * sin(time * 2.0 + uv.x * 10.0 + bass * 5.0);
  v += 0.25 * sin(time * 3.0 + uv.y * 20.0 + mid * 4.0);
  v += 0.25 * sin(time * 4.0 + (uv.x + uv.y) * 15.0 + treble * 6.0);
  gl_FragColor = vec4(vec3(v), 1.0);
}

ISF Shaders
	•	ISF is GLSL + metadata. The spec describes uniforms like TIME, RENDERSIZE, isf_FragNormCoord, DATE, etc..
	•	Implement IsfShaderLoader to:
	•	Load .fs / .isf file as text.
	•	Parse JSON metadata if present (header block).
	•	Extract fragment shader code (GLSL).
	•	Map ISF standard uniforms to Processing uniforms:
	•	TIME → float time uniform in Processing.
	•	RENDERSIZE → vec2 resolution.
	•	isf_FragNormCoord can be recomputed as fragCoord / resolution.
	•	For a first pass, you can:
	•	Generate a wrapper fragment shader template that:
	•	Declares Processing-style uniforms.
	•	Injects the ISF core main logic inside.
	•	Or, for simple ISF shaders, just adapt the variable names and let Processing handle the rest.
	•	Keep IsfShaderLoader as a pure calculation module (convert ISF file content → compiled GLSL source string + metadata). The actual PShader construction is the effectful part handled by ShaderManager.

You do not need full ISF support; start with the subset required by simple generative and post-FX shaders.

⸻

Audio Analysis

Use Processing Sound library (preferred) or Minim. The Sound library includes an FFT class that analyzes an audio stream into frequency bands. There are examples using SoundFile, FFT, etc..

Create audio/AudioAnalyzer.java:

Responsibilities:
	•	Initialize:
	•	Audio source: can be an AudioIn (mic) or SoundFile.
	•	FFT instance with a configurable number of bands.
	•	In each frame:
	•	Call fft.analyze() to get spectral data.
	•	Compute:
	•	bass (average of lowest N bands).
	•	mid (middle bands).
	•	treble (highest bands).
	•	overallLevel (RMS, or average magnitude).
	•	Optionally a simple beat detection (peak detection on bass).
	•	Expose a pure read API:

public class AudioAnalyzer {
  public void update();         // performs FFT analysis (action)
  public float getBass();       // 0..1
  public float getMid();
  public float getTreble();
  public float getOverallLevel();
  public float getBeatPhase();  // 0..1 simple LFO/phase if you want
}

Implementation notes:
	•	Use examples from Processing Sound’s FFT docs.
	•	Keep the analyzer self-contained and deep (no external dependencies beyond the Sound lib).

⸻

OSC Integration (Song Metadata + Lyrics)

Use oscP5 library for OSC in Processing.

Create osc/OscServer.java:

Responsibilities:
	•	Listen on a configurable UDP port for OSC messages.
	•	Handle at least:
	•	/song/title → string
	•	/song/artist → string
	•	/song/lyrics → string (possibly sent in chunks; handle accumulating).
	•	/song/id → string (if provided; otherwise generate from title+artist).
	•	Maintain current SongMetadata (immutable; updates by creating new instance).
	•	Expose:

public interface SongMetadataListener {
  void onSongMetadataUpdated(SongMetadata metadata);
}

public class OscServer {
  public OscServer(int port, SongMetadataListener listener);
  public void start();
  public void stop();
  public SongMetadata getCurrentMetadata();  // last known
}

	•	Keep network handling (OSC) separate from domain logic (SongMetadata). The Parsing and building of SongMetadata should be done via pure helper functions in a separate class, so they can be unit-tested.

⸻

LLM Integration (Ollama Client)

Use local Ollama API, served on http://localhost:11434. The generate endpoint expects JSON with at least model and prompt. Example from API docs:

curl http://localhost:11434/api/generate -d '{
  "model": "llama3.2",
  "prompt": "Write a haiku"
}'

Create llm/LlmClient.java:
	•	Use Java’s built-in HttpClient (Java 11+).
	•	Expose:

public final class LlmClient {
  private final URI baseUri;
  private final String modelName;

  public LlmClient(URI baseUri, String modelName);

  public String generate(String prompt) throws IOException, InterruptedException;
}

	•	generate() sends a POST to /api/generate with streaming disabled (if supported) so we get a single response.
	•	It should be an action; keep all parsing separate.

Create llm/ScenePromptBuilder.java:
	•	Pure class that turns:
	•	SongMetadata
	•	List<ShaderMetadata> (all available)
into a prompt string.

Prompt spec:
	•	Provide the model with:
	•	Song title, artist, and a sample of lyrics (trim long lyrics).
	•	A list of shader IDs with short tags (dark/bright/glitchy/3D/post).
	•	Ask it to:
	•	Pick a mood/style label (short string).
	•	Select N shader IDs (e.g. 3–5).
	•	Output in a strict JSON format so we can parse reliably, e.g.:

{
  "mood": "dark glitchy 3d",
  "shader_ids": ["simple_pulse", "feedback_glitch", "bloom_post"]
}

	•	Make the prompt explicit about the schema and ask the model to only output JSON.

Create a pure function:

public final class ScenePromptBuilder {
  public static String buildPrompt(SongMetadata song,
                                   List<ShaderMetadata> shaders);
}

Create a pure parser:

public final class ShaderSelectionParser {
  public static ShaderSelection parse(String songId, String jsonResponse);
}

	•	Use a JSON library (e.g. Jackson or Gson) to parse the LLM output into ShaderSelection.

⸻

Song → Scene Mapping Storage

Create storage/SongSceneStore.java:

Responsibilities:
	•	Persist and load ShaderSelection per song.
	•	Implement as simple JSON on disk in data/scenes/:

data/scenes/
  <songId>.json

JSON format:

{
  "songId": "...",
  "mood": "dark glitchy 3d",
  "shaderIds": ["simple_pulse", "feedback_glitch", "bloom_post"],
  "createdAtMillis": 1733400000000
}

API:

public final class SongSceneStore {
  public SongSceneStore(Path rootDir);

  public Optional<ShaderSelection> load(String songId);

  public void save(ShaderSelection selection) throws IOException;
}

	•	Keep file I/O isolated here; no drawing or LLM logic.

⸻

Scene Orchestration & Rendering

In the main sketch (AudioreactiveSketch.pde):
	•	Use size(width, height, P3D) and P3D renderer.
	•	Dependencies:
	•	ShaderManager
	•	AudioAnalyzer
	•	OscServer
	•	LlmClient
	•	SongSceneStore
	•	Maintain mutable state only for:
	•	SceneState currentSceneState
	•	Active ShaderSelection and PShader instances.
	•	Timing variables.

Startup (setup())
	1.	Initialize Processing window: size(1920, 1080, P3D); or similar.
	2.	Initialize AudioAnalyzer and start audio input / playback.
	3.	Initialize ShaderManager and load shaders from data/shaders/glsl and data/shaders/isf.
	4.	Initialize SongSceneStore with data/scenes.
	5.	Initialize OscServer, with a listener that:
	•	Updates current SongMetadata.
	•	Triggers a scene update logic (described below).
	6.	Initialize LlmClient with:
	•	baseUri = URI.create("http://localhost:11434");
	•	modelName configurable (e.g. "llama3.2" or another 16B model).
	7.	Optionally, create an off-screen PGraphics target for multi-pass rendering (ping-pong) for chaining shaders.

Per-frame (draw())
	1.	Clear background or render a base 3D scene (e.g. some shapes).
	2.	Update AudioAnalyzer.update().
	3.	Compute SceneState (pure calculation) using:
	•	Current ShaderSelection.
	•	AudioAnalyzer outputs.
	4.	Apply the shader pipeline:
	•	For each shader ID in SceneState.selection.shaderIds:
	•	Get its PShader from ShaderManager.
	•	Set uniforms:
	•	time = millis() / 1000.0f.
	•	resolution = vec2(width, height).
	•	bass, mid, treble, level, etc.
	•	For ISF-style shaders, also set TIME, RENDERSIZE, etc.
	•	Apply via either:
	•	shader(pShader); // then draw full-screen quad
	•	Or multi-pass using PGraphics (draw to off-screen buffer, feed to next shader).
	5.	Draw a simple overlay with debug info:
	•	Current song title and mood.
	•	Names of active shaders.
	6.	Add key bindings:
	•	r → reload shaders via ShaderManager.reloadShaders().
	•	n → force re-run of scene selection for current song (re-query LLM).
	•	d → toggle debug text overlay.

⸻

Scene Update Logic (Song → ShaderSelection)

Create a pure function in a “core” class:

public final class SceneSelector {
  public static ShaderSelection selectScene(
    SongMetadata song,
    List<ShaderMetadata> allShaders,
    Optional<ShaderSelection> existingSelection,
    LlmClient llmClient,            // side-effect interaction
    SongSceneStore store            // side-effect interaction
  );
}

But for clarity and testability, split:
	•	SceneSelectorLogic (pure):

public final class SceneSelectorLogic {
  public static boolean shouldReuseExistingSelection(SongMetadata song,
                                                     ShaderSelection existing);

  public static String buildPrompt(SongMetadata song,
                                   List<ShaderMetadata> allShaders);

  public static ShaderSelection parseResponse(String songId,
                                              String responseJson);
}

	•	A small orchestrator in the sketch or a wrapper class that:
	•	Checks SongSceneStore.load(songId).
	•	If found and fresh → reuse.
	•	Otherwise:
	•	Build prompt via ScenePromptBuilder.
	•	Call LlmClient.generate(prompt) (action).
	•	Parse JSON with ShaderSelectionParser.
	•	Save via SongSceneStore.save().
	•	Update current ShaderSelection.

The sketch should call this logic when:
	•	A new song ID is received via OSC.
	•	Or user hits a key (n) to force re-selection.

This respects “Grokking Simplicity” by isolating actions (HTTP+disk) from pure logic.

⸻

Auto-discovery of New Shaders

In ShaderManager:
	•	Maintain a simple directory scan with timestamps:

public void reloadShadersIfChanged() {
  // check lastModified times of shader directories
}

	•	Optionally:
	•	Pressing r triggers a full rescan.
	•	In development, you can check every few seconds.

When new files are found:
	•	Create new ShaderMetadata.
	•	Compile PShader for them (or lazily compile when first used).
	•	Make sure they become visible to LLM (list passed to ScenePromptBuilder should include them).

⸻

Testing & Running

Even though Processing’s graphics are hard to unit test, a lot of this system is pure logic and can be tested.

Unit Tests

Use JUnit (or similar) for pure modules:
	•	ScenePromptBuilder:
	•	Given a sample SongMetadata and a few ShaderMetadata entries, assert that the prompt:
	•	Contains song title + artist.
	•	Lists shader IDs.
	•	Includes a JSON schema request.
	•	ShaderSelectionParser:
	•	Feed example JSON and assert the resulting ShaderSelection is correct.
	•	SongSceneStore:
	•	Write/read a temp directory and assert data round-trips.
	•	IsfShaderLoader:
	•	Feed a sample minimal ISF file (include small fixture file) and assert:
	•	The returned GLSL text has correct uniform mappings.
	•	SceneSelectorLogic:
	•	Test shouldReuseExistingSelection behavior.

Manual / Integration Testing

Create README.md with step-by-step instructions:
	1.	Install Processing 4.x and Java.
	2.	Install Sound and oscP5 libraries:
	•	Sound: via Processing’s “Add Library…” (Sound library).
	•	oscP5: download from oscP5 site / GitHub and put in Processing libraries/ folder.
	3.	Install Ollama and pull a model (e.g. llama3.2 or another 16B model):
	•	Start Ollama so it listens on http://localhost:11434.
	4.	Start the sketch from Processing IDE or via Gradle.
	5.	Send OSC messages from your DJ/bridge (e.g. /song/title, /song/artist, /song/lyrics).
	6.	Verify:
	•	On first song, the sketch queries the LLM, builds a new shader selection, and writes a JSON file to data/scenes/<songId>.json.
	•	On second play of the same song, it reuses the cached selection (no LLM call).
	•	Press r to reload shaders and see new effects show up in selection for new songs.
	7.	Check audio-reactivity:
	•	Play music into the audio input or via SoundFile and see the scene change with bass/mid/treble.
	•	Adjust thresholds in AudioAnalyzer if needed.

Also include a simple “dev checklist” in the repo:
	•	Start Ollama and confirm curl http://localhost:11434/api/tags works.
	•	Start OSC source and confirm the sketch logs song metadata on each message.
	•	Confirm data/scenes/ files are created and updated.
	•	Confirm pressing r reloads shaders (e.g. log shader count before/after).

⸻

Implementation Notes for Copilot

When Copilot generates code:
	•	Prefer:
	•	Small, cohesive classes with a single responsibility.
	•	Immutable data classes.
	•	Clear boundaries between:
	•	UI (Processing sketch).
	•	Audio/OSC/LLM (side-effect modules).
	•	Pure calculations (prompt building, mapping, parsing, selection).
	•	Avoid:
	•	Putting heavy logic in draw().
	•	Global mutable state spread across classes.
	•	Add comments explaining invariants, e.g.:
	•	“SongSceneStore: invariant – each songId has at most one JSON file, and JSON conforms to ShaderSelection schema.”
	•	Wherever possible, implement in small steps and keep the sketch running after each addition.

⸻

References (keep these as plain text)

Processing loadShader reference:
https://processing.org/reference/loadShader_

PShader reference (class and set()):
https://processing.org/reference/PShader.html

Processing Sound library overview:
https://processing.org/reference/libraries/sound/

FFT with Processing Sound example (gist):
https://gist.github.com/jaywon/72705b0cc1832f6878bb

oscP5 library (Processing OSC):
http://www.sojamo.de/libraries/oscp5/
https://github.com/sojamo/oscp5

OSC + oscP5 documentation:
https://www.cs.princeton.edu/~prc/ChucKU/Code/OSCAndMIDIExamples/VideoAction/oscP5/documentation/index.htm

Interactive Shader Format (ISF) intro:
https://docs.isf.video/quickstart.html

ISF variables (TIME, RENDERSIZE, etc.):
https://docs.isf.video/ref_variables.html
https://github.com/mrRay/ISF_Spec

Ollama API docs (local server, /api/generate):
https://docs.ollama.com/api
https://github.com/ollama/ollama/blob/main/docs/api.md

Ollama local server details:
https://docs.ollama.com/faq
https://docs.ollama.com/windows
https://blog.postman.com/how-to-connect-to-local-ollama/

Use these docs as authoritative sources for how to call loadShader(), how to set up Sound/FFT, how to handle OSC with oscP5, how ISF uniforms work, and how to talk to Ollama’s HTTP API on localhost:11434.