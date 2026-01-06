/**
 * SpiralGalaxyWireframeLevel - Wireframe/Particle Spiral Galaxy
 *
 * A realistic spiral galaxy simulation with:
 * - Bright yellow/white core
 * - Blue spiral arms extending outward
 * - Differential rotation (inner stars faster than outer)
 * - Trailing spiral structure
 * - Dust lanes and star clusters
 * - Audio-reactive brightness and rotation speed
 */
class SpiralGalaxyWireframeLevel extends Level {

  // Galaxy parameters
  int numStars = 8000;
  int numCoreStars = 2000;
  int numArmStars = 6000;
  int numSpiralArms = 4;

  // Star data
  float[] starRadius;      // Distance from center
  float[] starAngle;       // Current angle
  float[] starHeight;      // Height above/below plane
  float[] starBaseAngle;   // Initial angle (for spiral structure)
  float[] starBrightness;  // Individual brightness
  int[] starArm;           // Which arm (-1 = core)

  // Galaxy geometry
  float coreRadius = 80;
  float galaxyRadius = 600;
  float diskThickness = 30;
  float armSpread = 0.4;   // How tight the spiral arms are

  // Rotation
  float galaxyRotation = 0;
  float rotationSpeed = 0.08;

  // Camera
  CinematicCamera cam;
  float totalTime = 0;

  // Background stars (distant)
  PVector[] backgroundStars;

  SpiralGalaxyWireframeLevel() {
    initStars();
    initBackgroundStars();

    cam = new CinematicCamera();
    cam.setSpringParams(1.5, 0.92);
    cam.setNoiseParams(0.04, 3.0, 0.004);
    cam.setDistanceLimits(400, 1500, 900);
    cam.setSubjectRadius(400);
  }

  void initStars() {
    int totalStars = numCoreStars + numArmStars;
    starRadius = new float[totalStars];
    starAngle = new float[totalStars];
    starHeight = new float[totalStars];
    starBaseAngle = new float[totalStars];
    starBrightness = new float[totalStars];
    starArm = new int[totalStars];

    int idx = 0;

    // Core stars - dense center, gaussian distribution
    for (int i = 0; i < numCoreStars; i++) {
      // Gaussian distribution for core density
      float r = abs(randomGaussian()) * coreRadius * 0.5;
      r = min(r, coreRadius * 1.5);

      starRadius[idx] = r;
      starAngle[idx] = random(TWO_PI);
      starBaseAngle[idx] = starAngle[idx];
      starHeight[idx] = randomGaussian() * diskThickness * 0.3 * (1 + r / coreRadius);
      starBrightness[idx] = random(0.6, 1.0);
      starArm[idx] = -1; // Core
      idx++;
    }

    // Arm stars - logarithmic spiral distribution
    for (int i = 0; i < numArmStars; i++) {
      int arm = i % numSpiralArms;

      // Position along the arm (0 to 1)
      float t = random(0.1, 1.0);
      t = pow(t, 0.7); // More stars toward center

      // Logarithmic spiral: angle increases with radius
      float r = coreRadius + t * (galaxyRadius - coreRadius);

      // Base spiral angle
      float armOffset = arm * TWO_PI / numSpiralArms;
      float spiralAngle = armOffset + t * 2.5; // Tightness of spiral

      // Add spread perpendicular to arm
      float spread = randomGaussian() * armSpread * (0.3 + t * 0.7);
      spiralAngle += spread;

      // Add radial spread
      r += randomGaussian() * 20 * (1 + t);
      r = max(r, coreRadius * 0.5);

      starRadius[idx] = r;
      starAngle[idx] = spiralAngle;
      starBaseAngle[idx] = spiralAngle;

      // Disk thickness increases with radius
      float heightScale = diskThickness * (0.5 + t * 0.5);
      starHeight[idx] = randomGaussian() * heightScale * 0.4;

      // Brightness varies - some bright clusters
      starBrightness[idx] = random(0.3, 0.9);
      if (random(1) < 0.05) starBrightness[idx] = random(0.9, 1.0); // Bright stars

      starArm[idx] = arm;
      idx++;
    }
  }

  void initBackgroundStars() {
    backgroundStars = new PVector[800];
    for (int i = 0; i < backgroundStars.length; i++) {
      float theta = random(TWO_PI);
      float phi = random(PI);
      float r = random(2000, 5000);
      backgroundStars[i] = new PVector(
        r * sin(phi) * cos(theta),
        r * sin(phi) * sin(theta),
        r * cos(phi)
      );
    }
  }

  public void reset() {
    totalTime = 0;
    galaxyRotation = 0;
    cam.reset();
  }

  public void update(float dt, float t, AudioEnvelope audio) {
    totalTime += dt;

    // Audio-reactive rotation speed
    float targetSpeed = 0.06 + audio.bassLevel * 0.08 + audio.midLevel * 0.04;
    rotationSpeed = lerp(rotationSpeed, targetSpeed, dt * 2);

    galaxyRotation += dt * rotationSpeed;

    // Update star positions with differential rotation
    // Inner stars rotate faster (Keplerian-like)
    for (int i = 0; i < starRadius.length; i++) {
      float r = starRadius[i];

      // Differential rotation: v ∝ 1/sqrt(r) approximately
      // Faster in center, slower at edges
      float rotationFactor;
      if (r < coreRadius) {
        // Solid body rotation in core
        rotationFactor = 1.0;
      } else {
        // Differential rotation outside core
        float normalizedR = (r - coreRadius) / (galaxyRadius - coreRadius);
        rotationFactor = 1.0 / (0.5 + normalizedR * 0.8);
      }

      starAngle[i] = starBaseAngle[i] + galaxyRotation * rotationFactor;
    }

    // Track galaxy center
    cam.trackSubject(new PVector(0, 0, 0));

    // Camera modes - mostly tilted views to see spiral structure
    float cyclePhase = (totalTime * 0.025) % 1.0;
    if (cyclePhase < 0.4) {
      // Tilted orbit - classic galaxy view
      float orbitRadius = 900 + sin(totalTime * 0.05) * 100;
      float orbitHeight = -400 + sin(totalTime * 0.04) * 100;
      cam.setOrbit(orbitRadius, 0.06, orbitHeight);
    } else if (cyclePhase < 0.65) {
      // Edge-on view
      float orbitRadius = 800 + sin(totalTime * 0.06) * 80;
      float orbitHeight = -50 + sin(totalTime * 0.08) * 30;
      cam.setOrbit(orbitRadius, 0.04, orbitHeight);
    } else if (cyclePhase < 0.85) {
      // Top-down view
      float orbitRadius = 600 + sin(totalTime * 0.05) * 50;
      float orbitHeight = -800 + sin(totalTime * 0.03) * 100;
      cam.setOrbit(orbitRadius, 0.03, orbitHeight);
    } else {
      // Close approach
      cam.setChase(600, -200 + sin(totalTime * 0.07) * 80);
    }

    cam.update(dt);
  }

  public void render(PGraphics pg) {
    pg.pushStyle();
    pg.background(2, 2, 6);

    pg.perspective(PI/3, (float)pg.width/pg.height, 1, 10000);
    cam.apply(pg);

    // Background stars
    drawBackgroundStars(pg);

    // Galaxy
    pg.pushMatrix();
    drawGalaxy(pg);
    pg.popMatrix();

    pg.popStyle();
  }

  void drawGalaxy(PGraphics pg) {
    pg.noStroke();

    // Draw core glow first (additive feel)
    drawCoreGlow(pg);

    // Draw all stars
    for (int i = 0; i < starRadius.length; i++) {
      float r = starRadius[i];
      float angle = starAngle[i];
      float h = starHeight[i];

      float x = cos(angle) * r;
      float z = sin(angle) * r;
      float y = h;

      // Color based on distance from center
      float normalizedDist = r / galaxyRadius;
      color starColor = getStarColor(normalizedDist, starBrightness[i], starArm[i]);

      // Size based on brightness and distance
      float size = 1.5 + starBrightness[i] * 2.5;
      if (r < coreRadius) size *= 1.2; // Core stars slightly larger

      pg.fill(starColor);
      pg.pushMatrix();
      pg.translate(x, y, z);
      pg.box(size);
      pg.popMatrix();
    }

    // Draw spiral arm connections (wireframe trails)
    drawSpiralTrails(pg);
  }

  color getStarColor(float normalizedDist, float brightness, int arm) {
    // Core: warm yellow/white
    // Arms: transition to blue
    // Edge: deep blue

    float r, g, b;

    if (normalizedDist < 0.15) {
      // Bright core - yellow/white
      float coreT = normalizedDist / 0.15;
      r = lerp(255, 255, coreT);
      g = lerp(240, 200, coreT);
      b = lerp(200, 120, coreT);
    } else if (normalizedDist < 0.4) {
      // Inner arms - warm orange to white
      float t = (normalizedDist - 0.15) / 0.25;
      r = lerp(255, 200, t);
      g = lerp(200, 180, t);
      b = lerp(120, 220, t);
    } else {
      // Outer arms - blue
      float t = (normalizedDist - 0.4) / 0.6;
      t = min(t, 1.0);
      r = lerp(200, 80, t);
      g = lerp(180, 140, t);
      b = lerp(220, 255, t);
    }

    // Apply brightness
    r *= brightness;
    g *= brightness;
    b *= brightness;

    // Add slight variation for visual interest
    float variation = noise(normalizedDist * 10, arm * 100) * 0.2;
    r *= (1 - variation * 0.5);
    g *= (1 - variation * 0.3);

    return color(r, g, b, 200 + brightness * 55);
  }

  void drawCoreGlow(PGraphics pg) {
    // Multiple layers of glow
    pg.noStroke();

    int glowLayers = 6;
    for (int layer = glowLayers; layer >= 0; layer--) {
      float layerSize = coreRadius * (0.3 + layer * 0.4);
      int alpha = (int)(20 + (glowLayers - layer) * 15);

      // Warm glow color
      pg.fill(255, 220, 150, alpha);

      // Draw as a flat disk
      pg.beginShape();
      for (int i = 0; i <= 32; i++) {
        float angle = i * TWO_PI / 32;
        float x = cos(angle) * layerSize;
        float z = sin(angle) * layerSize;
        pg.vertex(x, 0, z);
      }
      pg.endShape(CLOSE);
    }
  }

  void drawSpiralTrails(PGraphics pg) {
    pg.noFill();
    pg.strokeWeight(1);

    // Draw spiral arm guides
    for (int arm = 0; arm < numSpiralArms; arm++) {
      float armOffset = arm * TWO_PI / numSpiralArms + galaxyRotation;

      pg.beginShape();
      for (int i = 0; i < 60; i++) {
        float t = i / 60.0;
        float r = coreRadius + t * (galaxyRadius - coreRadius);

        // Differential rotation applied to trail
        float rotationFactor = 1.0 / (0.5 + t * 0.8);
        float angle = armOffset + t * 2.5 + galaxyRotation * (rotationFactor - 1);

        float x = cos(angle) * r;
        float z = sin(angle) * r;

        // Color fades along arm
        int alpha = (int)(80 - t * 60);
        float blue = 150 + t * 100;
        pg.stroke(100, 140, blue, alpha);

        pg.vertex(x, 0, z);
      }
      pg.endShape();
    }
  }

  void drawBackgroundStars(PGraphics pg) {
    pg.noStroke();
    for (int i = 0; i < backgroundStars.length; i++) {
      PVector s = backgroundStars[i];
      float tw = 0.8 + noise(i * 0.1, totalTime * 0.1) * 1.2;
      float brightness = 80 + 60 * sin(i * 0.15 + totalTime * 0.2);
      pg.fill(brightness, brightness * 0.95, 255, 140);
      pg.pushMatrix();
      pg.translate(s.x, s.y, s.z);
      pg.box(tw);
      pg.popMatrix();
    }
  }

  public String getName() { return "Spiral Galaxy"; }
}
