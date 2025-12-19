class GalaxySpiralLevel extends Level {
  int count = 2200;  // Much denser
  float[] radii = new float[count];
  float[] angles = new float[count];
  float[] speeds = new float[count];
  float[] heights = new float[count];
  float twist = random(1000);
  
  public void reset() {
    for (int i = 0; i < count; i++) {
      radii[i] = pow(random(1), 1.6f) * 320 + 20;  // Tighter, more concentrated
      angles[i] = random(TWO_PI);
      speeds[i] = lerp(0.15f, 0.8f, random(1)) * (random(1) > 0.5f ? 1 : -1);
      heights[i] = random(-60, 60);  // Flatter disk
    }
    twist = random(1000);
  }
  
  public void update(float dt, float t, AudioEnvelope audio) {
    twist += dt * (0.2f + audio.getLevel() * 0.6f);
    for (int i = 0; i < count; i++) {
      angles[i] += speeds[i] * dt;
      heights[i] += sin(twist + i * 0.02f) * 0.3f;
    }
  }
  
  public void render(PGraphics pg) {
    pg.pushStyle();
    pg.background(4, 6, 12);
    pg.camera();  // Reset camera to default
    pg.blendMode(ADD);
    pg.hint(DISABLE_DEPTH_TEST);
    
    pg.pushMatrix();
    pg.translate(pg.width/2, pg.height/2, -100);  // Closer to camera
    pg.rotateY(sin(time*0.25f)*0.6f);  // Less extreme rotation
    pg.rotateX(0.5f + sin(time*0.2f)*0.15f);  // Tilt to show disk
    
    for (int i = 0; i < count; i++) {
      float r = radii[i];
      float a = angles[i] + (r/300.0f) * 2.5f;  // Tighter spiral arms
      float h = heights[i];
      float x = cos(a) * r;
      float z = sin(a) * r;
      float y = h;
      int c = galaxyColor(pg, r / 400.0f, i);
      pg.stroke(c);
      pg.strokeWeight(2.8f);  // Larger stars
      pg.point(x, y, z);
    }
    
    pg.popMatrix();
    pg.blendMode(BLEND);
    pg.hint(ENABLE_DEPTH_TEST);
    pg.popStyle();
  }
  
  int galaxyColor(PGraphics pg, float t, int idx) {
    float h = (0.72f + 0.2f * t + sin(idx * 0.008f + twist)*0.04f) % 1.0f;
    float s = 0.5f + 0.3f * t;  // Less saturated = brighter
    float b = 0.75f + 0.25f * (1 - t);  // Brighter overall
    pg.pushStyle();
    pg.colorMode(HSB, 1);
    int c = pg.color(h, s, b, 1);
    pg.popStyle();
    return c;
  }
  
  public String getName() { return "Galaxy Spiral"; }
}

