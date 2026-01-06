/**
 * CapitalShipFlybyLevel - Massive Wireframe Capital Ship
 *
 * Uses the improved CinematicCamera for smooth, subject-locked filming.
 * Capital ship always stays ~85% visible on screen.
 */
class CapitalShipFlybyLevel extends Level {
  // Geometry
  ArrayList<PVector> verts = new ArrayList<PVector>();
  ArrayList<int[]> edges = new ArrayList<int[]>();
  PVector[] stars;

  // Ship state
  PVector shipPosition;
  PVector shipVelocity;
  float shipYaw = 0;
  float shipPitch = 0;
  float shipRoll = 0;

  // Cinematic camera
  CinematicCamera cam;
  float totalTime = 0;

  // Running lights
  float[][] runningLights;
  float lightPhase = 0;

  CapitalShipFlybyLevel() {
    buildCapitalShip();
    buildStars();

    cam = new CinematicCamera();
    cam.setSpringParams(1.8, 0.92);  // Slower, more majestic for large ship
    cam.setNoiseParams(0.06, 6.0, 0.006);  // Subtle noise for epic scale
    cam.setDistanceLimits(500, 1800, 1000);  // Large ship needs more distance
    cam.setSubjectRadius(500);  // Ship is ~1200 units long

    shipPosition = new PVector(0, 0, 0);
    shipVelocity = new PVector(0, 0, 0);

    // Running light positions along the hull
    runningLights = new float[][] {
      {-400, -80, 200}, {400, -80, 200},
      {-350, -60, 0}, {350, -60, 0},
      {-300, -50, -200}, {300, -50, -200},
      {0, -120, 400}, {0, -100, -600},
      {-200, 50, -500}, {200, 50, -500}
    };
  }

  public void reset() {
    totalTime = 0;
    lightPhase = 0;
    shipPosition = new PVector(0, 0, 0);
    shipVelocity = new PVector(0, 0, 40);  // Slow majestic drift
    shipYaw = 0;
    shipPitch = 0;
    shipRoll = 0;
    cam.reset();
  }

  public void update(float dt, float t, AudioEnvelope audio) {
    totalTime += dt;

    // Running lights phase (audio-reactive)
    lightPhase += dt * (2 + audio.midLevel * 3);

    updateShipMotion(dt, audio);

    // Track the ship
    cam.trackSubject(shipPosition);

    // Smoothly vary camera - capital ship uses wider, slower orbits
    float cyclePhase = (totalTime * 0.025) % 1.0;  // Slower cycle for majesty
    if (cyclePhase < 0.5) {
      // Wide orbit - emphasize scale
      float orbitRadius = 1200 + sin(totalTime * 0.06) * 200;
      float orbitHeight = -200 + sin(totalTime * 0.08) * 100;
      cam.setOrbit(orbitRadius, 0.12, orbitHeight);  // Slow orbit
    } else if (cyclePhase < 0.8) {
      // Chase from behind - see the engines
      cam.setChase(900, 150 + sin(totalTime * 0.1) * 50);
    } else {
      // Follow from side
      PVector offset = new PVector(
        800 + sin(totalTime * 0.15) * 100,
        -100 + sin(totalTime * 0.12) * 50,
        200
      );
      cam.setFollow(offset);
    }

    cam.update(dt);
    shipPosition.add(PVector.mult(shipVelocity, dt));
  }

  void updateShipMotion(float dt, AudioEnvelope audio) {
    float motionPhase = totalTime * 0.08;  // Very slow, majestic motion

    // Slow forward drift
    float baseSpeed = 40 + audio.bassLevel * 20;
    shipVelocity.z = lerp(shipVelocity.z, baseSpeed, dt * 0.3);
    shipVelocity.x = lerp(shipVelocity.x, sin(motionPhase) * 15, dt * 0.4);
    shipVelocity.y = lerp(shipVelocity.y, cos(motionPhase * 0.7) * 8, dt * 0.4);

    // Very subtle rotation - capital ships don't bank much
    float targetYaw = sin(motionPhase * 0.5) * 0.08;
    float targetPitch = sin(motionPhase * 0.8) * 0.02;
    float targetRoll = sin(motionPhase * 0.6) * 0.03;

    shipYaw = lerp(shipYaw, targetYaw, dt * 0.5);
    shipPitch = lerp(shipPitch, targetPitch, dt * 0.6);
    shipRoll = lerp(shipRoll, targetRoll, dt * 0.5);
  }

  public void render(PGraphics pg) {
    pg.pushStyle();
    pg.background(2, 3, 8);

    pg.perspective(PI/3.5, (float)pg.width/pg.height, 1, 15000);
    cam.apply(pg);

    drawStars(pg);

    pg.pushMatrix();
    pg.translate(shipPosition.x, shipPosition.y, shipPosition.z);
    pg.rotateY(shipYaw);

    // Main wireframe
    pg.noFill();
    pg.strokeWeight(2.5);
    pg.stroke(100, 180, 255);
    drawWireframe(pg);

    // Running lights
    drawRunningLights(pg);

    // Engine glow
    drawEngines(pg);

    pg.popMatrix();
    pg.popStyle();
  }

  void drawRunningLights(PGraphics pg) {
    pg.pushStyle();

    for (int i = 0; i < runningLights.length; i++) {
      float phase = lightPhase + i * 0.5;
      float brightness = (sin(phase) + 1) * 0.5;

      int alpha = (int)(50 + brightness * 200);
      pg.stroke(255, 100, 80, alpha);
      pg.strokeWeight(3 + brightness * 4);

      float[] pos = runningLights[i];
      pg.point(pos[0], pos[1], pos[2]);
    }

    pg.popStyle();
  }

  void drawEngines(PGraphics pg) {
    pg.pushStyle();

    // Four massive engines at rear
    float[][] engines = {
      {-200, 80, -650}, {200, 80, -650},
      {-120, 0, -680}, {120, 0, -680}
    };

    float glow = 0.6 + sin(totalTime * 3) * 0.2;

    for (float[] e : engines) {
      pg.pushMatrix();
      pg.translate(e[0], e[1], e[2]);

      // Outer glow
      pg.stroke(80, 150, 255, (int)(100 * glow));
      pg.strokeWeight(6);
      pg.noFill();
      pg.ellipse(0, 0, 80, 80);

      // Inner core
      pg.stroke(150, 200, 255, (int)(180 * glow));
      pg.strokeWeight(3);
      pg.ellipse(0, 0, 50, 50);

      // Thrust cone
      pg.stroke(100, 180, 255, (int)(120 * glow));
      pg.strokeWeight(2);
      float thrustLen = 100 + glow * 80;
      for (int i = 0; i < 8; i++) {
        float angle = i * TWO_PI / 8;
        float x = cos(angle) * 25;
        float y = sin(angle) * 25;
        pg.line(x, y, 0, x * 0.3, y * 0.3, -thrustLen);
      }

      pg.popMatrix();
    }

    pg.popStyle();
  }

  void buildCapitalShip() {
    verts.clear();
    edges.clear();

    // MAIN HULL - elongated box shape
    // Front section (tapered)
    addVertex(-80, -60, 500);   // 0
    addVertex(80, -60, 500);    // 1
    addVertex(-100, 60, 450);   // 2
    addVertex(100, 60, 450);    // 3

    // Mid-front
    addVertex(-150, -80, 300);  // 4
    addVertex(150, -80, 300);   // 5
    addVertex(-180, 80, 300);   // 6
    addVertex(180, 80, 300);    // 7

    // Mid-section (widest)
    addVertex(-200, -100, 0);   // 8
    addVertex(200, -100, 0);    // 9
    addVertex(-220, 100, 0);    // 10
    addVertex(220, 100, 0);     // 11

    // Rear-mid
    addVertex(-180, -90, -400); // 12
    addVertex(180, -90, -400);  // 13
    addVertex(-200, 90, -400);  // 14
    addVertex(200, 90, -400);   // 15

    // Engine block
    addVertex(-250, -60, -600); // 16
    addVertex(250, -60, -600);  // 17
    addVertex(-280, 100, -600); // 18
    addVertex(280, 100, -600);  // 19

    // Connect main hull longitudinal
    for (int i = 0; i < 4; i++) {
      addEdge(i, i + 4);
      addEdge(i + 4, i + 8);
      addEdge(i + 8, i + 12);
      addEdge(i + 12, i + 16);
    }

    // Connect main hull rings
    int[][] rings = {{0,1,3,2}, {4,5,7,6}, {8,9,11,10}, {12,13,15,14}, {16,17,19,18}};
    for (int[] ring : rings) {
      addEdge(ring[0], ring[1]);
      addEdge(ring[1], ring[2]);
      addEdge(ring[2], ring[3]);
      addEdge(ring[3], ring[0]);
    }

    // BRIDGE TOWER
    int bridgeBase = verts.size();
    addVertex(-60, -100, 350);  // 20
    addVertex(60, -100, 350);   // 21
    addVertex(-50, -180, 320);  // 22
    addVertex(50, -180, 320);   // 23
    addVertex(-40, -200, 380);  // 24
    addVertex(40, -200, 380);   // 25

    addEdge(bridgeBase, bridgeBase + 1);
    addEdge(bridgeBase, bridgeBase + 2);
    addEdge(bridgeBase + 1, bridgeBase + 3);
    addEdge(bridgeBase + 2, bridgeBase + 3);
    addEdge(bridgeBase + 2, bridgeBase + 4);
    addEdge(bridgeBase + 3, bridgeBase + 5);
    addEdge(bridgeBase + 4, bridgeBase + 5);

    // WING STRUCTURES
    int wingBase = verts.size();
    // Left wing
    addVertex(-220, 0, 100);    // 26
    addVertex(-400, -20, 50);   // 27
    addVertex(-450, 0, -100);   // 28
    addVertex(-350, 20, -250);  // 29

    addEdge(wingBase, wingBase + 1);
    addEdge(wingBase + 1, wingBase + 2);
    addEdge(wingBase + 2, wingBase + 3);
    addEdge(8, wingBase);       // Connect to hull
    addEdge(10, wingBase);

    // Right wing
    int rwBase = verts.size();
    addVertex(220, 0, 100);
    addVertex(400, -20, 50);
    addVertex(450, 0, -100);
    addVertex(350, 20, -250);

    addEdge(rwBase, rwBase + 1);
    addEdge(rwBase + 1, rwBase + 2);
    addEdge(rwBase + 2, rwBase + 3);
    addEdge(9, rwBase);
    addEdge(11, rwBase);

    // ANTENNA ARRAYS
    int antBase = verts.size();
    addVertex(0, -120, 200);
    addVertex(-80, -180, 180);
    addVertex(80, -180, 180);
    addVertex(0, -220, 200);

    addEdge(antBase, antBase + 1);
    addEdge(antBase, antBase + 2);
    addEdge(antBase + 1, antBase + 3);
    addEdge(antBase + 2, antBase + 3);

    // HULL DETAILS - cross braces
    addEdge(0, 5);
    addEdge(1, 4);
    addEdge(4, 9);
    addEdge(5, 8);
    addEdge(8, 13);
    addEdge(9, 12);
    addEdge(12, 17);
    addEdge(13, 16);
  }

  void addVertex(float x, float y, float z) {
    verts.add(new PVector(x, y, z));
  }

  void addEdge(int a, int b) {
    edges.add(new int[] {a, b});
  }

  void drawWireframe(PGraphics pg) {
    pg.beginShape(LINES);
    for (int[] e : edges) {
      if (e[0] < verts.size() && e[1] < verts.size()) {
        PVector a = verts.get(e[0]);
        PVector b = verts.get(e[1]);
        pg.vertex(a.x, a.y, a.z);
        pg.vertex(b.x, b.y, b.z);
      }
    }
    pg.endShape();
  }

  void buildStars() {
    stars = new PVector[500];
    for (int i = 0; i < stars.length; i++) {
      float theta = random(TWO_PI);
      float phi = random(PI);
      float r = random(4000, 10000);
      stars[i] = new PVector(
        r * sin(phi) * cos(theta),
        r * sin(phi) * sin(theta),
        r * cos(phi)
      );
    }
  }

  void drawStars(PGraphics pg) {
    pg.pushStyle();
    pg.noStroke();
    for (int i = 0; i < stars.length; i++) {
      PVector s = stars[i];
      float tw = 1.2 + noise(i * 0.15, totalTime * 0.15) * 1.8;
      float brightness = 120 + 100 * sin(i * 0.2 + totalTime * 0.3);
      pg.fill(brightness, brightness * 0.95, 255, 180);
      pg.pushMatrix();
      pg.translate(s.x, s.y, s.z);
      pg.box(tw);
      pg.popMatrix();
    }
    pg.popStyle();
  }

  public String getName() { return "Capital Ship Flyby"; }
}
