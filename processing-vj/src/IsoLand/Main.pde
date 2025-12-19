/**
 * Infinite Low-Poly Isometric World (Processing / P3D)
 *
 * Controls:
 *   WASD / Arrow keys  - move
 *   Q / E              - zoom out / in
 *   N                  - toggle day/night
 *   R                  - new world seed
 *
 * Notes:
 *   - Uses ortho() for isometric-style orthographic projection. https://processing.org/reference/ortho_  [oai_citation:0‡Processing](https://processing.org/reference/ortho_?utm_source=chatgpt.com)
 *   - Uses emissive() for simple “building lights” at night. https://processing.org/reference/emissive_.html  [oai_citation:1‡Processing](https://processing.org/reference/emissive_.html?utm_source=chatgpt.com)
 *   - Uses PShape for chunk meshes (batching geometry). https://processing.org/tutorials/pshape/  [oai_citation:2‡Processing](https://processing.org/tutorials/pshape/?utm_source=chatgpt.com)
 */

import java.util.HashMap;
import java.util.ArrayList;

final int   CHUNK_TILES  = 28;    // tiles per chunk edge
final float TILE_SIZE    = 24;    // world units per tile
final int   VIEW_RADIUS  = 2;     // chunks radius around camera to keep (2 => up to 5x5)
final float HEIGHT_SCALE = 150;   // terrain vertical scale
final float WATER_LEVEL  = 0.42;  // normalized [0..1]
final float BEACH_BAND   = 0.05;  // above water
final float SNOW_LEVEL   = 0.82;  // normalized
final float CITY_LEVEL   = 0.55;  // flat-ish and moderate elevation
final float VOLC_LEVEL   = 0.78;

final float H_FREQ       = 0.018; // height noise frequency
final float M_FREQ       = 0.012; // moisture noise frequency
final float C_FREQ       = 0.006; // “civilization” noise frequency (city placement)

HashMap<Long, Chunk> chunks = new HashMap<Long, Chunk>();

float camX = 0;
float camZ = 0;
float zoom = 1.1;

boolean night = false;
float tod = 0; // time-of-day phase accumulator

long worldSeed = 1337;

boolean up, down, left, right, akey, dkey;
boolean qkey, ekey;

void settings() {
  size(1280, 800, P3D);
}

void setup() {
  surface.setTitle("Infinite Low-Poly Isometric World (Chunks + Noise)");
  noiseDetail(5, 0.55);
  reseed(worldSeed);
}

void draw() {
  float dt = min(1.0/20.0, 1.0/max(frameRate, 1)); // stable-ish dt

  updateCamera(dt);
  streamChunks();

  // ---- Isometric-ish camera ----
  background(night ? color(8, 10, 18) : color(170, 210, 255));

  // Orthographic projection (no perspective shrinking)
  ortho(-width/2, width/2, -height/2, height/2, -20000, 20000);

  // Center + zoom
  translate(width * 0.5, height * 0.58, 0);
  scale(zoom);

  // Classic isometric-ish rotation
  rotateX(radians(60));
  rotateZ(radians(45));

  // World pan (camera movement)
  translate(-camX, 0, -camZ);

  // ---- Lighting / day-night ----
  applyLighting(dt);

  // ---- Render visible chunks ----
  int ccx = floor(camX / chunkWorldSize());
  int ccz = floor(camZ / chunkWorldSize());

  for (int dz = -VIEW_RADIUS; dz <= VIEW_RADIUS; dz++) {
    for (int dx = -VIEW_RADIUS; dx <= VIEW_RADIUS; dx++) {
      int cx = ccx + dx;
      int cz = ccz + dz;
      Chunk c = chunks.get(key(cx, cz));
      if (c == null) continue;

      pushMatrix();
      translate(cx * chunkWorldSize(), 0, cz * chunkWorldSize());

      // Terrain mesh
      shape(c.terrain);

      // Water mesh (draw after terrain)
      shape(c.water);

      // Objects (trees/buildings/boats)
      c.drawObjects(night);

      popMatrix();
    }
  }

  // Simple moon (visual cue)
  if (night) drawMoon();
}

void applyLighting(float dt) {
  if (!night) {
    // Day: bright ambient + sun
    ambientLight(70, 70, 85);
    directionalLight(240, 235, 220, -0.4, -1.0, -0.2);
  } else {
    // Night: dim ambient + moonlight
    ambientLight(10, 12, 22);
    directionalLight(90, 110, 160, -0.2, -1.0, -0.4);
  }

  // A little specular so low-poly faces pop
  specular(80);
  shininess(10.0);
}

void drawMoon() {
  pushMatrix();
  // put it somewhere “in the sky”
  translate(camX + 900, -850, camZ - 900);
  noStroke();
  emissive(160, 170, 210);
  fill(160, 170, 210);
  sphereDetail(10);
  sphere(70);
  emissive(0);
  popMatrix();
}

void updateCamera(float dt) {
  float speed = 520;
  if (keyPressed && (keyCode == SHIFT)) speed *= 1.8;

  float vx = 0;
  float vz = 0;

  if (left || akey)  vx -= 1;
  if (right || dkey) vx += 1;
  if (up)            vz -= 1;
  if (down)          vz += 1;

  float len = sqrt(vx*vx + vz*vz);
  if (len > 0) {
    vx /= len;
    vz /= len;
  }

  camX += vx * speed * dt;
  camZ += vz * speed * dt;

  if (qkey) zoom *= pow(0.98, dt * 60);
  if (ekey) zoom *= pow(1.02, dt * 60);
  zoom = constrain(zoom, 0.55, 2.6);
}

float chunkWorldSize() {
  return CHUNK_TILES * TILE_SIZE;
}

void streamChunks() {
  int ccx = floor(camX / chunkWorldSize());
  int ccz = floor(camZ / chunkWorldSize());

  // Create needed chunks
  for (int dz = -VIEW_RADIUS; dz <= VIEW_RADIUS; dz++) {
    for (int dx = -VIEW_RADIUS; dx <= VIEW_RADIUS; dx++) {
      int cx = ccx + dx;
      int cz = ccz + dz;
      long k = key(cx, cz);
      if (!chunks.containsKey(k)) {
        chunks.put(k, new Chunk(cx, cz));
      }
    }
  }

  // Remove far chunks
  ArrayList<Long> toRemove = new ArrayList<Long>();
  for (long k : chunks.keySet()) {
    int cx = (int)(k >> 32);
    int cz = (int)(k & 0xffffffffL);
    if (abs(cx - ccx) > VIEW_RADIUS + 1 || abs(cz - ccz) > VIEW_RADIUS + 1) {
      toRemove.add(k);
    }
  }
  for (long k : toRemove) chunks.remove(k);
}

long key(int cx, int cz) {
  return ((long)cx << 32) ^ (cz & 0xffffffffL);
}

void reseed(long s) {
  worldSeed = s;
  noiseSeed((int)(worldSeed ^ (worldSeed >>> 32)));
  chunks.clear();
  streamChunks();
}

// -----------------------------
// Chunk + procedural generation
// -----------------------------
class Chunk {
  final int cx, cz;
  PShape terrain;
  PShape water;
  ArrayList<Obj> objects = new ArrayList<Obj>();

  Chunk(int cx, int cz) {
    this.cx = cx;
    this.cz = cz;
    build();
  }

  void build() {
    terrain = createShape();
    terrain.beginShape(TRIANGLES);
    terrain.noStroke();

    water = createShape();
    water.beginShape(TRIANGLES);
    water.noStroke();

    // Build tile grid as two triangles per tile
    for (int tz = 0; tz < CHUNK_TILES; tz++) {
      for (int tx = 0; tx < CHUNK_TILES; tx++) {

        float wx0 = (tx + 0) * TILE_SIZE;
        float wz0 = (tz + 0) * TILE_SIZE;
        float wx1 = (tx + 1) * TILE_SIZE;
        float wz1 = (tz + 1) * TILE_SIZE;

        float gx0 = (cx * CHUNK_TILES + tx + 0);
        float gz0 = (cz * CHUNK_TILES + tz + 0);
        float gx1 = (cx * CHUNK_TILES + tx + 1);
        float gz1 = (cz * CHUNK_TILES + tz + 1);

        float h00 = heightAt(gx0, gz0);
        float h10 = heightAt(gx1, gz0);
        float h01 = heightAt(gx0, gz1);
        float h11 = heightAt(gx1, gz1);

        // Biome based on center sample
        float gcx = (cx * CHUNK_TILES + tx + 0.5);
        float gcz = (cz * CHUNK_TILES + tz + 0.5);
        Biome b = biomeAt(gcx, gcz);

        int col = biomeColor(b);

        // Terrain triangles
        terrain.fill(col);
        tri(terrain, wx0, -h00, wz0,  wx1, -h10, wz0,  wx1, -h11, wz1);
        tri(terrain, wx0, -h00, wz0,  wx1, -h11, wz1,  wx0, -h01, wz1);

        // Water overlay (if tile is water)
        if (b == Biome.OCEAN || b == Biome.LAKE) {
          int wcol = night ? color(10, 25, 55) : color(20, 90, 155);
          water.fill(wcol);
          float wy = -WATER_LEVEL * HEIGHT_SCALE + 0.5; // slight lift to avoid z-fight
          tri(water, wx0, wy, wz0,  wx1, wy, wz0,  wx1, wy, wz1);
          tri(water, wx0, wy, wz0,  wx1, wy, wz1,  wx0, wy, wz1);
        }

        // Objects (deterministic per tile)
        spawnObjects(b, tx, tz, gcx, gcz, (h00+h10+h01+h11)*0.25);
      }
    }

    terrain.endShape();
    water.endShape();
  }

  void spawnObjects(Biome b, int tx, int tz, float gx, float gz, float h) {
    int r = hashTile((int)gx, (int)gz, 0);

    float localX = (tx + 0.5) * TILE_SIZE;
    float localZ = (tz + 0.5) * TILE_SIZE;

    // Forest trees
    if (b == Biome.FOREST) {
      if ((r & 0xff) < 80) {
        float s = 0.8 + ((r >>> 8) & 0xff) / 255.0 * 0.8;
        objects.add(new Obj(ObjType.TREE, localX, -h, localZ, s, r));
      }
    }

    // City buildings
    if (b == Biome.CITY) {
      if ((r & 0xff) < 140) {
        float s = 0.9 + ((r >>> 8) & 0xff) / 255.0 * 1.4;
        objects.add(new Obj(ObjType.BUILDING, localX, -h, localZ, s, r));
      }
    }

    // Boats on ocean
    if (b == Biome.OCEAN) {
      if ((r & 0xff) < 18) {
        float s = 0.9 + ((r >>> 8) & 0xff) / 255.0 * 0.7;
        float wy = -WATER_LEVEL * HEIGHT_SCALE;
        objects.add(new Obj(ObjType.BOAT, localX, wy, localZ, s, r));
      }
    }
  }

  void drawObjects(boolean nightMode) {
    for (Obj o : objects) {
      pushMatrix();
      translate(o.x, o.y, o.z);

      if (o.type == ObjType.TREE) {
        drawTree(o.scale);
      } else if (o.type == ObjType.BUILDING) {
        drawBuilding(o.scale, nightMode, o.seed);
      } else if (o.type == ObjType.BOAT) {
        drawBoat(o.scale, nightMode, o.seed);
      }

      popMatrix();
    }
  }
}

// -----------------------------
// Biomes / noise helpers
// -----------------------------
enum Biome { OCEAN, LAKE, BEACH, GRASS, FOREST, MOUNTAIN, SNOW, VOLCANO, CITY }

float heightAt(float gx, float gz) {
  // Fractal-ish height
  float n =
    1.00 * noise(gx * H_FREQ,        gz * H_FREQ) +
    0.50 * noise(gx * H_FREQ * 2.1,  gz * H_FREQ * 2.1) +
    0.25 * noise(gx * H_FREQ * 4.2,  gz * H_FREQ * 4.2);

  n /= (1.00 + 0.50 + 0.25);

  // Slight audio-reactive “pulse” placeholder (replace with real amplitude if you want)
  float audio = 0.0;
  audio = (mousePressed ? 1.0 : 0.0) * 0.06; // simple control

  float h = (n + audio) * HEIGHT_SCALE;
  return h;
}

float moistureAt(float gx, float gz) {
  return noise(1000 + gx * M_FREQ, 1000 + gz * M_FREQ);
}

float civAt(float gx, float gz) {
  return noise(2000 + gx * C_FREQ, 2000 + gz * C_FREQ);
}

Biome biomeAt(float gx, float gz) {
  float hN = noise(gx * H_FREQ, gz * H_FREQ);   // normalized height proxy
  float m  = moistureAt(gx, gz);
  float c  = civAt(gx, gz);

  // Water
  if (hN < WATER_LEVEL - 0.06) return Biome.OCEAN;
  if (hN < WATER_LEVEL)        return Biome.LAKE;
  if (hN < WATER_LEVEL + BEACH_BAND) return Biome.BEACH;

  // Volcano hotspot
  float v = noise(3000 + gx * 0.004, 3000 + gz * 0.004);
  if (hN > VOLC_LEVEL && v > 0.72) return Biome.VOLCANO;

  // Snow
  if (hN > SNOW_LEVEL) return Biome.SNOW;

  // Mountain
  if (hN > 0.70) return Biome.MOUNTAIN;

  // City: prefer flatter-ish mid elevation + “civilization” noise
  if (hN > 0.48 && hN < 0.66 && c > 0.62 && m < 0.62) return Biome.CITY;

  // Forest vs grass by moisture
  if (m > 0.55) return Biome.FOREST;
  return Biome.GRASS;
}

int biomeColor(Biome b) {
  if (!night) {
    switch(b) {
      case OCEAN:    return color(15, 80, 150);
      case LAKE:     return color(25, 100, 160);
      case BEACH:    return color(220, 205, 150);
      case GRASS:    return color(90, 170, 90);
      case FOREST:   return color(55, 125, 70);
      case MOUNTAIN: return color(150, 150, 155);
      case SNOW:     return color(235, 240, 245);
      case VOLCANO:  return color(110, 90, 85);
      case CITY:     return color(170, 170, 175);
    }
  } else {
    switch(b) {
      case OCEAN:    return color(6, 14, 35);
      case LAKE:     return color(7, 16, 38);
      case BEACH:    return color(60, 55, 45);
      case GRASS:    return color(20, 38, 25);
      case FOREST:   return color(12, 28, 18);
      case MOUNTAIN: return color(45, 45, 50);
      case SNOW:     return color(70, 75, 82);
      case VOLCANO:  return color(40, 30, 28);
      case CITY:     return color(55, 55, 60);
    }
  }
  return color(128);
}

// -----------------------------
// Drawing primitives (low-poly)
// -----------------------------
void tri(PShape s, float x1, float y1, float z1,
                float x2, float y2, float z2,
                float x3, float y3, float z3) {
  s.vertex(x1, y1, z1);
  s.vertex(x2, y2, z2);
  s.vertex(x3, y3, z3);
}

void drawTree(float sc) {
  noStroke();

  // trunk
  pushMatrix();
  fill(night ? color(35, 25, 18) : color(90, 70, 45));
  translate(0, -10*sc, 0);
  box(10*sc, 20*sc, 10*sc);
  popMatrix();

  // foliage (simple pyramid-ish cone using low detail sphere scaled)
  pushMatrix();
  fill(night ? color(12, 30, 16) : color(40, 120, 60));
  translate(0, -32*sc, 0);
  sphereDetail(6);
  sphere(18*sc);
  popMatrix();
}

void drawBuilding(float sc, boolean nightMode, int seed) {
  noStroke();

  float h = 35*sc + ((seed >>> 16) & 0xff) * 0.35;
  float w = 18*sc;
  float d = 18*sc;

  // base material
  fill(nightMode ? color(45, 45, 52) : color(165, 165, 175));
  pushMatrix();
  translate(0, -h*0.5, 0);
  box(w, h, d);
  popMatrix();

  // “lights” (emissive accent)
  if (nightMode) {
    pushMatrix();
    translate(0, -h*0.65, d*0.51);
    emissive(255, 210, 140);
    fill(255, 210, 140);
    box(w*0.55, h*0.12, 2);
    emissive(0);
    popMatrix();
  }
}

void drawBoat(float sc, boolean nightMode, int seed) {
  noStroke();
  float bob = sin((frameCount*0.05) + (seed & 0xff)) * 2.5;

  pushMatrix();
  translate(0, bob, 0);
  fill(nightMode ? color(80, 70, 60) : color(200, 185, 160));
  box(20*sc, 6*sc, 10*sc);

  // tiny mast
  fill(nightMode ? color(60) : color(130));
  translate(0, -14*sc, 0);
  box(2*sc, 28*sc, 2*sc);

  // tiny “lamp”
  if (nightMode) {
    emissive(255, 220, 160);
    fill(255, 220, 160);
    translate(0, -14*sc, 0);
    sphereDetail(6);
    sphere(3.5*sc);
    emissive(0);
  }
  popMatrix();
}

// -----------------------------
// Deterministic per-tile hash
// -----------------------------
int hashTile(int x, int z, int salt) {
  int h = (int)(worldSeed) ^ salt;
  h ^= x * 0x27d4eb2d;
  h = (h << 13) | (h >>> 19);
  h ^= z * 0x165667b1;
  h *= 0x85ebca6b;
  h ^= (h >>> 16);
  return h;
}

// -----------------------------
// Object records
// -----------------------------
enum ObjType { TREE, BUILDING, BOAT }

class Obj {
  ObjType type;
  float x, y, z;
  float scale;
  int seed;
  Obj(ObjType t, float x, float y, float z, float sc, int seed) {
    this.type = t;
    this.x = x; this.y = y; this.z = z;
    this.scale = sc;
    this.seed = seed;
  }
}

// -----------------------------
// Input
// -----------------------------
void keyPressed() {
  if (keyCode == UP) up = true;
  if (keyCode == DOWN) down = true;
  if (keyCode == LEFT) left = true;
  if (keyCode == RIGHT) right = true;

  if (key == 'w' || key == 'W') up = true;
  if (key == 's' || key == 'S') down = true;
  if (key == 'a' || key == 'A') akey = true;
  if (key == 'd' || key == 'D') dkey = true;

  if (key == 'q' || key == 'Q') qkey = true;
  if (key == 'e' || key == 'E') ekey = true;

  if (key == 'n' || key == 'N') night = !night;

  if (key == 'r' || key == 'R') {
    reseed((long)random(1, 1e9));
  }
}

void keyReleased() {
  if (keyCode == UP) up = false;
  if (keyCode == DOWN) down = false;
  if (keyCode == LEFT) left = false;
  if (keyCode == RIGHT) right = false;

  if (key == 'w' || key == 'W') up = false;
  if (key == 's' || key == 'S') down = false;
  if (key == 'a' || key == 'A') akey = false;
  if (key == 'd' || key == 'D') dkey = false;

  if (key == 'q' || key == 'Q') qkey = false;
  if (key == 'e' || key == 'E') ekey = false;
}