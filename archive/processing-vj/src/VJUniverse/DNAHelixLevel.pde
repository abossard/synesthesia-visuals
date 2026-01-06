class DNAHelixLevel extends Level {
  int segments = 140;
  float twist = 0;
  
  public void reset() {
    twist = random(TWO_PI);
  }
  
  public void update(float dt, float t, AudioEnvelope audio) {
    twist += dt * (0.8f + audio.getBass() * 1.2f);
  }
  
  public void render(PGraphics pg) {
    pg.pushStyle();
    pg.background(10, 10, 18);
    pg.lights();
    pg.translate(pg.width/2, pg.height/2, -180);
    pg.rotateY(time * 0.4f);
    pg.rotateX(0.3f);
    
    pg.strokeWeight(3);
    for (int i = 0; i < segments; i++) {
      float t = (float)i / segments;
      float angle = t * TWO_PI * 3 + twist;
      float radius = 80;
      float y = lerp(-220, 220, t);
      PVector a = new PVector(cos(angle) * radius, y, sin(angle) * radius);
      PVector b = new PVector(cos(angle + PI) * radius, y, sin(angle + PI) * radius);
      int c1 = color(120 + sin(i*0.2f)*80, 200, 255, 220);
      int c2 = color(255, 180 + cos(i*0.3f)*50, 120, 220);
      pg.stroke(c1);
      pg.fill(c1);
      pg.pushMatrix();
      pg.translate(a.x, a.y, a.z);
      pg.sphere(6 + 4 * sin(time * 2 + i*0.1f));
      pg.popMatrix();
      
      pg.stroke(c2);
      pg.fill(c2);
      pg.pushMatrix();
      pg.translate(b.x, b.y, b.z);
      pg.sphere(6 + 4 * sin(time * 2 + i*0.1f + PI));
      pg.popMatrix();
      
      pg.stroke(200, 220, 255, 160);
      pg.line(a.x, a.y, a.z, b.x, b.y, b.z);
    }
    
    pg.popStyle();
  }
  
  public String getName() { return "DNA Helix"; }
}

