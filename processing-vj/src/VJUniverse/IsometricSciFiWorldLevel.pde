/**
 * IsometricSciFiWorldLevel - Procedural dark sci-fi isometric world
 *
 * Inspired by low-poly isometric military/sci-fi bases
 * Features:
 * - Infinite scrolling procedural terrain
 * - Multiple zone types: military, spaceport, industrial, outpost
 * - Procedural buildings: hangars, towers, domes, modules, barracks
 * - Spacecraft and vehicles on landing pads
 * - Infrastructure: roads, pipes, power lines, landing pads
 * - Details: satellite dishes, antennas, cargo containers, lights
 * - Dark sci-fi color palette with accent lighting
 * - Audio-reactive glowing elements
 * - Slow cinematic camera movement
 */
class IsometricSciFiWorldLevel extends Level {

  // ═══════════════════════════════════════════════════════════════════════════
  // CONFIGURATION - Easy to modify
  // ═══════════════════════════════════════════════════════════════════════════

  // World grid
  static final int CHUNK_SIZE = 16;          // Tiles per chunk
  static final int VISIBLE_CHUNKS = 4;       // Chunks visible in each direction
  static final float TILE_SIZE = 40;         // World units per tile

  // Movement
  float scrollSpeed = 25;                    // Slow cinematic scroll
  float cameraRotationSpeed = 0.02;          // Very slow rotation

  // Generation thresholds (0-1, higher = rarer)
  float BUILDING_DENSITY = 0.35;             // How often buildings appear
  float VEHICLE_DENSITY = 0.85;              // How often vehicles appear
  float DETAIL_DENSITY = 0.6;                // How often small details appear

  // ═══════════════════════════════════════════════════════════════════════════
  // STATE
  // ═══════════════════════════════════════════════════════════════════════════

  // Scroll position
  float scrollX = 0;
  float scrollZ = 0;
  float cameraAngle = 0;

  // Audio state
  float audioPulse = 0;
  float audioGlow = 0;
  float audioBass = 0;

  // Time
  float worldTime = 0;

  // Noise seeds
  float terrainSeed;
  float zoneSeed;
  float buildingSeed;
  float detailSeed;

  // Cached chunks
  HashMap<Long, SciFiChunk> chunks = new HashMap<Long, SciFiChunk>();

  // ═══════════════════════════════════════════════════════════════════════════
  // COLORS - Dark sci-fi palette
  // ═══════════════════════════════════════════════════════════════════════════

  // Base colors
  color groundDark, groundMid, groundLight;
  color metalDark, metalMid, metalLight;
  color concrete, asphalt;

  // Accent colors
  color accentOrange, accentTeal, accentRed, accentBlue, accentYellow;
  color glowOrange, glowTeal, glowRed, glowBlue;

  // Building colors by zone
  color[] militaryColors;
  color[] industrialColors;
  color[] spaceportColors;
  color[] outpostColors;

  // ═══════════════════════════════════════════════════════════════════════════
  // ZONE TYPES
  // ═══════════════════════════════════════════════════════════════════════════

  static final int ZONE_EMPTY = 0;
  static final int ZONE_MILITARY = 1;
  static final int ZONE_SPACEPORT = 2;
  static final int ZONE_INDUSTRIAL = 3;
  static final int ZONE_OUTPOST = 4;
  static final int ZONE_MOUNTAIN = 5;

  // ═══════════════════════════════════════════════════════════════════════════
  // BUILDING TYPES
  // ═══════════════════════════════════════════════════════════════════════════

  static final int BUILD_HANGAR = 0;
  static final int BUILD_TOWER = 1;
  static final int BUILD_DOME = 2;
  static final int BUILD_MODULE = 3;
  static final int BUILD_BARRACKS = 4;
  static final int BUILD_RADAR = 5;
  static final int BUILD_SILO = 6;
  static final int BUILD_PLATFORM = 7;
  static final int BUILD_GENERATOR = 8;
  static final int BUILD_ANTENNA = 9;

  // ═══════════════════════════════════════════════════════════════════════════
  // LIFECYCLE
  // ═══════════════════════════════════════════════════════════════════════════

  public void reset() {
    // Initialize seeds
    terrainSeed = random(10000);
    zoneSeed = random(10000);
    buildingSeed = random(10000);
    detailSeed = random(10000);

    // Reset state
    scrollX = 0;
    scrollZ = 0;
    cameraAngle = 0;
    worldTime = 0;
    audioPulse = 0;
    audioGlow = 0;
    audioBass = 0;

    // Clear chunks
    chunks.clear();

    // Initialize colors
    initColors();
  }

  void initColors() {
    // Ground colors - dark desaturated
    groundDark = color(35, 38, 42);
    groundMid = color(55, 58, 62);
    groundLight = color(75, 78, 82);

    // Metal colors
    metalDark = color(45, 48, 55);
    metalMid = color(85, 90, 100);
    metalLight = color(130, 135, 145);

    // Surfaces
    concrete = color(95, 92, 88);
    asphalt = color(50, 52, 55);

    // Accent colors - sci-fi highlights
    accentOrange = color(255, 140, 50);
    accentTeal = color(50, 200, 200);
    accentRed = color(220, 60, 60);
    accentBlue = color(80, 150, 255);
    accentYellow = color(255, 220, 80);

    // Glow versions (for emissive)
    glowOrange = color(255, 160, 80);
    glowTeal = color(100, 255, 255);
    glowRed = color(255, 100, 100);
    glowBlue = color(120, 180, 255);

    // Zone-specific building colors
    militaryColors = new color[] {
      color(70, 75, 70),   // Military green-gray
      color(85, 85, 80),   // Khaki gray
      color(60, 65, 60),   // Dark green-gray
      color(100, 95, 85)   // Tan
    };

    industrialColors = new color[] {
      color(80, 75, 70),   // Rust brown-gray
      color(95, 90, 85),   // Industrial tan
      color(70, 70, 75),   // Blue-gray
      color(110, 100, 90)  // Light industrial
    };

    spaceportColors = new color[] {
      color(90, 95, 105),  // Clean gray-blue
      color(105, 110, 120),// Light steel
      color(75, 80, 90),   // Dark steel
      color(120, 120, 125) // Bright steel
    };

    outpostColors = new color[] {
      color(100, 90, 80),  // Desert tan
      color(85, 80, 75),   // Weathered brown
      color(110, 105, 95), // Sand
      color(75, 72, 68)    // Dark weathered
    };
  }

  public void update(float dt, float t, AudioEnvelope audio) {
    // Slow scroll - diagonal movement looks best in isometric
    float angle = worldTime * 0.05;
    scrollZ += scrollSpeed * dt;
    scrollX += sin(angle) * scrollSpeed * 0.15 * dt;

    // Very slow camera rotation
    cameraAngle += cameraRotationSpeed * dt;

    // Time
    worldTime += dt;

    // Audio reactivity
    float targetPulse = audio.getBass() * 0.8 + audio.getMid() * 0.4;
    audioPulse = lerp(audioPulse, targetPulse, dt * 4);

    float targetGlow = audio.getMid() * 0.6 + audio.getHigh() * 0.8;
    audioGlow = lerp(audioGlow, targetGlow, dt * 6);

    audioBass = lerp(audioBass, audio.getBass(), dt * 8);

    // Cleanup old chunks
    cleanupChunks();
  }

  public void render(PGraphics pg) {
    pg.pushStyle();
    pg.pushMatrix();
    pg.camera();

    // Dark sci-fi sky
    drawSky(pg);

    // Setup isometric camera
    setupIsometricCamera(pg);

    // Lighting
    setupLighting(pg);

    // Calculate visible chunks
    int centerChunkX = floor(scrollX / (CHUNK_SIZE * TILE_SIZE));
    int centerChunkZ = floor(scrollZ / (CHUNK_SIZE * TILE_SIZE));

    // Render chunks back to front for proper depth
    for (int cz = centerChunkZ + VISIBLE_CHUNKS; cz >= centerChunkZ - VISIBLE_CHUNKS; cz--) {
      for (int cx = centerChunkX + VISIBLE_CHUNKS; cx >= centerChunkX - VISIBLE_CHUNKS; cx--) {
        renderChunk(pg, cx, cz);
      }
    }

    pg.popMatrix();

    // Atmosphere overlay
    drawAtmosphere(pg);

    // Reset projection
    pg.perspective();
    pg.camera();

    pg.popStyle();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CAMERA & LIGHTING
  // ═══════════════════════════════════════════════════════════════════════════

  void drawSky(PGraphics pg) {
    // Dark gradient sky with subtle color
    color skyTop = color(15, 18, 25);
    color skyBottom = color(35, 40, 55);

    // Simple gradient via background and overlay
    pg.background(skyTop);

    pg.noStroke();
    pg.beginShape(QUADS);
    pg.fill(skyTop);
    pg.vertex(0, 0);
    pg.vertex(pg.width, 0);
    pg.fill(skyBottom);
    pg.vertex(pg.width, pg.height);
    pg.vertex(0, pg.height);
    pg.endShape();
  }

  void setupIsometricCamera(PGraphics pg) {
    // Orthographic projection for true isometric
    float aspect = (float)pg.width / pg.height;
    float viewSize = 160;  // Smaller = more zoomed in, shows height better
    pg.ortho(-viewSize * aspect, viewSize * aspect, -viewSize, viewSize, -5000, 5000);

    // Center screen
    pg.translate(pg.width * 0.5, pg.height * 0.5, 0);

    // True isometric angle: arctan(1/sqrt(2)) ≈ 35.264 degrees
    // Using ~40 degrees for slightly more dramatic view of heights
    pg.rotateX(radians(40));  // Shallower tilt shows vertical heights better
    pg.rotateY(radians(-45) + sin(cameraAngle) * 0.03);  // Diamond orientation with subtle sway

    // Scroll offset
    pg.translate(-scrollX, 0, -scrollZ);
  }

  void setupLighting(PGraphics pg) {
    pg.lights();

    // Cool ambient - dark sci-fi feel (slightly brighter for better visibility)
    pg.ambientLight(45, 50, 60);

    // Main directional light - stronger, more dramatic angle for shadow definition
    pg.directionalLight(180, 170, 160, -0.4, -0.7, -0.5);

    // Fill light - cool blue from the side
    pg.directionalLight(50, 65, 90, 0.5, -0.3, 0.4);

    // Rim light from behind - adds depth and edge definition
    pg.directionalLight(40, 50, 65, 0.3, 0.4, -0.7);

    // Top-down subtle light to highlight horizontal surfaces
    pg.directionalLight(30, 35, 40, 0, -1, 0);
  }

  void drawAtmosphere(PGraphics pg) {
    // Subtle fog/haze overlay
    pg.noStroke();
    pg.fill(25, 30, 40, 30);
    pg.rect(0, 0, pg.width, pg.height);

    // Vignette
    pg.noFill();
    for (int i = 0; i < 20; i++) {
      float alpha = map(i, 0, 20, 0, 40);
      pg.stroke(10, 12, 18, alpha);
      pg.strokeWeight(40);
      float inset = i * 25;
      pg.rect(inset, inset, pg.width - inset * 2, pg.height - inset * 2);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CHUNK GENERATION
  // ═══════════════════════════════════════════════════════════════════════════

  void renderChunk(PGraphics pg, int chunkX, int chunkZ) {
    SciFiChunk chunk = getOrCreateChunk(chunkX, chunkZ);

    float baseX = chunkX * CHUNK_SIZE * TILE_SIZE;
    float baseZ = chunkZ * CHUNK_SIZE * TILE_SIZE;

    pg.pushMatrix();
    pg.translate(baseX, 0, baseZ);

    // Render ground/terrain
    renderTerrain(pg, chunk);

    // Render roads first (on ground)
    renderRoads(pg, chunk);

    // Render buildings
    for (SciFiBuilding building : chunk.buildings) {
      renderBuilding(pg, building);
    }

    // Render vehicles
    for (SciFiVehicle vehicle : chunk.vehicles) {
      renderVehicle(pg, vehicle);
    }

    // Render details
    for (SciFiDetail detail : chunk.details) {
      renderDetail(pg, detail);
    }

    pg.popMatrix();
  }

  void renderTerrain(PGraphics pg, SciFiChunk chunk) {
    pg.noStroke();
    pg.beginShape(TRIANGLES);

    for (int z = 0; z < CHUNK_SIZE - 1; z++) {
      for (int x = 0; x < CHUNK_SIZE - 1; x++) {
        SciFiTile t00 = chunk.tiles[x][z];
        SciFiTile t10 = chunk.tiles[x + 1][z];
        SciFiTile t01 = chunk.tiles[x][z + 1];
        SciFiTile t11 = chunk.tiles[x + 1][z + 1];

        // Audio modulation - more dramatic terrain breathing
        float audioMod = audioPulse * 12 * noise(x * 0.15, z * 0.15);

        float x0 = x * TILE_SIZE;
        float x1 = (x + 1) * TILE_SIZE;
        float z0 = z * TILE_SIZE;
        float z1 = (z + 1) * TILE_SIZE;

        float y00 = -(t00.height + audioMod);
        float y10 = -(t10.height + audioMod);
        float y01 = -(t01.height + audioMod);
        float y11 = -(t11.height + audioMod);

        // Get terrain color based on zone and height
        color tileColor = getTerrainColor(t00.zone, t00.height, x, z);
        pg.fill(tileColor);

        // Calculate normals for proper lighting on terrain faces
        // Triangle 1: (x0,y00,z0), (x1,y10,z0), (x0,y01,z1)
        PVector v1 = new PVector(x1 - x0, y10 - y00, 0);
        PVector v2 = new PVector(0, y01 - y00, z1 - z0);
        PVector n1 = v2.cross(v1).normalize();
        pg.normal(n1.x, n1.y, n1.z);

        // Triangle 1
        pg.vertex(x0, y00, z0);
        pg.vertex(x1, y10, z0);
        pg.vertex(x0, y01, z1);

        // Triangle 2: (x1,y10,z0), (x1,y11,z1), (x0,y01,z1)
        PVector v3 = new PVector(0, y11 - y10, z1 - z0);
        PVector v4 = new PVector(x0 - x1, y01 - y11, 0);
        PVector n2 = v4.cross(v3).normalize();
        pg.normal(n2.x, n2.y, n2.z);

        // Triangle 2
        pg.vertex(x1, y10, z0);
        pg.vertex(x1, y11, z1);
        pg.vertex(x0, y01, z1);
      }
    }
    pg.endShape();
  }

  void renderRoads(PGraphics pg, SciFiChunk chunk) {
    pg.noStroke();

    for (int z = 0; z < CHUNK_SIZE; z++) {
      for (int x = 0; x < CHUNK_SIZE; x++) {
        SciFiTile tile = chunk.tiles[x][z];

        if (tile.hasRoad) {
          float px = x * TILE_SIZE + TILE_SIZE * 0.5;
          float pz = z * TILE_SIZE + TILE_SIZE * 0.5;
          float py = -tile.height - 0.5;

          pg.pushMatrix();
          pg.translate(px, py, pz);

          // Road surface
          pg.fill(asphalt);
          pg.box(TILE_SIZE * 0.9, 0.3, TILE_SIZE * 0.9);

          // Road markings
          if ((x + z) % 4 == 0) {
            pg.fill(accentYellow);
            pg.box(TILE_SIZE * 0.1, 0.5, TILE_SIZE * 0.3);
          }

          pg.popMatrix();
        }
      }
    }
  }

  color getTerrainColor(int zone, float height, int x, int z) {
    float variation = noise(x * 0.3, z * 0.3) * 20 - 10;

    // Height-based brightness variation to emphasize topography
    float heightBrightness = map(height, 0, 100, -15, 15);

    color baseColor;
    switch (zone) {
      case ZONE_MILITARY:
        // Darker valleys, lighter ridges
        float milT = constrain(map(height, 20, 80, 0, 1), 0, 1);
        baseColor = lerpColor(groundDark, groundMid, milT);
        break;
      case ZONE_SPACEPORT:
        baseColor = concrete;
        break;
      case ZONE_INDUSTRIAL:
        float indT = constrain(map(height, 20, 80, 0.2, 0.7), 0, 1);
        baseColor = lerpColor(groundDark, concrete, indT);
        break;
      case ZONE_OUTPOST:
        // Desert gradient from dark valleys to sandy peaks
        float outT = constrain(map(height, 10, 90, 0, 1), 0, 1);
        baseColor = lerpColor(color(80, 70, 60), color(140, 125, 100), outT);
        break;
      case ZONE_MOUNTAIN:
        // More dramatic mountain coloring
        float t = constrain(map(height, 40, 200, 0, 1), 0, 1);
        if (t > 0.7) {
          // Snow caps
          baseColor = lerpColor(metalLight, color(180, 185, 190), (t - 0.7) / 0.3);
        } else {
          baseColor = lerpColor(groundMid, metalLight, t / 0.7);
        }
        break;
      default:
        baseColor = groundMid;
    }

    return color(
      constrain(red(baseColor) + variation + heightBrightness, 0, 255),
      constrain(green(baseColor) + variation + heightBrightness, 0, 255),
      constrain(blue(baseColor) + variation + heightBrightness, 0, 255)
    );
  }

  SciFiChunk getOrCreateChunk(int cx, int cz) {
    long key = ((long)cx << 32) | (cz & 0xFFFFFFFFL);

    if (!chunks.containsKey(key)) {
      chunks.put(key, generateChunk(cx, cz));
    }

    return chunks.get(key);
  }

  SciFiChunk generateChunk(int chunkX, int chunkZ) {
    SciFiChunk chunk = new SciFiChunk();
    chunk.tiles = new SciFiTile[CHUNK_SIZE][CHUNK_SIZE];
    chunk.buildings = new ArrayList<SciFiBuilding>();
    chunk.vehicles = new ArrayList<SciFiVehicle>();
    chunk.details = new ArrayList<SciFiDetail>();

    float worldOffsetX = chunkX * CHUNK_SIZE;
    float worldOffsetZ = chunkZ * CHUNK_SIZE;

    // Determine zone for this chunk
    int chunkZone = getChunkZone(chunkX, chunkZ);

    // Generate tiles
    for (int x = 0; x < CHUNK_SIZE; x++) {
      for (int z = 0; z < CHUNK_SIZE; z++) {
        float worldX = worldOffsetX + x;
        float worldZ = worldOffsetZ + z;

        float height = getTerrainHeight(worldX, worldZ, chunkZone);
        boolean hasRoad = shouldHaveRoad(worldX, worldZ, chunkZone);

        chunk.tiles[x][z] = new SciFiTile(height, chunkZone, hasRoad);
      }
    }

    // Generate buildings based on zone
    generateBuildings(chunk, chunkX, chunkZ, chunkZone);

    // Generate vehicles
    generateVehicles(chunk, chunkX, chunkZ, chunkZone);

    // Generate details
    generateDetails(chunk, chunkX, chunkZ, chunkZone);

    return chunk;
  }

  int getChunkZone(int cx, int cz) {
    float n = noise(cx * 0.15 + zoneSeed, cz * 0.15);
    float n2 = noise(cx * 0.08 + zoneSeed + 100, cz * 0.08);

    // Mountains in certain areas
    if (n2 > 0.7) return ZONE_MOUNTAIN;

    // Zone distribution
    if (n < 0.25) return ZONE_EMPTY;
    if (n < 0.45) return ZONE_OUTPOST;
    if (n < 0.60) return ZONE_INDUSTRIAL;
    if (n < 0.80) return ZONE_MILITARY;
    return ZONE_SPACEPORT;
  }

  float getTerrainHeight(float x, float z, int zone) {
    float baseHeight = 0;

    // Multi-octave noise for terrain
    float freq1 = 0.008;
    float freq2 = 0.025;
    float freq3 = 0.06;

    float h = noise(x * freq1 + terrainSeed, z * freq1) * 1.0;
    h += noise(x * freq2 + terrainSeed + 50, z * freq2) * 0.4;
    h += noise(x * freq3 + terrainSeed + 100, z * freq3) * 0.15;

    h = h / 1.55;

    // Zone-specific terrain modifications - increased for more dramatic height variation
    switch (zone) {
      case ZONE_MOUNTAIN:
        baseHeight = pow(h, 1.3) * 250 + 40;  // More dramatic mountains
        break;
      case ZONE_SPACEPORT:
        // Flatter landing areas but still some variation
        baseHeight = 15 + h * 25;
        break;
      case ZONE_MILITARY:
      case ZONE_INDUSTRIAL:
        baseHeight = 20 + h * 60;  // More rolling terrain
        break;
      case ZONE_OUTPOST:
        baseHeight = 10 + h * 80;  // Desert dunes/hills
        break;
      default:
        baseHeight = h * 50;
    }

    return baseHeight;
  }

  boolean shouldHaveRoad(float x, float z, int zone) {
    if (zone == ZONE_MOUNTAIN || zone == ZONE_EMPTY) return false;

    // Grid-based roads
    float roadFreq = (zone == ZONE_SPACEPORT) ? 4 : 6;
    boolean onGridX = abs(x % roadFreq) < 1;
    boolean onGridZ = abs(z % roadFreq) < 1;

    return onGridX || onGridZ;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BUILDING GENERATION
  // ═══════════════════════════════════════════════════════════════════════════

  void generateBuildings(SciFiChunk chunk, int chunkX, int chunkZ, int zone) {
    if (zone == ZONE_EMPTY || zone == ZONE_MOUNTAIN) return;

    float worldOffsetX = chunkX * CHUNK_SIZE;
    float worldOffsetZ = chunkZ * CHUNK_SIZE;

    // Different building patterns per zone
    int buildingAttempts = (zone == ZONE_SPACEPORT) ? 8 :
                           (zone == ZONE_MILITARY) ? 6 : 4;

    for (int i = 0; i < buildingAttempts; i++) {
      float localX = noise(worldOffsetX * 0.1 + i + buildingSeed, worldOffsetZ * 0.1) * (CHUNK_SIZE - 4) + 2;
      float localZ = noise(worldOffsetX * 0.1, worldOffsetZ * 0.1 + i + buildingSeed) * (CHUNK_SIZE - 4) + 2;

      float buildNoise = noise(localX + worldOffsetX + buildingSeed, localZ + worldOffsetZ);

      if (buildNoise > BUILDING_DENSITY) {
        int tileX = (int)localX;
        int tileZ = (int)localZ;

        if (tileX >= 0 && tileX < CHUNK_SIZE && tileZ >= 0 && tileZ < CHUNK_SIZE) {
          SciFiTile tile = chunk.tiles[tileX][tileZ];

          if (!tile.hasRoad) {
            int buildingType = getBuildingTypeForZone(zone, buildNoise);
            int variant = (int)(buildNoise * 10) % 4;
            float rotation = ((int)(buildNoise * 8) % 4) * HALF_PI;
            float scale = 0.8 + buildNoise * 0.5;

            chunk.buildings.add(new SciFiBuilding(
              localX * TILE_SIZE,
              localZ * TILE_SIZE,
              tile.height,
              buildingType,
              variant,
              rotation,
              scale,
              zone
            ));
          }
        }
      }
    }
  }

  int getBuildingTypeForZone(int zone, float noise) {
    switch (zone) {
      case ZONE_MILITARY:
        if (noise > 0.85) return BUILD_RADAR;
        if (noise > 0.75) return BUILD_TOWER;
        if (noise > 0.60) return BUILD_HANGAR;
        if (noise > 0.50) return BUILD_BARRACKS;
        return BUILD_MODULE;

      case ZONE_SPACEPORT:
        if (noise > 0.85) return BUILD_TOWER;
        if (noise > 0.70) return BUILD_HANGAR;
        if (noise > 0.55) return BUILD_PLATFORM;
        if (noise > 0.45) return BUILD_DOME;
        return BUILD_MODULE;

      case ZONE_INDUSTRIAL:
        if (noise > 0.80) return BUILD_SILO;
        if (noise > 0.65) return BUILD_GENERATOR;
        if (noise > 0.50) return BUILD_HANGAR;
        return BUILD_MODULE;

      case ZONE_OUTPOST:
        if (noise > 0.80) return BUILD_ANTENNA;
        if (noise > 0.65) return BUILD_DOME;
        if (noise > 0.50) return BUILD_MODULE;
        return BUILD_BARRACKS;

      default:
        return BUILD_MODULE;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // VEHICLE GENERATION
  // ═══════════════════════════════════════════════════════════════════════════

  void generateVehicles(SciFiChunk chunk, int chunkX, int chunkZ, int zone) {
    if (zone == ZONE_EMPTY || zone == ZONE_MOUNTAIN) return;

    float worldOffsetX = chunkX * CHUNK_SIZE;
    float worldOffsetZ = chunkZ * CHUNK_SIZE;

    int vehicleAttempts = (zone == ZONE_SPACEPORT) ? 4 : 2;

    for (int i = 0; i < vehicleAttempts; i++) {
      float localX = noise(worldOffsetX * 0.15 + i * 3.7 + detailSeed, worldOffsetZ * 0.15) * (CHUNK_SIZE - 2) + 1;
      float localZ = noise(worldOffsetX * 0.15, worldOffsetZ * 0.15 + i * 3.7 + detailSeed) * (CHUNK_SIZE - 2) + 1;

      float vNoise = noise(localX + worldOffsetX + detailSeed + 200, localZ + worldOffsetZ);

      if (vNoise > VEHICLE_DENSITY) {
        int tileX = (int)localX;
        int tileZ = (int)localZ;

        if (tileX >= 0 && tileX < CHUNK_SIZE && tileZ >= 0 && tileZ < CHUNK_SIZE) {
          SciFiTile tile = chunk.tiles[tileX][tileZ];

          int vehicleType = getVehicleTypeForZone(zone, vNoise);
          float rotation = vNoise * TWO_PI;
          float scale = 0.7 + vNoise * 0.5;

          chunk.vehicles.add(new SciFiVehicle(
            localX * TILE_SIZE,
            localZ * TILE_SIZE,
            tile.height,
            vehicleType,
            rotation,
            scale
          ));
        }
      }
    }
  }

  int getVehicleTypeForZone(int zone, float noise) {
    // 0=fighter, 1=transport, 2=heavy ship, 3=ground vehicle, 4=drone
    switch (zone) {
      case ZONE_SPACEPORT:
        if (noise > 0.95) return 2; // Heavy ship
        if (noise > 0.90) return 1; // Transport
        return 0; // Fighter
      case ZONE_MILITARY:
        if (noise > 0.92) return 2;
        if (noise > 0.88) return 0;
        return 3; // Ground vehicle
      default:
        return (noise > 0.92) ? 1 : 3;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // DETAIL GENERATION
  // ═══════════════════════════════════════════════════════════════════════════

  void generateDetails(SciFiChunk chunk, int chunkX, int chunkZ, int zone) {
    float worldOffsetX = chunkX * CHUNK_SIZE;
    float worldOffsetZ = chunkZ * CHUNK_SIZE;

    for (int x = 0; x < CHUNK_SIZE; x++) {
      for (int z = 0; z < CHUNK_SIZE; z++) {
        float worldX = worldOffsetX + x;
        float worldZ = worldOffsetZ + z;

        float dNoise = noise(worldX * 0.4 + detailSeed, worldZ * 0.4);

        if (dNoise > DETAIL_DENSITY) {
          SciFiTile tile = chunk.tiles[x][z];

          if (!tile.hasRoad) {
            int detailType = getDetailType(zone, dNoise);
            float rotation = dNoise * TWO_PI;
            float scale = 0.5 + dNoise * 0.8;

            chunk.details.add(new SciFiDetail(
              x * TILE_SIZE + TILE_SIZE * 0.5,
              z * TILE_SIZE + TILE_SIZE * 0.5,
              tile.height,
              detailType,
              rotation,
              scale
            ));
          }
        }
      }
    }
  }

  int getDetailType(int zone, float noise) {
    // 0=cargo, 1=light, 2=pipe, 3=small antenna, 4=crate stack, 5=barrier, 6=dish small
    if (noise > 0.90) return 6; // Small dish
    if (noise > 0.85) return 3; // Small antenna
    if (noise > 0.78) return 1; // Light
    if (noise > 0.72) return 4; // Crate stack
    if (noise > 0.66) return 5; // Barrier
    return 0; // Cargo container
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BUILDING RENDERING
  // ═══════════════════════════════════════════════════════════════════════════

  void renderBuilding(PGraphics pg, SciFiBuilding b) {
    pg.pushMatrix();
    pg.translate(b.x, -b.groundHeight, b.z);
    pg.rotateY(b.rotation);
    pg.scale(b.scale);

    color[] zoneColors = getZoneColors(b.zone);

    switch (b.type) {
      case BUILD_HANGAR:
        drawHangar(pg, b.variant, zoneColors);
        break;
      case BUILD_TOWER:
        drawTower(pg, b.variant, zoneColors);
        break;
      case BUILD_DOME:
        drawDome(pg, b.variant, zoneColors);
        break;
      case BUILD_MODULE:
        drawModule(pg, b.variant, zoneColors);
        break;
      case BUILD_BARRACKS:
        drawBarracks(pg, b.variant, zoneColors);
        break;
      case BUILD_RADAR:
        drawRadar(pg, b.variant, zoneColors);
        break;
      case BUILD_SILO:
        drawSilo(pg, b.variant, zoneColors);
        break;
      case BUILD_PLATFORM:
        drawPlatform(pg, b.variant, zoneColors);
        break;
      case BUILD_GENERATOR:
        drawGenerator(pg, b.variant, zoneColors);
        break;
      case BUILD_ANTENNA:
        drawAntenna(pg, b.variant, zoneColors);
        break;
    }

    pg.popMatrix();
  }

  color[] getZoneColors(int zone) {
    switch (zone) {
      case ZONE_MILITARY: return militaryColors;
      case ZONE_INDUSTRIAL: return industrialColors;
      case ZONE_SPACEPORT: return spaceportColors;
      case ZONE_OUTPOST: return outpostColors;
      default: return spaceportColors;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Hangar - Large curved roof building
  // ─────────────────────────────────────────────────────────────────────────────
  void drawHangar(PGraphics pg, int variant, color[] colors) {
    float w = 80 + variant * 15;
    float h = 35 + variant * 8;
    float d = 60 + variant * 10;

    pg.noStroke();

    // Base foundation
    pg.fill(colors[0]);
    drawBox(pg, 0, -2, 0, w + 10, 4, d + 10);

    // Main structure
    pg.fill(colors[1]);
    drawBox(pg, 0, -h/2 - 4, 0, w, h, d);

    // Curved roof (approximated with trapezoid)
    pg.fill(colors[2]);
    pg.pushMatrix();
    pg.translate(0, -h - 4, 0);
    drawWedgeRoof(pg, w * 1.1, 15, d);
    pg.popMatrix();

    // Door opening (dark)
    pg.fill(20, 22, 28);
    drawBox(pg, 0, -h/2, d/2 + 0.5, w * 0.7, h * 0.85, 1);

    // Door frame accent
    pg.fill(accentOrange);
    drawBox(pg, -w * 0.35 - 2, -h/2, d/2 + 1, 3, h * 0.85, 2);
    drawBox(pg, w * 0.35 + 2, -h/2, d/2 + 1, 3, h * 0.85, 2);
    drawBox(pg, 0, -h + 2, d/2 + 1, w * 0.7 + 6, 4, 2);

    // Side details
    for (int i = 0; i < 3; i++) {
      float zOff = -d/3 + i * d/3;
      pg.fill(colors[3]);
      drawBox(pg, w/2 + 1, -h * 0.3, zOff, 2, h * 0.4, 8);
      drawBox(pg, -w/2 - 1, -h * 0.3, zOff, 2, h * 0.4, 8);
    }

    // Roof lights
    float glow = audioGlow * 0.5;
    setEmissive(pg, glowOrange, glow * 80);
    pg.fill(glowOrange);
    for (int i = 0; i < 4; i++) {
      float zOff = -d/2 + 10 + i * d/3;
      drawBox(pg, 0, -h - 18, zOff, 4, 2, 4);
    }
    pg.emissive(0);
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Control Tower - Tall with observation deck
  // ─────────────────────────────────────────────────────────────────────────────
  void drawTower(PGraphics pg, int variant, color[] colors) {
    float baseSize = 20 + variant * 4;
    float height = 80 + variant * 25;

    pg.noStroke();

    // Foundation
    pg.fill(colors[0]);
    drawBox(pg, 0, -3, 0, baseSize + 10, 6, baseSize + 10);

    // Main shaft
    pg.fill(colors[1]);
    drawBox(pg, 0, -height/2 - 6, 0, baseSize, height, baseSize);

    // Observation deck (wider top)
    pg.fill(colors[2]);
    float deckHeight = 20;
    drawBox(pg, 0, -height - 6 - deckHeight/2, 0, baseSize + 15, deckHeight, baseSize + 15);

    // Windows on deck
    pg.fill(30, 35, 45);
    for (int i = 0; i < 4; i++) {
      pg.pushMatrix();
      pg.rotateY(i * HALF_PI);
      drawBox(pg, 0, -height - 6 - deckHeight/2, (baseSize + 15)/2 + 0.5, baseSize + 10, deckHeight * 0.6, 1);
      pg.popMatrix();
    }

    // Antenna on top
    pg.fill(metalMid);
    drawBox(pg, 0, -height - 6 - deckHeight - 15, 0, 2, 30, 2);

    // Blinking light
    float blink = (sin(worldTime * 4) + 1) * 0.5;
    setEmissive(pg, glowRed, (blink + audioGlow) * 100);
    pg.fill(glowRed);
    drawBox(pg, 0, -height - 6 - deckHeight - 32, 0, 4, 4, 4);
    pg.emissive(0);

    // Number decal
    pg.fill(colors[3]);
    drawBox(pg, baseSize/2 + 0.5, -height * 0.7, 0, 0.5, 12, 8);
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Dome - Geodesic dome structure
  // ─────────────────────────────────────────────────────────────────────────────
  void drawDome(PGraphics pg, int variant, color[] colors) {
    float radius = 25 + variant * 8;

    pg.noStroke();

    // Base platform
    pg.fill(colors[0]);
    drawCylinder(pg, 0, -2, 0, radius + 5, 4, 12);

    // Dome (hemisphere approximation)
    pg.fill(colors[1]);
    drawHemisphere(pg, 0, -4, 0, radius, 8, 6);

    // Support ring
    pg.fill(colors[2]);
    drawCylinder(pg, 0, -4, 0, radius + 2, 3, 12);

    // Top cap
    pg.fill(colors[3]);
    drawCylinder(pg, 0, -4 - radius + 3, 0, 8, 6, 8);

    // Entrance
    pg.fill(30, 32, 38);
    pg.pushMatrix();
    pg.translate(0, -8, radius - 2);
    drawBox(pg, 0, 0, 0, 15, 16, 6);
    pg.popMatrix();

    // Glow ring
    float glow = audioGlow * 0.6;
    setEmissive(pg, glowTeal, glow * 100);
    pg.fill(glowTeal);
    drawCylinder(pg, 0, -6, 0, radius + 3, 1, 16);
    pg.emissive(0);
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Module - Modular box building
  // ─────────────────────────────────────────────────────────────────────────────
  void drawModule(PGraphics pg, int variant, color[] colors) {
    float w = 30 + variant * 10;
    float h = 15 + variant * 5;
    float d = 25 + variant * 8;

    pg.noStroke();

    // Main box
    pg.fill(colors[1]);
    drawBox(pg, 0, -h/2, 0, w, h, d);

    // Roof detail
    pg.fill(colors[2]);
    drawBox(pg, 0, -h - 1, 0, w - 4, 2, d - 4);

    // Door
    pg.fill(colors[0]);
    drawBox(pg, 0, -h * 0.4, d/2 + 0.5, 8, h * 0.7, 1);

    // Windows
    pg.fill(40, 50, 65);
    float winGlow = audioGlow * 0.3;
    setEmissive(pg, glowBlue, winGlow * 60);
    drawBox(pg, w/4, -h * 0.6, d/2 + 0.5, 5, 4, 0.5);
    drawBox(pg, -w/4, -h * 0.6, d/2 + 0.5, 5, 4, 0.5);
    pg.emissive(0);

    // AC unit or vent
    pg.fill(metalDark);
    drawBox(pg, w/3, -h - 4, -d/4, 8, 6, 8);

    // Accent stripe
    pg.fill(accentTeal);
    drawBox(pg, 0, -h + 1, d/2 + 0.5, w + 1, 2, 0.5);
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Barracks - Long low building
  // ─────────────────────────────────────────────────────────────────────────────
  void drawBarracks(PGraphics pg, int variant, color[] colors) {
    float w = 20 + variant * 5;
    float h = 12 + variant * 3;
    float d = 50 + variant * 15;

    pg.noStroke();

    // Main structure
    pg.fill(colors[1]);
    drawBox(pg, 0, -h/2, 0, w, h, d);

    // Sloped roof
    pg.fill(colors[2]);
    pg.pushMatrix();
    pg.translate(0, -h, 0);
    drawWedgeRoof(pg, w + 2, 5, d + 2);
    pg.popMatrix();

    // Windows along the side
    pg.fill(35, 42, 55);
    int numWindows = 4 + variant;
    for (int i = 0; i < numWindows; i++) {
      float zOff = -d/2 + 8 + i * (d - 16) / (numWindows - 1);
      drawBox(pg, w/2 + 0.5, -h * 0.5, zOff, 0.5, 4, 5);
      drawBox(pg, -w/2 - 0.5, -h * 0.5, zOff, 0.5, 4, 5);
    }

    // Door
    pg.fill(colors[0]);
    drawBox(pg, 0, -h * 0.35, d/2 + 0.5, 6, h * 0.6, 1);

    // Number plate
    pg.fill(accentYellow);
    drawBox(pg, 0, -h * 0.8, d/2 + 0.5, 4, 3, 0.5);
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Radar - Rotating dish
  // ─────────────────────────────────────────────────────────────────────────────
  void drawRadar(PGraphics pg, int variant, color[] colors) {
    float dishSize = 30 + variant * 10;
    float towerHeight = 25 + variant * 10;

    pg.noStroke();

    // Base
    pg.fill(colors[0]);
    drawCylinder(pg, 0, -3, 0, 15, 6, 8);

    // Tower
    pg.fill(colors[1]);
    drawBox(pg, 0, -towerHeight/2 - 6, 0, 8, towerHeight, 8);

    // Rotating platform
    pg.pushMatrix();
    pg.translate(0, -towerHeight - 8, 0);
    pg.rotateY(worldTime * 0.5);

    // Dish support arm
    pg.fill(colors[2]);
    drawBox(pg, dishSize/2, 0, 0, dishSize, 3, 4);

    // Dish
    pg.fill(metalLight);
    pg.pushMatrix();
    pg.translate(dishSize, 0, 0);
    pg.rotateZ(-QUARTER_PI);
    drawDishShape(pg, dishSize * 0.8, 8);
    pg.popMatrix();

    pg.popMatrix();

    // Status light
    float blink = (sin(worldTime * 3) + 1) * 0.5;
    setEmissive(pg, glowRed, blink * 150);
    pg.fill(glowRed);
    drawBox(pg, 0, -towerHeight - 12, 0, 3, 3, 3);
    pg.emissive(0);
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Silo - Cylindrical storage
  // ─────────────────────────────────────────────────────────────────────────────
  void drawSilo(PGraphics pg, int variant, color[] colors) {
    float radius = 15 + variant * 5;
    float height = 50 + variant * 15;

    pg.noStroke();

    // Main cylinder
    pg.fill(colors[1]);
    drawCylinder(pg, 0, -height/2, 0, radius, height, 12);

    // Top dome
    pg.fill(colors[2]);
    drawHemisphere(pg, 0, -height, 0, radius, 6, 4);

    // Base ring
    pg.fill(colors[0]);
    drawCylinder(pg, 0, -3, 0, radius + 3, 6, 12);

    // Bands
    pg.fill(colors[3]);
    for (int i = 1; i < 4; i++) {
      drawCylinder(pg, 0, -height * i / 4, 0, radius + 1, 2, 12);
    }

    // Ladder
    pg.fill(metalDark);
    drawBox(pg, radius + 1, -height/2, 0, 2, height, 3);

    // Pipes at base
    pg.fill(metalMid);
    drawCylinder(pg, radius + 8, -5, 0, 3, 10, 6);
    drawBox(pg, radius + 4, -8, 0, 8, 2, 2);
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Platform - Landing pad
  // ─────────────────────────────────────────────────────────────────────────────
  void drawPlatform(PGraphics pg, int variant, color[] colors) {
    float size = 50 + variant * 15;

    pg.noStroke();

    // Main platform
    pg.fill(concrete);
    drawBox(pg, 0, -2, 0, size, 4, size);

    // Landing circle markings
    pg.fill(accentYellow);
    drawCylinder(pg, 0, -0.1, 0, size * 0.35, 0.5, 16);
    pg.fill(concrete);
    drawCylinder(pg, 0, -0.2, 0, size * 0.32, 0.6, 16);

    // Center H marking
    pg.fill(accentYellow);
    drawBox(pg, 0, -0.1, 0, size * 0.15, 0.5, size * 0.02);
    drawBox(pg, -size * 0.07, -0.1, 0, size * 0.02, 0.5, size * 0.2);
    drawBox(pg, size * 0.07, -0.1, 0, size * 0.02, 0.5, size * 0.2);

    // Corner lights
    float glow = (sin(worldTime * 2) + 1) * 0.3 + audioGlow * 0.4;
    setEmissive(pg, glowTeal, glow * 100);
    pg.fill(glowTeal);
    float offset = size/2 - 3;
    drawBox(pg, -offset, -5, -offset, 3, 6, 3);
    drawBox(pg, offset, -5, -offset, 3, 6, 3);
    drawBox(pg, -offset, -5, offset, 3, 6, 3);
    drawBox(pg, offset, -5, offset, 3, 6, 3);
    pg.emissive(0);

    // Edge markings
    pg.fill(accentRed);
    drawBox(pg, 0, -0.1, size/2 - 2, size - 8, 0.5, 2);
    drawBox(pg, 0, -0.1, -size/2 + 2, size - 8, 0.5, 2);
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Generator - Power generation building
  // ─────────────────────────────────────────────────────────────────────────────
  void drawGenerator(PGraphics pg, int variant, color[] colors) {
    float w = 35 + variant * 8;
    float h = 20 + variant * 5;
    float d = 25 + variant * 6;

    pg.noStroke();

    // Main housing
    pg.fill(colors[1]);
    drawBox(pg, 0, -h/2, 0, w, h, d);

    // Vents on top
    pg.fill(metalDark);
    for (int i = 0; i < 3; i++) {
      float xOff = -w/3 + i * w/3;
      drawBox(pg, xOff, -h - 3, 0, 8, 6, d * 0.6);
    }

    // Exhaust pipes
    pg.fill(metalMid);
    drawCylinder(pg, w/2 + 5, -h/2, d/4, 4, h, 6);
    drawCylinder(pg, w/2 + 5, -h/2, -d/4, 4, h, 6);

    // Steam/exhaust effect
    float steam = (sin(worldTime * 2) + 1) * 0.5;
    pg.fill(150, 155, 160, 100 * steam);
    drawCylinder(pg, w/2 + 5, -h - 5, d/4, 6 + steam * 4, 10, 6);

    // Control panel (glowing)
    float panelGlow = audioGlow * 0.5 + 0.3;
    setEmissive(pg, glowBlue, panelGlow * 80);
    pg.fill(glowBlue);
    drawBox(pg, 0, -h * 0.6, d/2 + 0.5, 10, 6, 1);
    pg.emissive(0);

    // Warning stripes
    pg.fill(accentYellow);
    drawBox(pg, -w/2 - 0.5, -h/2, 0, 0.5, h * 0.8, 3);
    pg.fill(30);
    drawBox(pg, -w/2 - 0.5, -h/2 + 3, 0, 0.6, 3, 3.1);
    drawBox(pg, -w/2 - 0.5, -h/2 - 3, 0, 0.6, 3, 3.1);
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Antenna - Communication array
  // ─────────────────────────────────────────────────────────────────────────────
  void drawAntenna(PGraphics pg, int variant, color[] colors) {
    float height = 60 + variant * 20;

    pg.noStroke();

    // Base structure
    pg.fill(colors[0]);
    drawBox(pg, 0, -5, 0, 12, 10, 12);

    // Main mast (tapered)
    pg.fill(metalMid);
    drawBox(pg, 0, -height/2 - 10, 0, 4, height, 4);

    // Cross beams
    for (int i = 1; i <= 3; i++) {
      float y = -10 - height * i / 4;
      float armLen = 15 - i * 3;
      pg.fill(metalDark);
      drawBox(pg, 0, y, 0, armLen * 2, 2, 2);
      drawBox(pg, 0, y, 0, 2, 2, armLen * 2);
    }

    // Dishes on arms
    pg.fill(metalLight);
    pg.pushMatrix();
    pg.translate(12, -10 - height/4, 0);
    pg.rotateZ(-QUARTER_PI * 0.7);
    drawDishShape(pg, 10, 6);
    pg.popMatrix();

    pg.pushMatrix();
    pg.translate(-12, -10 - height/4, 0);
    pg.rotateZ(QUARTER_PI * 0.7);
    drawDishShape(pg, 10, 6);
    pg.popMatrix();

    // Top beacon
    float blink = (sin(worldTime * 5) + 1) * 0.5;
    setEmissive(pg, glowRed, blink * 200);
    pg.fill(glowRed);
    drawBox(pg, 0, -height - 12, 0, 3, 3, 3);
    pg.emissive(0);

    // Equipment box
    pg.fill(colors[1]);
    drawBox(pg, 8, -8, 8, 6, 6, 6);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // VEHICLE RENDERING
  // ═══════════════════════════════════════════════════════════════════════════

  void renderVehicle(PGraphics pg, SciFiVehicle v) {
    pg.pushMatrix();
    pg.translate(v.x, -v.groundHeight - 2, v.z);
    pg.rotateY(v.rotation);
    pg.scale(v.scale);

    switch (v.type) {
      case 0: drawFighter(pg); break;
      case 1: drawTransport(pg); break;
      case 2: drawHeavyShip(pg); break;
      case 3: drawGroundVehicle(pg); break;
      case 4: drawDrone(pg); break;
    }

    pg.popMatrix();
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Fighter - Small sleek spacecraft
  // ─────────────────────────────────────────────────────────────────────────────
  void drawFighter(PGraphics pg) {
    pg.noStroke();

    // Fuselage
    pg.fill(metalMid);
    drawBox(pg, 0, -5, 0, 8, 6, 30);

    // Nose cone (tapered)
    pg.fill(metalLight);
    pg.pushMatrix();
    pg.translate(0, -5, 18);
    pg.rotateX(HALF_PI);
    drawCone(pg, 0, 0, 0, 4, 12, 6);
    pg.popMatrix();

    // Wings
    pg.fill(metalDark);
    drawBox(pg, -18, -4, -5, 30, 2, 12);
    drawBox(pg, 18, -4, -5, 30, 2, 12);

    // Wing tips (angled down)
    pg.pushMatrix();
    pg.translate(-32, -2, -5);
    pg.rotateZ(radians(20));
    drawBox(pg, 0, 0, 0, 8, 2, 8);
    pg.popMatrix();

    pg.pushMatrix();
    pg.translate(32, -2, -5);
    pg.rotateZ(radians(-20));
    drawBox(pg, 0, 0, 0, 8, 2, 8);
    pg.popMatrix();

    // Cockpit
    pg.fill(30, 40, 60);
    drawBox(pg, 0, -9, 8, 5, 4, 8);

    // Engines
    pg.fill(metalDark);
    drawCylinder(pg, -5, -5, -18, 3, 8, 6);
    drawCylinder(pg, 5, -5, -18, 3, 8, 6);

    // Engine glow
    float glow = 0.5 + audioBass * 0.5;
    setEmissive(pg, glowOrange, glow * 150);
    pg.fill(glowOrange);
    drawCylinder(pg, -5, -5, -20, 2, 3, 6);
    drawCylinder(pg, 5, -5, -20, 2, 3, 6);
    pg.emissive(0);

    // Landing gear (if on ground)
    pg.fill(metalDark);
    drawBox(pg, 0, 0, 10, 2, 5, 2);
    drawBox(pg, -8, 0, -8, 2, 5, 2);
    drawBox(pg, 8, 0, -8, 2, 5, 2);
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Transport - Medium cargo ship
  // ─────────────────────────────────────────────────────────────────────────────
  void drawTransport(PGraphics pg) {
    pg.noStroke();

    // Main body
    pg.fill(metalMid);
    drawBox(pg, 0, -12, 0, 20, 16, 45);

    // Cockpit section
    pg.fill(metalLight);
    drawBox(pg, 0, -18, 20, 14, 8, 12);

    // Windows
    pg.fill(30, 40, 55);
    drawBox(pg, 0, -18, 26.5, 10, 5, 1);

    // Cargo bay door
    pg.fill(metalDark);
    drawBox(pg, 0, -8, -23, 16, 12, 2);

    // Wings (stubby)
    pg.fill(metalDark);
    drawBox(pg, -20, -10, -5, 22, 3, 18);
    drawBox(pg, 20, -10, -5, 22, 3, 18);

    // Engines (4 total)
    pg.fill(metalMid);
    drawCylinder(pg, -25, -8, -15, 4, 12, 6);
    drawCylinder(pg, 25, -8, -15, 4, 12, 6);
    drawCylinder(pg, -15, -8, -15, 3, 10, 6);
    drawCylinder(pg, 15, -8, -15, 3, 10, 6);

    // Engine glow
    float glow = 0.4 + audioBass * 0.4;
    setEmissive(pg, glowTeal, glow * 120);
    pg.fill(glowTeal);
    drawCylinder(pg, -25, -8, -20, 3, 3, 6);
    drawCylinder(pg, 25, -8, -20, 3, 3, 6);
    pg.emissive(0);

    // Landing struts
    pg.fill(metalDark);
    drawBox(pg, -12, 0, 10, 3, 8, 3);
    drawBox(pg, 12, 0, 10, 3, 8, 3);
    drawBox(pg, -12, 0, -15, 3, 8, 3);
    drawBox(pg, 12, 0, -15, 3, 8, 3);

    // Accent stripe
    pg.fill(accentOrange);
    drawBox(pg, 0, -20, 0, 20.5, 1, 45.5);
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Heavy Ship - Large freighter/military vessel
  // ─────────────────────────────────────────────────────────────────────────────
  void drawHeavyShip(PGraphics pg) {
    pg.noStroke();

    // Main hull
    pg.fill(metalDark);
    drawBox(pg, 0, -20, 0, 35, 28, 80);

    // Bridge superstructure
    pg.fill(metalMid);
    drawBox(pg, 0, -38, 25, 20, 14, 25);

    // Bridge windows
    pg.fill(30, 38, 50);
    drawBox(pg, 0, -38, 38, 16, 8, 1);

    // Lower hull extension
    pg.fill(metalDark);
    drawBox(pg, 0, -8, -20, 30, 12, 35);

    // Engine block
    pg.fill(metalMid);
    drawBox(pg, 0, -18, -45, 28, 20, 15);

    // Large engines
    pg.fill(metalDark);
    drawCylinder(pg, -10, -18, -55, 6, 18, 8);
    drawCylinder(pg, 10, -18, -55, 6, 18, 8);
    drawCylinder(pg, 0, -18, -55, 8, 18, 8);

    // Engine glow
    float glow = 0.5 + audioBass * 0.5;
    setEmissive(pg, glowOrange, glow * 180);
    pg.fill(glowOrange);
    drawCylinder(pg, -10, -18, -60, 5, 5, 8);
    drawCylinder(pg, 10, -18, -60, 5, 5, 8);
    drawCylinder(pg, 0, -18, -60, 7, 5, 8);
    pg.emissive(0);

    // Cargo pods
    pg.fill(metalMid);
    drawBox(pg, -22, -15, 0, 12, 18, 40);
    drawBox(pg, 22, -15, 0, 12, 18, 40);

    // Landing gear (heavy duty)
    pg.fill(metalDark);
    drawBox(pg, -15, 0, 20, 6, 12, 6);
    drawBox(pg, 15, 0, 20, 6, 12, 6);
    drawBox(pg, -15, 0, -25, 6, 12, 6);
    drawBox(pg, 15, 0, -25, 6, 12, 6);

    // Navigation lights
    setEmissive(pg, glowRed, 100);
    pg.fill(glowRed);
    drawBox(pg, -18, -35, 25, 2, 2, 2);
    pg.emissive(0);

    setEmissive(pg, accentTeal, 100);
    pg.fill(accentTeal);
    drawBox(pg, 18, -35, 25, 2, 2, 2);
    pg.emissive(0);
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Ground Vehicle - Military/utility vehicle
  // ─────────────────────────────────────────────────────────────────────────────
  void drawGroundVehicle(PGraphics pg) {
    pg.noStroke();

    // Main body
    pg.fill(militaryColors[0]);
    drawBox(pg, 0, -6, 0, 14, 8, 24);

    // Cabin
    pg.fill(militaryColors[1]);
    drawBox(pg, 0, -12, 6, 12, 6, 10);

    // Windshield
    pg.fill(30, 35, 45);
    drawBox(pg, 0, -12, 11.5, 10, 4, 1);

    // Bed/cargo area
    pg.fill(militaryColors[2]);
    drawBox(pg, 0, -8, -8, 13, 4, 12);

    // Wheels (6 wheel)
    pg.fill(25, 25, 28);
    // Front
    drawCylinder(pg, -9, -2, 8, 4, 4, 8);
    drawCylinder(pg, 9, -2, 8, 4, 4, 8);
    // Middle
    drawCylinder(pg, -9, -2, -2, 4, 4, 8);
    drawCylinder(pg, 9, -2, -2, 4, 4, 8);
    // Rear
    drawCylinder(pg, -9, -2, -10, 4, 4, 8);
    drawCylinder(pg, 9, -2, -10, 4, 4, 8);

    // Roof equipment
    pg.fill(metalMid);
    drawBox(pg, 0, -16, 6, 4, 2, 4);

    // Headlights
    float glow = 0.3 + audioGlow * 0.3;
    setEmissive(pg, glowOrange, glow * 80);
    pg.fill(accentYellow);
    drawBox(pg, -5, -8, 12.5, 2, 2, 1);
    drawBox(pg, 5, -8, 12.5, 2, 2, 1);
    pg.emissive(0);
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Drone - Small hovering unit
  // ─────────────────────────────────────────────────────────────────────────────
  void drawDrone(PGraphics pg) {
    // Hover animation
    float hover = sin(worldTime * 3) * 2;
    pg.translate(0, -8 + hover, 0);

    pg.noStroke();

    // Main body
    pg.fill(metalMid);
    drawBox(pg, 0, 0, 0, 10, 4, 10);

    // Rotors (4)
    pg.fill(metalDark);
    float rotorSpin = worldTime * 20;

    float armLen = 12;
    for (int i = 0; i < 4; i++) {
      float angle = i * HALF_PI + QUARTER_PI;
      float ax = cos(angle) * armLen;
      float az = sin(angle) * armLen;

      // Arm
      drawBox(pg, ax * 0.5, 0, az * 0.5, 2, 2, armLen * 0.7);

      // Rotor housing
      pg.pushMatrix();
      pg.translate(ax, -1, az);
      drawCylinder(pg, 0, 0, 0, 5, 2, 8);

      // Spinning blades (blur effect)
      pg.fill(60, 60, 65, 150);
      pg.rotateY(rotorSpin + i);
      drawBox(pg, 0, -1, 0, 10, 0.5, 2);
      pg.popMatrix();
    }

    // Camera/sensor
    pg.fill(30, 35, 45);
    drawBox(pg, 0, 3, 0, 4, 3, 4);

    // Status light
    float blink = (sin(worldTime * 4) + 1) * 0.5;
    setEmissive(pg, glowTeal, blink * 150);
    pg.fill(glowTeal);
    drawBox(pg, 0, -3, 0, 2, 2, 2);
    pg.emissive(0);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // DETAIL RENDERING
  // ═══════════════════════════════════════════════════════════════════════════

  void renderDetail(PGraphics pg, SciFiDetail d) {
    pg.pushMatrix();
    pg.translate(d.x, -d.groundHeight, d.z);
    pg.rotateY(d.rotation);
    pg.scale(d.scale);

    switch (d.type) {
      case 0: drawCargoContainer(pg); break;
      case 1: drawLight(pg); break;
      case 2: drawPipe(pg); break;
      case 3: drawSmallAntenna(pg); break;
      case 4: drawCrateStack(pg); break;
      case 5: drawBarrier(pg); break;
      case 6: drawSmallDish(pg); break;
    }

    pg.popMatrix();
  }

  void drawCargoContainer(PGraphics pg) {
    pg.noStroke();

    // Main container
    color[] containerColors = {
      color(180, 80, 60),   // Rust red
      color(60, 120, 80),   // Military green
      color(80, 100, 140),  // Blue-gray
      color(150, 140, 100)  // Tan
    };
    color c = containerColors[(int)(noise(worldTime * 0.01) * 4) % 4];
    pg.fill(c);
    drawBox(pg, 0, -6, 0, 12, 12, 25);

    // Ridges
    pg.fill(lerpColor(c, color(0), 0.2));
    for (int i = 0; i < 4; i++) {
      float zOff = -10 + i * 7;
      drawBox(pg, 0, -6, zOff, 12.5, 12.5, 1);
    }

    // Doors
    pg.fill(lerpColor(c, color(0), 0.3));
    drawBox(pg, 0, -6, 13, 10, 10, 0.5);
  }

  void drawLight(PGraphics pg) {
    pg.noStroke();

    // Pole
    pg.fill(metalDark);
    drawBox(pg, 0, -12, 0, 2, 24, 2);

    // Light fixture
    pg.fill(metalMid);
    drawBox(pg, 0, -25, 0, 6, 4, 6);

    // Light (glowing)
    float glow = 0.4 + audioGlow * 0.4;
    setEmissive(pg, glowOrange, glow * 150);
    pg.fill(glowOrange);
    drawBox(pg, 0, -22, 0, 5, 1, 5);
    pg.emissive(0);
  }

  void drawPipe(PGraphics pg) {
    pg.noStroke();

    // Horizontal pipe
    pg.fill(metalMid);
    drawCylinder(pg, 0, -3, 0, 3, 2, 6);
    pg.pushMatrix();
    pg.rotateZ(HALF_PI);
    drawCylinder(pg, 3, 0, 0, 3, 20, 6);
    pg.popMatrix();

    // Support
    pg.fill(metalDark);
    drawBox(pg, 0, -1.5, 0, 4, 3, 4);
  }

  void drawSmallAntenna(PGraphics pg) {
    pg.noStroke();

    // Base
    pg.fill(metalDark);
    drawBox(pg, 0, -2, 0, 4, 4, 4);

    // Mast
    pg.fill(metalMid);
    drawBox(pg, 0, -12, 0, 1.5, 20, 1.5);

    // Cross piece
    drawBox(pg, 0, -20, 0, 8, 1, 1);

    // Tip light
    float blink = (sin(worldTime * 6) + 1) * 0.5;
    setEmissive(pg, glowRed, blink * 100);
    pg.fill(glowRed);
    drawBox(pg, 0, -23, 0, 1.5, 1.5, 1.5);
    pg.emissive(0);
  }

  void drawCrateStack(PGraphics pg) {
    pg.noStroke();

    // Bottom crate
    pg.fill(metalMid);
    drawBox(pg, 0, -4, 0, 8, 8, 8);

    // Top crate (smaller, offset)
    pg.fill(lerpColor(metalMid, accentOrange, 0.2));
    drawBox(pg, 1, -10, -1, 6, 6, 6);

    // Labels
    pg.fill(accentYellow);
    drawBox(pg, 4.5, -4, 0, 0.5, 3, 3);
  }

  void drawBarrier(PGraphics pg) {
    pg.noStroke();

    // Posts
    pg.fill(metalDark);
    drawBox(pg, -6, -5, 0, 2, 10, 2);
    drawBox(pg, 6, -5, 0, 2, 10, 2);

    // Bar
    pg.fill(accentYellow);
    drawBox(pg, 0, -8, 0, 14, 2, 2);

    // Stripes
    pg.fill(30);
    drawBox(pg, -3, -8, 0.5, 2, 2, 2.1);
    drawBox(pg, 3, -8, 0.5, 2, 2, 2.1);
  }

  void drawSmallDish(PGraphics pg) {
    pg.noStroke();

    // Base
    pg.fill(metalDark);
    drawBox(pg, 0, -3, 0, 5, 6, 5);

    // Arm
    pg.fill(metalMid);
    drawBox(pg, 0, -8, 3, 2, 10, 2);

    // Dish
    pg.fill(metalLight);
    pg.pushMatrix();
    pg.translate(0, -12, 6);
    pg.rotateX(-QUARTER_PI * 0.5);
    drawDishShape(pg, 8, 6);
    pg.popMatrix();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PRIMITIVE SHAPE HELPERS
  // ═══════════════════════════════════════════════════════════════════════════

  // Helper: emissive with intensity scaling (Processing doesn't support emissive(color, float))
  void setEmissive(PGraphics pg, color c, float intensity) {
    float scale = constrain(intensity / 255.0, 0, 1);
    pg.emissive(red(c) * scale, green(c) * scale, blue(c) * scale);
  }

  void drawBox(PGraphics pg, float x, float y, float z, float w, float h, float d) {
    pg.pushMatrix();
    pg.translate(x, y, z);
    pg.box(w, h, d);
    pg.popMatrix();
  }

  void drawCylinder(PGraphics pg, float x, float y, float z, float r, float h, int segments) {
    pg.pushMatrix();
    pg.translate(x, y, z);

    // Sides
    pg.beginShape(QUAD_STRIP);
    for (int i = 0; i <= segments; i++) {
      float angle = TWO_PI * i / segments;
      float px = cos(angle) * r;
      float pz = sin(angle) * r;
      pg.vertex(px, h/2, pz);
      pg.vertex(px, -h/2, pz);
    }
    pg.endShape();

    // Top cap
    pg.beginShape(TRIANGLE_FAN);
    pg.vertex(0, -h/2, 0);
    for (int i = 0; i <= segments; i++) {
      float angle = TWO_PI * i / segments;
      pg.vertex(cos(angle) * r, -h/2, sin(angle) * r);
    }
    pg.endShape();

    // Bottom cap
    pg.beginShape(TRIANGLE_FAN);
    pg.vertex(0, h/2, 0);
    for (int i = segments; i >= 0; i--) {
      float angle = TWO_PI * i / segments;
      pg.vertex(cos(angle) * r, h/2, sin(angle) * r);
    }
    pg.endShape();

    pg.popMatrix();
  }

  void drawCone(PGraphics pg, float x, float y, float z, float r, float h, int segments) {
    pg.pushMatrix();
    pg.translate(x, y, z);

    pg.beginShape(TRIANGLE_FAN);
    pg.vertex(0, -h, 0);
    for (int i = 0; i <= segments; i++) {
      float angle = TWO_PI * i / segments;
      pg.vertex(cos(angle) * r, 0, sin(angle) * r);
    }
    pg.endShape();

    // Base
    pg.beginShape(TRIANGLE_FAN);
    pg.vertex(0, 0, 0);
    for (int i = segments; i >= 0; i--) {
      float angle = TWO_PI * i / segments;
      pg.vertex(cos(angle) * r, 0, sin(angle) * r);
    }
    pg.endShape();

    pg.popMatrix();
  }

  void drawHemisphere(PGraphics pg, float x, float y, float z, float r, int rings, int segments) {
    pg.pushMatrix();
    pg.translate(x, y, z);

    for (int i = 0; i < rings; i++) {
      float theta1 = map(i, 0, rings, 0, HALF_PI);
      float theta2 = map(i + 1, 0, rings, 0, HALF_PI);

      float r1 = cos(theta1) * r;
      float y1 = -sin(theta1) * r;
      float r2 = cos(theta2) * r;
      float y2 = -sin(theta2) * r;

      pg.beginShape(QUAD_STRIP);
      for (int j = 0; j <= segments; j++) {
        float phi = TWO_PI * j / segments;
        pg.vertex(cos(phi) * r1, y1, sin(phi) * r1);
        pg.vertex(cos(phi) * r2, y2, sin(phi) * r2);
      }
      pg.endShape();
    }

    pg.popMatrix();
  }

  void drawWedgeRoof(PGraphics pg, float w, float h, float d) {
    // Simple peaked roof
    pg.beginShape(TRIANGLES);

    // Front
    pg.vertex(-w/2, 0, d/2);
    pg.vertex(w/2, 0, d/2);
    pg.vertex(0, -h, d/2);

    // Back
    pg.vertex(-w/2, 0, -d/2);
    pg.vertex(0, -h, -d/2);
    pg.vertex(w/2, 0, -d/2);

    pg.endShape();

    // Sides
    pg.beginShape(QUADS);
    // Left slope
    pg.vertex(-w/2, 0, d/2);
    pg.vertex(0, -h, d/2);
    pg.vertex(0, -h, -d/2);
    pg.vertex(-w/2, 0, -d/2);

    // Right slope
    pg.vertex(w/2, 0, d/2);
    pg.vertex(w/2, 0, -d/2);
    pg.vertex(0, -h, -d/2);
    pg.vertex(0, -h, d/2);
    pg.endShape();
  }

  void drawDishShape(PGraphics pg, float r, int segments) {
    // Parabolic dish approximation
    pg.beginShape(TRIANGLE_FAN);
    pg.vertex(0, 0, 0);
    for (int i = 0; i <= segments; i++) {
      float angle = TWO_PI * i / segments;
      float depth = r * 0.3;
      pg.vertex(cos(angle) * r, depth, sin(angle) * r);
    }
    pg.endShape();

    // Back of dish
    pg.beginShape(TRIANGLE_FAN);
    pg.vertex(0, 2, 0);
    for (int i = segments; i >= 0; i--) {
      float angle = TWO_PI * i / segments;
      float depth = r * 0.3;
      pg.vertex(cos(angle) * r, depth, sin(angle) * r);
    }
    pg.endShape();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CHUNK MANAGEMENT
  // ═══════════════════════════════════════════════════════════════════════════

  void cleanupChunks() {
    int centerChunkX = floor(scrollX / (CHUNK_SIZE * TILE_SIZE));
    int centerChunkZ = floor(scrollZ / (CHUNK_SIZE * TILE_SIZE));
    int keepRadius = VISIBLE_CHUNKS + 2;

    ArrayList<Long> toRemove = new ArrayList<Long>();

    for (Long key : chunks.keySet()) {
      int cx = (int)(key >> 32);
      int cz = (int)(key & 0xFFFFFFFFL);

      if (abs(cx - centerChunkX) > keepRadius || abs(cz - centerChunkZ) > keepRadius) {
        toRemove.add(key);
      }
    }

    for (Long key : toRemove) {
      chunks.remove(key);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // NAME
  // ═══════════════════════════════════════════════════════════════════════════

  public String getName() { return "Isometric Sci-Fi World"; }

  // ═══════════════════════════════════════════════════════════════════════════
  // DATA CLASSES
  // ═══════════════════════════════════════════════════════════════════════════

  class SciFiChunk {
    SciFiTile[][] tiles;
    ArrayList<SciFiBuilding> buildings;
    ArrayList<SciFiVehicle> vehicles;
    ArrayList<SciFiDetail> details;
  }

  class SciFiTile {
    float height;
    int zone;
    boolean hasRoad;

    SciFiTile(float h, int z, boolean road) {
      height = h;
      zone = z;
      hasRoad = road;
    }
  }

  class SciFiBuilding {
    float x, z, groundHeight;
    int type, variant, zone;
    float rotation, scale;

    SciFiBuilding(float x, float z, float gh, int type, int variant, float rot, float scale, int zone) {
      this.x = x;
      this.z = z;
      this.groundHeight = gh;
      this.type = type;
      this.variant = variant;
      this.rotation = rot;
      this.scale = scale;
      this.zone = zone;
    }
  }

  class SciFiVehicle {
    float x, z, groundHeight;
    int type;
    float rotation, scale;

    SciFiVehicle(float x, float z, float gh, int type, float rot, float scale) {
      this.x = x;
      this.z = z;
      this.groundHeight = gh;
      this.type = type;
      this.rotation = rot;
      this.scale = scale;
    }
  }

  class SciFiDetail {
    float x, z, groundHeight;
    int type;
    float rotation, scale;

    SciFiDetail(float x, float z, float gh, int type, float rot, float scale) {
      this.x = x;
      this.z = z;
      this.groundHeight = gh;
      this.type = type;
      this.rotation = rot;
      this.scale = scale;
    }
  }
}
