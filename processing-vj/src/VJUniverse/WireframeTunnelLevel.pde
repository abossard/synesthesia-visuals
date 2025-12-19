/**
 * WireframeTunnelLevel - Cinematic Hyperspace Tunnel
 *
 * A pulsing wireframe tunnel with dynamic camera:
 * - Speed surges with audio
 * - Camera weaves through tunnel
 * - Dramatic acceleration/deceleration
 * - 6DOF shake at high speed
 */
class WireframeTunnelLevel extends Level {
  float zOffset = 0;
  float hueShift = random(1000);
  int ringCount = 30;
  float ringSpacing = 80;

  // Camera
  CinematicCamera cam;
  float tunnelSpeed = 0;
  float targetSpeed = 240;

  // Camera weave
  float weavePhase = 0;
  float weaveAmp = 0;

  // State
  float totalTime = 0;
  int speedPhase = 0;
  float phaseTime = 0;

  WireframeTunnelLevel() {
    cam = new CinematicCamera();
    cam.setSpringParams(3.0, 0.85);
    cam.setNoiseParams(0.2, 3.0, 0.01);
  }

  public void reset() {
    zOffset = 0;
    hueShift = random(1000);
    totalTime = 0;
    tunnelSpeed = 100;
    targetSpeed = 240;
    weavePhase = random(TWO_PI);
    weaveAmp = 0;
    speedPhase = 0;
    phaseTime = 0;

    cam.reset();
    cam.position = new PVector(0, 0, 200);
    cam.lookAt = new PVector(0, 0, -500);
  }

  public void update(float dt, float t, AudioEnvelope audio) {
    totalTime += dt;
    phaseTime += dt;

    // Audio-reactive speed
    float audioBoost = audio.bassLevel * 200 + audio.midLevel * 100;
    updateSpeedPhase(dt, audio);

    // Smooth speed transitions
    tunnelSpeed = lerp(tunnelSpeed, targetSpeed + audioBoost, dt * 2);
    zOffset += dt * tunnelSpeed;

    // Camera weave amplitude based on speed
    float speedNorm = tunnelSpeed / 500;
    weaveAmp = lerp(weaveAmp, 40 + speedNorm * 80, dt * 3);
    weavePhase += dt * (0.5 + speedNorm * 0.5);

    // Adjust noise based on speed
    cam.noiseAmplitude = 2 + speedNorm * 8;
    cam.noiseRotAmplitude = 0.005 + speedNorm * 0.025;

    // Camera weaves through tunnel
    float weaveX = sin(weavePhase) * weaveAmp;
    float weaveY = cos(weavePhase * 0.7) * weaveAmp * 0.6;

    cam.position.x = lerp(cam.position.x, weaveX, dt * 4);
    cam.position.y = lerp(cam.position.y, weaveY, dt * 4);
    cam.position.z = 200;

    // Look ahead with slight offset
    cam.lookAt.x = weaveX * 0.3;
    cam.lookAt.y = weaveY * 0.3;
    cam.lookAt.z = -800;

    // Roll into turns
    float targetRoll = -weaveX * 0.003;
    cam.roll = lerp(cam.roll, targetRoll, dt * 3);

    cam.update(dt);
  }

  void updateSpeedPhase(float dt, AudioEnvelope audio) {
    switch (speedPhase) {
      case 0: // Normal cruise
        targetSpeed = 240;
        if (phaseTime > 4.0 && audio.bassLevel > 0.6) {
          speedPhase = 1;
          phaseTime = 0;
        }
        break;

      case 1: // SURGE - Hyperspeed!
        float surgeProgress = phaseTime / 3.0;
        targetSpeed = 240 + Easing.easeInExpo(min(surgeProgress, 1)) * 600;
        if (phaseTime > 3.0) {
          speedPhase = 2;
          phaseTime = 0;
        }
        break;

      case 2: // Sustain high speed
        targetSpeed = 700;
        if (phaseTime > 2.0) {
          speedPhase = 3;
          phaseTime = 0;
        }
        break;

      case 3: // Decelerate
        float decelProgress = phaseTime / 2.5;
        targetSpeed = 700 - Easing.easeOutCubic(min(decelProgress, 1)) * 460;
        if (phaseTime > 2.5) {
          speedPhase = 0;
          phaseTime = 0;
        }
        break;
    }
  }

  public void render(PGraphics pg) {
    pg.pushStyle();
    pg.background(6, 8, 16);
    pg.noFill();

    // Apply camera
    pg.perspective(PI/2.5, (float)pg.width/pg.height, 1, 5000);
    cam.apply(pg);

    // Speed-based stroke weight
    float speedNorm = tunnelSpeed / 500;
    pg.strokeWeight(2 + speedNorm);

    // Draw tunnel rings
    for (int i = 0; i < ringCount; i++) {
      float rawZ = (i * ringSpacing - (zOffset % (ringCount * ringSpacing)));
      float z = rawZ - 400;

      float tNorm = map(i, 0, ringCount, 0, 1);
      int c = tunnelColor(pg, tNorm, hueShift + totalTime * 0.05);

      // Fade rings based on distance
      float fade = constrain(map(z, -1500, -100, 0, 1), 0, 1);
      pg.stroke(c, (int)(255 * fade));

      // Pulsing radius
      float pulse = 1 + sin(totalTime * 2 + i * 0.3) * 0.1 * speedNorm;
      float radius = (150 + tNorm * 250) * pulse;

      // Draw ring
      pg.pushMatrix();
      pg.translate(0, 0, z);
      drawRing(pg, radius, 36);

      // Spokes (less at high speed for performance)
      int spokeStep = speedNorm > 0.5 ? 8 : 6;
      drawSpokes(pg, radius, 36, spokeStep);
      pg.popMatrix();
    }

    // Speed lines at high speed
    if (speedNorm > 0.4) {
      drawSpeedLines(pg, speedNorm);
    }

    pg.popStyle();
  }

  void drawRing(PGraphics pg, float radius, int steps) {
    pg.beginShape();
    for (int j = 0; j <= steps; j++) {
      float a = map(j, 0, steps, 0, TWO_PI);
      float x = cos(a) * radius;
      float y = sin(a) * radius * 0.8; // Slight oval
      pg.vertex(x, y, 0);
    }
    pg.endShape();
  }

  void drawSpokes(PGraphics pg, float radius, int steps, int spokeStep) {
    pg.beginShape(LINES);
    for (int j = 0; j < steps; j += spokeStep) {
      float a = map(j, 0, steps, 0, TWO_PI);
      float x = cos(a) * radius;
      float y = sin(a) * radius * 0.8;
      pg.vertex(0, 0, 0);
      pg.vertex(x, y, 0);
    }
    pg.endShape();
  }

  void drawSpeedLines(PGraphics pg, float intensity) {
    pg.pushStyle();
    int lineAlpha = (int)(intensity * 150);
    pg.stroke(200, 220, 255, lineAlpha);
    pg.strokeWeight(1);

    int lineCount = (int)(20 * intensity);
    for (int i = 0; i < lineCount; i++) {
      float angle = noise(i * 0.5, totalTime * 0.1) * TWO_PI;
      float dist = 100 + noise(i * 0.3, totalTime * 0.2) * 150;
      float x = cos(angle) * dist;
      float y = sin(angle) * dist * 0.8;
      float len = 200 + intensity * 400;

      pg.line(x, y, -200, x, y, -200 - len);
    }
    pg.popStyle();
  }

  public int tunnelColor(PGraphics pg, float t, float shift) {
    float h = (0.6 + 0.3 * t + shift) % 1.0;
    float s = 0.75;
    float b = 0.95;
    pg.pushStyle();
    pg.colorMode(HSB, 1);
    int c = pg.color(h, s, b, 1);
    pg.popStyle();
    return c;
  }

  public String getName() { return "Wireframe Tunnel"; }
}
