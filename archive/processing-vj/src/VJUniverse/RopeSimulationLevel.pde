class RopeSimulationLevel extends Level {
  PVector[] pts;
  PVector[] prev;
  int segments = 24;
  PVector anchor;
  
  public void reset() {
    pts = new PVector[segments];
    prev = new PVector[segments];
    anchor = new PVector(width/2, height/3);
    for (int i=0; i<segments; i++) {
      pts[i] = new PVector(anchor.x, anchor.y + i*14);
      prev[i] = pts[i].copy();
    }
  }
  
  public void update(float dt, float t, AudioEnvelope audio) {
    PVector gravity = new PVector(0, 0.8f);
    for (int i=1; i<segments; i++) {
      PVector cur = pts[i];
      PVector temp = cur.copy();
      PVector vel = PVector.sub(cur, prev[i]);
      vel.mult(0.99f);
      cur.add(vel);
      cur.add(PVector.mult(gravity, dt*60));
      prev[i] = temp;
    }
    pts[0].set(anchor.x + sin(t*0.8f)*40, anchor.y + cos(t*0.6f)*20);
    // constraints
    for (int k=0; k<4; k++) {
      for (int i=0; i<segments-1; i++) {
        PVector p1 = pts[i];
        PVector p2 = pts[i+1];
        float target = 14;
        PVector diff = PVector.sub(p2, p1);
        float d = diff.mag();
        float err = (d - target)/2;
        diff.normalize();
        p1.add(PVector.mult(diff, err));
        p2.sub(PVector.mult(diff, err));
        if (i==0) pts[0] = anchor.copy();
      }
    }
  }
  
  public void render(PGraphics pg) {
    pg.pushStyle();
    pg.background(10, 10, 18);
    pg.stroke(200, 220, 255);
    pg.strokeWeight(4);
    pg.noFill();
    pg.beginShape();
    for (int i=0; i<segments; i++) {
      pg.vertex(pts[i].x, pts[i].y);
    }
    pg.endShape();
    pg.popStyle();
  }
  
  public String getName() { return "Rope Simulation"; }
}
