class MetaballsLevel extends Level {
  class Ball {
    PVector p = new PVector();
    PVector v = new PVector();
    float r;
  }
  ArrayList<Ball> balls = new ArrayList<Ball>();
  
  public void reset() {
    balls.clear();
    for (int i = 0; i < 6; i++) {
      Ball b = new Ball();
      b.p.set(random(-200, 200), random(-150, 150), random(-120, 120));
      b.v = PVector.random3D();
      b.v.mult(random(40, 90));
      b.r = random(50, 100);
      balls.add(b);
    }
  }
  
  public void update(float dt, float t, AudioEnvelope audio) {
    for (Ball b : balls) {
      b.p.add(PVector.mult(b.v, dt));
      if (b.p.x > 240 || b.p.x < -240) b.v.x *= -1;
      if (b.p.y > 180 || b.p.y < -180) b.v.y *= -1;
      if (b.p.z > 200 || b.p.z < -200) b.v.z *= -1;
    }
  }
  
  public void render(PGraphics pg) {
    pg.pushStyle();
    pg.background(6, 6, 12);
    pg.blendMode(ADD);
    pg.translate(pg.width/2, pg.height/2);
    pg.noStroke();
    for (int i = 0; i < balls.size(); i++) {
      Ball b = balls.get(i);
      int c = color(120 + i*20, 200, 255, 80);
      pg.pushMatrix();
      pg.translate(b.p.x, b.p.y);
      pg.fill(c);
      pg.ellipse(0, 0, b.r*2, b.r*2);
      pg.popMatrix();
    }
    pg.blendMode(BLEND);
    pg.popStyle();
  }
  
  public String getName() { return "Metaballs"; }
}

