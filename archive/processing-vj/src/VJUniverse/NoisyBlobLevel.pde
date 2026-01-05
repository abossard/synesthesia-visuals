class NoisyBlobLevel extends Level {
  class SoftBlob {
    PVector pos = new PVector();
    PVector vel = new PVector();
    float baseRadius;
    float orbitRadius;
    float colorPhase;
    float noiseSeed;
    float spinDir;
  }
  
  ArrayList<SoftBlob> blobs = new ArrayList<SoftBlob>();
  float globalRot = 0;
  float paletteShift = random(1000);
  int fogColor = color(12, 10, 20);
  
  NoisyBlobLevel() {
    reset();
  }
  
  public void reset() {
    blobs.clear();
    int blobCount = 8;
    for (int i = 0; i < blobCount; i++) {
      SoftBlob b = new SoftBlob();
      b.baseRadius = random(60, 130);
      b.orbitRadius = random(150, 320);
      b.colorPhase = random(TWO_PI);
      b.noiseSeed = random(1000);
      b.spinDir = random(1) > 0.5f ? 1 : -1;
      float a = random(TWO_PI);
      b.pos.set(cos(a) * b.orbitRadius, random(-120, 120), sin(a) * b.orbitRadius);
      blobs.add(b);
    }
    globalRot = 0;
  }
  
  public void update(float dt, float t, AudioEnvelope audio) {
    globalRot += dt * 0.25f;
    
    // Pairwise soft push to keep blobs separated
    for (int i = 0; i < blobs.size(); i++) {
      SoftBlob a = blobs.get(i);
      for (int j = i + 1; j < blobs.size(); j++) {
        SoftBlob b = blobs.get(j);
        PVector diff = PVector.sub(a.pos, b.pos);
        float dist = max(1, diff.mag());
        float minDist = (a.baseRadius + b.baseRadius) * 0.55f;
        if (dist < minDist) {
          diff.normalize();
          float push = (minDist - dist) * 0.6f;
          a.vel.add(PVector.mult(diff, push * 0.5f));
          b.vel.sub(PVector.mult(diff, push * 0.5f));
        }
      }
    }
    
    for (int i = 0; i < blobs.size(); i++) {
      SoftBlob b = blobs.get(i);
      
      // Orbit target driven by smooth sinusoids (non-audio-reactive)
      float orbitAngle = t * 0.35f + b.colorPhase * 0.7f;
      float wobble = sin(t * 0.6f + b.colorPhase) * 70;
      PVector target = new PVector(
        cos(orbitAngle) * b.orbitRadius,
        wobble * 0.4f + sin(t * 0.25f + b.colorPhase) * 80,
        sin(orbitAngle * 1.15f) * b.orbitRadius * 0.75f
      );
      
      // Force toward target
      PVector toTarget = PVector.sub(target, b.pos);
      toTarget.mult(0.5f);
      
      // Swirl around Y to keep motion lively
      PVector swirl = new PVector(-b.pos.z, 0, b.pos.x);
      swirl.mult(0.0015f * b.spinDir);
      
      // Gentle noise drift
      PVector noiseForce = new PVector(
        noise(b.noiseSeed + t * 0.25f, 10, 20) - 0.5f,
        noise(b.noiseSeed + t * 0.25f, 30, 40) - 0.5f,
        noise(b.noiseSeed + t * 0.25f, 50, 60) - 0.5f
      );
      noiseForce.mult(50);
      
      // Integrate
      PVector accel = new PVector();
      accel.add(toTarget);
      accel.add(swirl);
      accel.add(noiseForce);
      b.vel.add(PVector.mult(accel, dt));
      b.vel.mult(0.93f); // damping
      b.pos.add(PVector.mult(b.vel, dt));
    }
  }
  
  public void render(PGraphics pg) {
    pg.pushStyle();
    pg.colorMode(RGB, 255);
    
    // Soft gradient background
    pg.noStroke();
    for (int y = 0; y < pg.height; y += 4) {
      float t = map(y, 0, pg.height, 0, 1);
      int c = lerpColor(color(10, 8, 18), color(24, 14, 34), t);
      pg.fill(c);
      pg.rect(0, y, pg.width, 4);
    }
    
    pg.lights();
    pg.ambientLight(28, 28, 40);
    pg.directionalLight(140, 120, 180, -0.6f, -0.2f, -1);
    pg.directionalLight(60, 80, 200, 0.4f, 0.7f, 0.9f);
    pg.pointLight(220, 220, 255, 0, -200, 320);
    pg.pointLight(120, 160, 255, -260, 180, -200);
    
    pg.pushMatrix();
    pg.translate(pg.width * 0.5f, pg.height * 0.5f, -200);
    pg.rotateY(globalRot);
    pg.rotateX(sin(globalRot * 0.7f) * 0.35f);
    pg.rotateZ(cos(globalRot * 0.55f) * 0.2f);
    
    // Draw solid blobs
    for (int i = 0; i < blobs.size(); i++) {
      SoftBlob b = blobs.get(i);
      float dist = b.pos.mag();
      float fog = constrain(map(dist, 120, 520, 0.05f, 0.68f), 0, 0.8f);
      int blobColor = softColor(pg, i, globalRot, fog);
      pg.pushMatrix();
      pg.translate(b.pos.x, b.pos.y, b.pos.z);
      pg.rotateY(globalRot * 0.6f + b.spinDir * 0.4f);
      pg.rotateX(sin(globalRot + b.colorPhase) * 0.3f);
      
      pg.fill(blobColor, 215 * (1 - fog * 0.4f));
      pg.emissive(red(blobColor) * 0.18f, green(blobColor) * 0.18f, blue(blobColor) * 0.18f);
      pg.specular(255);
      pg.shininess(32);
      drawNoisySphere(pg, b.baseRadius, b.noiseSeed, globalRot * 0.6f + b.colorPhase);

      // Comic-style outline pass
      pg.noFill();
      pg.stroke(15, 30, 60, 160);
      pg.strokeWeight(2.2f);
      drawNoisySphere(pg, b.baseRadius * 1.03f, b.noiseSeed + 10, globalRot * 0.6f + b.colorPhase);
      pg.popMatrix();
    }
    
    // Glow layer (additive)
    pg.hint(DISABLE_DEPTH_TEST);
    pg.blendMode(ADD);
    for (int i = 0; i < blobs.size(); i++) {
      SoftBlob b = blobs.get(i);
      int blobColor = softColor(pg, i, globalRot, 0);
      float glowBase = b.baseRadius * 2.8f;
      pg.pushMatrix();
      pg.translate(b.pos.x, b.pos.y, b.pos.z);
      pg.noStroke();
      pg.fill(blobColor, 36);
      pg.ellipse(0, 0, glowBase * 1.6f, glowBase * 1.6f);
      pg.fill(blobColor, 20);
      pg.ellipse(0, 0, glowBase * 2.3f, glowBase * 2.3f);
      pg.popMatrix();
    }
    pg.blendMode(BLEND);
    pg.hint(ENABLE_DEPTH_TEST);
    
    // Fog overlay
    pg.noStroke();
    pg.fill(fogColor, 75);
    pg.rect(0, 0, pg.width, pg.height);
    
    pg.popMatrix();
    pg.popStyle();
  }
  
  public int softColor(PGraphics pg, int index, float t, float fog) {
    float hue = (0.55f + 0.12f * sin(t * 0.35f + paletteShift + index * 0.6f) + 0.18f * cos(t * 0.21f + index * 0.45f)) % 1.0f;
    float sat = 0.65f + 0.15f * sin(t * 0.28f + index) - fog * 0.15f;
    float bri = 0.9f - fog * 0.25f;
    pg.pushStyle();
    pg.colorMode(HSB, 1);
    int c = pg.color((hue + 1) % 1.0f, constrain(sat, 0.45f, 1.0f), bri, 1);
    pg.popStyle();
    return c;
  }
  
  public void drawNoisySphere(PGraphics pg, float radius, float seed, float t) {
    int latSteps = 24;
    int lonSteps = 32;
    for (int i = 0; i < latSteps; i++) {
      float theta1 = map(i, 0, latSteps, -HALF_PI, HALF_PI);
      float theta2 = map(i + 1, 0, latSteps, -HALF_PI, HALF_PI);
      pg.beginShape(TRIANGLE_STRIP);
      for (int j = 0; j <= lonSteps; j++) {
        float phi = map(j, 0, lonSteps, -PI, PI);
        addNoisyVertex(pg, theta1, phi, radius, seed, t);
        addNoisyVertex(pg, theta2, phi, radius, seed, t);
      }
      pg.endShape();
    }
  }
  
  public void addNoisyVertex(PGraphics pg, float theta, float phi, float radius, float seed, float t) {
    float nx = cos(theta) * cos(phi);
    float ny = sin(theta);
    float nz = cos(theta) * sin(phi);
    float noiseVal = noise(seed + nx * 1.3f + 3, seed + ny * 1.3f + 7, t * 0.35f + seed * 0.1f);
    float r = radius * (0.8f + noiseVal * 0.45f);
    pg.normal(nx, ny, nz);
    pg.vertex(nx * r, ny * r, nz * r);
  }
  
  public String getName() {
    return "Noisy Blobs";
  }
}
