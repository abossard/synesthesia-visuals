/**
 * RetroShipLevel - Cinematic Wireframe Fighter
 *
 * Uses the improved CinematicCamera for smooth, subject-locked filming.
 * Fighter ship always stays ~85% visible on screen.
 */
class RetroShipLevel extends Level {
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
  float engineThrust = 0;

  // Camera
  CinematicCamera cam;
  float totalTime = 0;

  RetroShipLevel() {
    buildGeometry();
    buildStars();

    cam = new CinematicCamera();
    cam.setSpringParams(3.0, 0.85);
    cam.setNoiseParams(0.15, 4.0, 0.015);
    cam.setDistanceLimits(150, 350, 220);
    cam.setSubjectRadius(120);

    shipPosition = new PVector(0, 0, 0);
    shipVelocity = new PVector(0, 0, 0);
  }

  public void reset() {
    totalTime = 0;
    shipPosition = new PVector(0, 0, 0);
    shipVelocity = new PVector(0, 0, 100);
    shipYaw = 0;
    shipPitch = 0;
    shipRoll = 0;
    engineThrust = 0.5;
    cam.reset();
  }

  public void update(float dt, float t, AudioEnvelope audio) {
    totalTime += dt;

    // Audio-reactive thrust
    float targetThrust = 0.4 + audio.bassLevel * 0.4 + audio.midLevel * 0.2;
    engineThrust = lerp(engineThrust, targetThrust, dt * 6);

    updateShipMotion(dt, audio);

    // Track the ship
    cam.trackSubject(shipPosition);

    // Smoothly vary camera - fighter uses tighter orbit
    float cyclePhase = (totalTime * 0.04) % 1.0;
    if (cyclePhase < 0.7) {
      float orbitRadius = 200 + sin(totalTime * 0.12) * 30;
      float orbitHeight = -50 + sin(totalTime * 0.18) * 25;
      cam.setOrbit(orbitRadius, 0.35, orbitHeight);
    } else {
      cam.setChase(180, 60 + sin(totalTime * 0.25) * 15);
    }

    cam.update(dt);
    shipPosition.add(PVector.mult(shipVelocity, dt));
  }

  void updateShipMotion(float dt, AudioEnvelope audio) {
    float motionPhase = totalTime * 0.25;

    // Forward flight with banking
    float baseSpeed = 100 + audio.bassLevel * 60;
    shipVelocity.z = lerp(shipVelocity.z, baseSpeed, dt * 0.8);

    float bankAngle = sin(motionPhase) * 0.6;
    shipVelocity.x = lerp(shipVelocity.x, sin(motionPhase * 1.3) * 45, dt * 1.2);
    shipVelocity.y = lerp(shipVelocity.y, cos(motionPhase * 0.9) * 30, dt * 1.0);

    // Dynamic rotation
    float targetYaw = sin(motionPhase * 0.7) * 0.35;
    float targetPitch = sin(motionPhase * 1.1) * 0.12 + audio.bassLevel * 0.08;
    float targetRoll = sin(motionPhase * 0.5) * 0.2 + bankAngle * 0.25;

    if (audio.bassLevel > 0.7) {
      targetRoll += sin(totalTime * 3) * 0.2;
    }

    shipYaw = lerp(shipYaw, targetYaw, dt * 1.5);
    shipPitch = lerp(shipPitch, targetPitch, dt * 2.0);
    shipRoll = lerp(shipRoll, targetRoll, dt * 1.8);
  }

  public void render(PGraphics pg) {
    pg.pushStyle();
    pg.background(6, 6, 14);

    pg.perspective(PI/3, (float)pg.width/pg.height, 1, 8000);
    cam.apply(pg);

    drawStars(pg);

    pg.pushMatrix();
    pg.translate(shipPosition.x, shipPosition.y, shipPosition.z);
    pg.rotateY(shipYaw);
    pg.rotateX(shipPitch);
    pg.rotateZ(shipRoll);

    pg.noFill();
    pg.strokeWeight(3);
    pg.stroke(255, 120, 80);
    drawWireframe(pg, verts, edges);

    pg.stroke(80, 220, 255, 180);
    pg.strokeWeight(2);
    pg.pushMatrix();
    pg.translate(0, 0, -70);
    pg.sphereDetail(10);
    pg.sphere(24 + engineThrust * 8);
    pg.popMatrix();

    drawEngineTrails(pg);
    pg.popMatrix();
    pg.popStyle();
  }

  void drawEngineTrails(PGraphics pg) {
    pg.pushStyle();
    int trailAlpha = (int)(100 + engineThrust * 155);
    pg.stroke(80, 180, 255, trailAlpha);
    pg.strokeWeight(2 + engineThrust * 2);

    float[][] engines = {{-30, 5, -90}, {30, 5, -90}};
    for (float[] e : engines) {
      pg.pushMatrix();
      pg.translate(e[0], e[1], e[2]);
      float trailLen = 40 + engineThrust * 120 + sin(totalTime * 20) * 15;
      pg.line(0, 0, 0, 0, 0, -trailLen);
      pg.stroke(180, 230, 255, trailAlpha + 50);
      pg.strokeWeight(1.5);
      pg.line(0, 0, 0, 0, 0, -trailLen * 0.5);
      pg.popMatrix();
    }
    pg.popStyle();
  }

  public void buildGeometry() {
    verts = new PVector[] {
      new PVector(0, 0, 120),
      new PVector(-40, -12, 40),
      new PVector(40, -12, 40),
      new PVector(-70, -8, -40),
      new PVector(70, -8, -40),
      new PVector(-50, 12, -90),
      new PVector(50, 12, -90),
      new PVector(0, -2, -120),
      new PVector(-120, -4, 0),
      new PVector(120, -4, 0),
      new PVector(0, -40, -10)
    };

    edges = new int[][] {
      {0,1},{0,2},{1,2},
      {1,3},{2,4},
      {3,5},{4,6},{5,7},{6,7},
      {3,8},{2,9},{1,8},{4,9},
      {8,5},{9,6},
      {1,10},{2,10},{10,3},{10,4}
    };
  }

  public void buildStars() {
    stars = new PVector[350];
    for (int i = 0; i < stars.length; i++) {
      float theta = random(TWO_PI);
      float phi = random(PI);
      float r = random(1500, 4000);
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
      float tw = 0.8 + noise(i * 0.1, totalTime * 0.3) * 1.5;
      pg.fill(200 + 55 * sin(i), 200, 255, 180);
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

  public String getName() { return "Retro Ship"; }
}
