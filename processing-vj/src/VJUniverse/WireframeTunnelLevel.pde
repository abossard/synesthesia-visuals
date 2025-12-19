class WireframeTunnelLevel extends Level {
  float zOffset = 0;
  float hueShift = random(1000);
  int ringCount = 26;
  float ringSpacing = 60;
  
  public void reset() {
    zOffset = 0;
    hueShift = random(1000);
  }
  
  public void update(float dt, float t, AudioEnvelope audio) {
    zOffset += dt * 240;
  }
  
  public void render(PGraphics pg) {
    pg.pushStyle();
    pg.background(6, 8, 16);
    pg.noFill();
    pg.strokeWeight(2);
    
    pg.pushMatrix();
    pg.translate(pg.width * 0.5f, pg.height * 0.5f, 0);
    pg.rotateX(0.35f + sin(time * 0.2f) * 0.1f);
    pg.rotateY(sin(time * 0.27f) * 0.6f);
    
    for (int i = 0; i < ringCount; i++) {
      float z = (i * ringSpacing - (zOffset % (ringCount * ringSpacing))) - 200;
      float tNorm = map(i, 0, ringCount, 0, 1);
      int c = tunnelColor(pg, tNorm, hueShift + time * 0.05f);
      pg.stroke(c);
      
      float radius = 120 + tNorm * 320 + sin(time * 0.8f + i * 0.4f) * 30;
      pg.beginShape();
      int steps = 42;
      for (int j = 0; j <= steps; j++) {
        float a = map(j, 0, steps, 0, TWO_PI);
        float x = cos(a) * radius;
        float y = sin(a) * radius * 0.7f;
        pg.vertex(x, y, z);
      }
      pg.endShape();
      
      // Spokes for comic feel
      pg.beginShape(LINES);
      for (int j = 0; j < steps; j += 6) {
        float a = map(j, 0, steps, 0, TWO_PI);
        float x = cos(a) * radius;
        float y = sin(a) * radius * 0.7f;
        pg.vertex(0, 0, z);
        pg.vertex(x, y, z);
      }
      pg.endShape();
    }
    
    pg.popMatrix();
    pg.popStyle();
  }
  
  public int tunnelColor(PGraphics pg, float t, float shift) {
    float h = (0.6f + 0.3f * t + shift) % 1.0f;
    float s = 0.75f;
    float b = 0.95f;
    pg.pushStyle();
    pg.colorMode(HSB, 1);
    int c = pg.color(h, s, b, 1);
    pg.popStyle();
    return c;
  }
  
  public String getName() { return "Wireframe Tunnel"; }
}
