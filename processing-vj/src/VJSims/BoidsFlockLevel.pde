class BoidsFlockLevel extends Level {
  class Boid {
    PVector p = new PVector();
    PVector v = new PVector();
  }
  ArrayList<Boid> boids = new ArrayList<Boid>();
  
  public void reset() {
    boids.clear();
    for (int i = 0; i < 180; i++) {
      Boid b = new Boid();
      b.p.set(random(-400, 400), random(-260, 260), random(-400, 200));
      PVector dir = PVector.random3D();
      dir.mult(random(60, 120));
      b.v.set(dir);
      boids.add(b);
    }
  }
  
  public void update(float dt, float t, AudioEnvelope audio) {
    float alignFactor = 0.08f;
    float cohFactor = 0.06f;
    float sepFactor = 0.14f;
    float maxSpeed = 180 + audio.getLevel() * 120;
    for (Boid b : boids) {
      PVector align = new PVector();
      PVector coh = new PVector();
      PVector sep = new PVector();
      int neigh = 0;
      for (Boid o : boids) {
        if (o == b) continue;
        float d = PVector.dist(b.p, o.p);
        if (d < 120) {
          align.add(o.v);
          coh.add(o.p);
          neigh++;
          if (d < 40) {
            PVector away = PVector.sub(b.p, o.p);
            away.normalize();
            away.div(max(d, 1));
            sep.add(away);
          }
        }
      }
      if (neigh > 0) {
        align.div(neigh);
        align.setMag(maxSpeed * 0.4f);
        align.sub(b.v);
        align.mult(alignFactor);
        
        coh.div(neigh);
        coh.sub(b.p);
        coh.setMag(50);
        coh.mult(cohFactor);
        
        sep.mult(sepFactor * 120);
      }
      b.v.add(align);
      b.v.add(coh);
      b.v.add(sep);
      b.v.limit(maxSpeed);
      b.p.add(PVector.mult(b.v, dt));
      
      // wrap
      float bounds = 500;
      if (b.p.x > bounds) b.p.x = -bounds;
      if (b.p.x < -bounds) b.p.x = bounds;
      if (b.p.y > bounds) b.p.y = -bounds;
      if (b.p.y < -bounds) b.p.y = bounds;
      if (b.p.z > bounds) b.p.z = -bounds;
      if (b.p.z < -bounds) b.p.z = bounds;
    }
  }
  
  public void render(PGraphics pg) {
    pg.pushStyle();
    pg.background(6, 8, 14);
    pg.lights();
    pg.translate(pg.width/2, pg.height/2, 0);
    pg.rotateY(time * 0.2f);
    pg.rotateX(sin(time * 0.3f) * 0.2f);
    pg.stroke(140, 220, 255, 160);
    pg.fill(40, 80, 120, 140);
    for (Boid b : boids) {
      pg.pushMatrix();
      pg.translate(b.p.x, b.p.y, b.p.z);
      PVector dir = b.v.copy();
      dir.normalize();
      float yaw = atan2(dir.x, dir.z);
      float pitch = asin(-dir.y);
      pg.rotateY(yaw);
      pg.rotateX(pitch);
      pg.beginShape(TRIANGLES);
      pg.vertex(0, 0, 18);
      pg.vertex(-6, -4, -10);
      pg.vertex(6, -4, -10);
      pg.vertex(0, 0, 18);
      pg.vertex(6, -4, -10);
      pg.vertex(0, 8, -8);
      pg.vertex(0, 0, 18);
      pg.vertex(0, 8, -8);
      pg.vertex(-6, -4, -10);
      pg.endShape();
      pg.popMatrix();
    }
    pg.popStyle();
  }
  
  public String getName() { return "Boids Flock"; }
}

