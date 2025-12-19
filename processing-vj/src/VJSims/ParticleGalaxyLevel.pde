class ParticleGalaxyLevel extends Level {
  int count = 520;
  float[] radii = new float[count];
  float[] angles = new float[count];
  float[] speeds = new float[count];
  float[] heights = new float[count];
  float twist = 0;
  
  ParticleGalaxyLevel() { reset(); }
  
  public void reset() {
    for (int i = 0; i < count; i++) {
      radii[i] = pow(random(1), 1.6f) * 400 + 40;
      angles[i] = random(TWO_PI);
      speeds[i] = lerp(0.1f, 1.2f, random(1)) * (random(1) > 0.5f ? 1 : -1);
      heights[i] = random(-180, 180);
    }
    twist = random(1000);
  }
  
  public void update(float dt, float t, AudioEnvelope audio) {
    twist += dt * 0.25f;
    for (int i = 0; i < count; i++) {
      angles[i] += speeds[i] * dt;
      heights[i] += sin(twist + i * 0.02f) * 0.2f;
    }
  }
  
  public void render(PGraphics pg) {
    pg.pushStyle();
    pg.background(5, 6, 14);
    pg.noLights();
    pg.hint(DISABLE_DEPTH_TEST);
    pg.blendMode(ADD);
    
    pg.pushMatrix();
    pg.translate(pg.width * 0.5f, pg.height * 0.5f, -200);
    pg.rotateY(sin(time * 0.2f) * 0.8f + 0.3f);
    pg.rotateX(0.4f + sin(time * 0.17f) * 0.2f);
    
    for (int i = 0; i < count; i++) {
      float r = radii[i];
      float a = angles[i];
      float h = heights[i] + sin(twist + i * 0.01f) * 30;
      float x = cos(a) * r;
      float z = sin(a) * r;
      float y = h * 0.9f;
      
      int c = galaxyColor(pg, r / 500.0f, i);
      pg.stroke(c);
      pg.strokeWeight(2.2f);
      pg.point(x, y, z);
    }
    
    // Nebula lines
    pg.stroke(140, 80, 255, 35);
    pg.strokeWeight(1.2f);
    int trails = 80;
    for (int i = 0; i < trails; i++) {
      int idx = (int)random(count);
      float r = radii[idx];
      float a = angles[idx];
      float h = heights[idx];
      float x = cos(a) * r;
      float z = sin(a) * r;
      float y = h * 0.9f;
      pg.line(0, 0, 0, x, y, z);
    }
    
    pg.popMatrix();
    pg.blendMode(BLEND);
    pg.hint(ENABLE_DEPTH_TEST);
    pg.popStyle();
  }
  
  public int galaxyColor(PGraphics pg, float t, int idx) {
    float h = (0.72f + 0.18f * t + sin(idx * 0.01f + twist) * 0.05f) % 1.0f;
    float s = 0.6f + 0.3f * t;
    float b = 0.6f + 0.4f * (1 - t);
    pg.pushStyle();
    pg.colorMode(HSB, 1);
    int c = pg.color(h, s, b, 1);
    pg.popStyle();
    return c;
  }
  
  public String getName() { return "Particle Galaxy"; }
}
