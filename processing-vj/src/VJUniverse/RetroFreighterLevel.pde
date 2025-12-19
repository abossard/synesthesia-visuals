/**
 * RetroFreighterLevel - Cinematic Wireframe Freighter
 *
 * Uses the improved CinematicCamera for smooth, subject-locked filming.
 * Ship always stays ~85% visible on screen.
 */
class RetroFreighterLevel extends Level {
  // Geometry
  PVector[] verts;
  int[][] edges;
  PVector[] stars;

  // Ship state
  PVector shipPosition;
  PVector shipVelocity;
  float shipYaw = 0;
  float shipPitch = 0;
  float shipRoll = 0;
  float engineGlow = 0;

  // Camera
  CinematicCamera cam;
  float totalTime = 0;

  RetroFreighterLevel() {
    buildGeometry();
    buildStars();

    cam = new CinematicCamera();
    cam.setSpringParams(2.5, 0.88);
    cam.setNoiseParams(0.1, 5.0, 0.012);
    cam.setDistanceLimits(200, 450, 300);
    cam.setSubjectRadius(180);

    shipPosition = new PVector(0, 0, 0);
    shipVelocity = new PVector(0, 0, 0);
  }

  public void reset() {
    totalTime = 0;
    shipPosition = new PVector(0, 0, 0);
    shipVelocity = new PVector(0, 0, 0);
    shipYaw = random(-0.2, 0.2);
    shipPitch = 0;
    shipRoll = 0;
    engineGlow = 0;
    cam.reset();
  }

  public void update(float dt, float t, AudioEnvelope audio) {
    totalTime += dt;

    // Audio-reactive engine glow
    float targetGlow = 0.3 + audio.bassLevel * 0.7;
    engineGlow = lerp(engineGlow, targetGlow, dt * 5);

    // Update ship motion
    updateShipMotion(dt, audio);

    // Track the ship with camera
    cam.trackSubject(shipPosition);

    // Smoothly vary camera mode based on time
    float cyclePhase = (totalTime * 0.05) % 1.0;
    if (cyclePhase < 0.6) {
      // Orbit mode most of the time
      float orbitRadius = 280 + sin(totalTime * 0.1) * 40;
      float orbitHeight = -70 + sin(totalTime * 0.15) * 30;
      cam.setOrbit(orbitRadius, 0.25, orbitHeight);
    } else {
      // Chase mode for variety
      cam.setChase(260, 80 + sin(totalTime * 0.2) * 20);
    }

    cam.update(dt);
    shipPosition.add(PVector.mult(shipVelocity, dt));
  }

  void updateShipMotion(float dt, AudioEnvelope audio) {
    float motionPhase = totalTime * 0.15;

    // Gentle forward drift
    float baseSpeed = 60 + audio.bassLevel * 40;
    shipVelocity.z = lerp(shipVelocity.z, baseSpeed, dt * 0.5);
    shipVelocity.x = lerp(shipVelocity.x, sin(motionPhase) * 20, dt * 0.8);
    shipVelocity.y = lerp(shipVelocity.y, cos(motionPhase * 0.7) * 12, dt * 0.8);

    // Smooth rotation
    float targetYaw = sin(motionPhase * 0.5) * 0.25;
    float targetPitch = sin(motionPhase * 0.7) * 0.06;
    float targetRoll = sin(motionPhase * 0.9) * 0.08;

    shipYaw = lerp(shipYaw, targetYaw, dt * 0.8);
    shipPitch = lerp(shipPitch, targetPitch, dt * 1.2);
    shipRoll = lerp(shipRoll, targetRoll, dt * 1.0);
  }

  public void render(PGraphics pg) {
    pg.pushStyle();
    pg.background(4, 5, 10);

    pg.perspective(PI/3, (float)pg.width/pg.height, 1, 10000);
    cam.apply(pg);

    drawStars(pg);

    pg.pushMatrix();
    pg.translate(shipPosition.x, shipPosition.y, shipPosition.z);
    pg.rotateY(shipYaw);
    pg.rotateX(shipPitch);
    pg.rotateZ(shipRoll);

    pg.noFill();
    pg.strokeWeight(2.6);
    pg.stroke(120, 200, 255);
    drawWireframe(pg, verts, edges);
    drawEngineGlow(pg);

    pg.popMatrix();
    pg.popStyle();
  }

  void drawEngineGlow(PGraphics pg) {
    pg.pushStyle();
    int glowAlpha = (int)(80 + engineGlow * 175);
    pg.stroke(255, 140, 80, glowAlpha);
    pg.strokeWeight(4 + engineGlow * 3);

    float[][] engines = {{-60, 10, -130}, {60, 10, -130}, {0, 20, -140}};
    for (float[] e : engines) {
      pg.pushMatrix();
      pg.translate(e[0], e[1], e[2]);
      float thrustLen = 30 + engineGlow * 80 + sin(totalTime * 15) * 10;
      pg.line(0, 0, 0, 0, 0, -thrustLen);
      pg.stroke(255, 200, 150, glowAlpha + 50);
      pg.strokeWeight(2);
      pg.line(0, 0, 0, 0, 0, -thrustLen * 0.6);
      pg.popMatrix();
    }

    pg.stroke(255, 140, 120, 180);
    pg.strokeWeight(3);
    pg.line(-20, 0, 0, 20, 0, 0);
    pg.line(0, -20, 0, 0, 20, 0);
    pg.popStyle();
  }

  public void buildGeometry() {
    verts = new PVector[] {
      new PVector(-90, -25, 130),
      new PVector(90, -25, 130),
      new PVector(-110, 25, 70),
      new PVector(110, 25, 70),
      new PVector(-140, -30, -20),
      new PVector(140, -30, -20),
      new PVector(-140, 30, -20),
      new PVector(140, 30, -20),
      new PVector(-90, -35, -140),
      new PVector(90, -35, -140),
      new PVector(-90, 35, -140),
      new PVector(90, 35, -140),
      new PVector(-180, 0, -60),
      new PVector(180, 0, -60)
    };

    edges = new int[][] {
      {0,1},{1,3},{2,3},{0,2},
      {0,4},{1,5},{2,6},{3,7},
      {4,5},{5,7},{4,6},{6,7},
      {4,8},{5,9},{6,10},{7,11},
      {8,9},{9,11},{8,10},{10,11},
      {4,12},{6,12},{5,13},{7,13},
      {12,8},{12,10},{13,9},{13,11}
    };
  }

  public void buildStars() {
    stars = new PVector[400];
    for (int i = 0; i < stars.length; i++) {
      float theta = random(TWO_PI);
      float phi = random(PI);
      float r = random(2000, 5000);
      stars[i] = new PVector(
        r * sin(phi) * cos(theta),
        r * sin(phi) * sin(theta),
        r * cos(phi)
      );
    }
  }

  public void drawStars(PGraphics pg) {
    pg.pushStyle();
    pg.noStroke();
    for (int i = 0; i < stars.length; i++) {
      PVector s = stars[i];
      float tw = 1.0 + noise(i * 0.2, totalTime * 0.2) * 2.0;
      float brightness = 150 + 100 * sin(i * 0.23 + totalTime * 0.5);
      pg.fill(brightness, brightness * 0.9, 255, 200);
      pg.pushMatrix();
      pg.translate(s.x, s.y, s.z);
      pg.box(tw);
      pg.popMatrix();
    }
    pg.popStyle();
  }

  public void drawWireframe(PGraphics pg, PVector[] v, int[][] e) {
    pg.beginShape(LINES);
    for (int i = 0; i < e.length; i++) {
      PVector a = v[e[i][0]];
      PVector b = v[e[i][1]];
      pg.vertex(a.x, a.y, a.z);
      pg.vertex(b.x, b.y, b.z);
    }
    pg.endShape();
  }

  public String getName() { return "Retro Freighter"; }
}
