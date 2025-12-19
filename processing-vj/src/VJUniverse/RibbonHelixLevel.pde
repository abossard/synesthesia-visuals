class RibbonHelixLevel extends Level {
  int ribbonCount = 3;
  int segments = 140;
  float spin = 0;
  
  public void reset() {
    spin = random(TWO_PI);
  }
  
  public void update(float dt, float t, AudioEnvelope audio) {
    spin += dt * 0.35f;
  }
  
  public void render(PGraphics pg) {
    pg.pushStyle();
    pg.background(8, 10, 18);
    pg.camera();  // Reset camera to default
    pg.lights();
    pg.ambientLight(30, 30, 40);
    pg.directionalLight(200, 180, 255, -0.4f, -0.6f, -1);
    pg.directionalLight(120, 200, 255, 0.4f, 0.5f, 0.7f);
    
    pg.pushMatrix();
    pg.translate(pg.width * 0.5f, pg.height * 0.5f, -200);
    pg.rotateY(spin * 0.6f);
    pg.rotateX(0.4f + sin(spin * 0.5f) * 0.2f);
    
    for (int r = 0; r < ribbonCount; r++) {
      float phase = spin + r * TWO_PI / ribbonCount;
      int c = ribbonColor(pg, r);
      pg.fill(c, 160);
      pg.stroke(20, 30, 60, 140);
      pg.beginShape(TRIANGLE_STRIP);
      for (int i = 0; i <= segments; i++) {
        float t = (float)i / segments;
        float angle = t * TWO_PI * 2 + phase;
        float radius = 240 + sin(t * TWO_PI * 1.5f + phase) * 60;
        float y = sin(t * TWO_PI * 1.2f + phase) * 180;
        PVector center = new PVector(cos(angle) * radius, y, sin(angle) * radius);
        
        // local normal for ribbon width
        PVector tangent = new PVector(-sin(angle) * radius, cos(t * TWO_PI * 1.2f + phase) * 180 * TWO_PI * 1.2f, cos(angle) * radius);
        tangent.normalize();
        PVector up = new PVector(0, 1, 0);
        PVector side = tangent.cross(up);
        side.normalize();
        
        float halfW = 16 + 10 * sin(t * TWO_PI * 3 + phase);
        PVector left = PVector.add(center, PVector.mult(side, -halfW));
        PVector right = PVector.add(center, PVector.mult(side, halfW));
        
        pg.vertex(left.x, left.y, left.z);
        pg.vertex(right.x, right.y, right.z);
      }
      pg.endShape();
    }
    
    pg.popMatrix();
    pg.popStyle();
  }
  
  public int ribbonColor(PGraphics pg, int idx) {
    pg.pushStyle();
    pg.colorMode(HSB, 1);
    int c = pg.color((0.05f + idx * 0.22f) % 1.0f, 0.7f, 0.95f, 1);
    pg.popStyle();
    return c;
  }
  
  public String getName() { return "Ribbon Helix"; }
}
