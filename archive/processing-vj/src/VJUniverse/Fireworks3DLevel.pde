class Fireworks3DLevel extends Level {
  class Particle {
    PVector p, v;
    float life;
    Particle(PVector p, PVector v, float life) { this.p=p; this.v=v; this.life=life; }
  }
  class Rocket {
    PVector p, v;
    boolean exploded=false;
    Rocket(PVector p, PVector v){this.p=p; this.v=v;}
  }
  ArrayList<Rocket> rockets = new ArrayList<Rocket>();
  ArrayList<Particle> parts = new ArrayList<Particle>();
  
  public void reset() {
    rockets.clear(); parts.clear();
  }
  
  public void update(float dt, float t, AudioEnvelope audio) {
    if (frameCount % 30 == 0 || audio.getLevel() > 0.65f) {
      spawnRocket();
    }
    // rockets
    for (int i = rockets.size()-1; i>=0; i--) {
      Rocket r = rockets.get(i);
      r.p.add(PVector.mult(r.v, dt));
      r.v.y += 180 * dt * -1;
      if (!r.exploded && r.v.y < -40) {
        explode(r.p.copy());
        r.exploded = true;
        rockets.remove(i);
      }
    }
    // particles
    for (int i = parts.size()-1; i>=0; i--) {
      Particle p = parts.get(i);
      p.p.add(PVector.mult(p.v, dt));
      p.v.y += 120 * dt;
      p.v.mult(0.99f);
      p.life -= dt;
      if (p.life <= 0) parts.remove(i);
    }
  }
  
  void spawnRocket() {
    rockets.add(new Rocket(new PVector(random(-200,200), 200, random(-40, 40)), new PVector(0, -260, 0)));
  }
  
  void explode(PVector pos) {
    int n = 140;
    for (int i=0; i<n; i++) {
      PVector dir = PVector.random3D();
      dir.mult(random(120, 260));
      parts.add(new Particle(pos.copy(), dir, 1.6f));
    }
  }
  
  public void render(PGraphics pg) {
    pg.pushStyle();
    pg.background(5, 6, 12);
    pg.blendMode(ADD);
    pg.translate(pg.width/2, pg.height/2, -120);
    pg.strokeWeight(2.5f);
    pg.stroke(255, 180, 120);
    for (Rocket r : rockets) {
      pg.point(r.p.x, r.p.y, r.p.z);
    }
    pg.strokeWeight(2);
    for (Particle p : parts) {
      float a = map(p.life, 0, 1.6f, 0, 255);
      pg.stroke(120 + p.life*80, 200, 255, a);
      pg.point(p.p.x, p.p.y, p.p.z);
    }
    pg.blendMode(BLEND);
    pg.popStyle();
  }
  
  public String getName() { return "Fireworks 3D"; }
}

