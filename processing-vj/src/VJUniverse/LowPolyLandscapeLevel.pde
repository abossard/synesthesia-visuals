/**
 * LowPolyLandscapeLevel - Infinite scrolling low-poly isometric landscape
 *
 * Features:
 * - Isometric orthographic projection
 * - Multiple biomes (forest, desert, snow, water, plains, mountains)
 * - Infinite scrolling terrain with chunk-based generation
 * - Low-poly procedural trees, rocks, and buildings
 * - Audio-reactive terrain modulation
 * - Smooth day/night cycle
 */
class LowPolyLandscapeLevel extends Level {

  // Terrain configuration
  static final int CHUNK_SIZE = 12;        // Tiles per chunk
  static final int VISIBLE_CHUNKS = 6;     // Chunks visible in each direction
  static final float TILE_SIZE = 32;       // World units per tile (larger = smoother terrain)

  // Scroll state
  float scrollX = 0;
  float scrollZ = 0;
  float scrollSpeed = 40;  // Units per second

  // Time tracking
  float dayTime = 0;       // 0-1 for day cycle
  float dayDuration = 60;  // Seconds for full day

  // Audio modulation
  float audioHeight = 0;
  float audioPulse = 0;

  // Noise seeds for different layers
  float heightSeed;
  float moistureSeed;
  float temperatureSeed;
  float detailSeed;

  // Cached chunk data
  HashMap<Long, Chunk> chunks = new HashMap<Long, Chunk>();

  // Colors for biomes
  color waterDeep, waterShallow, sand, grass, forest, rock, snow, desert;

  // Biome enum
  static final int BIOME_WATER = 0;
  static final int BIOME_BEACH = 1;
  static final int BIOME_PLAINS = 2;
  static final int BIOME_FOREST = 3;
  static final int BIOME_DESERT = 4;
  static final int BIOME_MOUNTAIN = 5;
  static final int BIOME_SNOW = 6;

  public void reset() {
    // Initialize noise seeds
    heightSeed = random(10000);
    moistureSeed = random(10000);
    temperatureSeed = random(10000);
    detailSeed = random(10000);

    scrollX = 0;
    scrollZ = 0;
    dayTime = 0.3;  // Start at morning
    audioHeight = 0;
    audioPulse = 0;

    // Clear cached chunks
    chunks.clear();

    // Initialize biome colors
    initColors();
  }

  void initColors() {
    waterDeep = color(25, 55, 95);
    waterShallow = color(45, 100, 150);
    sand = color(210, 190, 130);
    grass = color(80, 150, 70);
    forest = color(40, 100, 50);
    rock = color(100, 95, 90);
    snow = color(240, 245, 255);
    desert = color(200, 170, 100);
  }

  public void update(float dt, float t, AudioEnvelope audio) {
    // Smooth scroll forward (and slightly sideways with time)
    scrollZ += scrollSpeed * dt;
    scrollX += sin(t * 0.1) * scrollSpeed * 0.3 * dt;

    // Day/night cycle
    dayTime = (dayTime + dt / dayDuration) % 1.0;

    // Audio reactivity
    float targetHeight = audio.getBass() * 30 + audio.getMid() * 15;
    audioHeight = lerp(audioHeight, targetHeight, dt * 3);
    audioPulse = audio.getBass() * 0.5 + audio.getHigh() * 0.3;

    // Clean up old chunks (keep only nearby ones)
    cleanupChunks();
  }

  public void render(PGraphics pg) {
    pg.pushStyle();
    pg.pushMatrix();
    pg.camera();  // Reset camera to default

    // Sky gradient based on day time
    drawSky(pg);

    // Setup isometric camera
    setupIsometricCamera(pg);

    // Lighting based on day/night
    setupLighting(pg);

    // Calculate which chunks to render
    int centerChunkX = floor(scrollX / (CHUNK_SIZE * TILE_SIZE));
    int centerChunkZ = floor(scrollZ / (CHUNK_SIZE * TILE_SIZE));

    // Render terrain chunks
    for (int cz = centerChunkZ - VISIBLE_CHUNKS; cz <= centerChunkZ + VISIBLE_CHUNKS; cz++) {
      for (int cx = centerChunkX - VISIBLE_CHUNKS; cx <= centerChunkX + VISIBLE_CHUNKS; cx++) {
        renderChunk(pg, cx, cz);
      }
    }

    pg.popMatrix();

    // Fog overlay for depth
    drawFog(pg);

    // IMPORTANT: Reset perspective projection so other levels aren't affected
    // ortho() changes the projection matrix, popMatrix() only restores modelview
    pg.perspective();
    pg.camera();

    pg.popStyle();
  }

  void drawSky(PGraphics pg) {
    // Interpolate sky color based on time of day
    float dayBrightness = sin(dayTime * PI);  // 0 at midnight, 1 at noon
    dayBrightness = constrain(dayBrightness, 0, 1);

    // Night: dark blue, Day: light blue, Sunset: orange tint
    color nightSky = color(10, 15, 35);
    color daySky = color(135, 180, 220);
    color sunsetSky = color(220, 140, 80);

    color skyColor;
    if (dayTime < 0.25 || dayTime > 0.75) {
      // Night
      skyColor = nightSky;
    } else if (dayTime < 0.3 || dayTime > 0.7) {
      // Sunrise/sunset
      float t = (dayTime < 0.5) ? map(dayTime, 0.25, 0.3, 0, 1) : map(dayTime, 0.7, 0.75, 1, 0);
      skyColor = lerpColor(nightSky, sunsetSky, t);
    } else {
      // Day
      float t = map(dayTime, 0.3, 0.5, 0, 1);
      if (dayTime > 0.5) t = map(dayTime, 0.5, 0.7, 1, 0);
      skyColor = lerpColor(sunsetSky, daySky, t);
    }

    pg.background(skyColor);
  }

  void setupIsometricCamera(PGraphics pg) {
    // Orthographic projection for isometric look - zoomed in close
    float aspect = (float)pg.width / pg.height;
    float viewSize = 180;  // Zoomed in
    pg.ortho(-viewSize * aspect, viewSize * aspect, -viewSize, viewSize, -5000, 5000);

    // Move to center of screen
    pg.translate(pg.width * 0.5, pg.height * 0.5, 0);

    // True isometric: tilt down, then rotate around Y for diamond view
    // This makes +Z scroll direction appear as left-to-right on screen
    pg.rotateX(radians(55));  // Tilt down to see ground
    pg.rotateY(radians(-45)); // Diamond orientation

    // Offset by scroll position to create movement
    pg.translate(-scrollX, 0, -scrollZ);
  }

  void setupLighting(PGraphics pg) {
    pg.lights();

    float dayBrightness = sin(dayTime * PI);
    dayBrightness = constrain(dayBrightness * 1.5, 0, 1);

    // Ambient light (dim at night)
    float ambientLevel = lerp(20, 80, dayBrightness);
    pg.ambientLight(ambientLevel, ambientLevel, ambientLevel + 10);

    // Sun/moon directional light
    float sunAngle = dayTime * TWO_PI - HALF_PI;
    float sunX = cos(sunAngle);
    float sunY = -abs(sin(sunAngle)) - 0.3;
    float sunZ = 0.5;

    if (dayBrightness > 0.1) {
      // Sunlight (warm)
      float intensity = dayBrightness * 200;
      pg.directionalLight(intensity, intensity * 0.95, intensity * 0.85, sunX, sunY, sunZ);
    } else {
      // Moonlight (cool, dim)
      pg.directionalLight(40, 45, 60, -sunX, sunY, sunZ);
    }

    // Fill light from opposite side
    pg.directionalLight(50 * dayBrightness + 20, 50 * dayBrightness + 20, 60 * dayBrightness + 25,
                        -sunX * 0.5, 0.3, -sunZ);
  }

  void renderChunk(PGraphics pg, int chunkX, int chunkZ) {
    Chunk chunk = getOrCreateChunk(chunkX, chunkZ);

    float baseX = chunkX * CHUNK_SIZE * TILE_SIZE;
    float baseZ = chunkZ * CHUNK_SIZE * TILE_SIZE;

    pg.pushMatrix();
    pg.translate(baseX, 0, baseZ);

    // Render terrain mesh - individual triangles for clean seamless look
    pg.noStroke();
    pg.beginShape(TRIANGLES);

    for (int z = 0; z < CHUNK_SIZE - 1; z++) {
      for (int x = 0; x < CHUNK_SIZE - 1; x++) {
        // Get tile data for the quad corners
        TileData t00 = chunk.tiles[x][z];
        TileData t10 = chunk.tiles[x + 1][z];
        TileData t01 = chunk.tiles[x][z + 1];
        TileData t11 = chunk.tiles[x + 1][z + 1];

        // Audio modulation on height
        float audioMod = audioHeight * (0.5 + 0.5 * noise(x * 0.3 + chunkX, z * 0.3 + chunkZ));

        // Calculate positions
        float x0 = x * TILE_SIZE;
        float x1 = (x + 1) * TILE_SIZE;
        float z0 = z * TILE_SIZE;
        float z1 = (z + 1) * TILE_SIZE;

        float y00 = -(t00.height + audioMod);
        float y10 = -(t10.height + audioMod);
        float y01 = -(t01.height + audioMod);
        float y11 = -(t11.height + audioMod);

        // Use average height for face color
        float avgHeight = (t00.height + t10.height + t01.height + t11.height) / 4;
        int avgBiome = t00.biome;  // Use corner biome
        color faceColor = getBiomeColor(avgBiome, avgHeight);
        pg.fill(faceColor);

        // Triangle 1: top-left triangle
        pg.vertex(x0, y00, z0);
        pg.vertex(x1, y10, z0);
        pg.vertex(x0, y01, z1);

        // Triangle 2: bottom-right triangle
        pg.vertex(x1, y10, z0);
        pg.vertex(x1, y11, z1);
        pg.vertex(x0, y01, z1);
      }
    }
    pg.endShape();

    // Render decorations (trees, rocks, buildings)
    renderDecorations(pg, chunk, chunkX, chunkZ);

    pg.popMatrix();
  }

  void renderDecorations(PGraphics pg, Chunk chunk, int chunkX, int chunkZ) {
    for (Decoration dec : chunk.decorations) {
      pg.pushMatrix();
      pg.translate(dec.x * TILE_SIZE, -dec.height - audioHeight * 0.3, dec.z * TILE_SIZE);

      // Scale with audio pulse
      float scale = dec.scale * (1 + audioPulse * 0.1);
      pg.scale(scale);

      switch (dec.type) {
        case 0: drawTree(pg, dec.variant); break;
        case 1: drawRock(pg, dec.variant); break;
        case 2: drawBuilding(pg, dec.variant); break;
        case 3: drawCactus(pg); break;
        case 4: drawSnowTree(pg); break;
      }

      pg.popMatrix();
    }
  }

  // Low-poly tree
  void drawTree(PGraphics pg, int variant) {
    pg.pushStyle();
    pg.noStroke();

    // Trunk
    pg.fill(80, 60, 40);
    drawPrism(pg, 0, 0, 0, 3, 20, 4);

    // Foliage (stacked cones)
    pg.fill(40 + variant * 10, 120 + variant * 15, 50);
    drawCone(pg, 0, -25, 0, 18, 25, 6);
    pg.fill(50 + variant * 10, 140 + variant * 10, 60);
    drawCone(pg, 0, -45, 0, 14, 22, 6);
    pg.fill(60 + variant * 10, 155 + variant * 8, 70);
    drawCone(pg, 0, -62, 0, 10, 18, 5);

    pg.popStyle();
  }

  // Snow-covered tree
  void drawSnowTree(PGraphics pg) {
    pg.pushStyle();
    pg.noStroke();

    // Trunk
    pg.fill(70, 55, 45);
    drawPrism(pg, 0, 0, 0, 3, 18, 4);

    // Snow-covered foliage
    pg.fill(220, 230, 240);
    drawCone(pg, 0, -22, 0, 16, 22, 6);
    pg.fill(235, 240, 250);
    drawCone(pg, 0, -40, 0, 12, 18, 6);
    pg.fill(245, 248, 255);
    drawCone(pg, 0, -55, 0, 8, 14, 5);

    pg.popStyle();
  }

  // Low-poly rock
  void drawRock(PGraphics pg, int variant) {
    pg.pushStyle();
    pg.noStroke();

    float gray = 90 + variant * 15;
    pg.fill(gray, gray - 5, gray - 10);

    // Irregular rock shape using deformed sphere
    pg.pushMatrix();
    pg.scale(1, 0.6, 0.8);
    drawIcosahedron(pg, 0, -8, 0, 12 + variant * 3);
    pg.popMatrix();

    pg.popStyle();
  }

  // Low-poly cactus
  void drawCactus(PGraphics pg) {
    pg.pushStyle();
    pg.noStroke();
    pg.fill(70, 140, 60);

    // Main body
    drawPrism(pg, 0, -15, 0, 4, 30, 6);

    // Arms
    pg.pushMatrix();
    pg.translate(5, -20, 0);
    pg.rotateZ(radians(-30));
    drawPrism(pg, 0, -8, 0, 3, 16, 5);
    pg.popMatrix();

    pg.pushMatrix();
    pg.translate(-5, -15, 0);
    pg.rotateZ(radians(40));
    drawPrism(pg, 0, -6, 0, 2.5, 12, 5);
    pg.popMatrix();

    pg.popStyle();
  }

  // Low-poly building
  void drawBuilding(PGraphics pg, int variant) {
    pg.pushStyle();
    pg.noStroke();

    float h = 30 + variant * 20;

    // Main structure
    color wallColor = color(180 + variant * 10, 170 + variant * 8, 160);
    pg.fill(wallColor);
    drawBox(pg, 0, -h/2, 0, 16, h, 14);

    // Roof
    pg.fill(140, 80, 60);
    pg.pushMatrix();
    pg.translate(0, -h - 8, 0);
    drawPyramid(pg, 0, 0, 0, 20, 16, 4);
    pg.popMatrix();

    // Windows (emissive at night)
    float dayBrightness = sin(dayTime * PI);
    if (dayBrightness < 0.5) {
      float glow = (1 - dayBrightness * 2);  // 0 at day, 1 at night
      pg.emissive((int)(255 * glow), (int)(220 * glow), (int)(150 * glow));
    }
    pg.fill(255, 220, 150);
    drawBox(pg, 4, -h * 0.4, 7.5, 3, 4, 0.5);
    drawBox(pg, -4, -h * 0.4, 7.5, 3, 4, 0.5);
    drawBox(pg, 4, -h * 0.7, 7.5, 3, 4, 0.5);
    drawBox(pg, -4, -h * 0.7, 7.5, 3, 4, 0.5);
    pg.emissive(0);

    pg.popStyle();
  }

  // Primitive shape helpers
  void drawCone(PGraphics pg, float x, float y, float z, float r, float h, int segments) {
    pg.pushMatrix();
    pg.translate(x, y, z);
    pg.beginShape(TRIANGLE_FAN);
    pg.vertex(0, -h, 0);  // Apex
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

  void drawPrism(PGraphics pg, float x, float y, float z, float r, float h, int segments) {
    pg.pushMatrix();
    pg.translate(x, y, z);

    // Sides
    pg.beginShape(QUAD_STRIP);
    for (int i = 0; i <= segments; i++) {
      float angle = TWO_PI * i / segments;
      float px = cos(angle) * r;
      float pz = sin(angle) * r;
      pg.vertex(px, 0, pz);
      pg.vertex(px, -h, pz);
    }
    pg.endShape();

    // Top and bottom caps
    pg.beginShape(TRIANGLE_FAN);
    pg.vertex(0, -h, 0);
    for (int i = 0; i <= segments; i++) {
      float angle = TWO_PI * i / segments;
      pg.vertex(cos(angle) * r, -h, sin(angle) * r);
    }
    pg.endShape();

    pg.beginShape(TRIANGLE_FAN);
    pg.vertex(0, 0, 0);
    for (int i = segments; i >= 0; i--) {
      float angle = TWO_PI * i / segments;
      pg.vertex(cos(angle) * r, 0, sin(angle) * r);
    }
    pg.endShape();

    pg.popMatrix();
  }

  void drawBox(PGraphics pg, float x, float y, float z, float w, float h, float d) {
    pg.pushMatrix();
    pg.translate(x, y, z);
    pg.box(w, h, d);
    pg.popMatrix();
  }

  void drawPyramid(PGraphics pg, float x, float y, float z, float w, float h, int segments) {
    pg.pushMatrix();
    pg.translate(x, y, z);

    // Four-sided pyramid
    pg.beginShape(TRIANGLES);
    float hw = w / 2;

    // Front
    pg.vertex(0, -h, 0);
    pg.vertex(-hw, 0, hw);
    pg.vertex(hw, 0, hw);

    // Right
    pg.vertex(0, -h, 0);
    pg.vertex(hw, 0, hw);
    pg.vertex(hw, 0, -hw);

    // Back
    pg.vertex(0, -h, 0);
    pg.vertex(hw, 0, -hw);
    pg.vertex(-hw, 0, -hw);

    // Left
    pg.vertex(0, -h, 0);
    pg.vertex(-hw, 0, -hw);
    pg.vertex(-hw, 0, hw);

    pg.endShape();

    // Base
    pg.beginShape(QUADS);
    pg.vertex(-hw, 0, -hw);
    pg.vertex(hw, 0, -hw);
    pg.vertex(hw, 0, hw);
    pg.vertex(-hw, 0, hw);
    pg.endShape();

    pg.popMatrix();
  }

  void drawIcosahedron(PGraphics pg, float x, float y, float z, float r) {
    pg.pushMatrix();
    pg.translate(x, y, z);

    // Simplified low-poly sphere (octahedron)
    pg.beginShape(TRIANGLES);

    // Top pyramid
    pg.vertex(0, -r, 0);
    pg.vertex(r, 0, 0);
    pg.vertex(0, 0, r);

    pg.vertex(0, -r, 0);
    pg.vertex(0, 0, r);
    pg.vertex(-r, 0, 0);

    pg.vertex(0, -r, 0);
    pg.vertex(-r, 0, 0);
    pg.vertex(0, 0, -r);

    pg.vertex(0, -r, 0);
    pg.vertex(0, 0, -r);
    pg.vertex(r, 0, 0);

    // Bottom pyramid
    pg.vertex(0, r, 0);
    pg.vertex(0, 0, r);
    pg.vertex(r, 0, 0);

    pg.vertex(0, r, 0);
    pg.vertex(-r, 0, 0);
    pg.vertex(0, 0, r);

    pg.vertex(0, r, 0);
    pg.vertex(0, 0, -r);
    pg.vertex(-r, 0, 0);

    pg.vertex(0, r, 0);
    pg.vertex(r, 0, 0);
    pg.vertex(0, 0, -r);

    pg.endShape();
    pg.popMatrix();
  }

  color getBiomeColor(int biome, float height) {
    // Add some variation based on height
    float variation = noise(height * 0.05) * 20 - 10;

    switch (biome) {
      case BIOME_WATER:
        return (height < -30) ? waterDeep : waterShallow;
      case BIOME_BEACH:
        return color(red(sand) + variation, green(sand) + variation, blue(sand) + variation * 0.5);
      case BIOME_PLAINS:
        return color(red(grass) + variation, green(grass) + variation, blue(grass) + variation * 0.5);
      case BIOME_FOREST:
        return color(red(forest) + variation, green(forest) + variation * 0.5, blue(forest) + variation * 0.3);
      case BIOME_DESERT:
        return color(red(desert) + variation, green(desert) + variation * 0.8, blue(desert) + variation * 0.5);
      case BIOME_MOUNTAIN:
        return color(red(rock) + variation, green(rock) + variation, blue(rock) + variation);
      case BIOME_SNOW:
        return color(red(snow) - abs(variation) * 0.5, green(snow) - abs(variation) * 0.3, blue(snow));
      default:
        return grass;
    }
  }

  void drawFog(PGraphics pg) {
    // Distance fog for depth effect
    pg.noStroke();
    float dayBrightness = sin(dayTime * PI);
    color fogColor = lerpColor(color(20, 25, 45, 60), color(180, 200, 220, 40), constrain(dayBrightness, 0, 1));
    pg.fill(fogColor);
    pg.rect(0, 0, pg.width, pg.height);
  }

  // Chunk management
  Chunk getOrCreateChunk(int cx, int cz) {
    long key = ((long)cx << 32) | (cz & 0xFFFFFFFFL);

    if (!chunks.containsKey(key)) {
      chunks.put(key, generateChunk(cx, cz));
    }

    return chunks.get(key);
  }

  Chunk generateChunk(int chunkX, int chunkZ) {
    Chunk chunk = new Chunk();
    chunk.tiles = new TileData[CHUNK_SIZE][CHUNK_SIZE];
    chunk.decorations = new ArrayList<Decoration>();

    float worldOffsetX = chunkX * CHUNK_SIZE;
    float worldOffsetZ = chunkZ * CHUNK_SIZE;

    for (int x = 0; x < CHUNK_SIZE; x++) {
      for (int z = 0; z < CHUNK_SIZE; z++) {
        float worldX = worldOffsetX + x;
        float worldZ = worldOffsetZ + z;

        // Multi-octave height noise
        float height = getHeight(worldX, worldZ);

        // Moisture for biome determination
        float moisture = getMoisture(worldX, worldZ);

        // Temperature (affected by height and latitude-ish)
        float temperature = getTemperature(worldX, worldZ, height);

        // Determine biome
        int biome = determineBiome(height, moisture, temperature);

        chunk.tiles[x][z] = new TileData(height, biome, moisture, temperature);

        // Place decorations
        placeDecoration(chunk, x, z, height, biome, worldX, worldZ);
      }
    }

    return chunk;
  }

  float getHeight(float x, float z) {
    float freq1 = 0.006;   // Lower frequency for larger features
    float freq2 = 0.015;
    float freq3 = 0.04;

    // Multiple octaves of noise
    float h = noise(x * freq1 + heightSeed, z * freq1) * 1.0;
    h += noise(x * freq2 + heightSeed + 100, z * freq2) * 0.5;
    h += noise(x * freq3 + heightSeed + 200, z * freq3) * 0.25;

    // Normalize and scale
    h = h / 1.75;  // Sum of weights
    h = pow(h, 1.3);  // Slightly less contrast for smoother hills

    return h * 350 - 50;  // Much taller terrain: roughly -50 to 300
  }

  float getMoisture(float x, float z) {
    float freq = 0.012;
    return noise(x * freq + moistureSeed, z * freq);
  }

  float getTemperature(float x, float z, float height) {
    float freq = 0.015;
    float baseTemp = noise(x * freq + temperatureSeed, z * freq);

    // Higher altitude = colder (updated for new height range)
    float altitudeFactor = map(height, -50, 300, 0.2, -0.4);

    return constrain(baseTemp + altitudeFactor, 0, 1);
  }

  int determineBiome(float height, float moisture, float temperature) {
    // Water (updated for new height range -50 to 300)
    if (height < -15) return BIOME_WATER;

    // Beach (near water level)
    if (height < 20 && moisture > 0.4) return BIOME_BEACH;

    // Snow (cold and high)
    if (temperature < 0.3 && height > 150) return BIOME_SNOW;
    if (temperature < 0.2) return BIOME_SNOW;

    // Desert (hot and dry)
    if (temperature > 0.65 && moisture < 0.35) return BIOME_DESERT;

    // Mountain (high elevation)
    if (height > 180) return BIOME_MOUNTAIN;

    // Forest (moderate moisture and temperature)
    if (moisture > 0.5 && temperature > 0.35 && temperature < 0.7) return BIOME_FOREST;

    // Plains (default)
    return BIOME_PLAINS;
  }

  void placeDecoration(Chunk chunk, int x, int z, float height, int biome, float worldX, float worldZ) {
    // Use noise for deterministic decoration placement
    float decorNoise = noise(worldX * 0.3 + detailSeed, worldZ * 0.3);

    if (biome == BIOME_WATER) return;  // No decorations in water

    Decoration dec = null;

    if (biome == BIOME_FOREST) {
      // Dense trees in forest
      if (decorNoise > 0.45) {
        dec = new Decoration(x, z, height, 0, (int)(decorNoise * 5) % 3, 0.8 + decorNoise * 0.6);
      }
    } else if (biome == BIOME_PLAINS) {
      // Sparse trees and occasional rocks
      if (decorNoise > 0.75) {
        dec = new Decoration(x, z, height, 0, (int)(decorNoise * 3) % 3, 0.7 + decorNoise * 0.4);
      } else if (decorNoise > 0.7 && decorNoise <= 0.75) {
        dec = new Decoration(x, z, height, 1, (int)(decorNoise * 4) % 3, 0.6 + decorNoise * 0.5);
      }
      // Rare buildings
      if (decorNoise > 0.92 && noise(worldX * 0.1, worldZ * 0.1) > 0.6) {
        dec = new Decoration(x, z, height, 2, (int)(decorNoise * 5) % 4, 1.0);
      }
    } else if (biome == BIOME_DESERT) {
      // Cacti and rocks
      if (decorNoise > 0.8) {
        dec = new Decoration(x, z, height, 3, 0, 0.7 + decorNoise * 0.5);
      } else if (decorNoise > 0.75) {
        dec = new Decoration(x, z, height, 1, (int)(decorNoise * 3) % 3, 0.5 + decorNoise * 0.3);
      }
    } else if (biome == BIOME_SNOW) {
      // Snow trees
      if (decorNoise > 0.6) {
        dec = new Decoration(x, z, height, 4, 0, 0.7 + decorNoise * 0.5);
      }
    } else if (biome == BIOME_MOUNTAIN) {
      // Rocks on mountains
      if (decorNoise > 0.7) {
        dec = new Decoration(x, z, height, 1, (int)(decorNoise * 4) % 3, 0.8 + decorNoise * 0.6);
      }
    } else if (biome == BIOME_BEACH) {
      // Occasional rocks on beach
      if (decorNoise > 0.85) {
        dec = new Decoration(x, z, height, 1, 0, 0.4 + decorNoise * 0.3);
      }
    }

    if (dec != null) {
      chunk.decorations.add(dec);
    }
  }

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

  public String getName() { return "Low Poly Landscape"; }

  // Inner classes for data storage
  class Chunk {
    TileData[][] tiles;
    ArrayList<Decoration> decorations;
  }

  class TileData {
    float height;
    int biome;
    float moisture;
    float temperature;

    TileData(float h, int b, float m, float t) {
      height = h;
      biome = b;
      moisture = m;
      temperature = t;
    }
  }

  class Decoration {
    float x, z, height;
    int type;     // 0=tree, 1=rock, 2=building, 3=cactus, 4=snow tree
    int variant;
    float scale;

    Decoration(float x, float z, float h, int type, int variant, float scale) {
      this.x = x;
      this.z = z;
      this.height = h;
      this.type = type;
      this.variant = variant;
      this.scale = scale;
    }
  }
}
