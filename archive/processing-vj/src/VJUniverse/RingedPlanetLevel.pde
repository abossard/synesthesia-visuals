/**
 * RingedPlanetLevel - Wireframe Gas Giant with Rings
 *
 * Uses the improved CinematicCamera for smooth, subject-locked filming.
 * Planet always stays ~85% visible on screen.
 */
class RingedPlanetLevel extends Level {
  // Planet parameters
  float planetRadius = 400;
  int latLines = 16;
  int lonLines = 24;
  float planetRotation = 0;
  float atmosphereGlow = 0;

  // Ring parameters
  float ringInnerRadius = 550;
  float ringOuterRadius = 900;
  int ringSegments = 80;
  float ringRotation = 0;

  // Moons
  Moon[] moons;

  // Camera
  CinematicCamera cam;
  float totalTime = 0;

  // Stars
  PVector[] stars;

  // Planet center (stationary)
  PVector planetCenter;

  RingedPlanetLevel() {
    buildMoons();
    buildStars();

    cam = new CinematicCamera();
    cam.setSpringParams(1.5, 0.92);
    cam.setNoiseParams(0.06, 4.0, 0.006);
    cam.setDistanceLimits(800, 2500, 1400);  // Planet + rings span ~900 radius
    cam.setSubjectRadius(600);  // Account for planet + inner rings

    planetCenter = new PVector(0, 0, 0);
  }

  void buildMoons() {
    moons = new Moon[3];
    moons[0] = new Moon(700, 0.15, 60, 0);
    moons[1] = new Moon(1100, 0.08, 45, PI * 0.7);
    moons[2] = new Moon(1400, 0.05, 35, PI * 1.4);
  }

  void buildStars() {
    stars = new PVector[600];
    for (int i = 0; i < stars.length; i++) {
      float theta = random(TWO_PI);
      float phi = random(PI);
      float r = random(5000, 12000);
      stars[i] = new PVector(
        r * sin(phi) * cos(theta),
        r * sin(phi) * sin(theta),
        r * cos(phi)
      );
    }
  }

  public void reset() {
    totalTime = 0;
    planetRotation = 0;
    ringRotation = 0;
    atmosphereGlow = 0;

    for (Moon m : moons) m.reset();
    cam.reset();
  }

  public void update(float dt, float t, AudioEnvelope audio) {
    totalTime += dt;

    // Planet rotation
    planetRotation += dt * 0.05;
    ringRotation += dt * 0.02;

    // Update moons
    for (Moon m : moons) m.update(dt);

    // Audio-reactive atmosphere
    float targetGlow = 0.3 + audio.bassLevel * 0.4 + audio.midLevel * 0.3;
    atmosphereGlow = lerp(atmosphereGlow, targetGlow, dt * 4);

    // Track the planet center
    cam.trackSubject(planetCenter);

    // Smoothly vary camera - planet uses majestic slow orbits
    float cyclePhase = (totalTime * 0.02) % 1.0;  // Very slow cycle
    if (cyclePhase < 0.6) {
      // Wide orbit - see planet and rings
      float orbitRadius = 1500 + sin(totalTime * 0.04) * 200;
      float orbitHeight = -300 + sin(totalTime * 0.06) * 150;
      cam.setOrbit(orbitRadius, 0.08, orbitHeight);  // Slow, majestic orbit
    } else if (cyclePhase < 0.85) {
      // Higher angle - see rings from above
      float orbitRadius = 1200 + sin(totalTime * 0.05) * 100;
      float orbitHeight = -800 + sin(totalTime * 0.07) * 100;  // High above
      cam.setOrbit(orbitRadius, 0.06, orbitHeight);
    } else {
      // Chase mode - follow as if approaching
      cam.setChase(1600, -200 + sin(totalTime * 0.08) * 100);
    }

    cam.update(dt);
  }

  public void render(PGraphics pg) {
    pg.pushStyle();
    pg.background(2, 2, 6);

    pg.perspective(PI/3.2, (float)pg.width/pg.height, 1, 20000);
    cam.apply(pg);

    drawStars(pg);

    pg.pushMatrix();

    // Draw planet
    pg.pushMatrix();
    pg.rotateY(planetRotation);
    drawPlanet(pg);
    pg.popMatrix();

    // Draw rings (separate rotation)
    pg.pushMatrix();
    pg.rotateY(ringRotation);
    pg.rotateX(0.3); // Ring tilt
    drawRings(pg);
    pg.popMatrix();

    // Draw moons
    for (Moon m : moons) {
      m.draw(pg);
    }

    // Atmospheric glow
    drawAtmosphere(pg);

    pg.popMatrix();
    pg.popStyle();
  }

  void drawPlanet(PGraphics pg) {
    pg.noFill();
    pg.strokeWeight(1.5);
    pg.stroke(80, 160, 200);

    // Latitude lines
    for (int i = 1; i < latLines; i++) {
      float lat = map(i, 0, latLines, -HALF_PI, HALF_PI);
      float r = cos(lat) * planetRadius;
      float y = sin(lat) * planetRadius;

      pg.beginShape();
      for (int j = 0; j <= lonLines; j++) {
        float lon = map(j, 0, lonLines, 0, TWO_PI);
        float x = cos(lon) * r;
        float z = sin(lon) * r;
        pg.vertex(x, y, z);
      }
      pg.endShape();
    }

    // Longitude lines
    for (int i = 0; i < lonLines; i++) {
      float lon = map(i, 0, lonLines, 0, TWO_PI);

      pg.beginShape();
      for (int j = 0; j <= latLines; j++) {
        float lat = map(j, 0, latLines, -HALF_PI, HALF_PI);
        float r = cos(lat) * planetRadius;
        float y = sin(lat) * planetRadius;
        float x = cos(lon) * r;
        float z = sin(lon) * r;
        pg.vertex(x, y, z);
      }
      pg.endShape();
    }

    // Storm bands (extra latitude detail)
    pg.stroke(100, 180, 220, 150);
    pg.strokeWeight(1);
    float[] stormLats = {-0.3, -0.1, 0.15, 0.35};
    for (float lat : stormLats) {
      float r = cos(lat) * planetRadius * 1.01;
      float y = sin(lat) * planetRadius * 1.01;

      pg.beginShape();
      for (int j = 0; j <= lonLines * 2; j++) {
        float lon = map(j, 0, lonLines * 2, 0, TWO_PI);
        float wobble = noise(j * 0.2, totalTime * 0.5 + lat * 10) * 10;
        float x = cos(lon) * (r + wobble);
        float z = sin(lon) * (r + wobble);
        pg.vertex(x, y, z);
      }
      pg.endShape();
    }
  }

  void drawRings(PGraphics pg) {
    pg.noFill();

    // Multiple ring bands with gaps
    float[][] bands = {
      {550, 620, 0.8},   // Inner band
      {650, 750, 1.0},   // Main band
      {780, 850, 0.6},   // Outer band 1
      {870, 900, 0.4}    // Outer band 2
    };

    for (float[] band : bands) {
      float inner = band[0];
      float outer = band[1];
      float brightness = band[2];

      // Draw concentric ring circles
      int rings = 4;
      for (int r = 0; r <= rings; r++) {
        float radius = lerp(inner, outer, (float)r / rings);
        int alpha = (int)(100 + 80 * brightness);
        pg.stroke(150, 180, 220, alpha);
        pg.strokeWeight(1 + brightness);

        pg.beginShape();
        for (int i = 0; i <= ringSegments; i++) {
          float angle = map(i, 0, ringSegments, 0, TWO_PI);
          float x = cos(angle) * radius;
          float z = sin(angle) * radius;
          pg.vertex(x, 0, z);
        }
        pg.endShape();
      }

      // Radial spokes for texture
      pg.strokeWeight(0.5);
      pg.stroke(120, 150, 200, (int)(60 * brightness));
      int spokeCount = 24;
      for (int i = 0; i < spokeCount; i++) {
        float angle = map(i, 0, spokeCount, 0, TWO_PI);
        float x1 = cos(angle) * inner;
        float z1 = sin(angle) * inner;
        float x2 = cos(angle) * outer;
        float z2 = sin(angle) * outer;
        pg.line(x1, 0, z1, x2, 0, z2);
      }
    }
  }

  void drawAtmosphere(PGraphics pg) {
    pg.pushStyle();
    pg.noFill();

    int glowAlpha = (int)(30 + atmosphereGlow * 60);
    pg.stroke(80, 180, 255, glowAlpha);
    pg.strokeWeight(3 + atmosphereGlow * 2);

    // Atmospheric halo
    float haloRadius = planetRadius * 1.08;
    pg.beginShape();
    for (int i = 0; i <= 48; i++) {
      float angle = map(i, 0, 48, 0, TWO_PI);
      float x = cos(angle) * haloRadius;
      float z = sin(angle) * haloRadius;
      pg.vertex(x, 0, z);
    }
    pg.endShape();

    pg.popStyle();
  }

  void drawStars(PGraphics pg) {
    pg.pushStyle();
    pg.noStroke();
    for (int i = 0; i < stars.length; i++) {
      PVector s = stars[i];
      float tw = 1.0 + noise(i * 0.12, totalTime * 0.12) * 1.5;
      float brightness = 100 + 120 * sin(i * 0.18 + totalTime * 0.25);
      pg.fill(brightness, brightness * 0.95, 255, 160);
      pg.pushMatrix();
      pg.translate(s.x, s.y, s.z);
      pg.box(tw);
      pg.popMatrix();
    }
    pg.popStyle();
  }

  public String getName() { return "Ringed Planet"; }

  // Inner class for moons
  class Moon {
    float orbitRadius;
    float orbitSpeed;
    float radius;
    float angle;
    float initialAngle;

    Moon(float orbitR, float speed, float r, float startAngle) {
      this.orbitRadius = orbitR;
      this.orbitSpeed = speed;
      this.radius = r;
      this.angle = startAngle;
      this.initialAngle = startAngle;
    }

    void reset() {
      angle = initialAngle;
    }

    void update(float dt) {
      angle += orbitSpeed * dt;
    }

    PVector getPosition() {
      float x = cos(angle) * orbitRadius;
      float z = sin(angle) * orbitRadius;
      float y = sin(angle * 0.5) * orbitRadius * 0.1; // Slight orbital inclination
      return new PVector(x, y, z);
    }

    void draw(PGraphics pg) {
      PVector pos = getPosition();

      pg.pushMatrix();
      pg.translate(pos.x, pos.y, pos.z);

      pg.noFill();
      pg.stroke(180, 180, 200);
      pg.strokeWeight(1.5);

      // Simple wireframe sphere
      pg.sphereDetail(8);

      // Draw as wireframe circles
      int detail = 8;
      for (int i = 0; i < detail; i++) {
        float lat = map(i, 0, detail, 0, PI);
        float r = sin(lat) * radius;
        float y = cos(lat) * radius;

        pg.beginShape();
        for (int j = 0; j <= detail; j++) {
          float lon = map(j, 0, detail, 0, TWO_PI);
          float x = cos(lon) * r;
          float z = sin(lon) * r;
          pg.vertex(x, y, z);
        }
        pg.endShape();
      }

      pg.popMatrix();
    }
  }
}
