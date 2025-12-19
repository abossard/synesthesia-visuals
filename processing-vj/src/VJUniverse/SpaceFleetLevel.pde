/**
 * SpaceFleetLevel - Wireframe Fleet in Formation
 *
 * Uses the improved CinematicCamera for smooth, subject-locked filming.
 * Fleet always stays ~85% visible on screen.
 */
class SpaceFleetLevel extends Level {
  // Fleet
  ArrayList<FleetShip> ships = new ArrayList<FleetShip>();
  PVector fleetCenter;
  PVector fleetVelocity;
  float fleetYaw = 0;

  // Formation parameters
  float formationTightness = 1.0;
  float targetTightness = 1.0;

  // Camera
  CinematicCamera cam;
  float totalTime = 0;

  // Stars
  PVector[] stars;

  SpaceFleetLevel() {
    buildFleet();
    buildStars();

    cam = new CinematicCamera();
    cam.setSpringParams(2.2, 0.88);
    cam.setNoiseParams(0.1, 5.0, 0.012);
    cam.setDistanceLimits(400, 1200, 700);  // Fleet spans ~600 units
    cam.setSubjectRadius(350);

    fleetCenter = new PVector(0, 0, 0);
    fleetVelocity = new PVector(0, 0, 0);
  }

  void buildFleet() {
    ships.clear();

    // Lead ship (larger cruiser)
    ships.add(new FleetShip(FleetShip.TYPE_CRUISER, new PVector(0, 0, 0)));

    // Wing leaders
    ships.add(new FleetShip(FleetShip.TYPE_FIGHTER, new PVector(-150, -30, -100)));
    ships.add(new FleetShip(FleetShip.TYPE_FIGHTER, new PVector(150, -30, -100)));

    // Second row
    ships.add(new FleetShip(FleetShip.TYPE_BOMBER, new PVector(-100, 20, -200)));
    ships.add(new FleetShip(FleetShip.TYPE_BOMBER, new PVector(100, 20, -200)));

    // Outer wings
    ships.add(new FleetShip(FleetShip.TYPE_FIGHTER, new PVector(-280, -50, -180)));
    ships.add(new FleetShip(FleetShip.TYPE_FIGHTER, new PVector(280, -50, -180)));

    // Rear guard
    ships.add(new FleetShip(FleetShip.TYPE_FIGHTER, new PVector(-200, 0, -320)));
    ships.add(new FleetShip(FleetShip.TYPE_FIGHTER, new PVector(200, 0, -320)));
    ships.add(new FleetShip(FleetShip.TYPE_CRUISER, new PVector(0, 30, -400)));
  }

  void buildStars() {
    stars = new PVector[450];
    for (int i = 0; i < stars.length; i++) {
      float theta = random(TWO_PI);
      float phi = random(PI);
      float r = random(3000, 8000);
      stars[i] = new PVector(
        r * sin(phi) * cos(theta),
        r * sin(phi) * sin(theta),
        r * cos(phi)
      );
    }
  }

  public void reset() {
    totalTime = 0;
    fleetYaw = 0;
    formationTightness = 1.0;
    targetTightness = 1.0;

    fleetCenter = new PVector(0, 0, 0);
    fleetVelocity = new PVector(0, 0, 120);  // Fleet moves forward

    for (FleetShip ship : ships) ship.reset();
    cam.reset();
  }

  public void update(float dt, float t, AudioEnvelope audio) {
    totalTime += dt;

    // Fleet movement
    fleetCenter.add(PVector.mult(fleetVelocity, dt));
    fleetYaw += dt * 0.03;

    // Audio-reactive formation tightening
    targetTightness = 0.7 + audio.bassLevel * 0.5;
    formationTightness = lerp(formationTightness, targetTightness, dt * 3);

    // Update each ship
    for (FleetShip ship : ships) {
      ship.update(dt, fleetCenter, formationTightness, audio);
    }

    // Track the fleet center
    cam.trackSubject(fleetCenter);

    // Smoothly vary camera - fleet uses mixed modes
    float cyclePhase = (totalTime * 0.035) % 1.0;
    if (cyclePhase < 0.5) {
      // Wide orbit - see entire formation
      float orbitRadius = 800 + sin(totalTime * 0.08) * 100;
      float orbitHeight = -150 + sin(totalTime * 0.1) * 80;
      cam.setOrbit(orbitRadius, 0.18, orbitHeight);
    } else if (cyclePhase < 0.75) {
      // Chase - follow from behind
      cam.setChase(600, 100 + sin(totalTime * 0.12) * 40);
    } else {
      // Side follow
      PVector offset = new PVector(
        500 + sin(totalTime * 0.1) * 80,
        -80 + sin(totalTime * 0.08) * 40,
        -100
      );
      cam.setFollow(offset);
    }

    cam.update(dt);
  }

  public void render(PGraphics pg) {
    pg.pushStyle();
    pg.background(4, 4, 10);

    pg.perspective(PI/3, (float)pg.width/pg.height, 1, 15000);
    cam.apply(pg);

    drawStars(pg);

    // Draw all ships
    pg.pushMatrix();
    pg.rotateY(fleetYaw);

    for (int i = 0; i < ships.size(); i++) {
      FleetShip ship = ships.get(i);
      // Lead ship (index 0) is always highlighted
      ship.draw(pg, fleetCenter, i == 0);
    }

    pg.popMatrix();
    pg.popStyle();
  }

  void drawStars(PGraphics pg) {
    pg.pushStyle();
    pg.noStroke();
    for (int i = 0; i < stars.length; i++) {
      PVector s = stars[i];
      float tw = 0.8 + noise(i * 0.1, totalTime * 0.2) * 1.4;
      float brightness = 130 + 100 * sin(i * 0.2 + totalTime * 0.35);
      pg.fill(brightness, brightness * 0.95, 255, 170);
      pg.pushMatrix();
      pg.translate(s.x, s.y, s.z);
      pg.box(tw);
      pg.popMatrix();
    }
    pg.popStyle();
  }

  public String getName() { return "Space Fleet"; }

  // ============================================
  // INNER CLASS: FleetShip
  // ============================================
  class FleetShip {
    static final int TYPE_FIGHTER = 0;
    static final int TYPE_BOMBER = 1;
    static final int TYPE_CRUISER = 2;

    int type;
    PVector formationPos;  // Position relative to fleet center
    PVector breakOffset;   // Offset when formation breaks
    float roll, pitch, yaw;
    float engineGlow = 0.5;

    // Geometry
    PVector[] verts;
    int[][] edges;

    FleetShip(int type, PVector formPos) {
      this.type = type;
      this.formationPos = formPos.copy();
      this.breakOffset = new PVector(0, 0, 0);
      buildGeometry();
    }

    void reset() {
      roll = 0;
      pitch = 0;
      yaw = 0;
      engineGlow = 0.5;
      breakOffset.set(0, 0, 0);
    }

    void update(float dt, PVector fleetCenter, float tightness, AudioEnvelope audio) {
      // Slight individual motion
      float wobbleFreq = 0.8 + type * 0.2;
      pitch = sin(time * wobbleFreq + formationPos.x * 0.01) * 0.05;
      roll = sin(time * wobbleFreq * 0.7 + formationPos.y * 0.01) * 0.08;

      // Audio-reactive engine
      float targetGlow = 0.4 + audio.bassLevel * 0.4 + audio.midLevel * 0.2;
      engineGlow = lerp(engineGlow, targetGlow, dt * 5);
    }

    PVector getWorldPosition(PVector fleetCenter) {
      PVector pos = PVector.add(fleetCenter, formationPos);
      pos.add(breakOffset);
      return pos;
    }

    void draw(PGraphics pg, PVector fleetCenter, boolean highlighted) {
      PVector worldPos = getWorldPosition(fleetCenter);

      pg.pushMatrix();
      pg.translate(worldPos.x, worldPos.y, worldPos.z);
      pg.rotateY(yaw);
      pg.rotateX(pitch);
      pg.rotateZ(roll);

      pg.noFill();

      // Ship color based on type
      if (highlighted) {
        pg.stroke(255, 200, 100);
        pg.strokeWeight(3);
      } else {
        switch (type) {
          case TYPE_FIGHTER:
            pg.stroke(100, 200, 255);
            pg.strokeWeight(2);
            break;
          case TYPE_BOMBER:
            pg.stroke(255, 150, 100);
            pg.strokeWeight(2.5);
            break;
          case TYPE_CRUISER:
            pg.stroke(150, 255, 150);
            pg.strokeWeight(2.5);
            break;
        }
      }

      // Draw wireframe
      drawWireframe(pg);

      // Engine glow
      drawEngines(pg);

      pg.popMatrix();
    }

    void drawWireframe(PGraphics pg) {
      pg.beginShape(LINES);
      for (int[] e : edges) {
        PVector a = verts[e[0]];
        PVector b = verts[e[1]];
        pg.vertex(a.x, a.y, a.z);
        pg.vertex(b.x, b.y, b.z);
      }
      pg.endShape();
    }

    void drawEngines(PGraphics pg) {
      pg.pushStyle();
      int alpha = (int)(80 + engineGlow * 170);

      float[][] enginePositions;
      float thrustLen;

      switch (type) {
        case TYPE_FIGHTER:
          enginePositions = new float[][] {{0, 0, -50}};
          thrustLen = 20 + engineGlow * 40;
          pg.stroke(80, 180, 255, alpha);
          break;
        case TYPE_BOMBER:
          enginePositions = new float[][] {{-20, 5, -60}, {20, 5, -60}};
          thrustLen = 25 + engineGlow * 50;
          pg.stroke(255, 150, 80, alpha);
          break;
        default: // CRUISER
          enginePositions = new float[][] {{-30, 10, -100}, {30, 10, -100}, {0, 20, -100}};
          thrustLen = 35 + engineGlow * 70;
          pg.stroke(150, 255, 150, alpha);
          break;
      }

      pg.strokeWeight(2 + engineGlow * 2);
      for (float[] e : enginePositions) {
        pg.line(e[0], e[1], e[2], e[0], e[1], e[2] - thrustLen);
      }

      pg.popStyle();
    }

    void buildGeometry() {
      switch (type) {
        case TYPE_FIGHTER:
          buildFighter();
          break;
        case TYPE_BOMBER:
          buildBomber();
          break;
        case TYPE_CRUISER:
          buildCruiser();
          break;
      }
    }

    void buildFighter() {
      verts = new PVector[] {
        new PVector(0, 0, 60),     // nose
        new PVector(-25, -8, 20),  // left front
        new PVector(25, -8, 20),   // right front
        new PVector(-40, -5, -30), // left mid
        new PVector(40, -5, -30),  // right mid
        new PVector(-20, 8, -50),  // left rear
        new PVector(20, 8, -50),   // right rear
        new PVector(0, 0, -60),    // tail
        new PVector(-70, -3, -10), // left wing
        new PVector(70, -3, -10)   // right wing
      };

      edges = new int[][] {
        {0,1},{0,2},{1,2},
        {1,3},{2,4},{3,4},
        {3,5},{4,6},{5,6},{5,7},{6,7},
        {1,8},{3,8},{8,5},
        {2,9},{4,9},{9,6}
      };
    }

    void buildBomber() {
      verts = new PVector[] {
        new PVector(0, 0, 70),     // nose
        new PVector(-35, -12, 30), // left front
        new PVector(35, -12, 30),  // right front
        new PVector(-45, -10, -20),// left mid
        new PVector(45, -10, -20), // right mid
        new PVector(-40, 15, -60), // left rear
        new PVector(40, 15, -60),  // right rear
        new PVector(0, 10, -80),   // tail
        new PVector(-80, -5, 0),   // left wing
        new PVector(80, -5, 0),    // right wing
        new PVector(0, 25, -30)    // dorsal
      };

      edges = new int[][] {
        {0,1},{0,2},{1,2},
        {1,3},{2,4},{3,4},
        {3,5},{4,6},{5,6},{5,7},{6,7},
        {1,8},{3,8},{8,5},
        {2,9},{4,9},{9,6},
        {3,10},{4,10},{10,5},{10,6}
      };
    }

    void buildCruiser() {
      verts = new PVector[] {
        new PVector(0, -10, 100),  // nose
        new PVector(-40, -15, 50), // left front
        new PVector(40, -15, 50),  // right front
        new PVector(-60, -20, 0),  // left mid upper
        new PVector(60, -20, 0),   // right mid upper
        new PVector(-60, 20, 0),   // left mid lower
        new PVector(60, 20, 0),    // right mid lower
        new PVector(-50, -15, -70),// left rear upper
        new PVector(50, -15, -70), // right rear upper
        new PVector(-50, 25, -70), // left rear lower
        new PVector(50, 25, -70),  // right rear lower
        new PVector(0, 30, -100),  // tail
        new PVector(-100, 0, -20), // left wing
        new PVector(100, 0, -20),  // right wing
        new PVector(0, -40, 20)    // bridge
      };

      edges = new int[][] {
        {0,1},{0,2},{1,2},
        {1,3},{2,4},{1,5},{2,6},
        {3,4},{5,6},{3,5},{4,6},
        {3,7},{4,8},{5,9},{6,10},
        {7,8},{9,10},{7,9},{8,10},
        {7,11},{8,11},{9,11},{10,11},
        {3,12},{5,12},{12,7},{12,9},
        {4,13},{6,13},{13,8},{13,10},
        {1,14},{2,14},{14,3},{14,4}
      };
    }
  }
}
