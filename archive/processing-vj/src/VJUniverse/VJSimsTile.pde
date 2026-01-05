/**
 * VJSimsTile.pde - VJSims Level integration for VJUniverse
 *
 * Wraps VJSims levels as a VJUniverse tile with unified audio handling.
 *
 * Audio (same approach as shaders):
 * - Levels receive global 'audio' AudioEnvelope (enhanced in VJUniverse.draw)
 * - Timing uses global 'audioTime' (audio-reactive, synced to beat)
 * - Enhanced bass/mid/high values with kick punch, presence, energy mixed in
 *
 * Features:
 * - 42 procedural levels from VJSims
 * - Level switching via keyboard (when focused) and OSC
 * - Recording mode (auto-rotate + screenshots)
 */

class VJSimsTile extends Tile {

  // === LEVEL MANAGEMENT ===
  ArrayList<Level> levels = new ArrayList<Level>();
  Level activeLevel;
  int currentLevelIndex = 0;

  // === TIMING ===
  float lastFrameTime = 0;
  // Note: We use global 'audioTime' for audio-reactive timing (same as shaders)
  // Audio comes from global 'audio' (updated in VJUniverse.draw)

  // === RECORDING MODE ===
  boolean recordingMode = false;
  long levelChangeTimeMs = 0;
  long nextLevelAtMs = 0;
  int levelDurationMs = 10000;  // 10s per level
  int screenshotDelayMs = 3000; // 3s after level load
  boolean levelScreenshotTaken = false;
  String screenshotDir;

  VJSimsTile() {
    super("VJSims", "VJUniverse/VJSims");

    setOSCAddresses(
      new String[] {"/vjsims/level", "/vjsims/next", "/vjsims/prev", "/vjsims/reset", "/vjsims/record"},
      new String[] {"Load level", "Next level", "Previous level", "Reset level", "Toggle record"}
    );
  }

  @Override
  void init(PApplet parent) {
    super.init(parent);

    // Initialize levels
    initLevels();

    // Screenshots directory
    screenshotDir = parent.sketchPath("screenshots/vjsims");
    ensureScreenshotDir();

    // Start with first level
    switchLevel(0);

    println("[VJSimsTile] Initialized with " + levels.size() + " levels");
  }

  void initLevels() {
    levels.clear();

    // New audio-reactive P3D simulations
    levels.add(new BreathingPlanetLevel());
    levels.add(new BoidsFlockLevel());
    levels.add(new GalaxySpiralLevel());
    levels.add(new DNAHelixLevel());
    levels.add(new ToroidalFlowLevel());
    levels.add(new MetaballsLevel());
    levels.add(new Fireworks3DLevel());
    levels.add(new FFTMountainsLevel());
    levels.add(new ForceGraphLevel());
    levels.add(new LSystemTreesLevel());
    levels.add(new StarfieldWarpLevel());
    levels.add(new MeshMorphLevel());
    levels.add(new VoronoiCrystalLevel());
    levels.add(new VortexTunnelLevel());
    levels.add(new SpectrumBars3DLevel());
    levels.add(new VolumetricFireLevel());
    levels.add(new KaleidoscopeGeometryLevel());
    levels.add(new TentacleRibbonLevel());
    levels.add(new GeodesicExplosionLevel());
    levels.add(new ReactionDiffusionSurfaceLevel());

    // Existing / legacy levels
    levels.add(new GravityWellsLevel());
    levels.add(new JellyBlobsLevel());
    levels.add(new AgentTrailsLevel());
    levels.add(new ReactionDiffusionLevel());
    levels.add(new RecursiveCityLevel());
    levels.add(new LiquidFloorLevel());
    levels.add(new CellularAutomataLevel());
    levels.add(new PortalRaymarcherLevel());
    levels.add(new RopeSimulationLevel());
    levels.add(new LogoWindTunnelLevel());
    levels.add(new SwarmCamerasLevel());
    levels.add(new TimeSmearLevel());
    levels.add(new MirrorRoomsLevel());
    levels.add(new TextEngineLevel());

    // Extra stylized levels
    levels.add(new NoisyBlobLevel());
    levels.add(new WireframeTunnelLevel());
    levels.add(new FloatingTerrainLevel());
    levels.add(new ParticleGalaxyLevel());
    levels.add(new RibbonHelixLevel());
    levels.add(new RetroShipLevel());
    levels.add(new RetroFreighterLevel());
    levels.add(new ClassicPulseLevel());

    // Cinematic wireframe space levels
    levels.add(new CapitalShipFlybyLevel());
    levels.add(new RingedPlanetLevel());
    levels.add(new SpaceFleetLevel());

    // Low-poly landscape with infinite scrolling biomes
    levels.add(new LowPolyLandscapeLevel());

    // Isometric dark sci-fi world with procedural bases, spacecraft, and infrastructure
    levels.add(new IsometricSciFiWorldLevel());
  }

  // === LEVEL MANAGEMENT ===

  void switchLevel(int index) {
    if (levels.size() == 0) {
      activeLevel = null;
      return;
    }
    currentLevelIndex = ((index % levels.size()) + levels.size()) % levels.size();
    activeLevel = levels.get(currentLevelIndex);
    if (activeLevel != null) {
      activeLevel.reset();
      levelChangeTimeMs = millis();
      nextLevelAtMs = levelChangeTimeMs + levelDurationMs;
      levelScreenshotTaken = false;
      println("[VJSimsTile] Switched to level: " + activeLevel.getName());
    }
  }

  void nextLevel() {
    switchLevel(currentLevelIndex + 1);
  }

  void prevLevel() {
    switchLevel(currentLevelIndex - 1);
  }

  void resetLevel() {
    if (activeLevel != null) {
      activeLevel.reset();
      println("[VJSimsTile] Reset level: " + activeLevel.getName());
    }
  }

  // === UPDATE ===

  @Override
  void update() {
    // Calculate delta time
    float now = millis() / 1000.0;
    float dt = (lastFrameTime > 0) ? (now - lastFrameTime) : 0.016;
    lastFrameTime = now;

    // Update active level using:
    // - dt: frame delta for physics
    // - audioTime: audio-reactive time (same as shaders)
    // - audio: global AudioEnvelope (updated in VJUniverse.draw with enhanced values)
    if (activeLevel != null) {
      activeLevel.update(dt, audioTime, audio);
    }

    // Recording mode: auto-rotate and screenshots
    if (recordingMode) {
      long nowMs = millis();

      // Auto-rotate levels
      if (nowMs >= nextLevelAtMs) {
        nextLevel();
      }

      // Capture screenshot if needed
      captureScreenshotIfNeeded();
    }
  }

  // === RENDER ===

  @Override
  void render() {
    beginDraw();

    if (activeLevel != null) {
      activeLevel.render(buffer);
    }

    endDraw();
  }



  // === OSC HANDLING ===

  @Override
  boolean handleOSC(OscMessage msg) {
    String addr = msg.addrPattern();

    // /vjsims/level <int> or <string>
    if (addr.equals("/vjsims/level")) {
      if (msg.typetag().length() >= 1) {
        if (msg.typetag().charAt(0) == 'i') {
          switchLevel(msg.get(0).intValue());
        } else if (msg.typetag().charAt(0) == 's') {
          String name = msg.get(0).stringValue();
          loadLevelByName(name);
        }
        markOSCReceived(addr);
        return true;
      }
    }

    // /vjsims/next
    if (addr.equals("/vjsims/next")) {
      nextLevel();
      markOSCReceived(addr);
      return true;
    }

    // /vjsims/prev
    if (addr.equals("/vjsims/prev")) {
      prevLevel();
      markOSCReceived(addr);
      return true;
    }

    // /vjsims/reset
    if (addr.equals("/vjsims/reset")) {
      resetLevel();
      markOSCReceived(addr);
      return true;
    }

    // /vjsims/record <0/1>
    if (addr.equals("/vjsims/record")) {
      if (msg.typetag().length() >= 1) {
        recordingMode = msg.get(0).intValue() != 0;
      } else {
        recordingMode = !recordingMode;
      }
      if (recordingMode) {
        levelChangeTimeMs = millis();
        nextLevelAtMs = levelChangeTimeMs + levelDurationMs;
        levelScreenshotTaken = false;
      }
      println("[VJSimsTile] Recording mode: " + (recordingMode ? "ON" : "OFF"));
      markOSCReceived(addr);
      return true;
    }

    return false;
  }

  void loadLevelByName(String name) {
    String nameLower = name.toLowerCase();
    for (int i = 0; i < levels.size(); i++) {
      if (levels.get(i).getName().toLowerCase().contains(nameLower)) {
        switchLevel(i);
        return;
      }
    }
    println("[VJSimsTile] Level not found: " + name);
  }

  // === KEYBOARD HANDLING ===

  @Override
  boolean handleKey(char key, int keyCode) {
    // Arrow keys for level navigation
    if (keyCode == RIGHT) {
      nextLevel();
      return true;
    }
    if (keyCode == LEFT) {
      prevLevel();
      return true;
    }

    return false;
  }

  @Override
  String getStatusString() {
    if (activeLevel == null) return "No level";
    return activeLevel.getName() + " [" + (currentLevelIndex + 1) + "/" + levels.size() + "]";
  }

  // === SCREENSHOT FUNCTIONALITY ===

  void ensureScreenshotDir() {
    java.io.File dir = new java.io.File(screenshotDir);
    if (!dir.exists()) {
      dir.mkdirs();
    }
  }

  void captureScreenshotIfNeeded() {
    long now = millis();
    if (buffer == null || levelScreenshotTaken) {
      return;
    }
    if (now - levelChangeTimeMs < screenshotDelayMs) {
      return;
    }
    String levelName = activeLevel != null ? activeLevel.getName() : "vjsims";
    String safeName = levelName.toLowerCase().replaceAll("[^a-z0-9]+", "-");

    // Check if screenshot already exists
    if (screenshotExistsForLevel(safeName)) {
      println("[VJSimsTile] Screenshot already exists for level: " + levelName);
      levelScreenshotTaken = true;
      return;
    }

    String filename = screenshotDir + "/" + safeName + ".png";
    buffer.save(filename);
    println("[VJSimsTile] Saved screenshot: " + filename);
    levelScreenshotTaken = true;
  }

  boolean screenshotExistsForLevel(String safeName) {
    java.io.File dir = new java.io.File(screenshotDir);
    if (!dir.exists()) {
      return false;
    }
    String targetFilename = safeName + ".png";
    java.io.File targetFile = new java.io.File(screenshotDir + "/" + targetFilename);
    return targetFile.exists();
  }
}
