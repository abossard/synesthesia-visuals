class StarfieldWarpLevel extends Level {
  class Star {
    PVector p = new PVector();
    PVector prev = new PVector();
    float speed;
  }
  ArrayList<Star> stars = new ArrayList<Star>();
  
  public void reset() {
    stars.clear();
    for (int i=0;i<500;i++) {
      stars.add(makeStar());
    }
  }
  
  Star makeStar() {
    Star s = new Star();
    s.p.set(random(-1,1)*pgWidthHalf(), random(-1,1)*pgHeightHalf(), random(50, 1200));
    s.prev.set(s.p);
    s.speed = random(160, 320);
    return s;
  }
  
  float pgWidthHalf() { return width/2.0f; }
  float pgHeightHalf() { return height/2.0f; }
  
  public void update(float dt, float t, AudioEnvelope audio) {
    float speedMul = 1.0f + audio.getLevel() * 2.5f;
    for (Star s : stars) {
      s.prev.set(s.p);
      s.p.z -= s.speed * dt * speedMul;
      if (s.p.z < 10) {
        s.p = makeStar().p;
        s.prev.set(s.p);
      }
    }
  }
  
  public void render(PGraphics pg) {
    pg.pushStyle();
    pg.background(4, 6, 12);
    pg.translate(pg.width/2, pg.height/2);
    pg.stroke(180, 220, 255, 180);
    pg.strokeWeight(2);
    for (Star s : stars) {
      float sx = s.p.x / s.p.z * 400;
      float sy = s.p.y / s.p.z * 400;
      float px = s.prev.x / s.prev.z * 400;
      float py = s.prev.y / s.prev.z * 400;
      pg.line(px, py, sx, sy);
    }
    pg.popStyle();
  }
  
  public String getName() { return "Starfield Warp"; }
}

