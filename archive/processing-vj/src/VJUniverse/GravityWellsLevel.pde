class GravityWellsLevel extends Level {
  class Particle {
    PVector p = new PVector();
    PVector v = new PVector();
  }
  ArrayList<Particle> particles = new ArrayList<Particle>();
  PVector[] wells;
  
  public void reset() {
    particles.clear();
    for (int i = 0; i < 350; i++) {
      Particle p = new Particle();
      p.p.set(random(width) - width/2, random(height) - height/2, random(-100, 100));
      particles.add(p);
    }
    wells = new PVector[]{
      new PVector(-200, -60, 0),
      new PVector(220, 40, -50),
      new PVector(0, 140, 80)
    };
  }
  
  public void update(float dt, float t, AudioEnvelope audio) {
    for (Particle p : particles) {
      for (int i = 0; i < wells.length; i++) {
        PVector f = PVector.sub(wells[i], p.p);
        float d2 = max(60, f.magSq());
        f.normalize();
        f.mult(70000 / d2);
        p.v.add(PVector.mult(f, dt));
      }
      p.v.mult(0.96f);
      p.p.add(PVector.mult(p.v, dt * 60));
    }
  }
  
  public void render(PGraphics pg) {
    pg.pushStyle();
    pg.background(5, 6, 12);
    pg.translate(pg.width/2, pg.height/2);
    pg.noStroke();
    
    // faint trails
    pg.fill(0, 0, 0, 28);
    pg.rectMode(CENTER);
    pg.rect(0, 0, pg.width, pg.height);
    
    // wells
    for (int i = 0; i < wells.length; i++) {
      pg.fill(120 + i*40, 200, 255, 180);
      pg.ellipse(wells[i].x, wells[i].y, 16, 16);
    }
    
    // particles
    pg.fill(180, 220, 255, 170);
    for (Particle p : particles) {
      pg.ellipse(p.p.x, p.p.y, 3, 3);
    }
    pg.popStyle();
  }
  
  public String getName() { return "Gravity Wells"; }
}
